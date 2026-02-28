#!/bin/bash
# Monthly SLO Report to Discord
# Created: 2025-11-28
# Purpose: Send comprehensive SLO compliance report to Discord

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${1}"; }
log_section() { echo ""; log "${BLUE}▶ ${1}${NC}"; }

# Query Prometheus from inside the prometheus container
query_prom() {
    podman exec prometheus wget -q -O- "http://localhost:9090/api/v1/query?query=$1" 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null"
}

# Get current month name
MONTH=$(date '+%B %Y')

log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${CYAN}   GENERATING MONTHLY SLO REPORT - $MONTH${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# ============================================================================
# COLLECT SLO DATA
# ============================================================================
log_section "Collecting SLO metrics from Prometheus..."

# Jellyfin
jellyfin_actual=$(query_prom 'slo:jellyfin:availability:actual')
jellyfin_budget=$(query_prom 'error_budget:jellyfin:availability:budget_remaining')
jellyfin_compliant=$(query_prom 'slo:jellyfin:availability:compliant')

# Immich
immich_actual=$(query_prom 'slo:immich:availability:actual')
immich_budget=$(query_prom 'error_budget:immich:availability:budget_remaining')
immich_compliant=$(query_prom 'slo:immich:availability:compliant')

# Authelia
authelia_actual=$(query_prom 'slo:authelia:availability:actual')
authelia_budget=$(query_prom 'error_budget:authelia:availability:budget_remaining')
authelia_compliant=$(query_prom 'slo:authelia:availability:compliant')

# Traefik
traefik_actual=$(query_prom 'slo:traefik:availability:actual')
traefik_budget=$(query_prom 'error_budget:traefik:availability:budget_remaining')
traefik_compliant=$(query_prom 'slo:traefik:availability:compliant')

# Nextcloud
nextcloud_actual=$(query_prom 'slo:nextcloud:availability:actual')
nextcloud_budget=$(query_prom 'error_budget:nextcloud:availability:budget_remaining')
nextcloud_compliant=$(query_prom 'slo:nextcloud:availability:compliant')

# Home Assistant
ha_actual=$(query_prom 'slo:home_assistant:availability:actual')
ha_budget=$(query_prom 'error_budget:home_assistant:availability:budget_remaining')
ha_compliant=$(query_prom 'slo:home_assistant:availability:compliant')

# Navidrome
navidrome_actual=$(query_prom 'slo:navidrome:availability:actual')
navidrome_budget=$(query_prom 'error_budget:navidrome:availability:budget_remaining')
navidrome_compliant=$(query_prom 'slo:navidrome:availability:compliant')

# Audiobookshelf
audiobookshelf_actual=$(query_prom 'slo:audiobookshelf:availability:actual')
audiobookshelf_budget=$(query_prom 'error_budget:audiobookshelf:availability:budget_remaining')
audiobookshelf_compliant=$(query_prom 'slo:audiobookshelf:availability:compliant')

# ============================================================================
# FORMAT REPORT
# ============================================================================
log_section "Formatting report..."

# Helper function to format percentage (handles negative/over-budget values)
format_pct() {
    local val="$1"
    if [ "$val" = "null" ] || [ -z "$val" ]; then
        echo "N/A"
    else
        # Check if negative (over-budget scenario)
        local is_negative=$(echo "$val < 0" | bc -l 2>/dev/null || echo "0")
        if [ "$is_negative" = "1" ]; then
            echo "0.00% (exhausted)"
        else
            # Use awk for reliable number formatting
            echo "$val" | awk '{printf "%.2f%%", $1 * 100}'
        fi
    fi
}

# Helper function to determine compliance emoji
compliance_emoji() {
    local val="$1"
    if [ "$val" = "1" ]; then
        echo "✅"
    elif [ "$val" = "0" ]; then
        echo "❌"
    else
        echo "⏳"
    fi
}

# Helper function for budget color (returns Discord color code)
budget_color() {
    local val="$1"
    if [ "$val" = "null" ] || [ -z "$val" ]; then
        echo "10070709"  # Gray - no data
    else
        local pct=$(echo "$val * 100" | bc -l | cut -d. -f1)
        if [ "$pct" -ge 75 ]; then
            echo "3066993"   # Green
        elif [ "$pct" -ge 50 ]; then
            echo "15844367"  # Yellow
        elif [ "$pct" -ge 25 ]; then
            echo "15105570"  # Orange
        else
            echo "15158332"  # Red
        fi
    fi
}

# Determine overall health color
overall_violations=0
[ "$jellyfin_compliant" = "0" ] && ((overall_violations++)) || true
[ "$immich_compliant" = "0" ] && ((overall_violations++)) || true
[ "$authelia_compliant" = "0" ] && ((overall_violations++)) || true
[ "$traefik_compliant" = "0" ] && ((overall_violations++)) || true
[ "$nextcloud_compliant" = "0" ] && ((overall_violations++)) || true
[ "$ha_compliant" = "0" ] && ((overall_violations++)) || true
[ "$navidrome_compliant" = "0" ] && ((overall_violations++)) || true
[ "$audiobookshelf_compliant" = "0" ] && ((overall_violations++)) || true

if [ "$overall_violations" -eq 0 ]; then
    report_color="3066993"  # Green
    health_status="All SLOs Met ✅"
elif [ "$overall_violations" -le 2 ]; then
    report_color="15105570"  # Orange
    health_status="Some SLOs Violated ⚠️"
else
    report_color="15158332"  # Red
    health_status="Multiple SLOs Violated 🚨"
fi

# ============================================================================
# BUILD DISCORD EMBED
# ============================================================================
log_section "Building Discord payload..."

# Create JSON payload with Discord embed format
read -r -d '' DISCORD_PAYLOAD <<EOF || true
{
  "embeds": [{
    "title": "📊 Monthly SLO Report - $MONTH",
    "description": "**Overall Status:** $health_status\n\nService Level Objectives compliance report for the past 30 days.",
    "color": $report_color,
    "fields": [
      {
        "name": "🎬 Jellyfin Media Server",
        "value": "$(compliance_emoji "$jellyfin_compliant") **Availability:** $(format_pct "$jellyfin_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$jellyfin_budget") remaining",
        "inline": true
      },
      {
        "name": "📸 Immich Photos",
        "value": "$(compliance_emoji "$immich_compliant") **Availability:** $(format_pct "$immich_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$immich_budget") remaining",
        "inline": true
      },
      {
        "name": "🔐 Authelia SSO",
        "value": "$(compliance_emoji "$authelia_compliant") **Availability:** $(format_pct "$authelia_actual")\n**Target:** 99.90%\n**Error Budget:** $(format_pct "$authelia_budget") remaining",
        "inline": true
      },
      {
        "name": "🌐 Traefik Gateway",
        "value": "$(compliance_emoji "$traefik_compliant") **Availability:** $(format_pct "$traefik_actual")\n**Target:** 99.95%\n**Error Budget:** $(format_pct "$traefik_budget") remaining",
        "inline": true
      },
      {
        "name": "☁️ Nextcloud File Storage",
        "value": "$(compliance_emoji "$nextcloud_compliant") **Availability:** $(format_pct "$nextcloud_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$nextcloud_budget") remaining",
        "inline": true
      },
      {
        "name": "🏠 Home Assistant",
        "value": "$(compliance_emoji "$ha_compliant") **Availability:** $(format_pct "$ha_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$ha_budget") remaining",
        "inline": true
      },
      {
        "name": "🎵 Navidrome Music",
        "value": "$(compliance_emoji "$navidrome_compliant") **Availability:** $(format_pct "$navidrome_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$navidrome_budget") remaining",
        "inline": true
      },
      {
        "name": "🎧 Audiobookshelf",
        "value": "$(compliance_emoji "$audiobookshelf_compliant") **Availability:** $(format_pct "$audiobookshelf_actual")\n**Target:** 99.50%\n**Error Budget:** $(format_pct "$audiobookshelf_budget") remaining",
        "inline": true
      },
      {
        "name": "📈 Key Insights",
        "value": "• Services monitored: 8\n• SLOs met: $((8 - overall_violations))/8\n• Reporting period: 30 days",
        "inline": false
      },
      {
        "name": "💡 Recommendations",
        "value": "$(
            if [ "$overall_violations" -eq 0 ]; then
                echo '• All services meeting reliability targets ✅\n• Continue current deployment practices\n• Consider new feature rollouts'
            elif [ "$overall_violations" -le 2 ]; then
                echo '• Review services with low error budgets\n• Investigate recent incidents\n• Consider deployment freeze for affected services'
            else
                echo '• 🚨 Multiple SLO violations detected\n• Implement deployment freeze\n• Focus on reliability improvements\n• Schedule blameless postmortems'
            fi
        )",
        "inline": false
      }
    ],
    "footer": {
      "text": "Generated by homelab SLO framework • Next report: $(date -d 'next month' '+%B 1, %Y')"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }]
}
EOF

# ============================================================================
# SEND TO DISCORD
# ============================================================================
log_section "Sending report to Discord..."

# Get Discord webhook URL from alert-discord-relay container
DISCORD_WEBHOOK=$(podman exec alert-discord-relay env | grep DISCORD_WEBHOOK_URL | cut -d= -f2)

# Send directly to Discord API
if curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$DISCORD_PAYLOAD" \
    "$DISCORD_WEBHOOK" | grep -q "^20"; then
    log "${GREEN}✓ Monthly SLO report sent to Discord successfully${NC}"
    exit_code=0
else
    log "${RED}✗ Failed to send report to Discord${NC}"
    log "${YELLOW}  Check Discord webhook configuration${NC}"
    exit_code=1
fi

log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${GREEN}Report generation complete!${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

exit $exit_code
