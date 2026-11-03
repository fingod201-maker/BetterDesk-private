'use strict';

/**
 * Windows support-agent installer.
 *
 * Live deployments deliberately run in the logged-in user session, not as a
 * session-0 service: a service has no interactive desktop, so screen capture
 * is blank and SendInput cannot reach the real session. This installer mirrors
 * the working layout:
 *
 *   %LOCALAPPDATA%\BetterDesk\SupportAgent\   (app + dependencies)
 *   %APPDATA%\betterdesk\agent\start-agent.vbs
 *   %APPDATA%\betterdesk\agent\agent-launch.cmd
 *   %APPDATA%\betterdesk\agent\agent.log
 *   Scheduled task: <App> Support Agent -> wscript.exe //B start-agent.vbs
 *
 * It never calls `--install-service`; `-UseScheduledTask` is accepted for
 * backwards compatibility and is now the only mode.
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

const INSTALLER_SCRIPT = String.raw`[CmdletBinding()]
param(
    [switch]$UseScheduledTask
)

$ErrorActionPreference = 'Stop'
$profileInstallsTask = __INSTALL_SERVICE__
$profileAutostarts = __AUTOSTART__

$appCandidates = @('betterdesk.exe', 'rustdesk.exe', 'betterdesk-agent.exe')
$app = $null
foreach ($name in $appCandidates) {
    $candidate = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $candidate) { $app = $candidate; break }
}
if (-not $app) {
    $app = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $app) {
    throw 'BetterDesk executable was not found next to this installer.'
}

$appName = [IO.Path]::GetFileNameWithoutExtension($app)
$taskName = "$appName Support Agent"
$installDir = Join-Path $env:LOCALAPPDATA 'BetterDesk\SupportAgent'
$agentDir = Join-Path $env:APPDATA 'betterdesk\agent'
$launchCmd = Join-Path $agentDir 'agent-launch.cmd'
$startVbs = Join-Path $agentDir 'start-agent.vbs'
$configFile = Join-Path $agentDir 'agent-config.json'
$logFile = Join-Path $agentDir 'agent.log'
$isUninstall = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name) -match 'Uninstall'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        $MyInvocation.MyCommand.Path
    )
    if ($UseScheduledTask) {
        $arguments += '-UseScheduledTask'
    }
    $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $elevated.ExitCode
}

if ($isUninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Get-Process -Name $appName, 'betterdesk-agent' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $agentDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $agentDir -Force | Out-Null

# Copy the whole payload so bundled DLLs/Qt plugins stay next to the app.
$sourceFull = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$targetFull = (Resolve-Path -LiteralPath $installDir).ProviderPath
if ($sourceFull.TrimEnd('\') -ne $targetFull.TrimEnd('\')) {
    Get-ChildItem -LiteralPath $PSScriptRoot -Force | Where-Object {
        $_.Name -notin @('Install-BetterDesk.ps1', 'Uninstall-BetterDesk.ps1')
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $installDir -Recurse -Force
    }
}

$installedApp = Join-Path $installDir ([IO.Path]::GetFileName($app))
if (-not (Test-Path -LiteralPath $installedApp)) {
    $installedApp = (Get-ChildItem -LiteralPath $installDir -Filter '*.exe' -File |
        Select-Object -First 1 -ExpandProperty FullName)
}
if (-not $installedApp) {
    throw 'BetterDesk executable could not be staged in the install directory.'
}

# Preserve an operator-supplied config for unattended enrollment.
$sourceConfig = Join-Path $PSScriptRoot 'agent-config.json'
if ((Test-Path -LiteralPath $sourceConfig) -and -not (Test-Path -LiteralPath $configFile)) {
    Copy-Item -LiteralPath $sourceConfig -Destination $configFile -Force
}

$isAgentBinary = $appName -match 'agent'
$shellLine = if ($isAgentBinary) {
    'if exist "%CFG%" ( "%AGENT%" --config "%CFG%" >>"%LOG%" 2>&1 ) else ( "%AGENT%" >>"%LOG%" 2>&1 )'
} else {
    '"%AGENT%" --tray >>"%LOG%" 2>&1'
}

$launchContent = @'
@echo off
setlocal
set "AGENT=__AGENT__"
set "CFG=__CONFIG__"
set "LOG=__LOG__"

for %%A in ("%LOG%") do if %%~zA GTR 5242880 move /Y "%LOG%" "%LOG%.1" >nul 2>&1

echo.>>"%LOG%"
echo [%DATE% %TIME%] agent starting>>"%LOG%"
__RUN__
echo [%DATE% %TIME%] agent exited code %ERRORLEVEL%>>"%LOG%"
'@
$launchContent = $launchContent.Replace('__AGENT__', $installedApp)
$launchContent = $launchContent.Replace('__CONFIG__', $configFile)
$launchContent = $launchContent.Replace('__LOG__', $logFile)
$launchContent = $launchContent.Replace('__RUN__', $shellLine)
Set-Content -LiteralPath $launchCmd -Value $launchContent -Encoding ASCII

$vbsContent = @'
Set sh = CreateObject("WScript.Shell")
cmd = sh.ExpandEnvironmentStrings("%APPDATA%\betterdesk\agent\agent-launch.cmd")
sh.Run "cmd.exe /c """ & cmd & """", 0, False
'@
Set-Content -LiteralPath $startVbs -Value $vbsContent -Encoding ASCII

if ($profileInstallsTask -or $profileAutostarts) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B "{0}"' -f $startVbs) -WorkingDirectory $installDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "BetterDesk Support Agent installed (hidden user-session task)."
} else {
    Write-Host "BetterDesk installed without autostart."
}

Write-Host "  Binary: $installedApp"
Write-Host "  Config: $configFile"
Write-Host "  Log:    $logFile"
Write-Host "  Task:   $taskName"
`;

function buildWindowsSupportInstallerScript({ installService = false, autostart = false } = {}) {
    return INSTALLER_SCRIPT
        .replace('__INSTALL_SERVICE__', installService ? '$true' : '$false')
        .replace('__AUTOSTART__', autostart ? '$true' : '$false');
}

async function writeWindowsSupportInstallers(stageDir, options = {}) {
    const script = buildWindowsSupportInstallerScript(options);
    await fsp.writeFile(path.join(stageDir, 'Install-BetterDesk.ps1'), script, 'utf8');
    await fsp.writeFile(path.join(stageDir, 'Uninstall-BetterDesk.ps1'), script, 'utf8');
}

function hasWindowsSupportInstallers(stageDir) {
    return [
        'Install-BetterDesk.ps1',
        'Uninstall-BetterDesk.ps1',
    ].every((name) => fs.existsSync(path.join(stageDir, name)));
}

module.exports = {
    buildWindowsSupportInstallerScript,
    writeWindowsSupportInstallers,
    hasWindowsSupportInstallers,
};
