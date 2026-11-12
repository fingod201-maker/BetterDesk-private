$ErrorActionPreference = 'Stop'
$Fork = 'fingod201-maker/BetterDesk-Client'
$Upstream = 'UNITRONIX/BetterDesk-Client'

# 1. Verify fork exists publicly
$hdrs = @{ 'User-Agent' = 'BetterDesk-Console'; 'Accept' = 'application/vnd.github+json' }
try {
    $r = Invoke-WebRequest -Uri "https://api.github.com/repos/$Fork" -Headers $hdrs -UseBasicParsing -TimeoutSec 20
    $j = $r.Content | ConvertFrom-Json
    Write-Output ("FORK OK: " + $j.full_name + " default_branch=" + $j.default_branch + " fork_of=" + $j.parent.full_name)
    $branch = $j.default_branch
} catch {
    Write-Output ("FORK MISSING (status " + [int]$_.Exception.Response.StatusCode + ") - create the fork first")
    exit 1
}

# 2. Verify support-build.yml + the installed client commit exist on the fork
try {
    $wf = Invoke-WebRequest -Uri "https://api.github.com/repos/$Fork/contents/.github/workflows/support-build.yml?ref=$branch" -Headers $hdrs -UseBasicParsing -TimeoutSec 20
    Write-Output ("support-build.yml present on " + $branch)
} catch {
    Write-Output ("support-build.yml MISSING on fork (status " + [int]$_.Exception.Response.StatusCode + ")")
    exit 1
}
$commit = '7fe242d2c381712d5cf9c677813cfca78e8e7920'
try {
    $null = Invoke-WebRequest -Uri "https://api.github.com/repos/$Fork/commits/$commit" -Headers $hdrs -UseBasicParsing -TimeoutSec 20
    Write-Output ("client commit $commit present on fork")
} catch {
    Write-Output ("WARNING: client commit not found on fork (status " + [int]$_.Exception.Response.StatusCode + ")")
}

# 3. Patch .env: point repo config at the fork (preserve CRLF)
$envPath = 'C:\BetterDeskConsole\.env'
$text = [System.IO.File]::ReadAllText($envPath)
$text = $text -replace '(?m)^BETTERDESK_CLIENT_REPO=.*$', ('BETTERDESK_CLIENT_REPO=' + $Fork)
$text = $text -replace '(?m)^BETTERDESK_CLIENT_ALLOWED_REPOS=.*$', ('BETTERDESK_CLIENT_ALLOWED_REPOS=' + $Fork)
[System.IO.File]::WriteAllText($envPath, $text)
Write-Output '.env patched:'
Select-String -Path $envPath -Pattern '^BETTERDESK_CLIENT_REPO=|^BETTERDESK_CLIENT_ALLOWED_REPOS=' | ForEach-Object { Write-Output ('  ' + $_.Line) }

# 4. Restart console service
Restart-Service BetterDeskConsole -Force
Start-Sleep -Seconds 10
Write-Output ("service: " + (Get-Service BetterDeskConsole).Status)
