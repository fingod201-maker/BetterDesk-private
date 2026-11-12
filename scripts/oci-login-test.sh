#!/bin/bash
B="http://127.0.0.1:5000"
JAR=/tmp/bd_jar.txt
rm -f $JAR
NEWPASS='BetterDesk@2026!Admin'

curl -s -c $JAR "$B/login" -o /tmp/login.html -w "login HTTP %{http_code}\n"
TOKEN=$(grep -oE "csrfToken: '[^']+'" /tmp/login.html | head -1 | sed "s/csrfToken: '//;s/'//")
echo "token len: ${#TOKEN}"

echo "=== login ==="
curl -s -b $JAR -c $JAR -X POST "$B/api/auth/login" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $TOKEN" \
  -d "{\"username\":\"admin\",\"password\":\"$NEWPASS\"}" \
  -w "\nHTTP %{http_code}\n"

echo "=== devices ==="
curl -s -b $JAR "$B/api/devices" -w "\nHTTP %{http_code}\n" | head -c 2500
