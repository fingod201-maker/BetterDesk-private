#!/bin/sh
set -eu
LABEL="com.unitronix.betterdesk-support-agent"
UID_NUM="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ ! -f "$PLIST" ]; then
    echo "Agent is not installed ($PLIST missing). Run install-zoom-private.sh first." >&2
    exit 1
fi
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_NUM/$LABEL"
echo "Zoom-Private agent started."
echo "Log: $HOME/Library/Application Support/betterdesk/agent/agent.log"
