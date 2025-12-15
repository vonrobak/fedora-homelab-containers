#!/bin/bash
# scan-vulnerabilities.sh
# Container Image Vulnerability Scanner using Trivy
#
# Purpose: Scan container images for known CVEs
# Run: ./scripts/scan-vulnerabilities.sh [options]
#
# Options:
#   --image IMAGE    Scan specific image
#   --all            Scan all running container images
#   --severity LEVEL Filter by severity (CRITICAL,HIGH,MEDIUM,LOW)
#   --json           Output JSON report only
#   --notify         Send Discord notification for critical findings
#   --quiet          Minimal output
#
# Exit codes: 0 = no critical/high CVEs, 1 = vulnerabilities found, 2 = error
#
# Status: ACTIVE
# Created: 2025-11-29

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${HOME}/containers/data/security-reports"
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
DATE_ONLY=$(date '+%Y-%m-%d')

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
SCAN_ALL=false
SPECIFIC_IMAGE=""
SEVERITY="CRITICAL,HIGH"
JSON_ONLY=false
NOTIFY=false
QUIET=false

# Counters - Raw (all findings)
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
IMAGES_SCANNED=0
IMAGES_WITH_VULNS=0

# Counters - Actionable (filtered, real risks)
ACTIONABLE_CRITICAL=0
ACTIONABLE_HIGH=0
ACTIONABLE_MEDIUM=0
ACTIONABLE_LOW=0
ACTIONABLE_IMAGES_WITH_VULNS=0

# False positive packages (build-time only, not runtime risks)
FALSE_POSITIVE_PACKAGES="linux-libc-dev"

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  --image IMAGE    Scan specific image (e.g., docker.io/jellyfin/jellyfin:latest)
  --all            Scan all running container images
  --severity LEVEL Severity filter (default: CRITICAL,HIGH)
                   Options: CRITICAL, HIGH, MEDIUM, LOW (comma-separated)
  --json           Output JSON report only (no terminal output)
  --notify         Send Discord notification for critical/high findings
  --quiet          Minimal output (summary only)
  -h, --help       Show this help message

Examples:
  $(basename "$0") --all                    # Scan all running containers
  $(basename "$0") --image jellyfin:latest  # Scan specific image
  $(basename "$0") --all --notify           # Scan all and notify on findings

Exit Codes:
  0 - No critical/high vulnerabilities found
  1 - Critical or high vulnerabilities found
  2 - Error during scan
EOF
    exit 0
}

log() {
    if [ "$JSON_ONLY" = false ] && [ "$QUIET" = false ]; then
        echo -e "$1"
    fi
}

log_quiet() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "$1"
    fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            SPECIFIC_IMAGE="$2"
            shift 2
            ;;
        --all)
            SCAN_ALL=true
            shift
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --json)
            JSON_ONLY=true
            shift
            ;;
        --notify)
            NOTIFY=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [ "$SCAN_ALL" = false ] && [ -z "$SPECIFIC_IMAGE" ]; then
    echo "Error: Must specify --all or --image IMAGE"
    usage
fi

# Ensure report directory exists
mkdir -p "${REPORT_DIR}"

# ============================================================================
# Filtering Functions
# ============================================================================

filter_actionable_vulns() {
    local report_file="$1"
    local severity="$2"

    # Count vulnerabilities excluding false positive packages
    jq --arg severity "$severity" --arg false_pos "$FALSE_POSITIVE_PACKAGES" '[
        .Results[]?.Vulnerabilities[]? |
        select(.Severity == $severity) |
        select(.PkgName | IN($false_pos | split(" ")[]) | not)
    ] | length' "$report_file" 2>/dev/null || echo "0"
}

# ============================================================================
# Scanning Functions
# ============================================================================

scan_image() {
    local image="$1"
    local image_name=$(echo "$image" | sed 's|.*/||' | sed 's/:/_/g')
    local report_file="${REPORT_DIR}/trivy-${image_name}-${DATE_ONLY}.json"

    log "${BLUE}Scanning:${NC} $image"

    # Run Trivy scan
    if trivy image \
        --severity "${SEVERITY}" \
        --format json \
        --output "${report_file}" \
        --quiet \
        "$image" 2>/dev/null; then

        # Parse results - RAW counts (all findings)
        local critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$report_file" 2>/dev/null || echo "0")
        local high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$report_file" 2>/dev/null || echo "0")
        local medium=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$report_file" 2>/dev/null || echo "0")
        local low=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="LOW")] | length' "$report_file" 2>/dev/null || echo "0")

        # Parse results - ACTIONABLE counts (filtered)
        local actionable_critical=$(filter_actionable_vulns "$report_file" "CRITICAL")
        local actionable_high=$(filter_actionable_vulns "$report_file" "HIGH")
        local actionable_medium=$(filter_actionable_vulns "$report_file" "MEDIUM")
        local actionable_low=$(filter_actionable_vulns "$report_file" "LOW")

        # Update global counters - RAW
        CRITICAL_COUNT=$((CRITICAL_COUNT + critical))
        HIGH_COUNT=$((HIGH_COUNT + high))
        MEDIUM_COUNT=$((MEDIUM_COUNT + medium))
        LOW_COUNT=$((LOW_COUNT + low))
        IMAGES_SCANNED=$((IMAGES_SCANNED + 1))

        # Update global counters - ACTIONABLE
        ACTIONABLE_CRITICAL=$((ACTIONABLE_CRITICAL + actionable_critical))
        ACTIONABLE_HIGH=$((ACTIONABLE_HIGH + actionable_high))
        ACTIONABLE_MEDIUM=$((ACTIONABLE_MEDIUM + actionable_medium))
        ACTIONABLE_LOW=$((ACTIONABLE_LOW + actionable_low))

        if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
            IMAGES_WITH_VULNS=$((IMAGES_WITH_VULNS + 1))
            log "  ${RED}CRITICAL: $critical${NC} | ${YELLOW}HIGH: $high${NC} | MEDIUM: $medium | LOW: $low"

            # Show actionable count if different
            if [ "$actionable_critical" -ne "$critical" ] || [ "$actionable_high" -ne "$high" ]; then
                log "  ${CYAN}Actionable:${NC} ${RED}CRIT: $actionable_critical${NC} | ${YELLOW}HIGH: $actionable_high${NC} (filtered false positives)"
            fi
        fi

        if [ "$actionable_critical" -gt 0 ] || [ "$actionable_high" -gt 0 ]; then
            ACTIONABLE_IMAGES_WITH_VULNS=$((ACTIONABLE_IMAGES_WITH_VULNS + 1))

            # Show top CVEs for critical/high
            if [ "$QUIET" = false ] && [ "$JSON_ONLY" = false ]; then
                if [ "$critical" -gt 0 ]; then
                    log "  ${RED}Critical CVEs:${NC}"
                    jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | "    - \(.VulnerabilityID): \(.Title // .Description | .[0:60])..."' "$report_file" 2>/dev/null | head -3
                fi
                if [ "$high" -gt 0 ]; then
                    log "  ${YELLOW}High CVEs:${NC}"
                    jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH") | "    - \(.VulnerabilityID): \(.Title // .Description | .[0:60])..."' "$report_file" 2>/dev/null | head -3
                fi
            fi
        else
            log "  ${GREEN}No critical/high vulnerabilities${NC}"
        fi

        return 0
    else
        log "  ${RED}Scan failed${NC}"
        return 1
    fi
}

get_running_images() {
    # Get unique images from running containers
    podman ps --format "{{.Image}}" 2>/dev/null | sort -u
}

# ============================================================================
# Discord Notification
# ============================================================================

send_discord_notification() {
    if [ "$NOTIFY" = false ]; then
        return
    fi

    # Get trend data
    local prev_date=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null)
    local prev_summary="${REPORT_DIR}/vulnerability-summary-${prev_date}.json"
    local prev_actionable_critical=0
    local prev_actionable_high=0

    if [ -f "$prev_summary" ]; then
        prev_actionable_critical=$(jq -r '.actionable_vulnerabilities.critical // 0' "$prev_summary" 2>/dev/null)
        prev_actionable_high=$(jq -r '.actionable_vulnerabilities.high // 0' "$prev_summary" 2>/dev/null)
    fi

    local crit_change=$((ACTIONABLE_CRITICAL - prev_actionable_critical))
    local high_change=$((ACTIONABLE_HIGH - prev_actionable_high))

    # Only notify if:
    # 1. Actionable vulnerabilities exist AND have increased, OR
    # 2. Actionable critical vulnerabilities > 10
    local should_notify=false
    if [ "$ACTIONABLE_CRITICAL" -gt 10 ]; then
        should_notify=true
    elif [ "$crit_change" -gt 0 ] || [ "$high_change" -gt 5 ]; then
        should_notify=true
    fi

    if [ "$should_notify" = false ]; then
        log "${GREEN}No actionable increase in vulnerabilities, skipping Discord notification${NC}"
        return
    fi

    # Get Discord webhook URL
    local DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

    if [ -z "$DISCORD_WEBHOOK" ]; then
        log "${YELLOW}Discord webhook not found, skipping notification${NC}"
        return
    fi

    # Determine color and emoji based on severity and trend
    local color="16753920"  # Orange
    local emoji="⚠️"
    local status_text="Actionable vulnerabilities found"

    if [ "$ACTIONABLE_CRITICAL" -gt 10 ]; then
        color="15158332"  # Red
        emoji="🚨"
        status_text="High number of critical vulnerabilities"
    elif [ "$crit_change" -gt 0 ]; then
        color="15158332"  # Red
        emoji="📈"
        status_text="Critical vulnerabilities increased"
    elif [ "$high_change" -gt 5 ]; then
        color="16753920"  # Orange
        emoji="📈"
        status_text="High-severity vulnerabilities increased"
    fi

    # Build trend text
    local trend_text=""
    if [ "$crit_change" -ne 0 ] || [ "$high_change" -ne 0 ]; then
        trend_text="**Trend (vs. ${prev_date}):**\n"
        [ "$crit_change" -gt 0 ] && trend_text+="Critical: +${crit_change} ⬆️\n" || trend_text+="Critical: ${crit_change}\n"
        [ "$high_change" -gt 0 ] && trend_text+="High: +${high_change} ⬆️" || trend_text+="High: ${high_change}"
    fi

    # Build payload
    read -r -d '' PAYLOAD <<EOF || true
{
  "embeds": [{
    "title": "${emoji} Vulnerability Scan Alert",
    "description": "${status_text}",
    "color": ${color},
    "fields": [
      {
        "name": "Actionable Vulnerabilities",
        "value": "Critical: **${ACTIONABLE_CRITICAL}**\nHigh: **${ACTIONABLE_HIGH}**\nMedium: ${ACTIONABLE_MEDIUM}",
        "inline": true
      },
      {
        "name": "Total Findings (Raw)",
        "value": "Critical: ${CRITICAL_COUNT}\nHigh: ${HIGH_COUNT}\nFiltered: $((CRITICAL_COUNT + HIGH_COUNT - ACTIONABLE_CRITICAL - ACTIONABLE_HIGH))",
        "inline": true
      },
      {
        "name": "Images",
        "value": "Scanned: ${IMAGES_SCANNED}\nWith Issues: ${ACTIONABLE_IMAGES_WITH_VULNS}",
        "inline": true
      }${trend_text:+,
      {
        "name": "Trend",
        "value": "${trend_text}",
        "inline": false
      }}
    ],
    "footer": {
      "text": "Homelab Security • Reports: ~/containers/data/security-reports/ • Filtered: ${FALSE_POSITIVE_PACKAGES}"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }]
}
EOF

    curl -s -o /dev/null \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$DISCORD_WEBHOOK"

    log "${GREEN}Discord notification sent (actionable vulnerabilities: CRIT=${ACTIONABLE_CRITICAL}, HIGH=${ACTIONABLE_HIGH})${NC}"
}

# ============================================================================
# Summary Report
# ============================================================================

generate_summary() {
    local summary_file="${REPORT_DIR}/vulnerability-summary-${DATE_ONLY}.json"

    # Get previous week's data for trend analysis
    local prev_date=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null)
    local prev_summary="${REPORT_DIR}/vulnerability-summary-${prev_date}.json"

    local prev_actionable_critical=0
    local prev_actionable_high=0
    if [ -f "$prev_summary" ]; then
        prev_actionable_critical=$(jq -r '.actionable_vulnerabilities.critical // 0' "$prev_summary" 2>/dev/null)
        prev_actionable_high=$(jq -r '.actionable_vulnerabilities.high // 0' "$prev_summary" 2>/dev/null)
    fi

    cat > "$summary_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "date": "${DATE_ONLY}",
  "images_scanned": ${IMAGES_SCANNED},
  "images_with_vulnerabilities": ${IMAGES_WITH_VULNS},
  "total_vulnerabilities": {
    "critical": ${CRITICAL_COUNT},
    "high": ${HIGH_COUNT},
    "medium": ${MEDIUM_COUNT},
    "low": ${LOW_COUNT}
  },
  "actionable_vulnerabilities": {
    "critical": ${ACTIONABLE_CRITICAL},
    "high": ${ACTIONABLE_HIGH},
    "medium": ${ACTIONABLE_MEDIUM},
    "low": ${ACTIONABLE_LOW},
    "images_affected": ${ACTIONABLE_IMAGES_WITH_VULNS},
    "false_positives_filtered": $((CRITICAL_COUNT + HIGH_COUNT - ACTIONABLE_CRITICAL - ACTIONABLE_HIGH))
  },
  "trend": {
    "previous_scan_date": "${prev_date}",
    "actionable_critical_change": $((ACTIONABLE_CRITICAL - prev_actionable_critical)),
    "actionable_high_change": $((ACTIONABLE_HIGH - prev_actionable_high))
  },
  "severity_filter": "${SEVERITY}",
  "false_positive_packages": "${FALSE_POSITIVE_PACKAGES}",
  "reports_directory": "${REPORT_DIR}"
}
EOF

    if [ "$JSON_ONLY" = true ]; then
        cat "$summary_file"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    log ""
    log "${CYAN}═══════════════════════════════════════════════${NC}"
    log "${CYAN}     CONTAINER VULNERABILITY SCANNER${NC}"
    log "${CYAN}═══════════════════════════════════════════════${NC}"
    log ""
    log "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Severity filter: ${SEVERITY}"
    log ""

    if [ -n "$SPECIFIC_IMAGE" ]; then
        # Scan specific image
        scan_image "$SPECIFIC_IMAGE"
    elif [ "$SCAN_ALL" = true ]; then
        # Scan all running container images
        local images=$(get_running_images)

        if [ -z "$images" ]; then
            log "${YELLOW}No running containers found${NC}"
            exit 0
        fi

        log "Found $(echo "$images" | wc -l) unique images to scan"
        log ""

        while IFS= read -r image; do
            scan_image "$image" || true
            log ""
        done <<< "$images"
    fi

    # Generate summary
    generate_summary

    # Get previous week's data for trend display
    local prev_date=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null)
    local prev_summary="${REPORT_DIR}/vulnerability-summary-${prev_date}.json"
    local prev_actionable_critical=0
    local prev_actionable_high=0

    if [ -f "$prev_summary" ]; then
        prev_actionable_critical=$(jq -r '.actionable_vulnerabilities.critical // 0' "$prev_summary" 2>/dev/null)
        prev_actionable_high=$(jq -r '.actionable_vulnerabilities.high // 0' "$prev_summary" 2>/dev/null)
    fi

    local crit_change=$((ACTIONABLE_CRITICAL - prev_actionable_critical))
    local high_change=$((ACTIONABLE_HIGH - prev_actionable_high))

    # Print summary
    log_quiet ""
    log_quiet "${CYAN}═══════════════════════════════════════════════${NC}"
    log_quiet "${CYAN}                 SUMMARY${NC}"
    log_quiet "${CYAN}═══════════════════════════════════════════════${NC}"
    log_quiet ""
    log_quiet "Images scanned:     ${IMAGES_SCANNED}"
    log_quiet "Images with issues: ${IMAGES_WITH_VULNS} (raw) / ${ACTIONABLE_IMAGES_WITH_VULNS} (actionable)"
    log_quiet ""
    log_quiet "RAW Vulnerabilities (all findings):"
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        log_quiet "  ${RED}CRITICAL: ${CRITICAL_COUNT}${NC}"
    else
        log_quiet "  ${GREEN}CRITICAL: 0${NC}"
    fi
    if [ "$HIGH_COUNT" -gt 0 ]; then
        log_quiet "  ${YELLOW}HIGH: ${HIGH_COUNT}${NC}"
    else
        log_quiet "  ${GREEN}HIGH: 0${NC}"
    fi
    log_quiet "  MEDIUM: ${MEDIUM_COUNT}"
    log_quiet "  LOW: ${LOW_COUNT}"
    log_quiet ""
    log_quiet "${CYAN}ACTIONABLE Vulnerabilities (filtered):${NC}"
    if [ "$ACTIONABLE_CRITICAL" -gt 0 ]; then
        local crit_trend=""
        [ "$crit_change" -gt 0 ] && crit_trend=" (${RED}+${crit_change}⬆${NC})" || [ "$crit_change" -lt 0 ] && crit_trend=" (${GREEN}${crit_change}⬇${NC})"
        log_quiet "  ${RED}CRITICAL: ${ACTIONABLE_CRITICAL}${NC}${crit_trend}"
    else
        log_quiet "  ${GREEN}CRITICAL: 0${NC}"
    fi
    if [ "$ACTIONABLE_HIGH" -gt 0 ]; then
        local high_trend=""
        [ "$high_change" -gt 0 ] && high_trend=" (${RED}+${high_change}⬆${NC})" || [ "$high_change" -lt 0 ] && high_trend=" (${GREEN}${high_change}⬇${NC})"
        log_quiet "  ${YELLOW}HIGH: ${ACTIONABLE_HIGH}${NC}${high_trend}"
    else
        log_quiet "  ${GREEN}HIGH: 0${NC}"
    fi
    log_quiet "  MEDIUM: ${ACTIONABLE_MEDIUM}"
    log_quiet "  LOW: ${ACTIONABLE_LOW}"
    log_quiet ""
    log_quiet "False positives filtered: $((CRITICAL_COUNT + HIGH_COUNT - ACTIONABLE_CRITICAL - ACTIONABLE_HIGH)) (${FALSE_POSITIVE_PACKAGES})"
    log_quiet ""
    log_quiet "Reports: ${REPORT_DIR}/"
    log_quiet ""

    # Send Discord notification if enabled
    send_discord_notification

    # Exit code based on ACTIONABLE findings (not raw count)
    if [ "$ACTIONABLE_CRITICAL" -gt 0 ] || [ "$ACTIONABLE_HIGH" -gt 10 ]; then
        log_quiet "${RED}Actionable vulnerabilities requiring attention found!${NC}"
        exit 1
    else
        log_quiet "${GREEN}No actionable critical vulnerabilities (or <10 high-severity).${NC}"
        exit 0
    fi
}

main "$@"
