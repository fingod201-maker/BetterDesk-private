#!/bin/bash
set -e
ENV=/opt/betterdesk/console/.env
NEWPASS='BetterDesk@2026!Admin'
NEWSECRET=$(openssl rand -hex 32)

echo "=== Backing up .env ==="
sudo cp $ENV ${ENV}.bak.$(date +%s)

echo "=== Setting real DEFAULT_ADMIN_PASSWORD + SESSION_SECRET ==="
# Replace password line
sudo sed -i "s|^DEFAULT_ADMIN_PASSWORD=.*|DEFAULT_ADMIN_PASSWORD=${NEWPASS}|" $ENV
# Replace session secret placeholder / value
sudo sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=${NEWSECRET}|" $ENV

echo "=== Confirming (redacted) ==="
sudo grep -E '^DEFAULT_ADMIN_PASSWORD=|^SESSION_SECRET=' $ENV | sed -E 's/=(.{3}).*/=\1***(set)/'

echo "=== Creating force-password-update sentinel ==="
sudo touch /opt/betterdesk/data/.force_password_update
sudo ls -la /opt/betterdesk/data/.force_password_update

echo "=== Restarting console ==="
sudo systemctl restart betterdesk-console
sleep 5
systemctl is-active betterdesk-console

echo "=== Console log: password update lines ==="
sudo journalctl -u betterdesk-console --no-pager -n 40 2>&1 | grep -iE 'AUTH|admin|password|force' | tail -15

echo "=== Sentinel consumed? ==="
sudo ls -la /opt/betterdesk/data/.force_password_update 2>&1 || echo "sentinel removed (good)"
