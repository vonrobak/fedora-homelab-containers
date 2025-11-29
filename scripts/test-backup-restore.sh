#!/bin/bash
################################################################################
# BTRFS Backup Restore Testing Script
# Purpose: Validate backup integrity through automated restore tests
# Part of: Project A - Disaster Recovery Testing Framework
################################################################################

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# Test configuration
SAMPLE_SIZE=50                    # Number of random files to test per subvolume
RESTORE_TEST_DIR="/tmp/restore-tests"
TEST_LOG_DIR="$HOME/containers/data/backup-logs"
METRICS_DIR="$HOME/containers/data/backup-metrics"
METRICS_FILE="$METRICS_DIR/restore-test-metrics.prom"

# Backup locations (must match btrfs-snapshot-backup.sh)
EXTERNAL_BACKUP_ROOT="/run/media/patriark/WD-18TB/.snapshots"
LOCAL_HOME_SNAPSHOTS="$HOME/.snapshots"
LOCAL_POOL_SNAPSHOTS="/mnt/btrfs-pool/.snapshots"

# Subvolume definitions
declare -A SUBVOLUMES
SUBVOLUMES[htpc-home]="$LOCAL_HOME_SNAPSHOTS/htpc-home"
SUBVOLUMES[subvol3-opptak]="$LOCAL_POOL_SNAPSHOTS/subvol3-opptak"
SUBVOLUMES[subvol7-containers]="$LOCAL_POOL_SNAPSHOTS/subvol7-containers"
SUBVOLUMES[subvol1-docs]="$LOCAL_POOL_SNAPSHOTS/subvol1-docs"
SUBVOLUMES[htpc-root]="$LOCAL_HOME_SNAPSHOTS/htpc-root"
SUBVOLUMES[subvol2-pics]="$LOCAL_POOL_SNAPSHOTS/subvol2-pics"

# Test result tracking
declare -A TEST_RESULTS
declare -A TEST_DURATIONS
declare -A TEST_ERRORS
declare -A TEST_FILES_VALIDATED
declare -A TEST_SNAPSHOT_SOURCE

# Configuration flags
VERBOSE=false
DRY_RUN=false
SPECIFIC_SUBVOL=""
JSON_OUTPUT=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Logging Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        WARNING)
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[OK]${NC} $message" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" >&2
            ;;
        DEBUG)
            if $VERBOSE; then
                echo -e "${CYAN}[DEBUG]${NC} $message" >&2
            fi
            ;;
    esac
}

################################################################################
# Snapshot Discovery Functions
################################################################################

get_latest_snapshot() {
    local subvol=$1
    local snapshot_dir="${SUBVOLUMES[$subvol]}"
    local found_snapshot=""
    local source="none"

    log DEBUG "Looking for snapshots for $subvol"

    # Strategy 1: Check local snapshots first (most recent, most reliable)
    if [[ -d "$snapshot_dir" ]]; then
        found_snapshot=$(ls -1td "$snapshot_dir"/* 2>/dev/null | head -1 || echo "")
        if [[ -n "$found_snapshot" && -d "$found_snapshot" ]]; then
            source="local"
            log DEBUG "Found local snapshot: $found_snapshot"
        fi
    fi

    # Strategy 2: Try external drive (but handle old/scattered snapshots)
    # Note: External snapshots may be old (April 2025) and scattered
    if [[ -z "$found_snapshot" ]]; then
        # Try organized subfolder first
        local external_dir="$EXTERNAL_BACKUP_ROOT/$subvol"
        if [[ -d "$external_dir" ]]; then
            found_snapshot=$(ls -1td "$external_dir"/* 2>/dev/null | head -1 || echo "")
            if [[ -n "$found_snapshot" && -d "$found_snapshot" ]]; then
                source="external"
                log DEBUG "Found external snapshot (organized): $found_snapshot"
            fi
        fi

        # Try scattered snapshots in root .snapshots directory (legacy format)
        if [[ -z "$found_snapshot" ]]; then
            # Look for snapshots matching pattern: YYYYMMDD-subvol or YYYYMMDD-htpc-*
            local search_pattern=""
            case "$subvol" in
                htpc-home)
                    search_pattern="20*-htpc-home"
                    ;;
                htpc-root)
                    search_pattern="20*-htpc-root"
                    ;;
                subvol*)
                    # Extract number from subvolX-name
                    local subvol_num=$(echo "$subvol" | grep -oP 'subvol\K\d+')
                    search_pattern="20*-subvol${subvol_num}"
                    ;;
            esac

            if [[ -n "$search_pattern" ]]; then
                found_snapshot=$(ls -1td "$EXTERNAL_BACKUP_ROOT"/$search_pattern 2>/dev/null | head -1 || echo "")
                if [[ -n "$found_snapshot" && -d "$found_snapshot" ]]; then
                    source="external-scattered"
                    log WARNING "Found scattered external snapshot: $found_snapshot (may be old)"
                fi
            fi
        fi
    fi

    # Store source for reporting
    TEST_SNAPSHOT_SOURCE[$subvol]=$source

    echo "$found_snapshot"
}

################################################################################
# File Selection Functions
################################################################################

select_random_files() {
    local snapshot_path=$1
    local sample_size=$2
    local output_file=$3  # Output file path

    log DEBUG "Selecting random files from: $snapshot_path"

    # Find regular files, excluding special paths and hidden files
    # Use shuf to randomize, limit to sample size
    find "$snapshot_path" -type f \
        ! -path "*/proc/*" \
        ! -path "*/sys/*" \
        ! -path "*/dev/*" \
        ! -name ".*" \
        -print0 2>/dev/null | \
        shuf -z -n "$sample_size" > "$output_file"

    local count=$(tr -cd '\0' < "$output_file" | wc -c)
    log DEBUG "Selected $count files for testing"

    echo "$count"  # Output count to stdout
}

################################################################################
# Validation Functions
################################################################################

validate_file() {
    local original=$1
    local restored=$2
    local errors=0

    # Checksum validation (byte-for-byte comparison)
    if ! cmp -s "$original" "$restored" 2>/dev/null; then
        log ERROR "Checksum mismatch: $(basename "$original")"
        ((errors++))
        return $errors
    fi

    # Permission validation
    local orig_perms=$(stat -c '%a' "$original" 2>/dev/null || echo "")
    local rest_perms=$(stat -c '%a' "$restored" 2>/dev/null || echo "")
    if [[ -n "$orig_perms" && -n "$rest_perms" && "$orig_perms" != "$rest_perms" ]]; then
        log WARNING "Permission mismatch: $(basename "$original") ($orig_perms vs $rest_perms)"
        # Don't fail on permission mismatches in test restores
    fi

    # Ownership validation
    local orig_owner=$(stat -c '%U:%G' "$original" 2>/dev/null || echo "")
    local rest_owner=$(stat -c '%U:%G' "$restored" 2>/dev/null || echo "")
    if [[ -n "$orig_owner" && -n "$rest_owner" && "$orig_owner" != "$rest_owner" ]]; then
        log DEBUG "Ownership difference: $(basename "$original") ($orig_owner vs $rest_owner)"
        # Don't fail on ownership - expected in test environment
    fi

    # SELinux context validation (if enforcing)
    if command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        local orig_context=$(ls -Z "$original" 2>/dev/null | awk '{print $1}')
        local rest_context=$(ls -Z "$restored" 2>/dev/null | awk '{print $1}')
        if [[ -n "$orig_context" && -n "$rest_context" && "$orig_context" != "$rest_context" ]]; then
            log DEBUG "SELinux context difference: $(basename "$original")"
            # Don't fail on SELinux context - expected in test restore
        fi
    fi

    return $errors
}

################################################################################
# Core Testing Function
################################################################################

test_subvolume_restore() {
    local subvol=$1
    local start_time=$(date +%s)

    log INFO "========================================="
    log INFO "Testing restore for: $subvol"
    log INFO "========================================="

    # Get latest snapshot
    local snapshot=$(get_latest_snapshot "$subvol")
    if [[ -z "$snapshot" ]]; then
        log ERROR "No snapshot found for $subvol"
        TEST_RESULTS[$subvol]="FAIL"
        TEST_ERRORS[$subvol]=999
        TEST_FILES_VALIDATED[$subvol]=0
        TEST_DURATIONS[$subvol]=0
        return 1
    fi

    log INFO "Using snapshot: $(basename "$snapshot")"
    log INFO "Source: ${TEST_SNAPSHOT_SOURCE[$subvol]:-unknown}"

    # Check snapshot age (warn if >30 days old)
    local snapshot_date=$(basename "$snapshot" | grep -oP '^\d{8}' || echo "")
    if [[ -n "$snapshot_date" ]]; then
        local snapshot_epoch=$(date -d "$snapshot_date" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local age_days=$(( (current_epoch - snapshot_epoch) / 86400 ))
        if [[ $age_days -gt 30 ]]; then
            log WARNING "Snapshot is $age_days days old (may not reflect current state)"
        fi
    fi

    # Create restore directory
    local restore_dir="$RESTORE_TEST_DIR/$subvol-$(date +%Y%m%d%H%M%S)"
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Would create restore directory: $restore_dir"
    else
        mkdir -p "$restore_dir"
        log DEBUG "Created restore directory: $restore_dir"
    fi

    # Select random files
    log INFO "Selecting $SAMPLE_SIZE random files for testing..."
    local file_list=$(mktemp)
    local file_count=$(select_random_files "$snapshot" "$SAMPLE_SIZE" "$file_list")

    if [[ $file_count -eq 0 ]]; then
        log WARNING "No files found in snapshot for $subvol"
        TEST_RESULTS[$subvol]="SKIP"
        TEST_ERRORS[$subvol]=0
        TEST_FILES_VALIDATED[$subvol]=0
        TEST_DURATIONS[$subvol]=0
        rm -f "$file_list"
        return 0
    fi

    log INFO "Selected $file_count files for validation"

    if $DRY_RUN; then
        log INFO "[DRY-RUN] Would restore and validate $file_count files"
        TEST_RESULTS[$subvol]="DRY-RUN"
        TEST_ERRORS[$subvol]=0
        TEST_FILES_VALIDATED[$subvol]=$file_count
        TEST_DURATIONS[$subvol]=0
        rm -f "$file_list"
        return 0
    fi

    # Restore and validate each file
    local failed=0
    local validated=0
    local processed=0

    # Read files into array using mapfile
    local files_array=()
    log DEBUG "Loading files from temp list..."
    mapfile -d '' -t files_array < "$file_list"
    log DEBUG "Loaded ${#files_array[@]} files into array"

    # Cleanup temp file
    rm -f "$file_list"

    # Skip if array is empty
    if [[ ${#files_array[@]} -eq 0 ]]; then
        log WARNING "No files loaded into array"
        TEST_RESULTS[$subvol]="SKIP"
        TEST_ERRORS[$subvol]=0
        TEST_FILES_VALIDATED[$subvol]=0
        TEST_DURATIONS[$subvol]=0
        return 0
    fi

    # Process each file
    log DEBUG "Starting to process ${#files_array[@]} files..."
    log DEBUG "Array contents: ${files_array[*]}"
    for file in "${files_array[@]}"; do
        log DEBUG "Loop iteration started"
        processed=$((processed + 1))
        log DEBUG "Processing file $processed"

        # Show progress every 10 files
        if ((processed % 10 == 0)); then
            log DEBUG "Progress: $processed/$file_count files processed"
        fi

        # Get relative path
        log DEBUG "Getting relative path..."
        local rel_path="${file#$snapshot/}"
        local restore_path="$restore_dir/$rel_path"
        log DEBUG "Restore path: $restore_path"

        # Create parent directory
        log DEBUG "Creating parent directory..."
        mkdir -p "$(dirname "$restore_path")"

        # Restore file (preserve all attributes)
        log DEBUG "Copying file..."
        if cp -a "$file" "$restore_path" 2>/dev/null; then
            log DEBUG "File copied, validating..."
            # Validate
            if validate_file "$file" "$restore_path"; then
                validated=$((validated + 1))
                log DEBUG "Validation passed"
            else
                failed=$((failed + 1))
                log DEBUG "Validation failed"
            fi
        else
            log ERROR "Failed to copy file"
            failed=$((failed + 1))
        fi
    done

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    TEST_DURATIONS[$subvol]=$duration
    TEST_FILES_VALIDATED[$subvol]=$validated

    # Determine result
    if [[ $failed -eq 0 && $validated -gt 0 ]]; then
        TEST_RESULTS[$subvol]="PASS"
        TEST_ERRORS[$subvol]=0
        log SUCCESS "✓ $subvol: $validated files validated, 0 failures (${duration}s)"
    else
        TEST_RESULTS[$subvol]="FAIL"
        TEST_ERRORS[$subvol]=$failed
        log ERROR "✗ $subvol: $validated validated, $failed FAILED (${duration}s)"
    fi

    # Cleanup restore directory (keep for debugging if failures)
    if [[ $failed -eq 0 ]]; then
        rm -rf "$restore_dir"
        log DEBUG "Cleaned up restore directory"
    else
        log INFO "Restore directory preserved for debugging: $restore_dir"
    fi

    return 0
}

################################################################################
# Reporting Functions
################################################################################

generate_test_report() {
    local report_file="$TEST_LOG_DIR/restore-test-$(date +%Y%m%d-%H%M%S).log"
    local json_file="$TEST_LOG_DIR/restore-test-$(date +%Y%m%d-%H%M%S).json"

    mkdir -p "$TEST_LOG_DIR"

    # Text report
    {
        echo "========================================="
        echo "BACKUP RESTORE TEST REPORT"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Sample Size: $SAMPLE_SIZE files per subvolume"
        echo "========================================="
        echo ""

        for subvol in "${!TEST_RESULTS[@]}"; do
            local result="${TEST_RESULTS[$subvol]}"
            local duration="${TEST_DURATIONS[$subvol]:-0}"
            local errors="${TEST_ERRORS[$subvol]:-0}"
            local validated="${TEST_FILES_VALIDATED[$subvol]:-0}"
            local source="${TEST_SNAPSHOT_SOURCE[$subvol]:-unknown}"

            echo "Subvolume: $subvol"
            echo "  Result: $result"
            echo "  Source: $source"
            echo "  Duration: ${duration}s"
            echo "  Files Validated: $validated"
            echo "  Errors: $errors"
            echo ""
        done

        echo "========================================="
        echo "SUMMARY"
        echo "========================================="
        local total=0
        local passed=0
        local failed=0
        local skipped=0

        for result in "${TEST_RESULTS[@]}"; do
            ((total++))
            case $result in
                PASS) ((passed++)) ;;
                FAIL) ((failed++)) ;;
                SKIP|DRY-RUN) ((skipped++)) ;;
            esac
        done

        echo "Total Tests: $total"
        echo "Passed: $passed"
        echo "Failed: $failed"
        echo "Skipped: $skipped"

        if [[ $total -gt $skipped ]]; then
            local testable=$((total - skipped))
            echo "Success Rate: $(awk "BEGIN {printf \"%.1f\", ($passed/$testable)*100}")%"
        fi
        echo ""
        echo "Report saved to: $report_file"

    } | tee "$report_file"

    # JSON report (for programmatic access)
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"version\": \"$SCRIPT_VERSION\","
        echo "  \"sample_size\": $SAMPLE_SIZE,"
        echo "  \"results\": {"

        local first=true
        for subvol in "${!TEST_RESULTS[@]}"; do
            if ! $first; then echo ","; fi
            first=false

            echo -n "    \"$subvol\": {"
            echo -n "\"result\": \"${TEST_RESULTS[$subvol]}\", "
            echo -n "\"duration\": ${TEST_DURATIONS[$subvol]}, "
            echo -n "\"files_validated\": ${TEST_FILES_VALIDATED[$subvol]}, "
            echo -n "\"errors\": ${TEST_ERRORS[$subvol]}, "
            echo -n "\"source\": \"${TEST_SNAPSHOT_SOURCE[$subvol]}\""
            echo -n "}"
        done

        echo ""
        echo "  }"
        echo "}"
    } > "$json_file"

    log INFO "JSON report saved to: $json_file"
}

export_prometheus_metrics() {
    mkdir -p "$METRICS_DIR"

    {
        echo "# HELP backup_restore_test_success Whether restore test passed (1) or failed (0)"
        echo "# TYPE backup_restore_test_success gauge"

        for subvol in "${!TEST_RESULTS[@]}"; do
            local value=0
            [[ "${TEST_RESULTS[$subvol]}" == "PASS" ]] && value=1
            echo "backup_restore_test_success{subvolume=\"$subvol\"} $value"
        done

        echo ""
        echo "# HELP backup_restore_test_duration_seconds Time taken for restore test"
        echo "# TYPE backup_restore_test_duration_seconds gauge"

        for subvol in "${!TEST_DURATIONS[@]}"; do
            echo "backup_restore_test_duration_seconds{subvolume=\"$subvol\"} ${TEST_DURATIONS[$subvol]}"
        done

        echo ""
        echo "# HELP backup_restore_test_files_validated Number of files successfully validated"
        echo "# TYPE backup_restore_test_files_validated gauge"

        for subvol in "${!TEST_FILES_VALIDATED[@]}"; do
            echo "backup_restore_test_files_validated{subvolume=\"$subvol\"} ${TEST_FILES_VALIDATED[$subvol]}"
        done

        echo ""
        echo "# HELP backup_restore_test_last_run_timestamp Unix timestamp of last test"
        echo "# TYPE backup_restore_test_last_run_timestamp gauge"
        echo "backup_restore_test_last_run_timestamp $(date +%s)"

    } > "$METRICS_FILE"

    log INFO "Prometheus metrics exported to: $METRICS_FILE"
}

################################################################################
# Usage and Argument Parsing
################################################################################

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automated backup restore testing for BTRFS snapshots.

OPTIONS:
    --subvolume NAME    Test specific subvolume only
    --sample-size N     Number of files to test per subvolume (default: $SAMPLE_SIZE)
    --dry-run           Show what would be tested without executing
    --verbose           Enable debug output
    --json              Output JSON report to stdout
    --help              Show this help message

EXAMPLES:
    # Test all subvolumes
    $SCRIPT_NAME

    # Test specific subvolume with verbose output
    $SCRIPT_NAME --subvolume htpc-home --verbose

    # Dry-run to see what would be tested
    $SCRIPT_NAME --dry-run

    # Custom sample size
    $SCRIPT_NAME --sample-size 100

SUBVOLUMES:
    - htpc-home
    - htpc-root
    - subvol1-docs
    - subvol2-pics
    - subvol3-opptak
    - subvol7-containers

EXIT CODES:
    0 - All tests passed
    1 - One or more tests failed
    2 - Invalid arguments

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subvolume)
                SPECIFIC_SUBVOL="$2"
                shift 2
                ;;
            --sample-size)
                SAMPLE_SIZE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    # Validate specific subvolume if provided
    if [[ -n "$SPECIFIC_SUBVOL" ]]; then
        if [[ ! -v SUBVOLUMES[$SPECIFIC_SUBVOL] ]]; then
            log ERROR "Unknown subvolume: $SPECIFIC_SUBVOL"
            log ERROR "Valid subvolumes: ${!SUBVOLUMES[@]}"
            exit 2
        fi
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    parse_arguments "$@"

    log INFO "========================================="
    log INFO "BTRFS Backup Restore Test"
    log INFO "Version: $SCRIPT_VERSION"
    log INFO "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    log INFO "========================================="

    if $DRY_RUN; then
        log INFO "[DRY-RUN MODE - No changes will be made]"
    fi

    # Ensure directories exist
    mkdir -p "$RESTORE_TEST_DIR" "$TEST_LOG_DIR" "$METRICS_DIR"

    # Test subvolumes
    if [[ -n "$SPECIFIC_SUBVOL" ]]; then
        log INFO "Testing specific subvolume: $SPECIFIC_SUBVOL"
        test_subvolume_restore "$SPECIFIC_SUBVOL"
    else
        log INFO "Testing all subvolumes"
        for subvol in "${!SUBVOLUMES[@]}"; do
            test_subvolume_restore "$subvol"
            echo ""
        done
    fi

    # Generate reports
    log INFO ""
    log INFO "========================================="
    log INFO "Generating Reports"
    log INFO "========================================="
    generate_test_report

    if ! $DRY_RUN; then
        export_prometheus_metrics
    fi

    # Summary
    log INFO ""
    log INFO "========================================="
    log INFO "TEST SUMMARY"
    log INFO "========================================="

    local total=${#TEST_RESULTS[@]}
    local passed=0
    local failed=0

    for result in "${TEST_RESULTS[@]}"; do
        case $result in
            PASS) ((passed++)) ;;
            FAIL) ((failed++)) ;;
        esac
    done

    if [[ $failed -eq 0 && $passed -gt 0 ]]; then
        log SUCCESS "All $passed restore tests PASSED ✓"
        exit 0
    elif [[ $passed -eq 0 && $failed -eq 0 ]]; then
        log WARNING "No tests executed (all skipped or dry-run)"
        exit 0
    else
        log ERROR "$failed of $total restore tests FAILED ✗"
        log ERROR "Check logs for details: $TEST_LOG_DIR/restore-test-*.log"
        exit 1
    fi
}

# Execute main
main "$@"
