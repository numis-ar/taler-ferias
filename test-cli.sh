#!/bin/bash
# Test Taler payment flow using CLI tools

echo "=== Taler CLI Test Script ==="
echo ""

# Check if taler-wallet-cli is installed
if ! command -v taler-wallet-cli &> /dev/null; then
    echo "taler-wallet-cli not found. Install it with:"
    echo "  sudo apt install taler-wallet-cli"
    echo ""
    echo "Or use the browser extension wallet from https://wallet.taler.net/"
    exit 1
fi

echo "1. Checking wallet status..."
taler-wallet-cli status

echo ""
echo "2. Checking balance..."
taler-wallet-cli balance

echo ""
echo "3. To withdraw KUDOS, visit: https://bank.demo.taler.net/"
echo "   Then run: taler-wallet-cli withdraw"

echo ""
echo "4. Your merchant backend is at: http://localhost:9966/webui/"
echo "   Login: admin / qweqweqwe"

echo ""
echo "5. After creating an order, pay with:"
echo "   taler-wallet-cli pay <ORDER_URL>"
