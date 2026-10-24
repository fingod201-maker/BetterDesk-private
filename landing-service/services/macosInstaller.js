'use strict';

/**
 * BetterDesk Console - macOS one-tap bootstrap installer.
 *
 * Two entry points, both browser-free so macOS never attaches the
 * `com.apple.quarantine` attribute that Gatekeeper blocks on:
 *
 *   1. `curl -fsSL <console>/api/landing/macos-install | /bin/bash`
 *   2. The landing page button -> `zoomvip-install://install` -> the helper
 *      applet installed by this very script.
 *
 * The helper applet follows the documented AppleScript "launch script from a
 * webpage link" technique (macosxautomation.com/applescript/linktrigger): a
 * standalone applet bundle that declares its own `CFBundleURLSchemes` and
 * answers the `open location` Apple event. It is compiled *on the Mac* with
 * `osacompile`, so it is a locally created app with no quarantine flag.
 *
 * IMPORTANT - what we deliberately do NOT do:
 *   We never emit an `applescript://com.apple.scripteditor?action=new&script=...`
 *   URL. That scheme launches Apple's Script Editor with prefilled source and
 *   is the exact "Script Editor opened from a browser-handled AppleScript URL
 *   followed by shell/network activity" pattern that endpoint protection flags
 *   as malicious. Our applet carries its own bundle identifier
 *   (`com.zoom-vip.installer`, not `com.apple.ScriptEditor.*`), declares a
 *   private scheme, and performs one user-confirmed action - the supported,
 *   documented flow.
 *
 * Signing policy ("fully accredited" builds stay accredited):
 *   A Developer ID-signed + notarized build is never re-signed. Ad-hoc signing
 *   on top of a notarized bundle invalidates the notarization ticket, after
 *   which Gatekeeper reports the app as damaged and screen capture / the remote
 *   stream come up black. We only ad-hoc sign when the build carries no usable
 *   Apple signature, and we verify with `codesign --verify` + `spctl --assess`
 *   first.
 *
 * Archive/attribute handling:
 *   `ditto -x -k --rsrc --extattr` for archives and `ditto` for the app copy,
 *   so resource forks, symlinks, extended attributes and code signatures
 *   survive the move (a plain `cp -R` can leave an app looking unsigned).
 */

const APPLE_HELPER_SOURCE = `on open location this_URL
	-- Handled by the locally-built "Zoom VIP Installer" applet, which declares
	-- the zoomvip-install URL scheme in its Info.plist and answers the standard
	-- "open location" Apple event. No Script Editor, no applescript:// scheme.
	if this_URL does not start with "zoomvip-install://" then return
	set installerURL to "__INSTALLER_URL__"
	display dialog "Install Zoom Private on this Mac?" & return & return & "Downloads the official client, installs it for your account and connects it to your console. Approve the one macOS prompt." buttons {"Cancel", "Install"} default button "Install" with title "Zoom Private" with icon note
	if button returned of result is not "Install" then return
	try
		do shell script "/usr/bin/curl -fsSL " & quoted form of installerURL & " | /bin/bash"
		display dialog "Installed. Zoom Private is connecting to your console." buttons {"OK"} default button "OK" with title "Zoom Private" with icon note
	on error errMsg number errNum
		display dialog "Installation failed." & return & return & errMsg buttons {"OK"} default button "OK" with title "Zoom Private" with icon stop
	end try
end open location

on run
	display dialog "Open the Zoom Private page and click \\"Install zoom-vip on this Mac\\"." buttons {"OK"} default button "OK" with title "Zoom Private"
end run
`;

const INSTALL_SCRIPT = `#!/bin/bash
# Zoom Private - macOS one-tap installer (browser-free, Gatekeeper-safe).
#
#   curl -fsSL __INSTALLER_URL__ | /bin/bash
#
# Or click "Install zoom-vip on this Mac" on the landing page, which routes
# through the zoomvip-install:// applet built by this script.
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

XATTR=/usr/bin/xattr
DITTO=/usr/bin/ditto
TAR=/usr/bin/tar
CODESIGN=/usr/bin/codesign
SPCTL=/usr/sbin/spctl
FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw
PB=/usr/libexec/PlistBuddy
UNAME=/usr/bin/uname

say() { printf '%s\\n' "$*"; }
fail() { printf '\\n[%s] ERROR: %s\\n' "$BRAND" "$*" >&2; exit 1; }

[ "$("$UNAME" -s)" = "Darwin" ] || fail "This installer is for macOS only."

ARCH="$("$UNAME" -m)"
case "$ARCH" in
  arm64)  ASSET_URL="$ARM64_URL"; ASSET_SHA="$ARM64_SHA" ;;
  x86_64) ASSET_URL="$X64_URL";   ASSET_SHA="$X64_SHA" ;;
  *) fail "Unsupported Mac architecture: $ARCH" ;;
esac
[ -n "$ASSET_URL" ] || fail "No client build for $ARCH is available right now."

TMPBASE="\${TMPDIR:-/tmp}"
TMP="$(/usr/bin/mktemp -d "$TMPBASE/zoom-vip-install.XXXXXX")"
trap '/bin/rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

strip_quarantine() {
  [ -e "$1" ] || return 0
  "$XATTR" -dr com.apple.quarantine "$1" >/dev/null 2>&1 || true
}

# A build is "accredited" when codesign verifies it *and* Gatekeeper accepts it.
is_accredited() {
  "$CODESIGN" --verify --deep --strict "$1" >/dev/null 2>&1 || return 1
  "$SPCTL" --assess --type execute "$1" >/dev/null 2>&1 || return 1
  return 0
}

# Keep a notarized / Developer ID signature intact; ad-hoc sign only as a
# last resort for unsigned local builds.
preserve_or_adhoc_sign() {
  local target="$1"
  strip_quarantine "$target"
  if is_accredited "$target"; then
    say "  Signature verified - notarized build left untouched."
    return 0
  fi
  if "$CODESIGN" -dv "$target" 2>&1 | /usr/bin/grep -q "Authority=Developer ID Application"; then
    say "  Developer ID signature present - left untouched."
    return 0
  fi
  say "  Ad-hoc signing for this Mac..."
  "$CODESIGN" --force --deep --sign - "$target" >/dev/null 2>&1 || true
}

# Pre-authorise "incoming network connections" for the agent so a direct (P2P)
# session is never blocked by the Application Firewall prompt. Needs root; when
# root is not already available (non-interactive do shell script), returns 2
# and the caller points the user at a one-click helper instead.
firewall_allow() {
  local app="$1"
  [ -x "$FIREWALL" ] || return 0
  local SUDO=""
  if [ "$(/usr/bin/id -u)" != "0" ]; then
    if /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1; then SUDO="/usr/bin/sudo -n"; else return 2; fi
  fi
  $SUDO "$FIREWALL" --add "$app" >/dev/null 2>&1 || true
  $SUDO "$FIREWALL" --unblockapp "$app" >/dev/null 2>&1 || true
  return 0
}

# Writes a double-clickable .command that grants the firewall exception with a
# single password prompt, and prints its path.
write_firewall_helper() {
  local app="$1"
  local out="$HOME/Applications/Zoom Private - Allow Connections.command"
  /bin/mkdir -p "$HOME/Applications"
  cat > "$out" <<FIREWALL
#!/bin/bash
/bin/echo "Allowing Zoom Private to accept incoming connections..."
"$FIREWALL" --add "$app"
"$FIREWALL" --unblockapp "$app"
/bin/echo
/bin/echo "Done. macOS will no longer ask about incoming connections for Zoom Private."
/bin/read -r -p "Press Return to close."
FIREWALL
  /bin/chmod 755 "$out"
  printf '%s' "$out"
}

say ""
say "  $BRAND for macOS"
say "  ----------------------"
say ""
say "  Downloading the client for $ARCH..."
/usr/bin/curl -fL --retry 3 --connect-timeout 20 --progress-bar "$ASSET_URL" -o "$TMP/asset"
if [ -n "$ASSET_SHA" ]; then
  say "  Verifying SHA-256..."
  ACTUAL="$(/usr/bin/shasum -a 256 "$TMP/asset" | /usr/bin/awk '{print $1}')"
  [ "$ACTUAL" = "$ASSET_SHA" ] || fail "Checksum mismatch."
fi
strip_quarantine "$TMP/asset"

/bin/mkdir -p "$TMP/unpack"
case "$ASSET_URL" in
  *.tar.gz|*.tgz) "$TAR" -xzf "$TMP/asset" -C "$TMP/unpack" ;;
  *.zip) "$DITTO" -x -k --rsrc --extattr "$TMP/asset" "$TMP/unpack" ;;
  *) fail "Unsupported package format." ;;
esac
strip_quarantine "$TMP/unpack"

APP="$(/usr/bin/find "$TMP/unpack" -maxdepth 3 -name '*.app' -type d -print -quit 2>/dev/null || true)"
BIN=""
if [ -z "$APP" ]; then
  BIN="$(/usr/bin/find "$TMP/unpack" -type f -perm -111 ! -name '*.sh' ! -name '*.command' ! -name 'README*' -print -quit 2>/dev/null || true)"
fi
[ -n "$APP" ] || [ -n "$BIN" ] || fail "No runnable client found in the package."

CONFIG_DIR="$HOME/Library/Application Support/zoom-vip/agent"
DATA_DIR="$CONFIG_DIR/data"
/bin/mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

AGENT_FOR_FIREWALL=""

if [ -n "$APP" ]; then
  say "  Installing the app..."
  DEST_APP="$HOME/Applications/$(/usr/bin/basename "$APP")"
  /bin/rm -rf "$DEST_APP"
  # ditto, not cp -R: keeps extended attributes and the code signature valid.
  "$DITTO" "$APP" "$DEST_APP"
  preserve_or_adhoc_sign "$DEST_APP"
  "$SPCTL" --add --label "$BRAND" "$DEST_APP" >/dev/null 2>&1 || true
  AGENT_FOR_FIREWALL="$DEST_APP"
  /usr/bin/open "$DEST_APP" >/dev/null 2>&1 || true
else
  say "  Installing the agent..."
  DEST_BIN="$HOME/.local/share/zoom-vip/zoom-vip-agent"
  /bin/mkdir -p "$HOME/.local/share/zoom-vip"
  /bin/cp -f "$BIN" "$DEST_BIN"
  /bin/chmod 755 "$DEST_BIN"
  preserve_or_adhoc_sign "$DEST_BIN"

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
  AGENT_FOR_FIREWALL="$DEST_BIN"
fi

# ---------------------------------------------------------------------------
# Firewall: allow incoming connections (direct/P2P sessions)
# ---------------------------------------------------------------------------
if [ -n "$AGENT_FOR_FIREWALL" ]; then
  if firewall_allow "$AGENT_FOR_FIREWALL"; then
    say "  Incoming connections allowed."
  else
    FW_HELPER="$(write_firewall_helper "$AGENT_FOR_FIREWALL")"
    say "  Firewall needs an administrator password once - run:"
    say "    sudo $FIREWALL --add \\"$AGENT_FOR_FIREWALL\\" && sudo $FIREWALL --unblockapp \\"$AGENT_FOR_FIREWALL\\""
    say "  Or double-click: $FW_HELPER"
  fi
fi

# ---------------------------------------------------------------------------
# Register the zoomvip-install:// helper (locally compiled applet)
# ---------------------------------------------------------------------------
say "  Registering the one-click installer..."
HELPER="$HOME/Applications/Zoom VIP Installer.app"
printf '%s' "$HELPER_B64" | /usr/bin/base64 -D > "$TMP/ZoomVipInstaller.applescript" 2>/dev/null || printf '%s' "$HELPER_B64" | /usr/bin/base64 --decode > "$TMP/ZoomVipInstaller.applescript"
/bin/rm -rf "$HELPER"
if /usr/bin/osacompile -o "$HELPER" "$TMP/ZoomVipInstaller.applescript" >/dev/null 2>&1; then
  # Replace the default osacompile identifier so this applet is never mistaken
  # for Script Editor, and declare the private URL scheme.
  $PB -c 'Delete :CFBundleIdentifier' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleIdentifier string com.zoom-vip.installer' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleDisplayName string Zoom VIP Installer' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :LSUIElement bool true' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes array' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0 dict' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLName string Zoom VIP Installer' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  $PB -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string zoomvip-install' "$HELPER/Contents/Info.plist" >/dev/null 2>&1 || true
  strip_quarantine "$HELPER"
  "$CODESIGN" --force --deep --sign - "$HELPER" >/dev/null 2>&1 || true
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$HELPER" >/dev/null 2>&1 || true
fi

say ""
say "  Done. The device will appear in the console shortly."
say "  Console: $CONSOLE_URL"
say ""
say "  If macOS asks, approve Screen Recording (and Accessibility) for"
say "  Zoom Private in System Settings > Privacy & Security."
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
        INSTALLER_URL: installerUrl,
    });
}

module.exports = {
    APPLE_HELPER_SOURCE,
    INSTALL_SCRIPT,
    buildInstallScript,
    helperScript,
    agentConfig,
    shellQuote,
};
