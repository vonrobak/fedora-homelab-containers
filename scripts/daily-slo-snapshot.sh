#!/bin/bash
# Daily SLO Performance Snapshot
# Created: 2026-01-09
# Purpose: Capture daily SLO metrics for trend analysis and calibration
#
# This script collects SLO performance data daily and stores it in a CSV
# for later analysis. Used to calibrate SLO targets based on actual
# 95th percentile performance rather than estimates.

set -euo pipefail

# Configuration
SNAPSHOT_DIR="$HOME/containers/data/slo-snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/slo-daily-$(date +%Y-%m).csv"
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)

# Ensure directory exists
mkdir -p "$SNAPSHOT_DIR"

# Query Prometheus from inside the prometheus container
query_prom() {
    podman exec prometheus wget -q -O- "http://localhost:9090/api/v1/query?query=$1" 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null"
}

# Create CSV header if file doesn't exist
if [ ! -f "$SNAPSHOT_FILE" ]; then
    cat > "$SNAPSHOT_FILE" <<EOF
timestamp,service,availability_actual,availability_target,error_budget_remaining,compliant
EOF
fi

# Collect metrics for each service
declare -A SERVICES=(
    ["jellyfin"]="0.995"
    ["immich"]="0.995"
    ["authelia"]="0.999"
    ["traefik"]="0.9995"
    ["nextcloud"]="0.995"
    ["home_assistant"]="0.995"
)

for service in "${!SERVICES[@]}"; do
    target="${SERVICES[$service]}"
    actual=$(query_prom "slo:${service}:availability:actual")
    budget=$(query_prom "error_budget:${service}:availability:budget_remaining")
    compliant=$(query_prom "slo:${service}:availability:compliant")

    echo "$TIMESTAMP,$service,$actual,$target,$budget,$compliant" >> "$SNAPSHOT_FILE"
done

# Log completion
echo "$(date +%H:%M:%S) - SLO snapshot captured to $SNAPSHOT_FILE"

# Cleanup old snapshot files (keep 3 months)
find "$SNAPSHOT_DIR" -name "slo-daily-*.csv" -mtime +90 -delete 2>/dev/null || true

exit 0
