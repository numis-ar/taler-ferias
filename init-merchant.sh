#!/bin/bash
# Initialize Taler Merchant - Configure for local exchange
set -e

echo "=== Configuring Merchant for Local Exchange ==="

RO_CONF_FILE="/etc/taler/taler.conf"
CONF_FILE="/tmp/taler.conf"
EXCHANGE_URL="http://taler-exchange:8081"
MERCHANT_DB="taler_merchant"

cp $RO_CONF_FILE $CONF_FILE

# Wait for exchange to be ready
echo "Fetching exchange keys from $EXCHANGE_URL..."
for i in {1..90}; do
    KEYS_RESPONSE=$(curl -sf "$EXCHANGE_URL/keys" 2>/dev/null || echo "")
    if [ -n "$KEYS_RESPONSE" ]; then
        echo "Exchange responded"
        # Check if it has master_public_key
        MASTER_KEY=$(echo "$KEYS_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('master_public_key', ''))" 2>/dev/null || echo "")
        if [ -n "$MASTER_KEY" ] && [ "$MASTER_KEY" != "null" ]; then
            echo "Exchange master key found: ${MASTER_KEY:0:20}..."
            break
        fi
    fi
    echo "  Waiting for exchange keys... ($i/90)"
    sleep 2
done

if [ -z "$MASTER_KEY" ] || [ "$MASTER_KEY" = "null" ]; then
    echo "WARNING: Could not get master key from exchange after 180 seconds."
    echo "Exchange response was: $KEYS_RESPONSE"
    MASTER_KEY="PLACEHOLDER_KEY"
fi

echo "Exchange Master Key: $MASTER_KEY"

# Update config file with master key if it's valid
if [ -n "$MASTER_KEY" ] && [ "$MASTER_KEY" != "null" ] && [ "$MASTER_KEY" != "PLACEHOLDER_KEY" ] && [ ${#MASTER_KEY} -gt 50 ]; then
    echo "Updating merchant config with master key: ${MASTER_KEY:0:20}..."
    # Remove any existing MASTER_KEY line and add new one
    sed -i '/^MASTER_KEY = /d' /tmp/taler.conf 2>/dev/null || true
    sed -i "/^\[merchant-exchange-local\]/a MASTER_KEY = \"$MASTER_KEY\"" /tmp/taler.conf 2>/dev/null || true
fi

# Check if merchant schema exists
SCHEMA_EXISTS=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" -tc "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'merchant'" 2>/dev/null | grep -q 1 && echo 'yes' || echo 'no')
if [ "$SCHEMA_EXISTS" = "no" ]; then
    echo "ERROR: Merchant schema not found. Database may not be initialized."
    echo "Trying to initialize now..."
    taler-merchant-dbinit -c "$CONF_FILE" 2>&1 || true
fi

# Configure merchant to use local exchange via SQL
# The merchant-demo.conf should already have the exchange configured,
# but we also add it to the database for completeness
echo "Configuring merchant database..."

echo "Checking database tables..."
PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" -c "\dt merchant.*" 2>/dev/null | head -20


taler-merchant-httpd -c /tmp/taler.conf -l httpd.log -L DEBUG &
HTTPD_PID=$!

sleep 3

TOKEN=$(curl admin:asdasdasd@taler-merchant:9966/private/token -d '{"scope":"all"}' | jq -r .access_token)
curl taler-merchant:9966/private/accounts -H "Authorization: Bearer $TOKEN" -d '{"payto_uri":"payto://iban/DE75512108001245126199?receiver-name=merchant"}'

if kill -0 $HTTPD_PID 2>/dev/null; then
    echo "Stopping temporary httpd..."
    kill $HTTPD_PID
    wait $HTTPD_PID 2>/dev/null || true
fi

echo "=== Merchant configuration complete ==="
echo ""
echo "Local exchange configured: $EXCHANGE_URL"
echo "Bank wire gateway: http://libeufin-bank:8080/"
