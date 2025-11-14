#!/usr/bin/env bash
# Post-deployment verification
# Validates service is working correctly

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNED++))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

usage() {
    cat << 'USAGE'
Usage: test-deployment.sh [OPTIONS]

Options:
  --service NAME           Service name (required)
  --internal-port PORT     Internal port to test (e.g., 8096)
  --external-url URL       External URL to test (e.g., https://jellyfin.patriark.org)
  --expect-auth            Expect Authelia authentication redirect
  --skip-prometheus        Skip Prometheus target check
  --help                   Show this help message

Examples:
  # Basic service test
  test-deployment.sh --service jellyfin

  # Full test with external access
  test-deployment.sh --service jellyfin \
    --internal-port 8096 \
    --external-url https://jellyfin.patriark.org \
    --expect-auth

  # Internal service test
  test-deployment.sh --service redis-authelia --skip-prometheus

USAGE
    exit 0
}

# Parse arguments
SERVICE_NAME=""
INTERNAL_PORT=""
EXTERNAL_URL=""
EXPECT_AUTH=false
SKIP_PROMETHEUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --service) SERVICE_NAME="$2"; shift 2 ;;
        --internal-port) INTERNAL_PORT="$2"; shift 2 ;;
        --external-url) EXTERNAL_URL="$2"; shift 2 ;;
        --expect-auth) EXPECT_AUTH=true; shift ;;
        --skip-prometheus) SKIP_PROMETHEUS=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$SERVICE_NAME" ]]; then
    log_info "Service name required"
    usage
fi

echo ""
echo "========================================"
echo "Verifying Deployment: $SERVICE_NAME"
echo "========================================"
echo ""

# Test 1: Systemd service status
echo "Test 1: Systemd Service"
echo "------------------------"
if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    check_pass "Service is active"
    
    # Get service details
    UPTIME=$(systemctl --user show "${SERVICE_NAME}.service" --property=ActiveEnterTimestamp --value)
    log_info "Started: $UPTIME"
else
    check_fail "Service is not active"
    systemctl --user status "${SERVICE_NAME}.service" || true
fi
echo ""

# Test 2: Container status
echo "Test 2: Container Status"
echo "------------------------"
if podman ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    check_pass "Container is running"
    
    # Get container status
    CONTAINER_STATUS=$(podman inspect "$SERVICE_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
    CONTAINER_HEALTH=$(podman inspect "$SERVICE_NAME" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
    
    log_info "Status: $CONTAINER_STATUS"
    if [[ "$CONTAINER_HEALTH" != "none" && "$CONTAINER_HEALTH" != "" ]]; then
        if [[ "$CONTAINER_HEALTH" == "healthy" ]]; then
            check_pass "Health: $CONTAINER_HEALTH"
        else
            check_warn "Health: $CONTAINER_HEALTH"
        fi
    fi
else
    check_fail "Container is not running"
fi
echo ""

# Test 3: Health check
echo "Test 3: Health Check"
echo "--------------------"
if podman inspect "$SERVICE_NAME" --format '{{.Config.Healthcheck}}' 2>/dev/null | grep -q "Cmd"; then
    if podman healthcheck run "$SERVICE_NAME" &>/dev/null; then
        check_pass "Health check passed"
    else
        check_fail "Health check failed"
        log_info "Run manually: podman healthcheck run $SERVICE_NAME"
    fi
else
    check_warn "No health check configured"
fi
echo ""

# Test 4: Internal endpoint (if port specified)
if [[ -n "$INTERNAL_PORT" ]]; then
    echo "Test 4: Internal Endpoint"
    echo "-------------------------"
    
    # Check port is listening
    if ss -tulnp 2>/dev/null | grep -q ":${INTERNAL_PORT} "; then
        check_pass "Port $INTERNAL_PORT is listening"
    else
        check_warn "Port $INTERNAL_PORT not found in netstat"
    fi
    
    # Try HTTP request
    if curl -sf -m 5 "http://localhost:${INTERNAL_PORT}/" >/dev/null 2>&1; then
        check_pass "HTTP request to localhost:$INTERNAL_PORT succeeded"
    elif curl -sf -m 5 "http://localhost:${INTERNAL_PORT}/health" >/dev/null 2>&1; then
        check_pass "HTTP request to localhost:$INTERNAL_PORT/health succeeded"
    else
        check_warn "HTTP request to localhost:$INTERNAL_PORT failed (may require authentication)"
    fi
    echo ""
fi

# Test 5: External URL (if specified)
if [[ -n "$EXTERNAL_URL" ]]; then
    echo "Test 5: External URL"
    echo "--------------------"
    
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$EXTERNAL_URL" 2>/dev/null || echo "000")
    
    if [[ "$EXPECT_AUTH" == true ]]; then
        # Expect redirect to Authelia
        if [[ "$HTTP_CODE" == "302" || "$HTTP_CODE" == "303" || "$HTTP_CODE" == "307" ]]; then
            check_pass "External URL responds with redirect (HTTP $HTTP_CODE)"
            
            # Check if redirect is to Authelia
            REDIRECT_LOCATION=$(curl -s -I -m 10 "$EXTERNAL_URL" 2>/dev/null | grep -i "^location:" | cut -d' ' -f2 | tr -d '\r')
            if echo "$REDIRECT_LOCATION" | grep -q "sso\."; then
                check_pass "Redirect points to Authelia SSO"
            else
                check_warn "Redirect location: $REDIRECT_LOCATION"
            fi
        elif [[ "$HTTP_CODE" == "200" ]]; then
            check_warn "External URL responds OK (expected auth redirect)"
        else
            check_fail "External URL error (HTTP $HTTP_CODE)"
        fi
    else
        # Expect direct access
        if [[ "$HTTP_CODE" == "200" ]]; then
            check_pass "External URL responds OK (HTTP $HTTP_CODE)"
        elif [[ "$HTTP_CODE" == "302" || "$HTTP_CODE" == "303" || "$HTTP_CODE" == "307" ]]; then
            check_warn "External URL redirects (HTTP $HTTP_CODE, expected 200)"
        else
            check_fail "External URL error (HTTP $HTTP_CODE)"
        fi
    fi
    echo ""
fi

# Test 6: Traefik integration
echo "Test 6: Traefik Integration"
echo "---------------------------"
if podman ps --format '{{.Labels}}' --filter "name=^${SERVICE_NAME}$" 2>/dev/null | grep -q "traefik.enable=true"; then
    check_pass "Traefik labels present"
    
    # Extract hostname from labels
    TRAEFIK_HOST=$(podman inspect "$SERVICE_NAME" --format '{{index .Config.Labels "traefik.http.routers.'${SERVICE_NAME}'.rule"}}' 2>/dev/null || echo "")
    if [[ -n "$TRAEFIK_HOST" ]]; then
        log_info "Traefik route: $TRAEFIK_HOST"
    fi
    
    log_info "Check Traefik dashboard: http://localhost:8080/dashboard/"
else
    check_warn "No Traefik integration (internal service only)"
fi
echo ""

# Test 7: Prometheus monitoring (if not skipped)
if [[ "$SKIP_PROMETHEUS" == false ]]; then
    echo "Test 7: Prometheus Monitoring"
    echo "------------------------------"
    
    # Check if Prometheus is running
    if systemctl --user is-active --quiet prometheus.service 2>/dev/null; then
        # Check if service has metrics endpoint label
        METRICS_PATH=$(podman inspect "$SERVICE_NAME" --format '{{index .Config.Labels "prometheus.io.path"}}' 2>/dev/null || echo "")
        METRICS_PORT=$(podman inspect "$SERVICE_NAME" --format '{{index .Config.Labels "prometheus.io.port"}}' 2>/dev/null || echo "")
        
        if [[ -n "$METRICS_PATH" || -n "$METRICS_PORT" ]]; then
            check_pass "Prometheus labels detected"
            [[ -n "$METRICS_PATH" ]] && log_info "Metrics path: $METRICS_PATH"
            [[ -n "$METRICS_PORT" ]] && log_info "Metrics port: $METRICS_PORT"
        else
            check_warn "No Prometheus labels (metrics may not be scraped)"
        fi
        
        log_info "Check targets: http://localhost:9090/targets"
    else
        check_warn "Prometheus not running"
    fi
else
    log_info "Prometheus check skipped (--skip-prometheus)"
fi
echo ""

# Test 8: Logs check
echo "Test 8: Service Logs"
echo "--------------------"
RECENT_ERRORS=$(journalctl --user -u "${SERVICE_NAME}.service" --since "5 minutes ago" -p err --no-pager -q 2>/dev/null | wc -l)

if [[ $RECENT_ERRORS -eq 0 ]]; then
    check_pass "No errors in recent logs"
else
    check_warn "Found $RECENT_ERRORS error(s) in recent logs"
    log_info "View logs: journalctl --user -u ${SERVICE_NAME}.service -n 50"
fi
echo ""

# Summary
echo "========================================"
echo "Verification Summary"
echo "========================================"
echo ""
echo "Results:"
echo "  ✓ Passed:  $CHECKS_PASSED"
echo "  ⚠ Warned:  $CHECKS_WARNED"
echo "  ✗ Failed:  $CHECKS_FAILED"
echo ""

if [[ $CHECKS_FAILED -eq 0 && $CHECKS_WARNED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed! Deployment is healthy.${NC}"
    exit 0
elif [[ $CHECKS_FAILED -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Deployment successful with warnings.${NC}"
    echo "Review warnings above and verify service functionality."
    exit 0
else
    echo -e "${RED}✗ Deployment verification failed.${NC}"
    echo "Fix issues above before considering deployment complete."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check service logs:"
    echo "     journalctl --user -u ${SERVICE_NAME}.service -n 50"
    echo ""
    echo "  2. Check container logs:"
    echo "     podman logs $SERVICE_NAME --tail 50"
    echo ""
    echo "  3. Use systematic-debugging skill for deeper analysis"
    exit 1
fi
