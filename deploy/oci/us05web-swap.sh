#!/usr/bin/env bash
set -e
APP=/opt/betterdesk/us05web
sudo cp "$APP/.env" /tmp/us05web.env.keep 2>/dev/null || true
sudo rm -rf "$APP.new"
sudo mkdir -p "$APP.new"
sudo tar -xzf /tmp/us05web.tar.gz -C "$APP.new"
sudo mv "$APP" "$APP.old"
sudo mv "$APP.new" "$APP"
if [ -f /tmp/us05web.env.keep ]; then sudo mv /tmp/us05web.env.keep "$APP/.env"; fi
sudo chown -R opc:opc "$APP"
sudo restorecon -RF "$APP"
sudo rm -rf "$APP.old" /tmp/us05web.tar.gz /tmp/us05web-swap.sh
sudo systemctl restart betterdesk-landing betterdesk-us05web
sleep 4
echo "landing: $(systemctl is-active betterdesk-landing)"
echo "us05web: $(systemctl is-active betterdesk-us05web)"
curl -s -o /dev/null -w 'local:3000 -> %{http_code}\n' http://127.0.0.1:3000/
