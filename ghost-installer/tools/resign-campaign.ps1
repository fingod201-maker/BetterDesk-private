# Re-sign the APK for a campaign (new certificate => new hashes, no cross-campaign updates).
#   .\tools\resign-campaign.ps1 -Campaign acme -Apk ..\distro\clients\android\zoom-private.apk
param(
    [Parameter(Mandatory = $true)][string]$Campaign,
    [string]$Apk = "",
    [string]$OutDir = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
if (-not $Apk) { $Apk = Join-Path $root "app\build\outputs\apk\release\zoom-private.apk" }
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $root -Parent) "distro\clients\android\campaigns" }
$bt = Join-Path $env:ANDROID_HOME "build-tools\36.0.0"
$ks = Join-Path $root "campaign.keystore"
$pass = "Campaign2026!"
$alias = "campaign"
$safe = ($Campaign -replace '[^A-Za-z0-9]+', '-').Trim('-')
if (-not $safe) { throw "Campaign name is empty" }
if (-not (Test-Path $Apk)) { throw "APK not found: $Apk" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path $ks)) {
    & keytool -genkeypair -v -keystore $ks -storepass $pass -keypass $pass `
        -alias $alias -keyalg RSA -keysize 4096 -validity 10000 `
        -dname "CN=Zoom Private, OU=Delivery, O=Zoom Private, C=US"
}

$aligned = Join-Path $env:TEMP ("camp-" + $safe + "-aligned.apk")
$out = Join-Path $OutDir ("Zoom_Update_" + $safe + ".apk")
& (Join-Path $bt "zipalign.exe") -f -p 4 $Apk $aligned
& (Join-Path $bt "apksigner.bat") sign --ks $ks --ks-pass "pass:$pass" --key-pass "pass:$pass" `
    --ks-key-alias $alias --v1-signing-enabled true --v2-signing-enabled true `
    --v3-signing-enabled true --out $out $aligned
& (Join-Path $bt "apksigner.bat") verify --print-certs $out | Out-Null
Remove-Item $aligned -Force
Write-Host "Campaign APK: $out"
Write-Host ("SHA256: " + (Get-FileHash $out -Algorithm SHA256).Hash)
Write-Host "Note: installs from another campaign require an uninstall (different signer)."
