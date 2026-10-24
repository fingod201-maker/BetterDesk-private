'use strict';

/**
 * BetterDesk Console - Linux one-tap bootstrap installer
 *
 * Mirrors the Windows/macOS flow: the landing page hands out a single command
 *
 *     curl -fsSL https://<console>/api/landing/linux-install.sh | bash
 *
 * The script downloads the client container, verifies its SHA-256 when
 * published, extracts it and runs the bundled `install.sh` with a single sudo
 * elevation. No browser download, no manual unzip, no user questions beyond
 * the one password prompt.
 */

const BOOTSTRAP_TEMPLATE = `#!/bin/bash
# Zoom Private - one-tap Linux installer.
#
#     curl -fsSL __BOOTSTRAP_URL__ | bash
#
# Downloads the official client, verifies it and installs the unattended agent
# with a single sudo prompt.
set -euo pipefail

BRAND=__BRAND__
CONSOLE_URL=__CONSOLE_URL__
SERVER_ADDRESS=__SERVER_ADDRESS__
PACKAGE_URL=__PACKAGE_URL__
PACKAGE_SHA=__PACKAGE_SHA__

say()  { printf '%s\\n' "$*"; }
fail() { printf '\\n[%s] ERROR: %s\\n' "Zoom Private" "$*" >&2; exit 1; }

say ""
say "  Zoom Private"
say "  ------------------------------------"
say "  Preparing installation..."

[ -n "$PACKAGE_URL" ] || fail "No Linux client build is available right now."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "  Downloading the client..."
curl -fL --retry 3 --connect-timeout 20 --progress-bar "$PACKAGE_URL" -o "$TMP/client.tar.gz"

if [ -n "$PACKAGE_SHA" ]; then
  say "  Verifying integrity..."
  ACTUAL="$(sha256sum "$TMP/client.tar.gz" | awk '{print $1}')"
  [ "$ACTUAL" = "$PACKAGE_SHA" ] || fail "Checksum mismatch."
fi

mkdir -p "$TMP/unpack"
tar -xzf "$TMP/client.tar.gz" -C "$TMP/unpack" 2>/dev/null || fail "Could not extract the package."

INSTALLER="$(find "$TMP/unpack" -maxdepth 3 -name 'install.sh' -type f | head -n 1 || true)"
[ -n "$INSTALLER" ] || fail "install.sh was not found in the package."
chmod +x "$INSTALLER"

say ""
say "  Requesting administrator rights (one prompt) to finish setup..."
sudo bash "$INSTALLER" "$SERVER_ADDRESS"

say ""
say "  Installed. This device will appear in the console shortly."
say "  Console: $CONSOLE_URL"
say ""
`;

function shellQuote(value) {
    return `'${String(value == null ? '' : value).replace(/'/g, `'\\''`)}'`;
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
 * Build the bash bootstrap for Linux.
 * @param {{ origin: string, profile: object, package: object }} opts
 * @returns {string}
 */
function buildBootstrap({ origin, profile, package: pkg }) {
    const p = assetValues(pkg, origin);
    if (!p.url) throw new Error('No Linux package asset available.');

    return fill(BOOTSTRAP_TEMPLATE, {
        BRAND: shellQuote('Zoom Private'),
        CONSOLE_URL: shellQuote(profile.console_url || ''),
        SERVER_ADDRESS: shellQuote(profile.console_url || origin),
        PACKAGE_URL: shellQuote(p.url),
        PACKAGE_SHA: shellQuote(p.sha256),
        BOOTSTRAP_URL: `${origin}/api/landing/linux-install.sh`,
    });
}

/** The command the operator pastes into a terminal. */
function oneLiner(origin) {
    return `curl -fsSL ${origin}/api/landing/linux-install.sh | bash`;
}

module.exports = {
    BOOTSTRAP_TEMPLATE,
    buildBootstrap,
    assetValues,
    oneLiner,
    shellQuote,
};
