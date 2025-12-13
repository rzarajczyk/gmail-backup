# Gmail Backup Container

Searchable Gmail backup with OfflineIMAP, Dovecot and Rainloop web interface.

## Features

- **OfflineIMAP**: Periodically syncs emails from Gmail
- **Dovecot**: Local IMAP server with Xapian full-text search indexing
- **Rainloop**: Modern web interface for reading and searching emails
- **Multi-account support**: Backup up to 5 Gmail accounts simultaneously ✨ **NEW**
- **Persistent storage**: All data stored in `/data` volume

## Prerequisites

1. **Gmail App Password**: You need to create an App Password for your Gmail account:
   - Go to [Google Account Security](https://myaccount.google.com/security)
   - Enable 2-Step Verification if not already enabled
   - Go to [App Passwords](https://myaccount.google.com/apppasswords)
   - Generate a new app password for "Mail"
   - Save this password - you'll need it for the container

## Quick Start

### Using Docker Compose (Recommended)

1. Create a `.env` file:
```bash
GMAIL_USER_1=your.email@gmail.com
GMAIL_APP_PASSWORD_1=your-app-password
RAINLOOP_PASSWORD_1=your-secure-password
```

2. Start the container:

**Development mode** (with local build):
```bash
docker-compose -f docker-compose.dev.yml up --build -d
```

**Production mode** (using pre-built image):
```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Using Docker Run

```bash
docker run -d \
  --name gmail-backup \
  -e GMAIL_USER_1=your.email@gmail.com \
  -e GMAIL_APP_PASSWORD_1=your-app-password \
  -e RAINLOOP_PASSWORD_1=your-secure-password \
  -p 8080:8080 \
  -v gmail_data:/data \
  gmail-backup
```

## Environment Variables

| Variable                 | Required | Default                          | Description                                                 |
|--------------------------|----------|----------------------------------|-------------------------------------------------------------|
| `GMAIL_USER_1`           | **Yes**  | -                                | Gmail address for account 1                                 |
| `GMAIL_APP_PASSWORD_1`   | **Yes**  | -                                | Gmail App Password for account 1                            |
| `RAINLOOP_PASSWORD_1`    | No       | Same as `GMAIL_APP_PASSWORD_1`   | Rainloop login password for account 1                       |
| `GMAIL_USER_2`           | No       | -                                | Gmail address for account 2 (optional)                      |
| `GMAIL_APP_PASSWORD_2`   | No       | -                                | Gmail App Password for account 2 (optional)                 |
| `RAINLOOP_PASSWORD_2`    | No       | Same as `GMAIL_APP_PASSWORD_2`   | Rainloop login password for account 2 (optional)            |
| `GMAIL_USER_3..5`        | No       | -                                | Additional accounts (3, 4, 5) - same pattern as above       |
| `SYNC_INTERVAL`          | No       | `3600`                           | Sync interval in seconds (default: 1 hour)                  |

**Note**: Up to 5 Gmail accounts can be configured simultaneously. Each account requires both `GMAIL_USER_N` and `GMAIL_APP_PASSWORD_N` to be set.

## Multi-Account Configuration ✨

The container supports up to 5 Gmail accounts simultaneously.

### Multi-Account Setup Example

```bash
# Account 1 (Required)
GMAIL_USER_1=first.account@gmail.com
GMAIL_APP_PASSWORD_1=first-app-password
RAINLOOP_PASSWORD_1=first-secure-password

# Account 2 (Optional)
GMAIL_USER_2=second.account@gmail.com
GMAIL_APP_PASSWORD_2=second-app-password
RAINLOOP_PASSWORD_2=second-secure-password

# Accounts 3-5 follow the same pattern
```

### How Multi-Account Works

- Each account syncs independently via OfflineIMAP
- Mail stored in separate directories: `/data/mail/<email>`
- Each account has its own Rainloop login
- Full-text search indexes maintained per account
- All accounts share the same sync interval

## Accessing the Web Interface

1. Open your browser and go to: `http://localhost:8080`
2. Login with:
   - **Email**: Your full Gmail address (e.g., `your.email@gmail.com`)
   - **Password**: Your `RAINLOOP_PASSWORD_1` (or Gmail App Password if `RAINLOOP_PASSWORD_1` is not set)

**Note**: The Gmail App Password is only used by OfflineIMAP to download emails from Gmail. You should set a separate `RAINLOOP_PASSWORD_1` for logging into the Rainloop web interface.

### Multi-Account Login

With multiple accounts configured, login with any account:
- Use the corresponding email address
- Use the corresponding `RAINLOOP_PASSWORD_N` for that account

### Rainloop Admin Panel

To configure Rainloop settings:
1. Go to: `http://localhost:8080/?admin`
2. Default credentials: `admin` / `12345`
3. **Important**: Change the admin password immediately!

## Full-Text Search

The container uses Dovecot's Xapian FTS plugin for full-text search:
- Emails are automatically indexed after sync
- Search in Rainloop will search through email content, not just headers
- Initial indexing may take some time for large mailboxes

## Data Persistence

All data is stored in `/data`:
- `/data/mail/<email>` - Downloaded emails per account (Maildir format)
- `/data/rainloop` - Rainloop configuration and cache (shared)
- `/data/offlineimap` - OfflineIMAP state and configuration (shared)
- `/data/dovecot` - Dovecot indexes

### Multi-Account Data Structure

```
/data/
├── mail/
│   ├── first.account@gmail.com/
│   │   ├── INBOX/
│   │   ├── Sent/
│   │   └── xapian-indexes/
│   └── second.account@gmail.com/
│       ├── INBOX/
│       └── ...
├── rainloop/ (shared)
├── offlineimap/ (shared)
└── dovecot/ (shared)
```

## Building the Image

```bash
docker build -t gmail-backup .
```

## Logs and Debugging

View sync logs:
```bash
docker logs -f gmail-backup
```

Access container shell:
```bash
docker exec -it gmail-backup bash
```

Check OfflineIMAP status:
```bash
docker exec gmail-backup cat /var/log/supervisor/offlineimap.log
```

Manually trigger sync:
```bash
docker exec gmail-backup offlineimap -c /data/offlineimap/.offlineimaprc
```

Rebuild search index:
```bash
docker exec gmail-backup doveadm fts rescan -u your.email@gmail.com
docker exec gmail-backup doveadm index -u your.email@gmail.com '*'
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 8080 | Rainloop | Web interface |
| 143 | IMAP | Local IMAP server (optional, for external clients) |

## Security Considerations

- The container stores credentials in configuration files - keep the volume secure
- IMAP is unencrypted (plain) - only use within trusted networks or localhost
- Change Rainloop admin password immediately after first login
- Consider using Docker secrets for credentials in production

## Troubleshooting

### Sync not working
- Verify your App Password is correct
- Check if "Less secure app access" or App Passwords are enabled
- View logs: `docker logs gmail-backup`

### Can't login to Rainloop
- Make sure you're using the same email and App Password
- Check that Dovecot is running: `docker exec gmail-backup pgrep dovecot`

### Search not working
- Wait for initial indexing to complete after first sync
- Manually trigger reindex (see above)
- Check Dovecot logs for FTS errors

### Multi-Account Issues

**Account not syncing**
- Verify both `GMAIL_USER_N` and `GMAIL_APP_PASSWORD_N` are set
- Check logs for specific account errors: `docker logs gmail-backup`
- Each account requires its own App Password from Google

**Can't login with second account**
- Ensure `RAINLOOP_PASSWORD_N` is set (or it defaults to `GMAIL_APP_PASSWORD_N`)
- Check Dovecot passwd file: `docker exec gmail-backup cat /etc/dovecot/users/passwd`

**Too many accounts error**
- Maximum 5 accounts supported
- Remove extra account variables from `.env` file if you have more than 5

**Duplicate username error**
- Each account must have a unique email address
- Cannot configure the same Gmail account twice

## License

MIT

