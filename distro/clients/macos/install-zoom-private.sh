#!/bin/sh
set -eu
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -f "$DIR/install-betterdesk-support.sh" ]; then
    echo "install-betterdesk-support.sh is missing next to this script." >&2
    exit 1
fi
if ! find "$DIR" -maxdepth 1 -name "*.app" -type d | grep -q . && [ ! -x "$DIR/betterdesk-agent" ] && [ ! -x "$DIR/betterdesk" ]; then
    echo "No Zoom-Private app or betterdesk-agent binary found next to this installer." >&2
    echo "Open the .dmg/.zip package or place the .app/binary here first." >&2
    exit 1
fi
exec /bin/sh "$DIR/install-betterdesk-support.sh"

