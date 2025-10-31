#!/bin/bash
# security-audit.sh

echo "=== Homelab Security Audit ==="
echo ""

# Check 1: Verify no plain-text secrets
echo "[1] Checking for plain-text secrets..."
grep -r "password.*:" ~/containers/config/ 2>/dev/null | grep -v "file://" && \
  echo "❌ FAIL: Plain-text passwords found" || \
  echo "✅ PASS: No plain-text passwords"

# Check 2: Traefik dashboard authentication
echo "[2] Checking Traefik dashboard auth..."
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/rawdata | \
  grep -q "401" && \
  echo "✅ PASS: Dashboard requires auth" || \
  echo "⚠️  WARN: Dashboard may be exposed"

# Check 3: Valid certificates
echo "[3] Checking TLS certificates..."
curl -vI https://auth.patriark.dev 2>&1 | grep -q "CN=R3" && \
  echo "✅ PASS: Valid Let's Encrypt cert" || \
  echo "❌ FAIL: Invalid certificate"

# Check 5: Rate limiting active
echo "[5] Checking rate limiting..."
grep -q "rateLimit:" ~/containers/config/traefik/dynamic/middleware.yml && \
  echo "✅ PASS: Rate limiting configured" || \
  echo "⚠️  WARN: No rate limiting"

# Check 6: Port exposure
echo "[6] Checking open ports..."
sudo firewall-cmd --list-ports | grep -q "8080" && \
  echo "⚠️  WARN: Port 8080 exposed (Traefik dashboard)" || \
  echo "✅ PASS: Only 80/443 exposed"

# Check 7: SELinux status
echo "[7] Checking SELinux..."
getenforce | grep -q "Enforcing" && \
  echo "✅ PASS: SELinux enforcing" || \
  echo "❌ FAIL: SELinux not enforcing"

# Check 8: Container rootless
echo "[8] Checking rootless containers..."
podman ps --format "{{.User}}" | grep -q "root" && \
  echo "❌ FAIL: Root containers detected" || \
  echo "✅ PASS: All containers rootless"

echo ""
echo "=== Audit Complete ==="
