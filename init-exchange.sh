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

# Generate master key using 'setup' command
# This creates master.priv and outputs the public key
if [ ! -f /var/lib/taler-exchange/master.priv ]; then
    echo "Generating exchange master key with 'taler-exchange-offline setup'..."
    # Run setup and capture the public key output
    SETUP_OUTPUT=$(taler-exchange-offline -c "$CONF_FILE" setup 2>&1)
    SETUP_STATUS=$?
    echo "Setup command exit status: $SETUP_STATUS"
    echo "Setup output:"
    echo "$SETUP_OUTPUT"
    
    # The setup command outputs the public key directly
    # Look for a line that looks like: YE6Q6TR1ED... (base32, 52 chars)
    MASTER_PUB=$(echo "$SETUP_OUTPUT" | tr ' ' '\n' | grep -E '^[A-Z2-7]{52}$' | head -1 || echo "")
    
    if [ -z "$MASTER_PUB" ]; then
        # Try broader search
        MASTER_PUB=$(echo "$SETUP_OUTPUT" | grep -o '[A-Z2-7]\{52\}' | head -1 || echo "")
    fi
    
    if [ -n "$MASTER_PUB" ]; then
        echo "Found master public key from setup: $MASTER_PUB"
    else
        echo "WARNING: Could not extract public key from setup output"
        echo "Searching for any public key patterns..."
        echo "$SETUP_OUTPUT" | grep -i "public\|master\|key" || true
    fi
else
    echo "Master key already exists at /var/lib/taler-exchange/master.priv"
fi

# Always try to extract and add MASTER_PUBLIC_KEY if missing
if ! grep -q "^MASTER_PUBLIC_KEY" "$CONF_FILE"; then
    if [ -z "$MASTER_PUB" ]; then
        # Try to extract from existing key file or info command
        if [ -f /var/lib/taler-exchange/master.priv ]; then
            echo "Trying to extract public key from master.priv..."
            # The master.priv might contain the public key in comments or as a separate entry
            MASTER_PUB=$(cat /var/lib/taler-exchange/master.priv 2>/dev/null | tr ' ' '\n' | grep -E '^[A-Z2-7]{52}$' | head -1 || echo "")
        fi
        
        if [ -z "$MASTER_PUB" ]; then
            echo "Trying taler-exchange-offline info..."
            INFO_OUTPUT=$(taler-exchange-offline -c "$CONF_FILE" info 2>&1 || true)
            echo "Info output: $INFO_OUTPUT"
            MASTER_PUB=$(echo "$INFO_OUTPUT" | tr ' ' '\n' | grep -E '^[A-Z2-7]{52}$' | head -1 || echo "")
        fi
    fi
    
    if [ -n "$MASTER_PUB" ]; then
        echo "Adding MASTER_PUBLIC_KEY to config: $MASTER_PUB"
        # Remove any commented or empty MASTER_PUBLIC_KEY lines first
        sed -i '/^MASTER_PUBLIC_KEY/d' "$CONF_FILE"
        sed -i '/^# Master public key/d' "$CONF_FILE"
        # Add the key
        echo "" >> "$CONF_FILE"
        echo "# Master public key" >> "$CONF_FILE"
        echo "MASTER_PUBLIC_KEY = $MASTER_PUB" >> "$CONF_FILE"
        echo "Successfully added MASTER_PUBLIC_KEY"
    else
        echo "ERROR: Could not determine MASTER_PUBLIC_KEY!"
        echo "Config file contents:"
        cat "$CONF_FILE"
        exit 1
    fi
else
    echo "MASTER_PUBLIC_KEY already in config"
fi

# Show current key status
echo ""
echo "Exchange key status:"
ls -la /var/lib/taler-exchange/ 2>/dev/null || echo "(directory listing failed)"

# Show master.priv contents if exists
if [ -f /var/lib/taler-exchange/master.priv ]; then
    echo ""
    echo "Contents of master.priv:"
    cat /var/lib/taler-exchange/master.priv
fi

# Check if MASTER_PUBLIC_KEY is now in config
echo ""
if grep -q "^MASTER_PUBLIC_KEY" "$CONF_FILE"; then
    echo "MASTER_PUBLIC_KEY configured:"
    grep "^MASTER_PUBLIC_KEY" "$CONF_FILE"
else
    echo "WARNING: MASTER_PUBLIC_KEY not found in config!"
    echo "Current config file:"
    cat "$CONF_FILE"
fi

# Set up wire fees
echo ""
echo "Setting up wire fees..."
taler-exchange-offline -c "$CONF_FILE" wire-fees 2024 KUDOS 0 0 0 2>&1 || true

# Sign denominations
echo "Signing denomination keys..."
taler-exchange-offline -c "$CONF_FILE" sign 2>&1 || {
    echo "Note: sign may have warnings if no denominations ready"
}

# Start httpd briefly to generate keys
echo ""
echo "Starting exchange httpd to generate denomination keys..."
taler-exchange-httpd -c "$CONF_FILE" &
HTTPD_PID=$!

# Wait for keys endpoint
echo "Waiting for /keys endpoint..."
for i in {1..60}; do
    if curl -sf http://localhost:8081/keys >/dev/null 2>&1; then
        echo "Keys endpoint is ready!"
        break
    fi
    echo "  Waiting for keys... ($i/60)"
    sleep 2
done

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
