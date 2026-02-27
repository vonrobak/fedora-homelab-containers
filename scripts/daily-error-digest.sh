#!/bin/bash
# Daily Error Digest from Loki
# Created: 2026-01-11
# Purpose: Query Loki for last 24h errors, aggregate by service/type, write to daily digest
# Exit: Always 0 (digest is best-effort; Loki/query failures should not mark the
#       service as failed in systemd since the morning digest handles missing data gracefully)

set -uo pipefail  # Remove -e to handle errors gracefully

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${1}"; }
log_section() { echo ""; log "${BLUE}▶ ${1}${NC}"; }

# Configuration
ERROR_THRESHOLD=10  # Send to Discord if total errors > threshold
LOOKBACK_HOURS=24   # How far back to look
LOKI_URL="http://loki:3100"

# Calculate time range (Loki expects nanosecond timestamps)
END_TIME=$(date +%s)000000000
START_TIME=$(date -d "$LOOKBACK_HOURS hours ago" +%s)000000000

log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${CYAN}   DAILY ERROR DIGEST - Last ${LOOKBACK_HOURS}h${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# ============================================================================
# HELPER: Query Loki from Grafana container
# ============================================================================
query_loki() {
    local query="$1"
    podman exec grafana curl -s -G "${LOKI_URL}/loki/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=${START_TIME}" \
        --data-urlencode "end=${END_TIME}" \
        --data-urlencode "limit=1000" 2>/dev/null || echo '{}'
}

# ============================================================================
# QUERY 1: Systemd Journal Errors (priority <= 3)
# ============================================================================
log_section "Querying systemd journal for errors (priority <= 3)..."

# Priority levels: 0=emerg, 1=alert, 2=crit, 3=err, 4=warning, 5=notice, 6=info, 7=debug
JOURNAL_ERRORS=$(query_loki '{job="systemd-journal"} | json | priority <= "3"' | \
    jq -r '.data.result[].values[][1]' 2>/dev/null | head -100 || echo "")

JOURNAL_ERROR_COUNT=$(echo "$JOURNAL_ERRORS" | grep -v "^$" | wc -l)
log "  Found: ${YELLOW}${JOURNAL_ERROR_COUNT}${NC} systemd errors"

# Group by service (extract unit name)
JOURNAL_BY_SERVICE=""
if [ "$JOURNAL_ERROR_COUNT" -gt 0 ]; then
    JOURNAL_BY_SERVICE=$(query_loki '{job="systemd-journal"} | json | priority <= "3"' | \
        jq -r '.data.result[] | .stream.unit + " (" + (.values | length | tostring) + ")"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || echo "")
fi

# ============================================================================
# QUERY 2: Traefik 5xx Errors
# ============================================================================
log_section "Querying Traefik for 5xx errors..."

TRAEFIK_5XX=$(query_loki '{job="traefik-access"} | json | status >= "500"' | \
    jq -r '.data.result[].values[][1]' 2>/dev/null | head -100 || echo "")

TRAEFIK_5XX_COUNT=$(echo "$TRAEFIK_5XX" | grep -v "^$" | wc -l)
log "  Found: ${YELLOW}${TRAEFIK_5XX_COUNT}${NC} Traefik 5xx errors"

# Group by service and status code
TRAEFIK_BY_SERVICE=""
if [ "$TRAEFIK_5XX_COUNT" -gt 0 ]; then
    TRAEFIK_BY_SERVICE=$(query_loki '{job="traefik-access"} | json | status >= "500"' | \
        jq -r '.data.result[] | .stream.service + " (HTTP " + .stream.status + "): " + (.values | length | tostring)' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || echo "")
fi

# ============================================================================
# QUERY 3: Failed Autonomous Remediations
# ============================================================================
log_section "Querying remediation failures..."

REMEDIATION_FAILURES=$(query_loki '{job="remediation-decisions"} | json | success="false"' | \
    jq -r '.data.result[].values[][1]' 2>/dev/null | head -100 || echo "")

REMEDIATION_FAILURE_COUNT=$(echo "$REMEDIATION_FAILURES" | grep -v "^$" | wc -l)
log "  Found: ${YELLOW}${REMEDIATION_FAILURE_COUNT}${NC} failed remediations"

# Group by playbook
REMEDIATION_BY_PLAYBOOK=""
if [ "$REMEDIATION_FAILURE_COUNT" -gt 0 ]; then
    REMEDIATION_BY_PLAYBOOK=$(query_loki '{job="remediation-decisions"} | json | success="false"' | \
        jq -r '.data.result[] | .stream.playbook + " (" + (.values | length | tostring) + ")"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || echo "")
fi

# ============================================================================
# CALCULATE TOTALS & DETERMINE ACTION
# ============================================================================
TOTAL_ERRORS=$((JOURNAL_ERROR_COUNT + TRAEFIK_5XX_COUNT + REMEDIATION_FAILURE_COUNT))

log ""
log "${CYAN}Summary:${NC}"
log "  ${YELLOW}Systemd errors:${NC}        $JOURNAL_ERROR_COUNT"
log "  ${YELLOW}Traefik 5xx:${NC}           $TRAEFIK_5XX_COUNT"
log "  ${YELLOW}Remediation failures:${NC}  $REMEDIATION_FAILURE_COUNT"
log "  ${CYAN}Total errors:${NC}          $TOTAL_ERRORS"
log ""

# ============================================================================
# WRITE STATUS TO DAILY DIGEST
# ============================================================================
log_section "Writing status to daily digest..."

DIGEST_DIR="/tmp/daily-digest"
mkdir -p "$DIGEST_DIR"

# Determine severity level
SEVERITY="ok"
if [ "$TOTAL_ERRORS" -ge 50 ]; then
    SEVERITY="critical"
elif [ "$TOTAL_ERRORS" -ge "$ERROR_THRESHOLD" ]; then
    SEVERITY="warning"
fi

# Build top errors summary for digest
TOP_ERRORS=""
if [ "$JOURNAL_ERROR_COUNT" -gt 0 ]; then
    TOP_ERRORS+="Systemd: $JOURNAL_ERROR_COUNT"
fi
if [ "$TRAEFIK_5XX_COUNT" -gt 0 ]; then
    [ -n "$TOP_ERRORS" ] && TOP_ERRORS+=", "
    TOP_ERRORS+="Traefik 5xx: $TRAEFIK_5XX_COUNT"
fi
if [ "$REMEDIATION_FAILURE_COUNT" -gt 0 ]; then
    [ -n "$TOP_ERRORS" ] && TOP_ERRORS+=", "
    TOP_ERRORS+="Remediation: $REMEDIATION_FAILURE_COUNT"
fi

cat > "$DIGEST_DIR/error-digest.json" <<EOF
{
  "status": "$SEVERITY",
  "total_errors": $TOTAL_ERRORS,
  "systemd_errors": $JOURNAL_ERROR_COUNT,
  "traefik_5xx": $TRAEFIK_5XX_COUNT,
  "remediation_failures": $REMEDIATION_FAILURE_COUNT,
  "summary": "$TOP_ERRORS"
}
EOF

if [ "$TOTAL_ERRORS" -ge "$ERROR_THRESHOLD" ]; then
    log "${YELLOW}Error count ($TOTAL_ERRORS) exceeds threshold ($ERROR_THRESHOLD) — flagged in digest${NC}"
else
    log "${GREEN}✓ Error count ($TOTAL_ERRORS) below threshold ($ERROR_THRESHOLD)${NC}"
fi

log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${GREEN}Error digest generation complete!${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

exit 0
