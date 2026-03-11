#!/bin/bash
# Initialize Taler Exchange
set -e

echo "=== Initializing Taler Exchange ==="

# Use provided config or default
CONF_FILE="${TALER_CONFIG:-/etc/taler/taler.conf}"

# If using the copied config from docker-compose
if [ -f /tmp/taler-exchange.conf ]; then
    CONF_FILE=/tmp/taler-exchange.conf
    export TALER_CONFIG=/tmp/taler-exchange.conf
fi

echo "Using config: $CONF_FILE"

# Check if config exists and is readable
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Config file not found: $CONF_FILE"
    exit 1
fi

# Show config content for debugging
echo "Config BASE_URL:"
grep "BASE_URL" "$CONF_FILE" | head -1

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U taler; do
    echo "  PostgreSQL not ready, waiting..."
    sleep 2
done
echo "PostgreSQL is ready"

# Ensure exchange database exists
echo "Checking exchange database..."
if ! PGPASSWORD=talerpassword psql -h postgres -U taler -tc "SELECT 1 FROM pg_database WHERE datname = 'taler_exchange'" | grep -q 1; then
    echo "Creating taler_exchange database..."
    PGPASSWORD=talerpassword psql -h postgres -U taler -c "CREATE DATABASE taler_exchange;"
fi

# Initialize database schema
echo "Initializing exchange database schema..."
taler-exchange-dbinit -c "$CONF_FILE" 2>&1 || {
    echo "DB init may have already been done or failed"
}

# Wait for fakebank
echo "Waiting for fakebank..."
for i in {1..30}; do
    if curl -sf http://fakebank:8082/healthz >/dev/null 2>&1 || \
       curl -sf http://fakebank:8082/accounts >/dev/null 2>&1; then
        echo "Fakebank is ready"
        break
    fi
    echo "  Waiting for fakebank... ($i/30)"
    sleep 2
done

# Generate master key if not exists
if [ ! -f /var/lib/taler-exchange/master.priv ]; then
    echo "Generating exchange master key..."
    taler-exchange-offline -c "$CONF_FILE" generate-key 2>&1 || {
        echo "Key generation may have failed or already exists"
    }
else
    echo "Master key already exists"
fi

# Extract and add master public key to config
if [ -f /var/lib/taler-exchange/master.priv ]; then
    echo "Extracting master public key..."
    # Extract the public key from the private key file
    # Format in master.priv is typically base32-encoded public key
    MASTER_PUB=$(grep -o '[A-Z2-7]\{52\}' /var/lib/taler-exchange/master.priv | head -1 || echo "")
    if [ -z "$MASTER_PUB" ]; then
        # Try alternative extraction
        MASTER_PUB=$(cat /var/lib/taler-exchange/master.priv | tr -d '\n' | grep -o '[A-Z2-7]\{40,60\}' | head -1 || echo "")
    fi
    if [ -n "$MASTER_PUB" ]; then
        echo "Found master public key: $MASTER_PUB"
        echo "Adding MASTER_PUBLIC_KEY to config..."
        # Replace placeholder or add if not exists
        sed -i "s/MASTER_KEY_PLACEHOLDER/$MASTER_PUB/" "$CONF_FILE"
    else
        echo "WARNING: Could not extract master public key from master.priv"
        echo "Contents of master.priv:"
        head -5 /var/lib/taler-exchange/master.priv
    fi
else
    echo "WARNING: master.priv not found after key generation"
fi

# Set up wire fees
echo "Setting up wire fees..."
taler-exchange-offline -c "$CONF_FILE" wire-fees 2024 KUDOS 0 0 0 2>&1 || true

# Sign denominations if any exist
echo "Signing denomination keys..."
taler-exchange-offline -c "$CONF_FILE" sign 2>&1 || {
    echo "Note: sign may have warnings if no denominations ready"
}

# Show what we have
echo ""
echo "Exchange key status:"
ls -la /var/lib/taler-exchange/ 2>/dev/null | head -20 || echo "(directory listing failed)"

# Check master key
echo ""
if [ -f /var/lib/taler-exchange/master.priv ]; then
    echo "Master key exists:"
    head -3 /var/lib/taler-exchange/master.priv
else
    echo "WARNING: No master key found!"
fi

# Start httpd briefly to generate keys if needed
echo ""
echo "Starting exchange httpd to generate keys (if needed)..."
taler-exchange-httpd -c "$CONF_FILE" &
HTTPD_PID=$!

# Wait for keys to be generated
echo "Waiting for /keys endpoint..."
for i in {1..60}; do
    if curl -sf http://localhost:8081/keys >/dev/null 2>&1; then
        echo "Keys endpoint is ready!"
        break
    fi
    echo "  Waiting for keys... ($i/60)"
    sleep 2
done

# Kill the temporary httpd
if kill -0 $HTTPD_PID 2>/dev/null; then
    echo "Stopping temporary httpd..."
    kill $HTTPD_PID
    wait $HTTPD_PID 2>/dev/null || true
fi

echo ""
echo "=== Starting Exchange Services ==="

# Start helper services in background
echo "Starting wirewatch..."
taler-exchange-wirewatch -c "$CONF_FILE" &

echo "Starting closer..."
taler-exchange-closer -c "$CONF_FILE" &

echo "Starting aggregator..."
taler-exchange-aggregator -c "$CONF_FILE" &

echo "Starting transfer..."
taler-exchange-transfer -c "$CONF_FILE" &

# Give helper services time to start
sleep 2

echo ""
echo "=== Starting Exchange HTTPD ==="
exec taler-exchange-httpd -c "$CONF_FILE" -L INFO
