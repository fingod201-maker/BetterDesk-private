#!/usr/bin/env bash
# =============================================================================
# BetterDesk — Linux code-signing script (GPG detached signatures)
# =============================================================================
# GPG-signs Linux client artifacts (.deb, .AppImage) and writes
# detached .sig/.asc files alongside them for repo/package verification.
#
# Required GitHub secrets:
#   LINUX_GPG_PRIVATE_KEY_BASE64  — base64-encoded GPG private key (asc)
#   LINUX_GPG_PASSPHRASE          — GPG private-key passphrase
#
# Usage:
#   ./.github/scripts/sign-linux.sh "path/to/artifact.deb"
#   ./.github/scripts/sign-linux.sh "path/to/directory/"   (signs all .deb/.AppImage)
# =============================================================================
set -euo pipefail

TARGET="${1:?Usage: $0 <path-to-file-or-directory>}"
GPG_KEY_B64="${LINUX_GPG_PRIVATE_KEY_BASE64:?LINUX_GPG_PRIVATE_KEY_BASE64 secret not set}"
GPG_PASSPHRASE="${LINUX_GPG_PASSPHRASE:?LINUX_GPG_PASSPHRASE secret not set}"

GNUPG_HOME="$(mktemp -d)"
export GNUPG_HOME
chmod 700 "$GNUPG_HOME"
trap 'rm -rf "$GNUPG_HOME"' EXIT

# Import private key
echo "$GPG_KEY_B64" | base64 -d | gpg --batch --import --passphrase "$GPG_PASSPHRASE"
gpg --batch --list-secret-keys --keyid-format LONG

GPG_FINGERPRINT=$(gpg --batch --list-secret-keys --keyid-format LONG \
    | grep 'sec' | head -1 | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$GPG_FINGERPRINT" ]; then
    echo "ERROR: No GPG secret key found after import." >&2
    exit 1
fi

echo "Signing with GPG key: $GPG_FINGERPRINT"

# Collect files to sign
if [ -d "$TARGET" ]; then
    FILES=()
    while IFS= read -r -d '' f; do
        FILES+=("$f")
    done < <(find "$TARGET" -type f \( -name "*.deb" -o -name "*.AppImage" -o -name "*.rpm" -o -name "*.tar.gz" -o -name "*.zip" \) -print0 | sort -z)
else
    FILES=("$TARGET")
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No signable files found in $TARGET"
    exit 0
fi

for f in "${FILES[@]}"; do
    echo "GPG-signing: $f"
    gpg --batch --yes --pinentry-mode loopback \
        --passphrase "$GPG_PASSPHRASE" \
        --local-user "$GPG_FINGERPRINT" \
        --detach-sign --armor "$f"
done

echo "Linux GPG signing complete."
