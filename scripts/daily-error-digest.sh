#!/bin/bash
# Daily Error Digest from Loki
# Created: 2026-01-11
# Purpose: Query Loki for last 24h errors, aggregate by service/type, send to Discord

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

# Skip Discord if below threshold
if [ "$TOTAL_ERRORS" -lt "$ERROR_THRESHOLD" ]; then
    log "${GREEN}✓ Error count below threshold ($ERROR_THRESHOLD), skipping Discord notification${NC}"
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"
    exit 0
fi

# ============================================================================
# FORMAT DISCORD PAYLOAD
# ============================================================================
log_section "Formatting Discord notification..."

# Determine color based on severity
if [ "$TOTAL_ERRORS" -ge 50 ]; then
    EMBED_COLOR="15158332"  # Red - critical
elif [ "$TOTAL_ERRORS" -ge 25 ]; then
    EMBED_COLOR="16776960"  # Yellow - warning
else
    EMBED_COLOR="3447003"   # Blue - info
fi

# Build fields for Discord embed
DISCORD_FIELDS="["

# Add systemd errors field
if [ "$JOURNAL_ERROR_COUNT" -gt 0 ]; then
    SYSTEMD_TOP=$(echo "$JOURNAL_BY_SERVICE" | head -5 | sed 's/^/• /' | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g')
    DISCORD_FIELDS+=$(cat <<EOF
{
  "name": "🔴 Systemd Errors ($JOURNAL_ERROR_COUNT)",
  "value": "$SYSTEMD_TOP",
  "inline": false
},
EOF
)
fi

# Add Traefik 5xx field
if [ "$TRAEFIK_5XX_COUNT" -gt 0 ]; then
    TRAEFIK_TOP=$(echo "$TRAEFIK_BY_SERVICE" | head -5 | sed 's/^/• /' | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g')
    DISCORD_FIELDS+=$(cat <<EOF
{
  "name": "🌐 Traefik 5xx Errors ($TRAEFIK_5XX_COUNT)",
  "value": "$TRAEFIK_TOP",
  "inline": false
},
EOF
)
fi

# Add remediation failures field
if [ "$REMEDIATION_FAILURE_COUNT" -gt 0 ]; then
    REMEDIATION_TOP=$(echo "$REMEDIATION_BY_PLAYBOOK" | head -5 | sed 's/^/• /' | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g')
    DISCORD_FIELDS+=$(cat <<EOF
{
  "name": "🤖 Remediation Failures ($REMEDIATION_FAILURE_COUNT)",
  "value": "$REMEDIATION_TOP",
  "inline": false
},
EOF
)
fi

# Add recommendations
RECOMMENDATIONS=""
if [ "$JOURNAL_ERROR_COUNT" -ge 20 ]; then
    RECOMMENDATIONS+="• Investigate systemd service failures\n"
fi
if [ "$TRAEFIK_5XX_COUNT" -ge 10 ]; then
    RECOMMENDATIONS+="• Review backend service health (5xx = server errors)\n"
fi
if [ "$REMEDIATION_FAILURE_COUNT" -ge 5 ]; then
    RECOMMENDATIONS+="• Check autonomous playbook configurations\n"
fi
if [ -z "$RECOMMENDATIONS" ]; then
    RECOMMENDATIONS="• Monitor trends over next 24h\n• All systems operational"
fi

DISCORD_FIELDS+=$(cat <<EOF
{
  "name": "💡 Recommendations",
  "value": "$RECOMMENDATIONS",
  "inline": false
}
EOF
)

DISCORD_FIELDS+="]"

# Build full payload
DISCORD_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "📊 Daily Error Digest",
    "description": "**Lookback period:** Last ${LOOKBACK_HOURS} hours\n**Total errors:** $TOTAL_ERRORS",
    "color": $EMBED_COLOR,
    "fields": $DISCORD_FIELDS,
    "footer": {
      "text": "Generated by Loki daily error digest • Next report: $(date -d '1 day' '+%Y-%m-%d 07:00')"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }]
}
EOF
)

# ============================================================================
# SEND TO DISCORD
# ============================================================================
log_section "Sending digest to Discord..."

# Get Discord webhook URL from alert-discord-relay container
DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

if [ -z "$DISCORD_WEBHOOK" ]; then
    log "${RED}✗ Could not get Discord webhook URL${NC}"
    log "${YELLOW}  Check that alert-discord-relay container is running${NC}"
    exit 1
fi

# Send to Discord
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$DISCORD_PAYLOAD" \
    "$DISCORD_WEBHOOK")

if echo "$HTTP_CODE" | grep -q "^20"; then
    log "${GREEN}✓ Daily error digest sent to Discord successfully (HTTP $HTTP_CODE)${NC}"
    exit_code=0
else
    log "${RED}✗ Failed to send digest to Discord (HTTP $HTTP_CODE)${NC}"
    log "${YELLOW}  Check Discord webhook configuration${NC}"
    exit_code=1
fi

log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${GREEN}Digest generation complete!${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

exit $exit_code
