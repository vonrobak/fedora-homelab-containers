#!/bin/bash
# SLO Trend Analysis and Calibration Script
# Created: 2026-01-09
# Purpose: Analyze collected SLO data to recommend target calibration
#
# Usage: ./analyze-slo-trends.sh [month]
#   month: Optional YYYY-MM format (default: current month)
#
# This script analyzes daily SLO snapshots to calculate:
# - Mean availability per service
# - 95th percentile availability (recommended SLO target)
# - Min/max availability range
# - Days in compliance vs violation
# - Error budget burn rate trends

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
SNAPSHOT_DIR="$HOME/containers/data/slo-snapshots"
MONTH="${1:-$(date +%Y-%m)}"
SNAPSHOT_FILE="$SNAPSHOT_DIR/slo-daily-${MONTH}.csv"

log() { echo -e "${1}"; }
log_section() { echo ""; log "${BLUE}▶ ${1}${NC}"; }

# Check if snapshot file exists
if [ ! -f "$SNAPSHOT_FILE" ]; then
    log "${RED}✗ No snapshot file found for $MONTH${NC}"
    log "${YELLOW}  Expected: $SNAPSHOT_FILE${NC}"
    log "${YELLOW}  Run daily-slo-snapshot.sh to start collecting data${NC}"
    exit 1
fi

log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${CYAN}   SLO TREND ANALYSIS - $MONTH${NC}"
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# Count data points
total_snapshots=$(tail -n +2 "$SNAPSHOT_FILE" | wc -l)
unique_days=$(tail -n +2 "$SNAPSHOT_FILE" | cut -d',' -f1 | cut -d' ' -f1 | sort -u | wc -l)

log_section "Data Collection Summary"
log "  Snapshot file: $SNAPSHOT_FILE"
log "  Total data points: $total_snapshots"
log "  Unique days: $unique_days"
log "  Services tracked: 5 (jellyfin, immich, authelia, traefik, nextcloud)"

# Analyze each service
for service in jellyfin immich authelia traefik nextcloud; do
    log_section "Analysis: $service"

    # Extract service data
    service_data=$(grep ",$service," "$SNAPSHOT_FILE" || true)

    if [ -z "$service_data" ]; then
        log "${YELLOW}  No data collected for $service${NC}"
        continue
    fi

    # Get current target
    current_target=$(echo "$service_data" | head -1 | cut -d',' -f4)

    # Calculate statistics using awk
    stats=$(echo "$service_data" | awk -F',' '
    {
        availability = $3 * 100
        values[NR] = availability
        sum += availability
        if (availability < min || NR == 1) min = availability
        if (availability > max || NR == 1) max = availability
        if ($6 == 1) compliant++
        else violations++
    }
    END {
        # Sort values for percentile calculation
        n = asort(values)
        p95_idx = int(n * 0.95)
        p95 = values[p95_idx]

        mean = sum / NR
        printf "%.2f|%.2f|%.2f|%.2f|%d|%d|%d\n", mean, p95, min, max, compliant, violations, NR
    }')

    mean=$(echo "$stats" | cut -d'|' -f1)
    p95=$(echo "$stats" | cut -d'|' -f2)
    min=$(echo "$stats" | cut -d'|' -f3)
    max=$(echo "$stats" | cut -d'|' -f4)
    compliant=$(echo "$stats" | cut -d'|' -f5)
    violations=$(echo "$stats" | cut -d'|' -f6)
    samples=$(echo "$stats" | cut -d'|' -f7)

    current_target_pct=$(echo "$current_target * 100" | bc -l | xargs printf "%.2f")

    log "  ${CYAN}Current Target:${NC} $current_target_pct%"
    log "  ${CYAN}Actual Performance (30-day rolling):${NC}"
    log "    Mean:        ${mean}%"
    log "    95th %ile:   ${GREEN}${p95}%${NC} ${YELLOW}(recommended SLO target)${NC}"
    log "    Min:         ${min}%"
    log "    Max:         ${max}%"
    log "  ${CYAN}Compliance:${NC}"
    log "    Compliant:   $compliant days"
    log "    Violations:  $violations days"
    log "    Data points: $samples"

    # Recommendation
    log "  ${CYAN}Recommendation:${NC}"
    p95_compare=$(echo "$p95 >= $current_target_pct" | bc -l)
    if [ "$p95_compare" = "1" ]; then
        log "    ${GREEN}✓ Current target ($current_target_pct%) is achievable${NC}"
        log "      (95th percentile: ${p95}% meets target)"
    else
        recommended=$(echo "$p95 - 0.5" | bc -l | xargs printf "%.1f")
        log "    ${YELLOW}⚠ Consider adjusting target to ${recommended}%${NC}"
        log "      (95th percentile: ${p95}% below current target $current_target_pct%)"
        log "      (Recommended: 0.5% below p95 for buffer)"
    fi
done

log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"
log "${CYAN}Key Insights:${NC}"
log ""
log "• ${GREEN}95th percentile${NC} represents realistic achievable reliability"
log "• Targets set at p95 mean 5% of days may have minor incidents"
log "• Current rolling window includes December incidents"
log "• Re-run this analysis Feb 1 with full January data"
log "• More data points = more accurate calibration"
log ""
log "${CYAN}Next Steps:${NC}"
log "1. Continue daily snapshot collection (automatic via timer)"
log "2. Re-run analysis on Feb 1, 2026 with 22+ days of January data"
log "3. Update SLO targets in prometheus rules if recommended"
log "4. Document calibration decisions in journal"
log ""
log "${CYAN}═══════════════════════════════════════════════════════${NC}"

exit 0
