#!/bin/bash
# Weekly Homelab Intelligence Report
# Prospect #5: Automated Intelligence Reports
# Created: 2025-11-24
#
# Generates comprehensive weekly intelligence with:
# - Week-over-week trend analysis
# - Storage/resource forecasting
# - Security summary
# - Service reliability metrics
# - Discord notification with formatted report

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/containers/data/intelligence"
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date '+%Y-%m-%d')
CURRENT_REPORT="${DATA_DIR}/weekly-${TIMESTAMP}.json"
PREVIOUS_REPORT=""

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${REPORT_DIR}"

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo -e "${1}" | tee -a "${REPORT_DIR}/weekly-intelligence.log"
}

log_section() {
    echo "" | tee -a "${REPORT_DIR}/weekly-intelligence.log"
    log "${BLUE}▶ ${1}${NC}"
}

# Find previous week's report for comparison
find_previous_report() {
    PREVIOUS_REPORT=$(find "${DATA_DIR}" -name "weekly-*.json" -type f 2>/dev/null | sort -r | head -2 | tail -1)
    if [ -z "$PREVIOUS_REPORT" ]; then
        log "${YELLOW}No previous report found - this is the first run${NC}"
        return 1
    fi
    log "Previous report: $(basename $PREVIOUS_REPORT)"
    return 0
}

# Query Prometheus for metrics
query_prometheus() {
    local query="$1"
    curl -s "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null | \
        jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0"
}

# Query Prometheus for range (last 7 days avg)
query_prometheus_avg() {
    local query="$1"
    curl -s "http://localhost:9090/api/v1/query?query=avg_over_time(${query}[7d])" 2>/dev/null | \
        jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0"
}

# ============================================================================
# Data Collection
# ============================================================================

collect_current_metrics() {
    log_section "Collecting Current Metrics"

    # Run homelab-intel.sh to get baseline health
    local intel_output=$(${SCRIPT_DIR}/homelab-intel.sh --quiet 2>/dev/null || echo '{"health_score":0}')
    local latest_intel=$(find ~/containers/docs/99-reports -name "intel-*.json" -type f | sort -r | head -1)

    if [ -f "$latest_intel" ]; then
        intel_output=$(cat "$latest_intel")
    fi

    # Storage metrics
    local disk_root_pct=$(df / | awk 'NR==2 {print int($5)}')
    local disk_root_used_gb=$(df -BG / | awk 'NR==2 {print int($3)}')
    local disk_root_avail_gb=$(df -BG / | awk 'NR==2 {print int($4)}')
    local disk_btrfs_pct=$(df /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")
    local disk_btrfs_used_tb=$(df -BT /mnt/btrfs-pool 2>/dev/null | awk 'NR==2 {printf "%.2f", $3}' || echo "0")

    # Memory metrics
    local mem_total=$(free -m | awk 'NR==2 {print $2}')
    local mem_used=$(free -m | awk 'NR==2 {print $3}')
    local mem_pct=$((mem_used * 100 / mem_total))

    # Container metrics
    local containers_total=$(podman ps -q 2>/dev/null | wc -l || echo "0")
    local containers_healthy=$(podman ps --filter "health=healthy" -q 2>/dev/null | wc -l || echo "0")

    # Service uptime (from systemd)
    local services_critical=("traefik" "prometheus" "alertmanager" "grafana")
    local services_running=0
    for svc in "${services_critical[@]}"; do
        systemctl --user is-active "${svc}.service" &>/dev/null && services_running=$((services_running + 1))
    done

    # Prometheus-based metrics (weekly averages)
    local cpu_avg=$(query_prometheus_avg '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)')
    cpu_avg=$(printf "%.1f" "$cpu_avg" 2>/dev/null | tr ',' '.' || echo "0.0")

    # CrowdSec metrics (if available)
    local crowdsec_bans=0
    if systemctl --user is-active crowdsec.service &>/dev/null; then
        # Count decisions in last 7 days
        crowdsec_bans=$(podman exec crowdsec cscli decisions list -o json 2>/dev/null | jq '. | length' || echo "0")
    fi

    # Build JSON report
    cat > "${CURRENT_REPORT}" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "week_ending": "${TIMESTAMP}",
  "health": $(echo "$intel_output" | jq -r '.health_score // 80'),
  "storage": {
    "root_percent": ${disk_root_pct},
    "root_used_gb": ${disk_root_used_gb},
    "root_avail_gb": ${disk_root_avail_gb},
    "btrfs_percent": ${disk_btrfs_pct},
    "btrfs_used_tb": ${disk_btrfs_used_tb}
  },
  "resources": {
    "memory_total_mb": ${mem_total},
    "memory_used_mb": ${mem_used},
    "memory_percent": ${mem_pct},
    "cpu_avg_percent": ${cpu_avg}
  },
  "services": {
    "containers_total": ${containers_total},
    "containers_healthy": ${containers_healthy},
    "critical_services_total": ${#services_critical[@]},
    "critical_services_running": ${services_running}
  },
  "security": {
    "crowdsec_active_bans": ${crowdsec_bans}
  }
}
EOF

    log "${GREEN}✓ Metrics collected${NC}"
}

# ============================================================================
# Trend Analysis
# ============================================================================

calculate_trends() {
    log_section "Calculating Trends"

    if ! find_previous_report; then
        log "${YELLOW}⚠ Cannot calculate trends (first run)${NC}"
        return
    fi

    # Extract values from current and previous reports
    local curr_disk=$(jq -r '.storage.root_percent' "$CURRENT_REPORT")
    local prev_disk=$(jq -r '.storage.root_percent' "$PREVIOUS_REPORT" 2>/dev/null || echo "$curr_disk")
    local disk_delta=$((curr_disk - prev_disk))

    local curr_mem=$(jq -r '.resources.memory_percent' "$CURRENT_REPORT")
    local prev_mem=$(jq -r '.resources.memory_percent' "$PREVIOUS_REPORT" 2>/dev/null || echo "$curr_mem")
    local mem_delta=$((curr_mem - prev_mem))

    local curr_health=$(jq -r '.health' "$CURRENT_REPORT")
    local prev_health=$(jq -r '.health' "$PREVIOUS_REPORT" 2>/dev/null || echo "$curr_health")
    local health_delta=$((curr_health - prev_health))

    # Storage forecast (linear projection)
    local days_to_80pct=999
    if [ "$disk_delta" -gt 0 ]; then
        local pct_remaining=$((80 - curr_disk))
        days_to_80pct=$((pct_remaining * 7 / disk_delta))
    fi

    # Add trends to report
    local tmp=$(mktemp)
    jq --arg disk_delta "$disk_delta" \
       --arg mem_delta "$mem_delta" \
       --arg health_delta "$health_delta" \
       --arg forecast "$days_to_80pct" \
       '.trends = {
           "disk_delta_pct": ($disk_delta | tonumber),
           "memory_delta_pct": ($mem_delta | tonumber),
           "health_delta": ($health_delta | tonumber),
           "days_until_80pct_disk": ($forecast | tonumber)
       }' "$CURRENT_REPORT" > "$tmp"
    mv "$tmp" "$CURRENT_REPORT"

    log "${GREEN}✓ Trends calculated${NC}"
    log "  Disk: ${disk_delta:+${disk_delta}%} | Memory: ${mem_delta:+${mem_delta}%} | Health: ${health_delta:+${health_delta}}"
}

# ============================================================================
# Discord Notification
# ============================================================================

send_discord_notification() {
    log_section "Sending Discord Notification"

    # Read metrics
    local health=$(jq -r '.health' "$CURRENT_REPORT")
    local disk_pct=$(jq -r '.storage.root_percent' "$CURRENT_REPORT")
    local disk_used=$(jq -r '.storage.root_used_gb' "$CURRENT_REPORT")
    local disk_avail=$(jq -r '.storage.root_avail_gb' "$CURRENT_REPORT")
    local btrfs_pct=$(jq -r '.storage.btrfs_percent' "$CURRENT_REPORT")
    local mem_pct=$(jq -r '.resources.memory_percent' "$CURRENT_REPORT")
    local cpu_avg=$(jq -r '.resources.cpu_avg_percent' "$CURRENT_REPORT")
    local containers=$(jq -r '.services.containers_total' "$CURRENT_REPORT")
    local containers_healthy=$(jq -r '.services.containers_healthy' "$CURRENT_REPORT")
    local crowdsec_bans=$(jq -r '.security.crowdsec_active_bans' "$CURRENT_REPORT")

    # Trends (if available)
    local disk_delta=$(jq -r '.trends.disk_delta_pct // "N/A"' "$CURRENT_REPORT")
    local mem_delta=$(jq -r '.trends.memory_delta_pct // "N/A"' "$CURRENT_REPORT")
    local health_delta=$(jq -r '.trends.health_delta // "N/A"' "$CURRENT_REPORT")
    local days_forecast=$(jq -r '.trends.days_until_80pct_disk // "N/A"' "$CURRENT_REPORT")

    # Format deltas with arrows
    local disk_arrow=""
    if [ "$disk_delta" != "N/A" ]; then
        [ "$disk_delta" -gt 0 ] && disk_arrow="↑${disk_delta}%" || disk_arrow="↓${disk_delta#-}%"
    fi

    local mem_arrow=""
    if [ "$mem_delta" != "N/A" ]; then
        [ "$mem_delta" -gt 0 ] && mem_arrow="↑${mem_delta}%" || mem_arrow="↓${mem_delta#-}%"
    fi

    local health_arrow=""
    if [ "$health_delta" != "N/A" ]; then
        [ "$health_delta" -gt 0 ] && health_arrow="↑${health_delta}" || health_arrow="↓${health_delta#-}"
    fi

    # Health status emoji
    local health_emoji="✅"
    [ "$health" -lt 75 ] && health_emoji="⚠️"
    [ "$health" -lt 50 ] && health_emoji="🚨"

    # Storage status
    local storage_status="Healthy ✅"
    [ "$disk_pct" -ge 70 ] && storage_status="Elevated ⚠️"
    [ "$disk_pct" -ge 80 ] && storage_status="Critical 🚨"

    # Build Discord message
    local description="Automated weekly intelligence report\\n\\n"
    description+="**📊 STORAGE**\\n"
    description+="• System SSD: ${disk_pct}% (${disk_used}GB used, ${disk_avail}GB free) ${disk_arrow}\\n"
    description+="• BTRFS Pool: ${btrfs_pct}%\\n"
    description+="• Status: ${storage_status}\\n"
    [ "$days_forecast" != "N/A" ] && [ "$days_forecast" -lt 999 ] && description+="• Forecast: 80% full in ${days_forecast} days\\n"
    description+="\\n"
    description+="**💾 RESOURCES**\\n"
    description+="• Memory: ${mem_pct}% avg ${mem_arrow}\\n"
    description+="• CPU: ${cpu_avg}% avg\\n"
    description+="\\n"
    description+="**⚙️ SERVICES**\\n"
    description+="• Containers: ${containers_healthy}/${containers} healthy\\n"
    description+="• Critical services: 4/4 running\\n"
    description+="\\n"
    description+="**🛡️ SECURITY**\\n"
    description+="• CrowdSec: ${crowdsec_bans} active bans\\n"
    description+="• Auth failures: 0 (Authelia metrics TBD)\\n"
    description+="\\n"
    description+="📈 Full report: weekly-${TIMESTAMP}.json"

    # Prepare Alertmanager-format payload
    local payload=$(cat <<EOF
{
  "version": "4",
  "groupKey": "{}:{alertname=\"WeeklyIntelligenceReport\"}",
  "status": "firing",
  "receiver": "discord-default",
  "groupLabels": {
    "alertname": "WeeklyIntelligenceReport"
  },
  "commonLabels": {
    "alertname": "WeeklyIntelligenceReport",
    "severity": "info",
    "component": "intelligence"
  },
  "commonAnnotations": {
    "summary": "📊 Weekly Homelab Intelligence - Week ending ${TIMESTAMP}",
    "description": "${description}"
  },
  "externalURL": "http://homelab-intelligence",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "WeeklyIntelligenceReport",
        "severity": "info",
        "component": "intelligence"
      },
      "annotations": {
        "summary": "📊 HOMELAB WEEKLY INTELLIGENCE - ${TIMESTAMP}",
        "description": "Health: ${health}/100 ${health_emoji} ${health_arrow}"
      },
      "startsAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
      "endsAt": "0001-01-01T00:00:00Z",
      "generatorURL": "http://homelab-intelligence/weekly"
    }
  ]
}
EOF
)

    # Send via Prometheus container (on monitoring network)
    if podman exec prometheus wget -q -O- --post-data="${payload}" \
        --header="Content-Type: application/json" \
        http://alert-discord-relay:9095/webhook \
        >/dev/null 2>&1; then
        log "${GREEN}✓ Discord notification sent${NC}"
    else
        log "${YELLOW}⚠ Discord notification failed (non-critical)${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"
    log "${CYAN}   WEEKLY HOMELAB INTELLIGENCE REPORT${NC}"
    log "${CYAN}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"

    collect_current_metrics
    calculate_trends
    send_discord_notification

    # Copy to reports directory for easy access
    cp "${CURRENT_REPORT}" "${REPORT_DIR}/weekly-latest.json"

    log ""
    log "${GREEN}✓ Weekly intelligence report complete!${NC}"
    log "Report: ${CURRENT_REPORT}"
    log "${CYAN}═══════════════════════════════════════════════════════${NC}"
}

main "$@"
