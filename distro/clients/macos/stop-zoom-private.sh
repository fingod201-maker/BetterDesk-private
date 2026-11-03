#!/bin/sh
set -eu
LABEL="com.unitronix.betterdesk-support-agent"
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
pkill -f 'betterdesk-agent' 2>/dev/null || true
echo "Zoom-Private agent stopped."
