#!/bin/bash
set -euo pipefail
DMG="${1:-}"
OUT="${2:-/tmp/ZoomPrivate-client.pkg}"
STAGE_ROOT="$(mktemp -d)"
STAGE="$STAGE_ROOT/stage"
mkdir -p "$STAGE"
hdiutil attach "$DMG" -nobrowse -mountpoint "$STAGE/mnt" >/dev/null 2>&1
APP_PATH="$(find "$STAGE/mnt" -maxdepth 1 -name '*.app' -type d -print -quit)"
APP_NAME="$(basename "$APP_PATH")"
cp -R "$APP_PATH" "$STAGE/"
hdiutil detach "$STAGE/mnt" >/dev/null 2>&1 || true
cat > "$STAGE/package-distribution.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>title>Zoom Private Client</key>
	<key>version</key>
	<string>1.0.0</string>
	<key>installScope</key>
	<string>system</string>
	<key>installLocation</key>
	<string>/usr/local/zoom-private</string>
	<key>distributionReference</key>
	<array/>
	<key>components</key>
	<array/>
	<key>scripts</key>
	<array>
		<dict>
			<key>script</key>
			<string>postinstall</string>
			<key>scriptFile</key>
			<string>postinstall</string>
			<key>version</key>
			<string>1.0.0</string>
		</dict>
	</array>
</dict>
</plist>
XML
cat > "$STAGE/postinstall" <<'SCRIPT'
#!/bin/bash
set -e
SRC="/usr/local/zoom-private/Zoom Private.app"
DST="/Applications/Zoom Private.app"
if [ -e "$DST" ]; then rm -rf "$DST"; fi
mkdir -p "$(dirname "$DST")"
cp -R "$SRC" "$DST"
SCRIPT
chmod +x "$STAGE/postinstall"
pkgbuild --root "$STAGE" --spec "$STAGE/package-distribution.xml" --out "$OUT"
productbuild --distribution "$STAGE/package-distribution.xml" --output "$OUT" "$OUT"
rm -rf "$STAGE_ROOT"
