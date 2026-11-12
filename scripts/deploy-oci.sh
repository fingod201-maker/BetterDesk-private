#!/bin/bash
set -e
echo "[$(date -Is)] BetterDesk deployment via Podman on Oracle Linux 10..."

# Stop old
sudo podman rm -f betterdesk 2>/dev/null || true

# Create directories
sudo mkdir -p /opt/betterdesk/data /opt/betterdesk/ssl

# Open firewall
echo "[$(date -Is)] Configuring firewall..."
sudo ufw --force reset 2>/dev/null || true
sudo ufw default deny incoming 2>/dev/null || true
sudo ufw default allow outgoing 2>/dev/null || true
for port in 22 80 443 5000 21114 21115 21116 21117 21118 21119 21121 21122; do
    sudo ufw allow $port/tcp 2>/dev/null || true
done
sudo ufw allow 21116/udp 2>/dev/null || true
sudo ufw --force enable 2>/dev/null || true

for port in 22 80 443 5000 21114 21115 21116 21117 21118 21119 21121 21122; do
    sudo iptables -I INPUT 1 -p tcp --dport $port -j ACCEPT 2>/dev/null || true
done
sudo iptables -I INPUT 1 -p udp --dport 21116 -j ACCEPT 2>/dev/null || true

# Pull GHCR image via podman
echo "[$(date -Is)] Pulling GHCR image..."
sudo podman pull ghcr.io/unitronix/betterdesk:latest 2>&1

# Run the all-in-one container
echo "[$(date -Is)] Starting BetterDesk container..."
sudo podman run -d \
    --name betterdesk \
    --restart unless-stopped \
    --network host \
    -e BETTERDESK_ENROLLMENT=open \
    -e BETTERDESK_REG_TIMEOUT=90 \
    -e CONSOLE_URL=https://panel.telcom.stream \
    -v /opt/betterdesk/data:/app/data \
    ghcr.io/unitronix/betterdesk:latest 2>&1

sleep 10

# Create systemd service for auto-start
sudo podman generate systemd --name betterdesk --restart-policy=always > /etc/systemd/system/betterdesk.service 2>/dev/null
sudo systemctl daemon-reload 2>/dev/null || true
sudo systemctl enable betterdesk.service 2>/dev/null || true

echo ""
echo "=== Status ==="
sudo podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== Ports ==="
sudo ss -tlnp | grep -E ':(5000|21114|21115|21116|21117|21118|21119|21121|21122)' || echo "Ports starting up..."
echo ""
echo "=== Container logs ==="
sudo podman logs betterdesk --tail 25 2>&1 || echo "No logs yet"
echo ""
echo "=== Admin credentials ==="
sudo podman exec betterdesk cat /app/data/admin-credentials.txt 2>/dev/null || echo "Still generating..."
echo ""
echo "Server IP: $(curl -s ifconfig.me)"
