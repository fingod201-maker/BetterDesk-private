'use strict';

const fs = require('fs');
const path = require('path');

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
 * script downloads the Windows container, verifies its SHA-256 when
 * published, expands it, and runs the bundled `install.ps1` with a single
 * elevation prompt (one UAC dialog), which is the "one allow" the operator
 * sees. The per-user agent, firewall rules, connection profile, autostart,
 * and tray startup are then configured without another wizard.
 */

// The silent installer lives in its own .ps1 file so PowerShell backticks and
// here-strings do not have to be escaped inside a JavaScript template literal.
const BOOTSTRAP_TEMPLATE = fs.readFileSync(
    path.join(__dirname, 'windows-install.ps1'),
    'utf8'
);

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
    // Empty means the installer generates a unique permanent device password.
    // Never fall back to a fleet-wide password in a public bootstrap.
    const password = process.env.ZOOM_PRIVATE_UNATTENDED_PASSWORD
        || process.env.BETTERDESK_UNATTENDED_PASSWORD
        || '';

    return fill(BOOTSTRAP_TEMPLATE, {
        BRAND: psSingleQuote('BetterDesk'),
        CONSOLE_URL: psSingleQuote(profile.console_url || origin),
        SERVER_ADDRESS: psSingleQuote(profile.server_address || profile.api_url || origin),
        CDAP_URL: psSingleQuote(profile.cdap_url || ''),
        CDAP_PORT: String(Number(profile.cdap_port) || 21122),
        DEFAULT_PASSWORD: psSingleQuote(password),
        SERVER_KEY: psSingleQuote(profile.server_key || ''),
        PACKAGE_URL: psSingleQuote(p.url),
        PACKAGE_SHA: psSingleQuote(p.sha256 || ''),
        BOOTSTRAP_URL: psSingleQuote(bootstrapUrl),
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
