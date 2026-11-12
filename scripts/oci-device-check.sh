#!/bin/bash
B="http://127.0.0.1:5000"
JAR=/tmp/bd_jar.txt
rm -f $JAR /tmp/login.html
curl -s -c $JAR "$B/login" -o /tmp/login.html
TOKEN=$(grep -oE "csrfToken: '[^']+'" /tmp/login.html | head -1 | sed "s/csrfToken: '//;s/'//")
curl -s -b $JAR -c $JAR -X POST "$B/api/auth/login" \
  -H "Content-Type: application/json" -H "X-CSRF-Token: $TOKEN" \
  -d '{"username":"admin","password":"BetterDesk@2026!Admin"}' -o /dev/null
echo "=== Devices ==="
curl -s -b $JAR "$B/api/devices" | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]["devices"]
for x in d:
    print(x["id"], x["hostname"], "online="+str(x["online"]), "cdap="+str(x["cdap_connected"]), x["status_tier"], "last="+x["last_online"])
'
echo
echo "=== recent cdap auth events ==="
sudo journalctl -u betterdesk-server --no-pager -n 120 2>&1 | grep -iE 'cdap_auth|cdap_register|cdap.*BD-MCWX' | tail -8
