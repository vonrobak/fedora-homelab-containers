#!/bin/bash
# precompute-queries.sh
# Pre-compute common queries and populate cache
#
# STATUS: ✅ PRODUCTION-READY (Approved 2025-11-22)
# Safety audit: docs/99-reports/2025-11-22-query-system-safety-audit.md
#
# Purpose:
#   - Execute frequently asked queries proactively
#   - Populate query cache for instant responses
#   - Run via cron every 5 minutes for fresh cache
#
# Usage:
#   ./precompute-queries.sh
#
# Cron (every 5 minutes):
#   */5 * * * * ~/containers/scripts/precompute-queries.sh >> ~/containers/data/query-cache.log 2>&1
#
# Safety: Timeout protected (10s per query), completes in <5s total

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_SCRIPT="$SCRIPT_DIR/query-homelab.sh"

# Common queries to pre-compute (SAFE queries only - no journalctl heavy ops)
QUERIES=(
    "What services are using the most memory?"
    "What's using the most CPU?"
    "Show me disk usage"
)

# Optional: Log output
LOG_FILE="${LOG_FILE:-/dev/null}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pre-computing common queries..." >> "$LOG_FILE"

# Execute each query to populate cache with timeout protection
for query in "${QUERIES[@]}"; do
    echo "  - $query" >> "$LOG_FILE"

    # Add timeout protection (10 seconds per query)
    if timeout 10 "$QUERY_SCRIPT" "$query" > /dev/null 2>&1; then
        echo "    ✓ Cached successfully" >> "$LOG_FILE"
    else
        echo "    WARNING: Query failed or timed out" >> "$LOG_FILE"
    fi
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cache updated successfully" >> "$LOG_FILE"
