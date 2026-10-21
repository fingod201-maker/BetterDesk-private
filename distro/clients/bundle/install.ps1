<#
  zoom-private client portable installer (Windows) - Zero-Config Edition.

  Run after unzipping the bundle:
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -ServerAddress https://panel.telcom.stream [-UnattendedPassword <pw>] [-Silent] [-InstallDir <path>] [-ConfigDir <path>]

  - Single visible elevation (UAC) is the only interaction the user makes
  - Installs the zoom-private agent as a native Windows service via sc.exe,
    running SYSTEM with automatic start (survives reboot and logout)
  - Configures automatic service recovery (restart on failure)
  - Opens firewall policy for the agent (inbound + outbound)
  - Writes pre-seeded agent-config.json (server / CDAP / console URLs, server
    key, unattended mode, shared permanent unattended password)
  - Starts the service and launches the tray app in the user's session

  Unattended password policy: the value passed via -UnattendedPassword (or the
  ZOOM_PRIVATE_UNATTENDED_PASSWORD environment variable) is the ONE shared
  permanent password baked into this deployment. If neither is set, a random
  per-device password is generated and still synced to the console.
#>
[CmdletBinding()]
param(
    [string]$ServerAddress = 'https://panel.telcom.stream',
    [string]$UnattendedPassword = $env:ZOOM_PRIVATE_UNATTENDED_PASSWORD,
    [string]$InstallDir = "$env:ProgramFiles\zoom-private",
    [string]$ConfigDir = "$env:ProgramData\zoom-private\agent",
    [switch]$Silent,
    [switch]$NoAutostart,
    [switch]$NoLaunch,
    [switch]$ForceReinstall
)

$ErrorActionPreference = 'Stop'

# =========================================================================
# Helper: Ensure running as Administrator (auto-elevate if needed)
# =========================================================================
function Ensure-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $argList = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -ServerAddress `"$ServerAddress`" -InstallDir `"$InstallDir`" -ConfigDir `"$ConfigDir`" -UnattendedPassword `"$UnattendedPassword`" $($Silent.IsPresent ? '-Silent' : '') $($NoAutostart.IsPresent ? '-NoAutostart' : '') $($NoLaunch.IsPresent ? '-NoLaunch' : '') $($ForceReinstall.IsPresent ? '-ForceReinstall' : '')"
        if ($Silent) {
            Write-Warning "Re-launching as Administrator..."
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
            exit 0
        } else {
            Write-Error "This installer requires Administrator privileges. Re-run with -Silent or run PowerShell as Administrator."
            exit 1
        }
    }
}
Ensure-Admin

$svcName       = 'zoom-private-agent'
$svcDisplay    = 'zoom-private Agent (Service)'
$fwRuleName    = 'zoom-private Agent'

# =========================================================================
# Force reinstall cleanup
# =========================================================================
if ($ForceReinstall) {
    Write-Host "Force reinstall requested - cleaning up existing installation..."
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    sc.exe delete $svcName | Out-Null
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    $runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Remove-ItemProperty -Path $runKey -Name 'BetterDeskAgent' -ErrorAction SilentlyContinue
}

Ensure-Admin

# =========================================================================
# Locate client executable in the bundle
# =========================================================================
$bundleDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @('zoom-private.agent.exe', 'betterdesk-agent-client.exe', 'BetterDesk Client.exe')

$client = $null
foreach ($name in $candidates) {
    $p = Join-Path $bundleDir $name
    if (Test-Path -LiteralPath $p) { $client = $p; break }
}
if (-not $client) {
    $found = Get-ChildItem -LiteralPath $bundleDir -Filter '*.exe' -File |
        Where-Object { $_.Name -notmatch '^(install|unins|setup|nssm|betterdesk-agent\.exe)' } |
        Select-Object -First 1
    if ($found) { $client = $found.FullName }
}
if (-not $client) {
    Write-Error "Client executable not found in $bundleDir"
    exit 1
}

Write-Host "Installing client: $client"

$InstallDir = $InstallDir.TrimEnd('\')
$ConfigDir  = $ConfigDir.TrimEnd('\')

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

# =========================================================================
# Stop any running client/sidecar
# =========================================================================
foreach ($proc in @('zoom-private.agent', 'betterdesk-agent-client', 'betterdesk-agent', 'zoom-private-agent')) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Stopping running process: $($_.ProcessName) (pid $($_.Id))"
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { }
    }
}
Start-Sleep -Milliseconds 800

# Stop existing service (pre-upgrade) before replacing binaries
Start-Service -Name $svcName -ErrorAction SilentlyContinue | Out-Null
Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# =========================================================================
# Copy client binary + CDAP sidecar
# =========================================================================
$target = Join-Path $InstallDir (Split-Path -Leaf $client)
Copy-Item -LiteralPath $client -Destination $target -Force

foreach ($extra in @('betterdesk-agent.exe')) {
    $src = Join-Path $bundleDir $extra
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $extra) -Force
    }
}

# =========================================================================
# Firewall policy: allow the agent both directions (inbound session +
# outbound API/CDAP), program-scoped
# =========================================================================
try {
    if (Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $fwRuleName | Out-Null
    }
    New-NetFirewallRule -DisplayName $fwRuleName -Direction Inbound -Action Allow -Program $target `
        -Enabled True -Profile Any -Description 'zoom-private Remote Access Agent (inbound)' | Out-Null
    New-NetFirewallRule -DisplayName "$fwRuleName Out" -Direction Outbound -Action Allow -Program $target `
        -Enabled True -Profile Any -Description 'zoom-private Remote Access Agent (outbound API/CDAP)' | Out-Null
    Write-Host "Firewall rules created (inbound + outbound)."
} catch {
    Write-Warning "Could not create firewall rules (may need manual setup): $_"
}

# =========================================================================
# Write agent-config.json (zero-config: all URLs pre-seeded)
# =========================================================================
if (-not $UnattendedPassword) {
    # No shared password provided: generate a strong per-device password.
    $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new(24); $rng.GetBytes($bytes)
    $UnattendedPassword = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

$configPath = Join-Path $ConfigDir 'agent-config.json'
$config = [pscustomobject]@{
    server_address       = 'https://api.telcom.stream'
    api_url              = 'https://api.telcom.stream/api'
    cdap_url             = 'wss://cdap.telcom.stream/cdap'
    cdap_port            = 443
    console_url          = 'https://panel.telcom.stream'
    server_key           = 'q8UeY1D2/XMe8GddEW7mBoK5KaGQFUYEBn6yFqtRgYA='
    api_key              = ''
    device_id            = ''
    device_name          = ''
    auth_token           = ''
    registered           = $false
    allow_screen_capture = $true
    access_mode          = 'unattended'
    require_consent      = $false
    allow_terminal       = $true
    allow_file_browser   = $true
    allow_clipboard      = $true
    auto_start_sidecar   = $true
    video_codec          = 'auto'
    hw_accel             = 'auto'
    autostart            = -not $NoAutostart.IsPresent
    start_minimized      = $true
    language             = 'en'
    unattended_password  = $UnattendedPassword
    enforce_tls          = $true
    server_cert_pin      = ''
    settings_lock        = [pscustomobject]@{
        enabled         = $false
        master_password = ''
    }
}

$json = $config | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Config written: $configPath"

# =========================================================================
# Install as native SYSTEM service via sc.exe
# =========================================================================
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Removing existing service..."
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    sc.exe delete $svcName | Out-Null
    Start-Sleep -Seconds 1
}

Write-Host "Installing SYSTEM service via sc.exe..."
$binPath = "`"$target`" --autostart"
sc.exe create $svcName binPath= $binPath obj= 'LocalSystem' start= auto displayname= $svcDisplay | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "sc.exe create failed (exit $LASTEXITCODE)"; exit 1 }

sc.exe description $svcName 'zoom-private Remote Access Agent - unattended access, starts on boot.' | Out-Null
# Service recovery: restart on crash, reset failure counter after 1 day
sc.exe failure $svcName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null

# Restrict service UI to interactive-tray handling: the service instance runs
# headless in session 0. The tray app is launched separately per user session.
try {
    [Environment]::SetEnvironmentVariable('BETTERDESK_AGENT_CONFIG_DIR', $ConfigDir, 'Machine')
} catch { Write-Warning "Could not set machine env var: $_" }

Write-Host "Starting service..."
Start-Service -Name $svcName -ErrorAction Stop
Start-Sleep -Seconds 2

# =========================================================================
# Launch tray app in the current user session (visible presence)
# =========================================================================
if (-not $NoLaunch.IsPresent) {
    Write-Host "Launching tray app..."
    try {
        Start-Process -FilePath $target -ArgumentList '--autostart' -WindowStyle Hidden
    } catch {
        Write-Warning "Tray launch failed (binary will start on next login): $_"
    }
}

Write-Host ""
Write-Host "Done. The device registers itself and appears in the web console."
Write-Host "Console: https://panel.telcom.stream"
Write-Host "Service : $svcName (SYSTEM, automatic start, recovery configured)"