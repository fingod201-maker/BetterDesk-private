# BetterDesk 24/7 Operations Runbook

## Architecture Overview

```
Internet
    |
    v
+---------------------+      443/SSL      +---------------------------+
|  Nginx Reverse Proxy| <---------------- |  zoom.telcom.stream       |
|  (port 80/443)      |                   |  -> Landing service (8080)|
+---------------------+                   +---------------------------+
        |
        |      443/SSL
        v
+---------------------+      443/SSL      +---------------------------+
|  Nginx Reverse Proxy| <---------------- |  panel.telcom.stream      |
|  (port 80/443)      |                   |  -> Node.js Console (5000)|
+---------------------+                   |  -> Go API (21121 via /api/)|
                                          +---------------------------+

Backend services (NOT exposed publicly — internal only):
  - Landing service:       127.0.0.1:8080   (zoom.telcom.stream)
  - Node.js Console:       127.0.0.1:5000   (panel.telcom.stream)
  - Go Server API:         127.0.0.1:21121  (panel.telcom.stream/api/)
  - Go Server Signal:      127.0.0.1:21116  (TCP+UDP, P2P signaling)
  - Go Server Relay:       127.0.0.1:21117  (TCP, media relay)
  - Go Server WS Signal:   127.0.0.1:21118  (WebSocket)
  - Go Server WS Relay:    127.0.0.1:21119  (WebSocket)
  - Go Server NAT test:    127.0.0.1:21115  (TCP)
```

## Domains

| Domain | Purpose | Backend |
|--------|---------|---------|
| `zoom.telcom.stream` | Public landing page + client downloads | Landing service (:8080) |
| `panel.telcom.stream` | Admin web console + client API | Node.js Console (:5000) + Go API (:21121) |

## Deployment

### Docker Compose (recommended)

```bash
export CERTBOT_EMAIL=admin@telcom.stream
export RELAY_PUBLIC_IP=YOUR.PUBLIC.IP
export SESSION_SECRET=$(openssl rand -hex 32)

# Initial deploy
./scripts/deploy-24x7.sh docker

# Issue SSL certificates
docker compose -f docker-compose.ops.yml --profile init run --rm certbot

# Verify health
./scripts/health-check.sh
```

### Bare Metal (systemd)

```bash
export CERTBOT_EMAIL=admin@telcom.stream
export RELAY_PUBLIC_IP=YOUR.PUBLIC.IP
export SESSION_SECRET=$(openssl rand -hex 32)

./scripts/deploy-24x7.sh bare
```

## DNS Configuration

Create A records at your DNS provider:

```
zoom.telcom.stream    A   YOUR.PUBLIC.IP
panel.telcom.stream   A   YOUR.PUBLIC.IP
```

## SSL / Certificate Management

Certificates are auto-renewed via certbot (twice daily timer).

```bash
# Check certificate status
./scripts/ssl-setup.sh --status

# Force renewal
./scripts/ssl-setup.sh --renew

# Initial issue (staging/test)
./scripts/ssl-setup.sh --issue --staging=1
```

## Health Checks

```bash
# Full health check (exit 0=healthy, 1=degraded, 2=critical)
./scripts/health-check.sh

# JSON output for monitoring integration
./scripts/health-check.sh --json

# Auto-remediate failures
./scripts/health-check.sh --fix
```

Uptime monitor runs every minute via cron and auto-restarts failed services:
```
* * * * * /usr/local/bin/bd-uptime-monitor
```

## Service Management (systemd)

```bash
# Status
systemctl status betterdesk-landing
systemctl status betterdesk-console
systemctl status betterdesk-nginx

# Restart
systemctl restart betterdesk-landing
systemctl restart betterdesk-console
systemctl restart betterdesk-nginx

# Logs
journalctl -u betterdesk-landing -f
journalctl -u betterdesk-console -f
journalctl -u betterdesk-nginx -f
```

## Docker Management

```bash
# View logs
docker compose -f docker-compose.ops.yml logs -f

# Restart a service
docker compose -f docker-compose.ops.yml restart landing-service
docker compose -f docker-compose.ops.yml restart betterdesk-console
docker compose -f docker-compose.ops.yml restart nginx

# Scale (if needed)
docker compose -f docker-compose.ops.yml up -d --scale betterdesk-console=2
```

## Backup Strategy

```bash
# SQLite database + auth.db
tar czf /backups/betterdesk-data-$(date +%F).tar.gz \
  /opt/betterdesk/data/ \
  /opt/betterdesk/web-nodejs/data/ \
  /etc/letsencrypt/ \
  /etc/nginx/

# Verify restore
tar tzf /backups/betterdesk-data-latest.tar.gz
```

## Monitoring Endpoints

| Endpoint | Purpose |
|----------|---------|
| `https://zoom.telcom.stream/healthz` | Landing service health |
| `https://panel.telcom.stream/health` | Admin console health |
| `https://panel.telcom.stream:3001` | Uptime Kuma status page (internal) |
| `http://localhost:8081` | cAdvisor container metrics (internal) |

## Port Firewall Rules (ufw example)

```bash
ufw allow 80/tcp    # HTTP -> HTTPS redirect
ufw allow 443/tcp   # HTTPS (both domains)
ufw allow 21116/tcp # Go signal TCP
ufw allow 21116/udp # Go signal UDP
ufw allow 21117/tcp # Go relay TCP
ufw allow 21115/tcp # NAT type test
ufw deny 5000/tcp   # Console — internal only (blocked by nginx)
ufw deny 8080/tcp   # Landing — internal only (blocked by nginx)
ufw deny 21121/tcp  # Go API — internal only (proxied via nginx)
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| 502 Bad Gateway on panel.telcom.stream | Console not running | `systemctl restart betterdesk-console` |
| 502 Bad Gateway on zoom.telcom.stream | Landing not running | `systemctl restart betterdesk-landing` |
| SSL certificate error | Certbot not issued / expired | `./scripts/ssl-setup.sh --issue` |
| Devices can't connect (relay) | RELAY_PUBLIC_IP wrong | Set to public IP, restart console |
| Port 80/443 conflict | Another web server | Stop conflicting service, only nginx binds 80/443 |
| WebSocket chat fails | Nginx not proxying Upgrade headers | Verify nginx.conf Upgrade/Connection headers |

## Security Checklist

- [ ] Nginx `server_tokens off` (hides version)
- [ ] TLS 1.2+ only, strong ciphers
- [ ] HSTS with preload
- [ ] Rate limiting on login/API endpoints
- [ ] `no-new-privileges` on all containers/services
- [ ] Non-root users for landing + console
- [ ] SESSION_SECRET 32+ characters
- [ ] ADMIN_PASSWORD 12+ characters
- [ ] Database files not web-accessible
- [ ] Certbot auto-renewal timer active
- [ ] Health check cron or monitoring configured
