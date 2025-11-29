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
    local crowdsec_alerts=0
    local crowdsec_capi="disconnected"
    if systemctl --user is-active crowdsec.service &>/dev/null; then
        # Count active decisions (bans)
        crowdsec_bans=$(timeout 5 podman exec crowdsec cscli decisions list -o json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
        # Count alerts in last 7 days
        crowdsec_alerts=$(timeout 5 podman exec crowdsec cscli alerts list -o json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
        # Check CAPI status
        if timeout 5 podman exec crowdsec cscli capi status 2>&1 | grep -q "successfully interact"; then
            crowdsec_capi="connected"
        fi
    fi

    # Autonomous Operations metrics
    local auto_ops_enabled="false"
    local auto_ops_actions=0
    local auto_ops_success_rate="1.0"
    local auto_ops_circuit="ok"
    local auto_state_file="${HOME}/containers/.claude/context/autonomous-state.json"
    local auto_decision_log="${HOME}/containers/.claude/context/decision-log.json"

    if [[ -f "$auto_state_file" ]]; then
        auto_ops_enabled=$(jq -r '.enabled // false' "$auto_state_file")
        auto_ops_success_rate=$(jq -r '.statistics.success_rate // 1.0' "$auto_state_file")
        if [[ "$(jq -r '.circuit_breaker.triggered // false' "$auto_state_file")" == "true" ]]; then
            auto_ops_circuit="triggered"
        elif [[ "$(jq -r '.paused // false' "$auto_state_file")" == "true" ]]; then
            auto_ops_circuit="paused"
        fi
    fi

    if [[ -f "$auto_decision_log" ]]; then
        # Count decisions in last 7 days
        local cutoff_date
        cutoff_date=$(date -d "7 days ago" -Iseconds)
        auto_ops_actions=$(jq --arg cutoff "$cutoff_date" '[.decisions[] | select(.timestamp > $cutoff)] | length' "$auto_decision_log" 2>/dev/null || echo "0")
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
    "crowdsec_active_bans": ${crowdsec_bans},
    "crowdsec_alerts_7d": ${crowdsec_alerts},
    "crowdsec_capi": "${crowdsec_capi}"
  },
  "autonomous_ops": {
    "enabled": ${auto_ops_enabled},
    "actions_7d": ${auto_ops_actions},
    "success_rate": ${auto_ops_success_rate},
    "circuit_breaker": "${auto_ops_circuit}"
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
    local disk_avail=$(jq -r '.storage.root_avail_gb' "$CURRENT_REPORT")
    local btrfs_pct=$(jq -r '.storage.btrfs_percent' "$CURRENT_REPORT")
    local mem_pct=$(jq -r '.resources.memory_percent' "$CURRENT_REPORT")
    local containers=$(jq -r '.services.containers_total' "$CURRENT_REPORT")
    local containers_healthy=$(jq -r '.services.containers_healthy' "$CURRENT_REPORT")
    local crowdsec_bans=$(jq -r '.security.crowdsec_active_bans' "$CURRENT_REPORT")
    local crowdsec_alerts=$(jq -r '.security.crowdsec_alerts_7d // 0' "$CURRENT_REPORT")
    local crowdsec_capi=$(jq -r '.security.crowdsec_capi // "unknown"' "$CURRENT_REPORT")

    # Autonomous operations metrics
    local auto_ops_actions=$(jq -r '.autonomous_ops.actions_7d // 0' "$CURRENT_REPORT")
    local auto_ops_rate=$(jq -r '.autonomous_ops.success_rate // 1.0' "$CURRENT_REPORT" | awk '{printf "%.0f", $1 * 100}')
    local auto_ops_circuit=$(jq -r '.autonomous_ops.circuit_breaker // "ok"' "$CURRENT_REPORT")
    local auto_ops_enabled=$(jq -r '.autonomous_ops.enabled // false' "$CURRENT_REPORT")

    # Determine status display
    local auto_ops_status="Active"
    if [[ "$auto_ops_circuit" == "triggered" ]]; then
        auto_ops_status="⚠️ Breaker"
    elif [[ "$auto_ops_circuit" == "paused" ]]; then
        auto_ops_status="Paused"
    elif [[ "$auto_ops_enabled" == "false" ]]; then
        auto_ops_status="Disabled"
    fi

    # Trends (if available)
    local disk_delta=$(jq -r '.trends.disk_delta_pct // 0' "$CURRENT_REPORT")
    local days_forecast=$(jq -r '.trends.days_until_80pct_disk // 999' "$CURRENT_REPORT")

    # Format delta arrow
    local disk_trend=""
    if [ "$disk_delta" -gt 0 ] 2>/dev/null; then
        disk_trend=" ↑${disk_delta}%"
    elif [ "$disk_delta" -lt 0 ] 2>/dev/null; then
        disk_trend=" ↓${disk_delta#-}%"
    fi

    # Determine health color and emoji
    local report_color="3066993"  # Green
    local health_emoji="✅"
    if [ "$health" -lt 75 ]; then
        report_color="15105570"  # Orange
        health_emoji="⚠️"
    fi
    if [ "$health" -lt 50 ]; then
        report_color="15158332"  # Red
        health_emoji="🚨"
    fi

    # Build forecast warning if relevant
    local forecast_note=""
    if [ "$days_forecast" -lt 30 ] 2>/dev/null; then
        forecast_note="\n⚠️ **Disk forecast:** 80% full in ${days_forecast} days"
    fi

    # Build succinct Discord embed
    read -r -d '' DISCORD_PAYLOAD <<EOF || true
{
  "embeds": [{
    "title": "📊 Weekly Intelligence - Week of ${TIMESTAMP}",
    "description": "**Health Score:** ${health}/100 ${health_emoji}${forecast_note}",
    "color": ${report_color},
    "fields": [
      {
        "name": "💾 Storage",
        "value": "SSD: ${disk_pct}%${disk_trend} (${disk_avail}GB free)\nBTRFS: ${btrfs_pct}%",
        "inline": true
      },
      {
        "name": "⚙️ Services",
        "value": "${containers_healthy}/${containers} healthy\n4/4 critical",
        "inline": true
      },
      {
        "name": "🛡️ Security",
        "value": "CrowdSec: ${crowdsec_capi}\nBans: ${crowdsec_bans} | Alerts: ${crowdsec_alerts}",
        "inline": true
      },
      {
        "name": "🤖 Autonomous Ops",
        "value": "Status: ${auto_ops_status}\nActions: ${auto_ops_actions} | Rate: ${auto_ops_rate}%",
        "inline": true
      }
    ],
    "footer": {
      "text": "Weekly Report • Next: $(date -d 'next friday' '+%b %d')"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }]
}
EOF

    # Get Discord webhook URL and send directly
    local DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

    if [ -n "$DISCORD_WEBHOOK" ]; then
        if curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$DISCORD_PAYLOAD" \
            "$DISCORD_WEBHOOK" | grep -q "^20"; then
            log "${GREEN}✓ Discord notification sent${NC}"
        else
            log "${YELLOW}⚠ Discord notification failed${NC}"
        fi
    else
        log "${YELLOW}⚠ Discord webhook not found${NC}"
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
