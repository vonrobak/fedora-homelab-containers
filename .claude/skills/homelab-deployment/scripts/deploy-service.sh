#!/usr/bin/env bash
# Service deployment orchestrator
# Handles systemd operations, health checks, and service coordination

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WAIT_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_INTERVAL=5
PROMETHEUS_RESTART_NEEDED=false

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

usage() {
    cat << 'USAGE'
Usage: deploy-service.sh [OPTIONS]

Options:
  --service NAME          Service name (required)
  --wait-for-healthy      Wait for health check to pass
  --skip-health-check     Skip health check validation
  --reload-prometheus     Restart Prometheus after deployment
  --timeout SECONDS       Health check timeout (default: 300)
  --help                  Show this help message

Examples:
  # Basic deployment
  deploy-service.sh --service jellyfin

  # Deployment with health check
  deploy-service.sh --service jellyfin --wait-for-healthy

  # Deployment with Prometheus reload
  deploy-service.sh --service vaultwarden --wait-for-healthy --reload-prometheus

USAGE
    exit 0
}

# Parse arguments
SERVICE_NAME=""
WAIT_FOR_HEALTHY=false
SKIP_HEALTH_CHECK=false
RELOAD_PROMETHEUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --service) SERVICE_NAME="$2"; shift 2 ;;
        --wait-for-healthy) WAIT_FOR_HEALTHY=true; shift ;;
        --skip-health-check) SKIP_HEALTH_CHECK=true; shift ;;
        --reload-prometheus) RELOAD_PROMETHEUS=true; shift ;;
        --timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Service name required"
    usage
fi

echo ""
echo "========================================"
echo "Deploying: $SERVICE_NAME"
echo "========================================"
echo ""

# Step 1: Reload systemd daemon
log_info "Reloading systemd daemon..."
if systemctl --user daemon-reload; then
    log_success "Systemd daemon reloaded"
else
    log_error "Failed to reload systemd daemon"
    exit 1
fi

# Step 2: Enable service for persistence
log_info "Enabling service for auto-start..."
if systemctl --user enable "${SERVICE_NAME}.service" 2>/dev/null; then
    log_success "Service enabled: ${SERVICE_NAME}.service"
else
    log_warn "Service enable failed (may already be enabled)"
fi

# Step 3: Start service
log_info "Starting service..."
START_TIME=$(date +%s)

if systemctl --user start "${SERVICE_NAME}.service"; then
    log_success "Service started: ${SERVICE_NAME}.service"
else
    log_error "Failed to start service"
    echo ""
    echo "Check status with:"
    echo "  systemctl --user status ${SERVICE_NAME}.service"
    echo "  journalctl --user -u ${SERVICE_NAME}.service -n 50"
    exit 1
fi

# Step 4: Wait for service to be active
log_info "Waiting for service to become active..."
ELAPSED=0
while [[ $ELAPSED -lt 30 ]]; do
    if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
        log_success "Service is active"
        break
    fi
    sleep 1
    ((ELAPSED++))
done

if ! systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    log_error "Service failed to become active"
    systemctl --user status "${SERVICE_NAME}.service" || true
    exit 1
fi

# Step 5: Health check (if requested)
if [[ "$WAIT_FOR_HEALTHY" == true && "$SKIP_HEALTH_CHECK" == false ]]; then
    log_info "Waiting for health check to pass (timeout: ${WAIT_TIMEOUT}s)..."
    
    HEALTH_ELAPSED=0
    HEALTH_PASSED=false
    
    while [[ $HEALTH_ELAPSED -lt $WAIT_TIMEOUT ]]; do
        # Check if service is still active
        if ! systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
            log_error "Service stopped unexpectedly"
            systemctl --user status "${SERVICE_NAME}.service" || true
            exit 1
        fi
        
        # Try health check
        if podman healthcheck run "$SERVICE_NAME" &>/dev/null; then
            HEALTH_PASSED=true
            log_success "Health check passed (${HEALTH_ELAPSED}s elapsed)"
            break
        fi
        
        # Progress indicator
        if [[ $((HEALTH_ELAPSED % 15)) -eq 0 && $HEALTH_ELAPSED -gt 0 ]]; then
            log_info "Still waiting... (${HEALTH_ELAPSED}s/${WAIT_TIMEOUT}s)"
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        ((HEALTH_ELAPSED+=HEALTH_CHECK_INTERVAL))
    done
    
    if [[ "$HEALTH_PASSED" == false ]]; then
        log_error "Health check did not pass within timeout"
        log_warn "Service is running but may not be fully healthy"
        echo ""
        echo "Check service logs:"
        echo "  journalctl --user -u ${SERVICE_NAME}.service -f"
        exit 1
    fi
elif [[ "$SKIP_HEALTH_CHECK" == true ]]; then
    log_warn "Health check skipped (--skip-health-check)"
else
    log_info "Health check not requested (use --wait-for-healthy to enable)"
fi

# Step 6: Check for Traefik integration
log_info "Checking Traefik integration..."
if podman ps --format '{{.Labels}}' --filter "name=^${SERVICE_NAME}$" 2>/dev/null | grep -q "traefik.enable=true"; then
    log_success "Traefik labels detected (auto-discovery enabled)"
    log_info "Traefik will discover this service automatically"
    echo "  Check Traefik dashboard: http://localhost:8080/dashboard/"
else
    log_info "No Traefik labels detected (internal service only)"
fi

# Step 7: Reload Prometheus (if requested)
if [[ "$RELOAD_PROMETHEUS" == true ]]; then
    log_info "Restarting Prometheus to reload configuration..."
    if systemctl --user restart prometheus.service 2>/dev/null; then
        log_success "Prometheus restarted"
        log_info "New scrape target will be active within 30s"
    else
        log_warn "Prometheus restart failed (may not be installed)"
    fi
fi

# Calculate deployment time
END_TIME=$(date +%s)
DEPLOY_TIME=$((END_TIME - START_TIME))

# Summary
echo ""
echo "========================================"
echo "Deployment Complete: $SERVICE_NAME"
echo "========================================"
echo ""
echo "Summary:"
echo "  Status: $(systemctl --user is-active ${SERVICE_NAME}.service)"
echo "  Deployment time: ${DEPLOY_TIME}s"
echo ""
echo "Next steps:"
echo "  1. Verify deployment:"
echo "     ./claude/skills/homelab-deployment/scripts/test-deployment.sh --service $SERVICE_NAME"
echo ""
echo "  2. Check service status:"
echo "     systemctl --user status ${SERVICE_NAME}.service"
echo ""
echo "  3. View logs:"
echo "     journalctl --user -u ${SERVICE_NAME}.service -f"
echo ""

if [[ "$WAIT_FOR_HEALTHY" == true ]]; then
    log_success "Deployment verified and healthy"
    exit 0
else
    log_warn "Deployment completed (health not verified)"
    exit 0
fi
