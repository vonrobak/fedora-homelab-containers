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
#   --subvolume <name>  Run specific subvolume only (overrides schedule)
#                       Names: home, opptak, containers, docs, root, pics,
#                              multimedia, music, tmp
#                       Also accepts full names: htpc-home, subvol3-opptak, etc.
#   --verbose           Verbose output
#   --help              Show this help message
#
# Schedule (via systemd timer at 02:00 AM nightly):
#   - Tier 1/2 (daily): Local snapshot + incremental external send
#   - Tier 3 (weekly):  Local snapshot on Saturdays only
#   - External sends:   Per-subvolume schedule (daily/weekly/monthly)
#   - Local retention:  Graduated (14 daily + 6 weekly + 3 monthly)
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

# Detect which external drive is mounted (for drive-specific pin files)
EXTERNAL_DRIVE_LABEL=""
for candidate in "${EXTERNAL_BACKUP_CANDIDATES[@]}"; do
    if mountpoint -q "$candidate" 2>/dev/null; then
        EXTERNAL_DRIVE_LABEL=$(basename "$candidate")
        break
    fi
done
EXTERNAL_DRIVE_MOUNTED=false
[[ -n "$EXTERNAL_DRIVE_LABEL" ]] && EXTERNAL_DRIVE_MOUNTED=true

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

# Send type tracking (for Prometheus metrics)
declare -A SEND_TYPE  # "incremental", "full", or "" (no send)

################################################################################
# TIER 1: CRITICAL - Daily local, Weekly external
################################################################################

# htpc-home (/home subvolume)
TIER1_HOME_ENABLED=true
TIER1_HOME_SOURCE="/home"
TIER1_HOME_LOCAL_DIR="$LOCAL_HOME_SNAPSHOTS/htpc-home"
TIER1_HOME_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/htpc-home"
TIER1_HOME_LOCAL_SCHEDULE="daily"              # daily | weekly | monthly
TIER1_HOME_EXTERNAL_SCHEDULE="daily"           # daily | weekly | monthly
TIER1_HOME_EXTERNAL_RETENTION=14               # Keep 14 daily snapshots on external

# subvol3-opptak (private recordings - HEIGHTENED BACKUP DEMANDS)
TIER1_OPPTAK_ENABLED=true
TIER1_OPPTAK_SOURCE="/mnt/btrfs-pool/subvol3-opptak"
TIER1_OPPTAK_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol3-opptak"
TIER1_OPPTAK_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol3-opptak"
TIER1_OPPTAK_LOCAL_SCHEDULE="daily"
TIER1_OPPTAK_EXTERNAL_SCHEDULE="daily"
TIER1_OPPTAK_EXTERNAL_RETENTION=14

# subvol7-containers (operational data)
TIER1_CONTAINERS_ENABLED=true
TIER1_CONTAINERS_SOURCE="/mnt/btrfs-pool/subvol7-containers"
TIER1_CONTAINERS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol7-containers"
TIER1_CONTAINERS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol7-containers"
TIER1_CONTAINERS_LOCAL_SCHEDULE="daily"
TIER1_CONTAINERS_EXTERNAL_SCHEDULE="daily"
TIER1_CONTAINERS_EXTERNAL_RETENTION=14

################################################################################
# TIER 2: IMPORTANT - Daily/Monthly local, Weekly/Monthly external
################################################################################

# subvol1-docs (documents)
TIER2_DOCS_ENABLED=true
TIER2_DOCS_SOURCE="/mnt/btrfs-pool/subvol1-docs"
TIER2_DOCS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol1-docs"
TIER2_DOCS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol1-docs"
TIER2_DOCS_LOCAL_SCHEDULE="daily"
TIER2_DOCS_EXTERNAL_SCHEDULE="daily"
TIER2_DOCS_EXTERNAL_RETENTION=14

# htpc-root (/ root subvolume - monthly only per architecture doc)
TIER2_ROOT_ENABLED=true
TIER2_ROOT_SOURCE="/"
TIER2_ROOT_LOCAL_DIR="$LOCAL_HOME_SNAPSHOTS/htpc-root"
TIER2_ROOT_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/htpc-root"
TIER2_ROOT_LOCAL_SCHEDULE="monthly"
TIER2_ROOT_EXTERNAL_SCHEDULE="monthly"
TIER2_ROOT_LOCAL_RETENTION=1             # Keep ONLY 1 local snapshot
TIER2_ROOT_EXTERNAL_RETENTION=6

################################################################################
# TIER 3: STANDARD - Weekly local, Monthly external
################################################################################

# subvol2-pics (pictures/art - mostly replaceable)
TIER3_PICS_ENABLED=true
TIER3_PICS_SOURCE="/mnt/btrfs-pool/subvol2-pics"
TIER3_PICS_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol2-pics"
TIER3_PICS_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol2-pics"
TIER3_PICS_LOCAL_SCHEDULE="weekly"
TIER3_PICS_EXTERNAL_SCHEDULE="first-saturday"
TIER3_PICS_LOCAL_RETENTION=8             # 8 weekly = 2 months
TIER3_PICS_EXTERNAL_RETENTION=6

# subvol4-multimedia (Jellyfin media - 5.8TB, replaceable but time-consuming)
# NOTE: Initially disabled for external backup - do initial backup manually first!
# Initial backup estimated at ~27 hours. After first backup, enable external.
TIER3_MULTIMEDIA_ENABLED=true
TIER3_MULTIMEDIA_SOURCE="/mnt/btrfs-pool/subvol4-multimedia"
TIER3_MULTIMEDIA_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol4-multimedia"
TIER3_MULTIMEDIA_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol4-multimedia"
TIER3_MULTIMEDIA_EXTERNAL_ENABLED=false  # Set to true after initial manual backup
TIER3_MULTIMEDIA_LOCAL_SCHEDULE="weekly"
TIER3_MULTIMEDIA_EXTERNAL_SCHEDULE="first-saturday"
TIER3_MULTIMEDIA_LOCAL_RETENTION=4
TIER3_MULTIMEDIA_EXTERNAL_RETENTION=3

# subvol5-music (Music library - 1.1TB, replaceable)
TIER3_MUSIC_ENABLED=true
TIER3_MUSIC_SOURCE="/mnt/btrfs-pool/subvol5-music"
TIER3_MUSIC_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol5-music"
TIER3_MUSIC_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol5-music"
TIER3_MUSIC_LOCAL_SCHEDULE="weekly"
TIER3_MUSIC_EXTERNAL_SCHEDULE="first-saturday"
TIER3_MUSIC_LOCAL_RETENTION=8            # 8 weekly = 2 months
TIER3_MUSIC_EXTERNAL_RETENTION=6

# subvol6-tmp (Temporary files/cache - 6.2GB, fully replaceable)
TIER3_TMP_ENABLED=true
TIER3_TMP_SOURCE="/mnt/btrfs-pool/subvol6-tmp"
TIER3_TMP_LOCAL_DIR="$LOCAL_POOL_SNAPSHOTS/subvol6-tmp"
TIER3_TMP_EXTERNAL_DIR="$EXTERNAL_BACKUP_ROOT/subvol6-tmp"
TIER3_TMP_LOCAL_SCHEDULE="weekly"
TIER3_TMP_EXTERNAL_SCHEDULE="never"      # Cache data — fully replaceable, no external backup
TIER3_TMP_LOCAL_RETENTION=4              # Only 4 weeks (cache data)
TIER3_TMP_EXTERNAL_RETENTION=3

# Graduated local retention (Time Machine-style) for daily-schedule subvolumes
# Tier 3 (weekly) uses simple count via _LOCAL_RETENTION instead
# Total coverage: 14 + (6*7) + (3*31) = ~149 days (~5 months)
GRADUATED_RETENTION_DAILY=14    # Keep all snapshots from last 14 days
GRADUATED_RETENTION_WEEKLY=6    # Keep 1 per week for next ~6 weeks (days 15-56)
GRADUATED_RETENTION_MONTHLY=3   # Keep 1 per month for next ~3 months (days 57-149)

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
    # Write timestamped plain text to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Write colorized output to terminal (stderr for ERROR, stdout otherwise)
    case $level in
        ERROR)   echo -e "${RED}[$level]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[$level]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[$level]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[$level]${NC} $message" ;;
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
        # Uses awk instead of bc to avoid dependency on bc package
        if [[ "$exclusive_bytes" =~ ([0-9.]+)TiB ]]; then
            required_bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1099511627776}")
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)GiB ]]; then
            required_bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1073741824}")
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)MiB ]]; then
            required_bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1048576}")
            size_source="btrfs-exclusive"
        elif [[ "$exclusive_bytes" =~ ([0-9.]+)KiB ]]; then
            required_bytes=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * 1024}")
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

should_run_on_schedule() {
    # Determine if an action should run based on schedule
    # Used for both local snapshot gating and external send gating
    local schedule=$1  # "daily" | "weekly" | "monthly" | "first-saturday" | "never"
    # "never" means never, even with --subvolume (e.g., tmp external backup)
    if [[ "$schedule" == "never" ]]; then
        return 1
    fi
    # When --subvolume is set, override time-based schedules (explicit manual request)
    if [[ -n "$SUBVOL_FILTER" ]]; then
        return 0
    fi
    case "$schedule" in
        daily)          return 0 ;;
        weekly)         [[ $(date +%u) -eq 6 ]] ;;
        monthly)        [[ $(date +%d) == "01" ]] ;;
        first-saturday) [[ $(date +%u) -eq 6 ]] && [[ $(date +%d) -le 7 ]] ;;
        *)              return 1 ;;
    esac
}

pin_parent() {
    local local_dir=$1
    local snapshot_name=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would pin parent: $snapshot_name (drive: ${EXTERNAL_DRIVE_LABEL:-unknown})"
        return 0
    fi

    # Drive-specific pin file (supports offsite rotation with separate incremental chains)
    if [[ -n "$EXTERNAL_DRIVE_LABEL" ]]; then
        local pin_file="$local_dir/.last-external-parent-${EXTERNAL_DRIVE_LABEL}"
        echo "$snapshot_name" > "$pin_file"
        log INFO "Pinned parent for ${EXTERNAL_DRIVE_LABEL} incremental chain: $snapshot_name"
    fi

    # Legacy pin file — remove after 2026-04-21 (1 month transition)
    # Once both drives have drive-specific pin files, this is unused
    echo "$snapshot_name" > "$local_dir/.last-external-parent"
}

get_pinned_parent() {
    local local_dir=$1

    # Try drive-specific pin file first
    if [[ -n "$EXTERNAL_DRIVE_LABEL" ]]; then
        local pin_file="$local_dir/.last-external-parent-${EXTERNAL_DRIVE_LABEL}"
        if [[ -f "$pin_file" ]]; then
            cat "$pin_file"
            return
        fi
    fi

    # Fall back to legacy pin file
    local pin_file="$local_dir/.last-external-parent"
    if [[ -f "$pin_file" ]]; then
        cat "$pin_file"
    fi
}

get_all_pinned_parents() {
    # Return all pinned parent names across all drives (for graduated cleanup protection)
    local local_dir=$1
    local pinned=()

    for pin_file in "$local_dir"/.last-external-parent*; do
        if [[ -f "$pin_file" ]]; then
            local name
            name=$(cat "$pin_file")
            [[ -n "$name" ]] && pinned+=("$name")
        fi
    done

    # Deduplicate and print
    printf '%s\n' "${pinned[@]}" | sort -u
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
    # Simple count-based retention (used for external drives and Tier 3 local)
    local snapshot_dir=$1
    local retention_count=$2
    local pattern=$3  # e.g., "*-daily" or "*-weekly"

    if [[ ! -d "$snapshot_dir" ]]; then
        log WARNING "Snapshot directory does not exist: $snapshot_dir"
        return 0
    fi

    # Collect ALL pinned parents across all drives
    local -a pinned_names=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && pinned_names+=("$name")
    done < <(get_all_pinned_parents "$snapshot_dir")

    # Get list of snapshots matching pattern, sorted by modification time (oldest first)
    local snapshots=($(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort | awk '{print $2}'))

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

        # Never delete any pinned parent — they're incremental chain anchors
        local is_pinned=false
        for pinned_name in "${pinned_names[@]}"; do
            if [[ "$snap_basename" == "$pinned_name" ]]; then
                is_pinned=true
                break
            fi
        done

        if [[ "$is_pinned" == "true" ]]; then
            log WARNING "Preserving pinned parent snapshot (incremental chain anchor): $snapshot"
            continue
        fi

        log INFO "Deleting old snapshot: $snapshot"
        run_cmd "sudo btrfs subvolume delete '$snapshot'"
        ((deleted++))
    done

    if [[ $deleted -lt $to_delete ]]; then
        log INFO "Retained $(( to_delete - deleted )) snapshot(s) due to pinned parent protection"
    fi

    return 0
}

cleanup_graduated() {
    # Time Machine-style graduated retention for daily-schedule subvolumes
    # Keeps: all from last N days, 1/week for M weeks, 1/month for P months
    # Protects all pinned parents across all drives
    local snapshot_dir=$1
    local pattern=$2  # e.g., "*-htpc-home"

    if [[ ! -d "$snapshot_dir" ]]; then
        log WARNING "Snapshot directory does not exist: $snapshot_dir"
        return 0
    fi

    # Collect ALL pinned parents across all drives
    local -a pinned_names=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && pinned_names+=("$name")
    done < <(get_all_pinned_parents "$snapshot_dir")

    # Get list of snapshots matching pattern, sorted newest first
    local -a snapshots=()
    while IFS= read -r snap; do
        [[ -n "$snap" ]] && snapshots+=("$snap")
    done < <(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%T@ %p\n' | sort -rn | awk '{print $2}')

    local count=${#snapshots[@]}
    if [[ $count -eq 0 ]]; then
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)

    # Track which weeks and months already have a keeper
    local -A kept_weeks=()
    local -A kept_months=()
    local -a to_delete=()
    local kept=0

    for snapshot in "${snapshots[@]}"; do
        local snap_basename
        snap_basename=$(basename "$snapshot")

        # Always protect pinned parents
        local is_pinned=false
        for pinned_name in "${pinned_names[@]}"; do
            if [[ "$snap_basename" == "$pinned_name" ]]; then
                is_pinned=true
                break
            fi
        done
        if [[ "$is_pinned" == "true" ]]; then
            log INFO "Graduated cleanup: preserving pinned parent: $snap_basename"
            ((kept++))
            continue
        fi

        # Extract date from snapshot name (format: YYYYMMDD-*)
        local snap_date="${snap_basename:0:8}"
        if ! [[ "$snap_date" =~ ^[0-9]{8}$ ]]; then
            log WARNING "Cannot parse date from snapshot name: $snap_basename — keeping"
            ((kept++))
            continue
        fi

        local snap_epoch
        snap_epoch=$(date -d "${snap_date:0:4}-${snap_date:4:2}-${snap_date:6:2}" +%s 2>/dev/null || echo "0")
        if [[ "$snap_epoch" == "0" ]]; then
            log WARNING "Invalid date in snapshot name: $snap_basename — keeping"
            ((kept++))
            continue
        fi

        local age_days=$(( (now_epoch - snap_epoch) / 86400 ))

        # Rule 1: Keep all from last GRADUATED_RETENTION_DAILY days
        if [[ $age_days -le $GRADUATED_RETENTION_DAILY ]]; then
            ((kept++))
            continue
        fi

        # Rule 2: Keep 1 per ISO week for next GRADUATED_RETENTION_WEEKLY weeks
        local weekly_limit=$(( GRADUATED_RETENTION_DAILY + (GRADUATED_RETENTION_WEEKLY * 7) ))
        if [[ $age_days -le $weekly_limit ]]; then
            local iso_week
            iso_week=$(date -d "${snap_date:0:4}-${snap_date:4:2}-${snap_date:6:2}" +%G-W%V 2>/dev/null)
            if [[ -z "${kept_weeks[$iso_week]:-}" ]]; then
                kept_weeks["$iso_week"]=1
                ((kept++))
                continue
            fi
            # Already have a keeper for this week — delete
            to_delete+=("$snapshot")
            continue
        fi

        # Rule 3: Keep 1 per month for next GRADUATED_RETENTION_MONTHLY months
        local monthly_limit=$(( weekly_limit + (GRADUATED_RETENTION_MONTHLY * 31) ))
        if [[ $age_days -le $monthly_limit ]]; then
            local month="${snap_date:0:6}"  # YYYYMM
            if [[ -z "${kept_months[$month]:-}" ]]; then
                kept_months["$month"]=1
                ((kept++))
                continue
            fi
            # Already have a keeper for this month — delete
            to_delete+=("$snapshot")
            continue
        fi

        # Rule 4: Older than all windows — delete
        to_delete+=("$snapshot")
    done

    if [[ ${#to_delete[@]} -eq 0 ]]; then
        log INFO "Graduated cleanup: no snapshots to delete in $snapshot_dir (keeping $kept)"
        return 0
    fi

    log INFO "Graduated cleanup: deleting ${#to_delete[@]} snapshots from $snapshot_dir (keeping $kept)"

    if [[ "$DRY_RUN" == "true" ]]; then
        for snapshot in "${to_delete[@]}"; do
            log INFO "[DRY-RUN] Would delete: $(basename "$snapshot")"
        done
        return 0
    fi

    for snapshot in "${to_delete[@]}"; do
        log INFO "Deleting old snapshot: $(basename "$snapshot")"
        sudo btrfs subvolume delete "$snapshot" 2>/dev/null || \
            log ERROR "Failed to delete snapshot: $snapshot"
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
    local latest=$(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort -r | head -1 | awk '{print $2}')

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
    local second=$(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%T+ %p\n' | sort -r | sed -n '2p' | awk '{print $2}')

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

    # Prefer the pinned parent (the known-good chain anchor for this drive)
    local pinned
    pinned=$(get_pinned_parent "$local_dir")
    if [[ -n "$pinned" ]] && [[ -d "$local_dir/$pinned" ]] && [[ -d "$external_dir/$pinned" ]]; then
        echo "$local_dir/$pinned"
        return 0
    fi

    # Fall back to scanning: find newest local snapshot that also exists on external
    local local_snapshots=$(find "$local_dir" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%f\n' | sort -r)

    for snap in $local_snapshots; do
        if [[ -d "$external_dir/$snap" ]]; then
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
    local success=$3  # 1=success, 0=failure, 2=schedule-skipped (not scheduled today)
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

    # Send to external (per schedule)
    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER1_HOME_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_HOME_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_HOME_LOCAL_DIR" "$TIER1_HOME_EXTERNAL_DIR" "*-htpc-home"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER1_HOME_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER1_HOME_EXTERNAL_DIR" "$TIER1_HOME_EXTERNAL_RETENTION" "*-htpc-home"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    # Cleanup local snapshots (graduated retention for daily subvolumes)
    cleanup_graduated "$TIER1_HOME_LOCAL_DIR" "*-htpc-home"

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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER1_OPPTAK_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_OPPTAK_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_OPPTAK_LOCAL_DIR" "$TIER1_OPPTAK_EXTERNAL_DIR" "*-opptak"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER1_OPPTAK_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER1_OPPTAK_EXTERNAL_DIR" "$TIER1_OPPTAK_EXTERNAL_RETENTION" "*-opptak"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_graduated "$TIER1_OPPTAK_LOCAL_DIR" "*-opptak"

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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER1_CONTAINERS_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER1_CONTAINERS_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER1_CONTAINERS_LOCAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_DIR" "*-containers"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER1_CONTAINERS_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER1_CONTAINERS_EXTERNAL_DIR" "$TIER1_CONTAINERS_EXTERNAL_RETENTION" "*-containers"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_graduated "$TIER1_CONTAINERS_LOCAL_DIR" "*-containers"

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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER2_DOCS_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_DOCS_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_DOCS_LOCAL_DIR" "$TIER2_DOCS_EXTERNAL_DIR" "*-docs"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER2_DOCS_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER2_DOCS_EXTERNAL_DIR" "$TIER2_DOCS_EXTERNAL_RETENTION" "*-docs"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_graduated "$TIER2_DOCS_LOCAL_DIR" "*-docs"

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

    # Root is monthly only (local schedule gate)
    if ! should_run_on_schedule "$TIER2_ROOT_LOCAL_SCHEDULE"; then
        log INFO "$subvol_name backup runs on 1st of month only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 2 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER2_ROOT_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER2_ROOT_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_EXTERNAL_DIR" "*-htpc-root"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER2_ROOT_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER2_ROOT_EXTERNAL_DIR" "$TIER2_ROOT_EXTERNAL_RETENTION" "*-htpc-root"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_old_snapshots "$TIER2_ROOT_LOCAL_DIR" "$TIER2_ROOT_LOCAL_RETENTION" "*-htpc-root"

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

    # Tier 3: weekly local snapshots only
    if ! should_run_on_schedule "$TIER3_PICS_LOCAL_SCHEDULE"; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 2 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER3_PICS_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_PICS_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_EXTERNAL_DIR" "*-pics*"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER3_PICS_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER3_PICS_EXTERNAL_DIR" "$TIER3_PICS_EXTERNAL_RETENTION" "*-pics*"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_old_snapshots "$TIER3_PICS_LOCAL_DIR" "$TIER3_PICS_LOCAL_RETENTION" "*-pics*"

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

    # Tier 3: weekly local snapshots only
    if ! should_run_on_schedule "$TIER3_MULTIMEDIA_LOCAL_SCHEDULE"; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 2 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
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

    if [[ "$TIER3_MULTIMEDIA_EXTERNAL_ENABLED" == "true" ]] && [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER3_MULTIMEDIA_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "*-multimedia*"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER3_MULTIMEDIA_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER3_MULTIMEDIA_EXTERNAL_DIR" "$TIER3_MULTIMEDIA_EXTERNAL_RETENTION" "*-multimedia*"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    elif [[ "$TIER3_MULTIMEDIA_EXTERNAL_ENABLED" != "true" ]]; then
        log WARNING "$subvol_name external backup is DISABLED (set TIER3_MULTIMEDIA_EXTERNAL_ENABLED=true to enable)"
    fi

    cleanup_old_snapshots "$TIER3_MULTIMEDIA_LOCAL_DIR" "$TIER3_MULTIMEDIA_LOCAL_RETENTION" "*-multimedia*"

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

    # Tier 3: weekly local snapshots only
    if ! should_run_on_schedule "$TIER3_MUSIC_LOCAL_SCHEDULE"; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 2 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER3_MUSIC_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_MUSIC_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_EXTERNAL_DIR" "*-music*"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER3_MUSIC_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER3_MUSIC_EXTERNAL_DIR" "$TIER3_MUSIC_EXTERNAL_RETENTION" "*-music*"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_old_snapshots "$TIER3_MUSIC_LOCAL_DIR" "$TIER3_MUSIC_LOCAL_RETENTION" "*-music*"

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

    # Tier 3: weekly local snapshots only
    if ! should_run_on_schedule "$TIER3_TMP_LOCAL_SCHEDULE"; then
        log INFO "$subvol_name local backup runs on Saturdays only, skipping"
        record_backup_metrics "$subvol_name" "$start_time" 2 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
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

    if [[ "$LOCAL_ONLY" != "true" ]] && should_run_on_schedule "$TIER3_TMP_EXTERNAL_SCHEDULE"; then
        if check_external_mounted; then
            local parent=$(find_common_parent "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*")
            send_snapshot_incremental "$parent" "$local_snapshot" "$TIER3_TMP_EXTERNAL_DIR" || {
                record_failure "$subvol_name" "External send failed"
                record_backup_metrics "$subvol_name" "$start_time" 0 "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_EXTERNAL_DIR" "*-tmp*"
                return 1
            }

            if [[ -n "$parent" ]]; then
                SEND_TYPE["$subvol_name"]="incremental"
            else
                SEND_TYPE["$subvol_name"]="full"
            fi
            pin_parent "$TIER3_TMP_LOCAL_DIR" "$snapshot_name"
            cleanup_old_snapshots "$TIER3_TMP_EXTERNAL_DIR" "$TIER3_TMP_EXTERNAL_RETENTION" "*-tmp*"
        else
            log INFO "No external drive mounted — skipping external send for $subvol_name"
        fi
    fi

    cleanup_old_snapshots "$TIER3_TMP_LOCAL_DIR" "$TIER3_TMP_LOCAL_RETENTION" "*-tmp*"

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
    # Valid short names for --subvolume filter (must match the filter checks in main)
    local -A VALID_SUBVOLS=(
        [home]=1 [opptak]=1 [containers]=1 [docs]=1 [root]=1
        [pics]=1 [multimedia]=1 [music]=1 [tmp]=1
    )
    # Map full names to short names for convenience
    local -A SUBVOL_ALIASES=(
        [htpc-home]=home [subvol3-opptak]=opptak [subvol7-containers]=containers
        [subvol1-docs]=docs [htpc-root]=root [subvol2-pics]=pics
        [subvol4-multimedia]=multimedia [subvol5-music]=music [subvol6-tmp]=tmp
    )

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
                local raw_name="$2"
                # Resolve alias (full name -> short name)
                if [[ -n "${SUBVOL_ALIASES[$raw_name]:-}" ]]; then
                    SUBVOL_FILTER="${SUBVOL_ALIASES[$raw_name]}"
                elif [[ -n "${VALID_SUBVOLS[$raw_name]:-}" ]]; then
                    SUBVOL_FILTER="$raw_name"
                else
                    echo "ERROR: Unknown subvolume '$raw_name'" >&2
                    echo "Valid names: ${!VALID_SUBVOLS[*]}" >&2
                    echo "Also accepts: ${!SUBVOL_ALIASES[*]}" >&2
                    exit 1
                fi
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
        echo "# HELP backup_success Backup result: 1=success, 0=failure, 2=schedule-skipped"
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
        echo "# HELP backup_send_type Last send type: 2=no send this run, 1=incremental, 0=full"
        echo "# TYPE backup_send_type gauge"

        # Emit for all known subvolumes to avoid disappearing series in Prometheus
        # Uses 2 for no-send (not -1) so alert rules on ==0 (full send) don't false-positive
        for subvol in "${!BACKUP_SUCCESS[@]}"; do
            if [[ -n "${SEND_TYPE[$subvol]:-}" ]]; then
                if [[ "${SEND_TYPE[$subvol]}" == "incremental" ]]; then
                    echo "backup_send_type{subvolume=\"$subvol\"} 1"
                else
                    echo "backup_send_type{subvolume=\"$subvol\"} 0"
                fi
            else
                echo "backup_send_type{subvolume=\"$subvol\"} 2"
            fi
        done

        echo ""
        echo "# HELP backup_external_drive_mounted Whether external drive was mounted during run (1=yes, 0=no)"
        echo "# TYPE backup_external_drive_mounted gauge"
        [[ "$EXTERNAL_DRIVE_MOUNTED" == "true" ]] && echo "backup_external_drive_mounted 1" || echo "backup_external_drive_mounted 0"

        echo ""
        echo "# HELP backup_external_free_bytes Free space on external drive in bytes (0 when unmounted)"
        echo "# TYPE backup_external_free_bytes gauge"
        if [[ "$EXTERNAL_DRIVE_MOUNTED" == "true" ]] && [[ -d "$EXTERNAL_BACKUP_ROOT" ]]; then
            local free_bytes
            free_bytes=$(df --output=avail -B1 "$(dirname "$EXTERNAL_BACKUP_ROOT")" 2>/dev/null | tail -1 | tr -d ' ')
            echo "backup_external_free_bytes ${free_bytes:-0}"
        else
            echo "backup_external_free_bytes 0"
        fi

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
