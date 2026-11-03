#!/bin/sh
# Build an unsigned BetterDesk Support Agent .pkg on macOS.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=${1:-${BETTERDESK_VERSION:-1.0.0}}
PKG_ID="com.unitronix.betterdesk-support-agent"
OUT_DIR="$DIR/out"
OUT="$OUT_DIR/BetterDesk-Support-Agent-$VERSION.pkg"
if [ "$(uname -s)" != "Darwin" ]; then
    echo "build-pkg.sh must run on macOS (pkgbuild/productbuild are Apple tools)." >&2
    exit 1
fi
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/betterdesk-pkg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
BASE="$STAGE/root/usr/local/share/betterdesk-support"
SCRIPTS="$STAGE/scripts"
mkdir -p "$BASE" "$SCRIPTS" "$OUT_DIR"
cp "$DIR/install.sh" "$DIR/install-betterdesk-support.sh" "$DIR/uninstall-betterdesk-support.sh" "$BASE/"
if [ -d "$DIR/payload" ]; then
    cp -a "$DIR/payload/." "$BASE/"
else
    for item in "$DIR"/*.app "$DIR"/betterdesk-agent "$DIR"/betterdesk-agent-* "$DIR"/betterdesk "$DIR"/rustdesk; do
        [ -e "$item" ] && cp -a "$item" "$BASE/"
    done
fi
chmod 755 "$BASE"/*.sh 2>/dev/null || true
cat >"$SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/sh
BASE="/usr/local/share/betterdesk-support"
U=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
[ -n "$U" ] && [ "$U" != "root" ] && /usr/bin/sudo -u "$U" -H /bin/sh "$BASE/install.sh" || true
exit 0
POSTINSTALL
chmod 755 "$SCRIPTS/postinstall"
pkgbuild --root "$STAGE/root" --identifier "$PKG_ID" --version "$VERSION" --scripts "$SCRIPTS" "$STAGE/component.pkg"
productbuild --package "$STAGE/component.pkg" "$OUT"
echo "Built: $OUT"
