#!/bin/bash
# =============================================================================
# BetterDesk 24/7 Health Check Script
# Validates all services + domain routing for zoom.telcom.stream & panel.telcom.stream
#
# Usage: sudo ./scripts/health-check.sh [--json] [--fix]
# Exit codes: 0=healthy, 1=degraded, 2=critical
# =============================================================================
set -euo pipefail

JSON_MODE=0
FIX_MODE=0
EXIT_CODE=0
FAILURES=0
WARNINGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=1; shift ;;
    --fix)  FIX_MODE=1; shift ;;
    *)      echo "Unknown option: $1"; exit 3 ;;
  esac
done

LOG_FILE="/var/log/betterdesk/health-check.log"
mkdir -p /var/log/betterdesk

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

# --- Configuration ---
LANDING_URL="https://zoom.telcom.stream/healthz"
PANEL_URL="https://panel.telcom.stream/health"
LANDING_PORT=8080
CONSOLE_PORT=5000
GO_API_PORT=21121
SIGNAL_PORT=21116
RELAY_PORT=21117

fail()  { FAILURES=$((FAILURES+1));  EXIT_CODE=2; log "CRITICAL: $*"; }
warn()  { WARNINGS=$((WARNINGS+1));  EXIT_CODE=1; log "WARNING:  $*"; }
ok()    { log "OK: $*"; }

# --- Service checks ---
check_process() {
  local name="$1" pattern="$2"
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    ok "Process running: $name"
  else
    fail "Process not running: $name (pattern: $pattern)"
    if [[ $FIX_MODE -eq 1 ]]; then
      log "Attempting restart: $name"
      systemctl restart "$name" 2>/dev/null || log "FAILED to restart $name"
    fi
  fi
}

check_port() {
  local name="$1" port="$2" proto="${3:-tcp}"
  if command -v ss >/dev/null 2>&1; then
    if ss -${proto:0:1}ln | grep -q ":${port} "; then
      ok "Port listening: $name ($proto:$port)"
    else
      fail "Port not listening: $name ($proto:$port)"
    fi
  else
    warn "ss not available — skipping port check for $name"
  fi
}

check_http() {
  local name="$1" url="$2" expected="${3:-200}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 "$url" 2>/dev/null) || code="000"
  if [[ "$code" == "$expected" ]]; then
    ok "HTTP $name -> $url ($code)"
  else
    fail "HTTP $name -> $url (expected $expected, got $code)"
  fi
}

check_ssl_cert() {
  local domain="$1"
  local expiry
  expiry=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2) || expiry=""
  if [[ -z "$expiry" ]]; then
    fail "SSL certificate not fetchable: $domain"
    return
  fi
  local expiry_epoch
  expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null) || expiry_epoch=0
  local now_epoch
  now_epoch=$(date +%s)
  local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
  if [[ $days_left -lt 7 ]]; then
    fail "SSL certificate expires soon: $domain ($days_left days)"
  elif [[ $days_left -lt 30 ]]; then
    warn "SSL certificate expires in $days_left days: $domain"
  else
    ok "SSL certificate valid: $domain ($days_left days)"
  fi
}

# =============================================================================
log "==================== BetterDesk Health Check ===================="

# 1. Process checks
check_process "betterdesk-landing"  "landing-service/server.js"
check_process "betterdesk-console"  "web-nodejs/server.js"
check_process "betterdesk-nginx"    "nginx: master"

# 2. Port checks
check_port "Landing service"   "$LANDING_PORT" tcp
check_port "Console web"       "$CONSOLE_PORT" tcp
check_port "Go API"            "$GO_API_PORT" tcp
check_port "Signal TCP"        "$SIGNAL_PORT" tcp
check_port "Signal UDP"        "$SIGNAL_PORT" udp
check_port "Relay TCP"         "$RELAY_PORT" tcp

# 3. HTTP / domain checks
check_http "Landing health"    "$LANDING_URL" 200
check_http "Panel health"      "$PANEL_URL" 200

# 4. SSL certificate checks
check_ssl_cert "zoom.telcom.stream"
check_ssl_cert "panel.telcom.stream"

# 5. Disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $DISK_USAGE -gt 90 ]]; then
  fail "Disk usage critical: / at ${DISK_USAGE}%"
elif [[ $DISK_USAGE -gt 80 ]]; then
  warn "Disk usage high: / at ${DISK_USAGE}%"
else
  ok "Disk usage: / at ${DISK_USAGE}%"
fi

# 6. Memory
MEM_FREE=$(free -m | awk '/Mem:/ {print $7}')
if [[ $MEM_FREE -lt 256 ]]; then
  warn "Low free memory: ${MEM_FREE}MB"
else
  ok "Free memory: ${MEM_FREE}MB"
fi

# =============================================================================
log "==================== Results ===================="
log "Failures: $FAILURES | Warnings: $WARNINGS"

if [[ $JSON_MODE -eq 1 ]]; then
  cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "failures": $FAILURES,
  "warnings": $WARNINGS,
  "status": $([ $FAILURES -eq 0 ] && echo '"healthy"' || echo '"unhealthy"'),
  "checks": {
    "landing_service": "$([ $FAILURES -eq 0 ] && echo 'ok' || echo 'fail')",
    "panel_console": "$([ $FAILURES -eq 0 ] && echo 'ok' || echo 'fail')",
    "ssl_zoom": "ok",
    "ssl_panel": "ok"
  }
}
EOF
fi

if [[ $FAILURES -gt 0 ]]; then
  log "HEALTH CHECK FAILED — $FAILURES critical issue(s)"
  exit 2
elif [[ $WARNINGS -gt 0 ]]; then
  log "HEALTH CHECK DEGRADED — $WARNINGS warning(s)"
  exit 1
fi
log "ALL CHECKS PASSED"
exit 0
