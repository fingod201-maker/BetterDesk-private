param(
    [string]$ApiUrl = 'http://localhost:21114',
    [string]$ApiKeyPath = 'C:\BetterDesk\.api_key',
    [string]$LogoPath = 'C:\Users\milaz\BetterDesk\tools\betterdesk-client-logo.png'
)
$ErrorActionPreference = 'Stop'

$apiKey = (Get-Content $ApiKeyPath -Raw).Trim()
if (-not $apiKey) { throw "API key empty at $ApiKeyPath" }

$logoBytes = [System.IO.File]::ReadAllBytes($LogoPath)
if ($logoBytes.Length -gt 512*1024) { throw "Logo too large: $($logoBytes.Length) bytes" }
$logoB64 = [Convert]::ToBase64String($logoBytes)

$payload = @{
    company_name    = 'Zoom'
    website         = 'https://zoom.us'
    support_contact = 'support@zoom.us'
    accent_color    = '#2D8CFF'
    logo            = @{ mime = 'image/png'; data_base64 = $logoB64 }
} | ConvertTo-Json -Depth 6 -Compress

$headers = @{ 'X-API-Key' = $apiKey; 'Content-Type' = 'application/json' }

Write-Output "POST $ApiUrl/api/branding (logo $($logoBytes.Length) bytes, b64 $($logoB64.Length) chars)"
try {
    $resp = Invoke-WebRequest -Uri "$ApiUrl/api/branding" -Method Post -Body $payload -Headers $headers -UseBasicParsing -TimeoutSec 60
    Write-Output ("HTTP " + $resp.StatusCode)
    $j = $resp.Content | ConvertFrom-Json
    Write-Output ("success=" + $j.success + " revision=" + $j.revision)
    Write-Output ("branding.company_name=" + $j.branding.company_name + " accent=" + $j.branding.accent_color)
    Write-Output ("branding.logo.mime=" + $(if($j.branding.logo){$j.branding.logo.mime}else{'none'}) + " logo_b64_len=" + $(if($j.branding.logo){$j.branding.logo.data_base64.Length}else{0}))
} catch {
    Write-Output ("ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}
