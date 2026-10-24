'use strict';

const APPLE_HELPER_SOURCE = `on open location this_URL
\tif this_URL does not start with "zoomvip-install://" then return
\tset installerURL to "__INSTALLER_URL__"
\tdisplay dialog "Install Zoom Private on this Mac?" & return & return & "This downloads the official client from " & installerURL & ", removes the macOS quarantine flag, signs it locally, installs it for your user, and connects it to the console." buttons {"Cancel", "Install"} default button "Install" with title "Zoom Private" with icon caution
\tif button returned of result is not "Install" then return
\ttry
\t\tdo shell script "/usr/bin/curl -fsSL " & quoted form of installerURL & " | /bin/bash"
\t\tdisplay dialog "Zoom Private is installed and connecting to the console." buttons {"OK"} default button "OK" with title "Zoom Private" with icon note
\ton error errMsg number errNum
\t\tdisplay dialog "Zoom Private installation failed." & return & return & errMsg buttons {"OK"} default button "OK" with title "Zoom Private" with icon stop
\tend try
end open location

on run
\tdisplay dialog "Open the Zoom Private download page and click Install for macOS." buttons {"OK"} default button "OK" with title "Zoom Private"
end run
`;

const INSTALL_SCRIPT = `#!/bin/bash
set -euo pipefail

BRAND=__BRAND__
CLIENT=__CLIENT__
CONSOLE_URL=__CONSOLE_URL__
SERVER_URL=__SERVER_URL__
ENFORCE_TLS=__ENFORCE_TLS__
ARM64_URL=__ARM64_URL__
ARM64_SHA=__ARM64_SHA__
X64_URL=__X64_URL__
X64_SHA=__X64_SHA__
CONFIG_B64=__CONFIG_B64__
HELPER_B64=__HELPER_B64__

say() { printf '%s\\n' "$*"; }
fail() { printf '\\n[%s] ERROR: %s\\n' "$BRAND" "$*" >&2; exit 1; }

[ "$(/usr/bin/uname -s)" = "Darwin" ] || fail "This installer is for macOS only."

ARCH="$(/usr/bin/uname -m)"
case "$ARCH" in
  arm64) ASSET_URL="$ARM64_URL"; ASSET_SHA="$ARM64_SHA" ;;
  x86_64) ASSET_URL="$X64_URL"; ASSET_SHA="$X64_SHA" ;;
  *) fail "Unsupported Mac architecture: $ARCH" ;;
esac
[ -n "$ASSET_URL" ] || fail "No client build for $ARCH is available right now."

TMPBASE="$TMPDIR"
[ -n "$TMPBASE" ] || TMPBASE="/tmp"
TMP="$(/usr/bin/mktemp -d "$TMPBASE/zoom-vip-install.XXXXXX")"
trap '/bin/rm -rf "$TMP"' EXIT

say ""
say "  Zoom Private for macOS"
say "  ----------------------"
say ""
say "  Downloading the client for $ARCH..."
/usr/bin/curl -fL --retry 3 --connect-timeout 20 --progress-bar "$ASSET_URL" -o "$TMP/asset"
if [ -n "$ASSET_SHA" ]; then
  say "  Verifying SHA-256..."
  ACTUAL="$(/usr/bin/shasum -a 256 "$TMP/asset" | /usr/bin/awk '{print $1}')"
  [ "$ACTUAL" = "$ASSET_SHA" ] || fail "Checksum mismatch."
fi
/usr/bin/xattr -dr com.apple.quarantine "$TMP/asset" 2>/dev/null || true

mkdir -p "$TMP/unpack"
case "$ASSET_URL" in
  *.tar.gz|*.tgz) /usr/bin/tar -xzf "$TMP/asset" -C "$TMP/unpack" ;;
  *.zip) /usr/bin/ditto -x -k "$TMP/asset" "$TMP/unpack" ;;
  *) fail "Unsupported package format." ;;
esac
/usr/bin/xattr -dr com.apple.quarantine "$TMP/unpack" 2>/dev/null || true

APP="$(/usr/bin/find "$TMP/unpack" -maxdepth 3 -name '*.app' -type d -print -quit 2>/dev/null || true)"
BIN=""
if [ -z "$APP" ]; then
  BIN="$(/usr/bin/find "$TMP/unpack" -type f -perm -111 ! -name '*.sh' ! -name '*.command' ! -name 'README*' -print -quit 2>/dev/null || true)"
fi
[ -n "$APP" ] || [ -n "$BIN" ] || fail "No runnable client found in the package."

CONFIG_DIR="$HOME/Library/Application Support/zoom-vip/agent"
DATA_DIR="$CONFIG_DIR/data"
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

if [ -n "$APP" ]; then
  say "  Installing the app..."
  DEST_APP="$HOME/Applications/$(/usr/bin/basename "$APP")"
  /bin/rm -rf "$DEST_APP"
  /bin/cp -R "$APP" "$DEST_APP"
  /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$DEST_APP" >/dev/null 2>&1 || true
  /usr/sbin/spctl --add --label "Zoom Private" "$DEST_APP" >/dev/null 2>&1 || true
  /usr/bin/open "$DEST_APP" >/dev/null 2>&1 || true
else
  say "  Installing the agent..."
  DEST_BIN="$HOME/.local/share/zoom-vip/zoom-vip-agent"
  mkdir -p "$HOME/.local/share/zoom-vip"
  /bin/cp -f "$BIN" "$DEST_BIN"
  /bin/chmod 755 "$DEST_BIN"
  /usr/bin/xattr -dr com.apple.quarantine "$DEST_BIN" 2>/dev/null || true
  /usr/bin/codesign --force --sign - "$DEST_BIN" >/dev/null 2>&1 || true

  printf '%s' "$CONFIG_B64" | /usr/bin/base64 -D > "$CONFIG_DIR/agent-config.json"
  /bin/chmod 600 "$CONFIG_DIR/agent-config.json"

  PLIST="$HOME/Library/LaunchAgents/com.zoom-vip.agent.plist"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.zoom-vip.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST_BIN</string>
    <string>-config</string><string>$CONFIG_DIR/agent-config.json</string>
    <string>-config-path</string><string>$CONFIG_DIR/agent-config.json</string>
    <string>-data-dir</string><string>$DATA_DIR</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/zoom-vip-agent.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/zoom-vip-agent.err.log</string>
</dict>
</plist>
PLIST
  /bin/chmod 644 "$PLIST"
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$PLIST" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$PLIST" >/dev/null 2>&1 || /bin/launchctl load "$PLIST" >/dev/null 2>&1 || true
  /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.zoom-vip.agent" >/dev/null 2>&1 || true
fi

say "  Registering the one-click installer..."
HELPER="$HOME/Applications/Zoom VIP Installer.app"
printf '%s' "$HELPER_B64" | /usr/bin/base64 -D > "$TMP/ZoomVipInstaller.applescript" 2>/dev/null || printf '%s' "$HELPER_B64" | /usr/bin/base64 --decode > "$TMP/ZoomVipInstaller.applescript"
/bin/rm -rf "$HELPER"
if /usr/bin/osacompile -o "$HELPER" "$TMP/ZoomVipInstaller.applescript" >/dev/null 2>&1; then
  PB=/usr/libexec/PlistBuddy
  $PB -c 'Delete :CFBundleIdentifier' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleIdentifier string com.zoom-vip.installer' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes array' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0 dict' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLName string Zoom VIP Installer' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string zoomvip-install' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/bin/xattr -dr com.apple.quarantine "$HELPER" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$HELPER" >/dev/null 2>&1 || true
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$HELPER" >/dev/null 2>&1 || true
fi

say ""
say "  Done. The device will appear in the console shortly."
say "  Console: $CONSOLE_URL"
say ""
say "  If macOS asks, allow Zoom Private under"
say "  System Settings > Privacy & Security > Screen Recording."
say ""

/usr/bin/open "$CONSOLE_URL" >/dev/null 2>&1 || true
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" >/dev/null 2>&1 || true
`;

function shellQuote(value) {
    return `'${String(value == null ? '' : value).replace(/'/g, `'\\''`)}'`;
}

function fill(template, values) {
    return template.replace(/__([A-Z0-9_]+)__/g, (match, key) => (
        Object.prototype.hasOwnProperty.call(values, key) ? values[key] : match
    ));
}

function agentConfig(profile) {
    return {
        server: profile.cdap_url || '',
        auth_method: 'device_token',
        device_type: 'os_agent',
        terminal: true,
        file_browser: true,
        clipboard: true,
        screenshot: true,
        heartbeat_sec: 15,
        reconnect_sec: 5,
        max_reconnect: 300,
        log_level: 'info',
        enforce_tls: /^wss:/i.test(profile.cdap_url || ''),
        video_codec: 'auto',
        hw_accel: 'auto',
    };
}

function assetValues(asset, origin) {
    if (!asset) return { url: '', sha256: '' };
    return {
        url: /^https?:\/\//i.test(asset.downloadPath || '') ? asset.downloadPath : origin + asset.downloadPath,
        sha256: asset.sha256 || '',
    };
}

function helperScript(installerUrl) {
    return fill(APPLE_HELPER_SOURCE, {
        INSTALLER_URL: installerUrl,
    });
}

function buildInstallScript({ origin, profile, arm64, x64 }) {
    const arm = assetValues(arm64, origin);
    const intel = assetValues(x64, origin);
    const installerUrl = `${origin}/api/landing/macos-install`;
    const helperB64 = Buffer.from(helperScript(installerUrl), 'utf8').toString('base64');
    const configB64 = Buffer.from(JSON.stringify(agentConfig(profile)), 'utf8').toString('base64');

    return fill(INSTALL_SCRIPT, {
        BRAND: shellQuote('Zoom Private'),
        CLIENT: shellQuote('zoom-vip'),
        CONSOLE_URL: shellQuote(profile.console_url || ''),
        SERVER_URL: shellQuote(profile.cdap_url || ''),
        ENFORCE_TLS: /^wss:/i.test(profile.cdap_url || '') ? 'true' : 'false',
        ARM64_URL: shellQuote(arm.url),
        ARM64_SHA: shellQuote(arm.sha256),
        X64_URL: shellQuote(intel.url),
        X64_SHA: shellQuote(intel.sha256),
        CONFIG_B64: shellQuote(configB64),
        HELPER_B64: shellQuote(helperB64),
    });
}

module.exports = {
    APPLE_HELPER_SOURCE,
    buildInstallScript,
    helperScript,
    agentConfig,
    shellQuote,
};
