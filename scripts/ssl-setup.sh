#!/bin/bash
# =============================================================================
# BetterDesk SSL Certificate Manager
# Issues + renews Let's Encrypt certificates for both domains.
#
# Usage:
#   sudo ./scripts/ssl-setup.sh --issue       # Initial certificate issuance
#   sudo ./scripts/ssl-setup.sh --renew       # Force renewal
#   sudo ./scripts/ssl-setup.sh --status      # Check certificate status
# =============================================================================
set -euo pipefail

EMAIL="${CERTBOT_EMAIL:-admin@telcom.stream}"
STAGING="${STAGING:-0}"
DOMAINS="zoom.telcom.stream panel.telcom.stream"
WEBROOT="/var/www/certbot"

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  MODE="issue"; shift ;;
    --renew)  MODE="renew"; shift ;;
    --status) MODE="status"; shift ;;
    *)        echo "Unknown option: $1"; exit 3 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 --issue | --renew | --status"
  exit 3
fi

mkdir -p "$WEBROOT" /etc/letsencrypt /var/log/betterdesk

log() { echo "[$(date -Iseconds)] $*"; }

case "$MODE" in
  issue)
    log "Issuing Let's Encrypt certificates for: $DOMAINS"
    if [[ "$STAGING" == "1" ]]; then
      STAGING_FLAG="--staging"
      log "Using STAGING environment (test certificates)"
    else
      STAGING_FLAG=""
    fi
    certbot certonly --webroot -w "$WEBROOT" \
      --email "$EMAIL" --agree-tos --no-eff-email \
      $STAGING_FLAG \
      -d zoom.telcom.stream -d panel.telcom.stream
    log "Certificate issuance complete"
    ;;

  renew)
    log "Forcing certificate renewal"
    certbot renew --force-renewal --no-eff-email
    systemctl reload betterdesk-nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
    log "Renewal complete"
    ;;

  status)
    log "Certificate status:"
    for domain in $DOMAINS; do
      CERT_FILE="/etc/letsencrypt/live/$domain/fullchain.pem"
      if [[ -f "$CERT_FILE" ]]; then
        END_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
        DAYS_LEFT=$(( ($(date -d "$END_DATE" +%s) - $(date +%s)) / 86400 ))
        echo "  $domain: expires $END_DATE ($DAYS_LEFT days)"
      else
        echo "  $domain: NO CERTIFICATE FOUND"
      fi
    done
    ;;
esac
