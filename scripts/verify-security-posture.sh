#!/usr/bin/env bash
# Verify security posture for a service
# Checks: CrowdSec, TLS, security headers, auth flow, rate limiting, direct exposure
# Part of Phase 2: Verification Infrastructure

set -euo pipefail

# Usage check
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 jellyfin"
    exit 1
fi

SERVICE="$1"
HOSTNAME="${SERVICE}.patriark.org"
EXIT_CODE=0

echo "========================================="
echo "Security Posture Verification: $SERVICE"
echo "========================================="
echo ""

# 1. CrowdSec middleware processing
echo -n "CrowdSec middleware: "
if curl -sf http://localhost:8080/metrics 2>/dev/null | grep -q "traefik_middleware_requests_total.*crowdsec"; then
    echo "✓ Active"
else
    echo "✗ NOT FOUND"
    EXIT_CODE=1
fi

# 2. TLS certificate validation
echo -n "TLS certificate: "
if timeout 5 bash -c "echo | openssl s_client -connect \"$HOSTNAME:443\" -servername \"$HOSTNAME\" 2>/dev/null | openssl x509 -noout -dates" > /dev/null 2>&1; then
    EXPIRY=$(timeout 5 bash -c "echo | openssl s_client -connect \"$HOSTNAME:443\" -servername \"$HOSTNAME\" 2>/dev/null | openssl x509 -noout -enddate" | cut -d= -f2)
    echo "✓ Valid (expires: $EXPIRY)"
else
    echo "✗ INVALID or unreachable"
    EXIT_CODE=1
fi

# 3. Security headers check
echo "Security headers:"
if HEADERS=$(timeout 10 curl -sI "https://$HOSTNAME" 2>/dev/null); then
    # X-Frame-Options
    if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
        echo "  ✓ X-Frame-Options present"
    else
        echo "  ✗ X-Frame-Options MISSING"
        EXIT_CODE=1
    fi

    # HSTS (Strict-Transport-Security)
    if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
        echo "  ✓ HSTS present"
    else
        echo "  ✗ HSTS MISSING"
        EXIT_CODE=1
    fi

    # CSP (Content-Security-Policy) - warning only for some services
    if echo "$HEADERS" | grep -qi "Content-Security-Policy"; then
        echo "  ✓ CSP present"
    else
        echo "  ⚠ CSP missing (may be expected for some services)"
    fi
else
    echo "  ✗ Could not fetch headers from https://$HOSTNAME"
    EXIT_CODE=1
fi

# 4. Authentication flow check
echo -n "Authentication: "
if REDIRECT=$(timeout 10 curl -sI "https://$HOSTNAME" 2>/dev/null | grep -i "location:" | awk '{print $2}' | tr -d '\r'); then
    if echo "$REDIRECT" | grep -q "auth.patriark.org"; then
        echo "✓ Redirects to Authelia"
    elif [[ -z "$REDIRECT" ]]; then
        echo "⚠ No redirect (public service or native auth)"
    else
        echo "⚠ Unexpected redirect: $REDIRECT"
    fi
else
    echo "⚠ Could not determine redirect behavior"
fi

# 5. Rate limiting check
echo -n "Rate limiting: "
if curl -sf http://localhost:8080/metrics 2>/dev/null | grep -q "traefik_middleware_requests_total.*rate-limit"; then
    echo "✓ Active"
else
    echo "⚠ Not detected in metrics"
fi

# 6. Direct exposure check (CRITICAL)
echo -n "Direct host exposure: "
if podman inspect "$SERVICE" --format '{{range $p, $conf := .HostConfig.PortBindings}}{{$p}}{{end}}' 2>/dev/null | grep -q "0.0.0.0"; then
    echo "✗ SECURITY VIOLATION: Service exposed directly to host!"
    echo "   Ports: $(podman inspect "$SERVICE" --format '{{range $p, $conf := .HostConfig.PortBindings}}{{$p}} {{end}}' 2>/dev/null)"
    EXIT_CODE=1
else
    echo "✓ No direct host exposure"
fi

echo ""
echo "========================================="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Security posture verification: PASSED ✓"
else
    echo "Security posture verification: FAILED ✗"
fi
echo "========================================="

exit $EXIT_CODE
