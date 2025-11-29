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

# Counters
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
IMAGES_SCANNED=0
IMAGES_WITH_VULNS=0

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

        # Parse results
        local critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$report_file" 2>/dev/null || echo "0")
        local high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$report_file" 2>/dev/null || echo "0")
        local medium=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$report_file" 2>/dev/null || echo "0")
        local low=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="LOW")] | length' "$report_file" 2>/dev/null || echo "0")

        # Update global counters
        CRITICAL_COUNT=$((CRITICAL_COUNT + critical))
        HIGH_COUNT=$((HIGH_COUNT + high))
        MEDIUM_COUNT=$((MEDIUM_COUNT + medium))
        LOW_COUNT=$((LOW_COUNT + low))
        IMAGES_SCANNED=$((IMAGES_SCANNED + 1))

        if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
            IMAGES_WITH_VULNS=$((IMAGES_WITH_VULNS + 1))
            log "  ${RED}CRITICAL: $critical${NC} | ${YELLOW}HIGH: $high${NC} | MEDIUM: $medium | LOW: $low"

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

    if [ "$CRITICAL_COUNT" -eq 0 ] && [ "$HIGH_COUNT" -eq 0 ]; then
        return
    fi

    # Get Discord webhook URL
    local DISCORD_WEBHOOK=$(podman exec alert-discord-relay env 2>/dev/null | grep DISCORD_WEBHOOK_URL | cut -d= -f2 || echo "")

    if [ -z "$DISCORD_WEBHOOK" ]; then
        log "${YELLOW}Discord webhook not found, skipping notification${NC}"
        return
    fi

    # Determine color based on severity
    local color="16753920"  # Orange for high
    local emoji="⚠️"
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        color="15158332"  # Red for critical
        emoji="🚨"
    fi

    # Build payload
    read -r -d '' PAYLOAD <<EOF || true
{
  "embeds": [{
    "title": "${emoji} Vulnerability Scan Alert",
    "description": "Trivy scan completed with findings requiring attention.",
    "color": ${color},
    "fields": [
      {
        "name": "Images Scanned",
        "value": "${IMAGES_SCANNED}",
        "inline": true
      },
      {
        "name": "Images with Issues",
        "value": "${IMAGES_WITH_VULNS}",
        "inline": true
      },
      {
        "name": "Vulnerabilities",
        "value": "Critical: ${CRITICAL_COUNT}\nHigh: ${HIGH_COUNT}\nMedium: ${MEDIUM_COUNT}",
        "inline": true
      }
    ],
    "footer": {
      "text": "Homelab Security • Reports: ~/containers/data/security-reports/"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  }]
}
EOF

    curl -s -o /dev/null \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$DISCORD_WEBHOOK"

    log "${GREEN}Discord notification sent${NC}"
}

# ============================================================================
# Summary Report
# ============================================================================

generate_summary() {
    local summary_file="${REPORT_DIR}/vulnerability-summary-${DATE_ONLY}.json"

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
  "severity_filter": "${SEVERITY}",
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

    # Print summary
    log_quiet ""
    log_quiet "${CYAN}═══════════════════════════════════════════════${NC}"
    log_quiet "${CYAN}                 SUMMARY${NC}"
    log_quiet "${CYAN}═══════════════════════════════════════════════${NC}"
    log_quiet ""
    log_quiet "Images scanned:    ${IMAGES_SCANNED}"
    log_quiet "Images with issues: ${IMAGES_WITH_VULNS}"
    log_quiet ""
    log_quiet "Vulnerabilities found:"
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
    log_quiet "Reports: ${REPORT_DIR}/"
    log_quiet ""

    # Send Discord notification if enabled
    send_discord_notification

    # Exit code based on findings
    if [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ]; then
        log_quiet "${RED}Vulnerabilities requiring attention found!${NC}"
        exit 1
    else
        log_quiet "${GREEN}No critical or high vulnerabilities found.${NC}"
        exit 0
    fi
}

main "$@"
