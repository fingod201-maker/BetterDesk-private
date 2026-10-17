#!/usr/bin/env bash
# =============================================================================
# BetterDesk — macOS code-signing + notarization script
# =============================================================================
# Signs a macOS .app / .dmg with Apple Developer ID, submits to Apple
# Notarization service, and staples the ticket.
#
# Required GitHub secrets:
#   MACOS_CODESIGN_CERT_P12_BASE64  — base64-encoded Developer ID p12
#   MACOS_CODESIGN_CERT_PASSWORD    — p12 private-key password
#   MACOS_NOTARY_USERNAME           — Apple ID email (notarytool auth)
#   MACOS_NOTARY_PASSWORD           — app-specific password (notarytool auth)
#   MACOS_TEAM_ID                   — Apple Developer Team ID
#
# Usage:
#   ./.github/scripts/sign-macos.sh "path/to/BetterDesk Agent.app"
# =============================================================================
set -euo pipefail

INPUT_PATH="${1:?Usage: $0 <path-to-app-or-dmg>}"
CERT_P12_BASE64="${MACOS_CODESIGN_CERT_P12_BASE64:?MACOS_CODESIGN_CERT_P12_BASE64 secret not set}"
CERT_PASSWORD="${MACOS_CODESIGN_CERT_PASSWORD:?MACOS_CODESIGN_CERT_PASSWORD secret not set}"
NOTARY_USER="${MACOS_NOTARY_USERNAME:?MACOS_NOTARY_USERNAME secret not set}"
NOTARY_PASS="${MACOS_NOTARY_PASSWORD:?MACOS_NOTARY_PASSWORD secret not set}"
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

# --- If it's a .app, build a .dmg for notarization --------------------------
if [[ "$INPUT_PATH" == *.app ]]; then
    APP_NAME=$(basename "$INPUT_PATH" .app)
    DMG_FILE="$TEMP_DIR/${APP_NAME}.dmg"
    echo "Creating DMG for notarization: $DMG_FILE"
    hdiutil create -srcfolder "$INPUT_PATH" -ov -format UDZO \
        -volname "$APP_NAME" "$DMG_FILE"
    NOTARIZE_TARGET="$DMG_FILE"
else
    NOTARIZE_TARGET="$INPUT_PATH"
fi

# --- Notarize ---------------------------------------------------------------
echo "Submitting to Apple Notarization service..."
NOTARY_RESPONSE=$(xcrun notarytool submit "$NOTARIZE_TARGET" \
    --apple-id "$NOTARY_USER" \
    --password "$NOTARY_PASS" \
    --team-id "$TEAM_ID" \
    --wait --output json 2>&1 || true)

echo "$NOTARY_RESPONSE"

STATUS=$(echo "$NOTARY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo "")

if [ "$STATUS" != "Accepted" ]; then
    echo "ERROR: Notarization did not accept the build." >&2
    exit 1
fi

echo "Notarization accepted."

# --- Staple -----------------------------------------------------------------
if [[ "$INPUT_PATH" == *.app ]]; then
    echo "Stapling notarization ticket to app..."
    xcrun stapler staple "$INPUT_PATH"
else
    echo "Stapling notarization ticket to dmg..."
    xcrun stapler staple "$NOTARIZE_TARGET"
fi

echo "macOS code-sign + notarize complete: $INPUT_PATH"
