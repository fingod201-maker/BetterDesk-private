#!/usr/bin/env bash
set -euo pipefail

cargo ndk --platform 21 --target armv7-linux-androideabi -o android/app/src/main/jniLibs build --locked --release
