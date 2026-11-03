#!/bin/sh
set -eu
# Resolve the logged-in desktop user. An agent that captures the screen must
# run inside the GUI session, never as root.
resolve_desktop_user() {
    if [ "$(id -u)" -ne 0 ]; then
        id -un
        return
    fi
    if [ -n "$(printenv SUDO_USER 2>/dev/null || true)" ] && [ "$(printenv SUDO_USER)" != "root" ]; then
        printenv SUDO_USER
        return
    fi
    if command -v console_user >/dev/null 2>&1; then
        console_user
        return
    fi
    stat -c '%U' /dev/console 2>/dev/null || stat -f '%Su' /dev/console 2>/dev/null || true
}

# Re-exec as the desktop user when invoked through sudo/root.
if [ "$(id -u)" -eq 0 ]; then
    BETTERDESK_TARGET_USER="$(resolve_desktop_user)"
    if [ -z "$BETTERDESK_TARGET_USER" ] || [ "$BETTERDESK_TARGET_USER" = "root" ]; then
        echo "Run this installer as the logged-in desktop user (not root)." >&2
        exit 1
    fi
    exec sudo -u "$BETTERDESK_TARGET_USER" -H "$0" "$@"
fi

# Kill stray instances from a previous install (best effort).
terminate_agent() {
    pid_file="$1"
    [ -f "$pid_file" ] || return 0
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$HOME/.local/share/betterdesk/agent"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/betterdesk-support-agent.desktop"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$UNIT_DIR/betterdesk-support-agent.service"
LOG_DIR="$HOME/.local/share/betterdesk/agent"
LOG_FILE="$LOG_DIR/agent.log"
CONFIG_FILE="$LOG_DIR/agent-config.json"
LAUNCHER="$APP_DIR/agent-launch.sh"
INSTALL_SERVICE="1"
AUTOSTART="1"

mkdir -p "$APP_DIR" "$AUTOSTART_DIR" "$LOG_DIR"

# Ship the whole portable payload so bundled libraries/assets stay next to
# the binary (Windows copies the payload directory for the same reason).
cp -a "$SOURCE_DIR"/. "$APP_DIR"/
chmod 755 "$APP_DIR" 2>/dev/null || true

AGENT_BIN=""
for candidate in "$APP_DIR/betterdesk-agent" "$APP_DIR/betterdesk" "$APP_DIR/rustdesk"; do
    [ -f "$candidate" ] && chmod 755 "$candidate" 2>/dev/null || true
    [ -x "$candidate" ] && AGENT_BIN="$candidate" && break
done
if [ -z "$AGENT_BIN" ]; then
    AGENT_BIN="$(find "$APP_DIR" -maxdepth 2 -type f -perm -111 2>/dev/null | head -n 1)"
fi
if [ -z "$AGENT_BIN" ]; then
    echo "BetterDesk executable was not found in the installer payload." >&2
    exit 1
fi

if [ -f "$SOURCE_DIR/agent-config.json" ] && [ ! -f "$CONFIG_FILE" ]; then
    cp -f "$SOURCE_DIR/agent-config.json" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

cat >"$APP_DIR/agent-env.sh" <<ENV_EOF
APP_DIR="$APP_DIR"
AGENT="$AGENT_BIN"
CONFIG="$CONFIG_FILE"
LOG="$LOG_FILE"
ENV_EOF
chmod 600 "$APP_DIR/agent-env.sh"

cat >"$LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/sh
# BetterDesk agent launcher (user session). Mirrors the Windows
# start-agent.vbs + agent-launch.cmd pair: hidden, logged, restart-safe.
set -eu

. "$(dirname "$0")/agent-env.sh"
PID_FILE="$APP_DIR/agent.pid"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Single-instance guard. launchd/systemd/XDG may all be active at once.
if [ -f "$PID_FILE" ]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PID_FILE"
fi
echo $$ >"$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT INT TERM

# Rotate at ~5 MB, matching the Windows launcher.
if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    mv -f "$LOG" "$LOG.1" 2>/dev/null || true
fi

printf '[%s] agent starting\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"

case "$(basename "$AGENT")" in
    *agent*)
        if [ -f "$CONFIG" ]; then
            "$AGENT" --config "$CONFIG" >>"$LOG" 2>&1
        else
            "$AGENT" >>"$LOG" 2>&1
        fi
        ;;
    *)
        "$AGENT" --tray >>"$LOG" 2>&1
        ;;
esac
code=$?
printf '[%s] agent exited code %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$code" >>"$LOG"
exit "$code"

LAUNCHER_EOF
chmod 755 "$LAUNCHER"

if [ "$INSTALL_SERVICE" = 1 ]; then
    terminate_agent "$APP_DIR/agent.pid"
    mkdir -p "$UNIT_DIR"
    cat >"$UNIT_FILE" <<UNIT_EOF
[Unit]
Description=BetterDesk Support Agent (user session)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/bin/sh "$LAUNCHER"
Restart=always
RestartSec=5
Environment=DISPLAY=:0
Environment=XDG_SESSION_TYPE=wayland

[Install]
WantedBy=graphical-session.target
UNIT_EOF

    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now "betterdesk-support-agent.service" 2>/dev/null || true
        systemctl --user restart "betterdesk-support-agent.service" 2>/dev/null || true
        echo "BetterDesk Support Agent user service installed (desktop session)."
    else
        # No user systemd (minimal/container/Live CD) - use XDG autostart.
        AUTOSTART=1
        rm -f "$UNIT_FILE"
        echo "systemd --user unavailable; using XDG autostart."
    fi
fi

if [ "$AUTOSTART" = 1 ]; then
    cat >"$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=BetterDesk Support Agent
Comment=Remote support agent (user session)
Exec=/bin/sh "$LAUNCHER"
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
DESKTOP_EOF
    chmod 644 "$DESKTOP_FILE"

    # Start immediately without waiting for the next login.
    if [ -n "$(printenv DISPLAY 2>/dev/null || true)$(printenv WAYLAND_DISPLAY 2>/dev/null || true)" ]; then
        nohup /bin/sh "$LAUNCHER" >/dev/null 2>&1 &
    fi
    echo "BetterDesk Support Agent XDG autostart installed."
fi

if [ "$INSTALL_SERVICE" != 1 ] && [ "$AUTOSTART" != 1 ]; then
    echo "BetterDesk installed without service or autostart."
    echo "Start manually: /bin/sh \"$LAUNCHER\""
fi

cat <<GUIDANCE_EOF

Installed:
  Binary  : $AGENT_BIN
  Config  : $CONFIG_FILE
  Log     : $LOG_FILE

The agent runs in the logged-in desktop session. For Wayland screen capture
install grim (wlroots) or use the XDG Desktop Portal; for X11 install scrot or
ImageMagick. Input injection uses xdotool when available.
GUIDANCE_EOF
