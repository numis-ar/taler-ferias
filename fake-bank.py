#!/usr/bin/env python3
"""
Taler Fakebank - Simple bank simulator for Taler testing
Provides Flask-based API matching Taler wire gateway expectations
"""

import os
import sys
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

BANK_PORT = int(os.environ.get('BANK_PORT', 8082))
CURRENCY = os.environ.get('BANK_CURRENCY', 'KUDOS')

# Simple in-memory account storage
accounts = {
    'admin': {'password': 'bankadmin', 'balance': 1000000.00, 'name': 'Bank Admin'},
    'exchange': {'password': 'exchange_password', 'balance': 100000.00, 'name': 'Taler Exchange'},
    'merchant': {'password': 'merchant_password', 'balance': 0.00, 'name': 'Taler Merchant'},
    'demo': {'password': 'demo_password', 'balance': 500.00, 'name': 'Demo User'}
}

transactions = []

@app.route('/healthz')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'})

@app.route('/')
def index():
    """Root endpoint"""
    return jsonify({
        'name': 'Taler Fakebank',
        'currency': CURRENCY,
        'version': '1.0',
        'accounts': list(accounts.keys())
    })

@app.route('/accounts', methods=['GET'])
def list_accounts():
    """List all accounts"""
    return jsonify({
        'accounts': [
            {'username': k, 'name': v['name'], 'balance': v['balance']}
            for k, v in accounts.items()
        ]
    })

@app.route('/accounts', methods=['POST'])
def create_account():
    """Create a new account"""
    data = request.get_json() or {}
    username = data.get('username')
    if not username:
        return jsonify({'error': 'Username required'}), 400
    if username in accounts:
        return jsonify({'error': 'Account exists'}), 409
    
    accounts[username] = {
        'password': data.get('password', 'password'),
        'balance': 0.00,
        'name': data.get('name', username)
    }
    return jsonify({'status': 'created', 'username': username}), 201

@app.route('/accounts/<username>/balance', methods=['GET'])
def get_balance(username):
    """Get account balance"""
    if username not in accounts:
        return jsonify({'error': 'Account not found'}), 404
    return jsonify({
        'username': username,
        'balance': accounts[username]['balance'],
        'currency': CURRENCY
    })

@app.route('/accounts/<username>/transactions', methods=['GET'])
def get_transactions(username):
    """Get account transactions"""
    if username not in accounts:
        return jsonify({'error': 'Account not found'}), 404
    user_txns = [t for t in transactions if t['from'] == username or t['to'] == username]
    return jsonify({'transactions': user_txns})

@app.route('/accounts/<username>/transactions', methods=['POST'])
def create_transaction(username):
    """Create a transaction"""
    if username not in accounts:
        return jsonify({'error': 'Account not found'}), 404
    
    data = request.get_json() or {}
    amount = float(data.get('amount', 0))
    to_account = data.get('to') or data.get('payto_uri', '').split('/')[-1]
    subject = data.get('subject', '')
    
    if not to_account or to_account not in accounts:
        return jsonify({'error': 'Invalid destination'}), 400
    if amount <= 0:
        return jsonify({'error': 'Invalid amount'}), 400
    if accounts[username]['balance'] < amount:
        return jsonify({'error': 'Insufficient funds'}), 400
    
    # Execute transfer
    accounts[username]['balance'] -= amount
    accounts[to_account]['balance'] += amount
    
    txn = {
        'id': len(transactions) + 1,
        'from': username,
        'to': to_account,
        'amount': amount,
        'subject': subject,
        'currency': CURRENCY
    }
    transactions.append(txn)
    
    return jsonify({'status': 'completed', 'transaction': txn}), 201

# Taler-specific endpoints
@app.route('/taler-bank-integration/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def taler_integration(path):
    """Handle Taler bank integration API calls"""
    return jsonify({'status': 'ok', 'path': path})

@app.route('/taler-wire-gateway/<path:path>', methods=['GET', 'POST'])
def taler_wire_gateway(path):
    """Taler wire gateway endpoint"""
    if request.method == 'POST':
        data = request.get_json() or {}
        return jsonify({
            'status': 'confirmed',
            'row_id': len(transactions) + 1,
            'timestamp': {'t_s': 0}
        })
    return jsonify({'transactions': []})

# Legacy endpoints for compatibility
@app.route('/transfer', methods=['POST'])
def transfer():
    """Legacy transfer endpoint"""
    data = request.get_json() or {}
    transfer_id = f"transfer_{len(transactions)}"
    return jsonify({
        'transfer_id': transfer_id,
        'timestamp': '2024-01-01T00:00:00Z',
        'status': 'confirmed'
    })

@app.route('/admin/add-incoming', methods=['POST'])
def add_incoming():
    """Add incoming funds (for testing)"""
    data = request.get_json() or {}
    account = data.get('account', 'admin')
    amount = float(data.get('amount', 0))
    if account in accounts:
        accounts[account]['balance'] += amount
        return jsonify({'status': 'ok', 'new_balance': accounts[account]['balance']})
    return jsonify({'error': 'Account not found'}), 404

if __name__ == '__main__':
    print(f"Starting Taler Fakebank on port {BANK_PORT}")
    print(f"Accounts: {list(accounts.keys())}")
    app.run(host='0.0.0.0', port=BANK_PORT, threaded=True)
