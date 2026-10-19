# BetterDesk cloudflared auto-start launcher (NAMED tunnel - stable domain).
# Runs the persistent tunnel defined in config.yml -> panel/api/cdap .telcom.stream
# This is what the Windows startup Scheduled Task / Startup-folder VBS calls.

param()

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin  = Join-Path $here "bin\cloudflared.exe"
$cfg  = Join-Path $here "config.yml"

if (-not (Test-Path $bin)) { Write-Error "cloudflared.exe not found at $bin"; exit 1 }
if (-not (Test-Path $cfg)) { Write-Error "config.yml not found at $cfg"; exit 1 }

Write-Host "[start-tunnel] Named tunnel via config.yml (panel/api/cdap .telcom.stream)"
& $bin tunnel --config $cfg run

