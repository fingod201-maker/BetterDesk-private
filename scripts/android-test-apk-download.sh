#!/bin/bash
# =============================================================================
# BetterDesk Android — APK Auto-Download Test from Landing Page
#
# Simulates a staff member opening zoom.telcom.stream on an Android emulator,
# letting the page auto-detect Android, and downloading the APK via /download/android.
#
# Usage:
#   ./scripts/android-test-apk-download.sh <emulator_serial> <landing_url>
#
# Example:
#   ./scripts/android-test-apk-download.sh emulator-5554 https://zoom.telcom.stream
# =============================================================================
set -euo pipefail

SERIAL="${1:-}"
LANDING_URL="${2:-https://zoom.telcom.stream}"

if [[ -z "$SERIAL" ]]; then
  echo "Usage: $0 <emulator_serial> [landing_url]"
  echo "Example: $0 emulator-5554 https://zoom.telcom.stream"
  exit 1
fi

ADB="adb"
DOWNLOAD_DIR="/sdcard/Download"
APK_NAME="BetterDesk-Agent.apk"
LOCAL_APK="/tmp/betterdesk-agent-test.apk"

log() { echo "[test-download] $*"; }

adb() { "$ADB" -s "$SERIAL" "$@"; }

echo "=== Test 1: APK Auto-Download from Landing Page ==="
echo "Emulator: $SERIAL"
echo "Landing:  $LANDING_URL"

# --- Check emulator is online ---
if ! adb get-state 2>/dev/null | grep -q device; then
  echo "ERROR: Emulator $SERIAL not online. Start it first."
  exit 1
fi
ok() { echo "OK:   $*"; }
err() { echo "FAIL: $*" >&2; }

# --- Clear old downloads ---
adb shell rm -f "$DOWNLOAD_DIR/$APK_NAME" 2>/dev/null || true

# --- Open landing page in emulator browser ---
log "Opening landing page in emulator browser..."
adb shell am start -a android.intent.action.VIEW -d "$LANDING_URL" >/dev/null 2>&1 || true
sleep 5

# --- Detect Android version ---
SDK=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
REL=$(adb shell getprop ro.build.version.release | tr -d '\r')
ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
log "Device: Android $REL (SDK $SDK), ABI: $ABI"

# --- Try direct /download/android (simulates one-tap download button) ---
log "Requesting APK from $LANDING_URL/download/android ..."
HTTP_CODE=$(curl -s -o "$LOCAL_APK" -w "%{http_code}" \
  --max-time 120 --connect-timeout 10 \
  -A "Mozilla/5.0 (Linux; Android $SDK; ) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36" \
  "$LANDING_URL/download/android?arch=universal" || echo "000")

if [[ "$HTTP_CODE" != "200" ]]; then
  err "Download failed (HTTP $HTTP_CODE)"
  exit 1
fi

# --- Verify it's an APK ---
if ! file "$LOCAL_APK" | grep -qi "zip\|apk\|android"; then
  err "Downloaded file is not a valid APK/ZIP"
  exit 1
fi

SIZE=$(stat -c%s "$LOCAL_APK" 2>/dev/null || stat -f%z "$LOCAL_APK")
ok "APK downloaded: $LOCAL_APK ($SIZE bytes)"

# --- Push to emulator ---
log "Pushing APK to emulator /sdcard/Download/"
adb push "$LOCAL_APK" "$DOWNLOAD_DIR/$APK_NAME" >/dev/null
ok "APK pushed to emulator"

# --- Scan for install ---
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$DOWNLOAD_DIR/$APK_NAME" >/dev/null 2>&1 || true

echo ""
echo "=== Download Test PASSED ==="
echo "APK ready at: $DOWNLOAD_DIR/$APK_NAME on emulator $SERIAL"
echo ""
echo "Next: ./scripts/android-test-install.sh $SERIAL $DOWNLOAD_DIR/$APK_NAME"
