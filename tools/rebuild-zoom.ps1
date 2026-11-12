param(
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$Base = 'http://localhost:5000',
    [string]$BundleId = '37fac6a77bcc'
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

# Confirm remote mode before rebuilding
try {
    $caps = Invoke-WebRequest -Uri "$Base/api/generator/module/status" -WebSession $sess -UseBasicParsing -TimeoutSec 20 -Headers @{ 'X-CSRF-Token'=$csrf }
    Write-Output ("module/status: " + $caps.Content)
} catch { Write-Output ("module/status ERR: " + $_.Exception.Message) }

# Re-queue all platforms (force resets failed -> queued)
try {
    $r = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId/rebuild" -Method Post -Body '{}' -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 60
    Write-Output ("rebuild: " + $r.StatusCode)
    Write-Output $r.Content
} catch {
    Write-Output ("rebuild ERR: " + $_.Exception.Message)
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}
