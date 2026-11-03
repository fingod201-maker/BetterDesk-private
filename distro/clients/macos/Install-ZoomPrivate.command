#!/bin/sh
set -eu
cd "$(dirname "$0")"
/bin/sh ./install-zoom-private.sh
printf '\nDone. Press Return to close this window. '
read _ || true
