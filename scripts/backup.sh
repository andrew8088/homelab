#!/bin/bash

set -euo pipefail

# Accept BACKUP_BASE as first argument, default to /mnt/backup
BACKUP_BASE="${1:-/mnt/backup}"

# Show usage if help requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [BACKUP_BASE]"
    echo "  BACKUP_BASE: Directory where backups will be stored (default: /mnt/backup)"
    echo "  Example: $0 /mnt/external-drive/backups"
    exit 0
fi

LOGFILE="/var/log/homelab-backup.log"
LOCK_FILE="/var/run/homelab-backup.lock"
RETENTION_DAYS=7

# Lock handling with proper cleanup
cleanup() {
    local exit_code=$?
    if [[ -n "${LOCK_FD:-}" ]]; then
        flock -u "$LOCK_FD"
        exec {LOCK_FD}>&-
    fi
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
    exit $exit_code
}

trap cleanup EXIT INT TERM

exec {LOCK_FD}>"$LOCK_FILE"

if ! flock -n "$LOCK_FD"; then
    echo "$(date): Backup already running (PID: $(cat "$LOCK_FILE" 2>/dev/null || echo 'unknown'))" >> "$LOGFILE"
    exit 1
fi

# Write our PID to lockfile for debugging
echo $$ > "$LOCK_FILE"

# Logging function
log() {
    echo "$(date): $*" | tee "$LOGFILE"
}

log "Starting hardlinked backup..."

# Generate backup directory name
DATE=$(date +%Y-%m-%d-%H-%M-%S)
LATEST_LINK="$BACKUP_BASE/latest"
CURRENT_BACKUP="$BACKUP_BASE/backup-$DATE"

# Create backup base directory if it doesn't exist
mkdir -p "$BACKUP_BASE"

# Build rsync command with optional hardlink destination
RSYNC_CMD=(
    rsync -avHAXS --numeric-ids --delete
    --exclude='lost+found'
    --exclude='.tmp*'
    --log-file="$LOGFILE"
)

# Add hardlink destination if previous backup exists
if [[ -L "$LATEST_LINK" && -d "$LATEST_LINK" ]]; then
    RSYNC_CMD+=(--link-dest="$LATEST_LINK")
    log "Using hardlinks from: $(readlink "$LATEST_LINK")"
else
    log "No previous backup found, creating full copy"
fi

# Add source and destination
RSYNC_CMD+=(/mnt/primary/k3s-storage "$CURRENT_BACKUP/")

# Execute backup
START_TIME=$SECONDS
log "Executing: ${RSYNC_CMD[*]}"

if "${RSYNC_CMD[@]}"; then
    DURATION=$((SECONDS - START_TIME))
    BACKUP_SIZE=$(du -sh "$CURRENT_BACKUP" | cut -f1)
    
    # Update latest symlink atomically
    TEMP_LINK="$BACKUP_BASE/.latest-$$"
    ln -s "backup-$DATE" "$TEMP_LINK"
    mv "$TEMP_LINK" "$LATEST_LINK"
    
    log "Backup completed successfully in ${DURATION}s, size: $BACKUP_SIZE"
    
    # Cleanup old backups
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    OLD_BACKUPS=$(find "$BACKUP_BASE" -maxdepth 1 -name "backup-*" -type d -mtime +$RETENTION_DAYS)
    
    if [[ -n "$OLD_BACKUPS" ]]; then
        echo "$OLD_BACKUPS" | while IFS= read -r old_backup; do
            log "Removing old backup: $(basename "$old_backup")"
            rm -rf "$old_backup"
        done
    else
        log "No old backups to clean up"
    fi
    
    # Show current backup inventory
    log "Current backups:"
    find "$BACKUP_BASE" -maxdepth 1 -name "backup-*" -type d | sort >> "$LOGFILE"
    
else
    log "ERROR: Backup failed with exit code $?"
    exit 1
fi

log "Backup process completed successfully"
