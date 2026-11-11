#!/bin/bash
# =============================================================================
# BetterDesk OCI (Oracle Cloud) cloud-init bootstrap
# -----------------------------------------------------------------------------
# Drop this into an OCI compute instance's cloud-init → Custom cloud-init script
# when launching from the OCI Console or via oci-cli.
#
# Shape: VM.Standard.E2.1.Micro (Always Free) or VM.Standard.E3.Flex (1 OCPU / 6 GB)
# Image: Canonical Ubuntu 24.04 or Oracle Linux 9
# Boot volume: 50 GB+ (default)
# -----------------------------------------------------------------------------
# After boot (~3 min), the server is live at:
#   Admin console:  https://<public-ip>:5000    (or your domain)
#   Signal/relay:   <public-ip>:21116-21119
#   API:            <public-ip>:21121
#   CDAP gateway:   <public-ip>:21122
# =============================================================================
set -euo pipefail

# --- Configure these ---------------------------------------------------------
DOMAIN="${BETTERDESK_DOMAIN:-panel.telcom.stream}"
ADMIN_EMAIL="${BETTERDESK_ADMIN_EMAIL:-admin@telcom.stream}"
LETSENCRYPT_EMAIL="${BETTERDESK_LETSENCRYPT_EMAIL:-admin@telcom.stream}"
ENROLLMENT_MODE="${BETTERDESK_ENROLLMENT_MODE:-open}"
LOG_FILE="/var/log/betterdesk-cloudinit.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date -Is)] BetterDesk cloud-init starting..."

# --- OS detection ------------------------------------------------------------
if [ -f /etc/oracle-release ]; then
    OS_FAMILY="ol"
    PKG_MGR="dnf"
    echo "Detected: Oracle Linux"
elif [ -f /etc/lsb-release ]; then
    OS_FAMILY="ubuntu"
    PKG_MGR="apt-get"
    echo "Detected: Ubuntu"
else
    OS_FAMILY="linux"
    PKG_MGR="apt-get"
    echo "Detected: generic Linux"
fi

# --- Install runtime dependencies --------------------------------------------
echo "[$(date -Is)] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive

if [ "$OS_FAMILY" = "ubuntu" ]; then
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates ufw nginx certbot python3-certbot-nginx
elif [ "$OS_FAMILY" = "ol" ]; then
    dnf install -y curl ca-certificates nginx certbot python3-certbot-nginx
    # OCI OL images have strict firewalld
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
fi

# --- Docker install ----------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "[$(date -Is)] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Install docker-compose plugin
if ! docker compose version >/dev/null 2>&1; then
    DOCKER_CONFIG=${DOCKER_CONFIG:-/usr/local/lib/docker/cli-plugins}
    mkdir -p "$DOCKER_CONFIG"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o "$DOCKER_CONFIG/docker-compose"
    chmod +x "$DOCKER_CONFIG/docker-compose"
fi

# --- Pull and run BetterDesk -------------------------------------------------
BETTERDESK_DIR="/opt/betterdesk"
mkdir -p "$BETTERDESK_DIR"/{data,logs,ssl}

cd "$BETTERDESK_DIR"

# Write docker-compose
cat > docker-compose.yml << 'COMPOSE'
services:
  betterdesk:
    image: ghcr.io/unitronix/betterdesk:latest
    container_name: betterdesk
    restart: unless-stopped
    network_mode: host
    environment:
      - BETTERDESK_ENROLLMENT=${BETTERDESK_ENROLLMENT:-open}
      - BETTERDESK_REG_TIMEOUT=90
      - BETTERDESK_TZ=UTC
    volumes:
      - ./data:/app/data
      - ./ssl:/app/ssl
      - ./betterdesk.toml:/app/betterdesk.toml:ro
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
COMPOSE

# Write server config
cat > betterdesk.toml << 'TOML'
# BetterDesk server configuration
[server]
bind = "0.0.0.0"
api_port = 21121
cdap_port = 21122
enrollment = "open"
reg_timeout = 90

[database]
driver = "sqlite"
dsn = "/app/data/betterdesk.db"

[signal]
bind_udp = "0.0.0.0:21116"
bind_tcp = "0.0.0.0:21116"

[relay]
bind_tcp = "0.0.0.0:21117"
bind_ws = "0.0.0.0:21119"

[webconsole]
enabled = true
port = 5000

[logging]
level = "info"
audit = true
TOML

# Write env file
cat > .env << ENVFILE
BETTERDESK_ENROLLMENT=${ENROLLMENT_MODE}
ENVFILE

echo "[$(date -Is)] Starting BetterDesk..."
docker compose down 2>/dev/null || true
docker compose pull
docker compose up -d

# --- Firewall -----------------------------------------------------------------
echo "[$(date -Is)] Configuring firewall..."

if command -v ufw >/dev/null 2>&1; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 5000/tcp comment 'Web console'
    ufw allow 21115/tcp comment 'NAT type test'
    ufw allow 21116/tcp comment 'Signal TCP'
    ufw allow 21116/udp comment 'Signal UDP'
    ufw allow 21117/tcp comment 'Relay TCP'
    ufw allow 21118/tcp comment 'Signal WS'
    ufw allow 21119/tcp comment 'Relay WS'
    ufw allow 21121/tcp comment 'API'
    ufw allow 21122/tcp comment 'CDAP gateway'
    ufw --force enable
elif command -v iptables >/dev/null 2>&1; then
    for port in 22 80 443 5000 21115 21116 21117 21118 21119 21121 21122; do
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    done
    iptables -I INPUT -p udp --dport 21116 -j ACCEPT 2>/dev/null || true
    # Persist on OL
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
    fi
fi

# --- OCI security list notes -------------------------------------------------
# Ensure the OCI subnet security list allows ingress on these ports:
#   22 (SSH), 80, 443, 5000, 21115-21122/tcp, 21116/udp
# OCI Console → Networking → Virtual Cloud Networks → <VCN> →
#   Security Lists → <Default> → Add Ingress Rules

# --- SSL (Let's Encrypt) -----------------------------------------------------
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ] && dig +short "$DOMAIN" >/dev/null 2>&1; then
    echo "[$(date -Is)] Requesting SSL certificate for $DOMAIN..."

    cat > /etc/nginx/sites-available/betterdesk << NGINX
server {
    listen 80;
    server_name ${DOMAIN} *.${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
NGINX

    mkdir -p /var/www/html
    ln -sf /etc/nginx/sites-available/betterdesk /etc/nginx/sites-enabled/ 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t && systemctl restart nginx

    certbot --nginx -n --agree-tos --email "$LETSENCRYPT_EMAIL" \
        -d "$DOMAIN" -d "*.$DOMAIN" --redirect 2>&1 || {
        echo "[$(date -Is)] certbot failed, continuing without SSL"
    }

    cat > /etc/nginx/sites-available/betterdesk << NGINXSSL
server {
    listen 80;
    server_name ${DOMAIN} *.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN} *.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location /ws/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXSSL

    nginx -t && systemctl restart nginx
fi

# --- Health check endpoint ---------------------------------------------------
docker run -d --name healthcheck --restart=unless-stopped \
    -p 8080:80 --health-cmd="curl -f localhost:80 || exit 1" \
    nginx:alpine 2>/dev/null || true

# --- Verify ------------------------------------------------------------------
sleep 10
echo "[$(date -Is)] Verifying deployment..."
curl -sf http://localhost:21121/api/server/status 2>/dev/null && echo "  Go server: OK" || echo "  Go server: starting..."
curl -sf http://localhost:5000 2>/dev/null && echo "  Web console: OK" || echo "  Web console: starting..."

PUBLIC_IP=$(curl -sf http://169.254.169.254/opc/v1/vnics/ 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d[0]['publicIp'] if isinstance(d, list) else d.get('publicIp',''))
" 2>/dev/null || curl -sf ifconfig.me 2>/dev/null || echo "unknown")

echo ""
echo "====================================================================="
echo "  BetterDesk is live!"
echo "  Admin console:  https://${DOMAIN:-$PUBLIC_IP}:5000"
echo "  Public IP:      $PUBLIC_IP"
echo "  Log:            $LOG_FILE"
echo "  Status:         docker compose -f $BETTERDESK_DIR/docker-compose.yml logs -f"
echo "====================================================================="

exit 0
