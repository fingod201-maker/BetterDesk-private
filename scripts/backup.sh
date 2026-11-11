#!/bin/bash
# =============================================================================
# BetterDesk Automated Backup
# Backs up: SQLite databases, auth.db, API key, SSL certs, nginx config.
#
# Cron (daily at 03:00):
#   0 3 * * * /opt/betterdesk/scripts/backup.sh >> /var/log/betterdesk/backup.log 2>&1
#
# Retention: keeps last 7 daily, 4 weekly, 1 monthly backups.
# =============================================================================
set -euo pipefail

BD_DIR="/opt/betterdesk"
BACKUP_ROOT="/backups/betterdesk"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=1

mkdir -p "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly" "$BACKUP_ROOT/monthly"

log() { echo "[$(date -Iseconds)] $*"; }

log "Starting BetterDesk backup ($TIMESTAMP)"

# --- Collect what exists ---
BACKUP_LIST=()
[[ -d "$BD_DIR/data" ]] && BACKUP_LIST+=("$BD_DIR/data")
[[ -d "$BD_DIR/web-nodejs/data" ]] && BACKUP_LIST+=("$BD_DIR/web-nodejs/data")
[[ -f "$BD_DIR/.env.ops" ]] && BACKUP_LIST+=("$BD_DIR/.env.ops")
[[ -d /etc/letsencrypt ]] && BACKUP_LIST+=("/etc/letsencrypt")
[[ -f /etc/nginx/nginx.conf ]] && BACKUP_LIST+=("/etc/nginx/nginx.conf")
[[ -f /etc/nginx/ssl-params.conf ]] && BACKUP_LIST+=("/etc/nginx/ssl-params.conf")

if [[ ${#BACKUP_LIST[@]} -eq 0 ]]; then
  log "WARNING: Nothing to backup — paths not found"
  exit 0
fi

ARCHIVE="$BACKUP_ROOT/daily/betterdesk-backup-$TIMESTAMP.tar.gz"
tar czf "$ARCHIVE" "${BACKUP_LIST[@]}" 2>/dev/null
log "Archive created: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# --- Retention: daily ---
find "$BACKUP_ROOT/daily" -name "betterdesk-backup-*.tar.gz" -mtime +$RETENTION_DAILY -delete 2>/dev/null || true

# --- Promote to weekly (Sunday) ---
if [[ $(date +%u) -eq 7 ]]; then
  cp "$ARCHIVE" "$BACKUP_ROOT/weekly/betterdesk-backup-weekly-$TIMESTAMP.tar.gz"
  find "$BACKUP_ROOT/weekly" -name "betterdesk-backup-weekly-*.tar.gz" -mtime +$((RETENTION_WEEKLY*7)) -delete 2>/dev/null || true
  log "Weekly backup promoted"
fi

# --- Promote to monthly (1st of month) ---
if [[ $(date +%d) -eq 01 ]]; then
  cp "$ARCHIVE" "$BACKUP_ROOT/monthly/betterdesk-backup-monthly-$TIMESTAMP.tar.gz"
  find "$BACKUP_ROOT/monthly" -name "betterdesk-backup-monthly-*.tar.gz" -mtime +$((RETENTION_MONTHLY*30)) -delete 2>/dev/null || true
  log "Monthly backup promoted"
fi

log "Backup complete"
