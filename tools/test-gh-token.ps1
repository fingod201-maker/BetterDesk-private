$ErrorActionPreference = 'Stop'
# Read token from .env without printing it
$envText = Get-Content 'C:\BetterDeskConsole\.env' -Raw
if ($envText -notmatch '(?m)^BETTERDESK_GITHUB_TOKEN=([^\r\n]+)') { Write-Output 'TOKEN NOT FOUND'; exit 1 }
$token = $Matches[1].Trim()
Write-Output ("token len=" + $token.Length)

$hdrs = @{
    'Authorization'  = "Bearer $token"
    'Accept'         = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'     = 'BetterDesk-Console'
}

function Test-Req($label, $method, $url, $body = $null) {
    try {
        $p = @{ Uri = $url; Method = $method; Headers = $hdrs; UseBasicParsing = $true; TimeoutSec = 30 }
        if ($body) { $p.Body = $body; $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p
        Write-Output "$label -> $($r.StatusCode)"
        $out = $r.Content
        if ($out.Length -gt 600) { $out = $out.Substring(0, 600) + '...' }
        Write-Output $out
    } catch {
        $code = 'ERR'
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        Write-Output "$label -> $code"
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $msg = $_.ErrorDetails.Message
        } else {
            try { $msg = $_.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { $msg = $_.Exception.Message }
        }
        if ($msg.Length -gt 800) { $msg = $msg.Substring(0, 800) }
        Write-Output $msg
    }
    Write-Output '---'
}

Test-Req 'GET /user' GET 'https://api.github.com/user'
try {
    $r = Invoke-WebRequest -Uri 'https://api.github.com/repos/fingod201-maker/BetterDesk-Client' -Headers $hdrs -UseBasicParsing -TimeoutSec 30
    $j = $r.Content | ConvertFrom-Json
    Write-Output ("fork permissions for token owner: " + ($j.permissions | ConvertTo-Json -Compress))
    Write-Output '---'
} catch { Write-Output ("fork perm check failed: " + $_.Exception.Message) }
Test-Req 'GET workflows (fork)' GET 'https://api.github.com/repos/fingod201-maker/BetterDesk-Client/actions/workflows'
Test-Req 'POST dispatch (fork)' POST 'https://api.github.com/repos/fingod201-maker/BetterDesk-Client/actions/workflows/support-build.yml/dispatches' '{"ref":"master","inputs":{"generation_id":"perm-test","config_b64":"e30=","client_commit":""}}'
