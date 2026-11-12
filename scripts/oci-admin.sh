#!/bin/bash
cd /opt/betterdesk/console
echo "=== .env admin lines ==="
sudo grep -nE 'ADMIN|PASS|CSRF|SESSION' .env 2>/dev/null | sed -E 's/(PASS[A-Z_]*=).*/\1<redacted>/'
echo
echo "=== how admin password is bootstrapped ==="
sudo grep -rnE 'DEFAULT_ADMIN_PASSWORD|INIT_ADMIN|ADMIN_PASSWORD|__DEFAULT_ADMIN' --include=*.js . 2>/dev/null | grep -v node_modules | head -20
echo
echo "=== auth.db schema + users ==="
sudo sqlite3 /opt/betterdesk/data/auth.db ".schema users" 2>&1 | head -20
sudo sqlite3 /opt/betterdesk/data/auth.db "SELECT id,username,role,length(password_hash) FROM users;" 2>&1
echo
echo "=== is bcrypt available in console? ==="
ls node_modules/bcryptjs node_modules/bcrypt 2>/dev/null
echo
echo "=== node version ==="
node -v
