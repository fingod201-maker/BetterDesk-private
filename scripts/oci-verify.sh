#!/bin/bash
ENV=/opt/betterdesk/console/.env
echo "=== admin password from env ==="
sudo grep -E '^DEFAULT_ADMIN_PASSWORD=|^ADMIN_PASSWORD=|^INIT_ADMIN_PASS=' $ENV 2>/dev/null
echo
PASS=$(sudo grep -E '^DEFAULT_ADMIN_PASSWORD=' $ENV 2>/dev/null | head -1 | cut -d= -f2-)
USER=$(sudo grep -E '^DEFAULT_ADMIN_USERNAME=' $ENV 2>/dev/null | head -1 | cut -d= -f2-)
USER=${USER:-admin}
echo "Using user=$USER pass=${PASS:0:2}****"
echo
echo "=== login to console ==="
COOKIE=/tmp/bd_cookies.txt
curl -s -c $COOKIE -X POST http://127.0.0.1:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}" -w "\nHTTP %{http_code}\n" 2>&1 | head -c 400
echo
echo "=== devices via console session ==="
curl -s -b $COOKIE http://127.0.0.1:5000/api/devices -w "\nHTTP %{http_code}\n" 2>&1 | head -c 1500
echo
echo
echo "=== API key auth variations on Go /api/peers ==="
KEY=$(sudo cat /opt/betterdesk/.api_key 2>/dev/null)
echo "-- Bearer --"; curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:21114/api/peers | head -c 300; echo
echo "-- X-API-Key --"; curl -s -H "X-API-Key: $KEY" http://127.0.0.1:21114/api/peers | head -c 300; echo
echo "-- query --"; curl -s "http://127.0.0.1:21114/api/peers?api_key=$KEY" | head -c 300; echo
echo "-- X-Api-Key --"; curl -s -H "X-Api-Key: $KEY" http://127.0.0.1:21114/api/peers | head -c 300; echo
echo
echo "=== CDAP device connections (gateway log) ==="
sudo journalctl -u betterdesk-server --no-pager -n 200 2>&1 | grep -iE 'EXQUISITE|BD-MCWX|cdap|device connect|register' | tail -20
