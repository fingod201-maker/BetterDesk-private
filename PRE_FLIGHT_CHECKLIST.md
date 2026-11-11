# BetterDesk — Pre-Flight Completeness Checklist
# Run this BEFORE publishing zoom.telcom.stream to staff globally.
# Target state: all checks PASS before go-live.

# =============================================================================
# SECTION A — DNS & DOMAINS
# =============================================================================
[ ] A record: zoom.telcom.stream  → <VPS_PUBLIC_IP>  (Cloudflare DNS only, grey cloud)
[ ] A record: panel.telcom.stream → <VPS_PUBLIC_IP>  (Cloudflare DNS only, grey cloud)
[ ] DNS propagation verified: `dig +short zoom.telcom.stream` returns VPS IP
[ ] DNS propagation verified: `dig +short panel.telcom.stream` returns VPS IP
[ ] DNS check script passes: ./scripts/dns-check.sh

# =============================================================================
# SECTION B — ENVIRONMENT & SECRETS
# =============================================================================
[ ] .env.ops created from .env.ops.example
[ ] CERTBOT_EMAIL set (real admin email, receives Let's Encrypt expiry notices)
[ ] RELAY_PUBLIC_IP set to VPS public IP (clients relay through it)
[ ] SESSION_SECRET set (32+ random hex chars)
[ ] ADMIN_PASSWORD set (12+ chars)
[ ] .env.ops NOT committed to git (secrets)

# =============================================================================
# SECTION C — DEPLOYMENT (Docker or Bare Metal)
# =============================================================================
[ ] Docker installed on VPS (or systemd + nginx + certbot for bare metal)
[ ] `./scripts/validate-deploy.sh` passes with 0 errors
[ ] Landing service builds and runs (port 8080 internal)
[ ] Console + Go server builds and runs (port 5000 internal, 21121 internal)
[ ] Nginx reverse proxy binds 80/443 (public)
[ ] Nginx config syntax valid: `nginx -t`
[ ] All ports unique — no conflicts (80, 443, 5000, 8080, 21115–21121)

# =============================================================================
# SECTION D — SSL / TLS
# =============================================================================
[ ] Let's Encrypt cert issued for zoom.telcom.stream
[ ] Let's Encrypt cert issued for panel.telcom.stream
[ ] certbot-renew timer active (auto-renewal twice daily)
[ ] `./scripts/ssl-setup.sh --status` shows valid certs (>30 days remaining)
[ ] HTTPS redirects work: http://zoom.telcom.stream → https://zoom.telcom.stream
[ ] HTTPS redirects work: http://panel.telcom.stream → https://panel.telcom.stream
[ ] SSL Labs grade A (or test with `./scripts/ssl-setup.sh --status`)

# =============================================================================
# SECTION E — HEALTH & MONITORING
# =============================================================================
[ ] `./scripts/health-check.sh` → ALL CHECKS PASSED (exit 0)
[ ] Landing health: https://zoom.telcom.stream/healthz  → 200
[ ] Panel health: https://panel.telcom.stream/health     → 200
[ ] Nginx process running + auto-restart enabled
[ ] Landing service process running + auto-restart enabled
[ ] Console process running + auto-restart enabled
[ ] Uptime monitor cron active (* * * * *)
[ ] Backup cron active (0 3 * * *)

# =============================================================================
# SECTION F — ARTIFACTS & DOWNLOADS
# =============================================================================
[ ] Android APK(s) present in distro/clients/ (universal + arm64)
[ ] Windows installer (.exe / .msi) present in distro/clients/
[ ] macOS installer (.dmg / .pkg) present in distro/clients/
[ ] Linux installer (.deb / .AppImage) present in distro/clients/
[ ] CHECKSUMS.sha256 present in distro/clients/
[ ] `./scripts/verify-artifacts.sh` → ALL ARTIFACTS VERIFIED
[ ] APKs signed (apksigner verify passes) — otherwise Android prompts "unknown source"
[ ] Landing page auto-detects OS and offers correct installer
[ ] /download/android serves the APK with correct MIME (application/vnd.android.package-archive)
[ ] /api/landing/client returns recommended download + full platform list

# =============================================================================
# SECTION G — BACKEND INTERNET-COMMUNICATION HARDENING
# =============================================================================
[ ] Landing service: security headers applied (HSTS, X-Frame-Options DENY, CSP, X-Content-Type-Options)
[ ] Landing service: rate limiting active on /api/ and /download/ endpoints
[ ] Landing service: CORS default same-origin only (LANDING_ALLOWED_ORIGINS optional)
[ ] Console: security middleware active (already in codebase)
[ ] Console: CSRF double-submit protection active
[ ] Console: rate limiting on /api/ endpoints
[ ] Console: TRUST_PROXY set correctly if behind nginx/Cloudflare
[ ] Go server: RELAY_SERVERS set to public IP (not Docker internal IP)
[ ] Go server: signal rate limiting (SIGNAL_RATE_LIMIT_PER_IP)
[ ] API key auto-generated at /opt/rustdesk/.api_key (shared between console + Go)

# =============================================================================
# SECTION H — STAFF COMMUNICATIONS (Step 2)
# =============================================================================
[ ] STAFF_ANNOUNCEMENT.md drafted (email)
[ ] STAFF_SLACK_ANNOUNCEMENT.md drafted (Slack/Teams)
[ ] Staff portal HTML ready at landing-service/public/landing/staff-portal.html
[ ] Helpdesk contact email defined
[ ] Rollout date communicated to staff

# =============================================================================
# SECTION I — ANDROID EMULATOR TEST READINESS (Step 4)
# =============================================================================
[ ] Android APK (universal or arm64) downloaded from landing page on emulator
[ ] APK installs successfully (one-tap, no "unknown source" block if signed)
[ ] Agent auto-enrolls / connects to panel.telcom.stream after install
[ ] Device appears online in admin console (panel.telcom.stream)
[ ] Remote-control session initiated from console → reaches emulator
[ ] Emulator user sees consent popup (supervised mode) or silent connect (unattended)
[ ] Tested on Android 13, 14, 15 (API 33, 34, 35)
[ ] Tested on arm64-v8a and x86_64 emulator ABIs

# =============================================================================
# GO-LIVE DECISION
# =============================================================================
[ ] ALL sections above checked → AUTHORIZED TO PUBLISH zoom.telcom.stream to staff
[ ] Any unchecked item → DO NOT publish; resolve first

Sign-off: ____________________   Date: __________
