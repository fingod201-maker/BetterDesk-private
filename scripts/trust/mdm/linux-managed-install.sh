#!/usr/bin/env bash
# Linux MDM allowlist / managed install for the in-house zoom-private client.
#
# Run from your MDM's Linux provisioning step (or manually as root):
#   bash scripts/trust/mdm/linux-managed-install.sh [server-address]
#
# Installs the client into /opt/zoom-private, registers a systemd unit and
# pins the in-house publisher certificate in the system trust store.

set -euo pipefail

SERVER_ADDRESS="${1:-https://panel.telcom.stream}"
INSTALL_DIR="/opt/zoom-private"
CONFIG_DIR="${HOME}/.config/zoom-private/agent"
BUNDLE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CERT="${BUNDLE_DIR}/scripts/trust/publisher.cer"

if [ ! -x "$INSTALL_DIR/zoom-private.agent" ]; then
  echo "Client binary not found in $INSTALL_DIR — deploy the bundle first." >&2
  exit 1
fi

if [ -f "$CERT" ]; then
  install -d /usr/local/share/ca-certificates
  cp "$CERT" /usr/local/share/ca-certificates/zoom-private-publisher.crt
  update-ca-certificates
  echo "Publisher certificate trusted."
fi

mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/agent-config.json" ]; then
  cat > "$CONFIG_DIR/agent-config.json" <<JSON
{
  "server_address": "$SERVER_ADDRESS",
  "api_key": "",
  "cdap_port": 21122,
  "device_id": "",
  "device_name": "",
  "auth_token": "",
  "registered": false,
  "allow_screen_capture": true,
  "access_mode": "unattended",
  "require_consent": false,
  "allow_terminal": true,
  "allow_file_browser": true,
  "allow_clipboard": true,
  "auto_start_sidecar": true,
  "video_codec": "auto",
  "hw_accel": "auto",
  "autostart": true,
  "start_minimized": true,
  "language": "en",
  "unattended_password": "",
  "enforce_tls": true,
  "server_cert_pin": ""
}
JSON
  echo "Config written: $CONFIG_DIR/agent-config.json"
fi

UNIT_DIR=/etc/systemd/system
cat > "$UNIT_DIR/zoom-private.service" <<UNIT
[Unit]
Description=zoom-private agent
After=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/zoom-private.agent
Environment=BETTERDESK_AGENT_CONFIG_DIR=$CONFIG_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable zoom-private.service
systemctl restart zoom-private.service
echo "zoom-private registered as a managed system service."
