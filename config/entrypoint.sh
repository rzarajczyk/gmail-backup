#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[ENTRYPOINT]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check required environment variables
if [ -z "$GMAIL_USER_1" ]; then
    error "GMAIL_USER_1 environment variable is required"
fi

if [ -z "$GMAIL_APP_PASSWORD_1" ]; then
    error "GMAIL_APP_PASSWORD_1 environment variable is required"
fi

if [ -z "$RAINLOOP_PASSWORD_1" ]; then
    warn "RAINLOOP_PASSWORD_1 not set, using GMAIL_APP_PASSWORD_1 for Rainloop login"
    RAINLOOP_PASSWORD_1="$GMAIL_APP_PASSWORD_1"
fi

log "Starting Gmail Backup Container"
log "Gmail User: $GMAIL_USER_1"
log "Sync Interval: ${SYNC_INTERVAL:-3600}s"

# Create data directories if they don't exist
log "Setting up data directories..."
mkdir -p "/data/mail/${GMAIL_USER_1}"
mkdir -p /data/rainloop
mkdir -p /data/dovecot
mkdir -p /data/offlineimap
mkdir -p /var/log/dovecot
mkdir -p /var/log/nginx
mkdir -p /var/log/supervisor

# Set up OfflineIMAP configuration
log "Configuring OfflineIMAP..."
mkdir -p /etc/offlineimap

# Create offlineimap helper script for password
cat > /etc/offlineimap/offlineimap_helper.py << 'PYEOF'
import os

def get_password_1():
    return os.environ.get('GMAIL_APP_PASSWORD_1', '')
PYEOF

# Create actual offlineimaprc from template
cat > /data/offlineimap/.offlineimaprc << EOF
[general]
accounts = ${GMAIL_USER_1}
maxsyncaccounts = 1
pythonfile = /etc/offlineimap/offlineimap_helper.py
metadata = /data/offlineimap

[Account ${GMAIL_USER_1}]
localrepository = Local
remoterepository = Remote
synclabels = yes
labelsheader = X-Keywords

[Repository Local]
type = Maildir
localfolders = /data/mail/${GMAIL_USER_1}
sync_deletes = no

[Repository Remote]
type = Gmail
remoteuser = ${GMAIL_USER_1}
remotepasseval = get_password_1()
realdelete = no
ssl = yes
sslcacertfile = /etc/ssl/certs/ca-certificates.crt
maxconnections = 3
folderfilter = lambda folder: folder not in ['[Gmail]/All Mail', '[Gmail]/Important', '[Gmail]/Starred']
nametrans = lambda folder: folder.replace('[Gmail]/', '').replace(' ', '_')
EOF

chmod 600 /data/offlineimap/.offlineimaprc

# Configure Dovecot password
log "Configuring Dovecot..."
export DOVECOT_PASSWORD="${RAINLOOP_PASSWORD_1}"

# Create Dovecot passwd file for authentication
mkdir -p /etc/dovecot/users
cat > /etc/dovecot/users/passwd << EOF
${GMAIL_USER_1}:{PLAIN}${RAINLOOP_PASSWORD_1}:${DOVECOT_UID}:${DOVECOT_GID}::/data/mail::
EOF
chmod 644 /etc/dovecot/users/passwd
chown dovecot:dovecot /etc/dovecot/users/passwd

# Update dovecot config to use passwd file
cat > /etc/dovecot/dovecot.conf << DOVEOF
# Dovecot configuration for Gmail backup

protocols = imap
listen = *
mail_location = maildir:/data/mail/${GMAIL_USER_1}:LAYOUT=fs:INBOX=/data/mail/${GMAIL_USER_1}/INBOX
mail_uid = vmail
mail_gid = vmail
ssl = no
disable_plaintext_auth = no
auth_mechanisms = plain login

passdb {
  driver = passwd-file
  args = /etc/dovecot/users/passwd
}

userdb {
  driver = static
  args = uid=vmail gid=vmail home=/data/mail
}

log_path = /var/log/dovecot/dovecot.log
info_log_path = /var/log/dovecot/info.log

protocol imap {
  mail_max_userip_connections = 20
  imap_idle_notify_interval = 2 mins
}

mail_plugins = $mail_plugins fts fts_xapian

plugin {
  fts = xapian
  fts_xapian = partial=3 full=20 verbose=0
  fts_autoindex = yes
  fts_autoindex_max_recent_msgs = 100
  fts_enforced = yes
}

service imap-login {
  inet_listener imap {
    port = 143
    address = *
  }
}

service auth {
  unix_listener auth-userdb {
    mode = 0666
    user = vmail
    group = vmail
  }
}

namespace inbox {
  inbox = yes
  separator = /

  mailbox Drafts {
    auto = subscribe
    special_use = \Drafts
  }
  mailbox Sent {
    auto = subscribe
    special_use = \Sent
  }
  mailbox Sent_Mail {
    auto = subscribe
    special_use = \Sent
  }
  mailbox Trash {
    auto = subscribe
    special_use = \Trash
  }
  mailbox Spam {
    auto = subscribe
    special_use = \Junk
  }
}

first_valid_uid = 1000
DOVEOF

# Set up Rainloop with persistent data
log "Configuring Rainloop..."
if [ ! -d "/data/rainloop/data" ]; then
    cp -r /var/www/rainloop/data /data/rainloop/
fi
rm -rf /var/www/rainloop/data
ln -sf /data/rainloop/data /var/www/rainloop/data

# Configure Rainloop domains for local IMAP
mkdir -p /data/rainloop/data/_data_/_default_/domains

# Create localhost.ini
cat > /data/rainloop/data/_data_/_default_/domains/localhost.ini << EOF
imap_host = "127.0.0.1"
imap_port = 143
imap_secure = "None"
imap_short_login = Off
sieve_use = Off
sieve_allow_raw = Off
sieve_host = ""
sieve_port = 4190
sieve_secure = "None"
smtp_host = ""
smtp_port = 25
smtp_secure = "None"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
white_list = ""
EOF

# Create gmail.com.ini pointing to local Dovecot
cat > /data/rainloop/data/_data_/_default_/domains/gmail.com.ini << EOF
imap_host = "127.0.0.1"
imap_port = 143
imap_secure = "None"
imap_short_login = Off
sieve_use = Off
sieve_allow_raw = Off
sieve_host = ""
sieve_port = 4190
sieve_secure = "None"
smtp_host = ""
smtp_port = 25
smtp_secure = "None"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
white_list = ""
EOF

# Set proper ownership
log "Setting file permissions..."
chown -R vmail:vmail /data/mail
chown -R www-data:www-data /data/rainloop
chown -R vmail:vmail /data/offlineimap
chmod -R 700 /data/mail
chmod 600 /data/offlineimap/.offlineimaprc

# Start PHP-FPM socket directory
mkdir -p /run/php
chown www-data:www-data /run/php

log "Configuration complete!"
log "============================================"
log "Rainloop Web UI: http://localhost:${RAINLOOP_PORT:-8080}"
log "Rainloop Admin: http://localhost:${RAINLOOP_PORT:-8080}/?admin"
log "Default admin login: admin / 12345"
log "IMAP Server: localhost:143"
log "Login with: ${GMAIL_USER_1}"
log "============================================"
log "Starting services..."

# Execute the main command and start services in background
exec "$@" &

# Wait for Dovecot to start
sleep 5

# Build FTS indexes for existing emails if not already built
if [ -d "/data/mail/${GMAIL_USER_1}" ] && [ ! -d "/data/mail/${GMAIL_USER_1}/xapian-indexes" ]; then
    log "Building full-text search indexes for existing emails..."
    doveadm fts rescan -u "${GMAIL_USER_1}" 2>/dev/null || true
    doveadm index -u "${GMAIL_USER_1}" '*' 2>/dev/null || true
    log "Full-text search indexes built successfully"
fi

# Wait for background process
wait

