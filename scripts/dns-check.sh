#!/bin/bash
# =============================================================================
# BetterDesk DNS Pre-Flight Check
# Verifies zoom.telcom.stream and panel.telcom.stream resolve to this server.
# Run on the target server before deploying SSL.
# =============================================================================
set -euo pipefail

PUBLIC_IP=$(curl -4 -sf --max-time 10 https://api.ipify.org 2>/dev/null \
    || curl -4 -sf --max-time 10 https://ifconfig.me/ip 2>/dev/null \
    || echo "UNKNOWN")

DOMAINS=("zoom.telcom.stream" "panel.telcom.stream")
ALL_OK=0

echo "Public IP of this server: $PUBLIC_IP"
echo ""

for domain in "${DOMAINS[@]}"; do
  RESOLVED=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | head -1) || RESOLVED=""
  if [[ -z "$RESOLVED" ]]; then
    echo "FAIL: $domain does not resolve (no DNS record)"
    ALL_OK=1
  elif [[ "$RESOLVED" == "$PUBLIC_IP" ]]; then
    echo "OK:   $domain -> $RESOLVED (matches public IP)"
  else
    echo "WARN: $domain -> $RESOLVED (does NOT match public IP $PUBLIC_IP)"
    ALL_OK=1
  fi
done

echo ""
if [[ $ALL_OK -eq 0 ]]; then
  echo "All DNS checks passed. Ready to issue SSL certificates."
  exit 0
else
  echo "DNS issues found. Fix A records before running ssl-setup.sh --issue"
  exit 1
fi
