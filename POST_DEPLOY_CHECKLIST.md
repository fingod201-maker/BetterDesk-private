# BetterDesk 24/7 — Post-Deployment Checklist
# Run these on the target server after deployment completes.

## 1. DNS Verification
# Run from the target server:
./scripts/dns-check.sh
# Expected: both zoom.telcom.stream and panel.telcom.stream resolve to PUBLIC_IP

## 2. SSL Issuance
# After DNS is confirmed and nginx can answer on :80:
./scripts/ssl-setup.sh --issue
# Then reload nginx:
systemctl reload betterdesk-nginx   # bare metal
# or:
docker compose -f docker-compose.ops.yml restart nginx   # docker

## 3. Health Check
./scripts/health-check.sh
# Expected: ALL CHECKS PASSED, exit 0

## 4. Admin Console Access
# Open https://panel.telcom.stream in a browser
# Login with the admin credentials from .env.ops
# Verify the dashboard loads and devices list appears

## 5. Agent Connectivity Test
# Install the BetterDesk agent on a remote test device
# Point it at https://panel.telcom.stream
# Confirm the device appears online in the admin console
# Test: remote session, file transfer, terminal, chat

## 6. Monitoring
# Uptime Kuma status page: https://panel.telcom.stream:3001 (internal only)
# Verify both domain monitors show UP

## 7. Backups (cron)
# Add to root crontab:
#   0 3 * * * /opt/betterdesk/scripts/backup.sh >> /var/log/betterdesk/backup.log 2>&1
#   * * * * * /opt/betterdesk/scripts/uptime-monitor.sh >> /var/log/betterdesk/uptime.log 2>&1

## 8. SSL Auto-Renewal (timer)
# Verify certbot timer is active:
systemctl list-timers certbot-renew.timer   # bare metal
# Renewal runs twice daily; nginx auto-reloads on success
