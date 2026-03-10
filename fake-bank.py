#!/usr/bin/env python3
"""
Taler Fakebank - Simple bank simulator for Taler testing
Provides Flask-based API and Web UI
"""

import os
import sys
import json
from flask import Flask, request, jsonify, render_template_string

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

# HTML Template for the web UI
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Taler Fakebank</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            text-align: center;
        }
        .header h1 { margin: 0 0 10px 0; font-size: 2em; }
        .header p { margin: 0; opacity: 0.9; }
        .card {
            background: white;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .card h2 {
            margin: 0 0 20px 0;
            color: #333;
            font-size: 1.3em;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid #eee;
        }
        th {
            color: #666;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85em;
            letter-spacing: 0.5px;
        }
        tr:hover { background: #f8f9fa; }
        .balance {
            font-weight: 600;
            color: #28a745;
            font-family: monospace;
            font-size: 1.1em;
        }
        .account-name {
            color: #333;
            font-weight: 500;
        }
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: 500;
        }
        .badge-exchange { background: #e3f2fd; color: #1976d2; }
        .badge-merchant { background: #f3e5f5; color: #7b1fa2; }
        .badge-demo { background: #e8f5e9; color: #388e3c; }
        .badge-admin { background: #fff3e0; color: #f57c00; }
        .info-box {
            background: #e3f2fd;
            border-left: 4px solid #2196f3;
            padding: 15px;
            border-radius: 4px;
            margin-top: 20px;
        }
        .info-box h3 { margin: 0 0 10px 0; color: #1976d2; }
        .info-box code {
            background: rgba(0,0,0,0.05);
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
        .info-box ul { margin: 10px 0; padding-left: 20px; }
        .info-box li { margin: 5px 0; }
        .transaction {
            padding: 10px;
            border-bottom: 1px solid #eee;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .transaction:last-child { border-bottom: none; }
        .tx-from { color: #666; }
        .tx-to { color: #666; }
        .tx-amount {
            font-weight: 600;
            color: #28a745;
            font-family: monospace;
        }
        .no-tx {
            color: #999;
            text-align: center;
            padding: 20px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🏦 Taler Fakebank</h1>
        <p>Demo Banking System for Taler Payments</p>
    </div>
    
    <div class="card">
        <h2>💳 Accounts</h2>
        <table>
            <thead>
                <tr>
                    <th>Account</th>
                    <th>Type</th>
                    <th>Balance</th>
                </tr>
            </thead>
            <tbody>
                {% for username, account in accounts.items() %}
                <tr>
                    <td>
                        <span class="account-name">{{ account.name }}</span><br>
                        <small style="color: #999;">@{{ username }}</small>
                    </td>
                    <td>
                        <span class="badge badge-{{ username }}">{{ username }}</span>
                    </td>
                    <td class="balance">{{ "%.2f"|format(account.balance) }} {{ currency }}</td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
    
    <div class="card">
        <h2>📋 Recent Transactions</h2>
        {% if transactions %}
            {% for tx in transactions %}
            <div class="transaction">
                <span class="tx-from">{{ tx.from }} → {{ tx.to }}</span>
                <span class="tx-amount">{{ "%.2f"|format(tx.amount) }} {{ currency }}</span>
            </div>
            {% endfor %}
        {% else %}
            <div class="no-tx">No transactions yet</div>
        {% endif %}
    </div>
    
    <div class="info-box">
        <h3>ℹ️ About</h3>
        <p>This is a <strong>fake bank</strong> for testing Taler payments.</p>
        <ul>
            <li><strong>Exchange</strong> account holds reserves for coin issuance</li>
            <li><strong>Merchant</strong> account receives payments from customers</li>
            <li><strong>Demo</strong> account is for testing customer operations</li>
        </ul>
        <p><strong>API Endpoint:</strong> <code>/accounts</code>, <code>/accounts/{username}/balance</code></p>
    </div>
</body>
</html>
'''

@app.route('/healthz')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'})

@app.route('/')
def index():
    """Root endpoint - returns HTML UI or JSON based on Accept header"""
    # Check if browser wants HTML
    accept = request.headers.get('Accept', '')
    if 'text/html' in accept or request.args.get('format') == 'html':
        return render_template_string(HTML_TEMPLATE, 
                                      accounts=accounts, 
                                      transactions=transactions[-10:],  # Last 10
                                      currency=CURRENCY)
    # Default to JSON API
    return jsonify({
        'name': 'Taler Fakebank',
        'currency': CURRENCY,
        'version': '1.0',
        'accounts': list(accounts.keys()),
        'ui_url': request.url_root + '?format=html'
    })

@app.route('/ui')
def ui():
    """Explicit UI endpoint"""
    return render_template_string(HTML_TEMPLATE, 
                                  accounts=accounts, 
                                  transactions=transactions[-10:],
                                  currency=CURRENCY)

@app.route('/accounts', methods=['GET'])
def list_accounts():
    """List all accounts"""
    accept = request.headers.get('Accept', '')
    if 'text/html' in accept:
        return render_template_string(HTML_TEMPLATE,
                                      accounts=accounts,
                                      transactions=transactions[-10:],
                                      currency=CURRENCY)
    return jsonify({
        'accounts': [
            {'username': k, 'name': v['name'], 'balance': v['balance']}
            for k, v in accounts.items()
        ]
    })

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
    user_txns = [t for t in transactions if t.get('from') == username or t.get('to') == username]
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
    print(f"Web UI: http://localhost:{BANK_PORT}/")
    app.run(host='0.0.0.0', port=BANK_PORT, threaded=True)
