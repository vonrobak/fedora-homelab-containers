#!/bin/bash
# Automated maintenance cleanup script for homelab storage management
# Part of Storage Management Automation (Prospect #1)
# Created: 2025-11-24
#
# This script safely cleans up system resources to prevent disk exhaustion:
# - Rotates systemd journal logs (keeps 30 days)
# - Prunes unused container images and volumes
# - Generates cleanup report
#
# Safe to run automatically via systemd timer

set -euo pipefail

# Configuration
JOURNAL_RETENTION="30d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${HOME}/containers/data/maintenance-logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/cleanup-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    log "${BLUE}▶ ${1}${NC}"
}

# Error handler
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Start cleanup report
log "${BLUE}═══════════════════════════════════════════════════════${NC}"
log "${BLUE}   HOMELAB MAINTENANCE CLEANUP${NC}"
log "${BLUE}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
log "${BLUE}═══════════════════════════════════════════════════════${NC}"

# ============================================================================
# SECTION 1: Pre-cleanup system state
# ============================================================================
log_section "Pre-Cleanup System State"

DISK_BEFORE=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
log "System SSD usage: ${DISK_BEFORE}"

JOURNAL_SIZE_BEFORE=$(journalctl --user --disk-usage 2>/dev/null | awk '{print $NF}' || echo "unknown")
log "Journal size: ${JOURNAL_SIZE_BEFORE}"

PODMAN_SIZE_BEFORE=$(podman system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "unknown")
log "Container images: ${PODMAN_SIZE_BEFORE}"

# ============================================================================
# SECTION 2: Journal cleanup
# ============================================================================
log_section "Cleaning Journal Logs (retain ${JOURNAL_RETENTION})"

if journalctl --user --vacuum-time="${JOURNAL_RETENTION}" >> "${LOG_FILE}" 2>&1; then
    JOURNAL_SIZE_AFTER=$(journalctl --user --disk-usage 2>/dev/null | awk '{print $NF}' || echo "unknown")
    log "${GREEN}✓ Journal cleanup successful${NC}"
    log "  Before: ${JOURNAL_SIZE_BEFORE}"
    log "  After:  ${JOURNAL_SIZE_AFTER}"
else
    log "${YELLOW}⚠ Journal cleanup had warnings (see log)${NC}"
fi

# ============================================================================
# SECTION 3: Container image and volume cleanup
# ============================================================================
log_section "Cleaning Unused Container Images and Volumes"

# Show what will be removed
log "Checking for reclaimable space..."
podman system df >> "${LOG_FILE}" 2>&1

# Prune unused images (not used by running containers)
if podman image prune -af >> "${LOG_FILE}" 2>&1; then
    log "${GREEN}✓ Unused images pruned${NC}"
else
    log "${YELLOW}⚠ Image pruning had warnings (see log)${NC}"
fi

# Prune unused volumes (not used by containers)
if podman volume prune -f >> "${LOG_FILE}" 2>&1; then
    log "${GREEN}✓ Unused volumes pruned${NC}"
else
    log "${YELLOW}⚠ Volume pruning had warnings (see log)${NC}"
fi

PODMAN_SIZE_AFTER=$(podman system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "unknown")
log "  Before: ${PODMAN_SIZE_BEFORE}"
log "  After:  ${PODMAN_SIZE_AFTER}"

# ============================================================================
# SECTION 4: Old log cleanup
# ============================================================================
log_section "Cleaning Old Maintenance Logs (>60 days)"

OLD_LOGS=$(find "${LOG_DIR}" -name "cleanup-*.log" -mtime +60 -type f 2>/dev/null | wc -l)
if [ "${OLD_LOGS}" -gt 0 ]; then
    find "${LOG_DIR}" -name "cleanup-*.log" -mtime +60 -type f -delete
    log "${GREEN}✓ Removed ${OLD_LOGS} old maintenance logs${NC}"
else
    log "No old logs to remove"
fi

# Also clean old backup logs if directory exists
if [ -d "${HOME}/containers/data/backup-logs" ]; then
    OLD_BACKUP_LOGS=$(find "${HOME}/containers/data/backup-logs" -name "*.log" -mtime +60 -type f 2>/dev/null | wc -l)
    if [ "${OLD_BACKUP_LOGS}" -gt 0 ]; then
        find "${HOME}/containers/data/backup-logs" -name "*.log" -mtime +60 -type f -delete
        log "${GREEN}✓ Removed ${OLD_BACKUP_LOGS} old backup logs${NC}"
    else
        log "No old backup logs to remove"
    fi
fi

# ============================================================================
# SECTION 5: Remediation log rotation
# ============================================================================
log_section "Rotating Remediation Logs"

REMEDIATION_LOG_DIR="${HOME}/containers/.claude/data/remediation-logs"
if [ -d "${REMEDIATION_LOG_DIR}" ]; then
    # Delete logs older than 90 days
    OLD_REMEDIATION=$(find "${REMEDIATION_LOG_DIR}" -name "*.log" -mtime +90 -type f 2>/dev/null | wc -l)
    if [ "${OLD_REMEDIATION}" -gt 0 ]; then
        find "${REMEDIATION_LOG_DIR}" -name "*.log" -mtime +90 -type f -delete
        log "${GREEN}✓ Deleted ${OLD_REMEDIATION} remediation logs older than 90 days${NC}"
    fi

    # Compress logs older than 30 days (skip already-compressed)
    COMPRESS_REMEDIATION=$(find "${REMEDIATION_LOG_DIR}" -name "*.log" -mtime +30 -type f 2>/dev/null | wc -l)
    if [ "${COMPRESS_REMEDIATION}" -gt 0 ]; then
        find "${REMEDIATION_LOG_DIR}" -name "*.log" -mtime +30 -type f -exec gzip {} \;
        log "${GREEN}✓ Compressed ${COMPRESS_REMEDIATION} remediation logs older than 30 days${NC}"
    fi

    REMAINING=$(find "${REMEDIATION_LOG_DIR}" -type f 2>/dev/null | wc -l)
    log "Remediation logs remaining: ${REMAINING}"
else
    log "No remediation log directory found"
fi

# ============================================================================
# SECTION 6: Post-cleanup summary
# ============================================================================
log_section "Post-Cleanup System State"

DISK_AFTER=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
log "System SSD usage: ${DISK_AFTER}"

DISK_USAGE_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "${DISK_USAGE_PERCENT}" -lt 70 ]; then
    log "${GREEN}✓ Disk usage healthy (<70%)${NC}"
elif [ "${DISK_USAGE_PERCENT}" -lt 80 ]; then
    log "${YELLOW}⚠ Disk usage elevated (70-80%)${NC}"
else
    log "${RED}⚠ Disk usage critical (>80%) - manual intervention needed${NC}"
fi

# ============================================================================
# SECTION 7: Discord Notification
# ============================================================================
log_section "Sending Discord Notification"

# Calculate space freed (rough estimate based on before/after)
DISK_BEFORE_PCT=$(echo "${DISK_BEFORE}" | grep -oP '\(\K[0-9]+')
DISK_AFTER_PCT=$(echo "${DISK_AFTER}" | grep -oP '\(\K[0-9]+')

# Prepare Discord message payload (Alertmanager format)
DISCORD_PAYLOAD=$(cat <<EOF
{
  "version": "4",
  "groupKey": "{}:{alertname=\"MaintenanceCleanup\"}",
  "status": "firing",
  "receiver": "discord-default",
  "groupLabels": {
    "alertname": "MaintenanceCleanup"
  },
  "commonLabels": {
    "alertname": "MaintenanceCleanup",
    "severity": "info",
    "component": "maintenance"
  },
  "commonAnnotations": {
    "summary": "✅ Weekly Maintenance Cleanup Complete",
    "description": "Automated cleanup successful\\n\\n**Disk Usage:** ${DISK_AFTER}\\n**Status:** $([ "${DISK_USAGE_PERCENT}" -lt 70 ] && echo "Healthy ✅" || echo "Elevated ⚠️")\\n\\n**Actions:**\\n- Journal logs vacuumed\\n- Container images: ${PODMAN_SIZE_BEFORE} → ${PODMAN_SIZE_AFTER}\\n- Old logs cleaned\\n\\nFull log: ${LOG_FILE}"
  },
  "externalURL": "http://homelab-maintenance",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "MaintenanceCleanup",
        "severity": "info",
        "component": "maintenance"
      },
      "annotations": {
        "summary": "✅ Weekly Maintenance Cleanup Complete",
        "description": "Disk: ${DISK_AFTER} ($([ "${DISK_USAGE_PERCENT}" -lt 70 ] && echo "healthy" || echo "elevated"))"
      },
      "startsAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
      "endsAt": "0001-01-01T00:00:00Z",
      "generatorURL": "http://homelab-maintenance/cleanup"
    }
  ]
}
EOF
)

# Send notification to Discord relay via Prometheus container (on monitoring network)
if podman exec prometheus wget -q -O- --post-data="${DISCORD_PAYLOAD}" \
    --header="Content-Type: application/json" \
    http://alert-discord-relay:9095/webhook \
    >/dev/null 2>&1; then
    log "${GREEN}✓ Discord notification sent${NC}"
else
    log "${YELLOW}⚠ Discord notification failed (non-critical)${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
log ""
log "${GREEN}Cleanup completed successfully!${NC}"
log "Full log: ${LOG_FILE}"
log "${BLUE}═══════════════════════════════════════════════════════${NC}"

exit 0
