#!/usr/bin/env python3
"""
Simple proxy to create Taler orders without exposing credentials to frontend.
This proxy handles authentication with the merchant backend internally.
"""

import http.server
import socketserver
import json
import urllib.request
import urllib.error
import ssl

# Configuration
MERCHANT_URL = "http://localhost:9966"
MERCHANT_TOKEN = "adminpassword"  # Internal only, not exposed to frontend
PORT = 8888

class OrderProxyHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Custom logging
        print(f"[PROXY] {format % args}")
    
    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_POST(self):
        """Handle order creation"""
        if self.path != '/create-order':
            self.send_error(404, "Not Found")
            return
        
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        
        try:
            order_data = json.loads(body)
            print(f"[PROXY] Creating order: {order_data}")
            
            # Forward to merchant backend with authentication
            merchant_payload = {
                "order": {
                    "amount": f"{order_data['amount']}:KUDOS",
                    "summary": order_data['summary'],
                    "fulfillment_url": order_data.get('fulfillment_url', 'http://localhost:8080'),
                    "products": [{
                        "description": order_data.get('description', order_data['summary']),
                        "quantity": 1,
                        "price": f"{order_data['amount']}:KUDOS"
                    }]
                }
            }
            
            # Make request to merchant backend
            req = urllib.request.Request(
                f"{MERCHANT_URL}/private/orders",
                data=json.dumps(merchant_payload).encode('utf-8'),
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {MERCHANT_TOKEN}'
                },
                method='POST'
            )
            
            try:
                with urllib.request.urlopen(req) as response:
                    response_data = json.loads(response.read().decode('utf-8'))
                    print(f"[PROXY] Order created: {response_data}")
                    
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(json.dumps(response_data).encode('utf-8'))
                    
            except urllib.error.HTTPError as e:
                error_data = json.loads(e.read().decode('utf-8'))
                print(f"[PROXY] Error from merchant: {error_data}")
                
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps(error_data).encode('utf-8'))
                
        except json.JSONDecodeError as e:
            print(f"[PROXY] JSON decode error: {e}")
            self.send_error(400, "Bad Request: Invalid JSON")
        except Exception as e:
            print(f"[PROXY] Error: {e}")
            self.send_error(500, f"Internal Server Error: {e}")
    
    def do_GET(self):
        """Health check"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode('utf-8'))
        else:
            self.send_error(404, "Not Found")

if __name__ == '__main__':
    print(f"Starting Order Proxy on port {PORT}")
    print(f"Proxying to: {MERCHANT_URL}")
    print(f"Test with: curl -X POST http://localhost:{PORT}/create-order -H 'Content-Type: application/json' -d '{{\"amount\":\"5.00\",\"summary\":\"Test\"}}'")
    
    with socketserver.TCPServer(("", PORT), OrderProxyHandler) as httpd:
        print(f"\nProxy server running at http://localhost:{PORT}/")
        httpd.serve_forever()
