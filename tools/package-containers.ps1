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
#>
[CmdletBinding()]
param()

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
$version = '1.0.0'

function Build-Agent($goos, $goarch, $outName) {
    Write-Host "Building $goos/$goarch -> $outName"
    Push-Location $agentDir
    try {
        $env:GOOS = $goos; $env:GOARCH = $goarch; $env:CGO_ENABLED = '0'
        go build -trimpath -ldflags '-s -w' -o $outName .
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
Build-Agent windows amd64 (Join-Path $winDir 'betterdesk-agent.exe')

Copy-Item (Join-Path $repo 'distro\clients\bundle\install.ps1') (Join-Path $winDir 'install.ps1') -Force
Copy-Item (Join-Path $repo 'distro\clients\bundle\install.sh') (Join-Path $winDir 'install.sh') -Force
Copy-Item (Join-Path $distro 'config\agent-config.json.example') (Join-Path $winDir 'agent-config.json.example') -Force

# Ship the ready GUI client binary alongside the CLI agent when present.
$src = Join-Path $distro 'windows\betterdesk-agent-client.exe'
if (Test-Path $src) { Copy-Item $src (Join-Path $winDir 'betterdesk-agent-client.exe') -Force }

@'
BetterDesk Agent bundle (Windows)

CONTENTS
  betterdesk-agent.exe         CLI/service agent (CDAP + proof enrollment sidecar)
  betterdesk-agent-client.exe  Tauri GUI/tray client (if included)
  install.ps1                  zero-config installer (SYSTEM service + autostart + firewall)
  install.sh                   Linux/macOS variant of the bundle installer
  agent-config.json.example    all URLs pre-seeded

INSTALL
  PowerShell (auto-elevates):
    powershell -ExecutionPolicy Bypass -File .\install.ps1
  Or use the MSI from the same release if you prefer a packaged installer.

SMARTSCREEN (unsigned builds)
  Files extracted from this zip may inherit Mark-of-the-Web (Explorer keeps
  the Zone.Identifier). If Windows flags an extracted binary: right-click it >
  Properties > Unblock > OK. Self-extracting via PowerShell Expand-Archive
  drops the flag automatically.
  Installing from the .iso container avoids this entirely - Explorer mounts
  a disk image without propagating MotW onto inner files:
    right-click > Mount > run install.ps1 from the mounted drive.

SIGNED releases clear the prompt once the certificate has been seen twice
(SmartScreen reputation). Ask the console admin for the signed build.
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
