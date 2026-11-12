param(
    [string]$Password = ''
)
# Sets up the LOCAL BetterDesk client for unattended access the right way:
#   1. Installs the client as a Windows service (starts at boot, works at the
#      login screen before anyone signs in).
#   2. Writes the service-level config pointing at the BetterDesk server
#      (panel.telcom.stream + server public key).
#   3. Sets a permanent password so operators connect with no approval prompt.
#   4. Cleans stale server options out of the user-level config.
# Self-elevates: service install + password require Administrator (UAC prompt).
# ASCII-only file - do not add non-ASCII characters.
$ErrorActionPreference = 'Stop'

$exe      = 'C:\Program Files\RustDesk\RustDesk.exe'
$serverHost = 'panel.telcom.stream'
$apiUrl     = 'https://panel.telcom.stream/api'
$serverKey  = 'q8UeY1D2/XMe8GddEW7mBoK5KaGQFUYEBn6yFqtRgYA='
$svcConfigDir = 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config'
$accessFile   = 'C:\Users\milaz\BetterDesk\tools\local-unattended-access.txt'
$logFile      = 'C:\Users\milaz\BetterDesk\tools\setup-unattended-local.log'

if (-not (Test-Path $exe)) { throw "Client executable not found: $exe" }

# --- Self-elevate (child runs this same script as Administrator, logs output) ---
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Remove-Item $logFile -ErrorAction SilentlyContinue
    $scriptPath = $MyInvocation.MyCommand.Path
    $pwArg = ''
    if ($Password) { $pwArg = " -Password '$Password'" }
    $inner = "Start-Transcript -Path '$logFile' -Force; & '$scriptPath'$pwArg; Stop-Transcript"
    $argLine = "-NoProfile -ExecutionPolicy Bypass -Command `"$inner`""
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine -Wait -PassThru
        if (Test-Path $logFile) { Get-Content $logFile | Write-Output }
        Write-Output ("elevated exit code: " + $proc.ExitCode)
        exit $proc.ExitCode
    } catch {
        Write-Output ("Elevation canceled or failed: " + $_.Exception.Message)
        exit 1
    }
}

# --- Elevated body ---
if (-not $Password) {
    $alnum   = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $symbols = '!@#%^*-_=+'
    $bytes = New-Object byte[] 18
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $Password = (($bytes[0..15] | ForEach-Object { $alnum[$_ % $alnum.Length] }) -join '')
    $Password += $symbols[$bytes[16] % $symbols.Length]
    $Password += $symbols[$bytes[17] % $symbols.Length]
}
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

# 1) Install the client as a Windows service (SYSTEM, automatic start).
$existingSvc = Get-CimInstance Win32_Service -Filter "PathName LIKE '%RustDesk.exe%'" | Select-Object -First 1
if ($existingSvc) {
    Write-Output ("[1/4] Service already installed (" + $existingSvc.Name + " = " + $existingSvc.State + ") - skipping install.")
} else {
    Write-Output '[1/4] Installing client service...'
    # Bounded per-process wait (NOT Start-Process -Wait, which waits for the
    # whole process tree - the service process never exits, causing a hang).
    $proc = Start-Process -FilePath $exe -ArgumentList '--install-service' -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(60)
    $svcReady = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $svcCheck = Get-CimInstance Win32_Service -Filter "Name='RustDesk'" -ErrorAction SilentlyContinue
        if ($svcCheck -and $svcCheck.State -eq 'Running') { $svcReady = $true; break }
        if ($proc.HasExited) { break }
    }
    if (-not $svcReady) {
        if (-not $proc.HasExited) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
        }
        $svcCheck = Get-CimInstance Win32_Service -Filter "Name='RustDesk'" -ErrorAction SilentlyContinue
        if (-not ($svcCheck -and $svcCheck.State -eq 'Running')) {
            throw 'Service install did not complete within 60 seconds.'
        }
    }
    if ($proc.HasExited -and $proc.ExitCode -ne 0) {
        throw "install-service failed with exit code $($proc.ExitCode)"
    }
    Write-Output '  service installed and running.'
}

# 2) Service-level config: server endpoints + key (used by the service, so it
#    survives logoff and answers at the login screen).
Write-Output '[2/4] Writing service config (server + key)...'
if (-not (Test-Path $svcConfigDir)) { New-Item -ItemType Directory -Path $svcConfigDir -Force | Out-Null }
$svcConfig = Join-Path $svcConfigDir 'RustDesk.toml2'
if (Test-Path $svcConfig) {
    Copy-Item $svcConfig "$svcConfig.bak.$ts" -Force
    Write-Output "  backup: $svcConfig.bak.$ts"
}
$svcContent = @"
[options]
custom-rendezvous-server = '$serverHost'
relay-server = '$serverHost'
api-server = '$apiUrl'
key = '$serverKey'
verification-method = 'use-permanent-password'
allow-websocket = 'Y'
"@
Set-Content -Path $svcConfig -Value $svcContent -Encoding ASCII

# 3) Permanent password (hashed into the active config; operators connect with
#    this password and no approval prompt on the remote machine).
Write-Output '[3/4] Setting permanent password...'
$proc = Start-Process -FilePath $exe -ArgumentList '--password', $Password -PassThru -WindowStyle Hidden
$deadline = (Get-Date).AddSeconds(60)
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
if (-not $proc.HasExited) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
    Write-Output '  warning: password process did not exit within 60s; process killed.'
} elseif ($proc.ExitCode -ne 0) {
    throw "password setup failed with exit code $($proc.ExitCode)"
}

# 4) User-level config: drop stale endpoint options (old server), keep the
#    rest of the UI state, re-add the correct endpoints + verification method.
Write-Output '[4/4] Updating user config...'
$uCfg = Join-Path $env:APPDATA 'RustDesk\config\RustDesk2.toml'
if (Test-Path $uCfg) {
    Copy-Item $uCfg "$uCfg.bak.$ts" -Force
    $raw = @(Get-Content $uCfg)
    $optIdx = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match '^\[options\]\s*$') { $optIdx = $i; break }
    }
    if ($optIdx -ge 0) { $before = $raw[0..($optIdx - 1)] } else { $before = $raw }
    $dropKeys = @('custom-rendezvous-server', 'relay-server', 'api-server', 'key',
                  'stop-service', 'local-ip-addr', 'direct-server')
    $keptOpts = @()
    if ($optIdx -ge 0) {
        for ($i = $optIdx + 1; $i -lt $raw.Count; $i++) {
            $line = $raw[$i]
            if ($line -match '^\s*\[') { break }
            $isStale = $false
            foreach ($k in $dropKeys) {
                if ($line -match ("^\s*" + [regex]::Escape($k) + "\s*=")) { $isStale = $true; break }
            }
            if (-not $isStale -and $line.Trim() -ne '') { $keptOpts += $line }
        }
    }
    $newOpts = @(
        '[options]',
        "custom-rendezvous-server = '$serverHost'",
        "relay-server = '$serverHost'",
        "api-server = '$apiUrl'",
        "key = '$serverKey'",
        "verification-method = 'use-permanent-password'",
        "allow-websocket = 'Y'"
    ) + $keptOpts
    Set-Content -Path $uCfg -Value (@($before) + $newOpts) -Encoding ASCII
    Write-Output "  backup: $uCfg.bak.$ts"
}

# Restart the service so config + password take effect, force automatic start.
$svc = Get-CimInstance Win32_Service -Filter "PathName LIKE '%RustDesk.exe%'" | Select-Object -First 1
if (-not $svc) { throw 'BetterDesk client service not found after install.' }
Set-Service -Name $svc.Name -StartupType Automatic
Restart-Service -Name $svc.Name -Force
Start-Sleep -Seconds 3
$svc = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object -First 1
if ($svc.State -ne 'Running') { throw "Service $($svc.Name) is not running (state: $($svc.State))." }

# Record access info for the operator.
$machineId = (& $exe --get-id 2>&1 | Out-String).Trim()
$accessInfo = @(
    'BetterDesk local unattended access - configured (setup-unattended-local.ps1)',
    "Date:               $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Machine ID:         $machineId",
    "Server:             $serverHost (api: $apiUrl)",
    "Permanent password: $Password",
    "Service:            $($svc.Name) = Running, StartupType=Automatic",
    '',
    'Connect from the operator side with this ID + password (no approval needed).',
    'Change the password later in the client: Settings > Security > Permanent password.'
)
Set-Content -Path $accessFile -Value $accessInfo -Encoding ASCII

Write-Output ''
Write-Output '=== UNATTENDED ACCESS CONFIGURED ==='
Write-Output ("Service:  " + $svc.Name + " (Running, Automatic)")
Write-Output ("ID:       " + $machineId)
Write-Output ("Password: " + $Password)
Write-Output ("Saved to: " + $accessFile)
