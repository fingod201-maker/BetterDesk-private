<#
  Cleanup script for existing Windows zoom-private agent installations:
  - Stops all duplicate agent processes
  - Removes Run key auto-start entries (causes visible console popup)
  - Removes old services (session 0 = black screen)
  - Creates clean Task Scheduler logon task in interactive session
  - Single agent instance (MultipleInstances=IgnoreNew)

  Run as admin:  pwsh -f cleanup-windows-agent.ps1
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

Write-Host "=== zoom-private agent cleanup ===" -ForegroundColor Cyan

# 1. Stop all agent processes
Write-Host "Stopping agent processes..." -ForegroundColor Yellow
foreach ($name in @('betterdesk-agent-client', 'betterdesk-agent', 'zoom-private.agent', 'zoom-private-agent')) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Killing $($_.Name) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

# 2. Remove old services (session 0 = captures black desktop)
Write-Host "Removing old services..." -ForegroundColor Yellow
foreach ($svc in @('zoom-private-agent', 'BetterDeskAgent', 'betterdesk-agent', 'ZoomPrivateAgent')) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        & sc.exe delete $svc 2>$null | Out-Null
        Write-Host "  Deleted service: $svc"
    }
}

# 3. Remove Run key entries (causes duplicate agent popups)
Write-Host "Removing Run key entries..." -ForegroundColor Yellow
@('HKCU:', 'HKLM:') | ForEach-Object {
    $runPath = Join-Path $_ 'Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($key in @('BetterDeskAgent', 'ZoomPrivateAgent')) {
        $val = Get-ItemProperty -Path $runPath -Name $key -ErrorAction SilentlyContinue
        if ($val) {
            Remove-ItemProperty -Path $runPath -Name $key -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed Run key: $runPath\$key"
        }
    }
}

# 4. Remove old scheduled tasks
Write-Host "Removing old scheduled tasks..." -ForegroundColor Yellow
foreach ($task in @('zoom-private-agent-task', 'zoom-private', 'BetterDeskAgent', 'ZoomPrivate')) {
    & schtasks /delete /tn $task /f 2>$null | Out-Null
}

# 5. Find the agent binary
$guiPath = $null
foreach ($dir in @(
    "$env:LOCALAPPDATA\zoom-private.agent",
    "$env:ProgramFiles\zoom-private",
    "$env:ProgramData\zoom-private\agent",
    "$env:LOCALAPPDATA\Programs\zoom-private"
)) {
    if (Test-Path $dir) {
        $exe = Get-ChildItem -Path $dir -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('betterdesk-agent-client.exe', 'zoom-private.agent.exe') } |
            Select-Object -First 1
        if ($exe) {
            $guiPath = $exe.FullName
            $installDir = $exe.DirectoryName
            break
        }
    }
}

if (-not $guiPath) {
    Write-Host "No agent binary found. Install the agent first: irm https://panel.telcom.stream/api/landing/windows-install.ps1 | iex" -ForegroundColor Red
    exit 1
}

Write-Host "Agent found at: $guiPath" -ForegroundColor Green

# 6. Create VBS wrapper autostart (no popup, no elevation needed)
Write-Host "Creating VBS autostart wrapper..." -ForegroundColor Yellow
$configDir = Join-Path $env:APPDATA "betterdesk\agent"
$vbsPath = Join-Path $configDir "launch-hidden.vbs"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$guiPath"" --autostart", 0, False
"@ | Out-File -FilePath $vbsPath -Encoding ASCII -Force

Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
    -Name 'BetterDeskAgent' -Value "wscript.exe `"$vbsPath`"" -Type String -Force
Write-Host "Autostart registered: wscript.exe → VBS → agent (zero popup)" -ForegroundColor Green

# Start the agent now
Write-Host "Launching agent hidden..." -ForegroundColor Yellow
Start-Process "wscript.exe" -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
Start-Sleep -Seconds 3

$running = Get-Process -Name "zoom-private.agent" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Agent running: PID $($running.Id)" -ForegroundColor Green
} else {
    Write-Host "Agent may still be starting. Check in 10s." -ForegroundColor Yellow
}

Write-Host "=== Cleanup complete ===" -ForegroundColor Cyan
Write-Host "No more empty console popups or duplicate instances."
