# Project A: Disaster Recovery - Production Implementation Roadmap

**Created:** 2025-11-18
**Status:** Ready for CLI Execution
**Priority:** 🔥 CRITICAL - Untested backups = No backups
**Estimated Effort:** 8-10 hours (3-4 CLI sessions)
**Foundation:** Builds on existing backup-strategy.md and storage-layout.md

---

## Executive Summary

**The Problem:**
Your homelab has sophisticated backup automation creating 6 subvolume snapshots daily/weekly to an 18TB external drive. But **zero restore validation exists**. In a disaster, you'd discover whether backups work at the worst possible moment.

**The Solution:**
Implement a **three-pillar DR framework**:
1. **Automated Restore Validation** - Monthly testing proves backups are restorable
2. **Production Runbooks** - Step-by-step recovery procedures for every failure scenario
3. **Proactive Monitoring** - Alerts before backup failures become disasters

**Business Value:**
```
Current State: ✅ Backups exist → ❌ Untested → ❓ Unknown if recoverable → 😱 Panic during disaster
Target State:  ✅ Backups exist → ✅ Tested monthly → ✅ Proven recoverable → 😌 Calm during disaster
```

**Real Impact:**
- **Without this:** System SSD fails → Panic → Attempt restore → "Parent snapshot not found!" → Total data loss → Rebuild from scratch (weeks)
- **With this:** System SSD fails → Reference DR-001 runbook → Restore in 4 hours → Back online same day

---

## Foundation Analysis

### What Already Works (Leverage This)

**Backup Infrastructure:** `scripts/btrfs-snapshot-backup.sh` (545 lines, production-grade)

**Backup Coverage:**

| Tier | Subvolume | Source | Size | Criticality | Local Retention | External Retention |
|------|-----------|--------|------|-------------|-----------------|-------------------|
| 1 | htpc-home | /home | 50GB | **CRITICAL** | 7 daily | 8 weekly + 12 monthly |
| 1 | subvol3-opptak | BTRFS pool | 2TB | **CRITICAL** | 7 daily | 8 weekly + 12 monthly |
| 1 | subvol7-containers | BTRFS pool | 100GB | **CRITICAL** | 7 daily | 4 weekly + 6 monthly |
| 2 | subvol1-docs | BTRFS pool | 20GB | Important | 7 daily | 8 weekly + 6 monthly |
| 2 | htpc-root | / | 40GB | Important | 1 monthly | 6 monthly |
| 3 | subvol2-pics | BTRFS pool | 500GB | Standard | 4 weekly | 12 monthly |

**Backup Schedule:**
- **Daily:** 02:00 AM (Tier 1 local snapshots)
- **Weekly:** Sunday 03:00 AM (All tiers → external drive)
- **Monthly:** 1st of month 04:00 AM (Monthly snapshots)

**Automation:**
- ✅ Systemd timers: `btrfs-backup-daily.timer`, `btrfs-backup-weekly.timer`
- ✅ Passwordless sudo configured for BTRFS operations
- ✅ LUKS-encrypted 18TB external drive
- ✅ Comprehensive logging to `~/containers/data/backup-logs/`

**Storage Architecture:**
- **System SSD:** 128GB NVMe BTRFS (constrained - 81% full, critical threshold)
- **BTRFS Pool:** 13TB HDD array (65% full, healthy)
- **External:** 18TB WD drive (LUKS encrypted, BTRFS)

### Critical Gaps (Fix These)

**❌ Gap 1: Zero Restore Validation**
- No proof that snapshots are actually restorable
- No verification of data integrity post-restore
- Unknown: Can we recover from disaster?
- **Risk:** Discover corruption during actual disaster

**❌ Gap 2: No Disaster Recovery Procedures**
- No runbooks for failure scenarios (SSD failure, pool corruption, accidental deletion)
- No documented recovery steps
- No time estimates (RTO unknown)
- **Risk:** Panic-driven decisions during crisis

**❌ Gap 3: Silent Backup Failures**
- Backup failures only visible in log files
- No Prometheus metrics for backup health
- No alerts when backups don't run or fail
- **Risk:** Weeks of failed backups before discovery

**❌ Gap 4: Unknown RTO/RPO**
- RTO (Recovery Time Objective): How long does full restore take? **Unknown**
- RPO (Recovery Point Objective): How much data loss is acceptable? **Undocumented**
- No capacity planning for recovery
- **Risk:** Unrealistic recovery expectations

---

## Architecture: Production DR Framework

### Design Principles

1. **Non-Destructive Testing** - Always restore to temporary locations, never overwrite live data
2. **Automated Monthly Validation** - Continuous confidence through regular testing
3. **Fail-Fast Alerts** - Detect backup issues before disaster strikes
4. **Documented Procedures** - No tribal knowledge, everything written down
5. **Measured Recovery** - Know RTO/RPO with real data, not guesses

### Three-Pillar Framework

```
┌─────────────────────────────────────────────────────────────────┐
│                     PILLAR 1: VALIDATION                        │
│  Automated Restore Testing (Monthly via systemd timer)         │
│  • Random sample validation (50 files per subvolume)           │
│  • Checksum verification (sha256)                              │
│  • Permission/ownership validation                             │
│  • SELinux context verification                                │
│  • Pass/fail reporting                                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Exports metrics to →
┌─────────────────────────────────────────────────────────────────┐
│                     PILLAR 2: MONITORING                        │
│  Prometheus Metrics + Grafana Dashboard + Alertmanager         │
│  • backup_restore_test_success{subvolume="htpc-home"}          │
│  • backup_last_success_timestamp                               │
│  • backup_age_seconds (time since last backup)                 │
│  • Alerts: Backup failed, Restore test failed, Backup too old  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Guides recovery with →
┌─────────────────────────────────────────────────────────────────┐
│                     PILLAR 3: RUNBOOKS                          │
│  Step-by-step procedures for each failure scenario             │
│  • DR-001: System SSD Failure (RTO: 4-6h)                      │
│  • DR-002: BTRFS Pool Corruption (RTO: 6-12h)                  │
│  • DR-003: Accidental Deletion (RTO: 5-30min)                  │
│  • DR-004: Total Catastrophe (RTO: 1-2 weeks)                  │
│  • RTO/RPO documented with real measurements                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Restore Validation Framework (3-4 hours)

**Objective:** Prove backups are restorable through automated monthly testing

#### Deliverable 1.1: Core Testing Script

**File:** `scripts/test-backup-restore.sh` (~450 lines)

**Key Features:**
- Test all 6 subvolumes or specific ones (`--subvolume` flag)
- Configurable sample size (`--sample-size`, default 50 files)
- Dry-run mode (`--dry-run`)
- Verbose logging (`--verbose`)
- JSON + text reports
- Prometheus metrics export

**Testing Strategy:**
```bash
# For each subvolume:
1. Get latest snapshot (prefer external for realism)
2. Select 50 random files (weighted across directories)
3. Restore to /tmp/restore-tests/<subvol>-<timestamp>/
4. Validate each file:
   ✓ Checksum matches (cmp -s)
   ✓ Permissions match (stat -c '%a')
   ✓ Ownership matches (stat -c '%U:%G')
   ✓ SELinux context matches (ls -Z)
5. Generate pass/fail report
6. Export metrics for Prometheus
7. Cleanup temp files (after 7 days)
```

**Critical Implementation Details:**

```bash
#!/bin/bash
################################################################################
# BTRFS Backup Restore Testing Script
# Purpose: Automated monthly validation of backup integrity
# Author: Generated for fedora-htpc homelab
# Version: 1.0
################################################################################

set -euo pipefail

# Configuration
SAMPLE_SIZE=50
RESTORE_TEST_DIR="/tmp/restore-tests"
TEST_LOG_DIR="$HOME/containers/data/backup-logs"
METRICS_DIR="$HOME/containers/data/backup-metrics"
METRICS_FILE="$METRICS_DIR/restore-test-metrics.prom"

# Backup locations (match btrfs-snapshot-backup.sh)
EXTERNAL_BACKUP_ROOT="/run/media/patriark/WD-18TB/.snapshots"
LOCAL_HOME_SNAPSHOTS="$HOME/.snapshots"
LOCAL_POOL_SNAPSHOTS="/mnt/btrfs-pool/.snapshots"

# Subvolume definitions
declare -A SUBVOL_PATHS
SUBVOL_PATHS[htpc-home]="$LOCAL_HOME_SNAPSHOTS/htpc-home"
SUBVOL_PATHS[subvol3-opptak]="$LOCAL_POOL_SNAPSHOTS/subvol3-opptak"
SUBVOL_PATHS[subvol7-containers]="$LOCAL_POOL_SNAPSHOTS/subvol7-containers"
SUBVOL_PATHS[subvol1-docs]="$LOCAL_POOL_SNAPSHOTS/subvol1-docs"
SUBVOL_PATHS[htpc-root]="$LOCAL_HOME_SNAPSHOTS/htpc-root"
SUBVOL_PATHS[subvol2-pics]="$LOCAL_POOL_SNAPSHOTS/subvol2-pics"

# Test result tracking
declare -A TEST_RESULTS      # PASS/FAIL/SKIP
declare -A TEST_DURATIONS    # seconds
declare -A TEST_ERRORS       # error count
declare -A FILES_VALIDATED   # file count

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case $level in
        INFO)    echo -e "${BLUE}[INFO]${NC} $*" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $*" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $*" ;;
    esac
}

# Get latest snapshot (prefer external for realistic testing)
get_latest_snapshot() {
    local subvol=$1

    # Try external first (more realistic - tests send/receive)
    local external_dir="$EXTERNAL_BACKUP_ROOT/$subvol"
    if [[ -d "$external_dir" ]]; then
        local latest=$(ls -1td "$external_dir"/* 2>/dev/null | head -1)
        if [[ -n "$latest" ]]; then
            echo "$latest"
            return 0
        fi
    fi

    # Fallback to local
    local local_dir="${SUBVOL_PATHS[$subvol]}"
    if [[ -d "$local_dir" ]]; then
        local latest=$(ls -1td "$local_dir"/* 2>/dev/null | head -1)
        if [[ -n "$latest" ]]; then
            echo "$latest"
            return 0
        fi
    fi

    echo ""
    return 1
}

# Select random sample of files
select_random_files() {
    local snapshot_path=$1
    local sample_size=$2
    local temp_list="/tmp/file-list-$$.txt"

    # Find all regular files (exclude hidden, special files)
    # Use shuf for random selection
    find "$snapshot_path" -type f \
        \( ! -path "*/.*" \) \
        \( ! -path "*/proc/*" \) \
        \( ! -path "*/sys/*" \) \
        \( ! -path "*/dev/*" \) \
        -print0 2>/dev/null | \
        shuf -z -n "$sample_size" | \
        tr '\0' '\n' > "$temp_list"

    if [[ ! -s "$temp_list" ]]; then
        rm -f "$temp_list"
        return 1
    fi

    cat "$temp_list"
    rm -f "$temp_list"
    return 0
}

# Validate single file
validate_file() {
    local original=$1
    local restored=$2
    local errors=0

    # Checksum validation (binary comparison)
    if ! cmp -s "$original" "$restored"; then
        log ERROR "Checksum mismatch: $(basename "$original")"
        ((errors++))
    fi

    # Permission validation
    local orig_perms=$(stat -c '%a' "$original" 2>/dev/null || echo "")
    local rest_perms=$(stat -c '%a' "$restored" 2>/dev/null || echo "")
    if [[ -n "$orig_perms" && "$orig_perms" != "$rest_perms" ]]; then
        log WARNING "Permission mismatch: $(basename "$original") ($orig_perms vs $rest_perms)"
        # Don't count as error - informational
    fi

    # Ownership validation
    local orig_owner=$(stat -c '%U:%G' "$original" 2>/dev/null || echo "")
    local rest_owner=$(stat -c '%U:%G' "$restored" 2>/dev/null || echo "")
    if [[ -n "$orig_owner" && "$orig_owner" != "$rest_owner" ]]; then
        log WARNING "Ownership mismatch: $(basename "$original") ($orig_owner vs $rest_owner)"
        # Don't count as error - test restore uses current user
    fi

    # SELinux context (informational only)
    if [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        local orig_context=$(ls -Z "$original" 2>/dev/null | awk '{print $1}')
        local rest_context=$(ls -Z "$restored" 2>/dev/null | awk '{print $1}')
        if [[ -n "$orig_context" && "$orig_context" != "$rest_context" ]]; then
            log WARNING "SELinux context differs: $(basename "$original")"
            # Don't count as error - context differs in test location
        fi
    fi

    return $errors
}

# Test restore for single subvolume
test_subvolume_restore() {
    local subvol=$1
    local start_time=$(date +%s)

    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO "Testing restore for: $subvol"
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get latest snapshot
    local snapshot=$(get_latest_snapshot "$subvol")
    if [[ -z "$snapshot" ]]; then
        log ERROR "No snapshot found for $subvol"
        TEST_RESULTS[$subvol]="FAIL"
        TEST_ERRORS[$subvol]=1
        return 1
    fi

    log INFO "Using snapshot: $snapshot"
    local snapshot_age=$(($(date +%s) - $(stat -c %Y "$snapshot")))
    log INFO "Snapshot age: $((snapshot_age / 86400)) days"

    # Create restore directory
    local restore_dir="$RESTORE_TEST_DIR/$subvol-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$restore_dir"
    log INFO "Restore directory: $restore_dir"

    # Select random files
    log INFO "Selecting $SAMPLE_SIZE random files for testing..."
    local file_list=$(select_random_files "$snapshot" "$SAMPLE_SIZE")

    if [[ -z "$file_list" ]]; then
        log WARNING "No files found in snapshot for $subvol"
        TEST_RESULTS[$subvol]="SKIP"
        FILES_VALIDATED[$subvol]=0
        return 0
    fi

    local file_count=$(echo "$file_list" | wc -l)
    log INFO "Selected $file_count files for validation"

    # Restore and validate each file
    local failed=0
    local validated=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Get relative path
        local rel_path="${file#$snapshot/}"
        local restore_path="$restore_dir/$rel_path"

        # Create parent directory
        mkdir -p "$(dirname "$restore_path")"

        # Restore file (preserve all attributes)
        if cp -a "$file" "$restore_path" 2>/dev/null; then
            # Validate
            if validate_file "$file" "$restore_path"; then
                ((validated++))
            else
                ((failed++))
            fi
        else
            log ERROR "Failed to restore: $(basename "$file")"
            ((failed++))
        fi
    done <<< "$file_list"

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    TEST_DURATIONS[$subvol]=$duration
    FILES_VALIDATED[$subvol]=$validated

    # Determine result
    if [[ $failed -eq 0 && $validated -gt 0 ]]; then
        TEST_RESULTS[$subvol]="PASS"
        TEST_ERRORS[$subvol]=0
        log SUCCESS "✓ $subvol: $validated files validated, 0 failures (${duration}s)"
    elif [[ $validated -eq 0 ]]; then
        TEST_RESULTS[$subvol]="SKIP"
        TEST_ERRORS[$subvol]=0
        log WARNING "⊘ $subvol: No files to validate (empty snapshot?)"
    else
        TEST_RESULTS[$subvol]="FAIL"
        TEST_ERRORS[$subvol]=$failed
        log ERROR "✗ $subvol: $validated validated, $failed FAILED (${duration}s)"
    fi

    log INFO ""

    return 0
}

# Generate test reports
generate_test_report() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="$TEST_LOG_DIR/restore-test-$timestamp.log"
    local json_file="$TEST_LOG_DIR/restore-test-$timestamp.json"

    mkdir -p "$TEST_LOG_DIR"

    # Text report
    {
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  BACKUP RESTORE TEST REPORT"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Host: $(hostname)"
        echo "Sample Size: $SAMPLE_SIZE files per subvolume"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  RESULTS BY SUBVOLUME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        for subvol in "${!TEST_RESULTS[@]}"; do
            local result="${TEST_RESULTS[$subvol]}"
            local duration="${TEST_DURATIONS[$subvol]:-0}"
            local errors="${TEST_ERRORS[$subvol]:-0}"
            local validated="${FILES_VALIDATED[$subvol]:-0}"

            echo "Subvolume: $subvol"
            echo "  Result:    $result"
            echo "  Duration:  ${duration}s"
            echo "  Validated: $validated files"
            echo "  Errors:    $errors"
            echo ""
        done

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  SUMMARY"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        local total=0
        local passed=0
        local failed=0
        local skipped=0

        for result in "${TEST_RESULTS[@]}"; do
            ((total++))
            case $result in
                PASS) ((passed++)) ;;
                FAIL) ((failed++)) ;;
                SKIP) ((skipped++)) ;;
            esac
        done

        echo "Total:        $total subvolumes"
        echo "Passed:       $passed"
        echo "Failed:       $failed"
        echo "Skipped:      $skipped"

        if [[ $total -gt 0 ]]; then
            local success_rate=$(awk "BEGIN {printf \"%.1f\", ($passed/$total)*100}")
            echo "Success Rate: ${success_rate}%"
        fi

        echo ""

        if [[ $failed -eq 0 && $passed -gt 0 ]]; then
            echo "✅ ALL TESTS PASSED - Backups are verified restorable"
        elif [[ $failed -gt 0 ]]; then
            echo "❌ TESTS FAILED - Investigate backup integrity immediately"
        else
            echo "⚠️  NO TESTS RUN - Check snapshot availability"
        fi

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    } | tee "$report_file"

    # JSON report (for programmatic access)
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"sample_size\": $SAMPLE_SIZE,"
        echo "  \"results\": {"

        local first=true
        for subvol in "${!TEST_RESULTS[@]}"; do
            if [[ "$first" == "false" ]]; then
                echo ","
            fi
            first=false

            echo -n "    \"$subvol\": {"
            echo -n " \"result\": \"${TEST_RESULTS[$subvol]}\","
            echo -n " \"duration\": ${TEST_DURATIONS[$subvol]:-0},"
            echo -n " \"validated\": ${FILES_VALIDATED[$subvol]:-0},"
            echo -n " \"errors\": ${TEST_ERRORS[$subvol]:-0}"
            echo -n " }"
        done

        echo ""
        echo "  }"
        echo "}"
    } > "$json_file"

    log INFO "Reports saved:"
    log INFO "  Text: $report_file"
    log INFO "  JSON: $json_file"
}

# Export Prometheus metrics
export_prometheus_metrics() {
    mkdir -p "$METRICS_DIR"

    {
        echo "# HELP backup_restore_test_success Whether restore test passed (1=pass, 0=fail)"
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
        echo "# HELP backup_restore_test_files_validated Number of files validated"
        echo "# TYPE backup_restore_test_files_validated gauge"

        for subvol in "${!FILES_VALIDATED[@]}"; do
            echo "backup_restore_test_files_validated{subvolume=\"$subvol\"} ${FILES_VALIDATED[$subvol]}"
        done

        echo ""
        echo "# HELP backup_restore_test_errors Number of validation errors"
        echo "# TYPE backup_restore_test_errors gauge"

        for subvol in "${!TEST_ERRORS[@]}"; do
            echo "backup_restore_test_errors{subvolume=\"$subvol\"} ${TEST_ERRORS[$subvol]}"
        done

        echo ""
        echo "# HELP backup_restore_test_last_run_timestamp Unix timestamp of last test"
        echo "# TYPE backup_restore_test_last_run_timestamp gauge"
        echo "backup_restore_test_last_run_timestamp $(date +%s)"

    } > "$METRICS_FILE.$$"

    mv "$METRICS_FILE.$$" "$METRICS_FILE"

    log INFO "Prometheus metrics exported to: $METRICS_FILE"
}

# Cleanup old test directories (keep last 7 days)
cleanup_old_tests() {
    if [[ -d "$RESTORE_TEST_DIR" ]]; then
        find "$RESTORE_TEST_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    fi
}

# Main execution
main() {
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO "  BACKUP RESTORE TEST - Starting"
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO ""
    log INFO "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log INFO "Sample size: $SAMPLE_SIZE files per subvolume"
    log INFO ""

    # Cleanup old test directories
    cleanup_old_tests

    # Test each subvolume
    for subvol in htpc-home subvol7-containers subvol3-opptak subvol1-docs htpc-root subvol2-pics; do
        test_subvolume_restore "$subvol"
    done

    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO "  Generating Reports"
    log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log INFO ""

    # Generate reports
    generate_test_report
    export_prometheus_metrics

    # Summary
    local total=${#TEST_RESULTS[@]}
    local passed=0
    for result in "${TEST_RESULTS[@]}"; do
        [[ "$result" == "PASS" ]] && ((passed++))
    done

    log INFO ""
    if [[ $passed -eq $total ]]; then
        log SUCCESS "All $total restore tests PASSED ✓"
        exit 0
    else
        log ERROR "$((total - passed)) restore tests FAILED ✗"
        exit 1
    fi
}

main "$@"
```

**Implementation Steps:**

1. Create the script:
```bash
nano ~/containers/scripts/test-backup-restore.sh
# Paste script above
chmod +x ~/containers/scripts/test-backup-restore.sh
```

2. Create metrics directory:
```bash
mkdir -p ~/containers/data/backup-metrics
```

3. Test manually:
```bash
# Dry-run first
cd ~/containers/scripts
./test-backup-restore.sh

# Review results
cat ~/containers/data/backup-logs/restore-test-*.log
cat ~/containers/data/backup-metrics/restore-test-metrics.prom
```

**Acceptance Criteria:**
- [

] Script executes without errors
- [ ] All 6 subvolumes tested
- [ ] Text + JSON reports generated
- [ ] Prometheus metrics exported
- [ ] Exit code 0 if all pass, 1 if any fail

---

#### Deliverable 1.2: Systemd Timer Automation

**Objective:** Run restore tests automatically on last Sunday of each month

**Files to create:**
1. `~/.config/systemd/user/backup-restore-test.service`
2. `~/.config/systemd/user/backup-restore-test.timer`

**Timer Configuration:**

```ini
# ~/.config/systemd/user/backup-restore-test.timer
[Unit]
Description=Monthly Backup Restore Test Timer
Documentation=file:///home/patriark/containers/docs/20-operations/guides/disaster-recovery.md

[Timer]
# Run on last Sunday of every month at 04:00 AM
# (1 hour after weekly backup completes at 03:00)
OnCalendar=Sun *-*-22..28 04:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
```

**Service Configuration:**

```ini
# ~/.config/systemd/user/backup-restore-test.service
[Unit]
Description=Backup Restore Validation Test
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/containers/scripts/test-backup-restore.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=2h

# Optional: Email on failure (requires mail configuration)
# OnFailure=email-notification@%n.service

[Install]
WantedBy=multi-user.target
```

**Implementation Steps:**

```bash
# Create timer
nano ~/.config/systemd/user/backup-restore-test.timer
# Paste timer config above

# Create service
nano ~/.config/systemd/user/backup-restore-test.service
# Paste service config above

# Reload systemd
systemctl --user daemon-reload

# Enable and start timer
systemctl --user enable backup-restore-test.timer
systemctl --user start backup-restore-test.timer

# Verify timer scheduled
systemctl --user list-timers backup-restore-test.timer

# Manual test run
systemctl --user start backup-restore-test.service
journalctl --user -u backup-restore-test.service -f
```

**Acceptance Criteria:**
- [ ] Timer shows next scheduled run (last Sunday of month)
- [ ] Manual trigger works: `systemctl --user start backup-restore-test.service`
- [ ] Logs visible in journalctl
- [ ] Service completes successfully
- [ ] Persistent across reboots

---

### Phase 2: Monitoring & Alerting Integration (2-3 hours)

**Objective:** Integrate backup health metrics into existing Prometheus/Grafana stack

#### Deliverable 2.1: Prometheus Metrics Collection

**Strategy:** Use node_exporter textfile collector to expose backup metrics

**Implementation Steps:**

1. **Configure node_exporter for textfile collection:**

```bash
# Check if textfile collector is enabled
systemctl --user cat node-exporter.service | grep collector.textfile

# If not, add to node_exporter arguments:
# --collector.textfile.directory=/home/patriark/containers/data/backup-metrics
```

2. **Update backup script to export metrics:**

Add to `scripts/btrfs-snapshot-backup.sh` (at end of script):

```bash
# Export backup metrics for Prometheus
export_backup_metrics() {
    local metrics_file="$HOME/containers/data/backup-metrics/backup.prom"
    local timestamp=$(date +%s)

    {
        echo "# HELP backup_last_success_timestamp Unix timestamp of last successful backup"
        echo "# TYPE backup_last_success_timestamp gauge"

        for subvol in htpc-home subvol3-opptak subvol7-containers subvol1-docs htpc-root subvol2-pics; do
            echo "backup_last_success_timestamp{subvolume=\"$subvol\",tier=\"1\"} $timestamp"
        done

        echo ""
        echo "# HELP backup_snapshot_count Number of snapshots available"
        echo "# TYPE backup_snapshot_count gauge"

        # Count local snapshots
        for subvol in htpc-home subvol3-opptak subvol7-containers; do
            local count=$(ls -1 $HOME/.snapshots/$subvol 2>/dev/null | wc -l || echo 0)
            echo "backup_snapshot_count{subvolume=\"$subvol\",location=\"local\"} $count"
        done

    } > "$metrics_file.$$"

    mv "$metrics_file.$$" "$metrics_file"
}

# Call at end of successful backup
export_backup_metrics
```

3. **Verify metrics collection:**

```bash
# Check metrics file
cat ~/containers/data/backup-metrics/backup.prom

# Check if Prometheus scrapes it (after node_exporter restart)
curl -s http://localhost:9090/api/v1/query?query=backup_last_success_timestamp | jq
```

**Acceptance Criteria:**
- [ ] Metrics file created: `~/containers/data/backup-metrics/backup.prom`
- [ ] Metrics file updated: `~/containers/data/backup-metrics/restore-test-metrics.prom`
- [ ] Prometheus scrapes both files
- [ ] Metrics visible in Prometheus UI

---

#### Deliverable 2.2: Prometheus Alert Rules

**File:** `~/containers/config/prometheus/alerts/backup-alerts.yml`

```yaml
groups:
  - name: backup_health
    interval: 60s
    rules:
      - alert: BackupFailed
        expr: (time() - backup_last_success_timestamp) > 172800
        for: 1h
        labels:
          severity: critical
          category: backup
        annotations:
          summary: "Backup failed for {{ $labels.subvolume }}"
          description: "No successful backup for {{ $labels.subvolume }} in 48+ hours"

      - alert: RestoreTestFailed
        expr: backup_restore_test_success == 0
        for: 5m
        labels:
          severity: critical
          category: disaster-recovery
        annotations:
          summary: "Restore test FAILED for {{ $labels.subvolume }}"
          description: "Backup may be corrupted - investigate immediately!"

      - alert: RestoreTestOverdue
        expr: (time() - backup_restore_test_last_run_timestamp) > 2678400
        for: 6h
        labels:
          severity: warning
          category: disaster-recovery
        annotations:
          summary: "Restore test overdue"
          description: "Restore test hasn't run in 31+ days (should be monthly)"

      - alert: BackupSnapshotCountLow
        expr: backup_snapshot_count{location="local"} < 3
        for: 2h
        labels:
          severity: warning
          category: backup
        annotations:
          summary: "Low snapshot count for {{ $labels.subvolume }}"
          description: "Only {{ $value }} local snapshots available (expected: 7 daily)"
```

**Implementation:**

```bash
# Create alerts directory
mkdir -p ~/containers/config/prometheus/alerts

# Create backup-alerts.yml
nano ~/containers/config/prometheus/alerts/backup-alerts.yml
# Paste config above

# Update prometheus.yml to include alerts
nano ~/containers/config/prometheus/prometheus.yml

# Add to rule_files section:
# rule_files:
#   - '/config/alerts/backup-alerts.yml'

# Reload Prometheus
systemctl --user reload prometheus.service

# Verify alerts loaded
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="backup_health")'
```

**Acceptance Criteria:**
- [ ] Alert rules loaded in Prometheus
- [ ] Alerts visible in Prometheus UI (http://localhost:9090/alerts)
- [ ] Test alert fires (simulate backup failure)

---

#### Deliverable 2.3: Grafana Dashboard

**File:** `~/containers/config/grafana/provisioning/dashboards/backup-health.json`

**Dashboard Panels:**

1. **Backup Status Overview** (Stat panel)
   - Query: `time() - backup_last_success_timestamp`
   - Thresholds: Green <24h, Yellow 24-48h, Red >48h

2. **Restore Test Results** (Table)
   - Query: `backup_restore_test_success`
   - Show: Subvolume, Last Test Result, Files Validated, Errors

3. **Backup Age** (Graph)
   - Query: `(time() - backup_last_success_timestamp) / 3600`
   - Y-axis: Hours since last backup

4. **Snapshot Inventory** (Stat)
   - Query: `backup_snapshot_count{location="local"}`
   - Show: Count per subvolume

5. **Restore Test Duration** (Graph)
   - Query: `backup_restore_test_duration_seconds`
   - Track: Test performance over time

**Quick Dashboard Creation:**

```bash
# Use Grafana UI to create dashboard with queries above
# Navigate to: http://localhost:3000/dashboard/new

# Or import pre-built dashboard JSON (if provided)
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @backup-health-dashboard.json
```

**Acceptance Criteria:**
- [ ] Dashboard created in Grafana
- [ ] All panels show data
- [ ] Thresholds configured for visual alerts
- [ ] Dashboard saved and accessible

---

### Phase 3: Disaster Recovery Runbooks (2-3 hours)

**Objective:** Document step-by-step recovery procedures for each failure scenario

#### Runbook Template Structure

Each runbook follows this format:

```markdown
# DR-XXX: [Scenario Name]

**Severity:** Critical | High | Medium
**RTO Target:** X hours (Recovery Time Objective)
**RPO Target:** X days (Recovery Point Objective)
**Last Tested:** YYYY-MM-DD
**Test Result:** ✅ Passed | ❌ Failed | ⏸️ Not Tested

---

## Scenario Description

[What failed? What's the impact?]

## Prerequisites

- [ ] External backup drive available
- [ ] Sufficient disk space for restore
- [ ] Root/sudo access
- [ ] [Other requirements]

## Detection

**Symptoms:**
- Symptom 1
- Symptom 2

**Verification command:**
```bash
# Command to confirm this scenario
```

## Impact Assessment

**Affected:**
- Service X (down)
- Data Y (unavailable)

**Still Working:**
- Service A
- Data B

## Recovery Procedure

### Step 1: Initial Assessment
[Commands and checks]

### Step 2: Prepare for Recovery
[Preparation steps]

### Step 3: Execute Restore
[Actual restore commands - copy-paste ready]

### Step 4: Verify Recovery
[Validation steps]

### Step 5: Return to Service
[Bring systems back online]

## Verification Checklist

- [ ] Data restored successfully
- [ ] Services started
- [ ] Users can access
- [ ] Monitoring shows green

## Post-Recovery Actions

- [ ] Root cause analysis
- [ ] Update runbook with lessons learned
- [ ] Document in incident log

## Rollback Plan

[If recovery fails, how to rollback]

## Estimated Timeline

- Detection: X minutes
- Preparation: X minutes
- Execution: X hours
- Verification: X minutes
- **Total RTO: X hours**

---

**Appendix: Copy-Paste Commands**

```bash
# Ready-to-execute commands
```
```

---

#### Deliverable 3.1: DR-001 - System SSD Failure

**File:** `docs/20-operations/runbooks/DR-001-system-ssd-failure.md`

**Key Sections:**

**Scenario:** Complete system SSD failure - cannot boot, data inaccessible

**RTO Target:** 4-6 hours (includes OS reinstall)
**RPO Target:** Up to 7 days (last weekly external backup)

**Recovery Steps (Summary):**

1. **Acquire replacement SSD** (same size or larger, 256GB+ recommended)
2. **Install fresh Fedora 42** on replacement SSD
3. **Mount external backup drive:**
   ```bash
   sudo cryptsetup open /dev/sdX WD-18TB
   sudo mount /dev/mapper/WD-18TB /mnt/external
   ```
4. **Restore htpc-root:**
   ```bash
   # Get latest root snapshot
   LATEST_ROOT=$(ls -t /mnt/external/.snapshots/htpc-root/ | head -1)

   # Restore to new SSD
   sudo btrfs send /mnt/external/.snapshots/htpc-root/$LATEST_ROOT | \
     sudo btrfs receive /
   ```
5. **Restore htpc-home:**
   ```bash
   LATEST_HOME=$(ls -t /mnt/external/.snapshots/htpc-home/ | head -1)
   sudo btrfs send /mnt/external/.snapshots/htpc-home/$LATEST_HOME | \
     sudo btrfs receive /home
   ```
6. **Restore containers config/data:**
   ```bash
   LATEST_CONTAINERS=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)
   # Mount BTRFS pool
   sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool
   # Restore containers
   sudo btrfs send /mnt/external/.snapshots/subvol7-containers/$LATEST_CONTAINERS | \
     sudo btrfs receive /mnt/btrfs-pool/
   ```
7. **Reinstall Podman, systemd quadlets**
8. **Restart services, verify functionality**

**Acceptance Criteria:**
- [ ] Runbook created and reviewed
- [ ] Commands tested in safe environment (if possible)
- [ ] Clear, copy-paste ready commands
- [ ] All prerequisites documented

---

#### Deliverable 3.2: DR-002 - BTRFS Pool Corruption

**File:** `docs/20-operations/runbooks/DR-002-btrfs-pool-corruption.md`

**Scenario:** BTRFS pool becomes corrupted or unmountable

**RTO Target:** 6-12 hours (depends on data volume to restore)
**RPO Target:** Up to 7 days (Tier 1), up to 30 days (Tier 3)

**Recovery Priority Order:**
1. subvol7-containers (operational data - Jellyfin metadata, Grafana dashboards, Prometheus data)
2. subvol3-opptak (2TB phone recordings - critical backup)
3. subvol1-docs (documents)
4. subvol2-pics (photos - can be restored later)
5. subvol4-multimedia, subvol5-music (media - lowest priority, can re-rip)

---

#### Deliverable 3.3: DR-003 - Accidental Deletion

**File:** `docs/20-operations/runbooks/DR-003-accidental-deletion.md`

**Scenario:** User accidentally deletes files or directories

**RTO Target:** 5-30 minutes
**RPO Target:** Up to 1 day (daily snapshots)

**Quick Recovery:**
```bash
# List snapshots
ls -lt ~/.snapshots/htpc-home/

# Find deleted file
find ~/.snapshots/htpc-home/20251118-htpc-home/ -name "deleted-file.txt"

# Restore
cp -a ~/.snapshots/htpc-home/20251118-htpc-home/path/to/file.txt ~/restored-file.txt
```

---

#### Deliverable 3.4: DR-004 - Total Catastrophe

**File:** `docs/20-operations/runbooks/DR-004-total-catastrophe.md`

**Scenario:** Fire, flood, theft - both system AND external backup drive lost

**RTO Target:** 1-2 weeks (hardware replacement + rebuild)
**RPO Target:** Depends on off-site backup frequency (if any)

**Prevention Measures (Critical):**
- [ ] Implement off-site backup (cloud, friend's house, bank vault)
- [ ] Store recovery documentation separately (GitHub private repo, printed copy)
- [ ] Maintain hardware/software inventory (for insurance)
- [ ] Keep list of critical data priorities

**Recovery Strategy:**
1. Accept data loss for data not in off-site backups
2. Rebuild homelab from documentation (CLAUDE.md, quadlet definitions in GitHub)
3. Restore from off-site backups (if implemented)
4. Document lessons learned

---

### Phase 4: Testing & Validation (1-2 hours)

**Objective:** Validate all DR components work before disaster strikes

#### Test 1: Automated Restore Test (Required)

**Purpose:** Verify monthly automation works end-to-end

```bash
# Trigger manual test
systemctl --user start backup-restore-test.service

# Watch logs
journalctl --user -u backup-restore-test.service -f

# Verify outputs
ls -lh ~/containers/data/backup-logs/restore-test-*.log
cat ~/containers/data/backup-metrics/restore-test-metrics.prom

# Check Prometheus
curl -s http://localhost:9090/api/v1/query?query=backup_restore_test_success | jq

# Check Grafana dashboard
# Navigate to: http://localhost:3000 → Backup Health dashboard
```

**Success Criteria:**
- [ ] Test completes without errors
- [ ] All subvolumes show PASS
- [ ] Metrics exported to Prometheus
- [ ] Grafana dashboard updated
- [ ] Duration <30 minutes

---

#### Test 2: Accidental Deletion Recovery (Required)

**Purpose:** Validate DR-003 runbook with real scenario

**Setup:**
```bash
# Create test file with known checksum
echo "Critical data - $(date)" > ~/test-dr-file.txt
sha256sum ~/test-dr-file.txt > ~/test-dr-file.checksum

# Force snapshot creation
~/containers/scripts/btrfs-snapshot-backup.sh --subvolume home --local-only

# Wait for snapshot to complete
sleep 10

# Delete test file
rm ~/test-dr-file.txt
```

**Recovery (following DR-003):**
```bash
# Step 1: List snapshots
ls -lt ~/.snapshots/htpc-home/

# Step 2: Find deleted file
find ~/.snapshots/htpc-home/$(date +%Y%m%d)-htpc-home/ -name "test-dr-file.txt"

# Step 3: Restore
cp -a ~/.snapshots/htpc-home/$(date +%Y%m%d)-htpc-home/home/patriark/test-dr-file.txt ~/test-dr-file.txt

# Step 4: Verify checksum
sha256sum -c ~/test-dr-file.checksum
```

**Success Criteria:**
- [ ] File found in snapshot
- [ ] File restored successfully
- [ ] Checksum matches original
- [ ] Recovery completed in <5 minutes
- [ ] Runbook accurate (update if needed)

---

#### Test 3: Alert Testing (Required)

**Purpose:** Verify backup alerts fire correctly

**Test 1: Simulate backup failure:**
```bash
# Temporarily rename backup script
mv ~/containers/scripts/btrfs-snapshot-backup.sh{,.disabled}

# Wait 48+ hours (or manually set old timestamp in metrics)
echo "backup_last_success_timestamp{subvolume=\"htpc-home\",tier=\"1\"} $(date -d '3 days ago' +%s)" > \
  ~/containers/data/backup-metrics/backup.prom

# Check Prometheus alerts
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="BackupFailed")'

# Restore backup script
mv ~/containers/scripts/btrfs-snapshot-backup.sh{.disabled,}
```

**Test 2: Simulate restore test failure:**
```bash
# Manually set failed test
echo "backup_restore_test_success{subvolume=\"htpc-home\"} 0" > \
  ~/containers/data/backup-metrics/restore-test-metrics.prom

# Check alert fires
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="RestoreTestFailed")'
```

**Success Criteria:**
- [ ] BackupFailed alert fires after 48h
- [ ] RestoreTestFailed alert fires when success=0
- [ ] Alerts visible in Prometheus UI
- [ ] Alerts routed to Alertmanager (if configured)
- [ ] Discord notification received (if configured)

---

## Implementation Checklist

### Phase 1: Restore Validation ✅
- [ ] Create `scripts/test-backup-restore.sh`
- [ ] Test script manually (dry-run)
- [ ] Create metrics directory structure
- [ ] Create systemd timer + service
- [ ] Enable and test timer
- [ ] Verify monthly schedule correct

### Phase 2: Monitoring Integration ✅
- [ ] Update `btrfs-snapshot-backup.sh` with metrics export
- [ ] Configure node_exporter textfile collector
- [ ] Create `prometheus/alerts/backup-alerts.yml`
- [ ] Reload Prometheus config
- [ ] Create Grafana dashboard
- [ ] Test alerts (simulate failures)

### Phase 3: DR Runbooks ✅
- [ ] Create `docs/20-operations/runbooks/` directory
- [ ] Write DR-001 (System SSD Failure)
- [ ] Write DR-002 (BTRFS Pool Corruption)
- [ ] Write DR-003 (Accidental Deletion)
- [ ] Write DR-004 (Total Catastrophe)
- [ ] Review runbooks for accuracy
- [ ] Add to main documentation index

### Phase 4: Testing & Validation ✅
- [ ] Test 1: Automated restore test
- [ ] Test 2: Accidental deletion recovery
- [ ] Test 3: Alert testing (backup failure)
- [ ] Test 4: Alert testing (restore failure)
- [ ] Document test results
- [ ] Update runbooks based on testing

---

## Success Metrics

### Project Completion Criteria

**Must Have (Go/No-Go):**
- [ ] Restore testing script works for all 6 subvolumes
- [ ] Monthly automated tests scheduled and verified
- [ ] At least DR-001 and DR-003 runbooks complete and tested
- [ ] Backup metrics exported to Prometheus
- [ ] Critical alerts configured (BackupFailed, RestoreTestFailed)

**Should Have (High Priority):**
- [ ] All 4 DR runbooks complete
- [ ] Grafana dashboard operational
- [ ] All alerts tested and working
- [ ] Documentation updated in CLAUDE.md

**Could Have (Nice to Have):**
- [ ] Discord notifications for backup alerts
- [ ] RTO measurements documented
- [ ] Quarterly DR drill scheduled
- [ ] Off-site backup strategy planned

---

## Timeline & Effort Estimate

### Session 1: Core Validation Framework (3-4 hours)
- **Hour 1:** Create test-backup-restore.sh script
- **Hour 2:** Test script manually, fix issues, create metrics directory
- **Hour 3:** Create systemd timer/service, enable automation
- **Hour 4:** Verify timer scheduled, test manual trigger

**Deliverables:** Working automated restore testing

---

### Session 2: Monitoring & Runbooks (2-3 hours)
- **Hour 1:** Update backup script with metrics, configure Prometheus alerts
- **Hour 2:** Create Grafana dashboard, test alert firing
- **Hour 3:** Write DR-001 and DR-003 runbooks

**Deliverables:** Full monitoring stack + 2 critical runbooks

---

### Session 3: Testing & Polish (1-2 hours)
- **Hour 1:** Test DR-003 runbook (accidental deletion), test alerts
- **Hour 2:** Write DR-002 and DR-004 runbooks, update documentation

**Deliverables:** Tested runbooks, complete documentation

---

**Total Estimated Effort:** 8-10 hours across 3 CLI sessions

---

## Post-Project Maintenance

### Monthly (Automated)
- [ ] Restore test runs automatically (last Sunday)
- [ ] Review test results in Grafana
- [ ] Investigate any failures immediately

### Quarterly (Manual)
- [ ] Run full DR-003 test (accidental deletion)
- [ ] Review and update runbooks
- [ ] Test one additional runbook (rotate through DR-001, DR-002, DR-004)

### Annual (Manual)
- [ ] Table-top disaster recovery exercise
- [ ] Review and update all runbooks
- [ ] Validate RTO/RPO targets still appropriate
- [ ] Update backup strategy based on changes

---

## Risk Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **Restore test disrupts services** | High | Very Low | Tests use temp directories, never touch live data |
| **External drive unavailable during test** | Medium | Medium | Script falls back to local snapshots automatically |
| **Test takes too long (>2 hours)** | Low | Low | Sample size configurable, start with 50 files |
| **Metrics break Prometheus** | Medium | Very Low | Textfile collector isolated, validated format |
| **Runbooks become outdated** | High | Medium | Quarterly review process, test regularly |
| **False alerts cause alert fatigue** | Medium | Medium | Tuned thresholds (48h for backup, 31d for test) |

---

## Value Delivered

**Before Project:**
- ❌ Backups exist but untested
- ❌ No recovery procedures
- ❌ Silent failures
- ❌ Unknown RTO/RPO
- 😱 **Panic during disaster**

**After Project:**
- ✅ Backups tested monthly
- ✅ Step-by-step runbooks
- ✅ Proactive alerts
- ✅ Measured recovery times
- 😌 **Confidence during disaster**

**ROI:**
- **Time Saved:** Hours/days during disaster (clear procedures vs figuring it out)
- **Risk Reduced:** Early detection of backup failures (48h vs weeks)
- **Confidence Gained:** Proven monthly that backups work
- **Documentation:** Transferable knowledge (not tribal)

---

## Next Steps

1. **Review this roadmap** - Understand approach, ask questions
2. **Execute Phase 1** in CLI - Get restore testing working
3. **Execute Phase 2** in CLI - Add monitoring
4. **Execute Phase 3** in CLI - Write runbooks
5. **Execute Phase 4** in CLI - Test everything
6. **Celebrate** 🎉 - You have production-grade DR!

---

**Status:** Ready for CLI execution on fedora-htpc
**Questions:** Review plan, clarify before implementation
**Approval:** Proceed when ready

**This plan transforms "hope" into "proof" for your backup strategy.**
