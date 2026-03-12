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
if [ -n "$FULL_DOMAIN" ]; then
    echo "FULL_DOMAIN is set to: $FULL_DOMAIN"
    sed -i "s|https://EXCHANGE_HOST_PLACEHOLDER/exchange/|https://${FULL_DOMAIN}/exchange/|g" "$CONF_FILE"
else
    echo "FULL_DOMAIN not set, using localhost for internal operations"
    sed -i 's|https://EXCHANGE_HOST_PLACEHOLDER/exchange/|http://localhost:8081/|g' "$CONF_FILE"
fi

# For internal operations, we use localhost:8081
# Note: INTERNAL_CONF will be created AFTER master key is added to CONF_FILE
INTERNAL_CONF="/tmp/taler-exchange-internal.conf"

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
    SETUP_OUTPUT=$(taler-exchange-offline -c "$CONF_FILE" setup 2>&1)
    echo "Setup output: $SETUP_OUTPUT"
    
    MASTER_PUB=$(echo "$SETUP_OUTPUT" | tr ' ' '\n' | grep -E '^[A-Z0-9]{50,55}$' | head -1 || echo "")
    
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

# Now create INTERNAL_CONF (after master key is in CONF_FILE)
echo "Creating internal config..."
cp "$CONF_FILE" "$INTERNAL_CONF"
echo "DIFF internal config..."
diff "$CONF_FILE" "$INTERNAL_CONF"
# sed -i 's|https://[^/]*/exchange/|http://localhost:8081/|g' "$INTERNAL_CONF"
# sed -i 's|BASE_URL = .*|BASE_URL = http://localhost:8081/|g' "$INTERNAL_CONF"
echo "Internal config created with MASTER_PUBLIC_KEY:"
grep "^MASTER_PUBLIC_KEY" "$INTERNAL_CONF" || echo "WARNING: No MASTER_PUBLIC_KEY in internal config!"

echo ""
echo "=== Starting Security Modules ==="

# Start security modules first
taler-exchange-secmod-rsa -c "$CONF_FILE" -l rsa.log -L DEBUG &
taler-exchange-secmod-cs -c "$CONF_FILE" -l cs.log -L DEBUG  &
taler-exchange-secmod-eddsa -c "$CONF_FILE" -l eddsa.log -L DEBUG  &

sleep 3

# Start httpd for configuration
echo "Starting httpd for configuration..."
taler-exchange-httpd -c "$INTERNAL_CONF" -l httpd.log -L DEBUG &
HTTPD_PID=$!

# Wait for httpd to be running (not necessarily /keys)
echo "Waiting for httpd to be running..."
for i in {1..60}; do
    if curl -sf http://localhost:8081/ >/dev/null 2>&1 || curl -sf http://localhost:8081/config >/dev/null 2>&1; then
        echo "Httpd is running!"
        break
    fi
    if ! kill -0 $HTTPD_PID 2>/dev/null; then
        echo "Httpd died! Restarting..."
        taler-exchange-httpd -c "$INTERNAL_CONF" -l httpd.log -L DEBUG &
        HTTPD_PID=$!
    fi
    sleep 1
done

# Wait extra time for secmods to generate keys and httpd to be fully ready
echo "Waiting for security modules and httpd to be fully ready..."
sleep 10

echo ""
echo "=== Configuring Exchange (offline operations) ==="

# Verify master key exists
MASTER_KEY_FILE="/root/.local/share/taler-exchange/offline/master.priv"
echo "Checking master key at $MASTER_KEY_FILE..."
if [ -f "$MASTER_KEY_FILE" ]; then
    echo "Master key file exists, size: $(wc -c < "$MASTER_KEY_FILE") bytes"
    ls -la "$MASTER_KEY_FILE"
else
    echo "ERROR: Master key file not found!"
fi

# Show internal config
echo "Internal config MASTER_PUBLIC_KEY:"
grep "^MASTER_PUBLIC_KEY" "$INTERNAL_CONF" || echo "WARNING: No MASTER_PUBLIC_KEY in internal config!"

# exchange: BE71096123456769
# wallet: FI1410093000123458
# merchant: DE75512108001245126199

# Bank payto URL - MUST match [exchange-account-1] PAYTO_URI in config
BANK_PAYTO_URL="payto://iban/BE71096123456769?receiver-name=PSP"
echo "Bank payto URL: $BANK_PAYTO_URL"

# Enable wire account - generate signed command and upload
echo ""
echo "Running enable-account command..."
taler-exchange-offline -c "$INTERNAL_CONF" enable-account "$BANK_PAYTO_URL" 2>&1 > /tmp/enable-account.json
ENABLE_EXIT=$?

echo ""
echo "enable-account exit code: $ENABLE_EXIT"
echo "Output file size: $(wc -c < /tmp/enable-account.json 2>/dev/null || echo 0) bytes"

if [ -s /tmp/enable-account.json ] && head -1 /tmp/enable-account.json | grep -qE '[\{\[]'; then
    echo "Valid JSON detected, uploading..."
    for retry in 1 2 3; do
        echo "Upload attempt $retry/3..."
        if taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/enable-account.json 2>&1; then
            echo "Upload successful!"
            break
        else
            UPLOAD_EXIT=$?
            echo "Upload failed with exit code $UPLOAD_EXIT"
            if [ $retry -lt 3 ]; then
                echo "Retrying in 3 seconds..."
                sleep 3
            fi
        fi
    done
else
    echo "ERROR: enable-account did not produce valid JSON output"
    echo "Raw output:"
    cat /tmp/enable-account.json
fi

# Wait for account to be processed
echo "Waiting for wire account to be processed..."
sleep 5

# Set up wire fees (needed for /keys to work)
echo ""
echo "Setting up wire fees..."
taler-exchange-offline -c "$INTERNAL_CONF" wire-fee now iban KUDOS:0 KUDOS:0 2>&1 > /tmp/wire-fee.json
WIRE_EXIT=$?

echo "wire-fee exit code: $WIRE_EXIT"
if [ -s /tmp/wire-fee.json ] && head -1 /tmp/wire-fee.json | grep -qE '[\{\[]'; then
    echo "Uploading wire fees..."
    taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/wire-fee.json 2>&1
else
    echo "No wire-fee JSON output"
fi

# Set up global fees
echo ""
echo "Setting up global fees..."
taler-exchange-offline -c "$INTERNAL_CONF" global-fee now KUDOS:0 KUDOS:0 KUDOS:0 1d 1y 100 2>&1 > /tmp/global-fee.json
GLOBAL_EXIT=$?

echo "global-fee exit code: $GLOBAL_EXIT"
if [ -s /tmp/global-fee.json ] && head -1 /tmp/global-fee.json | grep -qE '[\{\[]'; then
    echo "Uploading global fees..."
    taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/global-fee.json 2>&1
else
    echo "No global-fee JSON output"
fi

# Wait for exchange to process everything
sleep 3

# Check wire accounts
echo "Checking wire accounts..."
ACCOUNT_COUNT=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -tc "SELECT COUNT(*) FROM exchange.wire_accounts;" 2>/dev/null | xargs || echo "0")
echo "Wire accounts found: $ACCOUNT_COUNT"

# Show wire account details
echo "Wire account details:"
PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -c "SELECT payto_uri, is_active, length(master_sig) as sig_len FROM exchange.wire_accounts;" 2>/dev/null || echo "Could not query wire_accounts"

# If no wire accounts, try direct SQL insert as fallback
if [ "$ACCOUNT_COUNT" = "0" ]; then
    echo "WARNING: No wire accounts found after offline upload. Trying direct SQL insert..."
    
    # Get the master public key for signature generation
    MASTER_PUB_KEY=$(grep "^MASTER_PUBLIC_KEY" "$INTERNAL_CONF" 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d ' ')
    echo "Master public key: $MASTER_PUB_KEY"
    
    # Check actual table schema first
    echo "Checking wire_accounts schema..."
    PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -c "\d exchange.wire_accounts" 2>/dev/null || echo "Could not describe table"
    
    # The offline tool is the proper way to add wire accounts.
    # Direct SQL insert won't work because:
    # - master_sig must be exactly 64 bytes (CHECK constraint)
    # - last_change is required and must be monotonic
    # - Signatures must be valid
    # 
    # We need to debug why the upload is failing.
    echo ""
    echo "=== DEBUG: Checking enable-account output ==="
    if [ -f /tmp/enable-account.json ]; then
        echo "enable-account.json exists ($(wc -c < /tmp/enable-account.json) bytes):"
        cat /tmp/enable-account.json
    else
        echo "enable-account.json not found!"
    fi
    
    echo ""
    echo "=== DEBUG: Trying upload again with verbose output ==="
    if [ -f /tmp/enable-account.json ]; then
        taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/enable-account.json 2>&1 || echo "Upload failed"
    fi
    
    echo ""
    echo "=== DEBUG: Check exchange httpd availability ==="
    curl -v http://localhost:8081/ 2>&1 | head -20
    
    # Check again
    sleep 1
    ACCOUNT_COUNT=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -tc "SELECT COUNT(*) FROM exchange.wire_accounts;" 2>/dev/null | xargs || echo "0")
    echo "Wire accounts after direct insert: $ACCOUNT_COUNT"
fi

# Download, sign and upload online keys (needed for /keys to work)
echo ""
echo "=== Downloading and Signing Online Keys ==="
echo "Downloading keys from exchange..."
taler-exchange-offline -c "$INTERNAL_CONF" download 2>&1 > /tmp/keys-downloaded.json
DOWNLOAD_EXIT=${PIPESTATUS[0]}

if [ $DOWNLOAD_EXIT -eq 0 ] && [ -s /tmp/keys-downloaded.json ] && head -1 /tmp/keys-downloaded.json | grep -qE '[\{\[]'; then
    echo "Got keys ($(wc -c < /tmp/keys-downloaded.json) bytes), signing..."
    taler-exchange-offline -c "$INTERNAL_CONF" sign < /tmp/keys-downloaded.json 2>&1 > /tmp/keys-signed.json
    SIGN_EXIT=${PIPESTATUS[0]}
    
    if [ $SIGN_EXIT -eq 0 ] && [ -s /tmp/keys-signed.json ]; then
        echo "Uploading signed keys ($(wc -c < /tmp/keys-signed.json) bytes)..."
        taler-exchange-offline -c "$INTERNAL_CONF" upload < /tmp/keys-signed.json 2>&1
        echo "Keys signed and uploaded!"
    else
        echo "Sign failed or produced no output"
    fi
else
    echo "Download failed or produced invalid output"
    echo "Download exit code: $DOWNLOAD_EXIT"
fi

# Wait for keys to be processed and verify /keys works
echo ""
echo "=== Final Verification ==="
sleep 3
for i in {1..10}; do
    if curl -sf http://localhost:8081/keys > /tmp/final-keys.json 2>/dev/null; then
        echo "/keys endpoint is working!"
        MASTER_KEY=$(cat /tmp/final-keys.json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("master_public_key",""))' 2>/dev/null)
        echo "Exchange Master Key: $MASTER_KEY"
        break
    fi
    echo "Waiting for /keys... ($i/10)"
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
