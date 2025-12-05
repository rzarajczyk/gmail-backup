# Gmail Backup Container

Searchable Gmail backup with OfflineIMAP, Dovecot and Rainloop web interface.

## Features

- **OfflineIMAP**: Periodically syncs emails from Gmail
- **Dovecot**: Local IMAP server with Xapian full-text search indexing
- **Rainloop**: Modern web interface for reading and searching emails
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
GMAIL_USER=your.email@gmail.com
GMAIL_APP_PASSWORD=your-app-password
```

2. Start the container:
```bash
docker-compose up -d
```

### Using Docker Run

```bash
docker run -d \
  --name gmail-backup \
  -e GMAIL_USER=your.email@gmail.com \
  -e GMAIL_APP_PASSWORD=your-app-password \
  -p 8080:8080 \
  -v gmail_data:/data \
  gmail-backup
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GMAIL_USER` | **Yes** | - | Your Gmail address |
| `GMAIL_APP_PASSWORD` | **Yes** | - | Gmail App Password |
| `SYNC_INTERVAL` | No | `300` | Sync interval in seconds (default: 5 minutes) |
| `RAINLOOP_PORT` | No | `8080` | Web UI port |
| `DOVECOT_UID` | No | `1000` | UID for mail storage |
| `DOVECOT_GID` | No | `1000` | GID for mail storage |

## Accessing the Web Interface

1. Open your browser and go to: `http://localhost:8080`
2. Login with your Gmail credentials:
   - **Email**: Your full Gmail address (e.g., `your.email@gmail.com`)
   - **Password**: Your Gmail App Password

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
- `/data/mail` - Downloaded emails (Maildir format)
- `/data/rainloop` - Rainloop configuration and cache
- `/data/offlineimap` - OfflineIMAP state and configuration
- `/data/dovecot` - Dovecot indexes

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

## License

MIT

