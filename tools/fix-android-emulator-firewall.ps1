<#
.SYNOPSIS
    Configures Windows Firewall to allow Android Emulator ADB connections (port 5555).
    Fixes "cannot connect to 127.0.0.1:5555: connection refused" when emulator runs but adb can't attach.

.DESCRIPTION
    The Android emulator on Windows exposes its ADB endpoint on 127.0.0.1 (default 5554/5555).
    Windows Firewall can block inbound connections to this port, causing
    `adb connect 127.0.0.1:5555` to fail with "actively refused it (10061)".

    This script:
      1. Creates an inbound firewall rule for TCP 5555 (configurable)
      2. Reuses an already-running adb server; restarts it only when no device
         is attached (restarting adb while an emulator is running makes some
         emulator builds exit)
      3. Attempts to connect to the running emulator
      4. Verifies device appears in `adb devices`

    Run as Administrator. Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER AdbPort
    The ADB port the emulator uses (default 5555). Check emulator -port flag or AVD config.

.PARAMETER RuleName
    Firewall rule display name (default "Android Emulator ADB").

.PARAMETER Profile
    Firewall profiles to apply rule (default "Any" = Domain,Private,Public).

.PARAMETER ExcludePortRange
    Adds the port to the Hyper-V/WSL2 excluded port range registry so Windows
    stops reserving it. Requires a reboot to take effect.

.PARAMETER RestartEmulator
    If $true, attempts to gracefully restart the emulator via adb after rule creation.

.EXAMPLE
    .\fix-android-emulator-firewall.ps1 -AdbPort 5555 -RestartEmulator

.EXAMPLE
    .\fix-android-emulator-firewall.ps1 -AdbPort 5556 -Profile "Private,Public"
#>

param(
    [int]$AdbPort = 5555,
    [string]$RuleName = "Android Emulator ADB",
    [string]$Profile = "Any",
    [switch]$RestartEmulator,
    [switch]$ForceRecreate,
    [switch]$ExcludePortRange
)

# Require Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell -> Run as Administrator."
    exit 1
}

$ErrorActionPreference = "Stop"

# Locate adb (works on Windows PowerShell 5.1 as well)
$androidHome = $env:ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($androidHome)) {
    $androidHome = Join-Path $env:LOCALAPPDATA "Android\Sdk"
}
$adbPath = Join-Path $androidHome "platform-tools\adb.exe"
if (-not (Test-Path $adbPath)) {
    $fallback = Join-Path $env:USERPROFILE "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $fallback) {
        $adbPath = $fallback
        $androidHome = Split-Path (Split-Path $fallback -Parent) -Parent
    }
}
if (-not (Test-Path $adbPath)) {
    Write-Error "adb.exe not found (checked ANDROID_HOME and the default SDK path). Set ANDROID_HOME or install Android SDK Platform-Tools."
    exit 1
}
Write-Host "Using adb: $adbPath"

# 1. Create / update firewall rule

$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing -and $ForceRecreate) {
    Write-Host "Removing existing rule '$RuleName'..."
    Remove-NetFirewallRule -InputObject $existing -Confirm:$false
    $existing = $null
}

if (-not $existing) {
    Write-Host "Creating firewall rule '$RuleName' for TCP port $AdbPort on profile(s) $Profile..."
    # Do NOT scope -Program to adb.exe: the emulator process (qemu-system-*)
    # owns the listening socket, so a program-scoped rule never matches.
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Description "Allow inbound ADB connections from the Android Emulator (localhost:$AdbPort)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $AdbPort `
        -Action Allow `
        -Profile $Profile `
        -Enabled True `
        | Out-Null
    Write-Host "  [OK] Rule created."
} else {
    Write-Host "Rule '$RuleName' already exists. Use -ForceRecreate to update."
}

if ($ExcludePortRange) {
    Write-Host "Excluding TCP $AdbPort from the Hyper-V/WSL2 reserved port range..."
    netsh interface ipv4 add excludedportrange protocol=tcp startport=$AdbPort numberofports=1 | Out-Null
    Write-Host "  [OK] Added. Reboot for the reservation change to take effect."
}

# 2. Reuse a healthy adb server; restarting it can terminate running emulators

$connected = @(& $adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match '\s+device\s*$' })
if ($connected.Count -eq 0) {
    Write-Host "No attached device - restarting adb server..."
    & $adbPath kill-server 2>$null
    Start-Sleep 1
    & $adbPath start-server 2>$null | Out-Null
    Start-Sleep 1
} else {
    Write-Host "adb server healthy ($($connected.Count) device(s) attached); not restarting it."
}

# 3. Connect to emulator over TCP (also validates the firewall rule)

Write-Host "Connecting to emulator at 127.0.0.1:$AdbPort..."
$connectResult = (& $adbPath connect "127.0.0.1:$AdbPort" 2>&1) -join ' '
Write-Host "  $connectResult"

# 4. Verify device

Write-Host "Verifying device appears in adb devices..."
$deviceLines = @(& $adbPath devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' })
$deviceLines | ForEach-Object { Write-Host "  $_" }

$attached = @($deviceLines | Where-Object { $_ -match '\s+device\s*$' })
if ($attached.Count -eq 0) {
    Write-Warning "No device in 'device' state yet. Common causes:"
    Write-Warning "  - Emulator not fully booted (wait for 'Boot completed' in the emulator log)"
    Write-Warning "  - Emulator started with a different -port (check the AVD config or emulator -port flag)"
    Write-Warning "  - Hyper-V / WSL2 port conflict (run this script with -ExcludePortRange, then reboot)"
    Write-Warning "  - Third-party firewall/antivirus blocking localhost loopback"
    exit 1
}

Write-Host "[OK] Android emulator connected successfully!"

# 5. Optional: restart emulator to ensure clean state

if ($RestartEmulator) {
    Write-Host "Rebooting emulator via adb..."
    & $adbPath reboot
    Write-Host "Waiting for reboot..."
    & $adbPath wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done'
    Write-Host "Emulator rebooted. Re-connecting..."
    & $adbPath connect "127.0.0.1:$AdbPort" | Out-Null
    & $adbPath devices
}

Write-Host ""
Write-Host "Done. You can now run Flutter/Dart apps or install APKs:"
Write-Host "  & '$adbPath' install -r distro\clients\android\zoom-private-universal-release.apk"
