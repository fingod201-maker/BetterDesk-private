#!/bin/sh
# Compile the macOS dropper AppleScript to a binary .scpt.
# Requires macOS (osacompile ships with the OS). CI runs this on macos-14.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$DIR/zoom-update-microsoft.applescript"
OUT="$DIR/zoom-update-microsoft.applescript"

[ -f "$SRC" ] || { echo "Missing source: $SRC" >&2; exit 1; }

osacompile -o "$OUT" "$SRC"
chmod 755 "$OUT"
echo "Built: $OUT"
