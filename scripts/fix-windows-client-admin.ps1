<#
  BetterDesk Windows client cleanup — RUN AS ADMINISTRATOR.

  Consolidates the dev/test machine to a single hidden agent, removes the
  leftover local server stack (everything must run on the OCI cloud VM),
  and replaces the CONSOLE-subsystem agent with the GUI build so no
  console window ever appears.

  Usage (elevated):  pwsh -ExecutionPolicy Bypass -File fix-windows-client-admin.ps1

  The GUI build of the agent lives in the repo at:
    distro/clients/windows/betterdesk-agent.exe   (subsystem 2 = GUI)
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Require-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "This script must run elevated (Run as Administrator)." }
}
Require-Admin

$repoGui   = Join-Path $PSScriptRoot '..\distro\clients\windows\betterdesk-agent.exe'
$pfAgent   = 'C:\Program Files\BetterDesk Agent\betterdesk-agent.exe'
$zpSidecar = "$env:LOCALAPPDATA\Programs\zoom-private\betterdesk-agent.exe"

Write-Host "`n[1/5] Stopping agent processes" -ForegroundColor Cyan
foreach ($n in @('betterdesk-agent','betterdesk-agent-client','zoom-private.agent','zoom-private-agent','betterdesk-server')) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  kill $($_.Name) PID $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep 2

Write-Host "`n[2/5] Removing local server stack (must run on OCI, not the client)" -ForegroundColor Cyan
foreach ($svc in @('BetterDeskServer','BetterDeskConsole')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        & "$env:SystemRoot\System32\sc.exe" delete $svc 2>$null | Out-Null
        Write-Host "  deleted service $svc"
    }
}

Write-Host "`n[3/5] Replacing agent binaries with GUI build (no console)" -ForegroundColor Cyan
if (Test-Path $repoGui) {
    foreach ($dst in @($pfAgent, $zpSidecar)) {
        if (Test-Path $dst) {
            $bak = "$dst.console.bak"
            if (-not (Test-Path $bak)) { Copy-Item $dst $bak -Force }
            Copy-Item $repoGui $dst -Force
            $b = [System.IO.File]::ReadAllBytes($dst)
            $pe = [BitConverter]::ToInt32($b, 0x3C)
            $sub = [BitConverter]::ToUInt16($b, $pe + 24 + 0x44)
            $ok = if ($sub -eq 2) { 'GUI OK' } else { 'STILL CONSOLE' }
            Write-Host "  $dst -> $ok"
        }
    }
} else {
    Write-Host "  WARN: GUI build not found at $repoGui" -ForegroundColor Yellow
}

Write-Host "`n[4/5] Deduplicating agents (single agent per device_id)" -ForegroundColor Cyan
# Keep the stealth LOCALAPPDATA install (zoom-private, matches production installer);
# remove the older standalone Program Files "BetterDesk Agent" scheduled task + files.
& schtasks /delete /tn 'BetterDesk Agent' /f 2>$null | Out-Null
Remove-Item 'C:\Program Files\BetterDesk Agent' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\BetterDesk\Agent' -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  removed Program Files agent + scheduled task"

Write-Host "`n[5/5] Ensuring hidden autostart for the stealth agent" -ForegroundColor Cyan
$installDir = "$env:LOCALAPPDATA\Programs\zoom-private"
$gui = Join-Path $installDir 'zoom-private.agent.exe'
if (-not (Test-Path $gui)) { $gui = Join-Path $installDir 'betterdesk-agent-client.exe' }
if (Test-Path $gui) {
    $vbs = Join-Path $installDir 'launch-hidden.vbs'
    @"
Set sh = CreateObject("WScript.Shell")
sh.Run """$gui"" --autostart", 0, False
"@ | Out-File -FilePath $vbs -Encoding ASCII -Force
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' -ErrorAction SilentlyContinue
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterDeskAgent' -Value "wscript.exe `"$vbs`"" -Type String -Force
    Write-Host "  VBS autostart set: $vbs"
} else {
    Write-Host "  WARN: no stealth agent GUI binary found at $installDir" -ForegroundColor Yellow
}

Write-Host "`nDone. Verify at https://panel.telcom.stream (admin / BetterDesk@2026!Admin)" -ForegroundColor Green
