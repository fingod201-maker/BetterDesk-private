# verify-remote-provider.ps1
# Logs into the console and prints the generator capabilities.
# After the token is set + console restarted, expect:
#   capabilities.mode = "remote"   (not "local")
#   buildReady = true
#   availablePlatforms = 6 entries (win/mac/linux x64+arm64 portable)
param(
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$Base = 'http://localhost:5000'
)
$ErrorActionPreference = 'Stop'
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$login = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body (@{username=$User;password=$Pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
Write-Output ("LOGIN " + $login.StatusCode)

$st = Invoke-WebRequest -Uri "$Base/api/generator/module/status" -WebSession $sess -UseBasicParsing -TimeoutSec 30 -Headers @{ 'X-CSRF-Token'=$csrf }
$j = $st.Content | ConvertFrom-Json
$cap = $j.data.buildCapabilities
Write-Output "--- build capabilities ---"
Write-Output ("providerConfigured : " + $j.data.providerConfigured)
Write-Output ("mode               : " + $cap.mode)
Write-Output ("buildReady         : " + $cap.buildReady)
Write-Output ("reason             : " + $cap.reason)
Write-Output ("targets            : " + (($cap.targets | ForEach-Object { "$($_.platform)/$($_.arch)/$($_.format)" }) -join ', '))

$pf = Invoke-WebRequest -Uri "$Base/api/generator/platforms" -WebSession $sess -UseBasicParsing -TimeoutSec 30 -Headers @{ 'X-CSRF-Token'=$csrf }
$p = $pf.Content | ConvertFrom-Json
$avail = $p.data.availablePlatforms
Write-Output ("availablePlatforms : " + $avail.Count + " -> " + (($avail | ForEach-Object { "$($_.platform)/$($_.arch)" }) -join ', '))
