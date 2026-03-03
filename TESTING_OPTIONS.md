# Testing Taler Payment Flow - Options

## Current Setup Status

Your Taler PoC is running with:
- ✅ PostgreSQL Database
- ✅ Merchant Backend (with admin account)
- ✅ Demo Frontend
- ⚠️  Local Exchange (incomplete setup)

## Testing Options

### Option 1: Public Demo (Easiest - 5 minutes)

Use your merchant backend with the public Taler demo infrastructure:

1. **Get Test Money:**
   - Visit: https://bank.demo.taler.net/
   - Create account, withdraw KUDOS

2. **Install Wallet:**
   - Browser: https://wallet.taler.net/
   - Or CLI: `sudo apt install taler-wallet-cli`

3. **Create Order:**
   - http://localhost:9966/webui/
   - Login: admin / adminpassword
   - Orders → + → Amount: 5.00 KUDOS

4. **Pay:**
   - Open order URL
   - Wallet opens → Click Pay
   - Done!

**Pros:** Works immediately, no complex setup  
**Cons:** Requires internet, KYC may apply for large amounts

---

### Option 2: Complete Local Setup (Complex - hours)

Finish configuring the local exchange:

1. Add wire accounts to exchange.conf
2. Start security modules (taler-exchange-secmod-*)  
3. Create Terms of Service and Privacy Policy files
4. Configure coin denominations
5. Set up auditor

See LOCAL_EXCHANGE_SETUP.md for details.

**Pros:** Fully offline, no KYC  
**Cons:** Complex setup, beyond PoC scope

---

### Option 3: Use Taler's Built-in Test Tools

Taler includes testing tools:

```bash
# Install test harness
sudo apt install taler-harness

# Run integration tests
taler-harness check
```

**Pros:** Tests all components  
**Cons:** Not a user-facing flow

---

## Recommendation

For a quick demonstration of Taler:

1. Use **Option 1** (Public Demo) to show a working payment flow
2. Use your local merchant backend to show merchant operations
3. Explain that a production setup would use Option 2

This gives you a complete demo without days of configuration!
