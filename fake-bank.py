#!/usr/bin/env python3
"""
Minimal fake bank for Taler testing
Implements the Taler Wire Gateway API
"""

import http.server
import socketserver
import json
import urllib.parse

PORT = 8082

class FakeBankHandler(http.server.BaseHTTPRequestHandler):
    accounts = {
        "admin": {"balance": "1000.00", "currency": "KUDOS"}
    }
    transfers = []
    
    def log_message(self, format, *args):
        print(f"[FAKEBANK] {format % args}")
    
    def do_GET(self):
        """Handle GET requests"""
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        if path == "/" or path == "/health":
            self.send_json({"status": "ok", "bank": "fake", "currency": "KUDOS"})
        elif path.startswith("/accounts/"):
            account_id = path.split("/")[2]
            if account_id in self.accounts:
                self.send_json(self.accounts[account_id])
            else:
                self.send_error(404, "Account not found")
        else:
            self.send_error(404, "Not found")
    
    def do_POST(self):
        """Handle POST requests"""
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else '{}'
        
        try:
            data = json.loads(body) if body else {}
        except:
            data = {}
        
        if path == "/transfer":
            # Handle wire transfer request
            transfer_id = f"transfer_{len(self.transfers)}"
            self.transfers.append({
                "id": transfer_id,
                "amount": data.get("amount", "0"),
                "wire_transfer_subject": data.get("wire_transfer_subject", ""),
                "destination": data.get("destination_account", {})
            })
            self.send_json({
                "transfer_id": transfer_id,
                "timestamp": "2024-01-01T00:00:00Z",
                "status": "confirmed"
            })
        elif path == "/admin/add-incoming":
            # Add incoming transfer (for testing)
            account = data.get("account", "admin")
            amount = data.get("amount", "0")
            if account in self.accounts:
                current = float(self.accounts[account]["balance"])
                self.accounts[account]["balance"] = str(current + float(amount))
                self.send_json({"status": "ok", "new_balance": self.accounts[account]["balance"]})
            else:
                self.send_error(404, "Account not found")
        else:
            self.send_error(404, "Not found")
    
    def send_json(self, data):
        """Send JSON response"""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

if __name__ == '__main__':
    print(f"Starting Fake Bank on port {PORT}")
    print(f"Test with: curl http://localhost:{PORT}/")
    
    with socketserver.TCPServer(("", PORT), FakeBankHandler) as httpd:
        print(f"Fake Bank running at http://localhost:{PORT}/")
        httpd.serve_forever()
