#!/bin/bash
set -e

echo "=== Starting Libeufin Bank ==="

# Set postgres password
export PGPASSWORD=talerpassword

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until pg_isready -h postgres -U taler 2>/dev/null; do
    echo "  PostgreSQL not ready, waiting..."
    sleep 2
done
echo "PostgreSQL is ready"

# Create database if it doesn't exist
if ! psql -h postgres -U taler -tc "SELECT 1 FROM pg_database WHERE datname = 'libeufin_bank'" 2>/dev/null | grep -q 1; then
    echo "Creating libeufin_bank database..."
    psql -h postgres -U taler -c "CREATE DATABASE libeufin_bank;" 2>/dev/null || echo "Database may already exist"
fi

# Initialize database schema
echo "Initializing libeufin-bank database..."
libeufin-bank dbinit -c /etc/libeufin/bank.conf || {
    echo "DB init may have already been done"
}

# Create admin account if password is provided
if [ -n "$LIBEUFIN_BANK_ADMIN_PASSWORD" ]; then
    echo "Setting up admin account..."
    libeufin-bank passwd -c /etc/libeufin/bank.conf admin "$LIBEUFIN_BANK_ADMIN_PASSWORD" 2>/dev/null || echo "Admin account may already exist"
fi

# exchange: BE71096123456769
# wallet: FI1410093000123458
# merchant: DE75512108001245126199

# Create exchange account for Taler integration
# This account is used by the Taler exchange to interact with the bank
echo "Setting up exchange account..."
libeufin-bank create-account \
    -c /etc/libeufin/bank.conf \
    --username exchange --password asdasdasd \
    --name "PSP" --exchange \
    --payto_uri payto://iban/BE71096123456769 

# Create a default user account for testing wallet
echo "Setting up test user account..."
libeufin-bank create-account \
    -c /etc/libeufin/bank.conf \
    --username wallet --password asdasdasd \
    --name "Wallet Test User"  \
    --payto_uri payto://iban/FI1410093000123458 

libeufin-bank create-account \
    -c /etc/libeufin/bank.conf \
    --username merchant --password asdasdasd \
    --name "Merchant Test User"  \
    --payto_uri payto://iban/DE75512108001245126199 

# Start the server
echo "Starting libeufin-bank server..."
exec libeufin-bank serve -c /etc/libeufin/bank.conf -L INFO
