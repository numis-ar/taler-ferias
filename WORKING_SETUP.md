# Taler Payment System - Working Setup ✅

## Status: FULLY OPERATIONAL

This setup uses the **public Taler demo exchange** for a fully functional payment flow.

---

## 🚀 Quick Start

### System Status

```bash
cd /home/didi/code/taler-fullsystem
docker compose ps
```

Services:
- ✅ **PostgreSQL** (port 5432) - Database for merchant
- ✅ **Taler Merchant** (port 9966) - Backend with Web UI
- ✅ **Demo Frontend** (port 8080) - Product catalog interface

### Access the Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Demo Store | http://localhost:8080 | - |
| Merchant Web UI | http://localhost:9966/webui/ | admin / adminpassword |
| Merchant API | http://localhost:9966/ | Bearer secret-token:adminpassword |

---

## 💳 How to Test Payments

### Step 1: Install Taler Wallet
1. Go to https://wallet.demo.taler.net/
2. Install the browser extension for Firefox or Chrome

### Step 2: Get KUDOS (Test Currency)
1. Visit https://bank.demo.taler.net/
2. Login with any username/password (demo account)
3. Withdraw KUDOS to your wallet

### Step 3: Create an Order

**Option A: Via Web UI**
1. Go to http://localhost:9966/webui/
2. Login with: **admin** / **adminpassword**
3. Navigate to "Orders" → "Create Order"
4. Fill in:
   - Amount: `KUDOS:5.00`
   - Summary: `Digital Book`
   - Fulfillment URL: `http://localhost:8080/success`
5. Click "Create"

**Option B: Via API**
```bash
curl -X POST http://localhost:9966/private/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret-token:adminpassword" \
  -d '{"order": {
    "amount": "KUDOS:5.00",
    "summary": "Test Order",
    "fulfillment_url": "http://localhost:8080/success"
  }}'
```

### Step 4: Pay with Taler
1. Click the "Pay" button on the order
2. The Taler Wallet popup should appear
3. Confirm the payment
4. Payment is complete! 🎉

---

## 🏗️ Architecture

```
Your Store (localhost)          Public Demo
├─ Frontend: port 8080          └─ Exchange: exchange.demo.taler.net
├─ Merchant: port 9966          └─ Bank: bank.demo.taler.net
└─ Database: PostgreSQL         
```

---

## 📁 Configuration Files

### Merchant Configuration
**File:** `merchant-demo.conf`

```ini
[taler]
CURRENCY = KUDOS

[merchant]
SERVE = tcp
PORT = 9966
DATABASE = postgres

[merchantdb-postgres]
CONFIG = postgres://taler:talerpassword@postgres:5432/taler_merchant

[merchant-exchange-demo]
EXCHANGE_BASE_URL = https://exchange.demo.taler.net/
CURRENCY = KUDOS
MASTER_KEY = F80MFRG8HVH6R9CQ47KRFQSJP3T6DBJ4K1D9B703RJY3Z39TBMJ0
```

---

## 🔧 Useful Commands

```bash
# View logs
docker compose logs -f taler-merchant
docker compose logs -f taler-postgres

# Restart services
docker compose restart taler-merchant
docker compose restart demo-frontend

# Stop everything
docker compose down

# Start everything
docker compose up -d
```

---

## ✅ What's Working

1. **Merchant Backend**: Fully operational
   - Database initialized
   - Admin user created (admin/adminpassword)
   - Bank account configured
   - Connected to demo exchange
   - Order creation API working

2. **Web UI**: Accessible at http://localhost:9966/webui/
   - Create orders
   - Manage products
   - View payment history
   - Configure instances

3. **Payment Flow**: End-to-end working
   - Order creation via API and Web UI
   - Taler wallet integration
   - Payment processing
   - Fulfillment handling

4. **Demo Frontend**: Product showcase at http://localhost:8080/
   - Setup instructions
   - Product catalog
   - Links to merchant UI

---

## 🧪 API Examples

### Create Order
```bash
curl -X POST http://localhost:9966/private/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret-token:adminpassword" \
  -d '{"order": {
    "amount": "KUDOS:5.00",
    "summary": "Digital Book",
    "fulfillment_url": "http://localhost:8080/success"
  }}'
```

Response:
```json
{
  "order_id": "2026.034-038ANBZCCZANE",
  "token": "37T00VN6EQP019SG9FWQAG0BR8"
}
```

### Get Order Status
```bash
curl http://localhost:9966/private/orders/2026.034-038ANBZCCZANE \
  -H "Authorization: Bearer secret-token:adminpassword"
```

Response:
```json
{
  "taler_pay_uri": "taler+http://pay/localhost:9966/...",
  "order_status_url": "http://localhost:9966/orders/...",
  "order_status": "unpaid",
  "total_amount": "KUDOS:5",
  "summary": "Test Order"
}
```

---

## 🎯 Next Steps

You can now:
1. **Test payments** using the demo exchange
2. **Integrate** the payment flow into your application
3. **Experiment** with different order configurations
4. **Study** the Taler protocol and APIs

---

## 📚 Resources

- [Taler Documentation](https://docs.taler.net/)
- [Demo Exchange](https://exchange.demo.taler.net/)
- [Demo Bank](https://bank.demo.taler.net/)
- [Taler Wallet](https://wallet.demo.taler.net/)

---

## 🎉 Summary

This setup provides a **fully functional Taler payment system** using:
- Local merchant backend (your store)
- Public demo exchange (handles payments)
- Demo bank (provides test currency)

No local exchange complexity required - payments work out of the box!

**Login Credentials:**
- Username: `admin`
- Password: `adminpassword`
