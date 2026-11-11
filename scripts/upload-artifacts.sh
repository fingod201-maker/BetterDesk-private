#!/bin/bash
# =============================================================================
# BetterDesk Artifact Upload + Integrity Tool
# Uploads client artifacts (APK, MSI, EXE, DMG, DEB, etc.) into the landing
# service distro directory and computes SHA-256 checksums for client-side
# verification.
#
# Usage:
#   ./scripts/upload-artifacts.sh <path-to-file-or-dir> [--github-release]
#
# Without --github-release: copies files into distro/clients/ (served as
# fallback source by landingReleaseService). With --github-release: prints
# gh-release commands to publish artifacts to GitHub.
# =============================================================================
set -euo pipefail

BD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISTRO_DIR="$BD_DIR/distro/clients"
GITHUB_RELEASE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-release) GITHUB_RELEASE=1; shift ;;
    --distro-dir)     DISTRO_DIR="$2"; shift 2 ;;
    *)                break ;;
  esac
done

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  echo "Usage: $0 <file-or-dir> [--github-release] [--distro-dir <path>]"
  exit 1
fi

mkdir -p "$DISTRO_DIR"

log() { echo "[upload] $*"; }

sha256_of() {
  local f="$1"
  if command -v sha256sum &>/dev/null; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

upload_file() {
  local src="$1"
  local name
  name="$(basename "$src")"
  local dest="$DISTRO_DIR/$name"

  # Prevent overwriting a different file with the same name (safety).
  if [[ -f "$dest" ]]; then
    local existing_sum
    existing_sum="$(sha256_of "$dest")"
    local new_sum
    new_sum="$(sha256_of "$src")"
    if [[ "$existing_sum" != "$new_sum" ]]; then
      echo "WARNING: $name already exists with different SHA-256. Skipping to avoid collision."
      echo "  existing: $existing_sum"
      echo "  new:      $new_sum"
      return 0
    fi
    log "$name already present with identical checksum — skipping"
    return 0
  fi

  cp -p "$src" "$dest"
  chmod 644 "$dest"
  local sum
  sum="$(sha256_of "$dest")"
  log "Uploaded: $dest ($sum)"
}

# --- Collect files ---
if [[ -f "$INPUT" ]]; then
  upload_file "$INPUT"
elif [[ -d "$INPUT" ]]; then
  shopt -s nullglob
  for f in "$INPUT"/*; do
    [[ -f "$f" ]] && upload_file "$f"
  done
  shopt -u nullglob
else
  echo "ERROR: not a file or directory: $INPUT"
  exit 1
fi

# --- Write checksum manifest ---
MANIFEST="$DISTRO_DIR/CHECKSUMS.sha256"
: > "$MANIFEST"
shopt -s nullglob
for f in "$DISTRO_DIR"/*; do
  [[ -f "$f" && "$(basename "$f")" != "CHECKSUMS.sha256" ]] || continue
  sum="$(sha256_of "$f")"
  echo "$sum  $(basename "$f")" >> "$MANIFEST"
done
shopt -u nullglob
log "Checksum manifest written: $MANIFEST"

echo ""
echo "==================== NEXT STEPS ===================="
if [[ $GITHUB_RELEASE -eq 1 ]]; then
  echo "Publish to GitHub release (run on your machine with GH_TOKEN set):"
  echo "  gh release create <tag> --notes 'BetterDesk client build' $DISTRO_DIR/*"
  echo ""
  echo "Then set these env vars on the landing service:"
  echo "  LANDING_GITHUB_OWNER=<your-github-org>"
  echo "  LANDING_GITHUB_REPO=<your-github-repo>"
  echo "  UPDATE_GITHUB_TOKEN=<PAT with repo scope>"
else
  echo "Artifacts are now served from distro/clients/ as a fallback source."
  echo "Redeploy the landing service so it picks up the new distro assets."
fi
echo "===================================================="
