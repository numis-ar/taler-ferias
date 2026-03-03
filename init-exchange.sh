#!/bin/bash
# Initialize Taler Exchange for local testing

set -e

echo "=== Taler Exchange Initialization ==="

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U taler >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done
echo "PostgreSQL is ready!"

# Generate master key if it doesn't exist
MASTER_KEY_FILE="/var/lib/taler-exchange/master-key.txt"
if [ ! -f "$MASTER_KEY_FILE" ]; then
    echo "Generating master key..."
    cd /var/lib/taler-exchange
    mkdir -p /var/lib/taler-exchange/offline-keys
    
    # Generate master key using gnunet-ecc
    gnunet-ecc -g1 offline-keys/master.key 2>/dev/null
    
    # Extract the public key
    MASTER_PUB=$(gnunet-ecc -p offline-keys/master.key)
    echo "$MASTER_PUB" > "$MASTER_KEY_FILE"
    echo "Master public key: $MASTER_PUB"
else
    MASTER_PUB=$(cat "$MASTER_KEY_FILE")
    echo "Using existing master key: $MASTER_PUB"
fi

# Create taler.conf with all required settings
echo "Creating Taler configuration..."
cat > /etc/taler/taler.conf << EOF
[taler]
CURRENCY = KUDOS

[exchange]
BASE_URL = http://localhost:8081/
MASTER_PUBLIC_KEY = $MASTER_PUB
CURRENCY_FRACTION_DIGITS = 2
CURRENCY_ROUND_UNIT = KUDOS:0.01
TINY_AMOUNT = KUDOS:0.01
ENABLE_KYC = NO
DISABLE_DIRECT_DEPOSIT = NO
ASSET_TYPE = fiat
DB = postgres
SERVE = tcp
PORT = 8081
TERMS_DIR = /usr/share/taler-exchange/terms
PRIVACY_DIR = /usr/share/taler-exchange/privacy
LEGAL_PRESERVATION = 11 years
SHOPPING_URL = http://localhost:8080/

[exchangedb-postgres]
CONFIG = postgres://taler:talerpassword@postgres:5432/taler_exchange

[wire-fee-default]
WIRE_FEE_KUDOS = KUDOS:0
CLOSING_FEE_KUDOS = KUDOS:0

[fee-deposit]
ZERO = KUDOS:0

[fee-refresh]
ZERO = KUDOS:0

[fee-refund]
ZERO = KUDOS:0

[fee-withdraw]
ZERO = KUDOS:0

[coin_kudos_0_01]
VALUE = KUDOS:0.01
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0

[coin_kudos_0_10]
VALUE = KUDOS:0.10
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0

[coin_kudos_0_50]
VALUE = KUDOS:0.50
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0

[coin_kudos_1]
VALUE = KUDOS:1
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0

[coin_kudos_5]
VALUE = KUDOS:5
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0

[coin_kudos_10]
VALUE = KUDOS:10
DURATION_WITHDRAW = 7 days
DURATION_SPEND = 30 days
FEE_WITHDRAW = KUDOS:0
FEE_DEPOSIT = KUDOS:0
FEE_REFRESH = KUDOS:0
FEE_REFUND = KUDOS:0
EOF

echo "Configuration created at /etc/taler/taler.conf"

# Check if database is already initialized by looking for wire_accounts table
TABLE_CHECK=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -tc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'exchange' AND table_name = 'wire_accounts'" 2>/dev/null | xargs || echo "0")

if [ "$TABLE_CHECK" = "0" ] || [ -z "$TABLE_CHECK" ]; then
    echo "Database not initialized. Running dbinit..."
    taler-exchange-dbinit -c /etc/taler/taler.conf 2>&1 || {
        echo "dbinit may have partially run, continuing..."
    }
    
    # Verify tables exist now
    TABLE_CHECK=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -tc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'exchange' AND table_name = 'wire_accounts'" 2>/dev/null | xargs || echo "0")
    if [ "$TABLE_CHECK" = "0" ]; then
        echo "ERROR: wire_accounts table does not exist after dbinit!"
        echo "Database initialization failed."
        exit 1
    fi
    
    # Add wire accounts for fresh database
    echo "Setting up wire accounts..."
    WIRE_PAYTO="payto://x-taler-bank/localhost:8082/exchange"
    
    PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange << EOSQL 2>&1 || true
    INSERT INTO exchange.wire_accounts (payto_uri, master_sig, is_active, last_change, priority, bank_label) 
    VALUES (
      '$WIRE_PAYTO', 
      decode('00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', 'hex'),
      TRUE, 
      extract(epoch from now())::bigint,
      0,
      'local-bank'
    ) 
    ON CONFLICT DO NOTHING;
EOSQL
    echo "Wire account configured: $WIRE_PAYTO"
else
    echo "Database already initialized. Checking wire accounts..."
    WIRE_COUNT=$(PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange -tc "SELECT COUNT(*) FROM exchange.wire_accounts WHERE is_active = TRUE" 2>/dev/null | xargs || echo "0")
    if [ "$WIRE_COUNT" = "0" ]; then
        echo "No active wire accounts found. Adding default wire account..."
        WIRE_PAYTO="payto://x-taler-bank/localhost:8082/exchange"
        PGPASSWORD=talerpassword psql -h postgres -U taler -d taler_exchange << EOSQL 2>&1 || true
        INSERT INTO exchange.wire_accounts (payto_uri, master_sig, is_active, last_change, priority, bank_label) 
        VALUES (
          '$WIRE_PAYTO', 
          decode('00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', 'hex'),
          TRUE, 
          extract(epoch from now())::bigint,
          0,
          'local-bank'
        ) 
        ON CONFLICT DO NOTHING;
EOSQL
        echo "Wire account added: $WIRE_PAYTO"
    else
        echo "Found $WIRE_COUNT active wire account(s)."
    fi
fi

# Start security modules in background
echo "Starting security modules..."

# Create runtime directories
mkdir -p /tmp/taler-runtime/secmod-eddsa
mkdir -p /tmp/taler-runtime/secmod-rsa
mkdir -p /tmp/taler-runtime/secmod-cs

# EDDSA security module
mkdir -p /root/.local/share/taler-exchange/secmod-eddsa
taler-exchange-secmod-eddsa -c /etc/taler/taler.conf -L INFO 2>&1 &
SECMOD_EDDSA_PID=$!
echo "EDDSA security module started (PID: $SECMOD_EDDSA_PID)"

# RSA security module  
mkdir -p /root/.local/share/taler-exchange/secmod-rsa
taler-exchange-secmod-rsa -c /etc/taler/taler.conf -L INFO 2>&1 &
SECMOD_RSA_PID=$!
echo "RSA security module started (PID: $SECMOD_RSA_PID)"

# CS security module
mkdir -p /root/.local/share/taler-exchange/secmod-cs
taler-exchange-secmod-cs -c /etc/taler/taler.conf -L INFO 2>&1 &
SECMOD_CS_PID=$!
echo "CS security module started (PID: $SECMOD_CS_PID)"

# Wait for security modules to initialize
sleep 3

# Start exchange aggregator
echo "Starting exchange aggregator..."
taler-exchange-aggregator -c /etc/taler/taler.conf -L INFO 2>&1 &
AGGREGATOR_PID=$!

# Start exchange closer
echo "Starting exchange closer..."
taler-exchange-closer -c /etc/taler/taler.conf -L INFO 2>&1 &
CLOSER_PID=$!

# Start exchange transfer
echo "Starting exchange transfer..."
taler-exchange-transfer -c /etc/taler/taler.conf -L INFO 2>&1 &
TRANSFER_PID=$!

# Start exchange wirewatch
echo "Starting exchange wirewatch..."
taler-exchange-wirewatch -c /etc/taler/taler.conf -L INFO 2>&1 &
WIREWATCH_PID=$!

# Start the main HTTP server
echo "=== Starting Taler Exchange HTTP Server on port 8081 ==="
echo "Master Key: $MASTER_PUB"
echo "Database: postgres://taler:talerpassword@postgres:5432/taler_exchange"
echo ""

# Start the main HTTP daemon in foreground
exec taler-exchange-httpd -c /etc/taler/taler.conf -L INFO
