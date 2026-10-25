#!/bin/bash
# =============================================================================
# BetterDesk Deployment Readiness Validator
# Runs pre-deployment checks to catch config errors before going live.
# =============================================================================
set -euo pipefail

ERRORS=0
WARN=0

err() { echo "ERROR: $*" >&2; ERRORS=$((ERRORS+1)); }
warn() { echo "WARN:  $*"; WARN=$((WARN+1)); }
ok()   { echo "OK:    $*"; }

echo "=== BetterDesk Pre-Deployment Validation ==="
echo ""

# --- Env file ---
if [[ ! -f .env.ops ]]; then
  err ".env.ops not found — copy .env.ops.example and fill in values"
else
  ok ".env.ops exists"
  source .env.ops
  if [[ -z "${SESSION_SECRET:-}" || ${#SESSION_SECRET} -lt 32 ]]; then
    err "SESSION_SECRET must be 32+ hex chars in .env.ops"
  else
    ok "SESSION_SECRET length OK"
  fi
  if [[ "${RELAY_PUBLIC_IP:-}" == "YOUR.PUBLIC.IP" || -z "${RELAY_PUBLIC_IP:-}" ]]; then
    err "RELAY_PUBLIC_IP must be set to the server's public IP"
  else
    ok "RELAY_PUBLIC_IP=$RELAY_PUBLIC_IP"
  fi
  if [[ "${CERTBOT_EMAIL:-}" == "admin@telcom.stream" ]]; then
    warn "CERTBOT_EMAIL is default — change to a real admin email"
  else
    ok "CERTBOT_EMAIL=$CERTBOT_EMAIL"
  fi
fi

# --- Docker compose config ---
if command -v docker compose &>/dev/null; then
  if docker compose -f docker-compose.ops.yml config >/dev/null 2>&1; then
    ok "docker-compose.ops.yml is valid"
  else
    err "docker-compose.ops.yml has syntax errors"
  fi
else
  warn "docker not available — skipping compose validation"
fi

# --- Nginx config ---
if command -v nginx &>/dev/null; then
  if nginx -t -c "$(pwd)/nginx.conf" 2>&1 | grep -q "successful"; then
    ok "nginx.conf syntax valid"
  else
    err "nginx.conf has syntax errors"
  fi
else
  warn "nginx not available — skipping nginx syntax check"
fi

# --- Scripts executable ---
for s in scripts/health-check.sh scripts/uptime-monitor.sh scripts/ssl-setup.sh scripts/backup.sh scripts/dns-check.sh scripts/deploy-24x7.sh; do
  if [[ -x "$s" ]]; then
    ok "$s is executable"
  else
    warn "$s is not executable — run chmod +x $s"
  fi
done

# --- Port conflict quick scan ---
if command -v ss &>/dev/null; then
  for port in 80 443 5000 8080 21115 21116 21117 21118 21119 21121; do
    if ss -tln | grep -q ":${port} "; then
      err "Port $port is already in use — conflict!"
    else
      ok "Port $port is free"
    fi
  done
  for port in 21116; do
    if ss -uln | grep -q ":${port} "; then
      err "UDP Port $port is already in use — conflict!"
    else
      ok "UDP Port $port is free"
    fi
  done
else
  warn "ss not available — skipping port conflict scan"
fi

echo ""
echo "=== Summary: $ERRORS error(s), $WARN warning(s) ==="
if [[ $ERRORS -gt 0 ]]; then
  echo "Fix errors before deploying."
  exit 1
fi
echo "Ready to deploy."
