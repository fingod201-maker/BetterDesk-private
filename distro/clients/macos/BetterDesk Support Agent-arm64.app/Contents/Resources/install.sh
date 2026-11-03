#!/bin/sh
# BetterDesk client entry point. Committed/generated with mode 0755 so
# ./install.sh works without a separate chmod +x.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "${1:-}" in
    -u|--uninstall|uninstall)
        exec /bin/sh "$DIR/uninstall-betterdesk-support.sh" ;;
esac
if [ ! -f "$DIR/install-betterdesk-support.sh" ]; then
    echo "install-betterdesk-support.sh not found next to install.sh" >&2
    exit 1
fi
exec /bin/sh "$DIR/install-betterdesk-support.sh" "$@"
