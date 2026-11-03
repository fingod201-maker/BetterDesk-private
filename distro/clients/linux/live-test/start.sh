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

xsetroot -solid '#20242c' 2>/dev/null || true

xterm -fa Monospace -fs 20 -geometry 160x50+20+20 \
    >/tmp/xterm.log 2>&1 &

exec /usr/local/bin/betterdesk-agent -config /etc/betterdesk-agent.json
