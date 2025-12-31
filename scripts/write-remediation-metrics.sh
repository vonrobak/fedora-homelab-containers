#!/bin/bash
# write-remediation-metrics.sh - Write remediation metrics to Prometheus textfile collector
# Part of Phase 3: Remediation Arsenal Advanced Features
# Usage: ./write-remediation-metrics.sh --playbook <name> --status <success|failure> --duration <seconds> [options]

set -euo pipefail

# Configuration
METRICS_FILE="$HOME/containers/data/backup-metrics/remediation.prom"
METRICS_HISTORY="$HOME/containers/.claude/remediation/metrics-history.json"

# Ensure history file exists
mkdir -p "$(dirname "$METRICS_HISTORY")"
[ -f "$METRICS_HISTORY" ] || echo '{"executions": []}' > "$METRICS_HISTORY"

# Parse arguments
PLAYBOOK=""
STATUS=""
DURATION=0
DISK_RECLAIMED=0
SERVICES_RESTARTED=""
OOM_DETECTED=0
ROOT_CAUSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --playbook) PLAYBOOK="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --disk-reclaimed) DISK_RECLAIMED="$2"; shift 2 ;;
        --services-restarted) SERVICES_RESTARTED="$2"; shift 2 ;;
        --oom-detected) OOM_DETECTED="$2"; shift 2 ;;
        --root-cause) ROOT_CAUSE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate required parameters
if [ -z "$PLAYBOOK" ] || [ -z "$STATUS" ]; then
    echo "Usage: $0 --playbook <name> --status <success|failure> --duration <seconds> [options]"
    exit 1
fi

# Convert status to numeric (1=success, 0=failure)
if [ "$STATUS" = "success" ]; then
    STATUS_NUM=1
else
    STATUS_NUM=0
fi

# Record execution in history
TIMESTAMP=$(date +%s)
EXECUTION_RECORD=$(jq -n \
    --arg playbook "$PLAYBOOK" \
    --arg status "$STATUS" \
    --argjson timestamp "$TIMESTAMP" \
    --argjson duration "$DURATION" \
    --argjson disk_reclaimed "$DISK_RECLAIMED" \
    --arg services "$SERVICES_RESTARTED" \
    --argjson oom "$OOM_DETECTED" \
    --arg root_cause "$ROOT_CAUSE" \
    '{
        playbook: $playbook,
        status: $status,
        timestamp: $timestamp,
        duration: $duration,
        disk_reclaimed: $disk_reclaimed,
        services_restarted: $services,
        oom_detected: $oom,
        root_cause: $root_cause
    }')

# Append to history (keep last 1000 executions)
jq --argjson exec "$EXECUTION_RECORD" \
    '.executions += [$exec] | .executions |= .[-1000:]' \
    "$METRICS_HISTORY" > "${METRICS_HISTORY}.tmp" && \
    mv "${METRICS_HISTORY}.tmp" "$METRICS_HISTORY"

# Read all historical data to compute aggregated metrics
ALL_PLAYBOOKS=("disk-cleanup" "drift-reconciliation" "service-restart" "resource-pressure" "predictive-maintenance" "self-healing-restart" "database-maintenance")

# Start building metrics file
cat > "$METRICS_FILE" << 'EOF'
# HELP remediation_playbook_executions_total Total number of remediation playbook executions by playbook and status
# TYPE remediation_playbook_executions_total counter
EOF

# Compute execution totals from history
for pb in "${ALL_PLAYBOOKS[@]}"; do
    SUCCESS_COUNT=$(jq --arg pb "$pb" '[.executions[] | select(.playbook == $pb and .status == "success")] | length' "$METRICS_HISTORY")
    FAILURE_COUNT=$(jq --arg pb "$pb" '[.executions[] | select(.playbook == $pb and .status == "failure")] | length' "$METRICS_HISTORY")

    echo "remediation_playbook_executions_total{playbook=\"$pb\",status=\"success\"} $SUCCESS_COUNT" >> "$METRICS_FILE"
    echo "remediation_playbook_executions_total{playbook=\"$pb\",status=\"failure\"} $FAILURE_COUNT" >> "$METRICS_FILE"
done

# Last execution timestamp per playbook
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_playbook_last_execution_timestamp Unix timestamp of last playbook execution
# TYPE remediation_playbook_last_execution_timestamp gauge
EOF

for pb in "${ALL_PLAYBOOKS[@]}"; do
    LAST_TS=$(jq --arg pb "$pb" '[.executions[] | select(.playbook == $pb)] | if length > 0 then .[-1].timestamp else 0 end' "$METRICS_HISTORY")
    echo "remediation_playbook_last_execution_timestamp{playbook=\"$pb\"} $LAST_TS" >> "$METRICS_FILE"
done

# Last execution status (1=success, 0=failure)
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_playbook_last_execution_success Whether last playbook execution succeeded (1) or failed (0)
# TYPE remediation_playbook_last_execution_success gauge
EOF

for pb in "${ALL_PLAYBOOKS[@]}"; do
    LAST_STATUS=$(jq --arg pb "$pb" '[.executions[] | select(.playbook == $pb)] | if length > 0 then (if .[-1].status == "success" then 1 else 0 end) else 0 end' "$METRICS_HISTORY")
    echo "remediation_playbook_last_execution_success{playbook=\"$pb\"} $LAST_STATUS" >> "$METRICS_FILE"
done

# Last execution duration
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_playbook_duration_seconds Duration of last playbook execution in seconds
# TYPE remediation_playbook_duration_seconds gauge
EOF

for pb in "${ALL_PLAYBOOKS[@]}"; do
    LAST_DURATION=$(jq --arg pb "$pb" '[.executions[] | select(.playbook == $pb)] | if length > 0 then .[-1].duration else 0 end' "$METRICS_HISTORY")
    echo "remediation_playbook_duration_seconds{playbook=\"$pb\"} $LAST_DURATION" >> "$METRICS_FILE"
done

# Disk space reclaimed (cumulative last 30 days)
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_disk_space_reclaimed_bytes_total Total disk space reclaimed by remediation playbooks (last 30 days)
# TYPE remediation_disk_space_reclaimed_bytes_total gauge
EOF

THIRTY_DAYS_AGO=$(($(date +%s) - 30*24*60*60))
for pb in "${ALL_PLAYBOOKS[@]}"; do
    TOTAL_RECLAIMED=$(jq --arg pb "$pb" --argjson cutoff "$THIRTY_DAYS_AGO" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff) | .disk_reclaimed] | add // 0' \
        "$METRICS_HISTORY")
    echo "remediation_disk_space_reclaimed_bytes_total{playbook=\"$pb\"} $TOTAL_RECLAIMED" >> "$METRICS_FILE"
done

# OOM events detected
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_oom_events_detected_total Total OOM events detected during self-healing restarts
# TYPE remediation_oom_events_detected_total counter
EOF

# Get unique services that had OOM events
SERVICES_WITH_OOM=$(jq -r '[.executions[] | select(.oom_detected > 0) | .services_restarted] | unique | .[]' "$METRICS_HISTORY" | sort -u)
if [ -n "$SERVICES_WITH_OOM" ]; then
    while IFS= read -r svc; do
        OOM_COUNT=$(jq --arg svc "$svc" '[.executions[] | select(.services_restarted == $svc and .oom_detected > 0)] | length' "$METRICS_HISTORY")
        echo "remediation_oom_events_detected_total{service=\"$svc\"} $OOM_COUNT" >> "$METRICS_FILE"
    done <<< "$SERVICES_WITH_OOM"
else
    echo "# No OOM events detected" >> "$METRICS_FILE"
fi

# Services restarted (total count per service, last 30 days)
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_services_restarted_total Total number of service restarts by remediation (last 30 days)
# TYPE remediation_services_restarted_total counter
EOF

SERVICES_RESTARTED_LIST=$(jq -r --argjson cutoff "$THIRTY_DAYS_AGO" \
    '[.executions[] | select(.timestamp >= $cutoff and .services_restarted != "")] | map(.services_restarted) | unique | .[]' \
    "$METRICS_HISTORY" | sort -u)

if [ -n "$SERVICES_RESTARTED_LIST" ]; then
    while IFS= read -r svc; do
        RESTART_COUNT=$(jq --arg svc "$svc" --argjson cutoff "$THIRTY_DAYS_AGO" \
            '[.executions[] | select(.timestamp >= $cutoff and .services_restarted == $svc)] | length' \
            "$METRICS_HISTORY")
        echo "remediation_services_restarted_total{service=\"$svc\"} $RESTART_COUNT" >> "$METRICS_FILE"
    done <<< "$SERVICES_RESTARTED_LIST"
else
    echo "# No services restarted" >> "$METRICS_FILE"
fi

# Success rate per playbook (last 30 days)
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_playbook_success_rate Success rate of playbook executions (0.0-1.0) over last 30 days
# TYPE remediation_playbook_success_rate gauge
EOF

for pb in "${ALL_PLAYBOOKS[@]}"; do
    SUCCESS_30D=$(jq --arg pb "$pb" --argjson cutoff "$THIRTY_DAYS_AGO" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff and .status == "success")] | length' \
        "$METRICS_HISTORY")
    TOTAL_30D=$(jq --arg pb "$pb" --argjson cutoff "$THIRTY_DAYS_AGO" \
        '[.executions[] | select(.playbook == $pb and .timestamp >= $cutoff)] | length' \
        "$METRICS_HISTORY")

    if [ "$TOTAL_30D" -gt 0 ]; then
        SUCCESS_RATE=$(echo "scale=4; $SUCCESS_30D / $TOTAL_30D" | bc)
    else
        SUCCESS_RATE="0"
    fi

    echo "remediation_playbook_success_rate{playbook=\"$pb\"} $SUCCESS_RATE" >> "$METRICS_FILE"
done

# SLO Impact Metrics (Phase 4: SLO Integration)
# These track whether remediation actually improves user-facing SLO compliance
cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_slo_improvement_ratio SLO improvement after remediation (SLI after - SLI before)
# TYPE remediation_slo_improvement_ratio gauge
EOF

# Extract SLO improvement metrics from recent executions (last 30 days)
# These come from slo-violation-remediation playbook exports
SERVICES_WITH_SLO=$(jq -r --argjson cutoff "$THIRTY_DAYS_AGO" \
    '[.executions[] | select(.timestamp >= $cutoff and .sli_delta != null and .sli_delta != "")] | map(.services_restarted // .service) | unique | .[]' \
    "$METRICS_HISTORY" 2>/dev/null | sort -u)

if [ -n "$SERVICES_WITH_SLO" ]; then
    while IFS= read -r svc; do
        # Calculate average SLO improvement for this service (last execution)
        SLI_IMPROVEMENT=$(jq --arg svc "$svc" --argjson cutoff "$THIRTY_DAYS_AGO" \
            '[.executions[] | select(.timestamp >= $cutoff and (.services_restarted == $svc or .service == $svc) and .sli_delta != null and .sli_delta != "")] | map(.sli_delta | tonumber) | last // 0' \
            "$METRICS_HISTORY" 2>/dev/null)
        echo "remediation_slo_improvement_ratio{service=\"$svc\"} $SLI_IMPROVEMENT" >> "$METRICS_FILE"
    done <<< "$SERVICES_WITH_SLO"
else
    echo "# No SLO improvement data" >> "$METRICS_FILE"
fi

cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_burn_rate_delta Burn rate reduction after remediation (before - after, positive = improvement)
# TYPE remediation_burn_rate_delta gauge
EOF

# Track burn rate improvement
if [ -n "$SERVICES_WITH_SLO" ]; then
    while IFS= read -r svc; do
        BURN_REDUCTION=$(jq --arg svc "$svc" --argjson cutoff "$THIRTY_DAYS_AGO" \
            '[.executions[] | select(.timestamp >= $cutoff and (.services_restarted == $svc or .service == $svc) and .burn_delta != null and .burn_delta != "")] | map(.burn_delta | tonumber) | last // 0' \
            "$METRICS_HISTORY" 2>/dev/null)
        echo "remediation_burn_rate_delta{service=\"$svc\"} $BURN_REDUCTION" >> "$METRICS_FILE"
    done <<< "$SERVICES_WITH_SLO"
else
    echo "# No burn rate delta data" >> "$METRICS_FILE"
fi

cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_error_budget_saved_total Cumulative error budget saved by remediation (positive = saved, negative = consumed)
# TYPE remediation_error_budget_saved_total counter
EOF

# Calculate cumulative error budget impact (last 30 days)
if [ -n "$SERVICES_WITH_SLO" ]; then
    while IFS= read -r svc; do
        # Sum all budget deltas for this service
        BUDGET_SAVED=$(jq --arg svc "$svc" --argjson cutoff "$THIRTY_DAYS_AGO" \
            '[.executions[] | select(.timestamp >= $cutoff and (.services_restarted == $svc or .service == $svc) and .budget_delta != null and .budget_delta != "")] | map(.budget_delta | tonumber) | add // 0' \
            "$METRICS_HISTORY" 2>/dev/null)
        echo "remediation_error_budget_saved_total{service=\"$svc\"} $BUDGET_SAVED" >> "$METRICS_FILE"
    done <<< "$SERVICES_WITH_SLO"
else
    echo "# No error budget data" >> "$METRICS_FILE"
fi

# ==============================================================================
# CHAIN METRICS (Phase 5: Multi-Playbook Chaining)
# ==============================================================================

CHAIN_METRICS_HISTORY="$HOME/containers/.claude/remediation/chain-metrics-history.jsonl"

if [ -f "$CHAIN_METRICS_HISTORY" ]; then
    cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_chain_executions_total Total number of chain executions by chain and status
# TYPE remediation_chain_executions_total counter
EOF

    # Get unique chain names
    CHAINS=$(jq -r '.chain' "$CHAIN_METRICS_HISTORY" 2>/dev/null | sort -u)

    if [ -n "$CHAINS" ]; then
        while IFS= read -r chain; do
            SUCCESS_COUNT=$(jq --arg chain "$chain" 'select(.chain == $chain and .status == "success")' "$CHAIN_METRICS_HISTORY" 2>/dev/null | wc -l)
            FAILED_COUNT=$(jq --arg chain "$chain" 'select(.chain == $chain and .status == "failed")' "$CHAIN_METRICS_HISTORY" 2>/dev/null | wc -l)
            ABORTED_COUNT=$(jq --arg chain "$chain" 'select(.chain == $chain and .status == "aborted")' "$CHAIN_METRICS_HISTORY" 2>/dev/null | wc -l)

            echo "remediation_chain_executions_total{chain=\"$chain\",status=\"success\"} $SUCCESS_COUNT" >> "$METRICS_FILE"
            echo "remediation_chain_executions_total{chain=\"$chain\",status=\"failed\"} $FAILED_COUNT" >> "$METRICS_FILE"
            echo "remediation_chain_executions_total{chain=\"$chain\",status=\"aborted\"} $ABORTED_COUNT" >> "$METRICS_FILE"
        done <<< "$CHAINS"
    fi

    cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_chain_last_execution_timestamp Unix timestamp of last chain execution
# TYPE remediation_chain_last_execution_timestamp gauge
EOF

    if [ -n "$CHAINS" ]; then
        while IFS= read -r chain; do
            LAST_TS=$(jq -c --arg chain "$chain" 'select(.chain == $chain) | .timestamp' "$CHAIN_METRICS_HISTORY" 2>/dev/null | tail -1)
            if [ -n "$LAST_TS" ] && [ "$LAST_TS" != "null" ]; then
                echo "remediation_chain_last_execution_timestamp{chain=\"$chain\"} $LAST_TS" >> "$METRICS_FILE"
            else
                echo "remediation_chain_last_execution_timestamp{chain=\"$chain\"} 0" >> "$METRICS_FILE"
            fi
        done <<< "$CHAINS"
    fi

    cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_chain_duration_seconds Duration of last chain execution
# TYPE remediation_chain_duration_seconds gauge
EOF

    if [ -n "$CHAINS" ]; then
        while IFS= read -r chain; do
            LAST_DURATION=$(jq -c --arg chain "$chain" 'select(.chain == $chain) | .duration' "$CHAIN_METRICS_HISTORY" 2>/dev/null | tail -1)
            if [ -n "$LAST_DURATION" ] && [ "$LAST_DURATION" != "null" ]; then
                echo "remediation_chain_duration_seconds{chain=\"$chain\"} $LAST_DURATION" >> "$METRICS_FILE"
            else
                echo "remediation_chain_duration_seconds{chain=\"$chain\"} 0" >> "$METRICS_FILE"
            fi
        done <<< "$CHAINS"
    fi

    cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_chain_playbooks_total Total playbooks in last chain execution by outcome
# TYPE remediation_chain_playbooks_total gauge
EOF

    if [ -n "$CHAINS" ]; then
        while IFS= read -r chain; do
            # Get last execution for this chain
            LAST_EXEC=$(jq -c --arg chain "$chain" 'select(.chain == $chain)' "$CHAIN_METRICS_HISTORY" 2>/dev/null | tail -1)

            if [ -n "$LAST_EXEC" ]; then
                SUCCESS=$(echo "$LAST_EXEC" | jq -r '.playbooks_succeeded // 0')
                FAILED=$(echo "$LAST_EXEC" | jq -r '.playbooks_failed // 0')
                SKIPPED=$(echo "$LAST_EXEC" | jq -r '.playbooks_skipped // 0')

                echo "remediation_chain_playbooks_total{chain=\"$chain\",outcome=\"succeeded\"} $SUCCESS" >> "$METRICS_FILE"
                echo "remediation_chain_playbooks_total{chain=\"$chain\",outcome=\"failed\"} $FAILED" >> "$METRICS_FILE"
                echo "remediation_chain_playbooks_total{chain=\"$chain\",outcome=\"skipped\"} $SKIPPED" >> "$METRICS_FILE"
            fi
        done <<< "$CHAINS"
    fi

    cat >> "$METRICS_FILE" << 'EOF'

# HELP remediation_chain_success_rate Success rate of chain executions (0.0-1.0) over last 30 days
# TYPE remediation_chain_success_rate gauge
EOF

    THIRTY_DAYS_AGO=$(($(date +%s) - 30*24*60*60))

    if [ -n "$CHAINS" ]; then
        while IFS= read -r chain; do
            SUCCESS_30D=$(jq --arg chain "$chain" --argjson cutoff "$THIRTY_DAYS_AGO" \
                'select(.chain == $chain and .timestamp >= $cutoff and .status == "success")' \
                "$CHAIN_METRICS_HISTORY" 2>/dev/null | wc -l)
            TOTAL_30D=$(jq --arg chain "$chain" --argjson cutoff "$THIRTY_DAYS_AGO" \
                'select(.chain == $chain and .timestamp >= $cutoff)' \
                "$CHAIN_METRICS_HISTORY" 2>/dev/null | wc -l)

            if [ "$TOTAL_30D" -gt 0 ]; then
                SUCCESS_RATE=$(echo "scale=4; $SUCCESS_30D / $TOTAL_30D" | bc)
            else
                SUCCESS_RATE="0"
            fi

            echo "remediation_chain_success_rate{chain=\"$chain\"} $SUCCESS_RATE" >> "$METRICS_FILE"
        done <<< "$CHAINS"
    fi
fi

# Add metadata timestamp
cat >> "$METRICS_FILE" << EOF

# HELP remediation_metrics_last_update_timestamp Unix timestamp when metrics were last updated
# TYPE remediation_metrics_last_update_timestamp gauge
remediation_metrics_last_update_timestamp $(date +%s)
EOF

echo "✅ Remediation metrics written to $METRICS_FILE"
echo "📊 Metrics history: $(jq '.executions | length' "$METRICS_HISTORY") total executions tracked"
