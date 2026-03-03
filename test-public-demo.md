# Testing Taler with Public Demo Infrastructure

## Step 1: Get KUDOS from Demo Bank
1. Visit: https://bank.demo.taler.net/
2. Create a test account (any username/password)
3. Withdraw KUDOS to your Taler wallet

## Step 2: Install Taler Wallet
- Firefox/Chrome extension: https://wallet.taler.net/
- Or CLI: `apt install taler-wallet-cli`

## Step 3: Create an Order in Your Merchant
1. Visit: http://localhost:9966/webui/
2. Login: admin / adminpassword
3. Click "Orders" → "+"
4. Set:
   - Amount: 5.00
   - Currency: KUDOS
   - Summary: "Test Product"
5. Click "Create Order"
6. Copy the order URL

## Step 4: Customer Pays
1. Open the order URL in browser
2. Taler Wallet opens automatically
3. Click "Pay"
4. Payment completes instantly!

## Note on KYC
The public demo exchange may require KYC for larger amounts.
For small test amounts (< 10 KUDOS), it usually works without KYC.
