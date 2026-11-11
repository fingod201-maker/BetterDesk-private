# =============================================================================
# BetterDesk — Windows code-signing script
# =============================================================================
# Signs Windows client executables / installers with an Authenticode certificate.
#
# Required GitHub secrets:
#   WINDOWS_CODESIGN_CERT_PFX_BASE64  — base64-encoded PFX (cert + private key)
#   WINDOWS_CODESIGN_CERT_PASSWORD    — PFX private-key password
#
# Usage (PowerShell):
#   .\.github/scripts/sign-windows.ps1 -InputPath "path\to\file.exe" `
#       -TimeStamp "http://timestamp.digicert.com"
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$Description,

    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$TimeStamp = "http://timestamp.digicert.com",

    [string]$HashAlgorithm = "SHA256"
)

$ErrorActionPreference = "Stop"

# --- Resolve certificate from secret ---------------------------------------
$pfxB64 = $env:WINDOWS_CODESIGN_CERT_PFX_BASE64
$pfxPass = $env:WINDOWS_CODESIGN_CERT_PASSWORD

if ([string]::IsNullOrWhiteSpace($pfxB64)) {
    Write-Error "WINDOWS_CODESIGN_CERT_PFX_BASE64 secret is not set. Skipping Windows code-sign."
    exit 0
}

$certFile = Join-Path $env:TEMP "betterdesk-windows-codesign.pfx"
[System.IO.File]::WriteAllBytes($certFile, [System.Convert]::FromBase64String($pfxB64))

# --- Import into user cert store (signtool needs the private key) -----------
$import = Import-PfxCertificate -FilePath $certFile `
    -CertStoreLocation Cert:\CurrentUser\My `
    -Password (ConvertTo-SecureString -String $pfxPass -AsPlainText -Force) `
    -Exportable `
    -ErrorAction SilentlyContinue

if (-not $import) {
    Write-Error "Failed to import code-signing PFX certificate."
    exit 1
}

$thumbprint = $import.Thumbprint
Write-Host "Imported code-signing cert thumbprint: $thumbprint"

# --- Find signtool.exe ------------------------------------------------------
$signtoolCandidates = @(
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe",
    "C:\Program Files (x86)\Windows Kits\11\bin\*\x64\signtool.exe",
    "C:\Program Files (x86)\Windows Kits\11\bin\x64\signtool.exe"
)
$signtool = $null
foreach ($cand in $signtoolCandidates) {
    $match = Get-Item $cand -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { $signtool = $match.FullName; break }
}
if (-not $signtool) {
    Write-Error "signtool.exe not found. Install Windows SDK."
    exit 1
}
Write-Host "Using signtool: $signtool"

# --- Sign -------------------------------------------------------------------
$signArgs = @(
    "sign",
    "/a",
    "/f", $certFile,
    "/p", $pfxPass,
    "/t", $TimeStamp,
    "/fd", $HashAlgorithm,
    "/d", $Description,
    "/du", $Url,
    $InputPath
)

Write-Host "Signing: $InputPath"
& $signtool @signArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool failed with exit code $LASTEXITCODE"
    exit 1
}

# --- Verify -----------------------------------------------------------------
$verifyArgs = @("verify", "/a", "/v", $InputPath)
Write-Host "Verifying signature..."
& $signtool @verifyArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Signature verification failed with exit code $LASTEXITCODE"
    exit 1
}

# --- Copy signed output if different from input -----------------------------
if ($InputPath -ne $OutputPath) {
    Copy-Item -Path $InputPath -Destination $OutputPath -Force
}

Write-Host "Windows code-sign complete: $OutputPath"

# --- Cleanup ----------------------------------------------------------------
Remove-Item -Path $certFile -Force -ErrorAction SilentlyContinue
