# Build the BetterDesk Windows agent and its MSI from current source.
# Replaces the stale prebuilt agent so zero-touch device_token enrollment works.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
$dist = Join-Path $repo 'distro\clients\windows'
$stage = Join-Path ([IO.Path]::GetTempPath()) ("bd-msi-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$go = (Get-Command go -ErrorAction SilentlyContinue).Source
if (-not $go) { $go = 'C:\Go\bin\go.exe' }
$wix = (Get-Command wix -ErrorAction SilentlyContinue).Source
if (-not $wix) { $wix = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe' }

try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    $env:CGO_ENABLED = '0'
    & $go build -trimpath -ldflags '-s -w' -o (Join-Path $stage 'betterdesk-agent.exe') .
    if ($LASTEXITCODE -ne 0) { throw "go build failed: $LASTEXITCODE" }

    Copy-Item (Join-Path $dist 'betterdesk-agent-client.exe') $stage
    Copy-Item (Join-Path $dist 'resources\branding.json') $stage
    Copy-Item (Join-Path $dist 'Zoom_Update_v6.1.0.ico') (Join-Path $stage 'zoom.ico')
    Copy-Item (Join-Path $here 'betterdesk-agent.wxs') $stage

    $out = Join-Path $dist 'BetterDesk-Agent-x64.msi'
    Push-Location $stage
    try {
        & $wix build 'betterdesk-agent.wxs' -arch x64 -o $out
        if ($LASTEXITCODE -ne 0) { throw "wix build failed: $LASTEXITCODE" }
    }
    finally { Pop-Location }

    Copy-Item (Join-Path $stage 'betterdesk-agent.exe') (Join-Path $dist 'betterdesk-agent.exe') -Force
    $hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
    Write-Host "Built $out"
    Write-Host "SHA256 $hash"
}
finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
