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

LABEL="com.unitronix.betterdesk-support-agent"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/betterdesk/agent"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
LOG_FILE="$APP_DIR/agent.log"
CONFIG_FILE="$APP_DIR/agent-config.json"
LAUNCHER="$APP_DIR/agent-launch.sh"
START_SCRIPT="$APP_DIR/start-agent.sh"
INSTALL_SERVICE="1"
AUTOSTART="1"

mkdir -p "$APP_DIR" "$LAUNCH_AGENTS" "$HOME/Applications"

# Prefer a .app bundle (desktop client); fall back to a standalone binary
# (Go CDAP agent ships as betterdesk-agent).
APP_BUNDLE="$(find "$SOURCE_DIR" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -n 1)"
AGENT_BIN=""
if [ -n "$APP_BUNDLE" ]; then
    TARGET_APP="$HOME/Applications/$(basename "$APP_BUNDLE")"
    rm -rf "$TARGET_APP"
    ditto "$APP_BUNDLE" "$TARGET_APP"
    APP_BUNDLE="$TARGET_APP"
    # Remove the quarantine flag so Gatekeeper does not block the agent.
    xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    for candidate in "$TARGET_APP/Contents/MacOS/betterdesk" "$TARGET_APP/Contents/MacOS/rustdesk"; do
        [ -x "$candidate" ] && AGENT_BIN="$candidate" && break
    done
    if [ -z "$AGENT_BIN" ]; then
        AGENT_BIN="$(find "$TARGET_APP/Contents/MacOS" -maxdepth 1 -type f -perm -111 2>/dev/null | head -n 1)"
    fi
else
    AGENT_BIN="$(find "$SOURCE_DIR" -maxdepth 2 -type f \( -name 'betterdesk-agent*' -o -name betterdesk -o -name rustdesk \) 2>/dev/null | head -n 1)"
    if [ -z "$AGENT_BIN" ]; then
        echo "BetterDesk executable or .app bundle was not found next to this installer." >&2
        exit 1
    fi
    cp -f "$AGENT_BIN" "$APP_DIR/$(basename "$AGENT_BIN")"
    chmod 755 "$APP_DIR/$(basename "$AGENT_BIN")"
    AGENT_BIN="$APP_DIR/$(basename "$AGENT_BIN")"
fi

if [ -z "$AGENT_BIN" ] || [ ! -x "$AGENT_BIN" ]; then
    echo "BetterDesk executable is not runnable: $AGENT_BIN" >&2
    exit 1
fi

# Preserve an operator-supplied config (unattended enrollment). The panel
# injects it next to the installer for zero-touch rollouts.
if [ -f "$SOURCE_DIR/agent-config.json" ] && [ ! -f "$CONFIG_FILE" ]; then
    cp -f "$SOURCE_DIR/agent-config.json" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

# Resolve ffmpeg once at install time so the launcher does not depend on
# the desktop shell's PATH (common cause of blank streams).
FFMPEG_BIN=$(command -v ffmpeg 2>/dev/null || true)
for cand in "$HOME/.local/bin/ffmpeg" /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg /snap/bin/ffmpeg; do
    [ -n "$FFMPEG_BIN" ] || { [ -x "$cand" ] && FFMPEG_BIN="$cand"; }
done
FFMPEG_DIR=""
[ -n "$FFMPEG_BIN" ] && FFMPEG_DIR=$(dirname "$FFMPEG_BIN")
[ -n "$FFMPEG_BIN" ] || echo "WARNING: ffmpeg not found - install ffmpeg (or scrot/grim/ImageMagick) for screen streaming" >&2
if [ -n "$FFMPEG_DIR" ]; then
    AGENT_PATH="$FFMPEG_DIR:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
else
    AGENT_PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi

cat >"$APP_DIR/agent-env.sh" <<ENV_EOF
APP_DIR="$APP_DIR"
AGENT="$AGENT_BIN"
CONFIG="$CONFIG_FILE"
LOG="$LOG_FILE"
PATH="$AGENT_PATH"
export PATH
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

# start-agent.sh is the macOS equivalent of start-agent.vbs: it (re)bootstraps
# the LaunchAgent in the current GUI session.
cat >"$START_SCRIPT" <<START_EOF
#!/bin/sh
set -eu
LABEL="$LABEL"
PLIST="$PLIST"
UID_NUM="\$(id -u)"
launchctl bootout "gui/\$UID_NUM/\$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/\$UID_NUM" "\$PLIST" 2>/dev/null || true
launchctl enable "gui/\$UID_NUM/\$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/\$UID_NUM/\$LABEL" 2>/dev/null || true
START_EOF
chmod 755 "$START_SCRIPT"

if [ "$INSTALL_SERVICE" = 1 ] || [ "$AUTOSTART" = 1 ]; then
    terminate_agent "$APP_DIR/agent.pid"

    RUN_AT_LOAD="false"
    KEEP_ALIVE="false"
    if [ "$INSTALL_SERVICE" = 1 ] || [ "$AUTOSTART" = 1 ]; then
        RUN_AT_LOAD="true"
        KEEP_ALIVE="true"
    fi

    cat >"$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$LAUNCHER</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$APP_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>$HOME</string>
        <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <$RUN_AT_LOAD/>
    <key>KeepAlive</key>
    <$KEEP_ALIVE/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
PLIST_EOF
    chmod 644 "$PLIST"

    UID_NUM="$(id -u)"
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
    launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    if [ "$RUN_AT_LOAD" = "true" ]; then
        launchctl kickstart -k "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    fi

    echo "BetterDesk Support Agent LaunchAgent installed (user session)."
else
    echo "BetterDesk installed without autostart. Run: sh \"$START_SCRIPT\""
fi

cat <<GUIDANCE_EOF

Installed:
  App/binary : $AGENT_BIN
  Config     : $CONFIG_FILE
  Log        : $LOG_FILE
  LaunchAgent: $PLIST

macOS requires two one-time permissions for remote desktop + input:
  1. System Settings > Privacy & Security > Screen Recording  -> enable BetterDesk
  2. System Settings > Privacy & Security > Accessibility     -> enable BetterDesk
Grant them once, then run: sh "$START_SCRIPT"
Mouse input also uses cliclick when available (brew install cliclick).
GUIDANCE_EOF
