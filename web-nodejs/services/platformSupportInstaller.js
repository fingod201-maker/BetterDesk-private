'use strict';

/**
 * macOS / Linux support-agent installers.
 *
 * The live Windows deployment deliberately runs the agent in the logged-in
 * user session (scheduled task -> start-agent.vbs -> agent-launch.cmd) instead
 * of a session-0 service, because a system service cannot capture the real
 * desktop or inject input. The Unix installers below follow the same rule:
 *
 *   macOS: per-user LaunchAgent in ~/Library/LaunchAgents (NOT a LaunchDaemon)
 *   Linux: systemd --user unit / XDG autostart in the desktop session
 *
 * Both are non-interactive and idempotent so they can be pushed unattended by
 * the operator panel. If an install is executed as root the script drops back
 * to the desktop user automatically (SUDO_USER / console owner).
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

const MACOS_LABEL = 'com.unitronix.betterdesk-support-agent';
const LINUX_UNIT = 'betterdesk-support-agent.service';

function shellBool(value) {
    return value ? '1' : '0';
}

/**
 * Shared POSIX helpers embedded in every generated script. Kept small and
 * dependency-free (no bashisms) so it runs on macOS /bin/sh and any Linux.
 */
function shellPreamble() {
    return String.raw`
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
`.trim();
}

/** Launcher shared by macOS and Linux: PID guard, log rotation, exit log.
 *  Kept static on purpose (quoted heredoc) so shell runtime expressions are
 *  never expanded at install time. Paths are loaded from agent-env.sh. */
function unixLauncher() {
    return String.raw`#!/bin/sh
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
`;
}

function macInstaller({ installService, autostart }) {
    const startOnLogin = installService || autostart;
    return `#!/bin/sh
set -eu
${shellPreamble()}

LABEL="${MACOS_LABEL}"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/betterdesk/agent"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
LOG_FILE="$APP_DIR/agent.log"
CONFIG_FILE="$APP_DIR/agent-config.json"
LAUNCHER="$APP_DIR/agent-launch.sh"
START_SCRIPT="$APP_DIR/start-agent.sh"
INSTALL_SERVICE="${shellBool(installService)}"
AUTOSTART="${shellBool(autostart)}"

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
    AGENT_BIN="$(find "$SOURCE_DIR" -maxdepth 2 -type f \\( -name 'betterdesk-agent*' -o -name betterdesk -o -name rustdesk \\) 2>/dev/null | head -n 1)"
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

cat >"$APP_DIR/agent-env.sh" <<ENV_EOF
APP_DIR="$APP_DIR"
AGENT="$AGENT_BIN"
CONFIG="$CONFIG_FILE"
LOG="$LOG_FILE"
ENV_EOF
chmod 600 "$APP_DIR/agent-env.sh"

cat >"$LAUNCHER" <<'LAUNCHER_EOF'
${unixLauncher()}
LAUNCHER_EOF
chmod 755 "$LAUNCHER"

# start-agent.sh is the macOS equivalent of start-agent.vbs: it (re)bootstraps
# the LaunchAgent in the current GUI session.
cat >"$START_SCRIPT" <<START_EOF
#!/bin/sh
set -eu
LABEL="$LABEL"
PLIST="$PLIST"
UID_NUM="\\$(id -u)"
launchctl bootout "gui/\\$UID_NUM/\\$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/\\$UID_NUM" "\\$PLIST" 2>/dev/null || true
launchctl enable "gui/\\$UID_NUM/\\$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/\\$UID_NUM/\\$LABEL" 2>/dev/null || true
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
    echo "BetterDesk installed without autostart. Run: sh \\"$START_SCRIPT\\""
fi

cat <<GUIDANCE_EOF

Installed:
  App/binary : ${'$'}AGENT_BIN
  Config     : ${'$'}CONFIG_FILE
  Log        : ${'$'}LOG_FILE
  LaunchAgent: ${'$'}PLIST

macOS requires two one-time permissions for remote desktop + input:
  1. System Settings > Privacy & Security > Screen Recording  -> enable BetterDesk
  2. System Settings > Privacy & Security > Accessibility     -> enable BetterDesk
Grant them once, then run: sh "$START_SCRIPT"
Mouse input also uses cliclick when available (brew install cliclick).
GUIDANCE_EOF
`;
}

function macUninstaller({ installService }) {
    return `#!/bin/sh
set -eu
${shellPreamble()}

LABEL="${MACOS_LABEL}"
APP_DIR="$HOME/Library/Application Support/betterdesk/agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

if [ "${shellBool(installService)}" = 1 ]; then
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    launchctl disable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
fi
terminate_agent "$APP_DIR/agent.pid"
rm -f "$PLIST"
rm -rf "$APP_DIR"
rm -rf "$HOME/Applications/BetterDesk Support Agent.app"
echo "BetterDesk Support Agent removed."
`;
}

function linuxInstaller({ installService, autostart }) {
    return `#!/bin/sh
set -eu
${shellPreamble()}

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$HOME/.local/share/betterdesk/agent"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/betterdesk-support-agent.desktop"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$UNIT_DIR/${LINUX_UNIT}"
LOG_DIR="$HOME/.local/share/betterdesk/agent"
LOG_FILE="$LOG_DIR/agent.log"
CONFIG_FILE="$LOG_DIR/agent-config.json"
LAUNCHER="$APP_DIR/agent-launch.sh"
INSTALL_SERVICE="${shellBool(installService)}"
AUTOSTART="${shellBool(autostart)}"

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
    AGENT_BIN="$(find "$APP_DIR" -maxdepth 1 -type f -name 'betterdesk-agent*' 2>/dev/null | head -n 1)"
    [ -n "$AGENT_BIN" ] && chmod 755 "$AGENT_BIN"
fi
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
${unixLauncher()}
LAUNCHER_EOF
chmod 755 "$LAUNCHER"

if [ "$INSTALL_SERVICE" = 1 ]; then
    terminate_agent "$APP_DIR/agent.pid"
    mkdir -p "$UNIT_DIR"

    # Capture the display actually used at install time. Hardcoding :0/wayland
    # produced blank streams on multi-seat and X11-only machines.
    DISPLAY_VALUE=$(printenv DISPLAY 2>/dev/null || true)
    [ -n "$DISPLAY_VALUE" ] || DISPLAY_VALUE=":0"
    WAYLAND_VALUE=$(printenv WAYLAND_DISPLAY 2>/dev/null || true)
    if [ -n "$WAYLAND_VALUE" ]; then
        SESSION_TYPE="wayland"
    else
        SESSION_TYPE="x11"
    fi

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
Environment=DISPLAY=$DISPLAY_VALUE
Environment=WAYLAND_DISPLAY=$WAYLAND_VALUE
Environment=XDG_SESSION_TYPE=$SESSION_TYPE

[Install]
WantedBy=graphical-session.target
UNIT_EOF

    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now "${LINUX_UNIT}" 2>/dev/null || true
        systemctl --user restart "${LINUX_UNIT}" 2>/dev/null || true
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
    echo "Start manually: /bin/sh \\"$LAUNCHER\\""
fi

cat <<GUIDANCE_EOF

Installed:
  Binary  : ${'$'}AGENT_BIN
  Config  : ${'$'}CONFIG_FILE
  Log     : ${'$'}LOG_FILE

The agent runs in the logged-in desktop session. For Wayland screen capture
install grim (wlroots) or use the XDG Desktop Portal; for X11 install scrot or
ImageMagick. Input injection uses xdotool when available.
GUIDANCE_EOF
`;
}

function linuxUninstaller({ installService }) {
    return `#!/bin/sh
set -eu
${shellPreamble()}

APP_DIR="$HOME/.local/share/betterdesk/agent"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/betterdesk-support-agent.desktop"
UNIT_FILE="$HOME/.config/systemd/user/${LINUX_UNIT}"

if [ "${shellBool(installService)}" = 1 ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now "${LINUX_UNIT}" 2>/dev/null || true
    fi
    rm -f "$UNIT_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
fi
terminate_agent "$APP_DIR/agent.pid"
rm -f "$DESKTOP_FILE"
rm -rf "$APP_DIR"
echo "BetterDesk Support Agent removed."
`;
}

const UNIX_INSTALL_WRAPPER = `#!/bin/sh
# BetterDesk client entry point. Committed/generated with mode 0755 so
# ./install.sh works without a separate chmod +x.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "\${1:-}" in
    -u|--uninstall|uninstall)
        exec /bin/sh "$DIR/uninstall-betterdesk-support.sh" ;;
esac
if [ ! -f "$DIR/install-betterdesk-support.sh" ]; then
    echo "install-betterdesk-support.sh not found next to install.sh" >&2
    exit 1
fi
exec /bin/sh "$DIR/install-betterdesk-support.sh" "$@"
`;

const MAC_PKG_BUILDER = `#!/bin/sh
# Build an unsigned BetterDesk Support Agent .pkg on macOS.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=\${1:-\${BETTERDESK_VERSION:-1.0.0}}
PKG_ID="com.unitronix.betterdesk-support-agent"
OUT_DIR="$DIR/out"
OUT="$OUT_DIR/BetterDesk-Support-Agent-$VERSION.pkg"
if [ "$(uname -s)" != "Darwin" ]; then
    echo "build-pkg.sh must run on macOS (pkgbuild/productbuild are Apple tools)." >&2
    exit 1
fi
STAGE=$(mktemp -d "\${TMPDIR:-/tmp}/betterdesk-pkg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
BASE="$STAGE/root/usr/local/share/betterdesk-support"
SCRIPTS="$STAGE/scripts"
mkdir -p "$BASE" "$SCRIPTS" "$OUT_DIR"
cp "$DIR/install.sh" "$DIR/install-betterdesk-support.sh" "$DIR/uninstall-betterdesk-support.sh" "$BASE/"
if [ -d "$DIR/payload" ]; then
    cp -a "$DIR/payload/." "$BASE/"
else
    for item in "$DIR"/*.app "$DIR"/betterdesk-agent "$DIR"/betterdesk-agent-* "$DIR"/betterdesk "$DIR"/rustdesk; do
        [ -e "$item" ] && cp -a "$item" "$BASE/"
    done
fi
chmod 755 "$BASE"/*.sh 2>/dev/null || true
cat >"$SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/sh
BASE="/usr/local/share/betterdesk-support"
U=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
[ -n "$U" ] && [ "$U" != "root" ] && /usr/bin/sudo -u "$U" -H /bin/sh "$BASE/install.sh" || true
exit 0
POSTINSTALL
chmod 755 "$SCRIPTS/postinstall"
pkgbuild --root "$STAGE/root" --identifier "$PKG_ID" --version "$VERSION" --scripts "$SCRIPTS" "$STAGE/component.pkg"
productbuild --package "$STAGE/component.pkg" "$OUT"
echo "Built: $OUT"
`;

async function writeUnixSupportInstallers(stageDir, platform, options = {}) {
    const normalized = {
        installService: !!options.installService,
        autostart: !!options.autostart,
    };
    const isLinux = String(platform).toLowerCase() === 'linux';
    const scripts = isLinux
        ? {
            install: linuxInstaller(normalized),
            uninstall: linuxUninstaller(normalized),
        }
        : {
            install: macInstaller(normalized),
            uninstall: macUninstaller(normalized),
        };
    const installPath = path.join(stageDir, 'install-betterdesk-support.sh');
    const uninstallPath = path.join(stageDir, 'uninstall-betterdesk-support.sh');
    const wrapperPath = path.join(stageDir, 'install.sh');
    await fsp.writeFile(installPath, scripts.install, { mode: 0o755 });
    await fsp.writeFile(uninstallPath, scripts.uninstall, { mode: 0o755 });
    await fsp.writeFile(wrapperPath, UNIX_INSTALL_WRAPPER, { mode: 0o755 });
    const paths = [installPath, uninstallPath, wrapperPath];
    if (!isLinux) {
        const pkgPath = path.join(stageDir, 'build-pkg.sh');
        await fsp.writeFile(pkgPath, MAC_PKG_BUILDER, { mode: 0o755 });
        paths.push(pkgPath);
    }
    await Promise.all(paths.map((p) => fsp.chmod(p, 0o755)));
}

function hasUnixSupportInstallers(stageDir) {
    return ['install-betterdesk-support.sh', 'uninstall-betterdesk-support.sh']
        .every((name) => fs.existsSync(path.join(stageDir, name)));
}

module.exports = {
    writeUnixSupportInstallers,
    hasUnixSupportInstallers,
    buildMacSupportInstallerScript: macInstaller,
    buildLinuxSupportInstallerScript: linuxInstaller,
    constants: { MACOS_LABEL, LINUX_UNIT },
};
