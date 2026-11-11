param(
    [string]$Owner = 'fingod201-maker',
    [string]$Repo = 'BetterDesk-private',
    [string]$Tag = 'portable-latest',
    [string]$OutFile = (Join-Path $PSScriptRoot 'checksums.sha256')
)

$ErrorActionPreference = 'Stop'

$input = "protocol=https`nhost=github.com`n`n"
$cred = $input | git credential fill 2>$null
$token = $null
foreach ($line in $cred) {
    if ($line -like 'password=*') { $token = $line.Substring(9) }
}
if (-not $token) { throw 'no GitHub credential available' }

$headers = @{
    'Authorization' = "Bearer $token"
    'User-Agent' = 'BetterDesk-AllowlistUpdater'
    'Accept' = 'application/vnd.github+json'
}

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag" -Headers $headers
$wanted = $release.assets | Where-Object { $_.name -match '^zoom-private-.*\.zip$' }
if (-not $wanted) { throw "no zoom-private bundles in release $Tag" }

$lines = @()
foreach ($asset in $wanted) {
    $tmp = Join-Path $env:TEMP ("bd-asset-" + $asset.id + ".zip")
    & curl.exe -sS -L --connect-timeout 30 --max-time 900 `
        -H "Accept: application/octet-stream" -H "Authorization: Bearer $token" `
        "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($asset.id)" -o $tmp
    if (-not (Test-Path $tmp)) { continue }
    $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
    $lines += "$hash  $($asset.name)"
    Remove-Item $tmp -Force
    Write-Output ("{0}  {1}" -f $hash, $asset.name)
}

$header = @(
    "# zoom-private bundle checksums",
    "# release: $Owner/$Repo @ $Tag",
    "# generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "# pin these in your MDM deployment so only known-good bundles are installed."
)
($header + $lines) | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output ("written: " + $OutFile)
