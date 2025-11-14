#!/usr/bin/env bash
# Pre-deployment validation
# Checks environment is ready for deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

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
}

# Parse arguments
SERVICE_NAME=""
IMAGE=""
NETWORKS=""
PORTS=""
CONFIG_DIR=""
DATA_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --service-name) SERVICE_NAME="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --networks) NETWORKS="$2"; shift 2 ;;
        --ports) PORTS="$2"; shift 2 ;;
        --config-dir) CONFIG_DIR="$2"; shift 2 ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "Pre-Deployment Validation: $SERVICE_NAME"
echo "=========================================="
echo ""

# Check 1: Image exists
echo "Checking image availability..."
if podman image exists "$IMAGE" 2>/dev/null || \
   podman pull "$IMAGE" &>/dev/null; then
    check_pass "Image exists or pulled successfully: $IMAGE"
else
    check_fail "Image not found: $IMAGE"
fi

# Check 2: Networks exist
echo ""
echo "Checking networks..."
IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS"
for network in "${NETWORK_ARRAY[@]}"; do
    if podman network exists "$network" 2>/dev/null; then
        check_pass "Network exists: $network"
    else
        check_fail "Network not found: $network"
        echo "  Create with: podman network create $network"
    fi
done

# Check 3: Ports available
echo ""
echo "Checking port availability..."
IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
for port in "${PORT_ARRAY[@]}"; do
    if ! ss -tulnp 2>/dev/null | grep -q ":$port "; then
        check_pass "Port available: $port"
    else
        check_fail "Port already in use: $port"
        echo "  In use by: $(ss -tulnp 2>/dev/null | grep ":$port " | awk '{print $6}')"
    fi
done

# Check 4: Directories
echo ""
echo "Checking directories..."
for dir in "$CONFIG_DIR" "$DATA_DIR"; do
    if [[ -d "$dir" ]]; then
        check_pass "Directory exists: $dir"
    else
        check_warn "Directory missing: $dir (will be created)"
        mkdir -p "$dir" 2>/dev/null && \
            check_pass "Created directory: $dir" || \
            check_fail "Failed to create: $dir"
    fi
done

# Check 5: Disk space
echo ""
echo "Checking disk space..."
SYSTEM_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $SYSTEM_USAGE -lt 80 ]]; then
    check_pass "System disk usage: ${SYSTEM_USAGE}%"
else
    check_fail "System disk critically full: ${SYSTEM_USAGE}%"
    echo "  Run cleanup before deploying"
fi

# Check 6: No conflicting service
echo ""
echo "Checking for conflicts..."
if podman ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    check_fail "Container already exists: $SERVICE_NAME"
    echo "  Remove with: podman rm $SERVICE_NAME"
elif systemctl --user list-units --all | grep -q "${SERVICE_NAME}.service"; then
    check_fail "Service already exists: ${SERVICE_NAME}.service"
    echo "  Check with: systemctl --user status ${SERVICE_NAME}.service"
else
    check_pass "No conflicting services found"
fi

# Check 7: SELinux
echo ""
echo "Checking security..."
SELINUX=$(getenforce 2>/dev/null || echo "Unknown")
if [[ "$SELINUX" == "Enforcing" ]]; then
    check_pass "SELinux enforcing (volume labels required)"
else
    check_warn "SELinux not enforcing: $SELINUX"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary:"
echo "  Passed: $CHECKS_PASSED"
echo "  Failed: $CHECKS_FAILED"
echo ""

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed. Ready to deploy.${NC}"
    exit 0
else
    echo -e "${RED}✗ $CHECKS_FAILED check(s) failed. Fix issues before deploying.${NC}"
    exit 1
fi
