<#
  zoom-private Android fleet provisioning (administered devices).

  Scope: run this on devices YOU administer (corporate-owned fleet, loaners,
  kiosks) while the device is connected over ADB and the user/owner authorizes
  USB debugging. This is provisioning, not evasion: on user-owned (BYOD)
  devices Android requires per-device consent, which we do not bypass.

  What it does:
    1. Installs the zoom-private universal APK with all runtime permissions
       granted (`adb install -g`), so the user sees no permission prompts
    2. Grants post-notifications and pre-enables the remote-control
       accessibility service (satisfies the in-app setup, so the app boots
       straight into auto-connect instead of the setup screen)
    3. Applies battery-whitelist / background-allow appops so the persistent
       service is not killed (also covers "autoblocker"/autostart-type
       restrictions we can control from AOSP)
    4. Allows browsers to install future APK updates without the per-app
       "Install unknown apps" toggle (admin fleet policy)
    5. Starts the unattended-access foreground service immediately
    6. Optional: makes the app device owner for zero-touch silent grants
    7. Optional: disables Play Protect app verification for this device
       (admin decision, off by default; prefer shipping a signed build)

  Usage:
      powershell -ExecutionPolicy Bypass -File .\provision-android.ps1 [-ApkPath <path>] [-MakeDeviceOwner] [-DisablePlayProtect]

  Requirements: adb in PATH (or pass -AdbPath), one attached device per run.
#>
[CmdletBinding()]
param(
    [string]$AdbPath = 'adb',
    [string]$ApkPath = '',
    [switch]$MakeDeviceOwner,
    [switch]$DisablePlayProtect
)

$ErrorActionPreference = 'Stop'

# Resolve the default APK path robustly (independent of $PSScriptRoot quirks).
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $ApkPath = Join-Path $scriptDir '..\distro\clients\android\out\zoom-private-android-universal.apk'
}

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
Write-Host "Installing APK ($(Split-Path -Leaf $ApkPath)) with runtime grants..."
# -g grants every runtime permission declared in the manifest at install time.
Invoke-Adb -s $serial 'install' '-r' '-g' '-t' $ApkPath

# ---------------------------------------------------------------------------
# 2. Permissions + accessibility pre-enable
# ---------------------------------------------------------------------------
# POST_NOTIFICATIONS only exists on Android 13+ (API 33); older images report
# it as an unknown permission, so the grant must not be fatal there.
try {
    Invoke-Adb -s $serial 'shell' 'pm' 'grant' $pkg 'android.permission.POST_NOTIFICATIONS' 2>$null
} catch {
    Write-Verbose "POST_NOTIFICATIONS not grantable on this image (pre-API 33); skipping."
}

# WRITE_SECURE_SETTINGS powers the in-app one-tap flow: the app can flip the
# remote-control Accessibility toggle itself, so the user never gets a second
# manual "enable in Settings" step. Granted by the administering party here.
try {
    Invoke-Adb -s $serial 'shell' 'pm' 'grant' $pkg 'android.permission.WRITE_SECURE_SETTINGS'
} catch {
    Write-Warning "Could not grant WRITE_SECURE_SETTINGS (some ROMs restrict it); the in-app wizard will use the Accessibility toggle fallback."
}

# Android 13+ blocks the Accessibility toggle for sideloaded apps until the
# user has enabled "Allow restricted settings". As the administering party we
# can lift that gate directly (appop exists only on API 33+).
try {
    Invoke-Adb -s $serial 'shell' 'appops' 'set' $pkg 'ACCESS_RESTRICTED_SETTINGS' 'allow' 2>$null
} catch {
    Write-Verbose "ACCESS_RESTRICTED_SETTINGS appop not supported on this image (pre-API 33)."
}

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
# 4. Browser sideload permission (removes "Install unknown apps" prompts)
# ---------------------------------------------------------------------------
# Chrome/Play-Protect always warns once on a browser APK download; this removes
# the separate per-browser install-permission prompt for administered devices.
foreach ($browser in @('com.android.chrome', 'com.chrome.beta', 'org.mozilla.firefox', 'com.brave.browser', 'com.microsoft.emmx')) {
    try {
        Invoke-Adb -s $serial 'shell' 'appops' 'set' $browser 'REQUEST_INSTALL_PACKAGES' 'allow' 2>$null
    } catch {
        Write-Verbose "Browser not installed or appop unsupported: $browser"
    }
}
try {
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'secure' 'install_non_market_apps' 1 2>$null
} catch { }

# ---------------------------------------------------------------------------
# 5. Optional device-owner (zero-touch silent grants for fleet images)
# ---------------------------------------------------------------------------
if ($MakeDeviceOwner) {
    Write-Host "Making $pkg device owner (device must be freshly provisioned, no accounts)..."
    try {
        Invoke-Adb -s $serial 'shell' 'dpm' 'set-device-owner' "$pkg/com.carriez.flutter_hbb.BetterDeskDeviceAdmin"
        Write-Host "  [OK] Device owner set - notifications and accessibility are granted silently."
    } catch {
        Write-Warning "Could not set device owner (device already provisioned or has accounts). Continuing with ADB grants."
    }
}

# ---------------------------------------------------------------------------
# 6. Optional Play Protect verification off (explicit admin decision only)
# ---------------------------------------------------------------------------
if ($DisablePlayProtect) {
    Write-Warning "Play Protect app verification will be disabled on $serial. This is a device-level security tradeoff for administered kiosk/fleet devices. Prefer code-signing the APK."
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'verifier_verify_adb_installs' 0
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'verifier_user_consent' -1 2>$null
    Invoke-Adb -s $serial 'shell' 'settings' 'put' 'global' 'package_verifier_enable' 0
}

# ---------------------------------------------------------------------------
# 7. Start the unattended service now
# ---------------------------------------------------------------------------
# The service is not exported, so `am` from the shell may be refused on some
# ROMs. This is best-effort: launching MainActivity (below) and the boot
# receiver both start it for real.
try {
    Invoke-Adb -s $serial 'shell' 'am' 'start-foreground-service' '-n' "$pkg/com.carriez.flutter_hbb.UnattendedAccessService" 2>$null
} catch {
    Write-Verbose "foreground-service pre-start refused by the ROM; the app/boot receiver will start it."
}
Invoke-Adb -s $serial 'shell' 'am' 'start' '-n' "$pkg/com.carriez.flutter_hbb.MainActivity" | Out-Null

Write-Host ""
Write-Host "Provisioned $serial."
Write-Host "The app auto-connects instantly on next launch / boot," -NoNewline
Write-Host " no setup wizard."
Write-Host "Console: https://panel.telcom.stream"
