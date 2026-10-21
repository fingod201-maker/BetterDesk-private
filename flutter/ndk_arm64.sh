#!/usr/bin/env bash
set -euo pipefail

cargo ndk --platform 21 --target aarch64-linux-android -o android/app/src/main/jniLibs build --locked --release
