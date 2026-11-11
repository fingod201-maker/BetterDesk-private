#!/bin/bash
# =============================================================================
# BetterDesk Android Emulator Setup
# Creates AVDs for testing across modern Android versions (API 33/34/35).
#
# Prerequisites:
#   - Android SDK installed ($ANDROID_HOME or $ANDROID_SDK_ROOT)
#   - sdkmanager, emulator, avdmanager on PATH
#   - Hardware acceleration (KVM/HAXM/HVF) recommended
#
# Usage:
#   export ANDROID_HOME=$HOME/Android/Sdk
#   ./scripts/android-emulator-setup.sh
# =============================================================================
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
EMULATOR="$ANDROID_HOME/emulator/emulator"

log() { echo "[avd] $*"; }

if [[ ! -x "$SDKMANAGER" ]]; then
  echo "ERROR: sdkmanager not found at $SDKMANAGER"
  echo "Set ANDROID_HOME to your Android SDK location."
  exit 1
fi

echo "=== Android SDK: $ANDROID_HOME ==="

# --- Ensure required components are installed ---
echo "Installing required SDK components..."
"$SDKMANAGER" "platform-tools" "emulator" "platforms;android-35" "platforms;android-34" "platforms;android-33"
"$SDKMANAGER" "system-images;android-35;google_apis;arm64-v8a"
"$SDKMANAGER" "system-images;android-34;google_apis;arm64-v8a"
"$SDKMANAGER" "system-images;android-33;google_apis;arm64-v8a"

# --- AVD definitions ---
declare -A AVDS=(
  ["BD_Android15_API35"]="system-images;android-35;google_apis;arm64-v8a"
  ["BD_Android14_API34"]="system-images;android-34;google_apis;arm64-v8a"
  ["BD_Android13_API33"]="system-images;android-33;google_apis;arm64-v8a"
)

for avd in "${!AVDS[@]}"; do
  system_img="${AVDS[$avd]}"
  if "$AVDMANAGER" list avd | grep -q "^Name: $avd$"; then
    log "AVD '$avd' already exists — skipping creation"
  else
    log "Creating AVD '$avd' ($system_img)..."
    echo "no" | "$AVDMANAGER" create avd \
      -n "$avd" \
      -k "$system_img" \
      -g google_apis \
      -b arm64-v8a \
      -c 2048M \
      --device "pixel_6"
    log "AVD '$avd' created"
  fi
done

echo ""
echo "=== AVDs ready ==="
"$AVDMANAGER" list avd

echo ""
echo "To launch an emulator (run in a separate terminal):"
echo "  $EMULATOR @BD_Android15_API35 -gpu host -camera-backend none"
echo ""
echo "Then run the APK download/install test:"
echo "  ./scripts/android-test-apk-download.sh <emulator_serial> <landing_url>"
echo "  ./scripts/android-test-install.sh <emulator_serial> <apk_path>"
echo "  ./scripts/android-test-remote-control.sh <emulator_serial> <panel_url>"
