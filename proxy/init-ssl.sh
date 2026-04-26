#!/bin/bash
# init-ssl.sh — Issue a Let's Encrypt certificate for a domain via the shared proxy.
# Run from /opt/proxy/
#
# Usage:
#   ./init-ssl.sh equityrange.com your@email.com
#   ./init-ssl.sh poker.equityrange.com your@email.com
#   ./init-ssl.sh newproject.equityrange.com your@email.com
#
# Prerequisites:
#   - DNS A record for DOMAIN already pointing to this server
#   - Proxy stack running (docker compose up -d)
#   - Port 80 open

set -e

DOMAIN="${1:-}"
EMAIL="${2:-}"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "Usage: ./init-ssl.sh <domain> <email>"
  echo "  Example: ./init-ssl.sh equityrange.com admin@equityrange.com"
  exit 1
fi

# For equityrange.com, also cover www
EXTRA_DOMAINS=""
if [ "$DOMAIN" = "equityrange.com" ]; then
  EXTRA_DOMAINS="-d www.equityrange.com"
fi

echo "==> Requesting certificate for ${DOMAIN}..."
docker compose run --rm certbot \
  certonly --webroot \
  -w /var/www/certbot \
  -d "${DOMAIN}" ${EXTRA_DOMAINS} \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email

echo "==> Reloading nginx..."
docker compose exec nginx nginx -s reload

echo ""
echo "✅ Certificate issued for ${DOMAIN}"
echo "   nginx reloaded — site should be live at https://${DOMAIN}"
