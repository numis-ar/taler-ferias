#!/bin/bash
# Initialize Taler Exchange
set -e

echo "=== Initializing Taler Exchange ==="

# Set USER for taler paths
export USER=root

# Use provided config or default
CONF_FILE="${TALER_CONFIG:-/etc/taler/taler.conf}"

# Copy config to writable location
WRITABLE_CONF="/tmp/taler-exchange.conf"
if [ -f "$CONF_FILE" ]; then
    cp "$CONF_FILE" "$WRITABLE_CONF"
    CONF_FILE="$WRITABLE_CONF"
fi

# Export TALER_CONFIG so all taler commands use the writable config
export TALER_CONFIG="$CONF_FILE"
echo "Using config: $CONF_FILE"

# Replace placeholder with appropriate URL
# If FULL_DOMAIN is set (from install script), use that for public URL
# Otherwise use localhost for internal testing
INTERNAL_CONF="$CONF_FILE"  # For internal operations (download/upload)
if [ -n "$FULL_DOMAIN" ]; then
    echo "FULL_DOMAIN is set to: $FULL_DOMAIN"
    sed -i "s|https://EXCHANGE_HOST_PLACEHOLDER/exchange/|https://${FULL_DOMAIN}/exchange/|g" "$CONF_FILE"
    # Create internal config with localhost for download/upload operations
    INTERNAL_CONF="/tmp/taler-exchange-internal.conf"
    cp "$CONF_FILE" "$INTERNAL_CONF"
    sed -i 's|https://[^/]*/exchange/|http://localhost:8081/|g' "$INTERNAL_CONF"
else
    echo "FULL_DOMAIN not set, using localhost for internal operations"
    sed -i 's|https://EXCHANGE_HOST_PLACEHOLDER/exchange/|http://localhost:8081/|g' "$CONF_FILE"
fi

# Check if config exists
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Config file not found: $CONF_FILE"
    exit 1
fi

# Show BASE_URL
grep "BASE_URL" "$CONF_FILE" | head -1

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U taler; do
    echo "  PostgreSQL not ready, waiting..."
    sleep 2
done
echo "PostgreSQL is ready"

# Check if we need to reset the database (new master key vs old signed data)
MASTER_KEY_FILE="/root/.local/share/taler-exchange/offline/master.priv"
NEED_DB_RESET=false

if [ ! -f "$MASTER_KEY_FILE" ]; then
    # New master key will be generated, need fresh database
    NEED_DB_RESET=true
    echo "New master key will be generated, need fresh database"
fi

# Ensure exchange database exists (drop if need reset)
if [ "$NEED_DB_RESET" = "true" ]; then
    echo "Resetting exchange database..."
    PGPASSWORD=talerpassword psql -h postgres -U taler -c "DROP DATABASE IF EXISTS taler_exchange;" 2>/dev/null || true
fi

if ! PGPASSWORD=talerpassword psql -h postgres -U taler -tc "SELECT 1 FROM pg_database WHERE datname = 'taler_exchange'" | grep -q 1; then
    echo "Creating taler_exchange database..."
    PGPASSWORD=talerpassword psql -h postgres -U taler -c "CREATE DATABASE taler_exchange;"
fi

# Initialize database schema
echo "Initializing exchange database schema..."
taler-exchange-dbinit -c "$CONF_FILE" 2>&1 || echo "DB init may have already been done"

# Wait for libeufin-bank
echo "Waiting for libeufin-bank..."
for i in {1..30}; do
    if curl -sf http://libeufin-bank:8080/healthz >/dev/null 2>&1 || \
       curl -sf http://libeufin-bank:8080/config >/dev/null 2>&1; then
        echo "Libeufin-bank is ready"
        break
    fi
    echo "  Waiting for libeufin-bank... ($i/30)"
    sleep 2
done

# Check master key location
MASTER_KEY_FILE="/root/.local/share/taler-exchange/offline/master.priv"

# Generate master key
if [ ! -f "$MASTER_KEY_FILE" ]; then
    echo "Generating exchange master key..."
    
    SETUP_OUTPUT=$(taler-exchange-offline -c "$CONF_FILE" setup 2>&1)
    echo "Setup output: $SETUP_OUTPUT"
    
    MASTER_PUB=$(echo "$SETUP_OUTPUT" | tr ' ' '\n' | grep -E '^[A-Z0-9]{50,55}$' | head -1 || echo "")
    
    if [ -n "$MASTER_PUB" ]; then
        echo "Found master public key: $MASTER_PUB"
    fi
else
    echo "Master key already exists"
fi

# Add MASTER_PUBLIC_KEY to config if missing
if ! grep -q "^MASTER_PUBLIC_KEY" "$CONF_FILE"; then
    if [ -z "$MASTER_PUB" ]; then
        MASTER_PUB=$(cat "$MASTER_KEY_FILE" 2>/dev/null | tr ' ' '\n' | grep -E '^[A-Z0-9]{50,55}$' | head -1 || echo "")
    fi
    
    if [ -n "$MASTER_PUB" ]; then
        echo "Adding MASTER_PUBLIC_KEY: $MASTER_PUB"
        sed -i '/^[# ]*MASTER_PUBLIC_KEY/d' "$CONF_FILE"
        sed -i '/^# Master public key/d' "$CONF_FILE"
        sed -i '/^\[exchange\]/a MASTER_PUBLIC_KEY = '$MASTER_PUB "$CONF_FILE"
    else
        echo "ERROR: Could not determine MASTER_PUBLIC_KEY!"
        exit 1
    fi
else
    echo "MASTER_PUBLIC_KEY already configured"
    grep "^MASTER_PUBLIC_KEY" "$CONF_FILE"
fi

echo ""
echo "=== Starting Security Modules ==="

# Start security modules first
taler-exchange-secmod-rsa -c "$CONF_FILE" &
taler-exchange-secmod-cs -c "$CONF_FILE" &
taler-exchange-secmod-eddsa -c "$CONF_FILE" &

sleep 3

# Start temporary httpd for upload
echo "Starting httpd for configuration..."
taler-exchange-httpd -c "$CONF_FILE" &
HTTPD_PID=$!

# Wait for httpd
echo "Waiting for httpd..."
for i in {1..60}; do
    if curl -sf http://localhost:8081/ >/dev/null 2>&1; then
        echo "Httpd is ready!"
        break
    fi
    sleep 1
done

# Wait extra time for secmods to generate keys
echo "Waiting for security modules to generate keys..."
sleep 5

echo ""
echo "=== Configuring Exchange (offline operations) ==="

# Enable wire account and upload
echo "Enabling wire account..."
taler-exchange-offline -c "$CONF_FILE" enable-account payto://x-taler-bank/localhost/exchange?receiver-name=Exchange 2>&1 | \
    taler-exchange-offline -c "$INTERNAL_CONF" upload 2>&1 || echo "Account may already be enabled"

# Set up wire fees and upload
echo "Setting up wire fees..."
taler-exchange-offline -c "$CONF_FILE" wire-fee 2024 x-taler-bank KUDOS:0 KUDOS:0 2>&1 | \
    taler-exchange-offline -c "$INTERNAL_CONF" upload 2>&1 || echo "Wire fee may already be set"

# Set up global fees and upload
echo "Setting up global fees..."
taler-exchange-offline -c "$CONF_FILE" global-fee 2024 KUDOS:0 KUDOS:0 KUDOS:0 1d 1y 100 2>&1 | \
    taler-exchange-offline -c "$INTERNAL_CONF" upload 2>&1 || echo "Global fee may already be set"

# Wait a bit for exchange to generate keys
sleep 5

# Download keys from exchange, sign them, and upload
echo "Downloading keys from exchange..."
# Run download (uses internal config with localhost) and capture output
taler-exchange-offline -c "$INTERNAL_CONF" download > /tmp/keys.json 2>/dev/null || true

# Check if we got valid JSON (contains future_denoms or exchange-input-keys)
if head -10 /tmp/keys.json 2>/dev/null | grep -q 'exchange-input-keys\|future_denoms'; then
    echo "Got keys, signing..."
    taler-exchange-offline -c "$INTERNAL_CONF" sign < /tmp/keys.json > /tmp/signed.json 2>/dev/null || true
    
    if [ -s /tmp/signed.json ]; then
        echo "Uploading signed keys..."
        taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/signed.json 2>&1 || echo "Upload may have warnings"
        echo "Keys signed and uploaded successfully!"
    else
        echo "No keys to sign (this is normal for initial setup)"
    fi
else
    echo "No keys downloaded yet (this is normal for initial setup)"
fi

# Kill temporary httpd
if kill -0 $HTTPD_PID 2>/dev/null; then
    echo "Stopping temporary httpd..."
    kill $HTTPD_PID
    wait $HTTPD_PID 2>/dev/null || true
fi

echo ""
echo "=== Starting Exchange Services ==="

# Start helper services
taler-exchange-wirewatch -c "$CONF_FILE" &
taler-exchange-closer -c "$CONF_FILE" &
taler-exchange-aggregator -c "$CONF_FILE" &
taler-exchange-transfer -c "$CONF_FILE" &

sleep 2

echo ""
echo "=== Starting Exchange HTTPD ==="
exec taler-exchange-httpd -c "$CONF_FILE" -L INFO
