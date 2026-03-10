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
PORT_OFFSET=$(echo "$SUBDOMAIN" | cksum | cut -d' ' -f1 | awk '{print $1 % 1000}')
MERCHANT_PORT=$((9966 + PORT_OFFSET))
FRONTEND_PORT=$((8080 + PORT_OFFSET))

echo "Using ports: Frontend=${FRONTEND_PORT}, Merchant=${MERCHANT_PORT}"

# 3. Create docker-compose override file for dynamic ports (safer than modifying main file)
cat > docker-compose.override.yml << EOFCOMPOSE
services:
  postgres:
    container_name: taler-postgres-${SUBDOMAIN}
    volumes:
      - postgres_data_${SUBDOMAIN}:/var/lib/postgresql/data
    
  taler-merchant:
    container_name: taler-merchant-${SUBDOMAIN}
    volumes:
      - ./merchant-demo.conf:/etc/taler/taler.conf:ro
      - merchant_data_${SUBDOMAIN}:/var/lib/taler-merchant
    ports:
      - "0.0.0.0:${MERCHANT_PORT}:9966"
    
  demo-frontend:
    container_name: taler-demo-frontend-${SUBDOMAIN}
    ports:
      - "0.0.0.0:${FRONTEND_PORT}:80"

volumes:
  postgres_data_${SUBDOMAIN}:
  merchant_data_${SUBDOMAIN}:
EOFCOMPOSE

# 4. Update frontend HTML with the full domain
echo "Updating frontend configuration..."
sed -i "s/localhost:9966/${FULL_DOMAIN}\/webui/g" demo-frontend/index.html
sed -i "s/http:\/\/localhost:8080/https:\/\/${FULL_DOMAIN}/g" demo-frontend/index.html
sed -i "s/localhost:9966/${FULL_DOMAIN}\/webui/g" demo-frontend/qr-payment.html

# Also update any protocol-relative URLs
sed -i "s|window\.open('http://localhost:9966/webui/'|window.open('https://${FULL_DOMAIN}/webui/'|g" demo-frontend/index.html
sed -i 's|href="http://localhost:9966/webui/"|href="https://${FULL_DOMAIN}/webui/"|g' demo-frontend/index.html

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
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    # Merchant API endpoints
    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    location /config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    location /config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
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
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/webui/ /webui/;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    location /private/ {
        proxy_pass http://localhost:${MERCHANT_PORT}/private/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
    }

    location /config {
        proxy_pass http://localhost:${MERCHANT_PORT}/config;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization \$http_authorization;
        proxy_redirect http://localhost:${MERCHANT_PORT}/ /;
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

# 8. Start Docker services
echo "Starting Taler services..."
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

# Check if services are running
if $COMPOSE_CMD ps | grep -q "Up"; then
    echo ""
    echo "========================================"
    echo "=== Installation Complete! ==="
    echo "========================================"
    echo ""
    echo "Demo Store:    ${BASE_URL}"
    echo "Merchant UI:   ${BASE_URL}/webui/"
    echo ""
    echo "Login:         admin"
    echo "Password:      adminpassword"
    echo ""
    echo "Internal ports (for debugging):"
    echo "  Frontend:    http://localhost:${FRONTEND_PORT}"
    echo "  Merchant:    http://localhost:${MERCHANT_PORT}"
    echo ""
    echo "To view logs:  cd ${INSTALL_DIR} && $COMPOSE_CMD logs -f"
    echo "To stop:       cd ${INSTALL_DIR} && $COMPOSE_CMD down"
    echo ""
else
    echo "ERROR: Services failed to start. Check logs with: cd ${INSTALL_DIR} && $COMPOSE_CMD logs"
    exit 1
    exit 1
fi
