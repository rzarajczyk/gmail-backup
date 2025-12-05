#!/bin/bash

# Mail synchronization script using OfflineIMAP
# Runs periodically based on SYNC_INTERVAL

set -e

SYNC_INTERVAL=${SYNC_INTERVAL:-300}
OFFLINEIMAP_CONFIG="/data/offlineimap/.offlineimaprc"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for initial setup
sleep 10

log "Starting mail sync service (interval: ${SYNC_INTERVAL}s)"

while true; do
    log "Starting mail synchronization..."

    if [ -f "$OFFLINEIMAP_CONFIG" ]; then
        if offlineimap -c "$OFFLINEIMAP_CONFIG" -u quiet; then
            log "Mail sync completed successfully"

            # Trigger FTS index update after sync
            if command -v doveadm &> /dev/null; then
                log "Updating full-text search index..."
                doveadm fts rescan -u "${GMAIL_USER}" 2>/dev/null || true
                doveadm index -u "${GMAIL_USER}" '*' 2>/dev/null || true
                log "FTS index update completed"
            fi
        else
            log "Mail sync failed, will retry in ${SYNC_INTERVAL}s"
        fi
    else
        log "OfflineIMAP config not found at $OFFLINEIMAP_CONFIG"
    fi

    log "Sleeping for ${SYNC_INTERVAL}s..."
    sleep "$SYNC_INTERVAL"
done

