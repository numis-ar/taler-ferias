#!/bin/bash
# Initialize Libeufin Bank accounts
set -e

echo "=== Initializing Libeufin Bank ==="

BANK_URL="http://localhost:8082"
ADMIN_USER="admin"
ADMIN_PASS="bankadmin"

# Wait for bank to be fully ready
echo "Waiting for bank API..."
for i in {1..30}; do
    if curl -sf "$BANK_URL/" >/dev/null 2>&1; then
        echo "Bank API is up"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Create exchange account (for the Taler exchange)
echo "Creating exchange account..."
curl -sf -X POST "$BANK_URL/accounts" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d '{
        "username": "exchange",
        "password": "exchange_password",
        "name": "Taler Exchange",
        "is_public": false,
        "is_taler_exchange": true
    }' || echo "Exchange account may already exist"

# Create merchant account (for receiving payments)
echo "Creating merchant account..."
curl -sf -X POST "$BANK_URL/accounts" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d '{
        "username": "merchant",
        "password": "merchant_password",
        "name": "Taler Merchant",
        "is_public": false
    }' || echo "Merchant account may already exist"

# Create demo user account (for testing)
echo "Creating demo user account..."
curl -sf -X POST "$BANK_URL/accounts" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d '{
        "username": "demo",
        "password": "demo_password",
        "name": "Demo User",
        "is_public": false
    }' || echo "Demo account may already exist"

# Add initial balance to exchange (simulated - in production this would be real funds)
echo "Setting up exchange reserve..."
curl -sf -X POST "$BANK_URL/accounts/exchange/transactions" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d '{
        "amount": "100000.00",
        "subject": "Initial exchange reserve"
    }' || echo "Exchange funding may have failed"

echo "=== Libeufin Bank initialization complete ==="
echo ""
echo "Bank accounts created:"
echo "  - exchange / exchange_password (for Taler Exchange)"
echo "  - merchant / merchant_password (for Merchant payouts)"
echo "  - demo / demo_password (for testing)"
echo "  - admin / bankadmin (bank admin)"
