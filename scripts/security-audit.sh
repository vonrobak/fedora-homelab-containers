#!/bin/bash
# security-audit.sh
# Homelab Security Audit Script
#
# Purpose: Validate security configuration across the homelab
# Run: ./scripts/security-audit.sh
#
# Exit codes: 0 = all pass, 1 = warnings, 2 = failures
#
# Status: ACTIVE
# Updated: 2025-11-28

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
WARN=0
FAIL=0

pass() { echo -e "${GREEN}✅ PASS:${NC} $1"; ((PASS++)) || true; }
warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; ((WARN++)) || true; }
fail() { echo -e "${RED}❌ FAIL:${NC} $1"; ((FAIL++)) || true; }
info() { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}         HOMELAB SECURITY AUDIT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Check 1: SELinux status (most important)
# ============================================================================
echo "[1] Checking SELinux..."
if getenforce 2>/dev/null | grep -q "Enforcing"; then
    pass "SELinux enforcing"
else
    fail "SELinux not enforcing"
fi

# ============================================================================
# Check 2: Rootless containers
# ============================================================================
echo "[2] Checking rootless containers..."
# Check if any container is running as root inside (with timeout)
ROOT_CONTAINERS=$(timeout 10 bash -c '
    podman ps --format "{{.Names}}" 2>/dev/null | while read -r name; do
        USER=$(podman inspect "$name" --format "{{.Config.User}}" 2>/dev/null || echo "")
        if [ "$USER" = "root" ] || [ "$USER" = "0" ]; then
            echo "$name"
        fi
    done
' 2>/dev/null | grep -v "^$" || true)

if [ -z "$ROOT_CONTAINERS" ]; then
    pass "All containers rootless"
else
    warn "Containers running as root: $ROOT_CONTAINERS"
fi

# ============================================================================
# Check 3: CrowdSec health
# ============================================================================
echo "[3] Checking CrowdSec security..."
if systemctl --user is-active crowdsec.service &>/dev/null; then
    # Check CAPI connection (with timeout)
    CAPI_STATUS=$(timeout 10 podman exec crowdsec cscli capi status 2>&1 | grep -c "successfully interact" || echo "0")
    if [ "$CAPI_STATUS" -gt 0 ]; then
        pass "CrowdSec active, CAPI connected"
    else
        warn "CrowdSec running but CAPI disconnected"
    fi
else
    fail "CrowdSec not running"
fi

# ============================================================================
# Check 4: TLS certificates
# ============================================================================
echo "[4] Checking TLS certificates..."
# Check certificate expiry via Traefik's stored certs (with timeout)
CERT_DAYS=$(timeout 10 podman exec traefik cat /letsencrypt/acme.json 2>/dev/null | \
    jq -r '.letsencrypt.Certificates[0].certificate' 2>/dev/null | \
    base64 -d 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | \
    cut -d= -f2 || echo "")

if [ -n "$CERT_DAYS" ]; then
    EXPIRY_EPOCH=$(date -d "$CERT_DAYS" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    if [ "$DAYS_LEFT" -gt 30 ]; then
        pass "TLS certificates valid ($DAYS_LEFT days remaining)"
    elif [ "$DAYS_LEFT" -gt 7 ]; then
        warn "TLS certificates expiring soon ($DAYS_LEFT days)"
    else
        fail "TLS certificates critical ($DAYS_LEFT days)"
    fi
else
    warn "Could not verify TLS certificates"
fi

# ============================================================================
# Check 5: Rate limiting
# ============================================================================
echo "[5] Checking rate limiting..."
if grep -q "rateLimit\|rateLimitAverage" ~/containers/config/traefik/dynamic/*.yml 2>/dev/null; then
    pass "Rate limiting configured"
else
    warn "No rate limiting found"
fi

# ============================================================================
# Check 6: Authentication middleware
# ============================================================================
echo "[6] Checking authentication..."
# Check that Authelia is running
if systemctl --user is-active authelia.service &>/dev/null; then
    pass "Authelia SSO running"
else
    fail "Authelia not running"
fi

# ============================================================================
# Check 7: Firewall ports
# ============================================================================
echo "[7] Checking firewall..."
# Use ss instead of sudo firewall-cmd
LISTENING_PORTS=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | grep -oE '[0-9]+$' | sort -u)
UNEXPECTED=""
for port in $LISTENING_PORTS; do
    # Expected ports: 80, 443, high ports for container networking, local services
    if [ "$port" -lt 1024 ] && [ "$port" != "80" ] && [ "$port" != "443" ]; then
        UNEXPECTED="$UNEXPECTED $port"
    fi
done
if [ -z "$UNEXPECTED" ]; then
    pass "Only expected low ports (80, 443)"
else
    warn "Unexpected low ports:$UNEXPECTED"
fi

# ============================================================================
# Check 8: Secret files permissions
# ============================================================================
echo "[8] Checking secret file permissions..."
BAD_PERMS=""
shopt -s nullglob globstar 2>/dev/null || true
for secret in ~/containers/secrets/* ~/containers/config/**/secret*; do
    if [ -f "$secret" ]; then
        PERMS=$(stat -c %a "$secret" 2>/dev/null || echo "")
        if [ -n "$PERMS" ] && [ "$PERMS" != "600" ] && [ "$PERMS" != "400" ]; then
            BAD_PERMS="$BAD_PERMS $(basename "$secret"):$PERMS"
        fi
    fi
done
shopt -u nullglob globstar 2>/dev/null || true
if [ -z "$BAD_PERMS" ]; then
    pass "Secret files have restrictive permissions"
else
    warn "Loose permissions on:$BAD_PERMS"
fi

# ============================================================================
# Check 9: Security headers
# ============================================================================
echo "[9] Checking security headers..."
if grep -q "X-Frame-Options\|Content-Security-Policy" ~/containers/config/traefik/dynamic/*.yml 2>/dev/null; then
    pass "Security headers configured"
else
    warn "Security headers not found"
fi

# ============================================================================
# Check 10: Container resource limits
# ============================================================================
echo "[10] Checking container resource limits..."
NO_LIMITS=$(timeout 10 bash -c '
    count=0
    podman ps --format "{{.Names}}" 2>/dev/null | while read -r name; do
        MEM=$(podman inspect "$name" --format "{{.HostConfig.Memory}}" 2>/dev/null || echo "0")
        if [ "$MEM" = "0" ]; then
            echo -n "$name "
            count=$((count + 1))
            [ $count -ge 5 ] && break
        fi
    done
' 2>/dev/null || true)

if [ -z "$NO_LIMITS" ]; then
    pass "All containers have memory limits"
else
    warn "No memory limits: ${NO_LIMITS:0:50}..."
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✅ Passed:${NC}  $PASS"
echo -e "  ${YELLOW}⚠️  Warnings:${NC} $WARN"
echo -e "  ${RED}❌ Failed:${NC}  $FAIL"
echo ""

# Exit code
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Security audit: FAILED${NC}"
    exit 2
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}Security audit: WARNINGS${NC}"
    exit 1
else
    echo -e "${GREEN}Security audit: PASSED${NC}"
    exit 0
fi
