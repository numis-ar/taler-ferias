#!/bin/bash
# install-taler.sh - Install Taler payment system on a subdomain
# Usage: ./install-taler.sh <subdomain.domain.tld>
# Example: ./install-taler.sh shop.whatever.net      → creates 'shop' under 'whatever.net'
# Example: ./install-taler.sh myname.test.whatever.org → creates 'myname' under 'test.whatever.org'

set -e

FULL_DOMAIN=$1

if [ -z "$FULL_DOMAIN" ]; then
    echo "Usage: ./install-taler.sh <subdomain.domain.tld>"
    echo "Example: ./install-taler.sh shop.whatever.net"
    echo "Example: ./install-taler.sh myname.test.whatever.org"
    exit 1
fi

# Extract subdomain (first part) and domain (rest)
# e.g., "myname.test.whatever.org" → SUBDOMAIN="myname", DOMAIN="test.whatever.org"
SUBDOMAIN=$(echo "$FULL_DOMAIN" | cut -d'.' -f1)
DOMAIN=$(echo "$FULL_DOMAIN" | cut -d'.' -f2-)

if [ -z "$SUBDOMAIN" ] || [ -z "$DOMAIN" ]; then
    echo "Error: Invalid domain format. Use: subdomain.domain.tld"
    exit 1
fi

echo "=== Installing Taler on ${FULL_DOMAIN} ==="
echo "Subdomain: ${SUBDOMAIN}"
echo "Domain: ${DOMAIN}"

# Export for docker-compose
export FULL_DOMAIN
export SUBDOMAIN
export DOMAIN

# Create .env file for docker-compose variable substitution
cat > .env << EOF
FULL_DOMAIN=${FULL_DOMAIN}
SUBDOMAIN=${SUBDOMAIN}
DOMAIN=${DOMAIN}
EOF

echo "Created .env file with FULL_DOMAIN=${FULL_DOMAIN}"

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker required but not installed. Aborting."; exit 1; }

# Check for docker compose (modern) or docker-compose (legacy)
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "Docker Compose required but not installed. Aborting."
    echo "Install with: sudo apt install docker-compose-plugin"
    exit 1
fi

command -v nginx >/dev/null 2>&1 || { echo "Nginx required but not installed. Aborting."; exit 1; }

# 1. Create installation directory
INSTALL_DIR="/opt/taler-${SUBDOMAIN}"
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory ${INSTALL_DIR} already exists. Removing..."
    rm -rf "$INSTALL_DIR"
fi

echo "Cloning repository to ${INSTALL_DIR}..."
git clone https://github.com/numis-ar/taler-ferias.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2. Generate unique ports based on subdomain hash (to avoid conflicts between instances)
# Use high port range (30000+) to avoid conflicts
# Base ports: 31000-31004 with subdomain-based offset
PORT_OFFSET=$(echo "$SUBDOMAIN" | cksum | cut -d' ' -f1 | awk '{print $1 % 1000}')
BASE_PORT=$((30000 + PORT_OFFSET))
FRONTEND_PORT=$BASE_PORT
MERCHANT_PORT=$((BASE_PORT + 1))
EXCHANGE_PORT=$((BASE_PORT + 2))
BANK_PORT=$((BASE_PORT + 3))

echo "Using ports: Frontend=${FRONTEND_PORT}, Merchant=${MERCHANT_PORT}, Exchange=${EXCHANGE_PORT}, Bank=${BANK_PORT}"

# 3. Create docker-compose override file for dynamic ports (safer than modifying main file)
# Using printf to ensure proper variable expansion
printf '%s\n' "services:
  postgres:
    container_name: taler-postgres-${SUBDOMAIN}
    volumes:
      - postgres_data_${SUBDOMAIN}:/var/lib/postgresql/data
    
  libeufin-bank:
    container_name: taler-bank-${SUBDOMAIN}
    environment:
      - LIBEUFIN_BANK_CURRENCY=KUDOS
    ports:
      - \"0.0.0.0:${BANK_PORT}:8080\"
    volumes:
      - libeufin_bank_data_${SUBDOMAIN}:/var/lib/libeufin-bank
  
  taler-exchange:
    container_name: taler-exchange-${SUBDOMAIN}
    environment:
      - FULL_DOMAIN=${FULL_DOMAIN}
      - DB_PASSWORD=talerpassword
    ports:
      - \"0.0.0.0:${EXCHANGE_PORT}:8081\"
    volumes:
      - exchange_data_${SUBDOMAIN}:/var/lib/taler-exchange
      - ./exchange-local.conf:/etc/taler/taler.conf:ro
  
  taler-merchant:
    container_name: taler-merchant-${SUBDOMAIN}
    environment:
      - EXCHANGE_URL=http://taler-exchange:8081
      - FULL_DOMAIN=${FULL_DOMAIN}
    volumes:
      - ./merchant-${SUBDOMAIN}.conf:/etc/taler/taler.conf:ro
      - merchant_data_${SUBDOMAIN}:/var/lib/taler-merchant
    ports:
      - \"0.0.0.0:${MERCHANT_PORT}:9966\"
    
  demo-frontend:
    container_name: taler-demo-frontend-${SUBDOMAIN}
    ports:
      - \"0.0.0.0:${FRONTEND_PORT}:80\"

volumes:
  postgres_data_${SUBDOMAIN}:
  merchant_data_${SUBDOMAIN}:
  exchange_data_${SUBDOMAIN}:
  libeufin_bank_data_${SUBDOMAIN}:
" > docker-compose.override.yml

echo "Created docker-compose.override.yml"
grep "FULL_DOMAIN" docker-compose.override.yml | head -1

# 4. Update configuration files with the full domain
echo "Updating configuration files..."

# Update exchange configuration
sed -i "s|https://\${FULL_DOMAIN}/exchange/|https://${FULL_DOMAIN}/exchange/|g" exchange-local.conf || true

# Generate merchant configuration with correct BASE_URL
cat > "merchant-${SUBDOMAIN}.conf" << EOF
# Taler Merchant Configuration - Auto-generated for ${FULL_DOMAIN}
[taler]
CURRENCY = KUDOS

[merchant]
SERVE = tcp
PORT = 9966
DATABASE = postgres
BASE_URL = https://${FULL_DOMAIN}/merchant/

[merchantdb-postgres]
CONFIG = postgres://taler:talerpassword@postgres:5432/taler_merchant

# Use the local exchange (internal Docker network)
# Note: MASTER_KEY will be auto-populated by init-merchant.sh
[merchant-exchange-kudos]
EXCHANGE_BASE_URL = http://taler-exchange:8081/
CURRENCY = KUDOS
EOF

MASTER_KEY = PLACEHOLDER_WILL_BE_UPDATED
EOF

# Update Merchant Web UI links
sed -i "s|http://localhost:9966/webui/|https://${FULL_DOMAIN}/webui/|g" demo-frontend/index.html
sed -i "s|localhost:9966/webui|${FULL_DOMAIN}/webui|g" demo-frontend/index.html
sed -i "s/http:\/\/localhost:8080/https:\/\/${FULL_DOMAIN}/g" demo-frontend/index.html
# Update API URLs in qr-payment.html
sed -i "s|http://localhost:9966|https://${FULL_DOMAIN}|g" demo-frontend/qr-payment.html

# Also update any protocol-relative URLs
sed -i "s|window\.open('http://localhost:9966/webui/'|window.open('https://${FULL_DOMAIN}/webui/'|g" demo-frontend/index.html
sed -i "s|href=\"http://localhost:9966/webui/\"|href=\"https://${FULL_DOMAIN}/webui/\"|g" demo-frontend/index.html

# 5. Create nginx config for subdomain
echo "Creating nginx configuration..."

# Check if SSL certificate will exist
SSL_CERT_PATH="/etc/letsencrypt/live/${FULL_DOMAIN}/fullchain.pem"

sudo tee "/etc/nginx/sites-available/taler-${SUBDOMAIN}" << EOF
server {
    listen 80;
    server_name ${FULL_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${FULL_DOMAIN};

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key /etc/letsencrypt/live/${FULL_DOMAIN}/privkey.pem;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Frontend (root path)
    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Merchant Web UI - handle redirect from /webui to /webui/
    location = /webui {
        return 301 /webui/;
    }
    
    location /webui/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/webui/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /webui;
        proxy_set_header Authorization \$http_authorization;
        # Handle various redirect formats from merchant backend
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /webui/;
        proxy_redirect /webui/ /webui/;
        # Handle relative redirects that might cause double webui
        proxy_redirect webui/ /webui/;
    }

    # Merchant base path - proxy all merchant endpoints
    location /merchant/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
    }

    # Merchant API endpoints
    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
    }

    # Bank /config for wallet withdrawal (returns taler-corebank)
    location /config {
        proxy_pass http://localhost:${BANK_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Merchant /config for payments (returns taler-merchant)
    location /merchant/config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Taler Exchange
    # Redirect /exchange to /exchange/
    location = /exchange {
        return 301 /exchange/;
    }
    
    location /exchange/ {
        proxy_pass http://localhost:${EXCHANGE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${EXCHANGE_PORT}/ /exchange/;
        
        # WebSocket support for real-time updates
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Libeufin Sandbox Bank
    location /bank/ {
        proxy_pass http://localhost:${BANK_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${BANK_PORT}/ /bank/;
        
        # Handle bank's own redirects
        proxy_redirect / /bank/;
    }
}
EOF

# Enable nginx site
sudo ln -sf "/etc/nginx/sites-available/taler-${SUBDOMAIN}" "/etc/nginx/sites-enabled/"
sudo nginx -t && sudo systemctl reload nginx

# 6. Get SSL certificate for subdomain
echo "Obtaining SSL certificate for ${FULL_DOMAIN}..."

# Create webroot for certbot
sudo mkdir -p /var/www/certbot

# First, temporarily use HTTP-only config to allow certbot challenge
sudo rm -f "/etc/nginx/sites-enabled/taler-${SUBDOMAIN}"

sudo tee "/etc/nginx/sites-available/taler-${SUBDOMAIN}-temp" << EOF
server {
    listen 80;
    server_name ${FULL_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /webui {
        return 301 /webui/;
    }
    
    location /webui/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/webui/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /webui;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /webui/;
        proxy_redirect /webui/ /webui/;
        proxy_redirect webui/ /webui/;
    }

    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        
    }

    # Bank /config for wallet withdrawal (returns taler-corebank)
    location /config {
        proxy_pass http://localhost:${BANK_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
    }

    # Merchant /config for payments (returns taler-merchant)
    location /merchant/config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
    }

    # Redirect /exchange to /exchange/
    location = /exchange {
        return 301 /exchange/;
    }
    
    location /exchange/ {
        proxy_pass http://localhost:${EXCHANGE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${EXCHANGE_PORT}/ /exchange/;
    }

    # Libeufin Sandbox Bank
    location /bank/ {
        proxy_pass http://localhost:${BANK_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${BANK_PORT}/ /bank/;
    }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/taler-${SUBDOMAIN}-temp" "/etc/nginx/sites-enabled/"
sudo nginx -t && sudo systemctl reload nginx

# Get certificate using webroot method
SSL_SUCCESS=false
if ! sudo certbot certificates 2>/dev/null | grep -q "${FULL_DOMAIN}"; then
    echo "Requesting new SSL certificate for ${FULL_DOMAIN}..."
    if sudo certbot certonly --webroot -w /var/www/certbot -d "${FULL_DOMAIN}" --non-interactive --agree-tos -m "admin@${DOMAIN}" 2>/dev/null; then
        SSL_SUCCESS=true
        echo "SSL certificate obtained successfully!"
    else
        echo "WARNING: SSL certificate creation failed."
        echo "Make sure DNS for ${FULL_DOMAIN} points to this server."
        echo "Continuing with HTTP-only setup..."
    fi
else
    echo "SSL certificate for ${FULL_DOMAIN} already exists."
    SSL_SUCCESS=true
fi

# Remove temp config
sudo rm -f "/etc/nginx/sites-enabled/taler-${SUBDOMAIN}-temp"
sudo rm -f "/etc/nginx/sites-available/taler-${SUBDOMAIN}-temp"

# Enable the appropriate config
if [ "$SSL_SUCCESS" = true ] && [ -f "$SSL_CERT_PATH" ]; then
    echo "Enabling HTTPS configuration..."
    sudo ln -sf "/etc/nginx/sites-available/taler-${SUBDOMAIN}" "/etc/nginx/sites-enabled/"
    sudo nginx -t && sudo systemctl reload nginx
    BASE_URL="https://${FULL_DOMAIN}"
else
    echo "Enabling HTTP-only configuration..."
    # Create HTTP-only config permanently
    sudo tee "/etc/nginx/sites-available/taler-${SUBDOMAIN}" << EOF
server {
    listen 80;
    server_name ${FULL_DOMAIN};
    
    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /webui {
        return 301 /webui/;
    }
    
    location /webui/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/webui/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /webui;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /webui/;
        proxy_redirect /webui/ /webui/;
        proxy_redirect webui/ /webui/;
    }

    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        

    # Merchant /config for payments (returns taler-merchant)
    location /merchant/config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
    }
    }

    # Bank /config for wallet withdrawal (returns taler-corebank)
    location /config {
        proxy_pass http://localhost:${BANK_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        
    }

    location /exchange/ {
        proxy_pass http://localhost:${EXCHANGE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${EXCHANGE_PORT}/ /exchange/;
    }

    # Libeufin Sandbox Bank
    location /bank/ {
        proxy_pass http://localhost:${BANK_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${BANK_PORT}/ /bank/;
    }
}
EOF
    sudo ln -sf "/etc/nginx/sites-available/taler-${SUBDOMAIN}" "/etc/nginx/sites-enabled/"
    sudo nginx -t && sudo systemctl reload nginx
    BASE_URL="http://${FULL_DOMAIN}"
fi

# 7. Open firewall ports
echo "Configuring firewall..."
sudo ufw allow "${MERCHANT_PORT}/tcp" 2>/dev/null || true
sudo ufw allow "${FRONTEND_PORT}/tcp" 2>/dev/null || true
sudo ufw allow "${EXCHANGE_PORT}/tcp" 2>/dev/null || true
sudo ufw allow "${BANK_PORT}/tcp" 2>/dev/null || true

# 8. Start Docker services
echo "Starting Taler services..."
# Clean up any existing containers to avoid port conflicts
echo "Cleaning up existing containers..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true
$COMPOSE_CMD down -v --remove-orphans 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
# Fix: Delete Docker's network state file to release stuck ports
# This is needed when docker-proxy holds ports after container removal
if [ -f /var/lib/docker/network/files/local-kv.db ]; then
    systemctl stop docker 2>/dev/null || service docker stop 2>/dev/null || true
    rm -f /var/lib/docker/network/files/local-kv.db
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3
fi
$COMPOSE_CMD up -d

# Wait for services to be healthy and admin to be created
echo "Waiting for services to start..."
sleep 5

# Verify admin instance was created (docker-compose.yml now handles this via taler-merchant-passwd)
echo "Verifying admin instance..."
for i in {1..30}; do
    ADMIN_CHECK=$(docker exec taler-postgres-${SUBDOMAIN} psql -U taler -d taler_merchant -tc "SELECT merchant_id FROM merchant.merchant_instances WHERE merchant_id = 'admin'" 2>/dev/null | xargs)
    if [ "$ADMIN_CHECK" = "admin" ]; then
        echo "✓ Admin instance verified"
        break
    fi
    echo "  Waiting for admin instance... ($i/30)"
    sleep 2
done

# If admin doesn't exist after waiting, create it manually
if [ "$ADMIN_CHECK" != "admin" ]; then
    echo "Creating admin instance manually..."
    docker exec taler-merchant-${SUBDOMAIN} bash -c \
        'TALER_MERCHANT_PASSWORD=adminpassword taler-merchant-passwd -c /etc/taler/taler.conf --instance=admin' 2>&1
fi

# Verify bank account is configured
echo "Verifying merchant bank account..."
BANK_ACCOUNT_CHECK=$(docker exec taler-postgres-${SUBDOMAIN} psql -U taler -d taler_merchant -tc "SELECT COUNT(*) FROM merchant.merchant_accounts" 2>/dev/null | xargs)
if [ "$BANK_ACCOUNT_CHECK" = "0" ] || [ -z "$BANK_ACCOUNT_CHECK" ]; then
    echo "Setting up merchant bank account..."
    docker exec taler-merchant-${SUBDOMAIN} bash /tmp/init-merchant.sh 2>&1 || echo "Bank account setup may need manual intervention"
else
    echo "✓ Bank account configured ($BANK_ACCOUNT_CHECK account(s))"
fi

# Check if services are running
if $COMPOSE_CMD ps | grep -q "Up"; then
    echo ""
    echo "========================================"
    echo "=== Taler Infrastructure Complete! ==="
    echo "========================================"
    echo ""
    echo "Demo Store:    ${BASE_URL}"
    echo "Merchant UI:   ${BASE_URL}/webui/"
    echo "Bank UI:       ${BASE_URL}/bank/"
    echo "Exchange API:  ${BASE_URL}/exchange/"
    echo ""
    echo "Default Credentials:"
    echo "  Merchant:    admin / adminpassword"
    echo "  Bank Admin:  admin / bankadmin"
    echo "  Bank Users:  exchange / exchange_password"
    echo "               merchant / merchant_password"
    echo "               demo / demo_password"
    echo ""
    echo "Internal ports (for debugging):"
    echo "  Frontend:    http://localhost:${FRONTEND_PORT}"
    echo "  Merchant:    http://localhost:${MERCHANT_PORT}"
    echo "  Exchange:    http://localhost:${EXCHANGE_PORT}"
    echo "  Bank:        http://localhost:${BANK_PORT}"
    echo ""
    echo "Services are interconnected:"
    echo "  - Store → Merchant → Exchange → Bank"
    echo "  - All using KUDOS (demo currency)"
    echo ""
    echo "To view logs:  cd ${INSTALL_DIR} && $COMPOSE_CMD logs -f"
    echo "To stop:       cd ${INSTALL_DIR} && $COMPOSE_CMD down"
    echo ""
else
    echo "ERROR: Services failed to start. Check logs with: cd ${INSTALL_DIR} && $COMPOSE_CMD logs"
    exit 1
fi
