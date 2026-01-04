#!/usr/bin/env bash
# Comprehensive deployment verification wrapper
# Orchestrates all verification checks for a deployed service
# Invoked by service-validator subagent
# Part of Phase 2: Verification Infrastructure

set -euo pipefail

# Usage check
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <service-name> [external-url] [expect-auth]"
    echo ""
    echo "Arguments:"
    echo "  service-name : Name of the service to verify (required)"
    echo "  external-url : External URL (e.g., https://jellyfin.patriark.org) (optional)"
    echo "  expect-auth  : Expect Authelia auth (true/false, default: true) (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 jellyfin https://jellyfin.patriark.org true"
    echo "  $0 postgres   # Internal service, no external URL"
    exit 1
fi

SERVICE="$1"
EXTERNAL_URL="${2:-}"
EXPECT_AUTH="${3:-true}"

# Verification results tracking
CRITICAL_FAILURES=0
WARNINGS=0
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Verification report file
REPORT_FILE="/tmp/verification-${SERVICE}-$(date +%s).txt"

echo "=========================================" | tee "$REPORT_FILE"
echo "Comprehensive Deployment Verification" | tee -a "$REPORT_FILE"
echo "=========================================" | tee -a "$REPORT_FILE"
echo "Service: $SERVICE" | tee -a "$REPORT_FILE"
echo "Timestamp: $(date -Iseconds)" | tee -a "$REPORT_FILE"
if [[ -n "$EXTERNAL_URL" ]]; then
    echo "External URL: $EXTERNAL_URL" | tee -a "$REPORT_FILE"
fi
echo "=========================================" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Phase 1: Service Health (existing test-deployment.sh)
echo "=== Phase 1: Basic Deployment Verification ===" | tee -a "$REPORT_FILE"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if [[ -f ~/.claude/skills/homelab-deployment/scripts/test-deployment.sh ]]; then
    TEST_ARGS="--service $SERVICE"
    if [[ -n "$EXTERNAL_URL" ]]; then
        TEST_ARGS="$TEST_ARGS --external-url $EXTERNAL_URL"
    fi
    if [[ "$EXPECT_AUTH" == "true" ]]; then
        TEST_ARGS="$TEST_ARGS --expect-auth"
    fi

    if eval "~/.claude/skills/homelab-deployment/scripts/test-deployment.sh $TEST_ARGS" >> "$REPORT_FILE" 2>&1; then
        echo "✓ Basic deployment checks passed" | tee -a "$REPORT_FILE"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "✗ Basic deployment checks FAILED" | tee -a "$REPORT_FILE"
        CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
    fi
else
    echo "⚠ test-deployment.sh not found, performing manual checks..." | tee -a "$REPORT_FILE"

    # Manual basic checks
    echo -n "  Systemd service: " | tee -a "$REPORT_FILE"
    if systemctl --user is-active --quiet "${SERVICE}.service"; then
        echo "✓ Active" | tee -a "$REPORT_FILE"
    else
        echo "✗ NOT ACTIVE" | tee -a "$REPORT_FILE"
        CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
    fi

    echo -n "  Container running: " | tee -a "$REPORT_FILE"
    if podman ps --filter "name=^${SERVICE}$" --format "{{.Status}}" | grep -q "Up"; then
        UPTIME=$(podman ps --filter "name=^${SERVICE}$" --format "{{.Status}}")
        echo "✓ $UPTIME" | tee -a "$REPORT_FILE"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "✗ NOT RUNNING" | tee -a "$REPORT_FILE"
        CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
    fi
fi

echo "" | tee -a "$REPORT_FILE"

# Phase 2: Security Posture (if external URL provided)
if [[ -n "$EXTERNAL_URL" ]]; then
    echo "=== Phase 2: Security Verification ===" | tee -a "$REPORT_FILE"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if ~/containers/scripts/verify-security-posture.sh "$SERVICE" >> "$REPORT_FILE" 2>&1; then
        echo "✓ Security posture verified" | tee -a "$REPORT_FILE"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "✗ Security posture verification FAILED" | tee -a "$REPORT_FILE"
        CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
    fi

    echo "" | tee -a "$REPORT_FILE"
fi

# Phase 3: Monitoring Integration
echo "=== Phase 3: Monitoring Verification ===" | tee -a "$REPORT_FILE"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if ~/containers/scripts/verify-monitoring.sh "$SERVICE" >> "$REPORT_FILE" 2>&1; then
    echo "✓ Monitoring integration verified" | tee -a "$REPORT_FILE"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    # Monitoring failures are warnings, not critical
    echo "⚠ Monitoring integration issues (acceptable if service doesn't expose metrics)" | tee -a "$REPORT_FILE"
    WARNINGS=$((WARNINGS + 1))
fi

echo "" | tee -a "$REPORT_FILE"

# Phase 4: Configuration Drift Detection
echo "=== Phase 4: Drift Detection ===" | tee -a "$REPORT_FILE"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if [[ -f ~/.claude/skills/homelab-deployment/scripts/check-drift.sh ]]; then
    if ~/.claude/skills/homelab-deployment/scripts/check-drift.sh "$SERVICE" >> "$REPORT_FILE" 2>&1; then
        echo "✓ No configuration drift detected" | tee -a "$REPORT_FILE"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "⚠ Configuration drift detected (review details above)" | tee -a "$REPORT_FILE"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "⚠ Drift detection script not found" | tee -a "$REPORT_FILE"
    WARNINGS=$((WARNINGS + 1))
fi

echo "" | tee -a "$REPORT_FILE"

# Phase 5: Overall System Health
echo "=== Phase 5: Overall Health Assessment ===" | tee -a "$REPORT_FILE"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if ~/containers/scripts/homelab-intel.sh --quiet >> "$REPORT_FILE" 2>&1; then
    echo "✓ System health check passed" | tee -a "$REPORT_FILE"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "⚠ System health issues detected" | tee -a "$REPORT_FILE"
    WARNINGS=$((WARNINGS + 1))
fi

echo "" | tee -a "$REPORT_FILE"

# Calculate confidence score
CONFIDENCE=100
CONFIDENCE=$((CONFIDENCE - (CRITICAL_FAILURES * 30)))
CONFIDENCE=$((CONFIDENCE - (WARNINGS * 5)))

# Ensure confidence doesn't go negative
if [[ $CONFIDENCE -lt 0 ]]; then
    CONFIDENCE=0
fi

# Final summary
echo "=========================================" | tee -a "$REPORT_FILE"
echo "Verification Summary" | tee -a "$REPORT_FILE"
echo "=========================================" | tee -a "$REPORT_FILE"
echo "Total checks: $TOTAL_CHECKS" | tee -a "$REPORT_FILE"
echo "Passed: $PASSED_CHECKS" | tee -a "$REPORT_FILE"
echo "Warnings: $WARNINGS" | tee -a "$REPORT_FILE"
echo "Critical failures: $CRITICAL_FAILURES" | tee -a "$REPORT_FILE"
echo "Confidence: ${CONFIDENCE}%" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Determine overall status
if [[ $CRITICAL_FAILURES -eq 0 ]] && [[ $CONFIDENCE -ge 90 ]]; then
    echo "Overall Status: VERIFIED ✓" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "Recommendation: Deployment successful" | tee -a "$REPORT_FILE"
    echo "  → Proceed to documentation" | tee -a "$REPORT_FILE"
    echo "  → Ready for git commit" | tee -a "$REPORT_FILE"
    echo "  → Monitor for 5 minutes to ensure stability" | tee -a "$REPORT_FILE"
    EXIT_CODE=0
elif [[ $CRITICAL_FAILURES -eq 0 ]] && [[ $CONFIDENCE -ge 70 ]]; then
    echo "Overall Status: VERIFIED with warnings ⚠" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "Recommendation: Review warnings" | tee -a "$REPORT_FILE"
    echo "  → Check if warnings are acceptable for this service type" | tee -a "$REPORT_FILE"
    echo "  → Document warnings in deployment journal" | tee -a "$REPORT_FILE"
    echo "  → Proceed with caution" | tee -a "$REPORT_FILE"
    EXIT_CODE=0
else
    echo "Overall Status: FAILED ✗" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "Recommendation: Investigate failures" | tee -a "$REPORT_FILE"
    echo "  → Review detailed output above" | tee -a "$REPORT_FILE"
    echo "  → Check logs: journalctl --user -u ${SERVICE}.service -n 50" | tee -a "$REPORT_FILE"
    echo "  → Invoke systematic-debugging skill for root cause analysis" | tee -a "$REPORT_FILE"
    echo "  → Consider rollback if post-deployment" | tee -a "$REPORT_FILE"
    EXIT_CODE=1
fi

echo "=========================================" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
echo "Full report saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"

# Display report location for user reference
echo ""
echo "Verification complete. Full report:"
cat "$REPORT_FILE"

exit $EXIT_CODE
