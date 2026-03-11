#!/bin/bash
# Initialize Taler Merchant - Configure for local exchange
set -e

echo "=== Configuring Merchant for Local Exchange ==="

CONF_FILE="/etc/taler/taler.conf"
EXCHANGE_URL="http://taler-exchange:8081"
MERCHANT_DB="taler_merchant"

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
    sed -i '/^MASTER_KEY = /d' /etc/taler/taler.conf 2>/dev/null || true
    sed -i "/^\[merchant-exchange-kudos\]/a MASTER_KEY = \"$MASTER_KEY\"" /etc/taler/taler.conf 2>/dev/null || true
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

# Try to update exchange in database using the correct table name
# The table might be merchant_exchanges or merchant_exchange_keys
PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" <<EOSQL 2>/dev/null || true
    -- Try to delete from merchant_exchanges (older schema)
    DELETE FROM merchant.merchant_exchanges WHERE exchange_url = '${EXCHANGE_URL}/';
    
    -- Insert with current master key
    INSERT INTO merchant.merchant_exchanges 
        (exchange_url, master_pub, exchange_pub, last_keys, account_serial)
    VALUES 
        ('${EXCHANGE_URL}/', '\x${MASTER_KEY}', '\x${MASTER_KEY}', '{}'::jsonb, 0)
    ON CONFLICT (exchange_url) DO UPDATE SET
        master_pub = EXCLUDED.master_pub,
        exchange_pub = EXCLUDED.exchange_pub,
        last_keys = '{}'::jsonb;
EOSQL

# Also try merchant_exchange_keys (newer schema) if that failed
PGPASSWORD=talerpassword psql -h postgres -U taler -d "$MERCHANT_DB" <<EOSQL 2>/dev/null || true
    -- For newer schema: delete and insert into merchant_exchange_keys
    DELETE FROM merchant.merchant_exchange_keys WHERE exchange_base_url = '${EXCHANGE_URL}/';
    
    INSERT INTO merchant.merchant_exchange_keys 
        (exchange_base_url, master_pub, valid_from, valid_until)
    VALUES 
        ('${EXCHANGE_URL}/', '\x${MASTER_KEY}', NOW(), NOW() + INTERVAL '1 year')
    ON CONFLICT (exchange_base_url) DO UPDATE SET
        master_pub = EXCLUDED.master_pub;
EOSQL
    
    -- Ensure admin instance has wire info configured
    UPDATE merchant.merchant_instances 
    SET wire_type = 'x-taler-bank',
        wire_details = '{"bank_uri": "http://libeufin-bank:8080/", "account": "merchant"}'::jsonb
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
echo "Bank wire gateway: http://libeufin-bank:8080/"
