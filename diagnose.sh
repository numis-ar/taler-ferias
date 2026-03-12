#!/bin/bash
# diagnose.sh - Check nginx configuration and routing

echo "=== Nginx Configuration Diagnosis ==="
echo ""

echo "--- Active Sites (sites-enabled) ---"
ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "No sites-enabled directory"
echo ""

echo "--- All Site Configs (sites-available) ---"
ls -la /etc/nginx/sites-available/ 2>/dev/null | grep taler || echo "No taler configs found"
echo ""

for conf in /etc/nginx/sites-available/taler-*; do
    if [ -f "$conf" ]; then
        echo "=== Content of $conf ==="
        cat "$conf"
        echo ""
    fi
done

echo "--- Nginx Test ---"
nginx -t 2>&1
echo ""

echo "--- Listening Ports ---"
ss -tlnp | grep -E "(:80|:443)" || netstat -tlnp 2>/dev/null | grep -E "(:80|:443)" || echo "Could not check ports"
echo ""

echo "--- Docker Container Ports ---"
docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null || echo "Docker not available"
echo ""

echo "=== Test Local Requests ==="
echo "Testing localhost:30858 (should be frontend):"
curl -s -o /dev/null -w "%{http_code}" http://localhost:30858 2>/dev/null || echo "Failed"
echo ""

echo "Testing localhost:30861 (should be bank):"
curl -s -o /dev/null -w "%{http_code}" http://localhost:30861 2>/dev/null || echo "Failed"
echo ""
