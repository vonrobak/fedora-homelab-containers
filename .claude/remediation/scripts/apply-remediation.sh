#!/bin/bash
#
# apply-remediation.sh
# Execute auto-remediation playbooks
#
# Usage: ./apply-remediation.sh --playbook PLAYBOOK [--dry-run] [--service SERVICE]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PLAYBOOK_DIR="../playbooks"
LOG_DIR="../../data/remediation-logs"
DRY_RUN=false
PLAYBOOK=""
SERVICE=""
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Usage: $0 --playbook PLAYBOOK [--service SERVICE] [--dry-run] [--force]"
            echo "Available playbooks: disk-cleanup, drift-reconciliation, service-restart, resource-pressure"
            exit 1
            ;;
    esac
done

if [[ -z "$PLAYBOOK" ]]; then
    echo -e "${RED}Error: --playbook required${NC}"
    exit 1
fi

PLAYBOOK_FILE="$PLAYBOOK_DIR/${PLAYBOOK}.yml"

if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo -e "${RED}Error: Playbook not found: $PLAYBOOK_FILE${NC}"
    exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/${PLAYBOOK}-${TIMESTAMP}.log"

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${BLUE}  AUTO-REMEDIATION: ${PLAYBOOK}${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log ""
log "Timestamp: $(date -Iseconds)"
log "Playbook: $PLAYBOOK"
[[ -n "$SERVICE" ]] && log "Service: $SERVICE"
log "Dry Run: $DRY_RUN"
log "Log File: $LOG_FILE"
log ""

# Execute disk-cleanup playbook
execute_disk_cleanup() {
    log "${YELLOW}▶ Executing Disk Cleanup Playbook${NC}"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"
    DISK_BEFORE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    log "  System SSD usage: ${DISK_BEFORE}%"

    if [[ $DISK_BEFORE -lt 75 && "$FORCE" != "true" ]]; then
        log "${GREEN}  ✓ Disk usage below threshold (75%). No action needed.${NC}"
        return 0
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Action 1: Rotate user journal logs
    log "  [1/6] Rotating user journal logs (7 day retention)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        JOURNAL_OUTPUT=$(journalctl --user --vacuum-time=7d 2>&1 || true)
        log "    $JOURNAL_OUTPUT"
    else
        log "    [DRY RUN] Would execute: journalctl --user --vacuum-time=7d"
    fi

    # Action 2: Rotate system journal logs (requires sudo)
    log "  [2/6] Rotating system journal logs (7 day retention)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if sudo -n true 2>/dev/null; then
            JOURNAL_SYS_OUTPUT=$(sudo journalctl --vacuum-time=7d 2>&1 || true)
            log "    $JOURNAL_SYS_OUTPUT"
        else
            log "    ${YELLOW}Skipped (no sudo)${NC}"
        fi
    else
        log "    [DRY RUN] Would execute: sudo journalctl --vacuum-time=7d"
    fi

    # Action 3: Prune unused images
    log "  [3/6] Pruning unused Podman images (7+ days old)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        IMAGE_OUTPUT=$(podman image prune -af --filter 'until=168h' 2>&1 || true)
        log "    $IMAGE_OUTPUT"
    else
        log "    [DRY RUN] Would execute: podman image prune -af --filter 'until=168h'"
    fi

    # Action 4: Prune build cache
    log "  [4/6] Pruning Podman system cache..."
    if [[ "$DRY_RUN" == "false" ]]; then
        SYSTEM_OUTPUT=$(podman system prune -f --volumes=false 2>&1 || true)
        log "    $SYSTEM_OUTPUT"
    else
        log "    [DRY RUN] Would execute: podman system prune -f --volumes=false"
    fi

    # Action 5: Clean old backup logs
    log "  [5/6] Cleaning old backup logs (30+ days)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        BACKUP_COUNT=$(find ~/containers/data/backup-logs -name '*.log' -mtime +30 2>/dev/null | wc -l || echo 0)
        find ~/containers/data/backup-logs -name '*.log' -mtime +30 -delete 2>/dev/null || true
        log "    Removed $BACKUP_COUNT old backup log files"
    else
        BACKUP_COUNT=$(find ~/containers/data/backup-logs -name '*.log' -mtime +30 2>/dev/null | wc -l || echo 0)
        log "    [DRY RUN] Would remove $BACKUP_COUNT backup log files"
    fi

    # Action 6: Clean Jellyfin transcode files
    log "  [6/6] Cleaning stale Jellyfin transcode files (1+ day old)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        TRANSCODE_COUNT=$(find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mtime +1 2>/dev/null | wc -l || echo 0)
        find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mtime +1 -delete 2>/dev/null || true
        log "    Removed $TRANSCODE_COUNT transcode files"
    else
        TRANSCODE_COUNT=$(find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mtime +1 2>/dev/null | wc -l || echo 0)
        log "    [DRY RUN] Would remove $TRANSCODE_COUNT transcode files"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"
    DISK_AFTER=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    DISK_FREED=$((DISK_BEFORE - DISK_AFTER))
    log "  System SSD usage after: ${DISK_AFTER}%"
    log "  Space freed: ${DISK_FREED}%"

    # Verify critical services
    log "  Verifying critical services..."
    CRITICAL_SERVICES="traefik prometheus jellyfin"
    for svc in $CRITICAL_SERVICES; do
        if systemctl --user is-active "$svc.service" >/dev/null 2>&1; then
            log "    ✓ $svc: active"
        else
            log "    ${RED}✗ $svc: inactive${NC}"
        fi
    done

    log ""
    if [[ $DISK_FREED -gt 0 || "$DRY_RUN" == "true" ]]; then
        log "${GREEN}✓ Disk cleanup completed successfully${NC}"
    else
        log "${YELLOW}⚠ Disk cleanup completed but no space freed${NC}"
    fi
}

# Execute service-restart playbook
execute_service_restart() {
    if [[ -z "$SERVICE" ]]; then
        log "${RED}Error: --service required for service-restart playbook${NC}"
        exit 1
    fi

    log "${YELLOW}▶ Executing Service Restart Playbook${NC}"
    log "  Service: $SERVICE"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"
    if ! systemctl --user list-unit-files | grep -q "$SERVICE.service"; then
        log "${RED}  ✗ Service $SERVICE not found${NC}"
        exit 1
    fi
    log "  ✓ Service exists"

    # Capture logs before restart
    log "  Capturing pre-restart logs..."
    if [[ "$DRY_RUN" == "false" ]]; then
        journalctl --user -u "$SERVICE.service" -n 50 > "/tmp/${SERVICE}-pre-restart-${TIMESTAMP}.log"
    fi

    log ""
    log "${BLUE}[Actions]${NC}"
    log "  [1/3] Stopping service..."
    if [[ "$DRY_RUN" == "false" ]]; then
        systemctl --user stop "$SERVICE.service"
        sleep 3
    else
        log "    [DRY RUN] Would execute: systemctl --user stop $SERVICE.service"
    fi

    log "  [2/3] Starting service..."
    if [[ "$DRY_RUN" == "false" ]]; then
        systemctl --user start "$SERVICE.service"
        sleep 15
    else
        log "    [DRY RUN] Would execute: systemctl --user start $SERVICE.service"
    fi

    log "  [3/3] Verifying service status..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if systemctl --user is-active "$SERVICE.service" >/dev/null 2>&1; then
            log "    ${GREEN}✓ Service active${NC}"
        else
            log "    ${RED}✗ Service failed to start${NC}"
            exit 1
        fi
    fi

    log ""
    log "${GREEN}✓ Service restart completed successfully${NC}"
}

# Main execution
case $PLAYBOOK in
    disk-cleanup)
        execute_disk_cleanup
        ;;
    service-restart)
        execute_service_restart
        ;;
    drift-reconciliation)
        log "${YELLOW}Drift reconciliation playbook not yet implemented in execution engine${NC}"
        log "Use: .claude/skills/homelab-deployment/scripts/check-drift.sh for drift detection"
        exit 1
        ;;
    resource-pressure)
        log "${YELLOW}Resource pressure playbook not yet implemented in execution engine${NC}"
        exit 1
        ;;
    *)
        log "${RED}Unknown playbook: $PLAYBOOK${NC}"
        exit 1
        ;;
esac

log ""
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${GREEN}  REMEDIATION COMPLETE${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log ""
log "Log saved to: $LOG_FILE"
