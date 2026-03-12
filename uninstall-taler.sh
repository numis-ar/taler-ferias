#!/bin/bash
# uninstall-taler.sh - Remove Taler installation completely
# Usage: ./uninstall-taler.sh <full-domain>
# Example: ./uninstall-taler.sh shop.example.com

set -e

FULL_DOMAIN=$1

if [ -z "$FULL_DOMAIN" ]; then
    echo "Usage: ./uninstall-taler.sh <full-domain>"
    echo "Example: ./uninstall-taler.sh shop.whatever.net"
    echo "Example: ./uninstall-taler.sh myname.test.whatever.org"
    exit 1
fi

# Extract subdomain and domain
SUBDOMAIN=$(echo "$FULL_DOMAIN" | cut -d'.' -f1)
DOMAIN=$(echo "$FULL_DOMAIN" | cut -d'.' -f2-)
INSTALL_DIR="/opt/taler-${SUBDOMAIN}"

echo "=== Uninstalling Taler from ${FULL_DOMAIN} ==="
echo "Subdomain: ${SUBDOMAIN}"
echo "Domain: ${DOMAIN}"
echo "Install dir: ${INSTALL_DIR}"

# 1. Stop and remove Docker containers
echo "Stopping and removing Docker containers..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    
    # Check for docker compose
    if command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        echo "Warning: Docker Compose not found, attempting manual container removal"
    fi
    
    if [ -n "$COMPOSE_CMD" ]; then
        $COMPOSE_CMD down -v 2>/dev/null || true
    fi
    
    # Remove containers by name if compose failed
    docker rm -f taler-postgres-${SUBDOMAIN} 2>/dev/null || true
    docker rm -f taler-merchant-${SUBDOMAIN} 2>/dev/null || true
    docker rm -f taler-demo-frontend-${SUBDOMAIN} 2>/dev/null || true
    
    cd -
fi

# 2. Remove Docker volumes
echo "Removing Docker volumes..."
docker volume rm taler-rog_postgres_data_${SUBDOMAIN} 2>/dev/null || true
docker volume rm taler-rog_merchant_data_${SUBDOMAIN} 2>/dev/null || true

# 3. Remove installation directory
echo "Removing installation directory..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Removed: ${INSTALL_DIR}"
fi

# 4. Remove nginx configuration
echo "Removing nginx configuration..."
NGINX_AVAILABLE="/etc/nginx/sites-available/taler-${SUBDOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/taler-${SUBDOMAIN}"
NGINX_TEMP_AVAILABLE="/etc/nginx/sites-available/taler-${SUBDOMAIN}-temp"
NGINX_TEMP_ENABLED="/etc/nginx/sites-enabled/taler-${SUBDOMAIN}-temp"

# Subdomain-specific configs
EXCHANGE_SUBDOMAIN="exchange.${SUBDOMAIN}"
MERCHANT_SUBDOMAIN="merchant.${SUBDOMAIN}"
BANK_SUBDOMAIN="bank.${SUBDOMAIN}"

NGINX_EXCHANGE_AVAIL="/etc/nginx/sites-available/taler-${EXCHANGE_SUBDOMAIN}"
NGINX_EXCHANGE_EN="/etc/nginx/sites-enabled/taler-${EXCHANGE_SUBDOMAIN}"
NGINX_MERCHANT_AVAIL="/etc/nginx/sites-available/taler-${MERCHANT_SUBDOMAIN}"
NGINX_MERCHANT_EN="/etc/nginx/sites-enabled/taler-${MERCHANT_SUBDOMAIN}"
NGINX_BANK_AVAIL="/etc/nginx/sites-available/taler-${BANK_SUBDOMAIN}"
NGINX_BANK_EN="/etc/nginx/sites-enabled/taler-${BANK_SUBDOMAIN}"

# Extract ports for firewall cleanup BEFORE deleting configs
MERCHANT_PORT=""
FRONTEND_PORT=""
if [ -f "$NGINX_AVAILABLE" ]; then
    MERCHANT_PORT=$(grep -o 'localhost:[0-9]*' "$NGINX_AVAILABLE" | grep -v 8080 | head -1 | cut -d: -f2)
    FRONTEND_PORT=$(grep -o 'localhost:[0-9]*' "$NGINX_AVAILABLE" | grep 8080 | head -1 | cut -d: -f2)
fi

for f in "$NGINX_AVAILABLE" "$NGINX_ENABLED" "$NGINX_TEMP_AVAILABLE" "$NGINX_TEMP_ENABLED" \
         "$NGINX_EXCHANGE_AVAIL" "$NGINX_EXCHANGE_EN" \
         "$NGINX_MERCHANT_AVAIL" "$NGINX_MERCHANT_EN" \
         "$NGINX_BANK_AVAIL" "$NGINX_BANK_EN"; do
    if [ -f "$f" ] || [ -L "$f" ]; then
        rm -f "$f"
        echo "Removed: ${f}"
    fi
done

# 5. Test and reload nginx
echo "Reloading nginx..."
if nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo "Nginx reloaded successfully"
else
    echo "Warning: Nginx config test failed, manual check may be needed"
fi

# 6. Remove SSL certificates (optional - commented out by default)
echo ""
echo "SSL certificates for ${FULL_DOMAIN} are preserved at:"
echo "  /etc/letsencrypt/live/${FULL_DOMAIN}/"
echo ""
read -p "Remove SSL certificates for ${FULL_DOMAIN}? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    certbot delete --cert-name "${FULL_DOMAIN}" 2>/dev/null || true
    echo "SSL certificates removed"
else
    echo "SSL certificates preserved"
fi

# 7. Close firewall ports (optional)
echo ""
read -p "Close firewall ports for this installation? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Use ports extracted earlier before nginx configs were deleted
    if [ -n "$MERCHANT_PORT" ]; then
        ufw delete allow "${MERCHANT_PORT}/tcp" 2>/dev/null || true
        echo "Closed port: ${MERCHANT_PORT}"
    fi
    if [ -n "$FRONTEND_PORT" ]; then
        ufw delete allow "${FRONTEND_PORT}/tcp" 2>/dev/null || true
        echo "Closed port: ${FRONTEND_PORT}"
    fi
    echo "Firewall rules updated"
fi

echo ""
echo "========================================"
echo "=== Uninstallation Complete ==="
echo "========================================"
echo ""
echo "Removed:"
echo "  - Docker containers: taler-*-${SUBDOMAIN}"
echo "  - Docker volumes: postgres_data_${SUBDOMAIN}, merchant_data_${SUBDOMAIN}"
echo "  - Installation directory: ${INSTALL_DIR}"
echo "  - Nginx configs: taler-${SUBDOMAIN}, taler-exchange-${SUBDOMAIN}, taler-merchant-${SUBDOMAIN}, taler-bank-${SUBDOMAIN}"
echo ""
echo "Preserved (unless deleted):"
echo "  - SSL certificates: /etc/letsencrypt/live/${FULL_DOMAIN}/"
echo ""
echo "To verify cleanup:"
echo "  docker ps | grep taler-${SUBDOMAIN}"
echo "  docker volume ls | grep ${SUBDOMAIN}"
echo "  ls -la ${INSTALL_DIR} 2>&1 || echo 'Directory removed'"
echo ""
