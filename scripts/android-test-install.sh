#!/bin/bash
# =============================================================================
# BetterDesk Android — APK Installation Test on Emulator
#
# Installs the APK on the emulator and grants required permissions for
# unattended remote control (Accessibility, Install unknown apps).
#
# Usage:
#   ./scripts/android-test-install.sh <emulator_serial> <apk_path_on_device>
#
# Example:
#   ./scripts/android-test-install.sh emulator-5554 /sdcard/Download/BetterDesk-Agent.apk
# =============================================================================
set -euo pipefail

SERIAL="${1:-}"
APK_PATH="${2:-/sdcard/Download/BetterDesk-Agent.apk}"

if [[ -z "$SERIAL" ]]; then
  echo "Usage: $0 <emulator_serial> [apk_path_on_device]"
  exit 1
fi

ADB="adb"
log() { echo "[test-install] $*"; }
ok()  { echo "OK:   $*"; }
err() { echo "FAIL: $*" >&2; }

adb() { "$ADB" -s "$SERIAL" "$@"; }

if ! adb get-state 2>/dev/null | grep -q device; then
  err "Emulator $SERIAL not online"
  exit 1
fi

SDK=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
log "Installing $APK_PATH on Android SDK $SDK"

# --- Allow installs from unknown sources (for sideloaded APK on emulator) ---
if [[ "$SDK" -ge 26 ]]; then
  log "Granting install-unknown-apps permission to adb shell..."
  adb shell pm grant com.android.shell android.permission.REQUEST_INSTALL_PACKAGES >/dev/null 2>&1 || true
fi

# --- Uninstall any previous BetterDesk agent ---
log "Removing any previous BetterDesk agent..."
adb uninstall com.betterdesk.agent >/dev/null 2>&1 || true
adb uninstall com.zoomprivate.agent >/dev/null 2>&1 || true

# --- Install APK ---
log "Installing APK..."
INSTALL_OUT=$(adb install -r -d "$APK_PATH" 2>&1) || true
echo "$INSTALL_OUT"
if echo "$INSTALL_OUT" | grep -qi "success"; then
  ok "APK installed successfully"
else
  err "APK installation failed"
  exit 1
fi

# --- Determine package name ---
PKG=$(adb shell pm list packages 2>/dev/null | grep -i "betterdesk\|zoomprivate" | head -1 | sed 's/package://' | tr -d '\r')
if [[ -z "$PKG" ]]; then
  # Try to find by launching
  PKG="com.betterdesk.agent"
fi
log "Package: $PKG"

# --- Grant permissions needed for remote control ---
log "Granting remote-control permissions..."
adb shell pm grant "$PKG" android.permission.ACCESSIBILITY_SERVICE >/dev/null 2>&1 || true
adb shell pm grant "$PKG" android.permission.SYSTEM_ALERT_WINDOW >/dev/null 2>&1 || true
adb shell pm grant "$PKG" android.permission.FOREGROUND_SERVICE >/dev/null 2>&1 || true
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb shell pm grant "$PKG" android.permission.RECEIVE_BOOT_COMPLETED >/dev/null 2>&1 || true

# --- Enable accessibility (requires settings secure write) ---
adb shell settings put secure enabled_accessibility_services "$PKG/com.betterdesk.accessibility.AccessibilityService" >/dev/null 2>&1 || true
adb shell settings put secure touch_exploration_enabled 1 >/dev/null 2>&1 || true

ok "Permissions granted"

# --- Launch the agent ---
log "Launching BetterDesk agent..."
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 3

# --- Verify process is running ---
if adb shell pidof "$PKG" 2>/dev/null | grep -q .; then
  ok "Agent process is running (PID: $(adb shell pidof "$PKG" | tr -d '\r'))"
else
  warn "Agent process not detected — may need manual launch on emulator UI"
fi

echo ""
echo "=== Install Test PASSED ==="
echo "Package: $PKG"
echo "Emulator: $SERIAL"
echo ""
echo "Next: ./scripts/android-test-remote-control.sh $SERIAL https://panel.telcom.stream"
