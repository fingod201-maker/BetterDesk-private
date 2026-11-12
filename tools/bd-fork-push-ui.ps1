param()
# Push UI + Android CI fixes to fingod201-maker/BetterDesk-Client (master):
#   1. address_book.dart / my_group.dart: hide the stock RustDesk cloud Login
#      prompt; show guidance to use Your ID + permanent password instead.
#   2. build-android.yml: run cargo-ndk scripts from the repo root (the flutter/
#      dir has no Cargo.toml and cargo-ndk resolves the manifest from cwd).
# ASCII-only file.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$envText = Get-Content 'C:\BetterDeskConsole\.env' -Raw
$tok = (($envText -split "`n" | Where-Object { $_ -match '^BETTERDESK_GITHUB_TOKEN=' }) -replace '^BETTERDESK_GITHUB_TOKEN=','').Trim()
if (-not $tok) { throw 'BETTERDESK_GITHUB_TOKEN missing in console .env' }
$H = @{Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'bd-push'}
$repo = 'fingod201-maker/BetterDesk-Client'
$branch = 'master'
$apiBase = "https://api.github.com/repos/$repo/contents"

function Get-GH([string]$Uri) {
    for ($i = 1; $i -le 6; $i++) {
        try { return Invoke-RestMethod -Uri $Uri -Headers $H -TimeoutSec 30 }
        catch {
            if ($i -eq 6) { throw }
            Write-Output ("  retry {0}: {1}" -f $i, $_.Exception.Message)
            Start-Sleep -Seconds (2 * $i)
        }
    }
}
function Put-GH([string]$Uri, [string]$Body) {
    for ($i = 1; $i -le 6; $i++) {
        try { return Invoke-RestMethod -Uri $Uri -Method Put -Headers $H -Body $Body -ContentType 'application/json' -TimeoutSec 30 }
        catch {
            if ($i -eq 6) { throw }
            Write-Output ("  retry {0}: {1}" -f $i, $_.Exception.Message)
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

function Update-DartLogin([string]$Path, [string]$Message) {
    $f = Get-GH "$apiBase/$Path`?ref=$branch"
    $txt = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($f.content))
    $re = [regex]'if \(!gFFI\.userModel\.isLogin\) \{\s+return Center\(\s+child: ElevatedButton\(\s+onPressed: loginDialog, child: Text\(translate\("Login"\)\)\)\);\s+\}'
    $m = $re.Matches($txt)
    if ($m.Count -ne 1) { throw "$Path : expected 1 login block, found $($m.Count)" }
    $idx = $m[0].Index
    $ls = $txt.LastIndexOf("`n", $idx)
    $lineStart = $ls + 1
    $base = ''
    $k = $lineStart
    while ($k -lt $idx -and $txt[$k] -eq ' ') { $base += ' '; $k++ }
    if ($base.Length -eq 0) { $base = '      ' }
    $n1 = $base + '  '
    $n2 = $base + '    '
    $n3 = $base + '      '
    $msg = 'Sign-in is disabled in BetterDesk. Use Your ID and permanent password for unattended access.'
    $new = @(
        ($base + 'if (!gFFI.userModel.isLogin) {'),
        ($n1 + 'return Center('),
        ($n2 + 'child: Padding('),
        ($n2 + '  padding: const EdgeInsets.all(16),'),
        ($n2 + '  child: Text('),
        ($n3 + '    translate("' + $msg + '"),'),
        ($n3 + '    textAlign: TextAlign.center,'),
        ($n2 + '  ),'),
        ($n1 + '),'),
        ($base + ');'),
        ($base + '}')
    ) -join "`n"
    $updated = $txt.Substring(0, $idx) + $new + $txt.Substring($idx + $m[0].Length)
    $body = @{message = $Message; content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($updated)); sha = $f.sha; branch = $branch} | ConvertTo-Json -Compress
    $r = Put-GH "$apiBase/$Path" $body
    Write-Output ("  {0} -> commit {1}" -f $Path, $r.commit.sha.Substring(0, 10))
}

function Update-AndroidWorkflow {
    $Path = '.github/workflows/build-android.yml'
    $f = Get-GH "$apiBase/$Path`?ref=$branch"
    $txt = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($f.content))
    $lines = $txt -split "`n"
    $out = @()
    $inRust = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $L = $lines[$i]
        if ($L -match '^\s*- name: Build Rust for') { $inRust = $true; $out += $L; continue }
        if ($inRust -and $L -match '^\s*working-directory: flutter\s*$') { continue }
        if ($inRust -and $L -match '^(?<ind>\s*)run: bash (?<s>ndk_\w+\.sh)\s*$') {
            $out += ($Matches.ind + 'run: bash flutter/' + $Matches.s)
            $inRust = $false
            continue
        }
        if ($inRust -and $L -match '^\s*- name:') { $inRust = $false }
        $out += $L
    }
    $newTxt = $out -join "`n"
    $c1 = ([regex]::Matches($newTxt, [regex]::Escape('run: bash flutter/ndk_arm64.sh'))).Count
    $c2 = ([regex]::Matches($newTxt, [regex]::Escape('run: bash flutter/ndk_arm.sh'))).Count
    if ($c1 -ne 1 -or $c2 -ne 1) { throw "android transform failed (arm64=$c1 arm=$c2)" }
    $body = @{message = 'ci(android): run cargo-ndk builds from repo root [skip ci]'; content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($newTxt)); sha = $f.sha; branch = $branch} | ConvertTo-Json -Compress
    $r = Put-GH "$apiBase/$Path" $body
    Write-Output ("  {0} -> commit {1}" -f $Path, $r.commit.sha.Substring(0, 10))
}

Write-Output '=== push 1: address_book.dart ==='
Update-DartLogin 'flutter/lib/common/widgets/address_book.dart' 'ui: hide stock rustdesk Login, point to unattended access [skip ci]'
Write-Output '=== push 2: my_group.dart ==='
Update-DartLogin 'flutter/lib/common/widgets/my_group.dart' 'ui: hide stock rustdesk Login, point to unattended access [skip ci]'
Write-Output '=== push 3: build-android.yml ==='
Update-AndroidWorkflow
Write-Output 'DONE'

