#!/bin/bash
# =============================================================================
# BetterDesk Artifact Integrity Verifier
# Verifies all artifacts in distro/clients/ against CHECKSUMS.sha256 and
# validates APK signing (if apksigner/keytool available).
#
# Usage: ./scripts/verify-artifacts.sh [distro-dir]
# =============================================================================
set -euo pipefail

DISTRO_DIR="${1:-$PWD/distro/clients}"
FAILURES=0

err() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES+1)); }
ok()  { echo "OK:   $*"; }

if [[ ! -d "$DISTRO_DIR" ]]; then
  err "Distro directory not found: $DISTRO_DIR"
  exit 1
fi

echo "=== Verifying artifacts in $DISTRO_DIR ==="

# --- Check manifest exists ---
MANIFEST="$DISTRO_DIR/CHECKSUMS.sha256"
if [[ ! -f "$MANIFEST" ]]; then
  err "CHECKSUMS.sha256 missing — run upload-artifacts.sh first"
  exit 1
fi
ok "Checksum manifest present"

# --- Verify each listed checksum ---
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Format: <sha256>  <filename>
  sum="${line%% *}"
  name="${line##*  }"
  f="$DISTRO_DIR/$name"
  if [[ ! -f "$f" ]]; then
    err "Manifest lists $name but file is missing"
    continue
  fi
  actual=$(sha256sum "$f" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
  if [[ "$actual" != "$sum" ]]; then
    err "Checksum mismatch for $name (expected $sum, got $actual)"
  else
    ok "$name ($sum)"
  fi
done < "$MANIFEST"

# --- Check for unlisted artifacts ---
shopt -s nullglob
for f in "$DISTRO_DIR"/*; do
  base="$(basename "$f")"
  [[ "$base" == "CHECKSUMS.sha256" ]] && continue
  if ! grep -qF "  $base" "$MANIFEST" 2>/dev/null; then
    err "Artifact not in manifest: $base"
  fi
done
shopt -u nullglob

# --- APK signing check (optional) ---
if command -v apksigner &>/dev/null; then
  echo ""
  echo "=== APK signature verification ==="
  shopt -s nullglob
  for apk in "$DISTRO_DIR"/*.apk; do
    [[ -f "$apk" ]] || continue
    if apksigner verify --print-certs "$apk" >/dev/null 2>&1; then
      ok "APK signed: $(basename "$apk")"
    else
      warn "APK NOT signed or signature invalid: $(basename "$apk") — Android install will prompt 'unknown source'"
    fi
  done
  shopt -u nullglob
elif command -v keytool &>/dev/null; then
  echo ""
  echo "apksigner not found — skipping APK signature check (install Android SDK build-tools)"
else
  echo ""
  echo "apksigner not found — skipping APK signature check"
fi

echo ""
if [[ $FAILURES -gt 0 ]]; then
  echo "VERIFICATION FAILED — $FAILURES issue(s)"
  exit 1
fi
echo "ALL ARTIFACTS VERIFIED"
