#!/bin/bash
#
# apply-remediation.sh
# Execute auto-remediation playbooks
#
# Usage: ./apply-remediation.sh --playbook PLAYBOOK [--dry-run] [--service SERVICE]
#

set -euo pipefail

# Trap for error handling and metrics on failure
trap 'handle_error $? $LINENO' ERR

handle_error() {
    local exit_code=$1
    local line_number=$2

    # Only write failure metrics if we've started execution (not during arg parsing)
    if [[ -n "${PLAYBOOK:-}" ]] && [[ -n "${START_TIME:-}" ]] && [[ "${DRY_RUN:-false}" == "false" ]]; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        METRICS_WRITER="$HOME/containers/scripts/write-remediation-metrics.sh"
        if [[ -x "$METRICS_WRITER" ]]; then
            "$METRICS_WRITER" \
                --playbook "${PLAYBOOK}" \
                --status "failure" \
                --duration "$DURATION" \
                --disk-reclaimed "${METRICS_DISK_RECLAIMED:-0}" \
                --services-restarted "${METRICS_SERVICES_RESTARTED:-}" \
                --oom-detected "${METRICS_OOM_DETECTED:-0}" \
                --root-cause "script_error_line_${line_number}" &>/dev/null || true
        fi
    fi

    exit $exit_code
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$HOME/containers"
PLAYBOOK_DIR="../playbooks"
LOG_DIR="../../data/remediation-logs"
DRY_RUN=false
PLAYBOOK=""
SERVICE=""
FORCE=false
DECISION_LOG=""

# Metrics tracking
START_TIME=$(date +%s)
METRICS_DISK_RECLAIMED=0
METRICS_SERVICES_RESTARTED=""
METRICS_OOM_DETECTED=0
METRICS_ROOT_CAUSE=""

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
        --slo-target)
            SLO_TARGET="$2"
            shift 2
            ;;
        --tier)
            TIER="$2"
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
        --log-to)
            DECISION_LOG="$2"
            shift 2
            ;;
        --list-playbooks)
            echo "Available Remediation Playbooks:"
            echo ""
            echo "1. disk-cleanup                - Clean system disk (journals, images, caches)"
            echo "2. service-restart             - Restart a failed service"
            echo "3. drift-reconciliation        - Fix config drift between quadlet and running container"
            echo "4. resource-pressure           - Mitigate high memory/swap usage"
            echo "5. predictive-maintenance      - Proactive remediation based on forecasts"
            echo "6. self-healing-restart        - Smart service restart with root cause detection"
            echo "7. database-maintenance        - PostgreSQL VACUUM, Redis analysis, health checks"
            echo "8. slo-violation-remediation   - SLO-aware service recovery with burn rate measurement"
            echo ""
            echo "Usage: $0 --playbook PLAYBOOK [--service SERVICE] [--slo-target PCT] [--tier N] [--dry-run] [--force] [--log-to FILE]"
            exit 0
            ;;
        *)
            echo "Usage: $0 --playbook PLAYBOOK [--service SERVICE] [--slo-target PCT] [--tier N] [--dry-run] [--force] [--log-to FILE] [--list-playbooks]"
            echo "Available playbooks: disk-cleanup, drift-reconciliation, service-restart, resource-pressure, predictive-maintenance, self-healing-restart, database-maintenance, slo-violation-remediation"
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

    # Action 3: Prune dangling images
    log "  [3/6] Pruning dangling Podman images (7+ days old)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        IMAGE_OUTPUT=$(podman image prune -f --filter 'until=168h' 2>&1 || true)
        log "    $IMAGE_OUTPUT"
    else
        log "    [DRY RUN] Would execute: podman image prune -f --filter 'until=168h'"
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

    # Calculate disk space freed in bytes for metrics
    if [[ "$DRY_RUN" == "false" ]]; then
        DISK_SIZE_BYTES=$(df / | awk 'NR==2 {print $2}')
        METRICS_DISK_RECLAIMED=$(echo "$DISK_SIZE_BYTES * $DISK_FREED / 100" | bc)
    fi

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
    if systemctl --user show "$SERVICE.service" > /dev/null 2>&1; then
        log "  ✓ Service exists"
    else
        log "${RED}  ✗ Service $SERVICE not found${NC}"
        exit 1
    fi

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

    # Track metrics
    if [[ "$DRY_RUN" == "false" ]]; then
        METRICS_SERVICES_RESTARTED="$SERVICE"
    fi

    log ""
    log "${GREEN}✓ Service restart completed successfully${NC}"
}

# Execute drift-reconciliation playbook
execute_drift_reconciliation() {
    if [[ -z "$SERVICE" ]]; then
        log "${RED}Error: --service required for drift-reconciliation playbook${NC}"
        exit 1
    fi

    log "${YELLOW}▶ Executing Drift Reconciliation Playbook${NC}"
    log "  Service: $SERVICE"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"

    # Check if check-drift.sh exists
    DRIFT_SCRIPT="../../skills/homelab-deployment/scripts/check-drift.sh"
    if [[ ! -f "$DRIFT_SCRIPT" ]]; then
        log "${RED}  ✗ Drift detection script not found: $DRIFT_SCRIPT${NC}"
        exit 1
    fi
    log "  ✓ Drift detection script exists"

    # Check if service exists (using show which returns error if not found)
    if systemctl --user show "$SERVICE.service" > /dev/null 2>&1; then
        log "  ✓ Service exists"
    else
        log "${RED}  ✗ Service $SERVICE not found${NC}"
        exit 1
    fi

    # Check current drift status
    log "  Checking drift status..."
    if [[ "$DRY_RUN" == "false" ]]; then
        DRIFT_OUTPUT=$(cd ../../skills/homelab-deployment/scripts && ./check-drift.sh "$SERVICE" 2>&1 || true)
        log "    $DRIFT_OUTPUT"

        if echo "$DRIFT_OUTPUT" | grep -q "✓ MATCH"; then
            log "${GREEN}  ✓ No drift detected. Service config matches quadlet.${NC}"
            log "${YELLOW}  Skipping reconciliation - no action needed.${NC}"
            return 0
        fi
    else
        log "    [DRY RUN] Would check drift with: ./check-drift.sh $SERVICE"
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Create backup directory
    BACKUP_DIR=~/containers/backups/quadlets/$(date +%Y%m%d-%H%M%S)
    log "  [1/5] Creating backup directory..."
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$BACKUP_DIR"
        log "    Created: $BACKUP_DIR"
    else
        log "    [DRY RUN] Would create: $BACKUP_DIR"
    fi

    # Backup current quadlet
    log "  [2/5] Backing up current quadlet..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ -f ~/.config/containers/systemd/${SERVICE}.container ]]; then
            cp ~/.config/containers/systemd/${SERVICE}.container "$BACKUP_DIR/${SERVICE}.container.bak"
            log "    ${GREEN}✓ Backup created${NC}"
        else
            log "    ${YELLOW}⚠ Quadlet file not found, skipping backup${NC}"
        fi
    else
        log "    [DRY RUN] Would backup quadlet to $BACKUP_DIR"
    fi

    # Note: Full regeneration from pattern requires pattern detection which is complex
    # For now, we'll focus on reloading and restarting which fixes most drift
    log "  [3/5] Reloading systemd daemon..."
    if [[ "$DRY_RUN" == "false" ]]; then
        systemctl --user daemon-reload
        log "    ${GREEN}✓ Daemon reloaded${NC}"
    else
        log "    [DRY RUN] Would execute: systemctl --user daemon-reload"
    fi

    log "  [4/5] Restarting service..."
    if [[ "$DRY_RUN" == "false" ]]; then
        systemctl --user restart "$SERVICE.service"
        sleep 15
        log "    ${GREEN}✓ Service restarted${NC}"
    else
        log "    [DRY RUN] Would execute: systemctl --user restart $SERVICE.service"
    fi

    log "  [5/5] Waiting for service health check..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 30
        if systemctl --user is-active "$SERVICE.service" >/dev/null 2>&1; then
            log "    ${GREEN}✓ Service active${NC}"
        else
            log "    ${RED}✗ Service failed to start${NC}"
            log "    ${YELLOW}Backup available at: $BACKUP_DIR${NC}"
            exit 1
        fi
    else
        log "    [DRY RUN] Would wait 30s and verify service active"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"
    log "  Verifying drift resolved..."
    if [[ "$DRY_RUN" == "false" ]]; then
        DRIFT_AFTER=$(cd ../../skills/homelab-deployment/scripts && ./check-drift.sh "$SERVICE" 2>&1 || true)
        log "    $DRIFT_AFTER"
    else
        log "    [DRY RUN] Would verify drift resolved"
    fi

    log ""
    log "${GREEN}✓ Drift reconciliation completed${NC}"
    log "  Backup location: $BACKUP_DIR"
}

# Execute resource-pressure playbook
execute_resource_pressure() {
    log "${YELLOW}▶ Executing Resource Pressure Playbook${NC}"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"

    SWAP_MB=$(free -m | awk '/^Swap:/ {print $3}')
    MEM_AVAIL_MB=$(free -m | awk '/^Mem:/ {print $7}')
    MEM_TOTAL_MB=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_AVAIL_PCT=$((MEM_AVAIL_MB * 100 / MEM_TOTAL_MB))

    log "  Swap usage: ${SWAP_MB}MB"
    log "  Memory available: ${MEM_AVAIL_MB}MB (${MEM_AVAIL_PCT}%)"

    if [[ $SWAP_MB -lt 6000 && $MEM_AVAIL_PCT -gt 15 && "$FORCE" != "true" ]]; then
        log "${GREEN}  ✓ Resource usage within normal range. No action needed.${NC}"
        return 0
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Action 1: Clear system caches
    log "  [1/4] Clearing system caches..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if sudo -n true 2>/dev/null; then
            sync
            echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null
            log "    ${GREEN}✓ Caches cleared${NC}"
        else
            log "    ${YELLOW}Skipped (no sudo access)${NC}"
        fi
    else
        log "    [DRY RUN] Would execute: sync && echo 1 | sudo tee /proc/sys/vm/drop_caches"
    fi

    # Action 2: Clean Jellyfin transcode cache
    log "  [2/4] Cleaning Jellyfin transcode cache (1+ hour idle)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        TRANSCODE_COUNT=$(find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mmin +60 2>/dev/null | wc -l || echo 0)
        find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mmin +60 -delete 2>/dev/null || true
        log "    Removed $TRANSCODE_COUNT transcode files"
    else
        TRANSCODE_COUNT=$(find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes -type f -mmin +60 2>/dev/null | wc -l || echo 0)
        log "    [DRY RUN] Would remove $TRANSCODE_COUNT transcode files"
    fi

    # Action 3: Identify top memory consumers
    log "  [3/4] Identifying top memory consumers..."
    if [[ "$DRY_RUN" == "false" ]]; then
        TOP_CONSUMERS=$(podman stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' | grep -v NAME | sort -k2 -h -r | head -5)
        log "$TOP_CONSUMERS" | while read line; do
            log "    $line"
        done
    else
        log "    [DRY RUN] Would show top 5 memory consumers"
    fi

    # Action 4: Conditional Prometheus restart if high memory
    log "  [4/4] Checking if Prometheus needs restart (memory compaction)..."
    if [[ "$DRY_RUN" == "false" ]]; then
        PROM_MEM=$(podman stats --no-stream prometheus --format '{{.MemUsage}}' 2>/dev/null | awk '{print $1}' | tr -d 'GiB' || echo 0)
        if (( $(echo "$PROM_MEM > 2.5" | bc -l 2>/dev/null || echo 0) )); then
            log "    ${YELLOW}Prometheus using ${PROM_MEM}GB, restarting for compaction...${NC}"
            systemctl --user restart prometheus.service
            sleep 15
            log "    ${GREEN}✓ Prometheus restarted${NC}"
        else
            log "    ${GREEN}✓ Prometheus memory usage normal (${PROM_MEM}GB)${NC}"
        fi
    else
        log "    [DRY RUN] Would check Prometheus memory and restart if > 2.5GB"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"

    SWAP_AFTER=$(free -m | awk '/^Swap:/ {print $3}')
    MEM_AVAIL_AFTER=$(free -m | awk '/^Mem:/ {print $7}')
    SWAP_FREED=$((SWAP_MB - SWAP_AFTER))
    MEM_FREED=$((MEM_AVAIL_AFTER - MEM_AVAIL_MB))

    log "  Swap usage after: ${SWAP_AFTER}MB (freed: ${SWAP_FREED}MB)"
    log "  Memory available after: ${MEM_AVAIL_AFTER}MB (gained: ${MEM_FREED}MB)"

    # Verify critical services
    log "  Verifying critical services..."
    CRITICAL_SERVICES="traefik prometheus jellyfin grafana"
    for svc in $CRITICAL_SERVICES; do
        if systemctl --user is-active "$svc.service" >/dev/null 2>&1; then
            log "    ✓ $svc: active"
        else
            log "    ${RED}✗ $svc: inactive${NC}"
        fi
    done

    log ""
    if [[ $SWAP_FREED -gt 0 || $MEM_FREED -gt 0 || "$DRY_RUN" == "true" ]]; then
        log "${GREEN}✓ Resource pressure mitigation completed${NC}"
    else
        log "${YELLOW}⚠ Resource pressure mitigation completed but minimal improvement${NC}"
    fi
}

execute_predictive_maintenance() {
    log "${YELLOW}▶ Executing Predictive Maintenance Playbook${NC}"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"

    # Run predictive analytics
    log "  Running predictive analytics..."
    if [[ "$DRY_RUN" == "false" ]]; then
        PREDICT_OUTPUT=$("$CONTAINERS_DIR/scripts/predictive-analytics/predict-resource-exhaustion.sh" --output json 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log "    ${RED}✗ Failed to run predictions${NC}"
            return 1
        fi

        # Parse results
        RESOURCE=$(echo "$PREDICT_OUTPUT" | jq -r '.resource')
        SEVERITY=$(echo "$PREDICT_OUTPUT" | jq -r '.severity')
        FORECAST_7D=$(echo "$PREDICT_OUTPUT" | jq -r '.forecast_7d_pct')
        DAYS_UNTIL_90=$(echo "$PREDICT_OUTPUT" | jq -r '.days_until_90pct')
        CONFIDENCE=$(echo "$PREDICT_OUTPUT" | jq -r '.confidence')
        RECOMMENDATION=$(echo "$PREDICT_OUTPUT" | jq -r '.recommendation')

        log "    Resource: $RESOURCE"
        log "    Severity: $SEVERITY"
        log "    7-day forecast: ${FORECAST_7D}%"
        log "    Days until 90%: $DAYS_UNTIL_90"
        log "    Confidence: $CONFIDENCE"

        # Check if action needed
        if [[ "$SEVERITY" != "critical" && "$SEVERITY" != "warning" && "$FORCE" != "true" ]]; then
            log "    ${GREEN}✓ No critical predictions. System healthy.${NC}"
            return 0
        fi
    else
        log "    [DRY RUN] Would run predictive analytics"
        RESOURCE="disk"
        SEVERITY="critical"
        FORECAST_7D="88"
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Action 1: Preemptive cleanup if disk critical
    log "  [1/3] Checking if preemptive cleanup needed..."
    if [[ "$RESOURCE" == "disk" && "$SEVERITY" == "critical" ]]; then
        log "    ${YELLOW}Disk forecast critical, running preemptive cleanup...${NC}"
        if [[ "$DRY_RUN" == "false" ]]; then
            "$SCRIPT_DIR/apply-remediation.sh" --playbook disk-cleanup --log-to "$DECISION_LOG" 2>&1 | tee -a "$LOG_FILE"
            log "    ${GREEN}✓ Preemptive cleanup completed${NC}"
        else
            log "    [DRY RUN] Would execute: apply-remediation.sh --playbook disk-cleanup"
        fi
    else
        log "    ${GREEN}✓ No immediate cleanup needed${NC}"
    fi

    # Action 2: Log prediction for trend analysis
    log "  [2/3] Logging prediction for historical trending..."
    if [[ "$DRY_RUN" == "false" ]]; then
        PREDICTION_LOG="$CONTAINERS_DIR/data/remediation-logs/predictions.log"
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Resource: $RESOURCE, Severity: $SEVERITY, Forecast: ${FORECAST_7D}%, Confidence: $CONFIDENCE" >> "$PREDICTION_LOG"
        log "    ${GREEN}✓ Prediction logged${NC}"
    else
        log "    [DRY RUN] Would log prediction to predictions.log"
    fi

    # Action 3: Generate recommendation
    log "  [3/3] Recording recommendation..."
    if [[ "$DRY_RUN" == "false" ]]; then
        log "    Recommendation: $RECOMMENDATION"
    else
        log "    [DRY RUN] Would log recommendation"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"

    # Re-run predictions to see if severity improved
    if [[ "$DRY_RUN" == "false" && "$RESOURCE" == "disk" && "$SEVERITY" == "critical" ]]; then
        log "  Checking if prediction improved after cleanup..."
        PREDICT_AFTER=$("$CONTAINERS_DIR/scripts/predictive-analytics/predict-resource-exhaustion.sh" --output json 2>/dev/null)
        SEVERITY_AFTER=$(echo "$PREDICT_AFTER" | jq -r '.severity')
        log "    Severity after: $SEVERITY_AFTER (was: $SEVERITY)"

        if [[ "$SEVERITY_AFTER" != "critical" ]]; then
            log "    ${GREEN}✓ Prediction improved after remediation${NC}"
        else
            log "    ${YELLOW}⚠ Still critical - may need manual intervention${NC}"
        fi
    fi

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
    log "${GREEN}✓ Predictive maintenance completed${NC}"
    return 0
}

execute_self_healing_restart() {
    log "${YELLOW}▶ Executing Self-Healing Restart Playbook${NC}"
    log ""

    if [[ -z "$SERVICE" ]]; then
        log "${RED}Error: --service parameter required${NC}"
        return 1
    fi

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"

    # Check if service exists
    log "  Checking if service $SERVICE exists..."
    LOAD_STATE=$(systemctl --user show "$SERVICE.service" --property=LoadState 2>/dev/null | cut -d= -f2)
    if [[ "$LOAD_STATE" == "not-found" ]]; then
        log "    ${RED}✗ Service $SERVICE not found${NC}"
        return 1
    fi
    log "    ${GREEN}✓ Service exists${NC}"

    # Capture current state
    log "  Diagnosing failure cause..."
    if [[ "$DRY_RUN" == "false" ]]; then
        FAILURE_LOGS=$(journalctl --user -u "$SERVICE.service" -n 50 --no-pager 2>/dev/null)

        # Check for OOM
        OOM_DETECTED=false
        if echo "$FAILURE_LOGS" | grep -qi "out of memory\|OOM\|memory limit"; then
            OOM_DETECTED=true
            log "    ${YELLOW}⚠ OOM detected - service ran out of memory${NC}"
        fi

        # Check restart count
        RESTART_COUNT=$(systemctl --user show "$SERVICE.service" --property=NRestarts | cut -d= -f2)
        log "    Restart count in last hour: $RESTART_COUNT"

        # Check if in restart loop
        RESTART_LOOP=false
        if [[ $RESTART_COUNT -gt 2 ]]; then
            RESTART_LOOP=true
            log "    ${YELLOW}⚠ Restart loop detected${NC}"
        fi
    else
        log "    [DRY RUN] Would diagnose failure cause"
        OOM_DETECTED=false
        RESTART_LOOP=false
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Action 1: Apply targeted fix if OOM detected
    log "  [1/4] Applying targeted fixes..."
    if [[ "$OOM_DETECTED" == "true" ]]; then
        log "    ${YELLOW}OOM detected, attempting to increase memory limit...${NC}"
        if [[ "$DRY_RUN" == "false" ]]; then
            QUADLET_FILE="$HOME/.config/containers/systemd/$SERVICE.container"
            if [[ -f "$QUADLET_FILE" ]]; then
                # Check current memory limit
                CURRENT_MEM=$(grep "^MemoryMax=" "$QUADLET_FILE" | cut -d= -f2 || echo "none")
                log "      Current limit: $CURRENT_MEM"
                log "      ${YELLOW}Note: Memory limit adjustment requires manual review${NC}"
                log "      ${YELLOW}Proceeding with restart, but consider increasing MemoryMax in quadlet${NC}"
            fi
        else
            log "    [DRY RUN] Would check and potentially increase memory limit"
        fi
    else
        log "    ${GREEN}✓ No OOM detected, proceeding with standard restart${NC}"
    fi

    # Action 2: Clear failed state if restart loop
    log "  [2/4] Clearing service state..."
    if [[ "$RESTART_LOOP" == "true" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            systemctl --user reset-failed "$SERVICE.service" 2>/dev/null || true
            log "    ${GREEN}✓ Failed state cleared${NC}"
        else
            log "    [DRY RUN] Would execute: systemctl --user reset-failed $SERVICE.service"
        fi
    else
        log "    ${GREEN}✓ No restart loop, state is clean${NC}"
    fi

    # Action 3: Restart service
    log "  [3/4] Restarting service with clean state..."
    if [[ "$DRY_RUN" == "false" ]]; then
        systemctl --user restart "$SERVICE.service"
        log "    ${GREEN}✓ Restart command issued${NC}"
    else
        log "    [DRY RUN] Would execute: systemctl --user restart $SERVICE.service"
    fi

    # Action 4: Wait for stabilization
    log "  [4/4] Waiting for service stabilization..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 15
        log "    ${GREEN}✓ Stabilization period complete${NC}"
    else
        log "    [DRY RUN] Would wait 15 seconds"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"

    # Verify service is active
    log "  Verifying service status..."
    if [[ "$DRY_RUN" == "false" ]]; then
        if systemctl --user is-active "$SERVICE.service" >/dev/null 2>&1; then
            log "    ${GREEN}✓ Service is active${NC}"
        else
            log "    ${RED}✗ Service failed to start${NC}"
            return 1
        fi

        # Verify container is running
        if podman ps | grep -q "$SERVICE"; then
            log "    ${GREEN}✓ Container is running${NC}"
        else
            log "    ${YELLOW}⚠ Container not found (may be non-container service)${NC}"
        fi

        # Monitor for immediate failure
        log "  Monitoring for stability (30s)..."
        sleep 30
        if systemctl --user is-active "$SERVICE.service" >/dev/null 2>&1; then
            log "    ${GREEN}✓ Service remained stable for 30 seconds${NC}"
        else
            log "    ${RED}✗ Service failed again - escalation needed${NC}"
            log "    ${YELLOW}Recommendation: Check for config drift with check-drift.sh${NC}"
            return 1
        fi
    else
        log "    [DRY RUN] Would verify service active and monitor stability"
    fi

    log ""
    if [[ "$OOM_DETECTED" == "true" ]]; then
        log "${YELLOW}⚠ Action Required: Review memory limit for $SERVICE${NC}"
        log "  Edit: ~/.config/containers/systemd/$SERVICE.container"
        log "  Consider increasing MemoryMax value"
        log ""
    fi

    # Track metrics
    if [[ "$DRY_RUN" == "false" ]]; then
        METRICS_SERVICES_RESTARTED="$SERVICE"
        if [[ "$OOM_DETECTED" == "true" ]]; then
            METRICS_OOM_DETECTED=1
            METRICS_ROOT_CAUSE="oom"
        elif [[ "$RESTART_LOOP" == "true" ]]; then
            METRICS_ROOT_CAUSE="restart_loop"
        else
            METRICS_ROOT_CAUSE="standard_restart"
        fi
    fi

    log "${GREEN}✓ Self-healing restart completed${NC}"
    return 0
}

execute_database_maintenance() {
    log "${YELLOW}▶ Executing Database Maintenance Playbook${NC}"
    log ""

    # Pre-checks
    log "${BLUE}[Pre-Checks]${NC}"

    # Check database services
    log "  Checking database services..."
    POSTGRES_RUNNING=false
    REDIS_RUNNING=false

    if systemctl --user is-active postgresql-immich.service >/dev/null 2>&1; then
        POSTGRES_RUNNING=true
        log "    ${GREEN}✓ PostgreSQL (Immich): active${NC}"
    else
        log "    ${YELLOW}⚠ PostgreSQL (Immich): not running${NC}"
    fi

    if systemctl --user is-active redis-authelia.service >/dev/null 2>&1; then
        REDIS_RUNNING=true
        log "    ${GREEN}✓ Redis (Authelia): active${NC}"
    else
        log "    ${YELLOW}⚠ Redis (Authelia): not running${NC}"
    fi

    if [[ "$POSTGRES_RUNNING" == "false" && "$REDIS_RUNNING" == "false" ]]; then
        log "    ${RED}✗ No database services running${NC}"
        return 1
    fi

    # Capture sizes before
    if [[ "$DRY_RUN" == "false" ]]; then
        POSTGRES_SIZE_BEFORE=$(du -sm "$HOME/containers/data/postgresql-immich" 2>/dev/null | awk '{print $1}' || echo 0)
        log "  PostgreSQL size before: ${POSTGRES_SIZE_BEFORE}MB"
    fi

    log ""
    log "${BLUE}[Actions]${NC}"

    # Action 1: PostgreSQL VACUUM
    if [[ "$POSTGRES_RUNNING" == "true" ]]; then
        log "  [1/4] Running PostgreSQL VACUUM ANALYZE..."
        if [[ "$DRY_RUN" == "false" ]]; then
            log "    ${YELLOW}This may take 2-10 minutes...${NC}"
            if podman exec postgresql-immich psql -U immich -d immich -c 'VACUUM ANALYZE;' >/dev/null 2>&1; then
                log "    ${GREEN}✓ VACUUM completed successfully${NC}"
            else
                log "    ${RED}✗ VACUUM failed${NC}"
            fi
        else
            log "    [DRY RUN] Would execute: podman exec postgresql-immich psql -U immich -d immich -c 'VACUUM ANALYZE;'"
        fi
    else
        log "  [1/4] ${YELLOW}Skipping PostgreSQL (not running)${NC}"
    fi

    # Action 2: Redis memory analysis
    if [[ "$REDIS_RUNNING" == "true" ]]; then
        log "  [2/4] Analyzing Redis memory usage..."
        if [[ "$DRY_RUN" == "false" ]]; then
            REDIS_MEMORY=$(podman exec redis-authelia redis-cli INFO memory | grep "used_memory_human" | cut -d: -f2 || echo "unknown")
            log "    Redis memory usage: $REDIS_MEMORY"

            REDIS_KEYS=$(podman exec redis-authelia redis-cli DBSIZE | awk '{print $2}' || echo "unknown")
            log "    Redis keys: $REDIS_KEYS"

            log "    ${GREEN}✓ Redis analysis complete${NC}"
        else
            log "    [DRY RUN] Would execute: podman exec redis-authelia redis-cli MEMORY DOCTOR"
        fi
    else
        log "  [2/4] ${YELLOW}Skipping Redis (not running)${NC}"
    fi

    # Action 3: Loki retention check
    log "  [3/4] Checking Loki retention policy..."
    if systemctl --user is-active loki.service >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "false" ]]; then
            LOKI_LOGS=$(podman logs loki --tail 100 2>/dev/null | grep -i "retention\|compact" || echo "No retention messages")
            log "    ${GREEN}✓ Loki operational${NC}"
        else
            log "    [DRY RUN] Would check Loki logs for retention info"
        fi
    else
        log "    ${YELLOW}Loki not running, skipping${NC}"
    fi

    # Action 4: Generate maintenance report
    log "  [4/4] Generating maintenance report..."
    if [[ "$DRY_RUN" == "false" ]]; then
        REPORT_FILE="$CONTAINERS_DIR/data/remediation-logs/database-maintenance-$(date +%Y%m%d-%H%M%S).log"
        {
            echo "Database Maintenance Report"
            echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "PostgreSQL size before: ${POSTGRES_SIZE_BEFORE}MB"
            echo "PostgreSQL maintenance: Completed"
            echo "Redis analysis: Completed"
        } > "$REPORT_FILE"
        log "    ${GREEN}✓ Report saved to: $REPORT_FILE${NC}"
    else
        log "    [DRY RUN] Would generate maintenance report"
    fi

    log ""
    log "${BLUE}[Post-Checks]${NC}"

    # Verify services still healthy
    log "  Verifying database services..."
    if [[ "$POSTGRES_RUNNING" == "true" ]]; then
        if systemctl --user is-active postgresql-immich.service >/dev/null 2>&1; then
            log "    ${GREEN}✓ PostgreSQL still active${NC}"
        else
            log "    ${RED}✗ PostgreSQL became inactive${NC}"
            return 1
        fi
    fi

    if [[ "$REDIS_RUNNING" == "true" ]]; then
        if systemctl --user is-active redis-authelia.service >/dev/null 2>&1; then
            log "    ${GREEN}✓ Redis still active${NC}"
        else
            log "    ${RED}✗ Redis became inactive${NC}"
            return 1
        fi
    fi

    # Check size after
    if [[ "$DRY_RUN" == "false" && "$POSTGRES_RUNNING" == "true" ]]; then
        POSTGRES_SIZE_AFTER=$(du -sm "$HOME/containers/data/postgresql-immich" 2>/dev/null | awk '{print $1}' || echo 0)
        SPACE_SAVED=$((POSTGRES_SIZE_BEFORE - POSTGRES_SIZE_AFTER))
        log "  PostgreSQL size after: ${POSTGRES_SIZE_AFTER}MB"
        if [[ $SPACE_SAVED -gt 0 ]]; then
            log "    ${GREEN}✓ Reclaimed ${SPACE_SAVED}MB${NC}"
        else
            log "    Space delta: ${SPACE_SAVED}MB (no space reclaimed, statistics updated)"
        fi
    fi

    log ""
    log "${GREEN}✓ Database maintenance completed${NC}"
    return 0
}

# SLO Violation Remediation (Phase 4: SLO Integration)
execute_slo_violation_remediation() {
    log ""
    log "${BLUE}[SLO Violation Remediation]${NC}"
    log "Triggered by: SLO burn rate alert (Tier ${TIER:-1})"
    log "Target service: ${SERVICE}"
    log "SLO target: ${SLO_TARGET}%"
    log ""

    # This playbook uses YAML-based execution via generic runner
    # The YAML file contains all logic for SLO-aware remediation
    PLAYBOOK_YAML="$PLAYBOOK_DIR/slo-violation-remediation.yml"

    if [[ ! -f "$PLAYBOOK_YAML" ]]; then
        log "${RED}✗ Playbook YAML not found: $PLAYBOOK_YAML${NC}"
        return 1
    fi

    log "Executing YAML-based playbook..."
    log "(Note: YAML playbook execution not yet fully implemented)"
    log ""
    log "${YELLOW}For now, executing simplified SLO remediation:${NC}"
    log ""

    # Simplified SLO remediation logic (until YAML executor is built)
    log "${BLUE}[Pre-Checks]${NC}"

    # Capture baseline SLO state
    log "  Capturing baseline SLO metrics..."
    if command -v curl >/dev/null 2>&1; then
        SLI_BEFORE=$(curl -s "http://localhost:9090/api/v1/query?query=sli:${SERVICE}:availability:ratio" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null || echo "N/A")
        BURN_RATE_BEFORE=$(curl -s "http://localhost:9090/api/v1/query?query=burn_rate:${SERVICE}:availability:1h" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0")
        log "    SLI (before): ${SLI_BEFORE}"
        log "    Burn rate (before): ${BURN_RATE_BEFORE}x"
    else
        log "    ${YELLOW}⚠ curl not available, skipping SLO metrics${NC}"
        SLI_BEFORE="N/A"
        BURN_RATE_BEFORE="0"
    fi

    # Check service status
    log "  Checking service status..."
    if systemctl --user is-active "${SERVICE}.service" >/dev/null 2>&1; then
        log "    ${GREEN}✓ Service is active${NC}"
    else
        log "    ${YELLOW}⚠ Service is not active${NC}"
    fi

    log ""
    log "${BLUE}[Remediation Action]${NC}"

    # Apply tier-appropriate remediation
    case "${TIER:-1}" in
        1)
            log "  Tier 1: Critical - Executing immediate service restart"
            if [[ "$DRY_RUN" == "false" ]]; then
                systemctl --user restart "${SERVICE}.service"
                log "    ${GREEN}✓ Service restarted${NC}"
                sleep 5
            else
                log "    [DRY RUN] Would restart ${SERVICE}.service"
            fi
            ;;
        2)
            log "  Tier 2: High - Attempting reload before restart"
            if [[ "$DRY_RUN" == "false" ]]; then
                if systemctl --user reload "${SERVICE}.service" 2>/dev/null; then
                    log "    ${GREEN}✓ Service reloaded${NC}"
                else
                    log "    Reload not supported, performing restart..."
                    systemctl --user restart "${SERVICE}.service"
                    log "    ${GREEN}✓ Service restarted${NC}"
                fi
                sleep 3
            else
                log "    [DRY RUN] Would reload/restart ${SERVICE}.service"
            fi
            ;;
        *)
            log "  Tier ${TIER}: Investigation only (no automatic action)"
            ;;
    esac

    log ""
    log "${BLUE}[Post-Checks]${NC}"

    # Wait for metrics to stabilize
    if [[ "$DRY_RUN" == "false" ]]; then
        log "  Waiting 60s for metrics to stabilize..."
        sleep 60
    else
        log "  [DRY RUN] Would wait 60s for metrics"
    fi

    # Measure SLO improvement
    log "  Measuring SLO improvement..."
    if command -v curl >/dev/null 2>&1 && [[ "$DRY_RUN" == "false" ]]; then
        SLI_AFTER=$(curl -s "http://localhost:9090/api/v1/query?query=sli:${SERVICE}:availability:ratio" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null || echo "N/A")
        BURN_RATE_AFTER=$(curl -s "http://localhost:9090/api/v1/query?query=burn_rate:${SERVICE}:availability:5m" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0")

        log "    SLI (after): ${SLI_AFTER}"
        log "    Burn rate (after): ${BURN_RATE_AFTER}x"

        # Calculate improvement
        if [[ "$SLI_AFTER" != "N/A" && "$SLI_BEFORE" != "N/A" ]]; then
            SLI_DELTA=$(awk "BEGIN {printf \"%.4f\", $SLI_AFTER - $SLI_BEFORE}" 2>/dev/null || echo "0")
            log "    SLI delta: ${SLI_DELTA} (positive = improvement)"
            export SLI_DELTA
        fi

        if [[ "$BURN_RATE_AFTER" != "0" && "$BURN_RATE_BEFORE" != "0" ]]; then
            BURN_DELTA=$(awk "BEGIN {printf \"%.2f\", $BURN_RATE_BEFORE - $BURN_RATE_AFTER}" 2>/dev/null || echo "0")
            log "    Burn rate reduction: ${BURN_DELTA}x (positive = improvement)"
            export BURN_DELTA
        fi

        # Export for metrics collection
        export SLI_BEFORE
        export SLI_AFTER
        export BURN_RATE_BEFORE
        export BURN_RATE_AFTER

        # Verify improvement
        if (( $(awk "BEGIN {print ($BURN_RATE_AFTER < 1.0)}" 2>/dev/null || echo 0) )); then
            log "    ${GREEN}✓ SUCCESS: Burn rate normalized (<1.0x)${NC}"
        elif (( $(awk "BEGIN {print ($BURN_RATE_AFTER < $BURN_RATE_BEFORE)}" 2>/dev/null || echo 0) )); then
            log "    ${GREEN}✓ PARTIAL: Burn rate improved${NC}"
        else
            log "    ${YELLOW}⚠ Burn rate did not improve - further investigation required${NC}"
        fi
    else
        log "    [DRY RUN] Would measure SLO metrics"
    fi

    # Verify service health
    log "  Verifying service health..."
    if systemctl --user is-active "${SERVICE}.service" >/dev/null 2>&1; then
        log "    ${GREEN}✓ Service is active${NC}"
    else
        log "    ${RED}✗ Service is not active${NC}"
        return 1
    fi

    log ""
    log "${GREEN}✓ SLO violation remediation completed${NC}"
    return 0
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
        execute_drift_reconciliation
        ;;
    resource-pressure)
        execute_resource_pressure
        ;;
    predictive-maintenance)
        execute_predictive_maintenance
        ;;
    self-healing-restart)
        execute_self_healing_restart
        ;;
    database-maintenance)
        execute_database_maintenance
        ;;
    slo-violation-remediation)
        execute_slo_violation_remediation
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

# Append to decision log if requested (for autonomous operations integration)
if [[ -n "$DECISION_LOG" ]] && [[ -f "$DECISION_LOG" ]]; then
    local entry
    entry=$(cat << EOF
{
  "id": "remediation-$(date +%Y%m%d%H%M%S)-$RANDOM",
  "timestamp": "$(date -Iseconds)",
  "playbook": "$PLAYBOOK",
  "service": $(if [[ -n "$SERVICE" ]]; then echo "\"$SERVICE\""; else echo "null"; fi),
  "outcome": "success",
  "log_file": "$LOG_FILE"
}
EOF
    )

    # Append to decision log
    if jq --argjson entry "$entry" '.remediation_executions += [$entry]' "$DECISION_LOG" > "${DECISION_LOG}.tmp" 2>/dev/null; then
        mv "${DECISION_LOG}.tmp" "$DECISION_LOG"
        log "${GREEN}✓ Logged to decision log${NC}"
    else
        rm -f "${DECISION_LOG}.tmp"
        log "${YELLOW}⚠ Could not append to decision log${NC}"
    fi
fi

# Write metrics for Prometheus (skip in dry-run mode)
if [[ "$DRY_RUN" == "false" ]]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    METRICS_WRITER="$CONTAINERS_DIR/scripts/write-remediation-metrics.sh"
    if [[ -x "$METRICS_WRITER" ]]; then
        "$METRICS_WRITER" \
            --playbook "$PLAYBOOK" \
            --status "success" \
            --duration "$DURATION" \
            --disk-reclaimed "$METRICS_DISK_RECLAIMED" \
            --services-restarted "$METRICS_SERVICES_RESTARTED" \
            --oom-detected "$METRICS_OOM_DETECTED" \
            --root-cause "$METRICS_ROOT_CAUSE" &>> "$LOG_FILE"
    fi
fi
