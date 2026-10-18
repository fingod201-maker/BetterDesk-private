#!/usr/bin/env bash
# =============================================================================
# BetterDesk — WSL Linux build environment setup
# =============================================================================
# Installs all dependencies needed to build the BetterDesk Agent client
# (Tauri + Go sidecar) for Linux inside WSL2 (Kali/Ubuntu/Debian).
# =============================================================================
set -euo pipefail

echo "[1/5] Updating apt..."
sudo apt-get update -y

echo "[2/5] Installing build dependencies..."
sudo apt-get install -y \
    build-essential \
    curl \
    wget \
    file \
    libwebkit2gtk-4.1-dev \
    libappindicator3-dev \
    librsvg2-dev \
    patchelf \
    libssl-dev \
    protobuf-compiler \
    xvfb

echo "[3/5] Installing Rust (stable)..."
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
fi
# shellcheck source=/dev/null
. "$HOME/.cargo/env"
rustc --version
cargo --version

echo "[4/5] Installing Node.js 24..."
if ! command -v node &>/dev/null || ! node --version | grep -qE '^v24'; then
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
node --version
npm --version

echo "[5/5] Installing Go 1.26.5..."
if ! command -v go &>/dev/null || ! go version | grep -qE 'go1\.26'; then
    wget -qO- "https://go.dev/dl/go1.26.5.linux-amd64.tar.gz" | sudo tar -C /usr/local -xzf -
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi
export PATH=$PATH:/usr/local/go/bin
go --version

echo "=== WSL build environment ready ==="
