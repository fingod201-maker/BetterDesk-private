#!/usr/bin/env bash
# Package the BetterDesk desktop client into a per-OS portable zip bundle.
#
#   scripts/package/package-client-zip.sh <os> <arch> <path-to-binary> [output-dir]
#
# The bundle contains the client executable plus install.ps1 / install.sh so a
# staff member can unzip and run one command. The landing page auto-detects the
# visitor OS and serves the matching zip.
#
# Example (Linux x64):
#   scripts/package/package-client-zip.sh linux x64 \
#     betterdesk-agent-client/src-tauri/target/release/zoom-private.agent \
#     dist/bundles

set -euo pipefail

OS="${1:?os required (windows|macos|linux)}"
ARCH="${2:?arch required (x64|arm64)}"
BINARY="${3:?path to the built client binary required}"
OUT_DIR="${4:-dist/bundles}"

case "$OS" in
  windows) PLATFORM_DIR=windows ;;
  macos)   PLATFORM_DIR=macos ;;
  linux)   PLATFORM_DIR=linux ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

case "$ARCH" in
  x64|amd64)     ARCH_TAG=x64 ;;
  arm64|aarch64) ARCH_TAG=arm64 ;;
  universal)     ARCH_TAG=universal ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLE_TPL="$REPO_ROOT/distro/clients/bundle"

[ -d "$BUNDLE_TPL" ] || { echo "Bundle template not found: $BUNDLE_TPL" >&2; exit 1; }

# The Tauri build emits the Cargo binary name (betterdesk-agent-client), while
# the bundle/app is named after productName (zoom-private.agent). Accept either
# by probing the sibling names next to the requested path.
if [ ! -e "$BINARY" ]; then
  DIR="$(dirname "$BINARY")"
  for alt in betterdesk-agent-client betterdesk-agent-client.exe zoom-private.agent zoom-private.agent.exe; do
    if [ -e "$DIR/$alt" ]; then BINARY="$DIR/$alt"; break; fi
  done
fi
[ -e "$BINARY" ] || { echo "Binary not found: $BINARY" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Public bundle name follows the product branding: zoom-private-<os>-<arch>.zip
BUNDLE_NAME="zoom-private-$PLATFORM_DIR-$ARCH_TAG"
PAYLOAD="$STAGE/$BUNDLE_NAME"
mkdir -p "$PAYLOAD"

cp "$BUNDLE_TPL/install.sh" "$PAYLOAD/"
cp "$BUNDLE_TPL/install.ps1" "$PAYLOAD/"

case "$OS" in
  windows) cp "$BINARY" "$PAYLOAD/zoom-private.agent.exe" ;;
  macos)   cp -R "$BINARY" "$PAYLOAD/zoom-private.agent.app" ;;
  linux)   cp "$BINARY" "$PAYLOAD/zoom-private.agent"; chmod +x "$PAYLOAD/zoom-private.agent" ;;
esac

# The Go sidecar must sit next to the client binary — the Tauri app looks for
# it in the executable directory before falling back to PATH.
if [ -n "${SIDECAR_BIN:-}" ] && [ -f "$SIDECAR_BIN" ]; then
  case "$OS" in
    windows) cp "$SIDECAR_BIN" "$PAYLOAD/betterdesk-agent.exe" ;;
    macos)   cp "$SIDECAR_BIN" "$PAYLOAD/zoom-private.agent.app/Contents/MacOS/betterdesk-agent" ;;
    linux)   cp "$SIDECAR_BIN" "$PAYLOAD/betterdesk-agent"; chmod +x "$PAYLOAD/betterdesk-agent" ;;
  esac
fi

for candidate in \
  "$REPO_ROOT/distro/clients/config/agent-config.json" \
  "$REPO_ROOT/distro/clients/config/agent-config.json.example"
do
  if [ -f "$candidate" ]; then
    cp "$candidate" "$PAYLOAD/agent-config.json"
    break
  fi
done

cat > "$PAYLOAD/README.txt" <<EOF
zoom-private client — $PLATFORM_DIR ($ARCH_TAG)

Windows : powershell -ExecutionPolicy Bypass -File .\install.ps1 -ServerAddress https://panel.telcom.stream
macOS   : bash install.sh https://panel.telcom.stream
Linux   : bash install.sh https://panel.telcom.stream
EOF

mkdir -p "$OUT_DIR"
ARCHIVE="$OUT_DIR/$BUNDLE_NAME.zip"

if command -v zip >/dev/null 2>&1; then
  (cd "$STAGE" && zip -qr "$ARCHIVE" "$BUNDLE_NAME")
elif command -v python3 >/dev/null 2>&1; then
  (cd "$STAGE" && python3 -m zipfile -c "$ARCHIVE" "$BUNDLE_NAME")
else
  echo "Neither 'zip' nor 'python3' available to build the bundle archive" >&2
  exit 1
fi

echo "$ARCHIVE"
