#!/bin/sh
set -eu

export DISPLAY=:99
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT INT TERM

for _ in $(seq 1 40); do
    if xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

xterm -fa Monospace -fs 18 -geometry 100x30 \
    -e "bash -lc 'echo BetterDesk Linux live test; sleep 999999'" \
    >/tmp/xterm.log 2>&1 &

exec /usr/local/bin/betterdesk-agent -config /etc/betterdesk-agent.json
