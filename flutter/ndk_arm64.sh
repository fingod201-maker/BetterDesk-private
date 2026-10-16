#!/usr/bin/env bash
set -euo pipefail

cargo ndk --platform 21 --target aarch64-linux-android build --locked --release
