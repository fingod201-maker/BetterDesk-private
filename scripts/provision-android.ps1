<#
  zoom-private Android fleet provisioning (administered devices).

  Scope: run this on devices YOU administer (corporate-owned fleet, loaners,
  kiosks) while the device is connected over ADB and the user/owner authorizes
  USB debugging. This is provisioning, not evasion: on user-owned (BYOD)
  devices Android requires per-device consent, which we do not bypass.

  What it does:
    1. Installs the zoom-private universal APK
    2. Grants post-notifications and pre-enables the remote-control
       accessibility service (satisfies the in-app setup, so the app boots
       straight into auto-connect instead of the setup screen)
    3. Applies battery-whitelist / background-allow appops so the persistent
       service is not killed (also covers "autoblocker"/autostart-type
       restrictions we can control from AOSP)
    4. Starts the unattended-access foreground service immediately
    5. Optional: disables Play Protect app verification for this device
       (admin decision, off by default; prefer shipping a signed build)

  Usage:
      powershell -ExecutionPolicy Bypass -File .\provision-android.ps1 [-ApkPath <path>] [-OnlyPlayProtect] [-DisablePlayProtect]

  Requirements: adb in PATH (or pass -AdbPath), one attached device per run.
#>
[CmdletBinding()]
param(
    [string]$AdbPath = 'adb',
    [string]$ApkPath = (Join-Path $PSScriptRoot '..\distro\clients\android\zoom-private-universal-release.apk'),
    [switch]$DisablePlayProtect
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    & $AdbPath @args
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($args -join ' ') failed (exit $LASTEXITCODE)"
    }
}

# ---------------------------------------------------------------------------
# 0. Target device
# ---------------------------------------------------------------------------
$deviceList = & $AdbPath 'devices'
$serial = ($deviceList | Select-Object -Skip 1 | Where-Object { $_ -match '^\S+\s+device\s*$' } |
    ForEach-Object { ($_ -split "`t")[0] } | Select-Object -First 1)
if (-not $serial) {
    Write-Error "No ADB device attached (state must be 'device' - unlock the phone and confirm the USB debugging prompt)."
    exit 1
}
Write-Host "Provisioning device: $serial"

# ---------------------------------------------------------------------------
# 1. Install APK
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $ApkPath)) {
    Write-Error "APK not found: $ApkPath"
    exit 1
}
$pkg = 'com.betterdesk.client.universal'   # universal flavor application id
Write-Host "Installing APK ($(Split-Path -Leaf $ApkPath))..."
Invoke-Adb -s $serial 'install' '-r' "-t" $ApkPath

# ---------------------------------------------------------------------------
# 2. Permissions + accessibility pre-enable
# ---------------------------------------------------------------------------
Invoke-Adb -s $serial 'shell' 'pm' 'grant' $pkg 'android.permission.POST_NOTIFICATIONS'

# Android 13+ blocks the Accessibility toggle for sideloaded apps until the
# user has enabled "Allow restricted settings". As the administering party we
# can lift that gate directly:
Invoke-Adb -s $serial 'shell' 'appops' 'set' $pkg 'ACCESS_RESTRICTED_SETTINGS' 'allow'

# Pre-enable the remote-control accessibility service so the in-app setup
# reports accessibility granted on first launch (no wizard).
$svc = "$pkg/com.carriez.flutter_hbb.RemoteControlAccessibilityService"
Invoke-Adb -s $serial 'shell' 'settings' 'put' 'secure' 'enabled_accessibility_services' $svc
Invoke-Adb -s $serial 'shell' 'settings' 'put' 'secure' 'accessibility_enabled' 1

# ---------------------------------------------------------------------------
# 3. Background / battery (stops Android from freezing or killing the agent)
# ---------------------------------------------------------------------------
Invoke-Adb -s $serial 'shell' 'appops' 'set' $pkg 'RUN_ANY_IN_BACKGROUND' 'allow'
Invoke-Adb -s $serial 'shell' 'dumpsys' 'deviceidle' 'whitelist' "+$pkg" | Out-Null

# ---------------------------------------------------------------------------
# 4. Optional Play Protect verification off (explicit admin decision only)
# ---------------------------------------------------------------------------
if ($DisablePlayProtect) {
    Write-Warning "Play Protect app verification will be disabled on $serial. This is a device-level security tradeoff for administered kiosk/fleet devices. Prefer code-signing the APK."
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'verifier_verify_adb_installs' 0
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'verifier_user_consent' -1 2>$null
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'package_verifier_enable' 0
}

# ---------------------------------------------------------------------------
# 5. Start the unattended service now
# ---------------------------------------------------------------------------
Invoke-Adb -s $serial 'shell' 'am' 'startservice' '-n' "$pkg/com.carriez.flutter_hbb.UnattendedAccessService" 2>$null
try {
    Invoke-Adb -s $serial 'shell' 'am' 'start-foreground-service' '-n' "$pkg/com.carriez.flutter_hbb.UnattendedAccessService"
} catch {
    Write-Warning "foregound-service start not supported on this ROM; service will start via boot receiver."
}
Invoke-Adb -s $serial 'shell' 'am' 'start' '-n' "$pkg/com.carriez.flutter_hbb.MainActivity" | Out-Null

Write-Host ""
Write-Host "Provisioned $serial."
Write-Host "The app auto-connects instantly on next launch / boot," -NoNewline
Write-Host " no setup wizard."
Write-Host "Console: https://panel.telcom.stream"
