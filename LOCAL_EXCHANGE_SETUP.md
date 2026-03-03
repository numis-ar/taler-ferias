# Setting Up a Complete Local Taler Exchange

To make the local exchange fully functional, you need:

## 1. Wire Account Configuration
Add to exchange.conf:
```
[exchange-wire-test]
TEST_RESPONSE_FILE = /var/lib/taler-exchange/wire.json
```

## 2. Security Modules
Start the security module daemons:
```bash
taler-exchange-secmod-eddsa -c /etc/taler/taler.conf &
taler-exchange-secmod-rsa -c /etc/taler/taler.conf &
taler-exchange-secmod-cs -c /etc/taler/taler.conf &
```

## 3. Terms of Service
Create TOS files:
```bash
mkdir -p /usr/share/taler-exchange/terms
echo "Terms of Service" > /usr/share/taler-exchange/terms/en.txt
```

## 4. Privacy Policy
```bash
mkdir -p /usr/share/taler-exchange/privacy
echo "Privacy Policy" > /usr/share/taler-exchange/privacy/en.txt
```

## 5. Denominations
Configure coin denominations in exchange.conf

## 6. Auditor Setup
Run: `taler-exchange-offline -c /etc/taler/taler.conf`

This is complex and beyond a minimal PoC. 
For testing, use the public demo infrastructure instead.
