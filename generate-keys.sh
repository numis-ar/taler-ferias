#!/bin/bash
# Generate keys for Taler Exchange

echo "=== Generating Exchange Keys ==="

# Generate a master key using openssl
MASTER_KEY=$(openssl rand -base64 32 | base32 | tr -d '=' | cut -c1-52)
echo "Generated master key: $MASTER_KEY"

# Create override config file with the master key
cat > /tmp/exchange-override.conf << EOF
[exchange]
MASTER_PUBLIC_KEY = $MASTER_KEY
EOF

echo "Created override config at /tmp/exchange-override.conf"
