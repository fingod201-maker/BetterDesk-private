<#
  BetterDesk / Zoom Private - silent Windows installer

  Paste this in PowerShell:

      irm __BOOTSTRAP_URL__ | iex

  The script downloads the official Windows client container with
  Invoke-WebRequest (no Mark-of-the-Web, so SmartScreen stays quiet), then
  installs the per-user tray agent, pre-configures the server, enables
  unattended access with a permanent password, adds firewall/RDP rules,
  registers autostart and launches the agent hidden. One UAC prompt.

  When the script is run from an extracted zip, the local binaries next to
  the script are used instead of downloading a container.
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

if ([string]::IsNullOrWhiteSpace($Password)) {
    # Permanent for this device, but never shared across the fleet or exposed
    # in the public bootstrap when no operator-supplied password is configured.
    $Password = [guid]::NewGuid().ToString('N').Substring(0, 16)
}

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
# Resolve the payload
# ---------------------------------------------------------------------------
Write-Step 'Preparing BetterDesk...'

$tmp = Join-Path $env:TEMP ('betterdesk-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$payloadRoot = $null

try {
    $localGui = $null
    if ($PSScriptRoot) {
        $localGui = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('betterdesk-agent-client.exe', 'zoom-private.agent.exe') } |
            Select-Object -First 1
    }

    if ($localGui) {
        Write-Step 'Using the local client files...'
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

    $gui = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('betterdesk-agent-client.exe', 'zoom-private.agent.exe') } |
        Select-Object -First 1
    $sidecar = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'betterdesk-agent.exe' } |
        Select-Object -First 1

    if (-not $gui)     { throw 'The client executable was not found in the package.' }
    if (-not $sidecar) { throw 'The agent sidecar was not found in the package.' }

    # -----------------------------------------------------------------------
    # Stop old agents/services so files can be replaced
    # -----------------------------------------------------------------------
    if (-not $DryRun) {
        Write-Step 'Stopping previous agent instances...'
        foreach ($name in @('betterdesk-agent-client', 'betterdesk-agent', 'zoom-private.agent')) {
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
    # Install per-user (same layout the previous installer used)
    # -----------------------------------------------------------------------
    $installDir = Join-Path $env:LOCALAPPDATA 'zoom-private.agent'
    $resourceDir = Join-Path $installDir 'resources'
    $configDir  = Join-Path $env:APPDATA 'betterdesk\agent\config'
    $machineDir = Join-Path $env:ProgramData 'zoom-private\agent'

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    New-Item -ItemType Directory -Path $resourceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    New-Item -ItemType Directory -Path $machineDir -Force | Out-Null

    $guiPath     = Join-Path $installDir 'betterdesk-agent-client.exe'
    $sidecarPath = Join-Path $installDir 'betterdesk-agent.exe'

    Write-Step 'Installing the client files...'
    Copy-Item -LiteralPath $gui.FullName -Destination $guiPath -Force
    Copy-Item -LiteralPath $sidecar.FullName -Destination $sidecarPath -Force

    $branding = [ordered]@{
        product_name     = 'BetterDesk'
        company_name     = 'BetterDesk'
        tagline          = 'Secure Remote Support'
        primary_color    = '#0753FB'
        accent_color     = '#0ea5e9'
        default_language = 'en'
        allow_unattended = $true
        server_address   = $ServerAddress
        server_key       = $serverKey
        bundle_id        = 'com.betterdesk.agent'
    }
    $brandingJson = $branding | ConvertTo-Json -Depth 5
    Write-Json (Join-Path $resourceDir 'branding.json') $brandingJson

    # -----------------------------------------------------------------------
    # Pre-configured agent settings
    # -----------------------------------------------------------------------
    Write-Step 'Writing the connection profile...'
    $agentConfig = [ordered]@{
        server_address      = $ServerAddress
        api_key             = ''
        cdap_port           = $CdapPort
        cdap_url            = $CdapUrl
        console_url         = $ConsoleUrl
        device_id           = ''
        device_name         = $env:COMPUTERNAME
        auth_token          = ''
        registered          = $false
        allow_screen_capture = $true
        access_mode         = 'unattended'
        require_consent     = $false
        allow_terminal      = $true
        allow_file_browser  = $true
        allow_clipboard     = $true
        auto_start_sidecar  = $true
        video_codec         = 'auto'
        hw_accel            = 'auto'
        autostart           = $true
        start_minimized     = $true
        language            = 'en'
        unattended_password = $Password
        enforce_tls         = $true
        server_cert_pin     = ''
    }
    $configJson = $agentConfig | ConvertTo-Json -Depth 5

    Write-Json (Join-Path $configDir 'agent-config.json') $configJson
    Write-Json (Join-Path $machineDir 'agent-config.json') $configJson
    Write-Json (Join-Path $installDir 'agent-config.json') $configJson

    # -----------------------------------------------------------------------
    # Firewall: agent binaries, server allow-list, RDP
    # -----------------------------------------------------------------------
    if (-not $DryRun) {
    Write-Step 'Configuring Windows Firewall...'
    try {
        foreach ($rule in @(
            'BetterDesk Agent GUI', 'BetterDesk Agent Sidecar',
            'BetterDesk RDP', 'BetterDesk Server api.telcom.stream',
            'BetterDesk Server cdap.telcom.stream', 'BetterDesk Server rs.telcom.stream'
        )) {
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        }

        New-NetFirewallRule -DisplayName 'BetterDesk Agent GUI' -Direction Outbound -Program $guiPath -Action Allow -Profile Any | Out-Null
        New-NetFirewallRule -DisplayName 'BetterDesk Agent Sidecar' -Direction Outbound -Program $sidecarPath -Action Allow -Profile Any | Out-Null
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
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
        & "$env:SystemRoot\System32\net.exe" localgroup 'Remote Desktop Users' "$env:USERNAME" /add 2>$null | Out-Null
    } catch {
        Write-Log "RDP configuration warning: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Autostart + shortcuts
    # -----------------------------------------------------------------------
    Write-Step 'Registering autostart...'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $runKey -Name 'BetterDeskAgent' -Value ('"{0}" --autostart' -f $guiPath) -Type String

    # The GUI maintains the Run value above. Do not add a second Startup-folder
    # launcher, which would start duplicate agent instances at every logon.
    $shell = New-Object -ComObject WScript.Shell
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BetterDesk Support.lnk'
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $guiPath
        $shortcut.WorkingDirectory = $installDir
        $shortcut.WindowStyle = 1
        $shortcut.Description = 'BetterDesk Secure Remote Support'
        $shortcut.Save()
    } catch {
        Write-Log "Could not create shortcut $shortcutPath : $($_.Exception.Message)"
    }

    }

    # -----------------------------------------------------------------------
    # Launch hidden and wait for enrollment
    # -----------------------------------------------------------------------
    $deviceId = ''
    if ($DryRun) {
        Write-Step 'Dry run complete (no system changes were made).'
    } else {
        Write-Step 'Starting the agent in the background...'
        Start-Process -FilePath $guiPath -ArgumentList '--autostart' -WorkingDirectory $installDir -WindowStyle Hidden | Out-Null

        $configPath = Join-Path $configDir 'agent-config.json'
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            try {
                $current = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                if ($current.registered -and -not [string]::IsNullOrWhiteSpace($current.device_id)) {
                    $deviceId = $current.device_id
                    break
                }
            } catch { }
        }

        Write-Step 'Installation complete.'
        if ($deviceId) {
            Show-Notice 'BetterDesk installed' "Device ID: $deviceId`nPassword: $Password`nThe agent is running in the background."
        } else {
            Show-Notice 'BetterDesk installed' "The agent is running and waiting for server approval.`nPassword: $Password"
        }
    }
} catch {
    Write-Log "Installation failed: $($_.Exception.Message)"
    Show-Notice 'BetterDesk installation failed' $_.Exception.Message
    if (-not $Quiet) { Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
