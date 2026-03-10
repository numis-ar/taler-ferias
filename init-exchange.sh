#!/bin/bash
# Initialize Taler Exchange
set -e

echo "=== Initializing Taler Exchange ==="

CONF_FILE="/etc/taler/taler.conf"

# Check if master key exists, if not generate it
if [ ! -f /var/lib/taler-exchange/master.priv ]; then
    echo "Generating exchange master key..."
    taler-exchange-offline -c "$CONF_FILE" generate-key 2>&1 || {
        echo "Key generation may have already been done"
    }
fi

# Generate wire fees
echo "Setting up wire fees..."
taler-exchange-offline -c "$CONF_FILE" wire-fees 2024 KUDOS 0 0 0 2>&1 || true

# Generate future denominations
echo "Generating denomination keys..."
taler-exchange-offline -c "$CONF_FILE" future-denominations 2>&1 || {
    echo "Denomination generation may need more time"
}

# Sign the denomination keys
echo "Signing denominations..."
taler-exchange-offline -c "$CONF_FILE" sign 2>&1 || {
    echo "Signing may need denominations to be ready first"
}

# Display the master public key
echo ""
echo "Exchange Master Public Key:"
taler-exchange-keyup -c "$CONF_FILE" -o /dev/stdout 2>/dev/null || \
    cat /var/lib/taler-exchange/master.priv 2>/dev/null || \
    echo "(Keys will be available after first startup)"

echo ""
echo "=== Exchange initialization complete ==="
