#!/usr/bin/env bash
# Verify autonomous operation outcome
# Ensures actions actually solved the problem (feedback loop for confidence learning)
# Part of Phase 2: Verification Infrastructure

set -euo pipefail

# Usage check
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <action-type> <before-state-json> [wait-time]"
    echo ""
    echo "Action types: disk-cleanup, service-restart, drift-reconciliation, resource-pressure"
    echo "Example: $0 disk-cleanup /tmp/before-state-123.json 30"
    exit 1
fi

ACTION_TYPE="$1"
BEFORE_STATE="$2"
AFTER_DELAY="${3:-30}"  # Default 30s wait for stabilization

EXIT_CODE=0

echo "==========================================="
echo "Autonomous Action Outcome Verification"
echo "==========================================="
echo "Action: $ACTION_TYPE"
echo "Waiting ${AFTER_DELAY}s for stabilization..."
sleep "$AFTER_DELAY"

# Capture after state
AFTER_STATE="/tmp/after-state-$(date +%s).json"
~/containers/scripts/homelab-intel.sh --quiet --json > "$AFTER_STATE" 2>/dev/null || {
    echo "✗ Failed to capture after state"
    exit 1
}

echo ""
echo "Comparing states..."
echo ""

# Verify based on action type
case "$ACTION_TYPE" in
    disk-cleanup)
        echo "=== Disk Cleanup Verification ==="

        # Extract disk usage before/after
        BEFORE_DISK=$(jq -r '.metrics.disk_usage_percent // 0' "$BEFORE_STATE" 2>/dev/null || echo "0")
        AFTER_DISK=$(jq -r '.metrics.disk_usage_percent // 0' "$AFTER_STATE" 2>/dev/null || echo "0")

        # Calculate freed space
        FREED=$(echo "$BEFORE_DISK - $AFTER_DISK" | bc -l 2>/dev/null || echo "0")

        echo "Disk usage: ${BEFORE_DISK}% → ${AFTER_DISK}% (freed: ${FREED}%)"

        # Check if meaningful cleanup occurred (>3% freed)
        if (( $(echo "$FREED > 3" | bc -l 2>/dev/null || echo "0") )); then
            echo "✓ VERIFIED: Disk cleanup freed significant space (${FREED}%)"
        elif (( $(echo "$FREED > 0" | bc -l 2>/dev/null || echo "0") )); then
            echo "⚠ WARNING: Disk cleanup freed minimal space (${FREED}%)"
            EXIT_CODE=1
        else
            echo "✗ FAILED: No disk space freed or disk usage increased"
            EXIT_CODE=1
        fi
        ;;

    service-restart)
        echo "=== Service Restart Verification ==="

        # Extract service name from before state
        SERVICE=$(jq -r '.service // ""' "$BEFORE_STATE" 2>/dev/null)

        if [[ -z "$SERVICE" ]]; then
            echo "✗ FAILED: Service name not found in before state"
            exit 1
        fi

        echo "Service: $SERVICE"

        # Check service is active
        if systemctl --user is-active --quiet "${SERVICE}.service"; then
            echo "✓ Service active"
        else
            echo "✗ Service NOT active after restart"
            EXIT_CODE=1
        fi

        # Check health check if available
        if podman healthcheck run "$SERVICE" &>/dev/null; then
            echo "✓ Health check passing"
        else
            echo "⚠ Health check not available or failing"
        fi

        # Check restart count (should be low - 0 or 1 after manual restart)
        RESTART_COUNT=$(podman inspect "$SERVICE" --format '{{.RestartCount}}' 2>/dev/null || echo "999")
        if [[ $RESTART_COUNT -le 1 ]]; then
            echo "✓ No crash loops (restart count: $RESTART_COUNT)"
        else
            echo "✗ Crash loop detected (restart count: $RESTART_COUNT)"
            EXIT_CODE=1
        fi

        # Check recent logs for errors
        if journalctl --user -u "${SERVICE}.service" --since "1 minute ago" -n 20 2>/dev/null | grep -qiE "(error|fatal|panic|failed)"; then
            echo "⚠ Errors detected in recent logs"
        else
            echo "✓ No errors in recent logs"
        fi

        if [[ $EXIT_CODE -eq 0 ]]; then
            echo "✓ VERIFIED: Service restart successful"
        else
            echo "✗ FAILED: Service restart did not resolve issue"
        fi
        ;;

    drift-reconciliation)
        echo "=== Drift Reconciliation Verification ==="

        # Extract service name
        SERVICE=$(jq -r '.service // ""' "$BEFORE_STATE" 2>/dev/null)

        if [[ -z "$SERVICE" ]]; then
            echo "✗ FAILED: Service name not found in before state"
            exit 1
        fi

        echo "Service: $SERVICE"

        # Check drift status after reconciliation
        if [[ -f ~/.claude/skills/homelab-deployment/scripts/check-drift.sh ]]; then
            DRIFT_STATUS=$(~/.claude/skills/homelab-deployment/scripts/check-drift.sh "$SERVICE" --json 2>/dev/null | jq -r '.status // "UNKNOWN"')

            echo "Drift status: $DRIFT_STATUS"

            if [[ "$DRIFT_STATUS" == "MATCH" ]]; then
                echo "✓ VERIFIED: Drift reconciled successfully"
            else
                echo "✗ FAILED: Drift still present ($DRIFT_STATUS)"
                EXIT_CODE=1
            fi
        else
            echo "⚠ Drift check script not found, cannot verify"
            EXIT_CODE=1
        fi
        ;;

    resource-pressure)
        echo "=== Resource Pressure Relief Verification ==="

        # Extract memory usage before/after
        BEFORE_MEM=$(jq -r '.metrics.memory_usage_percent // 0' "$BEFORE_STATE" 2>/dev/null || echo "0")
        AFTER_MEM=$(jq -r '.metrics.memory_usage_percent // 0' "$AFTER_STATE" 2>/dev/null || echo "0")

        # Calculate reduction
        REDUCTION=$(echo "$BEFORE_MEM - $AFTER_MEM" | bc -l 2>/dev/null || echo "0")

        echo "Memory usage: ${BEFORE_MEM}% → ${AFTER_MEM}% (reduced: ${REDUCTION}%)"

        # Check if meaningful reduction (>5%)
        if (( $(echo "$REDUCTION > 5" | bc -l 2>/dev/null || echo "0") )); then
            echo "✓ VERIFIED: Memory pressure relieved (${REDUCTION}%)"
        elif (( $(echo "$REDUCTION > 0" | bc -l 2>/dev/null || echo "0") )); then
            echo "⚠ WARNING: Memory pressure reduced minimally (${REDUCTION}%)"
            EXIT_CODE=1
        else
            echo "✗ FAILED: Memory pressure not reduced or increased"
            EXIT_CODE=1
        fi
        ;;

    predictive-maintenance)
        echo "=== Predictive Maintenance Verification ==="

        # Similar to disk-cleanup but more lenient thresholds
        BEFORE_DISK=$(jq -r '.metrics.disk_usage_percent // 0' "$BEFORE_STATE" 2>/dev/null || echo "0")
        AFTER_DISK=$(jq -r '.metrics.disk_usage_percent // 0' "$AFTER_STATE" 2>/dev/null || echo "0")
        FREED=$(echo "$BEFORE_DISK - $AFTER_DISK" | bc -l 2>/dev/null || echo "0")

        echo "Disk usage: ${BEFORE_DISK}% → ${AFTER_DISK}% (freed: ${FREED}%)"

        # Predictive maintenance can have lower threshold (>1%)
        if (( $(echo "$FREED > 1" | bc -l 2>/dev/null || echo "0") )); then
            echo "✓ VERIFIED: Predictive cleanup successful (${FREED}%)"
        else
            echo "⚠ WARNING: Minimal cleanup performed (${FREED}%)"
        fi
        ;;

    *)
        echo "⚠ Unknown action type: $ACTION_TYPE"
        echo "Cannot verify outcome automatically"
        echo ""
        echo "Before state: $BEFORE_STATE"
        echo "After state: $AFTER_STATE"
        echo ""
        echo "Manual verification required."
        exit 2
        ;;
esac

echo ""
echo "==========================================="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Outcome verification: PASSED ✓"
    echo "Confidence delta: +5%"
else
    echo "Outcome verification: FAILED ✗"
    echo "Confidence delta: -10%"
    echo "Rollback recommended"
fi
echo "==========================================="

# Cleanup after state (before state preserved for debugging)
rm -f "$AFTER_STATE"

exit $EXIT_CODE
