#!/bin/bash

# Mail synchronization script using OfflineIMAP
# Runs periodically based on SYNC_INTERVAL

set -e

SYNC_INTERVAL=${SYNC_INTERVAL:-3600}
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

            # Step 5: Trigger FTS index update after sync for all accounts
            if command -v doveadm &> /dev/null; then
                log "Updating full-text search indexes..."
                # Loop through all configured accounts (1-5)
                for i in {1..5}; do
                    user_var="GMAIL_USER_${i}"
                    user="${!user_var}"
                    if [ -n "$user" ]; then
                        log "  Updating FTS index for ${user}..."
                        doveadm fts rescan -u "${user}" 2>/dev/null || true
                        doveadm index -u "${user}" '*' 2>/dev/null || true
                    fi
                done
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

