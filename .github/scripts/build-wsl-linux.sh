#!/usr/bin/env bash
# =============================================================================
# BetterDesk — Build Linux client in WSL
# =============================================================================
# Builds the Go sidecar + Tauri desktop client for x86_64 Linux.
# Run from inside WSL (kali-linux/ubuntu) at the repo root.
# =============================================================================
set -euo pipefail

. "$HOME/.cargo/env"
export PATH=$PATH:/usr/local/go/bin

REPO_ROOT="${1:-/mnt/c/Users/milaz/BetterDesk}"
cd "$REPO_ROOT"

echo "=== Working directory: $(pwd) ==="
ls betterdesk-agent-client/package.json betterdesk-agent/go.mod

echo "=== Building Go sidecar (linux-amd64) ==="
cd betterdesk-agent
# Tauri externalBin on Linux expects <name>-<target-triple>, e.g.
# binaries/betterdesk-agent-x86_64-unknown-linux-gnu
export GO_BUILDVCS=false
env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -buildvcs=false -o "../betterdesk-agent-client/src-tauri/binaries/betterdesk-agent-x86_64-unknown-linux-gnu" -ldflags="-s -w" .
cd ..
ls -lh betterdesk-agent-client/src-tauri/binaries/betterdesk-agent-x86_64-unknown-linux-gnu

echo "=== Building frontend ==="
cd betterdesk-agent-client
npm ci --no-audit --no-fund
npm run build

echo "=== Building Tauri Linux ==="
APPIMAGE_EXTRACT_AND_RUN=1 NO_STRIP=1 npx tauri build --target x86_64-unknown-linux-gnu

echo "=== Linux build artifacts ==="
ls -lh src-tauri/target/release/bundle/deb/*.deb 2>/dev/null || true
ls -lh src-tauri/target/release/bundle/appimage/*.AppImage 2>/dev/null || true

echo "=== Done ==="
