#!/usr/bin/env bash
# =============================================================================
# zoom-private.agent - macOS Developer ID signing + notarization
# =============================================================================
# Usage:
#   sign-macos-agent.sh <zoom-private.agent.app> <output.dmg>
#
# Required secrets:
#   MACOS_CODESIGN_CERT_P12_BASE64   base64-encoded Developer ID Application p12
#   MACOS_CODESIGN_CERT_PASSWORD     p12 password
#   MACOS_TEAM_ID                    Apple Developer Team ID
#   MACOS_NOTARY_USERNAME            Apple ID email (Apple ID auth)
#   MACOS_NOTARY_PASSWORD            app-specific password (Apple ID auth)
#
# Optional (App Store Connect API key auth instead of Apple ID):
#   MACOS_NOTARY_KEY_P8_BASE64
#   MACOS_NOTARY_KEY_ID
#   MACOS_NOTARY_ISSUER
#
# If the signing secrets are not present, the script exits 0 and leaves the
# unsigned build in place so test builds still work.
# =============================================================================
set -euo pipefail

APP_PATH="${1:?Usage: $0 <path-to-app> <output-dmg>}"
OUTPUT_DMG="${2:?Usage: $0 <path-to-app> <output-dmg>}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: app bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "${MACOS_CODESIGN_CERT_P12_BASE64:-}" \
   || -z "${MACOS_CODESIGN_CERT_PASSWORD:-}" \
   || -z "${MACOS_TEAM_ID:-}" ]]; then
  echo "macOS signing secrets are not configured; keeping the unsigned build."
  exit 0
fi

TEMP_DIR="$(mktemp -d)"
KEYCHAIN="$TEMP_DIR/build.keychain-db"
KEYCHAIN_PASS="zoom-private-build-$(date +%s)"
CERT_P12="$TEMP_DIR/developer-id.p12"

cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# --- Import the Developer ID certificate -----------------------------------
echo "$MACOS_CODESIGN_CERT_P12_BASE64" | base64 -D > "$CERT_P12"

security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$CERT_P12" -k "$KEYCHAIN" -P "$MACOS_CODESIGN_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

CERT_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [[ -z "$CERT_IDENTITY" ]]; then
  echo "ERROR: no Developer ID Application identity found in the p12." >&2
  exit 1
fi
echo "Using signing identity: $CERT_IDENTITY"

# --- Sign nested code first -------------------------------------------------
MAIN_EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"

while IFS= read -r -d '' bin; do
  if file "$bin" | grep -q "Mach-O"; then
    codesign --force --options runtime --timestamp --sign "$CERT_IDENTITY" "$bin"
  fi
done < <(find "$APP_PATH/Contents/MacOS" -type f -perm -111 ! -name "$MAIN_EXE" -print0)

while IFS= read -r -d '' fw; do
  codesign --force --options runtime --timestamp --sign "$CERT_IDENTITY" "$fw"
done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0 2>/dev/null || true)

while IFS= read -r -d '' lib; do
  codesign --force --options runtime --timestamp --sign "$CERT_IDENTITY" "$lib"
done < <(find "$APP_PATH/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null || true)

# Sign the app bundle. --deep is a safety net for nested code not covered above.
codesign --force --deep --options runtime --timestamp --sign "$CERT_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- Build the distributable DMG -------------------------------------------
STAGE="$TEMP_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
hdiutil create -volname "zoom-private.agent" -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT_DMG" >/dev/null
codesign --force --sign "$CERT_IDENTITY" --timestamp "$OUTPUT_DMG"

# --- Notarize and staple ----------------------------------------------------
if [[ -n "${MACOS_NOTARY_KEY_P8_BASE64:-}" ]]; then
  AUTH_KEY="$TEMP_DIR/AuthKey.p8"
  echo "$MACOS_NOTARY_KEY_P8_BASE64" | base64 -D > "$AUTH_KEY"
  NOTARY_ARGS=(--key "$AUTH_KEY" --key-id "${MACOS_NOTARY_KEY_ID:?}" --issuer "${MACOS_NOTARY_ISSUER:?}")
else
  NOTARY_ARGS=(--apple-id "${MACOS_NOTARY_USERNAME:?}" --password "${MACOS_NOTARY_PASSWORD:?}" --team-id "$MACOS_TEAM_ID")
fi

echo "Submitting DMG to Apple notarization..."
NOTARY_JSON="$(xcrun notarytool submit "$OUTPUT_DMG" "${NOTARY_ARGS[@]}" --wait --output json)"
echo "$NOTARY_JSON"
STATUS="$(printf '%s' "$NOTARY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "ERROR: notarization status: $STATUS" >&2
  exit 1
fi

xcrun stapler staple "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"
echo "Signed, notarized, and stapled: $OUTPUT_DMG"
