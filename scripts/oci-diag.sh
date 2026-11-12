#!/bin/bash
echo "=== Removing conflicting crash-looping container ==="
sudo podman rm -f betterdesk 2>&1
echo
echo "=== Existing systemd services ==="
for svc in betterdesk-server betterdesk-console; do
  echo "--- $svc ---"
  systemctl is-active $svc 2>&1
  systemctl show $svc -p ExecStart -p WorkingDirectory --no-pager 2>&1 | head -3
  echo
done
echo "=== What serves port 80/443? ==="
sudo ss -tlnp | grep -E ':(80|443) ' || echo "Nothing on 80/443"
echo
echo "=== Reverse proxy candidates ==="
for svc in nginx caddy cloudflared httpd apache2; do
  printf "%-12s " "$svc:"; systemctl is-active $svc 2>/dev/null || echo "not-found"
done
echo
echo "=== cloudflared config? ==="
ls -la /etc/cloudflared/ 2>/dev/null || echo "no /etc/cloudflared"
ls -la /root/.cloudflared/ 2>/dev/null || echo "no /root/.cloudflared"
echo
echo "=== Running service versions ==="
curl -s http://127.0.0.1:21114/api/version 2>&1 | head -c 200; echo
echo
echo "=== Console health ==="
curl -s -o /dev/null -w "console 5000: HTTP %{http_code} redirect=%{redirect_url}\n" http://127.0.0.1:5000/
echo
echo "=== Does panel.telcom.stream resolve? ==="
getent hosts panel.telcom.stream || echo "no local resolution"
echo
echo "=== Recent server logs ==="
sudo journalctl -u betterdesk-server --no-pager -n 8 2>&1
