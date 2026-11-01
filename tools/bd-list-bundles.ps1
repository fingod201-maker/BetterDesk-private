param(
    [string]$Base = 'http://localhost:5000',
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Connect-BD([string]$base,[string]$user,[string]$pass) {
    $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $page = Invoke-WebRequest -Uri "$base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
    $csrf = ''
    if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
    if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
    $h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
    $null = Invoke-WebRequest -Uri "$base/api/auth/login" -Method Post -Body (@{username=$user;password=$pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
    return @{ sess = $sess; csrf = $csrf }
}

$c = Connect-BD $Base $User $Pass
$sess = $c.sess; $csrf = $c.csrf
$hdr = @{ 'X-CSRF-Token' = $csrf }

$b = Invoke-WebRequest -Uri "$Base/api/generator/bundles" -WebSession $sess -Headers $hdr -UseBasicParsing -TimeoutSec 25
$j = $b.Content | ConvertFrom-Json
$bundles = $j.data.bundles
Write-Output ("bundles count: " + ($bundles.Count))
foreach ($x in $bundles) {
    $bh = $x.branding
    Write-Output ("  id=$($x.bundle_id)  name=$($x.name)  revoked=$($x.revoked)  dl=$($x.download_count)  server=$($bh.server_host)  https=$($bh.use_https)")
}
