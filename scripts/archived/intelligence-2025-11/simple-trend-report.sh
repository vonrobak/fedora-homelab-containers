#!/usr/bin/env bash
#
# Simple Homelab Trend Report
# Quick intelligence report from snapshots
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/snapshot-parser.sh"

# Get snapshots
mapfile -t SNAPSHOTS < <(get_all_snapshots)
TOTAL="${#SNAPSHOTS[@]}"

if [[ $TOTAL -lt 2 ]]; then
    echo "Need at least 2 snapshots. Found: $TOTAL"
    exit 1
fi

OLDEST="${SNAPSHOTS[0]}"
LATEST="${SNAPSHOTS[-1]}"

echo "# Homelab Intelligence Report"
echo ""
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Snapshots analyzed: $TOTAL"
echo "Period: $(get_snapshot_timestamp "$OLDEST") to $(get_snapshot_timestamp "$LATEST")"
echo ""

# System Memory Trend
echo "## System Memory Trend"
echo ""
MEM_FIRST=$(extract_system_memory "$OLDEST")
MEM_LAST=$(extract_system_memory "$LATEST")
MEM_CHANGE=$((MEM_LAST - MEM_FIRST))
echo "- Start: ${MEM_FIRST}MB"
echo "- Current: ${MEM_LAST}MB"
echo "- Change: ${MEM_CHANGE}MB"
if [[ $MEM_CHANGE -gt 100 ]]; then
    echo "- **Warning**: Memory increased significantly"
fi
echo ""

# System Disk Trend
echo "## System Disk Trend"
echo ""
DISK_FIRST=$(extract_system_disk_used "$OLDEST")
DISK_LAST=$(extract_system_disk_used "$LATEST")
DISK_TOTAL=$(jq -r '.storage.system_disk.total_gb' "$LATEST")
echo "- Start: ${DISK_FIRST}GB"
echo "- Current: ${DISK_LAST}GB / ${DISK_TOTAL}GB"
DISK_CHANGE=$(echo "$DISK_LAST - $DISK_FIRST" | bc)
echo "- Growth: ${DISK_CHANGE}GB"
if (( $(echo "$DISK_LAST / $DISK_TOTAL * 100 > 75" | bc -l) )); then
    echo "- **Warning**: Disk usage above 75%"
fi
echo ""

# BTRFS Pool Trend
echo "## BTRFS Pool Trend"
echo ""
BTRFS_FIRST=$(extract_btrfs_used "$OLDEST")
BTRFS_LAST=$(extract_btrfs_used "$LATEST")
BTRFS_TOTAL=$(jq -r '.storage.btrfs_pool.total_gb' "$LATEST")
echo "- Start: ${BTRFS_FIRST}GB"
echo "- Current: ${BTRFS_LAST}GB / ${BTRFS_TOTAL}GB"
BTRFS_CHANGE=$(echo "$BTRFS_LAST - $BTRFS_FIRST" | bc)
echo "- Growth: ${BTRFS_CHANGE}GB"
echo ""

# Service Health
echo "## Service Health Status"
echo ""
HEALTHY=$(extract_healthy_count "$LATEST")
UNHEALTHY=$(extract_unhealthy_count "$LATEST")
SERVICES=$(extract_service_count "$LATEST")
echo "- Total Services: $SERVICES"
echo "- Healthy: $HEALTHY"
echo "- Unhealthy: $UNHEALTHY"
if [[ $UNHEALTHY -gt 0 ]]; then
    echo "- **Action Required**: Investigate unhealthy services"
fi
echo ""

# Top Memory Users
echo "## Top Memory Consumers"
echo ""
SERVICES_LIST=$(get_service_names "$LATEST")
while IFS= read -r service; do
    MEM=$(extract_service_memory "$LATEST" "$service")
    if [[ "$MEM" != "0" && "$MEM" != "null" ]]; then
        echo "$service $MEM"
    fi
done <<< "$SERVICES_LIST" | sort -k2 -rn | head -5 | while read -r svc mem; do
    echo "- $svc: ${mem}MB"
done

echo ""
echo "---"
echo "For detailed analysis, run: ./scripts/intelligence/analyze-trends.sh"
