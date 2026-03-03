# Taler Exchange Setup - Debug Status

## Current State (as of 2026-02-03)

### ✅ Successfully Completed

1. **Database Setup**
   - PostgreSQL running with `taler_exchange` database
   - All 74 exchange tables created in the `exchange` schema
   - Schema patches applied (exchange-0001 through exchange-0006)

2. **Master Key Generation**
   - Ed25519 master key pair generated using gnunet-ecc
   - Public key: `Q3MXEJZDXU62KRNCTH5QA57FXSNGI47EISGF2IO63TMLZKGFJUUQ`
   - Private key stored in `/var/lib/taler-exchange/offline-keys/master.key`
   - Config updated with correct master public key

3. **Security Modules**
   - EDDSA security module running and generating keys
   - RSA security module running
   - CS (Clausen-Shacham) security module running
   - All modules synchronized with exchange HTTPD

4. **Wire Account Setup**
   - Wire account added to database: `payto://x-taler-bank/localhost:8082/exchange`
   - Signature created using Ed25519 over SHA-512 hash
   - Database has proper schema and constraints

5. **Configuration**
   - Full taler.conf generated with:
     - 6 coin denominations (KUDOS 0.01 to 10)
     - Zero fees for all operations
     - KYC disabled
     - Local wire method configured

### ⚠️  Blocking Issue: Wire Account Signature Validation

**Error:** `Database has wire account with invalid signature. Skipping entry. Did the exchange offline public key change?`

**Root Cause:** The signature format I'm creating doesn't match what Taler expects. Taler uses a specific signing protocol for wire accounts that involves:
- A specific data serialization format
- Possibly a signature purpose prefix/byte
- The exact same signing algorithm used by `taler-exchange-offline`

**What I've Tried:**
1. Signing the raw payto_uri string
2. Signing payto_uri with null terminator
3. Signing concatenated fields (payto_uri + conversion_url + debit_restrictions + credit_restrictions)
4. Signing SHA-512 hash of the concatenated fields
5. Using PyNaCl Ed25519 signing (compatible with Taler's libgcrypt)

All attempts result in "invalid signature" errors.

### 🔧 Next Steps to Fix

**Option 1: Use taler-exchange-offline (Recommended)**
The proper way to sign wire accounts is using the `taler-exchange-offline` tool with the master private key. This tool knows the exact format required.

Commands needed:
```bash
# Sign wire account using offline tool
taler-exchange-offline -c /etc/taler/taler.conf wire sign \
  --payto payto://x-taler-bank/localhost:8082/exchange \
  --master-key /var/lib/taler-exchange/offline-keys/master.key
```

**Option 2: Study Taler Source Code**
The exact signature format is defined in the Taler source code. Looking at:
- `src/exchange-tools/taler-exchange-offline.c` 
- `src/lib/exchange_api_wire.c`
- Wire account signature structure definition

**Option 3: Use Public Demo Exchange**
For a working PoC quickly, use the public Taler demo exchange instead of the local one.

### 📊 System Status

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Demo Frontend  │────▶│ Merchant Backend │────▶│   PostgreSQL    │
│  (Port 8080)    │     │  (Port 9966)     │     │  (Merchant DB)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │ Taler Exchange   │
                    │  (Port 8081)     │
                    │  ⚠️  Needs wire  │
                    │     signature    │
                    └──────────────────┘
```

### 🚀 Recommendation

Given the complexity of the offline signature requirement, I recommend:

1. **For immediate testing:** Use the public Taler demo infrastructure
   - Merchant backend is fully working
   - Connect to demo exchange at https://exchange.demo.taler.net/
   - No signature complexity

2. **For full offline setup:** Would require:
   - Studying the Taler source code for exact signature format
   - OR using taler-exchange-offline tool properly
   - OR using a pre-configured exchange database dump

The merchant backend, frontend, and database are all working correctly. The only blocker is the exchange wire account signature validation.
