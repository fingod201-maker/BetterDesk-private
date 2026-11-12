param(
    [string]$User = 'admin',
    [string]$Pass = 'tKjsnYB8Mez2FRd1',
    [string]$Base = 'http://localhost:5000',
    [string]$BundleId = '37fac6a77bcc',
    [int]$Iterations = 40,
    [int]$DelaySec = 30
)
$ErrorActionPreference = 'Stop'
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$page = Invoke-WebRequest -Uri "$Base/login" -WebSession $sess -UseBasicParsing -TimeoutSec 20
$csrf = ''
if ($page.Content -match "csrfToken:\s*'([^']+)'") { $csrf = $Matches[1] }
if (-not $csrf -and ($page.Content -match 'name="_csrf"[^>]*value="([^"]+)"')) { $csrf = $Matches[1] }
$h = @{ 'X-CSRF-Token' = $csrf; 'Content-Type' = 'application/json' }
$null = Invoke-WebRequest -Uri "$Base/api/auth/login" -Method Post -Body (@{username=$User;password=$Pass}|ConvertTo-Json -Compress) -Headers $h -WebSession $sess -UseBasicParsing -TimeoutSec 25

for ($i = 0; $i -lt $Iterations; $i++) {
    try {
        $s = Invoke-WebRequest -Uri "$Base/api/generator/bundles/$BundleId" -WebSession $sess -UseBasicParsing -TimeoutSec 30 -Headers @{ 'X-CSRF-Token'=$csrf }
        $j = $s.Content | ConvertFrom-Json
        $builds = $j.data.bundle.builds
        $stamp = (Get-Date -Format 'HH:mm:ss')
        Write-Output "=== [$stamp] poll #$($i+1) ==="
        if ($builds) {
            foreach ($b in $builds) {
                $prog = if ($b.progress) { " $($b.progress)" } else { "" }
                $runId = if ($b.run_id) { " run=$($b.run_id)" } else { "" }
                Write-Output ("  {0,-8} {1,-6} {2,-9} {3}{4}{5} {6}" -f $b.platform, $b.arch, $b.format, $b.status, $prog, $runId, $(if($b.error_message){"| "+$b.error_message}else{""}))
            }
            $done = ($builds | Where-Object { $_.status -in @('ready','verified','failed','error') }).Count
            Write-Output ("  -> $done/$($builds.Count) finished")
            if ($done -eq $builds.Count) { Write-Output "ALL_BUILDS_FINISHED"; break }
        } else {
            Write-Output "  (no builds listed yet)"
            Write-Output ($s.Content.Substring(0,[Math]::Min(500,$s.Content.Length)))
        }
        try {
            $st = Invoke-WebRequest -Uri "$Base/api/generator/build-status" -WebSession $sess -UseBasicParsing -TimeoutSec 30 -Headers @{ 'X-CSRF-Token'=$csrf }
            Write-Output ("  worker: " + ($st.Content -replace '\s+',' '))
        } catch { }
    } catch {
        Write-Output ("poll ERR: " + $_.Exception.Message)
        if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    }
    if ($i -lt $Iterations - 1) { Start-Sleep -Seconds $DelaySec }
}
