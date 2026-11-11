#!/usr/bin/env bash
# =============================================================================
# BetterDesk — macOS code-signing script (notarization disabled)
# =============================================================================
# Signs a macOS .app /.dmg with Apple Developer ID.
# Notarization is intentionally disabled — macOS builds do not require Apple
# notarization for internal/test distribution. Re-enable when we have a valid
# Apple Developer account with notarization rights.
# =============================================================================
set -euo pipefail

INPUT_PATH="${1:?Usage: $0 <path-to-app-or-dmg>}"
CERT_P12_BASE64="${MACOS_CODESIGN_CERT_P12_BASE64:?MACOS_CODESIGN_CERT_P12_BASE64 secret not set}"
CERT_PASSWORD="${MACOS_CODESIGN_CERT_PASSWORD:?MACOS_CODESIGN_CERT_PASSWORD secret not set}"
TEAM_ID="${MACOS_TEAM_ID:?MACOS_TEAM_ID secret not set}"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

P12_FILE="$TEMP_DIR/betterdesk-macos-codesign.p12"
KEYCHAIN_FILE="$TEMP_DIR/build.keychain-db"
KEYCHAIN_PASS="betterdesk-build-$(date +%s)"

echo "$CERT_P12_BASE64" | base64 -d > "$P12_FILE"

# --- Create temporary keychain and import certificate -----------------------
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_FILE"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_FILE"
security import "$P12_FILE" -k "$KEYCHAIN_FILE" -P "$CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN_FILE"
security default-keychain -s "$KEYCHAIN_FILE"

# Find the imported Developer ID certificate identity
CERT_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_FILE" \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -z "$CERT_IDENTITY" ]; then
    echo "ERROR: No Developer ID Application certificate found in keychain." >&2
    exit 1
fi

echo "Using code-signing identity: $CERT_IDENTITY"

# --- Sign the app bundle ----------------------------------------------------
echo "Signing: $INPUT_PATH"
codesign --deep --force --verbose \
    --sign "$CERT_IDENTITY" \
    --identifier "com.betterdesk.agent" \
    --team-id "$TEAM_ID" \
    --options runtime \
    --timestamp \
    "$INPUT_PATH"

# --- Verify signature -------------------------------------------------------
codesign --verify --deep --strict --verbose=2 "$INPUT_PATH"

# --- macOS code-sign complete (notarization intentionally skipped) ----------
echo "macOS code-sign complete: $INPUT_PATH"