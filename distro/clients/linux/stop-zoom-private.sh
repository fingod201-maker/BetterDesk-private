#!/bin/sh
set -eu
UNIT="betterdesk-support-agent.service"
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files 2>/dev/null | grep -q "$UNIT"; then
    systemctl --user stop "$UNIT" 2>/dev/null || true
fi
pkill -f 'betterdesk-agent' 2>/dev/null || true
echo "Zoom-Private agent stopped."
