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
# Downloads the official desktop client, verifies it and installs it for the
# current user. No sudo and no manual chmod: the app runs inside the logged-in
# graphical session so it can capture the real desktop and autostart with the
# user's session.
set -euo pipefail

BRAND=__BRAND__
CONSOLE_URL=__CONSOLE_URL__
SERVER_ADDRESS=__SERVER_ADDRESS__
API_URL=__API_URL__
CDAP_URL=__CDAP_URL__
SERVER_KEY=__SERVER_KEY__
PACKAGE_URL=__PACKAGE_URL__
PACKAGE_SHA=__PACKAGE_SHA__

say()  { printf '%s\\n' "$*"; }
fail() { printf '\\n[%s] ERROR: %s\\n' "$BRAND" "$*" >&2; exit 1; }

say ""
say "  Zoom Private"
say "  ------------------------------------"
say "  Preparing installation..."

[ -n "$PACKAGE_URL" ] || fail "No Linux client build is available right now."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "  Downloading the client..."
curl -fL --retry 3 --connect-timeout 20 --progress-bar "$PACKAGE_URL" -o "$TMP/client.pkg"

if [ -n "$PACKAGE_SHA" ]; then
  say "  Verifying integrity..."
  ACTUAL="$(sha256sum "$TMP/client.pkg" | awk '{print $1}')"
  [ "$ACTUAL" = "$PACKAGE_SHA" ] || fail "Checksum mismatch."
fi

mkdir -p "$TMP/unpack"
case "$PACKAGE_URL" in
  *.zip)
    if command -v unzip >/dev/null 2>&1; then
      unzip -q "$TMP/client.pkg" -d "$TMP/unpack"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -m zipfile -e "$TMP/client.pkg" "$TMP/unpack"
    else
      fail "This package needs unzip or python3 to extract."
    fi
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "$TMP/client.pkg" -C "$TMP/unpack"
    ;;
  *)
    fail "Unsupported package format."
    ;;
esac

INSTALLER="$(find "$TMP/unpack" -maxdepth 3 -name 'install.sh' -type f | head -n 1 || true)"
[ -n "$INSTALLER" ] || fail "install.sh was not found in the package."
chmod +x "$INSTALLER"

say ""
say "  Installing for the current user (no sudo)..."
BETTERDESK_SERVER_ADDRESS="$SERVER_ADDRESS" \\
BETTERDESK_API_URL="$API_URL" \\
BETTERDESK_CDAP_URL="$CDAP_URL" \\
BETTERDESK_CONSOLE_URL="$CONSOLE_URL" \\
BETTERDESK_SERVER_KEY="$SERVER_KEY" \\
BETTERDESK_USER_INSTALL=1 \\
bash "$INSTALLER"

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
        SERVER_ADDRESS: shellQuote(profile.server_address || profile.console_url || origin),
        API_URL: shellQuote(profile.api_url || ''),
        CDAP_URL: shellQuote(profile.cdap_url || ''),
        SERVER_KEY: shellQuote(profile.server_key || ''),
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
