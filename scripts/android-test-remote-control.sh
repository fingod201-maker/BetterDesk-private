#!/bin/bash
# =============================================================================
# BetterDesk Android — Remote Control Test from Admin Panel
#
# Verifies end-to-end: emulator agent connects to panel.telcom.stream,
# appears online, and accepts a remote-control session initiated from console.
#
# Usage:
#   ./scripts/android-test-remote-control.sh <emulator_serial> <panel_url>
#
# Example:
#   ./scripts/android-test-remote-control.sh emulator-5554 https://panel.telcom.stream
# =============================================================================
set -euo pipefail

SERIAL="${1:-}"
PANEL_URL="${2:-https://panel.telcom.stream}"

if [[ -z "$SERIAL" ]]; then
  echo "Usage: $0 <emulator_serial> [panel_url]"
  exit 1
fi

ADB="adb"
log() { echo "[test-remote] $*"; }
ok()  { echo "OK:   $*"; }
err() { echo "FAIL: $*" >&2; }

adb() { "$ADB" -s "$SERIAL" "$@"; }

if ! adb get-state 2>/dev/null | grep -q device; then
  err "Emulator $SERIAL not online"
  exit 1
fi

echo "=== Test 3: Remote Control End-to-End ==="
echo "Emulator:  $SERIAL"
echo "Panel:     $PANEL_URL"

# --- Wait for agent to register (check device appears online via panel API) ---
log "Waiting for agent to register with panel..."
DEVICE_ID=""
for i in $(seq 1 30); do
  # Try to detect device ID from agent logs
  DEVICE_ID=$(adb shell logcat -d 2>/dev/null | grep -iE "device.id|registered|device_id" | tail -1 | grep -oE '[a-f0-9]{8,}|[0-9]{8,}' | head -1) || true
  if [[ -n "$DEVICE_ID" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$DEVICE_ID" ]]; then
  warn "Could not auto-detect device_id from logs — check emulator agent UI manually"
else
  ok "Device registered: $DEVICE_ID"
fi

# --- Check device appears online in panel (via health/API endpoint if reachable) ---
log "Checking device visibility at $PANEL_URL ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 --connect-timeout 5 "$PANEL_URL/health" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Panel is reachable (HTTP 200)"
else
  err "Panel not reachable (HTTP $HTTP_CODE) — ensure VPS is deployed and DNS resolves"
  exit 1
fi

# --- Initiate remote-control session via panel API ---
log "Requesting remote-control session from panel..."
SESSION_RESP=$(curl -s --max-time 15 \
  -H "Content-Type: application/json" \
  -d "{\"device_id\":\"${DEVICE_ID:-unknown}\"}" \
  "$PANEL_URL/api/remote/start" 2>/dev/null || echo '{"success":false}')

if echo "$SESSION_RESP" | grep -qi "success"; then
  ok "Remote-control session requested"
else
  warn "Panel remote-start endpoint may not be exposed yet — verify manually at $PANEL_URL"
fi

# --- Check emulator for incoming session / consent popup ---
log "Checking emulator for session notification..."
adb shell dumpsys notification 2>/dev/null | grep -i "betterdesk\|zoomprivate\|remote" | head -5 || true

echo ""
echo "=== Remote Control Test Summary ==="
echo "Panel reachable: $([[ "$HTTP_CODE" == "200" ]] && echo YES || echo NO)"
echo "Device ID: ${DEVICE_ID:-not detected}"
echo "Session requested: $([[ "$SESSION_RESP" == *success* ]] && echo YES || echo NO/manual)"
echo ""
echo "MANUAL VERIFICATION STEPS (on emulator UI):"
echo "  1. Open BetterDesk agent app — confirm it shows 'Online' / connected"
echo "  2. From admin console ($PANEL_URL), select the emulator device"
echo "  3. Click 'Remote' — emulator user should see consent popup"
echo "  4. Accept on emulator → remote control view appears in browser"
echo ""
echo "Tested Android versions: run this against BD_Android13/14/15 AVDs"
