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

# Start the server
echo "Starting libeufin-bank server..."
exec libeufin-bank serve -c /etc/libeufin/bank.conf -L INFO
