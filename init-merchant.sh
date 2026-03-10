#!/bin/bash
# Initialize Taler Merchant - Configure local exchange
set -e

echo "=== Configuring Merchant for Local Exchange ==="

CONF_FILE="/etc/taler/taler.conf"
EXCHANGE_URL="http://taler-exchange:8081"
MERCHANT_DB="taler_merchant"

# Wait for exchange to be ready
echo "Fetching exchange keys..."
for i in {1..30}; do
    if curl -sf "$EXCHANGE_URL/keys" >/dev/null 2>&1; then
        echo "Exchange keys available"
        break
    fi
    echo "  Waiting for exchange keys... ($i/30)"
    sleep 2
done

# Get the master public key from exchange
MASTER_KEY=$(curl -sf "$EXCHANGE_URL/keys" | jq -r '.master_public_key' 2>/dev/null || echo "")

if [ -z "$MASTER_KEY" ] || [ "$MASTER_KEY" = "null" ]; then
    echo "WARNING: Could not get master key from exchange. Using placeholder."
    MASTER_KEY="PLACEHOLDER_KEY"
fi

echo "Exchange Master Key: $MASTER_KEY"

# Update merchant configuration to use local exchange
echo "Configuring merchant to use local exchange..."

# Create a temporary SQL file to insert the exchange
PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" <<-EOSQL
    -- Add local exchange if not exists
    INSERT INTO merchant.merchant_exchanges 
        (exchange_url, master_pub, exchange_pub, last_keys, account_serial)
    SELECT 
        '${EXCHANGE_URL}/',
        decode('${MASTER_KEY}', 'base64'),
        decode('${MASTER_KEY}', 'base64'),
        '{}'::jsonb,
        0
    WHERE NOT EXISTS (
        SELECT 1 FROM merchant.merchant_exchanges 
        WHERE exchange_url = '${EXCHANGE_URL}/'
    );
    
    -- Add bank account for admin instance if not exists
    INSERT INTO merchant.merchant_accounts 
        (merchant_serial, account_name, payto_uri)
    SELECT 
        m.merchant_serial,
        'default',
        'payto://x-taler-bank/localhost/merchant'
    FROM merchant.merchant_instances m
    WHERE m.merchant_id = 'admin'
    AND NOT EXISTS (
        SELECT 1 FROM merchant.merchant_accounts a
        WHERE a.merchant_serial = m.merchant_serial
    );
EOSQL

echo "=== Merchant configuration complete ==="
echo ""
echo "Local exchange configured: $EXCHANGE_URL"
echo "Master Key: $MASTER_KEY"
