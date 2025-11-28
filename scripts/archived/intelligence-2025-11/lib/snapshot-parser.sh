#!/usr/bin/env bash
#
# Snapshot Parser Library
# Provides functions to extract and analyze data from homelab snapshot JSON files
#
# Usage: source this file in intelligence scripts
#   source "$(dirname "$0")/lib/snapshot-parser.sh"
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SNAPSHOT_DIR="${SNAPSHOT_DIR:-docs/99-reports}"
SNAPSHOT_PATTERN="${SNAPSHOT_PATTERN:-snapshot-*.json}"

# ============================================================================
# Snapshot Discovery
# ============================================================================

# Get all snapshot files, sorted by timestamp (oldest first)
# Only returns valid JSON files
get_all_snapshots() {
    local snapshots
    snapshots=$(find "${SNAPSHOT_DIR}" -name "${SNAPSHOT_PATTERN}" -type f | sort)

    # Filter out invalid JSON
    while IFS= read -r snapshot; do
        if jq -e '.' "$snapshot" &>/dev/null; then
            echo "$snapshot"
        fi
    done <<< "$snapshots"
}

# Get most recent N snapshots
get_recent_snapshots() {
    local count="${1:-5}"
    get_all_snapshots | tail -n "${count}"
}

# Get snapshot timestamp from filename
# Input: snapshot-20251109-195148.json
# Output: 2025-11-09 19:51:48
get_snapshot_timestamp() {
    local snapshot_file="$1"
    local basename=$(basename "$snapshot_file" .json)
    # Extract: snapshot-20251109-195148 -> 20251109-195148
    local datetime="${basename#snapshot-}"
    # Parse: 20251109-195148 -> 2025-11-09 19:51:48
    echo "${datetime:0:4}-${datetime:4:2}-${datetime:6:2} ${datetime:9:2}:${datetime:11:2}:${datetime:13:2}"
}

# Get snapshot age in seconds relative to most recent snapshot
get_snapshot_age() {
    local snapshot_file="$1"
    local latest_snapshot="$2"

    local snapshot_ts=$(get_snapshot_timestamp "$snapshot_file")
    local latest_ts=$(get_snapshot_timestamp "$latest_snapshot")

    local snapshot_epoch=$(date -d "$snapshot_ts" +%s)
    local latest_epoch=$(date -d "$latest_ts" +%s)

    echo $((latest_epoch - snapshot_epoch))
}

# ============================================================================
# Data Extraction
# ============================================================================

# Extract system memory usage (MB)
extract_system_memory() {
    local snapshot_file="$1"
    jq -r '.resources.memory.used_mb // 0' "$snapshot_file"
}

# Extract system memory total (MB)
extract_system_memory_total() {
    local snapshot_file="$1"
    jq -r '.resources.memory.total_mb // 0' "$snapshot_file"
}

# Extract system disk usage percentage
extract_system_disk_percent() {
    local snapshot_file="$1"
    jq -r '.storage.system_disk.percent // 0' "$snapshot_file"
}

# Extract system disk usage (GB)
extract_system_disk_used() {
    local snapshot_file="$1"
    jq -r '.storage.system_disk.used_gb // 0' "$snapshot_file"
}

# Extract BTRFS pool usage percentage
extract_btrfs_percent() {
    local snapshot_file="$1"
    jq -r '.storage.btrfs_pool.percent // 0' "$snapshot_file"
}

# Extract BTRFS pool usage (GB)
extract_btrfs_used() {
    local snapshot_file="$1"
    jq -r '.storage.btrfs_pool.used_gb // 0' "$snapshot_file"
}

# Extract service count
extract_service_count() {
    local snapshot_file="$1"
    jq -r '.services | length' "$snapshot_file"
}

# Extract healthy service count
extract_healthy_count() {
    local snapshot_file="$1"
    jq -r '.health_check_analysis.healthy // 0' "$snapshot_file"
}

# Extract unhealthy service count
extract_unhealthy_count() {
    local snapshot_file="$1"
    jq -r '.health_check_analysis.unhealthy // 0' "$snapshot_file"
}

# Extract service memory usage (MB) for a specific service
extract_service_memory() {
    local snapshot_file="$1"
    local service_name="$2"
    jq -r ".services.\"${service_name}\".memory_mb // 0" "$snapshot_file"
}

# Extract service health status
extract_service_health() {
    local snapshot_file="$1"
    local service_name="$2"
    jq -r ".services.\"${service_name}\".health // \"unknown\"" "$snapshot_file"
}

# Get list of all services from a snapshot
get_service_names() {
    local snapshot_file="$1"
    jq -r '.services | keys[]' "$snapshot_file" | sort
}

# ============================================================================
# Time Series Analysis
# ============================================================================

# Build time series for a metric across snapshots
# Returns: timestamp value (one per line)
build_timeseries() {
    local extract_function="$1"
    shift
    local snapshots=("$@")

    for snapshot in "${snapshots[@]}"; do
        local timestamp=$(get_snapshot_timestamp "$snapshot")
        local value=$($extract_function "$snapshot")
        echo "$timestamp $value"
    done
}

# Calculate simple linear regression slope
# Input: series of "timestamp value" lines
# Output: slope (rate of change per second)
calculate_slope() {
    awk '
    BEGIN {
        n = 0
        sum_x = 0
        sum_y = 0
        sum_xy = 0
        sum_xx = 0
    }
    {
        # Convert timestamp to epoch
        cmd = "date -d \"" $1 " " $2 "\" +%s"
        cmd | getline x
        close(cmd)

        y = $3

        n++
        sum_x += x
        sum_y += y
        sum_xy += x * y
        sum_xx += x * x
    }
    END {
        if (n < 2) {
            print 0
            exit
        }

        # Calculate slope: (n*sum_xy - sum_x*sum_y) / (n*sum_xx - sum_x*sum_x)
        numerator = n * sum_xy - sum_x * sum_y
        denominator = n * sum_xx - sum_x * sum_x

        if (denominator == 0) {
            print 0
        } else {
            slope = numerator / denominator
            print slope
        }
    }'
}

# Calculate mean of a time series
calculate_mean() {
    awk '{sum += $3; count++} END {if (count > 0) print sum/count; else print 0}'
}

# Calculate standard deviation
calculate_stddev() {
    awk '
    {
        values[NR] = $3
        sum += $3
        count++
    }
    END {
        if (count == 0) {
            print 0
            exit
        }

        mean = sum / count
        sum_sq_diff = 0

        for (i = 1; i <= count; i++) {
            diff = values[i] - mean
            sum_sq_diff += diff * diff
        }

        variance = sum_sq_diff / count
        stddev = sqrt(variance)
        print stddev
    }'
}

# Get first and last values from time series
get_first_value() {
    head -1 | awk '{print $3}'
}

get_last_value() {
    tail -1 | awk '{print $3}'
}

# Calculate percentage change
calculate_percent_change() {
    local first="$1"
    local last="$2"

    if (( $(echo "$first == 0" | bc -l) )); then
        echo "N/A"
    else
        echo "scale=2; (($last - $first) / $first) * 100" | bc -l
    fi
}

# ============================================================================
# Prediction Functions
# ============================================================================

# Predict when a value will reach a threshold
# Args: current_value slope threshold
# Returns: seconds until threshold (or -1 if never/already passed)
predict_threshold_time() {
    local current="$1"
    local slope="$2"
    local threshold="$3"

    # If slope is zero or negative, will never reach threshold
    if (( $(echo "$slope <= 0" | bc -l) )); then
        echo "-1"
        return
    fi

    # If already at or above threshold
    if (( $(echo "$current >= $threshold" | bc -l) )); then
        echo "0"
        return
    fi

    # Calculate time: (threshold - current) / slope
    echo "scale=0; ($threshold - $current) / $slope" | bc -l | cut -d. -f1
}

# Convert seconds to human readable format
seconds_to_human() {
    local seconds="$1"

    if [[ "$seconds" == "-1" ]]; then
        echo "never"
        return
    fi

    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))

    if ((days > 0)); then
        echo "${days} days"
    elif ((hours > 0)); then
        echo "${hours} hours"
    else
        echo "< 1 hour"
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if jq is available
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        echo "Error: bc is required but not installed" >&2
        exit 1
    fi
}

# Print debug info if DEBUG=1
debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Initialize - check dependencies
check_dependencies

# Export functions for use in other scripts
export -f get_all_snapshots
export -f get_recent_snapshots
export -f get_snapshot_timestamp
export -f get_snapshot_age
export -f extract_system_memory
export -f extract_system_memory_total
export -f extract_system_disk_percent
export -f extract_system_disk_used
export -f extract_btrfs_percent
export -f extract_btrfs_used
export -f extract_service_count
export -f extract_healthy_count
export -f extract_unhealthy_count
export -f extract_service_memory
export -f extract_service_health
export -f get_service_names
export -f build_timeseries
export -f calculate_slope
export -f calculate_mean
export -f calculate_stddev
export -f get_first_value
export -f get_last_value
export -f calculate_percent_change
export -f predict_threshold_time
export -f seconds_to_human
export -f debug
