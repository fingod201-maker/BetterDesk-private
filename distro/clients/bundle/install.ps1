<#
  BetterDesk client portable installer (Windows).

  Run after unzipping the bundle:
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -ServerAddress https://panel.telcom.stream

  The script copies the client to a per-user install dir, writes a pre-seeded
  agent-config.json (server address baked in), registers autostart and starts
  the agent. The agent self-registers with the server on first launch and
  shows up in the web console.
#>
[CmdletBinding()]
param(
    [string]$ServerAddress = 'https://panel.telcom.stream',
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\BetterDesk",
    [string]$ConfigDir = "$env:LOCALAPPDATA\BetterDesk\agent",
    [switch]$NoAutostart,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$bundleDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @(
    'zoom-private.agent.exe',
    'betterdesk-agent-client.exe',
    'BetterDesk Client.exe'
)

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

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$target = Join-Path $InstallDir (Split-Path -Leaf $client)
Copy-Item -LiteralPath $client -Destination $target -Force

foreach ($extra in @('betterdesk-agent.exe', 'nssm.exe')) {
    $src = Join-Path $bundleDir $extra
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $extra) -Force
    }
}

$configPath = Join-Path $ConfigDir 'agent-config.json'
$config = $null
if (Test-Path -LiteralPath $configPath) {
    try { $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } catch { $config = $null }
}
if (-not $config) {
    $config = [pscustomobject]@{
        server_address       = $ServerAddress
        api_key              = ''
        cdap_port            = 21122
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
        autostart            = $true
        start_minimized      = $true
        language             = 'en'
        unattended_password  = ''
        enforce_tls          = $true
        server_cert_pin      = ''
    }
} else {
    $config.server_address = $ServerAddress
}

$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host "Config written: $configPath"

if (-not $NoAutostart) {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    # The env var is set inline because Explorer only re-reads the user
    # environment at logon, so a value written after the current session
    # would not be visible to the autostart entry.
    $runValue = "cmd.exe /c set `"BETTERDESK_AGENT_CONFIG_DIR=$ConfigDir`" && start `"`" `"$target`""
    Set-ItemProperty -Path $runKey -Name 'BetterDeskAgent' -Value $runValue
    Write-Host "Autostart registered (HKCU Run -> BetterDeskAgent)"
}

[Environment]::SetEnvironmentVariable('BETTERDESK_AGENT_CONFIG_DIR', $ConfigDir, 'User')

if (-not $NoLaunch) {
    $env:BETTERDESK_AGENT_CONFIG_DIR = $ConfigDir
    Start-Process -FilePath $target -WorkingDirectory $InstallDir
    Write-Host "Agent started."
}

Write-Host "Done. The device registers itself and appears in the web console."
