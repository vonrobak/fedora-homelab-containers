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

# Direct executor calls for queries without good NL patterns
# Format: "cache_key:executor_function"
DIRECT_EXECUTORS=(
    "unhealthy_services:get_unhealthy_services"
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

# Execute direct executor calls (for patterns that don't match well via NL)
for entry in "${DIRECT_EXECUTORS[@]}"; do
    IFS=':' read -r cache_key executor <<< "$entry"
    echo "  - Direct executor: $executor" >> "$LOG_FILE"

    # Source query-homelab.sh to get access to executor functions
    if timeout 10 bash -c "
        source '$QUERY_SCRIPT' 2>/dev/null || exit 1

        # Call executor and cache result
        CONTEXT_DIR=\"\$HOME/containers/.claude/context\"
        CACHE_FILE=\"\$CONTEXT_DIR/query-cache.json\"

        # Get result from executor
        result=\$($executor 2>/dev/null) || exit 1

        # Update cache
        mkdir -p \"\$CONTEXT_DIR\"
        if [[ ! -f \"\$CACHE_FILE\" ]]; then
            echo '{}' > \"\$CACHE_FILE\"
        fi

        # Add to cache with timestamp and TTL
        timestamp=\$(date -Iseconds)
        updated=\$(jq --arg key \"$cache_key\" \
                     --arg ts \"\$timestamp\" \
                     --argjson ttl 60 \
                     --argjson res \"\$result\" \
                     '.[\$key] = {timestamp: \$ts, ttl: \$ttl, result: \$res}' \
                     \"\$CACHE_FILE\")
        echo \"\$updated\" > \"\$CACHE_FILE\"
    " > /dev/null 2>&1; then
        echo "    ✓ Cached successfully ($cache_key)" >> "$LOG_FILE"
    else
        echo "    WARNING: Direct executor failed or timed out ($cache_key)" >> "$LOG_FILE"
    fi
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cache updated successfully" >> "$LOG_FILE"
