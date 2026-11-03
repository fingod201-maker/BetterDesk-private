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

APP_DIR="$HOME/.local/share/betterdesk/agent"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/betterdesk-support-agent.desktop"
UNIT_FILE="$HOME/.config/systemd/user/betterdesk-support-agent.service"

if [ "1" = 1 ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now "betterdesk-support-agent.service" 2>/dev/null || true
    fi
    rm -f "$UNIT_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
fi
terminate_agent "$APP_DIR/agent.pid"
rm -f "$DESKTOP_FILE"
rm -rf "$APP_DIR"
echo "BetterDesk Support Agent removed."
