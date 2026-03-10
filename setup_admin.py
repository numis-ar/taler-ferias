#!/usr/bin/env python3
"""Setup admin instance for Taler merchant"""
import secrets
import hashlib

# Generate keys
salt = secrets.token_bytes(32)
password = 'adminpassword'
auth_hash = hashlib.sha512(password.encode() + salt).digest()
priv_key = secrets.token_bytes(32)
pub_key = secrets.token_bytes(32)

salt_hex = salt.hex()
hash_hex = auth_hash.hex()
priv_hex = priv_key.hex()
pub_hex = pub_key.hex()

sql = f"""
INSERT INTO merchant.merchant_instances 
    (merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_wire_transfer_delay, default_pay_delay, default_refund_delay)
VALUES (
    decode('{pub_hex}', 'hex'),
    decode('{hash_hex}', 'hex'),
    decode('{salt_hex}', 'hex'),
    'admin',
    'Administrator',
    '{{"country": "XX", "city": "Test City", "zip": "12345"}}',
    '{{"country": "XX", "city": "Test City", "zip": "12345"}}',
    86400000000,
    3600000000,
    1296000000
) ON CONFLICT DO NOTHING;

INSERT INTO merchant.merchant_keys (merchant_priv, merchant_serial)
SELECT decode('{priv_hex}', 'hex'), merchant_serial
FROM merchant.merchant_instances 
WHERE merchant_id = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO merchant.merchant_accounts 
    (merchant_serial, h_wire, salt, payto_uri, active)
SELECT 
    merchant_serial,
    decode('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'hex'),
    decode('0123456789abcdef0123456789abcdef', 'hex'),
    'payto://x-taler-bank/localhost:8082/admin?receiver-name=Admin',
    true
FROM merchant.merchant_instances 
WHERE merchant_id = 'admin'
ON CONFLICT DO NOTHING;
"""

with open('/tmp/setup_admin.sql', 'w') as f:
    f.write(sql)

print('Admin setup SQL generated')
