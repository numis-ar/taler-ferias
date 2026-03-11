#!/bin/bash
# Initialize Taler Exchange
set -e

echo "=== Initializing Taler Exchange ==="

# Copy config to writable location and replace placeholder
if [ -f /etc/taler/taler.conf ]; then
    echo "Copying config to writable location..."
    cp /etc/taler/taler.conf /tmp/taler-exchange.conf
    
    # Replace placeholder with actual domain
    if [ -n "$FULL_DOMAIN" ]; then
        echo "Configuring for domain: $FULL_DOMAIN"
        sed -i "s|EXCHANGE_HOST_PLACEHOLDER|$FULL_DOMAIN|g" /tmp/taler-exchange.conf
    else
        echo "WARNING: FULL_DOMAIN not set, using placeholder value"
        # Try to get it from elsewhere or use a default
        FULL_DOMAIN="${HOSTNAME:-localhost}"
        sed -i "s|EXCHANGE_HOST_PLACEHOLDER|$FULL_DOMAIN|g" /tmp/taler-exchange.conf
    fi
    
    CONF_FILE=/tmp/taler-exchange.conf
    export TALER_CONFIG=/tmp/taler-exchange.conf
else
    echo "ERROR: Source config not found at /etc/taler/taler.conf"
    exit 1
fi

echo "Using config: $CONF_FILE"

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
PGPASSWORD=talerpassword psql -h postgres -U taler -tc "SELECT 1 FROM pg_database WHERE datname = 'taler_exchange'" | grep -q 1 || {
    echo "Creating taler_exchange database..."
    PGPASSWORD=talerpassword psql -h postgres -U taler -c "CREATE DATABASE taler_exchange;"
}

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

# Generate denomination keys
echo "Setting up wire fees..."
taler-exchange-offline -c "$CONF_FILE" wire-fees 2024 KUDOS 0 0 0 2>&1 || true

# Sign any configured denominations
echo "Signing denomination keys..."
taler-exchange-offline -c "$CONF_FILE" sign 2>&1 || {
    echo "Note: sign may have warnings if no denominations ready"
}

# Try to publish key information if taler-exchange-keyup exists
if which taler-exchange-keyup >/dev/null 2>&1; then
    echo "Publishing exchange keys..."
    taler-exchange-keyup -c "$CONF_FILE" 2>&1 || echo "keyup may need httpd to be running first"
fi

# Show available extensions
echo "Exchange extensions:"
taler-exchange-offline -c "$CONF_FILE" extensions 2>&1 || true

# Show status
echo ""
echo "Exchange Master Public Key:"
if [ -f /var/lib/taler-exchange/master.priv ]; then
    head -5 /var/lib/taler-exchange/master.priv 2>/dev/null || echo "(key file exists)"
else
    echo "(no master key file found)"
fi

# Check keys directory
echo ""
echo "Checking for denomination keys..."
ls -la /var/lib/taler-exchange/ 2>/dev/null || echo "(directory listing failed)"

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
echo "Note: The exchange will generate denomination keys on first startup"
echo "This may take a few minutes..."
exec taler-exchange-httpd -c "$CONF_FILE" -L INFO
