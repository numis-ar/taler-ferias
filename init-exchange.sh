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
    # Remove any existing master_pub file to force regeneration
    rm -f /var/lib/taler-exchange/master_pub
    taler-exchange-offline -c "$CONF_FILE" generate-key 2>&1 || {
        echo "Key generation completed (may have warnings)"
    }
else
    echo "Master key already exists"
fi

# Check for master_pub file (generated alongside master.priv)
if [ -f /var/lib/taler-exchange/master_pub ]; then
    echo "Found master_pub file"
    MASTER_PUB=$(cat /var/lib/taler-exchange/master_pub | tr -d '[:space:]')
    echo "Master public key: $MASTER_PUB"
elif [ -f /var/lib/taler-exchange/master.priv ]; then
    echo "Extracting public key from master.priv..."
    # The master.priv contains lines like:
    # [exchange-master-secret]
    # KEY = ...
    # We need to find any base32-encoded public key
    # Format: 52 characters of base32 (A-Z, 2-7)
    MASTER_PUB=$(grep -o '[A-Z2-7]\{52\}' /var/lib/taler-exchange/master.priv | head -1 || echo "")
fi

# If still no key, try using taler-exchange-keyup
if [ -z "$MASTER_PUB" ]; then
    echo "Trying taler-exchange-keyup..."
    MASTER_PUB=$(taler-exchange-keyup -c "$CONF_FILE" 2>/dev/null | grep -o '[A-Z2-7]\{52\}' | head -1 || echo "")
fi

# If we have a public key, add it to config
if [ -n "$MASTER_PUB" ]; then
    echo "Setting MASTER_PUBLIC_KEY in config..."
    # Remove any existing MASTER_PUBLIC_KEY lines
    sed -i '/^MASTER_PUBLIC_KEY/d' "$CONF_FILE"
    # Add the key
    echo "" >> "$CONF_FILE"
    echo "# Master public key (auto-generated)" >> "$CONF_FILE"
    echo "MASTER_PUBLIC_KEY = $MASTER_PUB" >> "$CONF_FILE"
    echo "Added MASTER_PUBLIC_KEY = $MASTER_PUB"
else
    echo "WARNING: Could not find or extract master public key"
    echo "Files in /var/lib/taler-exchange/:"
    ls -la /var/lib/taler-exchange/
    echo ""
    echo "master.priv contents:"
    cat /var/lib/taler-exchange/master.priv 2>/dev/null || echo "(file not readable)"
    
    # Try to generate a valid key pair using gnunet or openssl
    echo "Attempting to generate a valid master key pair..."
    # Remove corrupted key if any
    rm -f /var/lib/taler-exchange/master.priv
    rm -f /var/lib/taler-exchange/master_pub
    # Regenerate
    taler-exchange-offline -c "$CONF_FILE" generate-key 2>&1
    # Try to extract again
    if [ -f /var/lib/taler-exchange/master_pub ]; then
        MASTER_PUB=$(cat /var/lib/taler-exchange/master_pub | tr -d '[:space:]')
    elif [ -f /var/lib/taler-exchange/master.priv ]; then
        MASTER_PUB=$(grep -o '[A-Z2-7]\{52\}' /var/lib/taler-exchange/master.priv | head -1 || echo "")
    fi
    
    if [ -n "$MASTER_PUB" ]; then
        echo "MASTER_PUBLIC_KEY = $MASTER_PUB" >> "$CONF_FILE"
        echo "Added MASTER_PUBLIC_KEY after regeneration"
    else
        echo "FATAL: Could not generate master key pair"
        exit 1
    fi
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
