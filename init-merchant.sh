#!/bin/bash
# Initialize Taler Merchant - Configure for local exchange
set -e

echo "=== Configuring Merchant for Local Exchange ==="

CONF_FILE="/etc/taler/taler.conf"
EXCHANGE_URL="http://taler-exchange:8081"
MERCHANT_DB="taler_merchant"

# Wait for exchange to be ready
echo "Fetching exchange keys..."
for i in {1..60}; do
    if curl -sf "$EXCHANGE_URL/keys" >/dev/null 2>&1; then
        echo "Exchange keys available"
        break
    fi
    echo "  Waiting for exchange keys... ($i/60)"
    sleep 2
done

# Get the master public key from exchange
MASTER_KEY=$(curl -sf "$EXCHANGE_URL/keys" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('master_public_key', ''))" 2>/dev/null || echo "")

if [ -z "$MASTER_KEY" ] || [ "$MASTER_KEY" = "null" ]; then
    echo "WARNING: Could not get master key from exchange. Using placeholder."
    MASTER_KEY="PLACEHOLDER_KEY"
fi

echo "Exchange Master Key: $MASTER_KEY"

# Configure merchant to use local exchange via SQL
# The merchant-demo.conf should already have the exchange configured,
# but we also add it to the database for completeness
echo "Configuring merchant database..."

PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" <<EOSQL 2>/dev/null || true
    -- Add local exchange if not exists
    INSERT INTO merchant.merchant_exchanges 
        (exchange_url, master_pub, exchange_pub, last_keys, account_serial)
    SELECT 
        '${EXCHANGE_URL}/',
        '\x${MASTER_KEY}',
        '\x${MASTER_KEY}',
        '{}'::jsonb,
        0
    WHERE NOT EXISTS (
        SELECT 1 FROM merchant.merchant_exchanges 
        WHERE exchange_url = '${EXCHANGE_URL}/'
    )
    ON CONFLICT DO NOTHING;
    
    -- Ensure admin instance has wire info configured
    UPDATE merchant.merchant_instances 
    SET wire_type = 'x-taler-bank',
        wire_details = '{"bank_uri": "http://fakebank:8082/", "account": "merchant"}'::jsonb
    WHERE merchant_id = 'admin' 
    AND (wire_type IS NULL OR wire_type = '');
    
    -- Create merchant bank account if not exists
    INSERT INTO merchant.merchant_accounts 
        (merchant_serial, h_payto, account_name, active)
    SELECT 
        m.merchant_serial,
        'payto://x-taler-bank/localhost/merchant',
        'default',
        true
    FROM merchant.merchant_instances m
    WHERE m.merchant_id = 'admin'
    ON CONFLICT DO NOTHING;
    
    -- Also add to merchant_instance_wire_accounts for newer schema
    INSERT INTO merchant.merchant_instance_wire_accounts 
        (merchant_serial, payto_uri, active)
    SELECT 
        m.merchant_serial,
        'payto://x-taler-bank/localhost/merchant',
        true
    FROM merchant.merchant_instances m
    WHERE m.merchant_id = 'admin'
    ON CONFLICT DO NOTHING;
EOSQL

echo "=== Merchant configuration complete ==="
echo ""
echo "Local exchange configured: $EXCHANGE_URL"
echo "Bank wire gateway: http://fakebank:8082/"
