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
$body = @{ username = $User; password = $Pass } | ConvertTo-Json -Compress
$login = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body $body -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25
Write-Output ("LOGIN " + $login.StatusCode)

function Get-Api($path) {
    try {
        $r = Invoke-WebRequest -Uri ($Base + $path) -WebSession $sess -UseBasicParsing -TimeoutSec 30 -Headers @{ 'X-CSRF-Token' = $csrf }
        Write-Output ("`n=== GET $path -> " + $r.StatusCode + " ===")
        $r.Content
    } catch {
        Write-Output ("`n=== GET $path -> ERR " + $_.Exception.Message + " ===")
        if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    }
}

Get-Api '/api/generator/module/status'
Get-Api '/api/generator/platforms'
