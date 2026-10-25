#!/bin/bash
# =============================================================================
# BetterDesk 24/7 Production Deployment Script
# Sets up zoom.telcom.stream (landing) + panel.telcom.stream (admin console)
# with SSL, auto-restart, health checks, and zero port conflicts.
#
# Modes:
#   docker  — Docker Compose stack (recommended)
#   bare    — Bare metal with systemd + nginx + certbot
#
# Prerequisites:
#   - Domains zoom.telcom.stream & panel.telcom.stream point to this server
#   - Ports 80, 443, 5000, 8080, 21114-21121 open inbound
#   - CERTBOT_EMAIL, RELAY_PUBLIC_IP, SESSION_SECRET exported
# =============================================================================
set -euo pipefail

BD_DIR="/opt/betterdesk"
MODE="${1:-docker}"

fail() { echo "ERROR: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# --- Validate prerequisites ---
if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
  fail "CERTBOT_EMAIL not set (export CERTBOT_EMAIL=admin@telcom.stream)"
fi
if [[ -z "${RELAY_PUBLIC_IP:-}" ]]; then
  fail "RELAY_PUBLIC_IP not set (export RELAY_PUBLIC_IP=1.2.3.4)"
fi
if [[ -z "${SESSION_SECRET:-}" ]]; then
  SESSION_SECRET=$(openssl rand -hex 32)
  export SESSION_SECRET
  warn "SESSION_SECRET auto-generated: $SESSION_SECRET"
fi

echo "============================================================"
echo " BetterDesk 24/7 Production Deployment"
echo " Domains: zoom.telcom.stream -> landing"
echo "          panel.telcom.stream -> admin console"
echo " Mode: $MODE"
echo "============================================================"

# --- Create directories ---
mkdir -p "$BD_DIR" /var/log/betterdesk /var/www/certbot /etc/letsencrypt /etc/nginx

# --- Create betterdesk user ---
if ! id betterdesk &>/dev/null; then
  useradd -r -s /bin/bash -d "$BD_DIR" betterdesk
  ok "Created user: betterdesk"
fi

# --- Copy project files ---
cp -r . "$BD_DIR/" 2>/dev/null || true
chown -R betterdesk:betterdesk "$BD_DIR"
ok "Project files deployed to $BD_DIR"

# =============================================================================
# MODE: docker
# =============================================================================
if [[ "$MODE" == "docker" ]]; then
  echo "--- Deploying Docker Compose stack ---"

  # Write .env for compose
  cat > "$BD_DIR/.env.ops" <<EOF
CERTBOT_EMAIL=${CERTBOT_EMAIL}
RELAY_PUBLIC_IP=${RELAY_PUBLIC_IP}
SESSION_SECRET=${SESSION_SECRET}
EOF

  # Start stack
  (cd "$BD_DIR" && docker compose -f docker-compose.ops.yml --env-file .env.ops up -d)
  ok "Docker stack started"

  echo ""
  echo "Next steps:"
  echo "  1. Issue SSL certs:   docker compose -f docker-compose.ops.yml --profile init run --rm certbot"
  echo "  2. Check health:      ./scripts/health-check.sh"
  echo "  3. Monitor:           open https://panel.telcom.stream:3001 (Uptime Kuma)"
  exit 0
fi

# =============================================================================
# MODE: bare
# =============================================================================
echo "--- Deploying bare-metal systemd services ---"

# Install dependencies
if command -v apt-get &>/dev/null; then
  apt-get update -y && apt-get install -y nginx certbot curl wget openssl sqlite3
elif command -v yum &>/dev/null; then
  yum install -y nginx certbot curl wget openssl sqlite
elif command -v apk &>/dev/null; then
  apk add nginx certbot curl wget openssl sqlite
fi
ok "System dependencies installed"

# Install systemd unit files
cp "$BD_DIR/systemd/betterdesk-landing.service" /etc/systemd/system/
cp "$BD_DIR/systemd/betterdesk-console.service" /etc/systemd/system/
cp "$BD_DIR/systemd/betterdesk-nginx.service" /etc/systemd/system/
cp "$BD_DIR/systemd/certbot-renew.service" /etc/systemd/system/
cp "$BD_DIR/systemd/certbot-renew.timer" /etc/systemd/system/

# Substitute environment variables in console service
sed -i "s|\${SESSION_SECRET}|${SESSION_SECRET}|g" /etc/systemd/system/betterdesk-console.service
sed -i "s|\${RELAY_PUBLIC_IP}|${RELAY_PUBLIC_IP}|g" /etc/systemd/system/betterdesk-console.service

# Install nginx config
cp "$BD_DIR/nginx.conf" /etc/nginx/nginx.conf
mkdir -p /etc/nginx/ssl
cp "$BD_DIR/nginx/ssl-params.conf" /etc/nginx/ssl-params.conf

# Install scripts
cp "$BD_DIR/scripts/health-check.sh" /usr/local/bin/bd-health-check
cp "$BD_DIR/scripts/uptime-monitor.sh" /usr/local/bin/bd-uptime-monitor
cp "$BD_DIR/scripts/ssl-setup.sh" /usr/local/bin/bd-ssl-setup
chmod +x /usr/local/bin/bd-*

# Reload systemd
systemctl daemon-reload

# Enable + start services
systemctl enable --now betterdesk-landing
systemctl enable --now betterdesk-console
systemctl enable --now certbot-renew.timer

# Issue SSL certs before starting nginx (nginx needs certs)
echo "--- Issuing SSL certificates ---"
/usr/local/bin/bd-ssl-setup --issue

# Start nginx last (depends on certs)
systemctl enable --now betterdesk-nginx

# Setup uptime monitor cron
(crontab -l 2>/dev/null || echo "") | grep -v bd-uptime-monitor | { cat; echo "* * * * * /usr/local/bin/bd-uptime-monitor"; } | crontab -

ok "Bare-metal deployment complete"
echo ""
echo "==================== VERIFICATION ===================="
/usr/local/bin/bd-health-check
