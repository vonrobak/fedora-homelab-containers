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
#   - Weekly:  Saturday 04:00 AM - All tiers external backup
#   - Monthly: 1st of month 04:00 AM - Monthly snapshots + external
#
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION SECTION - ADJUST THESE PARAMETERS AS NEEDED
################################################################################

# Backup destination (external drive - two mirrored WD 18TB drives, either may be connected)
EXTERNAL_BACKUP_CANDIDATES=(
    "/run/media/patriark/WD-18TB"
    "/run/media/patriark/WD-18TB1"
)
EXTERNAL_BACKUP_ROOT=""
for candidate in "${EXTERNAL_BACKUP_CANDIDATES[@]}"; do
    if mountpoint -q "$candidate" 2>/dev/null; then
        EXTERNAL_BACKUP_ROOT="$candidate/.snapshots"
        break
    fi
done
# Fallback to first candidate (check_external_mounted will catch if not mounted)
EXTERNAL_BACKUP_ROOT="${EXTERNAL_BACKUP_ROOT:-${EXTERNAL_BACKUP_CANDIDATES[0]}/.snapshots}"

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

# Prometheus metrics
METRICS_DIR="$HOME/containers/data/backup-metrics"
METRICS_FILE="$METRICS_DIR/backup.prom"

# Dry run mode (set by --dry-run flag)
DRY_RUN=false
VERBOSE=false
LOCAL_ONLY=false
EXTERNAL_ONLY=false
TIER_FILTER=""
SUBVOL_FILTER=""

# Retry state: track completed subvolumes to skip on retry
STATE_DIR="/tmp"
STATE_FILE="$STATE_DIR/btrfs-backup-completed-${DATE_DAILY}"

# Discord webhook for failure notifications
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
if [[ -z "$DISCORD_WEBHOOK" && -f "$HOME/containers/config/alertmanager/discord-webhook.txt" ]]; then
    DISCORD_WEBHOOK=$(cat "$HOME/containers/config/alertmanager/discord-webhook.txt" 2>/dev/null || echo "")
fi

# Metrics tracking
declare -A BACKUP_SUCCESS
declare -A BACKUP_DURATION
declare -A BACKUP_TIMESTAMP
declare -A SNAPSHOT_COUNT_LOCAL
declare -A SNAPSHOT_COUNT_EXTERNAL
SCRIPT_START_TIME=$(date +%s)

# Failure tracking
FAILED_SUBVOLS=()
FAILED_REASONS=()
SUCCEEDED_SUBVOLS=()
SKIPPED_SUBVOLS=()

################################################################################
# TIER 1: CRITICAL - Daily local, Weekly external
################################################################################

# htpc-home (/home subvolume)
TIER1_HOME_ENABLED=true
TIER1_HOME_SOURCE="/home"
TIER1_HOME_LOCAL_DIR="$LOCAL_HOME_SNAPSHOTS/htpc-home"
TIER1_HOME_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/htpc-home"
TIER1_HOME_LOCAL_RETENTION_DAILY=15     # Keep 15 daily snapshots locally
TIER1_HOME_EXTERNAL_RETENTION_WEEKLY=8  # Keep 8 weekly snapshots on external
TIER1_HOME_EXTERNAL_RETENTION_MONTHLY=12 # Keep 12 monthly snapshots on external
TIER1_HOME_SCHEDULE="daily"             # daily | weekly | monthly

# subvol3-opptak (private recordings - HEIGHTENED BACKUP DEMANDS)
TIER1_OPPTAK_ENABLED=true
TIER1_OPPTAK_SOURCE="/mnt/btrfs-pool/subvol3-opptak"
TIER1_OPPTAK_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol3-opptak"
TIER1_OPPTAK_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol3-opptak"
TIER1_OPPTAK_LOCAL_RETENTION_DAILY=15
TIER1_OPPTAK_EXTERNAL_RETENTION_WEEKLY=8
TIER1_OPPTAK_EXTERNAL_RETENTION_MONTHLY=12
TIER1_OPPTAK_SCHEDULE="daily"

# subvol7-containers (operational data)
TIER1_CONTAINERS_ENABLED=true
TIER1_CONTAINERS_SOURCE="/mnt/btrfs-pool/subvol7-containers"
TIER1_CONTAINERS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol7-containers"
TIER1_CONTAINERS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol7-containers"
TIER1_CONTAINERS_LOCAL_RETENTION_DAILY=15
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
TIER2_DOCS_LOCAL_RETENTION_DAILY=15
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

# subvol4-multimedia (Jellyfin media - 5.8TB, replaceable but time-consuming)
# NOTE: Initially disabled for external backup - do initial backup manually first!
# Initial backup estimated at ~27 hours. After first backup, enable external.
TIER3_MULTIMEDIA_ENABLED=true
TIER3_MULTIMEDIA_SOURCE="/mnt/btrfs-pool/subvol4-multimedia"
TIER3_MULTIMEDIA_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol4-multimedia"
TIER3_MULTIMEDIA_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol4-multimedia"
TIER3_MULTIMEDIA_EXTERNAL_ENABLED=false  # Set to true after initial manual backup
TIER3_MULTIMEDIA_LOCAL_RETENTION_WEEKLY=4
TIER3_MULTIMEDIA_EXTERNAL_RETENTION_MONTHLY=6
TIER3_MULTIMEDIA_SCHEDULE="weekly"

# subvol5-music (Music library - 1.1TB, replaceable)
TIER3_MUSIC_ENABLED=true
TIER3_MUSIC_SOURCE="/mnt/btrfs-pool/subvol5-music"
TIER3_MUSIC_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol5-music"
TIER3_MUSIC_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol5-music"
TIER3_MUSIC_LOCAL_RETENTION_WEEKLY=4
TIER3_MUSIC_EXTERNAL_RETENTION_MONTHLY=6
TIER3_MUSIC_SCHEDULE="weekly"

# subvol6-tmp (Temporary files/cache - 6.2GB, fully replaceable)
TIER3_TMP_ENABLED=true
TIER3_TMP_SOURCE="/mnt/btrfs-pool/subvol6-tmp"
TIER3_TMP_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol6-tmp"
TIER3_TMP_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol6-tmp"
TIER3_TMP_LOCAL_RETENTION_WEEKLY=2  # Only 2 weeks (cache data)
TIER3_TMP_EXTERNAL_RETENTION_MONTHLY=3  # Only 3 months (cache data)
TIER3_TMP_SCHEDULE="weekly"

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

is_completed_today() {
    local subvol_name=$1
    if [[ -f "$STATE_FILE" ]] && grep -q "^${subvol_name}$" "$STATE_FILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

mark_completed() {
    local subvol_name=$1
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$subvol_name" >> "$STATE_FILE"
    fi
    SUCCEEDED_SUBVOLS+=("$subvol_name")
}

record_failure() {
    local subvol_name=$1
    local reason=$2
    FAILED_SUBVOLS+=("$subvol_name")
    FAILED_REASONS+=("$reason")
}

check_external_space() {
    local dest_dir=$1
    local is_full_send=$2        # "full" or "incremental"
    local source_snapshot=$3

    local mount_point
    mount_point=$(df --output=target "$dest_dir" 2>/dev/null | tail -1)
    if [[ -z "$mount_point" ]]; then
        log WARNING "Could not determine mount point for $dest_dir"
        return 0  # Don't block on detection failure
    fi

    local avail_bytes
    avail_bytes=$(df --output=avail -B1 "$mount_point" 2>/dev/null | tail -1 | tr -d ' ')
    local avail_gb=$(( avail_bytes / 1073741824 ))

    if [[ "$is_full_send" == "full" ]]; then
        # For full sends, estimate using source subvolume size
        # Try btrfs subvolume show first (exclusive data), fall back to du
        local required_bytes=0
        local size_source="unknown"

        local exclusive_bytes
        exclusive_bytes=$(sudo btrfs subvolume show "$source_snapshot" 2>/dev/null | grep -i "exclusive" | head -1 | awk '{print $NF}' || echo "0")

        # Parse human-readable size (e.g., "2.10TiB", "500.00GiB", "100.00MiB")
        if [[ "$exclusive_bytes" =~ ([0-9.]+)TiB ]]; then
            required_bytes=$(echo "${BASH_REMATCH[1]} * 1099511627776" | bc | cut -d. -f1)
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)GiB ]]; then
            required_bytes=$(echo "${BASH_REMATCH[1]} * 1073741824" | bc | cut -d. -f1)
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)MiB ]]; then
            required_bytes=$(echo "${BASH_REMATCH[1]} * 1048576" | bc | cut -d. -f1)
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)KiB ]]; then
            required_bytes=$(echo "${BASH_REMATCH[1]} * 1024" | bc | cut -d. -f1)
            size_source="btrfs-exclusive"
        fi

        # Fallback: use du if btrfs subvolume show didn't return useful data
        if [[ $required_bytes -eq 0 ]] && [[ -d "$source_snapshot" ]]; then
            local du_output
            du_output=$(du -sb "$source_snapshot" 2>/dev/null | head -1 | awk '{print $1}' | tr -cd '0-9')
            required_bytes=${du_output:-0}
            size_source="du"
        fi

        local required_gb=$(( required_bytes / 1073741824 ))
        log INFO "Space check (full send): available=${avail_gb}GB, estimated=${required_gb}GB (source: $size_source)"

        if [[ $required_bytes -gt 0 ]] && [[ $avail_bytes -lt $required_bytes ]]; then
            log ERROR "Insufficient space for full send: need ~${required_gb}GB, have ${avail_gb}GB"
            return 1
        fi

        # Warn if tight even when we can't estimate precisely
        if [[ $avail_gb -lt 50 ]]; then
            log WARNING "External drive has only ${avail_gb}GB free — full send may fail"
        fi
    else
        # For incremental sends, just ensure reasonable headroom
        log INFO "Space check (incremental): available=${avail_gb}GB"
        if [[ $avail_gb -lt 10 ]]; then
            log ERROR "Insufficient space for incremental send: only ${avail_gb}GB free (need at least 10GB headroom)"
            return 1
        fi
    fi

    return 0
}

pin_parent() {
    local local_dir=$1
    local snapshot_name=$2
    local pin_file="$local_dir/.last-external-parent"
    echo "$snapshot_name" > "$pin_file"
    log INFO "Pinned parent for incremental chain: $snapshot_name"
}

get_pinned_parent() {
    local local_dir=$1
    local pin_file="$local_dir/.last-external-parent"
    if [[ -f "$pin_file" ]]; then
        cat "$pin_file"
    fi
}

check_external_mounted() {
    if [[ ! -d "$EXTERNAL_BACKUP_ROOT" ]]; then
        log ERROR "External backup drive not mounted (checked: ${EXTERNAL_BACKUP_CANDIDATES[*]})"
        return 1
    fi

    if ! mountpoint -q "$(dirname "$EXTERNAL_BACKUP_ROOT")"; then
        log WARNING "External backup location may not be a mountpoint: $(dirname "$EXTERNAL_BACKUP_ROOT")"
        return 1
    fi

    log INFO "Using external backup drive: $(dirname "$EXTERNAL_BACKUP_ROOT")"
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

    local send_type="full"
    local send_args=()

    if [[ -n "$parent_snapshot" ]] && [[ -d "$parent_snapshot" ]]; then
        send_type="incremental"
        log INFO "Sending incremental snapshot: $new_snapshot (parent: $parent_snapshot)"
        send_args=(sudo btrfs send -p "$parent_snapshot" "$new_snapshot")
    else
        log INFO "Sending full snapshot: $new_snapshot (no common parent — this may take a long time)"
        send_args=(sudo btrfs send "$new_snapshot")
    fi

    # Pre-flight space check
    check_external_space "$dest_dir" "$send_type" "$new_snapshot" || return 1

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: ${send_args[*]} | sudo btrfs receive '$dest_dir'"
        return 0
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        log INFO "Executing: ${send_args[*]} | sudo btrfs receive '$dest_dir'"
    fi

    # Execute with stderr capture for both sides of the pipeline
    local stderr_file
    stderr_file=$(mktemp /tmp/btrfs-send-stderr.XXXXXX)

    "${send_args[@]}" 2>"${stderr_file}.send" | sudo btrfs receive "$dest_dir" 2>"${stderr_file}.recv"
    local pipe_status=("${PIPESTATUS[@]}")

    local send_exit=${pipe_status[0]}
    local recv_exit=${pipe_status[1]}

    if [[ $send_exit -ne 0 ]] || [[ $recv_exit -ne 0 ]]; then
        local send_err recv_err
        send_err=$(cat "${stderr_file}.send" 2>/dev/null || echo "")
        recv_err=$(cat "${stderr_file}.recv" 2>/dev/null || echo "")

        log ERROR "btrfs send/receive failed (send_exit=$send_exit, recv_exit=$recv_exit)"
        [[ -n "$send_err" ]] && log ERROR "  send stderr: $send_err"
        [[ -n "$recv_err" ]] && log ERROR "  recv stderr: $recv_err"

        # Clean up partial receive if it exists
        if [[ -d "$dest_snapshot" ]]; then
            log WARNING "Cleaning up incomplete snapshot at destination: $dest_snapshot"
            sudo btrfs subvolume delete "$dest_snapshot" 2>/dev/null || \
                log ERROR "Failed to clean up partial snapshot: $dest_snapshot"
        fi

        rm -f "${stderr_file}" "${stderr_file}.send" "${stderr_file}.recv"
        return 1
    fi

    rm -f "${stderr_file}" "${stderr_file}.send" "${stderr_file}.recv"
    return 0
}

cleanup_old_snapshots() {
    local snapshot_dir=$1
    local retention_count=$2
    local pattern=$3  # e.g., "*-daily" or "*-weekly"

    if [[ ! -d "$snapshot_dir" ]]; then
        log WARNING "Snapshot directory does not exist: $snapshot_dir"
        return 0
    fi

    # Check for pinned parent that must be preserved
    local pinned_name
    pinned_name=$(get_pinned_parent "$snapshot_dir")

    # Get list of snapshots matching pattern, sorted by modification time (oldest first)
    local snapshots=($(find "$snapshot_dir" -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort | awk '{print $2}'))

    local count=${#snapshots[@]}

    if [[ $count -le $retention_count ]]; then
        log INFO "No cleanup needed for $snapshot_dir (found $count, keeping $retention_count)"
        return 0
    fi

    local to_delete=$((count - retention_count))
    local deleted=0
    log INFO "Cleaning up $to_delete old snapshots from $snapshot_dir (keeping $retention_count)"

    for ((i=0; i<to_delete; i++)); do
        local snapshot="${snapshots[$i]}"
        local snap_basename
        snap_basename=$(basename "$snapshot")

        # Never delete the pinned parent — it's the incremental chain anchor
        if [[ -n "$pinned_name" ]] && [[ "$snap_basename" == "$pinned_name" ]]; then
            log WARNING "Preserving pinned parent snapshot (incremental chain anchor): $snapshot"
            continue
        fi

        log INFO "Deleting old snapshot: $snapshot"
        run_cmd "sudo btrfs subvolume delete '$snapshot'"
        ((deleted++))
    done

    if [[ -n "$pinned_name" ]] && [[ $deleted -lt $to_delete ]]; then
        log INFO "Retained $(( to_delete - deleted )) snapshot(s) due to pinned parent protection"
    fi

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

get_second_latest_snapshot() {
    local snapshot_dir=$1
    local pattern=$2

    if [[ ! -d "$snapshot_dir" ]]; then
        echo ""
        return 1
    fi

    # Find second most recent snapshot matching pattern (for use as parent in incremental send)
    local second=$(find "$snapshot_dir" -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort -r | sed -n '2p' | awk '{print $2}')

    echo "$second"
}

find_common_parent() {
    # Find a local snapshot that also exists on the external drive (for incremental send)
    # For btrfs send -p to work, the parent must exist locally AND have been received at destination
    local local_dir=$1
    local external_dir=$2
    local pattern=$3

    if [[ ! -d "$local_dir" ]] || [[ ! -d "$external_dir" ]]; then
        echo ""
        return 1
    fi

    # Get local snapshots sorted by date (newest first), excluding the current one being sent
    local local_snapshots=$(find "$local_dir" -maxdepth 1 -type d -name "$pattern" -printf '%f\n' | sort -r)

    # Check each local snapshot to see if it exists on external
    for snap in $local_snapshots; do
        if [[ -d "$external_dir/$snap" ]]; then
            # Found a common ancestor
            echo "$local_dir/$snap"
            return 0
        fi
    done

    # No common parent found - will need full send
    echo ""
    return 1
}

record_backup_metrics() {
    local subvol_name=$1
    local start_time=$2
    local success=$3  # 1 for success, 0 for failure
    local local_snapshot_dir=$4
    local external_snapshot_dir=$5
    local pattern=$6

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    BACKUP_SUCCESS["$subvol_name"]=$success
    BACKUP_DURATION["$subvol_name"]=$duration

    if [[ $success -eq 1 ]]; then
        BACKUP_TIMESTAMP["$subvol_name"]=$end_time
    fi

    # Count snapshots (use -mindepth 1 to exclude the search directory itself)
    if [[ -d "$local_snapshot_dir" ]]; then
        local local_count=$(find "$local_snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" 2>/dev/null | wc -l)
        SNAPSHOT_COUNT_LOCAL["$subvol_name"]=$local_count
    fi

    if [[ -d "$external_snapshot_dir" ]]; then
        local external_count=$(find "$external_snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" 2>/dev/null | wc -l)
        SNAPSHOT_COUNT_EXTERNAL["$subvol_name"]=$external_count
    else
        SNAPSHOT_COUNT_EXTERNAL["$subvol_name"]=0
    fi
}

################################################################################
# BACKUP FUNCTIONS BY TIER
################################################################################

backup_tier1_home() {
    local subvol_name="htpc-home"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 1: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER1_HOME_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-htpc-home"
    local local_snapshot="$TIER1_HOME_LOCAL_DIR/$snapshot_name"

    # Create local snapshot
    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_HOME_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
            return 1
        }
    fi

    # Send to external (weekly)
    if [[ "$LOCAL_ONLY" != "true" ]] && [[ "$TIER1_HOME_SCHEDULE" == "daily" ]]; then
        if [[ $(date +%u) -eq 6 ]]; then  # Saturday
            check_external_mounted || {
                record_failure "$subvol_name" "External drive not mounted"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
                return 1
            }

            local parent=$(find_common_parent "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_HOME_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
                return 1
            }

            # Pin the snapshot we just sent as the incremental chain anchor
            pin_parent "$TIER1_HOME_LOCAL_DIR" "$snapshot_name"

            cleanup_old_snapshots "$TIER1_HOME_EXTERNAL_DIR" "$TIER1_HOME_EXTERNAL_RETENTION_WEEKLY" "*-htpc-home"
        fi
    fi

    # Cleanup local snapshots
    cleanup_old_snapshots "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_LOCAL_RETENTION_DAILY" "*-htpc-home"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 1: $subvol_name"
}

backup_tier1_opptak() {
    local subvol_name="subvol3-opptak"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 1: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER1_OPPTAK_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-opptak"
    local local_snapshot="$TIER1_OPPTAK_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_OPPTAK_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 6 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
            return 1
        }

        local parent=$(find_common_parent "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_OPPTAK_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
            return 1
        }

        pin_parent "$TIER1_OPPTAK_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER1_OPPTAK_EXTERNAL_DIR" "$TIER1_OPPTAK_EXTERNAL_RETENTION_WEEKLY" "*-opptak"
    fi

    cleanup_old_snapshots "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_LOCAL_RETENTION_DAILY" "*-opptak"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 1: $subvol_name"
}

backup_tier1_containers() {
    local subvol_name="subvol7-containers"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 1: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER1_CONTAINERS_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-containers"
    local local_snapshot="$TIER1_CONTAINERS_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER1_CONTAINERS_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 6 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
            return 1
        }

        local parent=$(find_common_parent "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_CONTAINERS_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
            return 1
        }

        pin_parent "$TIER1_CONTAINERS_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER1_CONTAINERS_EXTERNAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_RETENTION_WEEKLY" "*-containers"
    fi

    cleanup_old_snapshots "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_LOCAL_RETENTION_DAILY" "*-containers"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 1: $subvol_name"
}

backup_tier2_docs() {
    local subvol_name="subvol1-docs"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 2: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER2_DOCS_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
        return 0
    fi

    local snapshot_name="${DATE_DAILY}-docs"
    local local_snapshot="$TIER2_DOCS_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER2_DOCS_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%u) -eq 6 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
            return 1
        }

        local parent=$(find_common_parent "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_DOCS_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
            return 1
        }

        pin_parent "$TIER2_DOCS_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER2_DOCS_EXTERNAL_DIR" "$TIER2_DOCS_EXTERNAL_RETENTION_WEEKLY" "*-docs"
    fi

    cleanup_old_snapshots "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_LOCAL_RETENTION_DAILY" "*-docs"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 2: $subvol_name"
}

backup_tier2_root() {
    local subvol_name="htpc-root"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 2: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER2_ROOT_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
        return 0
    fi

    # Root is monthly only
    if [[ $(date +%d) -ne 01 ]]; then
        log INFO "$subvol_name backup runs on 1st of month only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
        return 0
    fi

    local snapshot_name="${DATE_MONTHLY}-htpc-root"
    local local_snapshot="$TIER2_ROOT_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER2_ROOT_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
            return 1
        }

        local parent=$(find_common_parent "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_ROOT_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
            return 1
        }

        pin_parent "$TIER2_ROOT_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER2_ROOT_EXTERNAL_DIR" "$TIER2_ROOT_EXTERNAL_RETENTION_MONTHLY" "*-htpc-root"
    fi

    cleanup_old_snapshots "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_LOCAL_RETENTION_MONTHLY" "*-htpc-root"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 2: $subvol_name"
}

backup_tier3_pics() {
    local subvol_name="subvol2-pics"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 3: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER3_PICS_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
        return 0
    fi

    if [[ $(date +%u) -ne 6 ]]; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
        return 0
    fi

    local snapshot_name="${DATE_WEEKLY}-pics"
    local local_snapshot="$TIER3_PICS_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER3_PICS_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%d) -le 7 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
            return 1
        }

        local parent=$(find_common_parent "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_PICS_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
            return 1
        }

        pin_parent "$TIER3_PICS_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER3_PICS_EXTERNAL_DIR" "$TIER3_PICS_EXTERNAL_RETENTION_MONTHLY" "*-pics*"
    fi

    cleanup_old_snapshots "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_LOCAL_RETENTION_WEEKLY" "*-pics*"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 3: $subvol_name"
}

backup_tier3_multimedia() {
    local subvol_name="subvol4-multimedia"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 3: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER3_MULTIMEDIA_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
        return 0
    fi

    if [[ $(date +%u) -ne 6 ]]; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
        return 0
    fi

    local snapshot_name="${DATE_WEEKLY}-multimedia"
    local local_snapshot="$TIER3_MULTIMEDIA_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER3_MULTIMEDIA_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
            return 1
        }
    fi

    if [[ "$TIER3_MULTIMEDIA_EXTERNAL_ENABLED" == "true" ]] && [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%d) -le 7 ]]; then
        log INFO "$subvol_name external backup enabled (5.8TB - may take ~27h for initial backup)"
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
            return 1
        }

        local parent=$(find_common_parent "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
            return 1
        }

        pin_parent "$TIER3_MULTIMEDIA_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_RETENTION_MONTHLY" "*-multimedia*"
    elif [[ "$TIER3_MULTIMEDIA_EXTERNAL_ENABLED" != "true" ]]; then
        log WARNING "$subvol_name external backup is DISABLED (set TIER3_MULTIMEDIA_EXTERNAL_ENABLED=true to enable)"
        log WARNING "Do initial manual backup first (see docs/20-operations/guides/tier3-initial-backup.md)"
    fi

    cleanup_old_snapshots "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_LOCAL_RETENTION_WEEKLY" "*-multimedia*"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 3: $subvol_name"
}

backup_tier3_music() {
    local subvol_name="subvol5-music"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 3: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER3_MUSIC_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
        return 0
    fi

    if [[ $(date +%u) -ne 6 ]]; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
        return 0
    fi

    local snapshot_name="${DATE_WEEKLY}-music"
    local local_snapshot="$TIER3_MUSIC_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER3_MUSIC_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%d) -le 7 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
            return 1
        }

        local parent=$(find_common_parent "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_MUSIC_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
            return 1
        }

        pin_parent "$TIER3_MUSIC_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER3_MUSIC_EXTERNAL_DIR" "$TIER3_MUSIC_EXTERNAL_RETENTION_MONTHLY" "*-music*"
    fi

    cleanup_old_snapshots "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_LOCAL_RETENTION_WEEKLY" "*-music*"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 3: $subvol_name"
}

backup_tier3_tmp() {
    local subvol_name="subvol6-tmp"
    local start_time=$(date +%s)
    log INFO "=== Processing Tier 3: $subvol_name ==="

    if is_completed_today "$subvol_name"; then
        log INFO "$subvol_name already completed today, skipping (retry)"
        SKIPPED_SUBVOLS+=("$subvol_name")
        return 0
    fi

    if [[ "$TIER3_TMP_ENABLED" != "true" ]]; then
        log INFO "$subvol_name backup disabled, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
        return 0
    fi

    if [[ $(date +%u) -ne 6 ]]; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
        return 0
    fi

    local snapshot_name="${DATE_WEEKLY}-tmp"
    local local_snapshot="$TIER3_TMP_LOCAL_DIR/$snapshot_name"

    if [[ "$EXTERNAL_ONLY" != "true" ]]; then
        create_snapshot "$TIER3_TMP_SOURCE" "$local_snapshot" || {
            record_failure "$subvol_name" "Local snapshot creation failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
            return 1
        }
    fi

    if [[ "$LOCAL_ONLY" != "true" ]] && [[ $(date +%d) -le 7 ]]; then
        check_external_mounted || {
            record_failure "$subvol_name" "External drive not mounted"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
            return 1
        }

        local parent=$(find_common_parent "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*")
        send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_TMP_EXTERNAL_DIR" || {
            record_failure "$subvol_name" "External send failed"
            record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
            return 1
        }

        pin_parent "$TIER3_TMP_LOCAL_DIR" "$snapshot_name"
        cleanup_old_snapshots "$TIER3_TMP_EXTERNAL_DIR" "$TIER3_TMP_EXTERNAL_RETENTION_MONTHLY" "*-tmp*"
    fi

    cleanup_old_snapshots "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_LOCAL_RETENTION_WEEKLY" "*-tmp*"

    record_backup_metrics "$subvol_name" "$start_time" 1 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
    mark_completed "$subvol_name"
    log SUCCESS "Completed Tier 3: $subvol_name"
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

export_prometheus_metrics() {
    # Export backup metrics in Prometheus format
    mkdir -p "$METRICS_DIR"

    local temp_file="${METRICS_FILE}.$$"

    {
        echo "# HELP backup_last_success_timestamp Unix timestamp of last successful backup"
        echo "# TYPE backup_last_success_timestamp gauge"

        for subvol in "${!BACKUP_TIMESTAMP[@]}"; do
            echo "backup_last_success_timestamp{subvolume=\"$subvol\"} ${BACKUP_TIMESTAMP[$subvol]}"
        done

        echo ""
        echo "# HELP backup_success Whether last backup succeeded (1) or failed (0)"
        echo "# TYPE backup_success gauge"

        for subvol in "${!BACKUP_SUCCESS[@]}"; do
            echo "backup_success{subvolume=\"$subvol\"} ${BACKUP_SUCCESS[$subvol]}"
        done

        echo ""
        echo "# HELP backup_duration_seconds Time taken for last backup"
        echo "# TYPE backup_duration_seconds gauge"

        for subvol in "${!BACKUP_DURATION[@]}"; do
            echo "backup_duration_seconds{subvolume=\"$subvol\"} ${BACKUP_DURATION[$subvol]}"
        done

        echo ""
        echo "# HELP backup_snapshot_count Number of snapshots present"
        echo "# TYPE backup_snapshot_count gauge"

        for subvol in "${!SNAPSHOT_COUNT_LOCAL[@]}"; do
            echo "backup_snapshot_count{subvolume=\"$subvol\",location=\"local\"} ${SNAPSHOT_COUNT_LOCAL[$subvol]}"
        done

        for subvol in "${!SNAPSHOT_COUNT_EXTERNAL[@]}"; do
            echo "backup_snapshot_count{subvolume=\"$subvol\",location=\"external\"} ${SNAPSHOT_COUNT_EXTERNAL[$subvol]}"
        done

        echo ""
        echo "# HELP backup_script_last_run_timestamp Unix timestamp when script last ran"
        echo "# TYPE backup_script_last_run_timestamp gauge"
        echo "backup_script_last_run_timestamp $(date +%s)"

    } > "$temp_file"

    # Atomic move
    mv "$temp_file" "$METRICS_FILE"

    if [[ "$VERBOSE" == "true" ]]; then
        log INFO "Metrics exported to: $METRICS_FILE"
    fi
}

send_failure_notification() {
    if [[ ${#FAILED_SUBVOLS[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ -z "$DISCORD_WEBHOOK" ]]; then
        log WARNING "No Discord webhook configured — cannot send failure notification"
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        log WARNING "jq not found — cannot send Discord notification"
        return 0
    fi

    local fail_list=""
    for i in "${!FAILED_SUBVOLS[@]}"; do
        fail_list="${fail_list}• **${FAILED_SUBVOLS[$i]}**: ${FAILED_REASONS[$i]}\n"
    done

    local summary="Backup failures on $(date '+%Y-%m-%d %H:%M'):\n${fail_list}\nSucceeded: ${#SUCCEEDED_SUBVOLS[@]} | Failed: ${#FAILED_SUBVOLS[@]} | Skipped: ${#SKIPPED_SUBVOLS[@]}"

    local payload
    payload=$(jq -n \
        --arg msg "$summary" \
        '{
          embeds: [{
            title: "BTRFS Backup Failed",
            description: $msg,
            color: 15158332,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
          }]
        }')

    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1 || log WARNING "Failed to send Discord notification"
}

print_summary() {
    local script_end_time=$(date +%s)
    local total_duration=$(( script_end_time - SCRIPT_START_TIME ))

    log INFO "=========================================="
    log INFO "BACKUP RUN SUMMARY (${total_duration}s)"
    log INFO "=========================================="

    if [[ ${#SUCCEEDED_SUBVOLS[@]} -gt 0 ]]; then
        log SUCCESS "Succeeded (${#SUCCEEDED_SUBVOLS[@]}): ${SUCCEEDED_SUBVOLS[*]}"
    fi

    if [[ ${#SKIPPED_SUBVOLS[@]} -gt 0 ]]; then
        log INFO "Skipped (${#SKIPPED_SUBVOLS[@]}): ${SKIPPED_SUBVOLS[*]}"
    fi

    if [[ ${#FAILED_SUBVOLS[@]} -gt 0 ]]; then
        log ERROR "FAILED (${#FAILED_SUBVOLS[@]}):"
        for i in "${!FAILED_SUBVOLS[@]}"; do
            log ERROR "  ${FAILED_SUBVOLS[$i]}: ${FAILED_REASONS[$i]}"
        done
        log ERROR "Manual intervention may be required — check logs above for details"
    fi

    log INFO "=========================================="
}

main() {
    parse_args "$@"

    # Clean up stale state files from previous days
    find "$STATE_DIR" -maxdepth 1 -name "btrfs-backup-completed-*" \
        ! -name "btrfs-backup-completed-${DATE_DAILY}" -delete 2>/dev/null || true

    log INFO "=========================================="
    log INFO "BTRFS Snapshot & Backup Script Starting"
    log INFO "Date: $(date)"
    log INFO "Dry Run: $DRY_RUN"
    if [[ -f "$STATE_FILE" ]]; then
        log INFO "Retry run — previously completed: $(cat "$STATE_FILE" | tr '\n' ' ')"
    fi
    log INFO "=========================================="

    # Run backups based on filters
    # Individual failures are tracked in FAILED_SUBVOLS — don't let set -e kill the script
    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "1" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "home" ]]; then
            backup_tier1_home || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "opptak" ]]; then
            backup_tier1_opptak || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "containers" ]]; then
            backup_tier1_containers || true
        fi
    fi

    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "2" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "docs" ]]; then
            backup_tier2_docs || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "root" ]]; then
            backup_tier2_root || true
        fi
    fi

    if [[ -z "$TIER_FILTER" ]] || [[ "$TIER_FILTER" == "3" ]]; then
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "pics" ]]; then
            backup_tier3_pics || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "multimedia" ]]; then
            backup_tier3_multimedia || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "music" ]]; then
            backup_tier3_music || true
        fi
        if [[ -z "$SUBVOL_FILTER" ]] || [[ "$SUBVOL_FILTER" == "tmp" ]]; then
            backup_tier3_tmp || true
        fi
    fi

    # Print summary
    print_summary

    # Export metrics (unless dry-run)
    if [[ "$DRY_RUN" != "true" ]]; then
        export_prometheus_metrics
    fi

    # Send Discord notification on failures
    if [[ ${#FAILED_SUBVOLS[@]} -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        send_failure_notification
        exit 1
    fi
}

main "$@"
