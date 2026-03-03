#!/bin/bash
# GNU Taler Minimal PoC Installation Script for Ubuntu 24.04
# This script installs Taler components locally for testing

set -e

echo "==================================="
echo "GNU Taler PoC Installation Script"
echo "==================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Ubuntu 24.04
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    log_warn "This script is designed for Ubuntu 24.04. Your system may not be compatible."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for sudo
if [ "$EUID" -ne 0 ]; then 
    log_info "Requesting sudo privileges..."
    SUDO="sudo"
else
    SUDO=""
fi

# Step 1: Update system and install dependencies
log_info "Step 1: Installing dependencies..."
$SUDO apt-get update
$SUDO apt-get install -y wget gnupg2 curl jq postgresql postgresql-contrib

# Step 2: Add Taler repository
log_info "Step 2: Adding Taler repository..."
$SUDO mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/taler-systems.gpg ]; then
    $SUDO wget -O /etc/apt/keyrings/taler-systems.gpg https://taler.net/taler-systems.gpg
fi

# Check if repository is already added
if [ ! -f /etc/apt/sources.list.d/taler.list ]; then
    echo 'deb [signed-by=/etc/apt/keyrings/taler-systems.gpg] https://deb.taler.net/apt/ubuntu/ noble main' | $SUDO tee /etc/apt/sources.list.d/taler.list
    $SUDO apt-get update
fi

# Step 3: Install Taler packages
log_info "Step 3: Installing Taler packages..."
$SUDO apt-get install -y taler-exchange taler-merchant taler-bank || {
    log_warn "Some packages may not be available. Trying individual installations..."
    $SUDO apt-get install -y gnunet || true
    $SUDO apt-get install -y taler-exchange || log_warn "taler-exchange installation failed"
    $SUDO apt-get install -y taler-merchant || log_warn "taler-merchant installation failed"
}

# Step 4: Setup PostgreSQL
log_info "Step 4: Setting up PostgreSQL..."
$SUDO systemctl start postgresql
$SUDO systemctl enable postgresql

# Create taler user and databases
$SUDO -u postgres psql <<EOF
CREATE USER taler WITH PASSWORD 'talerpassword' CREATEDB;
CREATE DATABASE taler_exchange OWNER taler;
CREATE DATABASE taler_merchant OWNER taler;
CREATE DATABASE taler_bank OWNER taler;
GRANT ALL PRIVILEGES ON DATABASE taler_exchange TO taler;
GRANT ALL PRIVILEGES ON DATABASE taler_merchant TO taler;
GRANT ALL PRIVILEGES ON DATABASE taler_bank TO taler;
EOF

log_info "PostgreSQL setup complete"

# Step 5: Create configuration directories
log_info "Step 5: Creating configuration directories..."
$SUDO mkdir -p /etc/taler /var/lib/taler-exchange /var/lib/taler-merchant
$SUDO chown -R $USER:$USER /var/lib/taler-exchange /var/lib/taler-merchant 2>/dev/null || true

# Step 6: Create exchange configuration
log_info "Step 6: Creating Exchange configuration..."
$SUDO tee /etc/taler/taler-exchange.conf > /dev/null <<'EOF'
[taler]
CURRENCY = KUDOS

[exchange]
BASE_URL = http://localhost:8081/
WIRE_METHOD = x-taler-bank

[exchangedb-postgres]
CONFIG = postgres:///taler_exchange

[bank]
HTTP_PORT = 8082
DATABASE = postgres:///taler_bank
EOF

# Step 7: Create merchant configuration
log_info "Step 7: Creating Merchant configuration..."
$SUDO tee /etc/taler/taler-merchant.conf > /dev/null <<'EOF'
[taler]
CURRENCY = KUDOS

[merchant]
SERVE = tcp
PORT = 9966
DATABASE = postgres

[merchantdb-postgres]
CONFIG = postgres:///taler_merchant

[merchant-exchange-kudos]
EXCHANGE_BASE_URL = http://localhost:8081/
MASTER_KEY = 
CURRENCY = KUDOS
EOF

# Step 8: Initialize databases
log_info "Step 8: Initializing databases..."

# Exchange database
taler-exchange-dbinit -c /etc/taler/taler-exchange.conf 2>/dev/null || {
    log_warn "Exchange database initialization may have failed or already done"
}

# Merchant database
taler-merchant-dbinit -c /etc/taler/taler-merchant.conf 2>/dev/null || {
    log_warn "Merchant database initialization may have failed or already done"
}

log_info "Database initialization complete"

# Step 9: Create startup script
log_info "Step 9: Creating startup script..."
cat > ~/start-taler.sh <<'EOF'
#!/bin/bash
# Start Taler services for PoC

echo "Starting Taler services..."

# Start exchange HTTP daemon
taler-exchange-httpd -c /etc/taler/taler-exchange.conf -p 8081 &
EXCHANGE_PID=$!
echo "Exchange HTTPD started (PID: $EXCHANGE_PID)"

# Start exchange wirewatch
taler-exchange-wirewatch -c /etc/taler/taler-exchange.conf &
WIREWATCH_PID=$!
echo "Exchange Wirewatch started (PID: $WIREWATCH_PID)"

# Start exchange aggregator
taler-exchange-aggregator -c /etc/taler/taler-exchange.conf &
AGGREGATOR_PID=$!
echo "Exchange Aggregator started (PID: $AGGREGATOR_PID)"

# Start fake bank
taler-bank-transfer -c /etc/taler/taler-exchange.conf -p 8082 &
BANK_PID=$!
echo "Fake Bank started (PID: $BANK_PID)"

# Start merchant HTTP daemon
taler-merchant-httpd -c /etc/taler/taler-merchant.conf -p 9966 &
MERCHANT_PID=$!
echo "Merchant HTTPD started (PID: $MERCHANT_PID)"

echo ""
echo "Taler services started!"
echo "- Exchange: http://localhost:8081"
echo "- Fake Bank: http://localhost:8082"
echo "- Merchant: http://localhost:9966"
echo ""
echo "Press Enter to stop all services..."
read

# Stop all services
kill $EXCHANGE_PID $WIREWATCH_PID $AGGREGATOR_PID $BANK_PID $MERCHANT_PID 2>/dev/null
echo "All services stopped"
EOF
chmod +x ~/start-taler.sh

# Step 10: Create demo frontend launcher
cat > ~/start-demo.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Starting demo frontend on http://localhost:8080"
echo "Press Ctrl+C to stop"
python3 -m http.server 8080
EOF
chmod +x ~/start-demo.sh

# Final summary
echo ""
echo "==================================="
echo "Installation Complete!"
echo "==================================="
echo ""
echo "To start Taler services, run:"
echo "  ~/start-taler.sh"
echo ""
echo "To start the demo frontend, run:"
echo "  ~/start-demo.sh"
echo ""
echo "Services will be available at:"
echo "  - Demo Frontend: http://localhost:8080"
echo "  - Taler Exchange: http://localhost:8081"
echo "  - Fake Bank: http://localhost:8082"
echo "  - Merchant Backend: http://localhost:9966"
echo ""
echo "Note: You may need to create an admin instance for the merchant:"
echo "  taler-merchant-passwd --instance=admin yourpassword"
echo ""
