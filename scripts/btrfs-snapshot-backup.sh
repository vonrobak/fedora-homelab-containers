#!/bin/bash
################################################################################
# BTRFS Snapshot & Backup Script
# Author: patriark
# Created: 2025-11-07
#
# Purpose: Automated BTRFS snapshot creation and incremental backup to external
#          drive, optimized for minimal local storage (128GB NVMe)
#
# Usage:
#   ./btrfs-snapshot-backup.sh [options]
#
# Options:
#   --dry-run           Show what would be done without executing
#   --local-only        Create local snapshots only (no external backup)
#   --external-only     Send to external only (no new local snapshots)
#   --tier <1|2|3>      Run specific tier only (default: all)
#   --subvolume <name>  Run specific subvolume only
#   --verbose           Verbose output
#   --help              Show this help message
#
# Schedule (via systemd timers):
#   - Daily:   02:00 AM - Tier 1 local snapshots + cleanup
#   - Weekly:  Sunday 03:00 AM - All tiers external backup
#   - Monthly: 1st of month 04:00 AM - Monthly snapshots + external
#
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION SECTION - ADJUST THESE PARAMETERS AS NEEDED
################################################################################

# Backup destination (external drive)
EXTERNAL_BACKUP_ROOT="/run/media/patriark/WD-18TB/.snapshots"

# Local snapshot directories
LOCAL_HOME_SNAPSHOTS="$HOME/.snapshots"
LOCAL_POOL_SNAPSHOTS="/mnt/btrfs-pool/.snapshots"

# Date formats
DATE_DAILY=$(date +%Y%m%d)
DATE_HOURLY=$(date +%Y%m%d%H)
DATE_WEEKLY=$(date +%Y%m%d)
DATE_MONTHLY=$(date +%Y%m%d)

# Log file
LOG_DIR="$HOME/containers/data/backup-logs"
LOG_FILE="$LOG_DIR/backup-$(date +%Y%m).log"

# Dry run mode (set by --dry-run flag)
DRY_RUN=false
VERBOSE=false
LOCAL_ONLY=false
EXTERNAL_ONLY=false
TIER_FILTER=""
SUBVOL_FILTER=""

################################################################################
# TIER 1: CRITICAL - Daily local, Weekly external
################################################################################

# htpc-home (/home subvolume)
TIER1_HOME_ENABLED=true
TIER1_HOME_SOURCE="/home"
TIER1_HOME_LOCAL_DIR="$LOCAL_HOME_SNAPSHOTS/htpc-home"
TIER1_HOME_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/htpc-home"
TIER1_HOME_LOCAL_RETENTION_DAILY=7      # Keep 7 daily snapshots locally
TIER1_HOME_EXTERNAL_RETENTION_WEEKLY=8  # Keep 8 weekly snapshots on external
TIER1_HOME_EXTERNAL_RETENTION_MONTHLY=12 # Keep 12 monthly snapshots on external
TIER1_HOME_SCHEDULE="daily"             # daily | weekly | monthly

# subvol3-opptak (private recordings - HEIGHTENED BACKUP DEMANDS)
TIER1_OPPTAK_ENABLED=true
TIER1_OPPTAK_SOURCE="/mnt/btrfs-pool/subvol3-opptak"
TIER1_OPPTAK_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol3-opptak"
TIER1_OPPTAK_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol3-opptak"
TIER1_OPPTAK_LOCAL_RETENTION_DAILY=7
TIER1_OPPTAK_EXTERNAL_RETENTION_WEEKLY=8
TIER1_OPPTAK_EXTERNAL_RETENTION_MONTHLY=12
TIER1_OPPTAK_SCHEDULE="daily"

# subvol7-containers (operational data)
TIER1_CONTAINERS_ENABLED=true
TIER1_CONTAINERS_SOURCE="/mnt/btrfs-pool/subvol7-containers"
TIER1_CONTAINERS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol7-containers"
TIER1_CONTAINERS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol7-containers"
TIER1_CONTAINERS_LOCAL_RETENTION_DAILY=7
TIER1_CONTAINERS_EXTERNAL_RETENTION_WEEKLY=4
TIER1_CONTAINERS_EXTERNAL_RETENTION_MONTHLY=6
TIER1_CONTAINERS_SCHEDULE="daily"

################################################################################
# TIER 2: IMPORTANT - Daily/Monthly local, Weekly/Monthly external
################################################################################

# subvol1-docs (documents)
TIER2_DOCS_ENABLED=true
TIER2_DOCS_SOURCE="/mnt/btrfs-pool/subvol1-docs"
TIER2_DOCS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol1-docs"
TIER2_DOCS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol1-docs"
TIER2_DOCS_LOCAL_RETENTION_DAILY=7
TIER2_DOCS_EXTERNAL_RETENTION_WEEKLY=8
TIER2_DOCS_EXTERNAL_RETENTION_MONTHLY=6
TIER2_DOCS_SCHEDULE="daily"

# htpc-root (/ root subvolume - monthly only per architecture doc)
TIER2_ROOT_ENABLED=true
TIER2_ROOT_SOURCE="/"
TIER2_ROOT_LOCAL_DIR="$LOCAL_HOME_SNAPSHOTS/htpc-root"
TIER2_ROOT_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/htpc-root"
TIER2_ROOT_LOCAL_RETENTION_MONTHLY=1    # Keep ONLY 1 local snapshot
TIER2_ROOT_EXTERNAL_RETENTION_MONTHLY=6
TIER2_ROOT_SCHEDULE="monthly"

################################################################################
# TIER 3: STANDARD - Weekly local, Monthly external
################################################################################

# subvol2-pics (pictures/art - mostly replaceable)
TIER3_PICS_ENABLED=true
TIER3_PICS_SOURCE="/mnt/btrfs-pool/subvol2-pics"
TIER3_PICS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol2-pics"
TIER3_PICS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol2-pics"
TIER3_PICS_LOCAL_RETENTION_WEEKLY=4
TIER3_PICS_EXTERNAL_RETENTION_MONTHLY=12
TIER3_PICS_SCHEDULE="weekly"

################################################################################
# END OF CONFIGURATION SECTION
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# HELPER FUNCTIONS
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"

    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
    esac
}

run_cmd() {
    local cmd="$*"

    if [[ "$VERBOSE" == "true" ]]; then
        log INFO "Executing: $cmd"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    fi

    if eval "$cmd"; then
        return 0
    else
        log ERROR "Command failed: $cmd"
        return 1
    fi
}

check_external_mounted() {
    if [[ ! -d "$EXTERNAL_BACKUP_ROOT" ]]; then
        log ERROR "External backup drive not mounted at $EXTERNAL_BACKUP_ROOT"
        return 1
    fi

    if ! mountpoint -q "$(dirname "$EXTERNAL_BACKUP_ROOT")"; then
        log WARNING "External backup location may not be mounted"
    fi

    return 0
}

create_snapshot() {
    local source=$1
    local dest=$2
    local description=${3:-""}

    if [[ ! -d "$source" ]]; then
        log ERROR "Source subvolume does not exist: $source"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"

    if [[ -d "$dest" ]]; then
        log WARNING "Snapshot already exists: $dest"
        return 0
    fi

    log INFO "Creating snapshot: $source -> $dest"
    run_cmd "sudo btrfs subvolume snapshot -r '$source' '$dest'"

    return $?
}

send_snapshot_incremental() {
    local parent_snapshot=$1
    local new_snapshot=$2
    local dest_dir=$3

    if [[ ! -d "$new_snapshot" ]]; then
        log ERROR "Source snapshot does not exist: $new_snapshot"
        return 1
    fi

    mkdir -p "$dest_dir"

    local dest_snapshot="$dest_dir/$(basename "$new_snapshot")"

    if [[ -d "$dest_snapshot" ]]; then
        log WARNING "Destination snapshot already exists: $dest_snapshot"
        return 0
    fi

    if [[ -n "$parent_snapshot" ]] && [[ -d "$parent_snapshot" ]]; then
        log INFO "Sending incremental snapshot: $new_snapshot (parent: $parent_snapshot)"
        run_cmd "sudo btrfs send -p '$parent_snapshot' '$new_snapshot' | sudo btrfs receive '$dest_dir'"
    else
        log INFO "Sending full snapshot: $new_snapshot"
        run_cmd "sudo btrfs send '$new_snapshot' | sudo btrfs receive '$dest_dir'"
    fi

    return $?
}

cleanup_old_snapshots() {
    local snapshot_dir=$1
    local retention_count=$2
    local pattern=$3  # e.g., "*-daily" or "*-weekly"

    if [[ ! -d "$snapshot_dir" ]]; then
        log WARNING "Snapshot directory does not exist: $snapshot_dir"
        return 0
    fi

    # Get list of snapshots matching pattern, sorted by modification time (oldest first)
    local snapshots=($(find "$snapshot_dir" -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort | awk '{print $2}'))

    local count=${#snapshots[@]}

    if [[ $count -le $retention_count ]]; then
        log INFO "No cleanup needed for $snapshot_dir (found $count, keeping $retention_count)"
        return 0
    fi

    local to_delete=$((count - retention_count))
    log INFO "Cleaning up $to_delete old snapshots from $snapshot_dir (keeping $retention_count)"

    for ((i=0; i<to_delete; i++)); do
        local snapshot="${snapshots[$i]}"
        log INFO "Deleting old snapshot: $snapshot"
        run_cmd "sudo btrfs subvolume delete '$snapshot'"
    done

    return 0
}

get_latest_snapshot() {
    local snapshot_dir=$1
    local pattern=$2

    if [[ ! -d "$snapshot_dir" ]]; then
        echo ""
        return 1
    fi

    # Find most recent snapshot matching pattern
    local latest=$(find "$snapshot_dir" -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort -r | head -1 | awk '{print $2}')

    echo "$latest"
}

################################################################################
# BACKUP FUNCTIONS BY TIER
################################################################################

backup_tier1_home() {
    log INFO "=== Processing Tier 1: htpc-home ==="

    if [[ "$TIER1_HOME_ENABLED" != "true" ]]; then
        log INFO "htpc-home backup disabled, skipping"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-htpc-home"
    local local_snapshot="$TIER1_HOME_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_HOME_SOURCE" "$local_snapshot"
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ "$TIER1_HOME_SCHEDULE" == "daily" ]]; then
        # Only send on the designated weekly backup day
        if [[ $(date +%u) -eq 7 ]]; then  # Sunday
            check_external_mounted || return 1

            local parent=$(get_latest_snapshot "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_HOME_EXTERNAL_DIR"

            # Cleanup external snapshots
            cleanup_old_snapshots "$TIER1_HOME_EXTERNAL_DIR" "$TIER1_HOME_EXTERNAL_RETENTION_WEEKLY" "*-htpc-home"
        fi
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_LOCAL_RETENTION_DAILY" "*-htpc-home"

    log SUCCESS "Completed Tier 1: htpc-home"
}

backup_tier1_opptak() {
    log INFO "=== Processing Tier 1: subvol3-opptak ==="

    if [[ "$TIER1_OPPTAK_ENABLED" != "true" ]]; then
        log INFO "subvol3-opptak backup disabled, skipping"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-opptak"
    local local_snapshot="$TIER1_OPPTAK_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_OPPTAK_SOURCE" "$local_snapshot"
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 7 ]]; then
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_OPPTAK_EXTERNAL_DIR"

        # Cleanup external snapshots
        cleanup_old_snapshots "$TIER1_OPPTAK_EXTERNAL_DIR" "$TIER1_OPPTAK_EXTERNAL_RETENTION_WEEKLY" "*-opptak"
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_LOCAL_RETENTION_DAILY" "*-opptak"

    log SUCCESS "Completed Tier 1: subvol3-opptak"
}

backup_tier1_containers() {
    log INFO "=== Processing Tier 1: subvol7-containers ==="

    if [[ "$TIER1_CONTAINERS_ENABLED" != "true" ]]; then
        log INFO "subvol7-containers backup disabled, skipping"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-containers"
    local local_snapshot="$TIER1_CONTAINERS_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_CONTAINERS_SOURCE" "$local_snapshot"
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 7 ]]; then
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_CONTAINERS_EXTERNAL_DIR"

        # Cleanup external snapshots
        cleanup_old_snapshots "$TIER1_CONTAINERS_EXTERNAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_RETENTION_WEEKLY" "*-containers"
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_LOCAL_RETENTION_DAILY" "*-containers"

    log SUCCESS "Completed Tier 1: subvol7-containers"
}

backup_tier2_docs() {
    log INFO "=== Processing Tier 2: subvol1-docs ==="

    if [[ "$TIER2_DOCS_ENABLED" != "true" ]]; then
        log INFO "subvol1-docs backup disabled, skipping"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-docs"
    local local_snapshot="$TIER2_DOCS_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER2_DOCS_SOURCE" "$local_snapshot"
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 7 ]]; then
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER2_DOCS_EXTERNAL_DIR" "*-docs")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_DOCS_EXTERNAL_DIR"

        # Cleanup external snapshots
        cleanup_old_snapshots "$TIER2_DOCS_EXTERNAL_DIR" "$TIER2_DOCS_EXTERNAL_RETENTION_WEEKLY" "*-docs"
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_LOCAL_RETENTION_DAILY" "*-docs"

    log SUCCESS "Completed Tier 2: subvol1-docs"
}

backup_tier2_root() {
    log INFO "=== Processing Tier 2: htpc-root ==="

    if [[ "$TIER2_ROOT_ENABLED" != "true" ]]; then
        log INFO "htpc-root backup disabled, skipping"
        return 0
    fi

    # Root is monthly only
    if [[ $(date +%d) -ne 01 ]]; then
        log INFO "htpc-root backup runs on 1st of month only, skipping"
        return 0
    fi

    local snapshot_name="${DATE_MONTHLY}-htpc-root"
    local local_snapshot="$TIER2_ROOT_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER2_ROOT_SOURCE" "$local_snapshot"
    fi

    # Send to external (monthly)
    if [[ "$LOCAL_ONLY" != "true" ]]; then
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_ROOT_EXTERNAL_DIR"

        # Cleanup external snapshots
        cleanup_old_snapshots "$TIER2_ROOT_EXTERNAL_DIR" "$TIER2_ROOT_EXTERNAL_RETENTION_MONTHLY" "*-htpc-root"
    fi

    # Cleanup local snapshots - keep only 1
    cleanup_old_snapshots "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_LOCAL_RETENTION_MONTHLY" "*-htpc-root"

    log SUCCESS "Completed Tier 2: htpc-root"
}

backup_tier3_pics() {
    log INFO "=== Processing Tier 3: subvol2-pics ==="

    if [[ "$TIER3_PICS_ENABLED" != "true" ]]; then
        log INFO "subvol2-pics backup disabled, skipping"
        return 0
    fi

    # Weekly local snapshots
    if [[ $(date +%u) -ne 7 ]]; then
        log INFO "subvol2-pics local backup runs on Sundays only, skipping"
        return 0
    fi

    local snapshot_name="${DATE_WEEKLY}-pics-weekly"
    local local_snapshot="$TIER3_PICS_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER3_PICS_SOURCE" "$local_snapshot"
    fi

    # Send to external (monthly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%d) -le 7 ]]; then  # First week of month
        check_external_mounted || return 1

        local parent=$(get_latest_snapshot "$TIER3_PICS_EXTERNAL_DIR" "*-pics*")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_PICS_EXTERNAL_DIR"

        # Cleanup external snapshots
        cleanup_old_snapshots "$TIER3_PICS_EXTERNAL_DIR" "$TIER3_PICS_EXTERNAL_RETENTION_MONTHLY" "*-pics*"
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_LOCAL_RETENTION_WEEKLY" "*-pics*"

    log SUCCESS "Completed Tier 3: subvol2-pics"
}

################################################################################
# MAIN EXECUTION
################################################################################

show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --local-only)
                LOCAL_ONLY=true
                shift
                ;;
            --external-only)
                EXTERNAL_ONLY=true
                shift
                ;;
            --tier)
                TIER_FILTER="$2"
                shift 2
                ;;
            --subvolume)
                SUBVOL_FILTER="$2"
                shift 2
                ;;
            --help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    log INFO "=========================================="
    log INFO "BTRFS Snapshot & Backup Script Starting"
    log INFO "Date: $(date)"
    log INFO "Dry Run: $DRY_RUN"
    log INFO "=========================================="

    # Run backups based on filters
    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "1" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "home" ]]; then
            backup_tier1_home
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "opptak" ]]; then
            backup_tier1_opptak
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "containers" ]]; then
            backup_tier1_containers
        fi
    fi

    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "2" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "docs" ]]; then
            backup_tier2_docs
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "root" ]]; then
            backup_tier2_root
        fi
    fi

    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "3" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "pics" ]]; then
            backup_tier3_pics
        fi
    fi

    log INFO "=========================================="
    log SUCCESS "BTRFS Snapshot & Backup Script Completed"
    log INFO "=========================================="
}

main "$@"
