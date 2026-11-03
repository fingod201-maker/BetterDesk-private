#!/bin/sh
set -eu
UNIT="betterdesk-support-agent.service"
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files 2>/dev/null | grep -q "$UNIT"; then
    systemctl --user start "$UNIT"
    echo "Zoom-Private agent started (systemd user unit)."
else
    START="$HOME/.local/share/betterdesk/agent/start-agent.sh"
    if [ ! -f "$START" ]; then
        echo "Agent is not installed. Run install-zoom-private.sh first." >&2
        exit 1
    fi
    /bin/sh "$START"
    echo "Zoom-Private agent started (start-agent.sh)."
fi
echo "Log: $HOME/.local/share/betterdesk/agent/agent.log"
