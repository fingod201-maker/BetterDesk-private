#!/bin/bash
# =============================================================================
# BetterDesk 24/7 Uptime Monitor
# Monitors both domains and restarts failed services automatically.
# Intended to run via cron every minute.
#
# Cron: * * * * * /opt/betterdesk/scripts/uptime-monitor.sh >> /var/log/betterdesk/uptime.log 2>&1
# =============================================================================
set -euo pipefail

LOG_FILE="/var/log/betterdesk/uptime-monitor.log"
mkdir -p /var/log/betterdesk

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

# --- Config ---
LANDING_URL="https://zoom.telcom.stream/healthz"
PANEL_URL="https://panel.telcom.stream/health"
ALERT_EMAIL="${ALERT_EMAIL:-admin@telcom.stream}"

check_and_restart() {
  local service="$1"
  local url="$2"

  if curl -sf --max-time 10 --connect-timeout 5 "$url" >/dev/null 2>&1; then
    log "UP: $service ($url)"
    return 0
  fi

  log "DOWN: $service ($url) — attempting restart"
  systemctl restart "$service" 2>/dev/null || true
  sleep 5

  if curl -sf --max-time 10 --connect-timeout 5 "$url" >/dev/null 2>&1; then
    log "RECOVERED: $service after restart"
  else
    log "CRITICAL: $service still down after restart — sending alert"
    if command -v mail >/dev/null 2>&1; then
      echo "BetterDesk $service is DOWN on $(hostname) at $(date)" | mail -s "ALERT: $service DOWN" "$ALERT_EMAIL" 2>/dev/null || true
    fi
  fi
}

check_and_restart "betterdesk-landing"  "$LANDING_URL"
check_and_restart "betterdesk-console"  "$PANEL_URL"

# Also verify nginx is running
if ! systemctl is-active --quiet betterdesk-nginx 2>/dev/null; then
  log "CRITICAL: nginx is down — restarting"
  systemctl restart betterdesk-nginx 2>/dev/null || true
fi

log "Uptime monitor cycle complete"
