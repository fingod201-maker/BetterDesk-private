# TryCloudflare quick tunnel launcher (no domain, no token, works in ~30s).
# Gives a temporary https://<random>.trycloudflare.com URL that points at a LOCAL port.
# URL changes every restart - for testing only. For a stable hostname see ../README.md (Path B).
#
#   .\quick-tunnel.ps1                 # defaults to console on :5000
#   .\quick-tunnel.ps1 -Port 21114     # tunnel the Go API instead
#   .\quick-tunnel.ps1 -Port 21122     # tunnel the CDAP websocket gateway

param(
    [int]$Port = 5000,
    [string]$Bind = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin  = Join-Path $here "bin\cloudflared.exe"

if (-not (Test-Path $bin)) {
    Write-Error "cloudflared.exe not found at $bin. See README.md to download it."
    exit 1
}

Write-Host "Starting TryCloudflare tunnel -> http://${Bind}:${Port}"
Write-Host "Press Ctrl+C to stop. Your public URL appears below (ends in trycloudflare.com).`n"

& $bin tunnel --no-autoupdate --url "http://${Bind}:${Port}"
