# set-github-token.ps1
# Securely writes BETTERDESK_GITHUB_TOKEN into C:\BetterDeskConsole\.env
# WITHOUT echoing the secret. Run from an elevated PowerShell.
#
# Usage:
#   .\set-github-token.ps1 -Token 'github_pat_....'      # pass inline
#   .\set-github-token.ps1                                # will prompt (masked)

param(
    [string]$Token = '',
    [string]$EnvFile = 'C:\BetterDeskConsole\.env'
)

if (-not $Token) {
    $secure = Read-Host "Paste GitHub token (input hidden)" -AsSecureString
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
$Token = $Token.Trim()
if (-not $Token) { Write-Error "Empty token — aborting."; exit 1 }

if (-not (Test-Path -LiteralPath $EnvFile)) { Write-Error "Missing $EnvFile"; exit 1 }

$lines = Get-Content -LiteralPath $EnvFile
$found = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*BETTERDESK_GITHUB_TOKEN=') {
        $lines[$i] = "BETTERDESK_GITHUB_TOKEN=$Token"
        $found = $true
        break
    }
}
if (-not $found) { $lines += "BETTERDESK_GITHUB_TOKEN=$Token" }

# Write atomically
$tmp = "$EnvFile.tmp-$PID"
Set-Content -LiteralPath $tmp -Value $lines -Encoding UTF8 -NoNewline
Move-Item -LiteralPath $tmp -Destination $EnvFile -Force

# Report WITHOUT revealing the token
$len = $Token.Length
$masked = if ($len -ge 8) { $Token.Substring(0,4) + '...' + $Token.Substring($len-4) } else { '****' }
Write-Host "BETTERDESK_GITHUB_TOKEN set in $EnvFile (value: $masked, length $len)"
Write-Host "Next: Restart-Service BetterDeskConsole   (then run verify-remote-provider.ps1)"
