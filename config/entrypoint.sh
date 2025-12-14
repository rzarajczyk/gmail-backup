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

MAX_ACCOUNTS=5

# Arrays to store account information
ACCOUNT_USERS=()
ACCOUNT_PASSWORDS=()
RAINLOOP_PASSWORDS=()

# Discover configured accounts
discover_accounts() {
    log "Discovering configured accounts..."
    local account_count=0
    
    for i in {1..5}; do
        local user_var="GMAIL_USER_${i}"
        local pass_var="GMAIL_APP_PASSWORD_${i}"
        local rainloop_var="RAINLOOP_PASSWORD_${i}"
        
        local user="${!user_var}"
        local password="${!pass_var}"
        local rainloop_pass="${!rainloop_var}"
        
        if [ -n "$user" ] && [ -n "$password" ]; then
            account_count=$((account_count + 1))
            
            # Enforce MAX_ACCOUNTS limit
            if [ $account_count -gt $MAX_ACCOUNTS ]; then
                error "Too many accounts configured. Currently limited to $MAX_ACCOUNTS account(s). Found account $i: $user"
            fi
            
            ACCOUNT_USERS+=("$user")
            ACCOUNT_PASSWORDS+=("$password")
            
            # Use RAINLOOP_PASSWORD or fallback to GMAIL_APP_PASSWORD
            if [ -z "$rainloop_pass" ]; then
                warn "RAINLOOP_PASSWORD_${i} not set for $user, using GMAIL_APP_PASSWORD_${i}"
                RAINLOOP_PASSWORDS+=("$password")
            else
                RAINLOOP_PASSWORDS+=("$rainloop_pass")
            fi
            
            log "  Account ${i}: ${user}"
        elif [ -n "$user" ] || [ -n "$password" ]; then
            error "Incomplete configuration for account ${i}. Both GMAIL_USER_${i} and GMAIL_APP_PASSWORD_${i} are required."
        fi
    done
    
    if [ ${#ACCOUNT_USERS[@]} -eq 0 ]; then
        error "No accounts configured. At least GMAIL_USER_1 and GMAIL_APP_PASSWORD_1 are required."
    fi
    
    log "Found ${#ACCOUNT_USERS[@]} account(s)"
}

# Discover accounts
discover_accounts

log "Starting Gmail Backup Container"
log "Sync Interval: ${SYNC_INTERVAL:-3600}s"

# Create data directories if they don't exist
log "Setting up data directories..."

# Step 3: Create directories for all discovered accounts
for user in "${ACCOUNT_USERS[@]}"; do
    log "  Creating mail directory for: ${user}"
    mkdir -p "/data/mail/${user}"
done

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

def get_password_2():
    return os.environ.get('GMAIL_APP_PASSWORD_2', '')

def get_password_3():
    return os.environ.get('GMAIL_APP_PASSWORD_3', '')

def get_password_4():
    return os.environ.get('GMAIL_APP_PASSWORD_4', '')

def get_password_5():
    return os.environ.get('GMAIL_APP_PASSWORD_5', '')
PYEOF

# Create actual offlineimaprc from template with dynamic multi-account support
# Build comma-separated account list
ACCOUNT_LIST=""
for i in "${!ACCOUNT_USERS[@]}"; do
    if [ -n "$ACCOUNT_LIST" ]; then
        ACCOUNT_LIST="${ACCOUNT_LIST}, ${ACCOUNT_USERS[$i]}"
    else
        ACCOUNT_LIST="${ACCOUNT_USERS[$i]}"
    fi
done

log "Configuring OfflineIMAP for ${#ACCOUNT_USERS[@]} account(s)..."

cat > /data/offlineimap/.offlineimaprc << EOF
[general]
accounts = ${ACCOUNT_LIST}
maxsyncaccounts = ${#ACCOUNT_USERS[@]}
pythonfile = /etc/offlineimap/offlineimap_helper.py
metadata = /data/offlineimap
EOF

# Generate account sections dynamically
for i in "${!ACCOUNT_USERS[@]}"; do
    account_num=$((i + 1))
    user="${ACCOUNT_USERS[$i]}"
    log "  Creating OfflineIMAP config for ${user}"
    
    cat >> /data/offlineimap/.offlineimaprc << EOF

[Account ${user}]
localrepository = Local_${account_num}
remoterepository = Remote_${account_num}
synclabels = yes
labelsheader = X-Keywords

[Repository Local_${account_num}]
type = Maildir
localfolders = /data/mail/${user}
sync_deletes = no

[Repository Remote_${account_num}]
type = Gmail
remoteuser = ${user}
remotepasseval = get_password_${account_num}()
realdelete = no
readonly = True
ssl = yes
sslcacertfile = /etc/ssl/certs/ca-certificates.crt
maxconnections = 3
folderfilter = lambda folder: folder not in ['[Gmail]/All Mail', '[Gmail]/Important', '[Gmail]/Starred']
nametrans = lambda folder: folder.replace('[Gmail]/', '').replace(' ', '_')
EOF
done

chmod 600 /data/offlineimap/.offlineimaprc

# Configure Dovecot for multiple accounts
log "Configuring Dovecot for ${#ACCOUNT_USERS[@]} account(s)..."

# Create Dovecot passwd file for authentication with all accounts
mkdir -p /etc/dovecot/users
cat > /etc/dovecot/users/passwd << EOF
EOF

# Loop through all accounts and add to passwd file
for i in "${!ACCOUNT_USERS[@]}"; do
    user="${ACCOUNT_USERS[$i]}"
    password="${RAINLOOP_PASSWORDS[$i]}"
    log "  Added Dovecot user: ${user}"
    # Fixed: home directory should be /data/mail/${user} not /data/mail
    echo "${user}:{PLAIN}${password}:${DOVECOT_UID}:${DOVECOT_GID}::/data/mail/${user}::" >> /etc/dovecot/users/passwd
done

chmod 644 /etc/dovecot/users/passwd
chown dovecot:dovecot /etc/dovecot/users/passwd

# Update dovecot config to use passwd file with %u variable for multi-account
cat > /etc/dovecot/dovecot.conf << DOVEOF
# Dovecot configuration for Gmail backup

protocols = imap
listen = *
mail_location = maildir:/data/mail/%u:LAYOUT=fs:INBOX=/data/mail/%u/INBOX
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
  driver = passwd-file
  args = /etc/dovecot/users/passwd
  default_fields = uid=vmail gid=vmail
  override_fields = uid=vmail gid=vmail
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
if [ -L "/var/www/rainloop/data" ]; then
    log "  Rainloop data already configured (symlink exists)"
else
    log "  Setting up Rainloop persistent data..."
    mkdir -p /data/rainloop
    cp -r /var/www/rainloop/data /data/rainloop/
    rm -rf /var/www/rainloop/data
    ln -sf /data/rainloop/data /var/www/rainloop/data
    log "  Rainloop data copied to persistent storage"
fi

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
# This file will be used when users login with @gmail.com addresses
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
log "Configured accounts:"
for user in "${ACCOUNT_USERS[@]}"; do
    log "  - ${user}"
done
log "============================================"
log "Starting services..."

# Execute the main command and start services in background
exec "$@" &

# Wait for Dovecot to start
sleep 5

# Build FTS indexes for all accounts if not already built
log "Checking full-text search indexes..."
for user in "${ACCOUNT_USERS[@]}"; do
    if [ -d "/data/mail/${user}" ] && [ ! -d "/data/mail/${user}/xapian-indexes" ]; then
        log "Building full-text search indexes for ${user}..."
        doveadm fts rescan -u "${user}" 2>/dev/null || true
        doveadm index -u "${user}" '*' 2>/dev/null || true
    fi
done
log "Full-text search indexes ready"

# Wait for background process
wait

