#!/usr/bin/env bash
# Check system health before deployment
# Integrates with homelab-intel.sh for comprehensive health assessment
# Version: 2.0 (Session 3 enhancement)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
HEALTH_THRESHOLD_CRITICAL=70  # Block deployments below this
HEALTH_THRESHOLD_WARNING=85   # Warn but allow deployments
INTEL_SCRIPT="${HOME}/containers/scripts/homelab-intel.sh"
REPORT_DIR="${HOME}/containers/docs/99-reports"
DEPLOYMENT_LOG="${HOME}/containers/data/deployment-logs/health-scores.log"

# Flags
FORCE_DEPLOY=false
VERBOSE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_DEPLOY=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force       Force deployment even if health score is low"
            echo "  --verbose     Show detailed health information"
            echo "  --help        Show this help message"
            echo ""
            echo "Health Score Thresholds:"
            echo "  >= 85: Healthy (proceed automatically)"
            echo "  70-84: Warning (proceed with confirmation)"
            echo "  < 70: Critical (blocked unless --force)"
            exit 0
            ;;
    esac
done

echo -e "${BLUE}=== Pre-Deployment Health Assessment ===${NC}"
echo ""

##############################################################################
# Run homelab-intel.sh for comprehensive health check
##############################################################################

if [[ ! -x "$INTEL_SCRIPT" ]]; then
    echo -e "${YELLOW}⚠${NC} homelab-intel.sh not found, falling back to basic checks"
    INTEL_AVAILABLE=false
else
    INTEL_AVAILABLE=true
fi

if [[ "$INTEL_AVAILABLE" == "true" ]]; then
    echo "Running comprehensive system intelligence scan..."

    # Run homelab-intel.sh in quiet mode
    if [[ "$VERBOSE" == "true" ]]; then
        "$INTEL_SCRIPT"
        INTEL_EXIT_CODE=$?
    else
        "$INTEL_SCRIPT" --quiet >/dev/null 2>&1
        INTEL_EXIT_CODE=$?
    fi

    # Find the latest intelligence report
    LATEST_REPORT=$(ls -t "$REPORT_DIR"/intel-*.json 2>/dev/null | head -1)

    if [[ -z "$LATEST_REPORT" ]]; then
        echo -e "${RED}✗${NC} Failed to generate intelligence report"
        INTEL_AVAILABLE=false
    else
        # Parse JSON report (basic parsing without jq)
        HEALTH_SCORE=$(grep -o '"health_score":[0-9]*' "$LATEST_REPORT" | cut -d: -f2)
        CRITICAL_COUNT=$(grep -o '"critical":\[[^]]*\]' "$LATEST_REPORT" | grep -o '"code"' | wc -l)
        WARNING_COUNT=$(grep -o '"warnings":\[[^]]*\]' "$LATEST_REPORT" | grep -o '"code"' | wc -l)

        echo -e "${GREEN}✓${NC} System intelligence scan complete"
        echo ""
        echo "  Health Score: ${HEALTH_SCORE}/100"
        echo "  Critical Issues: ${CRITICAL_COUNT}"
        echo "  Warnings: ${WARNING_COUNT}"
        echo "  Full Report: ${LATEST_REPORT}"
        echo ""
    fi
fi

##############################################################################
# Fallback: Basic health checks if homelab-intel.sh unavailable
##############################################################################

if [[ "$INTEL_AVAILABLE" == "false" ]]; then
    echo "Running basic health checks..."
    echo ""

    BASIC_SCORE=100

    # Check 1: Disk space
    SYSTEM_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ $SYSTEM_USAGE -lt 75 ]]; then
        echo -e "${GREEN}✓${NC} System disk: ${SYSTEM_USAGE}% (healthy)"
    elif [[ $SYSTEM_USAGE -lt 85 ]]; then
        echo -e "${YELLOW}⚠${NC} System disk: ${SYSTEM_USAGE}% (getting full)"
        BASIC_SCORE=$((BASIC_SCORE - 10))
    else
        echo -e "${RED}✗${NC} System disk: ${SYSTEM_USAGE}% (critical!)"
        BASIC_SCORE=$((BASIC_SCORE - 30))
    fi

    # Check 2: Critical services
    CRITICAL_SERVICES=("traefik" "prometheus" "grafana")
    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl --user is-active "${service}.service" &>/dev/null; then
            echo -e "${GREEN}✓${NC} ${service}.service is running"
        else
            echo -e "${RED}✗${NC} ${service}.service is NOT running"
            BASIC_SCORE=$((BASIC_SCORE - 20))
        fi
    done

    # Check 3: Memory available
    MEM_AVAILABLE=$(free -g | awk 'NR==2 {print $7}')
    if [[ $MEM_AVAILABLE -gt 2 ]]; then
        echo -e "${GREEN}✓${NC} Available memory: ${MEM_AVAILABLE}GB (sufficient)"
    else
        echo -e "${YELLOW}⚠${NC} Available memory: ${MEM_AVAILABLE}GB (low)"
        BASIC_SCORE=$((BASIC_SCORE - 10))
    fi

    HEALTH_SCORE=$BASIC_SCORE
    echo ""
    echo "  Basic Health Score: ${HEALTH_SCORE}/100"
    echo ""
fi

##############################################################################
# Risk Assessment & Deployment Decision
##############################################################################

echo -e "${BLUE}=== Deployment Risk Assessment ===${NC}"
echo ""

# Calculate risk level
if [[ $HEALTH_SCORE -ge $HEALTH_THRESHOLD_WARNING ]]; then
    RISK_LEVEL="LOW"
    RISK_COLOR="${GREEN}"
    RECOMMENDATION="Proceed with deployment"
    SHOULD_BLOCK=false
elif [[ $HEALTH_SCORE -ge $HEALTH_THRESHOLD_CRITICAL ]]; then
    RISK_LEVEL="MEDIUM"
    RISK_COLOR="${YELLOW}"
    RECOMMENDATION="Proceed with caution - review issues first"
    SHOULD_BLOCK=false
else
    RISK_LEVEL="HIGH"
    RISK_COLOR="${RED}"
    RECOMMENDATION="Deployment NOT recommended - fix critical issues first"
    SHOULD_BLOCK=true
fi

echo "  Risk Level: ${RISK_COLOR}${RISK_LEVEL}${NC}"
echo "  Recommendation: ${RECOMMENDATION}"
echo ""

# Log health score for historical tracking
mkdir -p "$(dirname "$DEPLOYMENT_LOG")"
echo "$(date -Iseconds)|${HEALTH_SCORE}|${RISK_LEVEL}" >> "$DEPLOYMENT_LOG"

##############################################################################
# Display Critical Issues (if any)
##############################################################################

if [[ "$INTEL_AVAILABLE" == "true" ]] && [[ $CRITICAL_COUNT -gt 0 ]]; then
    echo -e "${RED}⚠ CRITICAL ISSUES DETECTED:${NC}"

    # Extract critical issues from JSON (basic parsing)
    grep -o '"critical":\[[^]]*\]' "$LATEST_REPORT" | \
        sed 's/"code":"\([^"]*\)","message":"\([^"]*\)","action":"\([^"]*\)"/\n  [\1] \2\n      → \3/g' | \
        grep -v "^\[" | head -20

    echo ""
fi

##############################################################################
# Deployment Decision
##############################################################################

if [[ "$SHOULD_BLOCK" == "true" ]] && [[ "$FORCE_DEPLOY" == "false" ]]; then
    echo -e "${RED}=== DEPLOYMENT BLOCKED ===${NC}"
    echo ""
    echo "Health score ${HEALTH_SCORE} is below critical threshold ${HEALTH_THRESHOLD_CRITICAL}."
    echo ""
    echo "Actions:"
    echo "  1. Review and fix critical issues above"
    echo "  2. Run: ~/containers/scripts/homelab-intel.sh"
    echo "  3. Or force deployment with: $0 --force"
    echo ""
    exit 2
elif [[ "$RISK_LEVEL" == "MEDIUM" ]]; then
    echo -e "${YELLOW}=== DEPLOYMENT WARNING ===${NC}"
    echo ""
    echo "Health score ${HEALTH_SCORE} indicates some issues."
    echo "Deployment will proceed, but monitor closely."
    echo ""
    exit 0
else
    echo -e "${GREEN}=== SYSTEM HEALTHY ===${NC}"
    echo ""
    echo "Health score ${HEALTH_SCORE} - System ready for deployment"
    echo ""
    exit 0
fi
