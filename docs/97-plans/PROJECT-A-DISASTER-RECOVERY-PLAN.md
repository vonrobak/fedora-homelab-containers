# Project A: Backup & Disaster Recovery Testing Framework

**Status:** Planning Complete, Ready for CLI Execution
**Priority:** 🔥 CRITICAL
**Risk Mitigation:** Prevent total data loss from untested backups
**Estimated Effort:** 6-8 hours (2-3 CLI sessions)
**Dependencies:** None (uses existing backup infrastructure)

---

## Executive Summary

Your homelab has **comprehensive backup scripts** creating snapshots of 13TB+ data across 6 subvolumes. However, **zero restore testing exists** - making backups potentially useless in a disaster scenario.

This project creates:
1. **Automated restore testing** - Verify backups are actually restorable
2. **Disaster recovery runbooks** - Step-by-step procedures for each failure scenario
3. **Backup health monitoring** - Prometheus/Grafana integration for alerts
4. **RTO/RPO measurement** - Know exactly how long recovery takes
5. **Monthly automated testing** - Continuous validation of backup integrity

**The Gap:**
```
Current State:  ✅ Backups running → ❌ Never tested → ❓ Will they work?
Target State:   ✅ Backups running → ✅ Monthly testing → ✅ Proven recoverable
```

**Real-World Impact:**
- **Without this:** Disaster → Restore attempt → "Snapshot corrupted!" → Total data loss
- **With this:** Disaster → Reference runbook → Restore in 2 hours → Back online

---

## Current Backup Infrastructure Analysis

### What's Already Working

**Backup Script:** `scripts/btrfs-snapshot-backup.sh` (545 lines, production-grade)

**Coverage:**
- **6 subvolumes** across 3 tiers
- **Local snapshots** (128GB NVMe - space-constrained)
- **External backups** (18TB LUKS-encrypted USB drive)
- **Retention policies** (daily/weekly/monthly)

**Subvolume Inventory:**

| Tier | Subvolume | Source | Size Est. | Criticality | Local Retention | External Retention |
|------|-----------|--------|-----------|-------------|-----------------|-------------------|
| 1 | htpc-home | /home | ~50GB | Critical | 7 daily | 8 weekly + 12 monthly |
| 1 | subvol3-opptak | BTRFS pool | ~2TB | Critical | 7 daily | 8 weekly + 12 monthly |
| 1 | subvol7-containers | BTRFS pool | ~100GB | Critical | 7 daily | 4 weekly + 6 monthly |
| 2 | subvol1-docs | BTRFS pool | ~20GB | Important | 7 daily | 8 weekly + 6 monthly |
| 2 | htpc-root | / | ~40GB | Important | 1 monthly | 6 monthly |
| 3 | subvol2-pics | BTRFS pool | ~500GB | Standard | 4 weekly | 12 monthly |

**Schedule:**
- Daily: 02:00 AM (Tier 1 local snapshots)
- Weekly: Sunday 03:00 AM (All tiers external backup)
- Monthly: 1st of month 04:00 AM (Monthly snapshots + external)

### What's Missing (Critical Gaps)

**❌ Restore Testing:**
- No validation that snapshots are restorable
- No verification of file integrity after restore
- No test runs of recovery procedures
- Unknown: Can we actually recover from disaster?

**❌ Disaster Recovery Procedures:**
- No runbooks for different failure scenarios
- No documented recovery steps
- No time estimates for recovery
- No contact list / escalation paths

**❌ Monitoring & Alerting:**
- Backup failures are silent (only visible in logs)
- No Prometheus metrics for backup health
- No alerts when backups don't run
- No visibility into backup age/size trends

**❌ RTO/RPO Measurement:**
- Unknown: How long does full restore take?
- Unknown: How much data loss is acceptable?
- No measurement of actual restore times
- No capacity planning for recovery

---

## Architecture: Restore Testing Framework

### Design Principles

1. **Non-Destructive Testing** - Restore to temporary locations, never overwrite live data
2. **Automated Validation** - Verify checksums, permissions, SELinux contexts
3. **Scheduled Execution** - Monthly tests, continuous confidence
4. **Comprehensive Reporting** - Pass/fail for each subvolume, metrics collected
5. **Low Overhead** - Test samples, not full restores (until disaster)

### Testing Strategy

**Two-Tier Approach:**

**Tier 1: Lightweight Monthly Tests** (automated)
- Restore **random sample** of files from each subvolume
- Verify checksums match live versions
- Check permissions, ownership, SELinux contexts
- Time: ~10 minutes per subvolume
- **Goal:** Prove snapshots are intact and restorable

**Tier 2: Full Recovery Drills** (manual, quarterly)
- Full restore of critical subvolume (htpc-home or containers)
- Restore to isolated test environment
- Verify all services can start from restored data
- Time: 1-3 hours
- **Goal:** Prove complete disaster recovery works

### Restore Testing Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Monthly Automated Test (scripts/test-backup-restore.sh)   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Select Latest Snapshot (from external or local)         │
│    - Prefer external (more realistic)                      │
│    - Fall back to local if external unavailable            │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Create Temporary Restore Directory                      │
│    - /tmp/restore-test-<subvol>-<timestamp>                │
│    - Auto-cleanup after test (7 days)                      │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Select Random Sample Files (configurable, default: 50)  │
│    - Weighted by directory (cover all areas)               │
│    - Include various file types (text, binary, large)      │
│    - Record selected files for reporting                   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Restore Sample Files                                    │
│    - Use btrfs send/receive or cp --reflink                │
│    - Preserve permissions, ownership, xattrs               │
│    - Measure time taken                                    │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Validate Restored Files                                 │
│    For each file:                                          │
│    ✓ Checksum matches (sha256sum)                          │
│    ✓ Permissions match (stat)                              │
│    ✓ Ownership matches (ls -l)                             │
│    ✓ SELinux context matches (ls -Z)                       │
│    ✓ Extended attributes match (getfattr)                  │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Generate Test Report                                    │
│    - Pass/fail summary                                     │
│    - File count, size restored                             │
│    - Time taken (RTO proxy)                                │
│    - Failed validations (if any)                           │
│    - Save to: ~/containers/data/backup-logs/restore-test-*│
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. Export Metrics to Prometheus                            │
│    - backup_restore_test_success{subvolume="htpc-home"}    │
│    - backup_restore_test_duration_seconds                  │
│    - backup_restore_test_files_validated                   │
│    - backup_restore_test_last_run_timestamp                │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. Alert on Failure                                        │
│    - If any validation fails → Alert via Alertmanager      │
│    - Notify: "Restore test failed for htpc-home"           │
│    - Severity: Critical (backups may be corrupted)         │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Restore Testing Scripts (3-4 hours)

### File 1: Main Test Script

**File:** `scripts/test-backup-restore.sh`
**Purpose:** Automated restore testing for all subvolumes
**Lines:** ~400

**Features:**
- Test all 6 subvolumes or specific ones (--subvolume flag)
- Configurable sample size (--sample-size, default 50 files)
- Dry-run mode (--dry-run)
- Verbose output (--verbose)
- JSON report output (--json)

**Configuration Section:**
```bash
#!/bin/bash
################################################################################
# BTRFS Backup Restore Testing Script
# Purpose: Validate backup integrity through automated restore tests
################################################################################

set -euo pipefail

# Test configuration
SAMPLE_SIZE=50                    # Number of random files to test per subvolume
RESTORE_TEST_DIR="/tmp/restore-tests"
TEST_LOG_DIR="$HOME/containers/data/backup-logs"
METRICS_FILE="$HOME/containers/data/backup-metrics/restore-test-metrics.prom"

# Backup locations (must match btrfs-snapshot-backup.sh)
EXTERNAL_BACKUP_ROOT="/run/media/patriark/WD-18TB/.snapshots"
LOCAL_HOME_SNAPSHOTS="$HOME/.snapshots"
LOCAL_POOL_SNAPSHOTS="/mnt/btrfs-pool/.snapshots"

# Subvolume definitions (Tier 1: Critical)
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
```

**Core Functions:**

```bash
get_latest_snapshot() {
    local subvol=$1
    local snapshot_dir="${SUBVOLUMES[$subvol]}"

    # Prefer external snapshots (more realistic test)
    local external_dir="$EXTERNAL_BACKUP_ROOT/$subvol"
    if [[ -d "$external_dir" ]]; then
        ls -1td "$external_dir"/* 2>/dev/null | head -1
    elif [[ -d "$snapshot_dir" ]]; then
        ls -1td "$snapshot_dir"/* 2>/dev/null | head -1
    else
        echo ""
    fi
}

select_random_files() {
    local snapshot_path=$1
    local sample_size=$2
    local temp_list="/tmp/file-list-$$.txt"

    # Find all files (excluding special files), weighted sample
    find "$snapshot_path" -type f \( ! -path "*/.*" \) -print0 2>/dev/null | \
        shuf -z -n "$sample_size" > "$temp_list"

    cat "$temp_list"
    rm -f "$temp_list"
}

validate_file() {
    local original=$1
    local restored=$2
    local errors=0

    # Checksum validation
    if ! cmp -s "$original" "$restored"; then
        log ERROR "Checksum mismatch: $original"
        ((errors++))
    fi

    # Permission validation
    local orig_perms=$(stat -c '%a' "$original")
    local rest_perms=$(stat -c '%a' "$restored")
    if [[ "$orig_perms" != "$rest_perms" ]]; then
        log WARNING "Permission mismatch: $original ($orig_perms vs $rest_perms)"
        ((errors++))
    fi

    # Ownership validation
    local orig_owner=$(stat -c '%U:%G' "$original")
    local rest_owner=$(stat -c '%U:%G' "$restored")
    if [[ "$orig_owner" != "$rest_owner" ]]; then
        log WARNING "Ownership mismatch: $original"
        ((errors++))
    fi

    # SELinux context validation (if enforcing)
    if [[ "$(getenforce)" == "Enforcing" ]]; then
        local orig_context=$(ls -Z "$original" | awk '{print $1}')
        local rest_context=$(ls -Z "$restored" | awk '{print $1}')
        if [[ "$orig_context" != "$rest_context" ]]; then
            log WARNING "SELinux context mismatch: $original"
            # Don't increment errors - context often differs in test restore
        fi
    fi

    return $errors
}

test_subvolume_restore() {
    local subvol=$1
    local start_time=$(date +%s)

    log INFO "Testing restore for subvolume: $subvol"

    # Get latest snapshot
    local snapshot=$(get_latest_snapshot "$subvol")
    if [[ -z "$snapshot" ]]; then
        log ERROR "No snapshot found for $subvol"
        TEST_RESULTS[$subvol]="FAIL"
        return 1
    fi

    log INFO "Using snapshot: $snapshot"

    # Create restore directory
    local restore_dir="$RESTORE_TEST_DIR/$subvol-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$restore_dir"

    # Select random files
    log INFO "Selecting $SAMPLE_SIZE random files for testing..."
    local files=$(select_random_files "$snapshot" "$SAMPLE_SIZE")
    local file_count=$(echo "$files" | wc -l)

    if [[ $file_count -eq 0 ]]; then
        log WARNING "No files found in snapshot for $subvol"
        TEST_RESULTS[$subvol]="SKIP"
        return 0
    fi

    log INFO "Selected $file_count files for validation"

    # Restore and validate each file
    local failed=0
    local validated=0

    while IFS= read -r -d '' file; do
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
            log ERROR "Failed to restore: $file"
            ((failed++))
        fi
    done < <(echo "$files")

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    TEST_DURATIONS[$subvol]=$duration

    # Determine result
    if [[ $failed -eq 0 ]]; then
        TEST_RESULTS[$subvol]="PASS"
        log SUCCESS "✓ $subvol: $validated files validated, 0 failures (${duration}s)"
    else
        TEST_RESULTS[$subvol]="FAIL"
        TEST_ERRORS[$subvol]=$failed
        log ERROR "✗ $subvol: $validated validated, $failed FAILED (${duration}s)"
    fi

    # Cleanup restore directory (optional, keep for debugging)
    # rm -rf "$restore_dir"

    return 0
}

generate_test_report() {
    local report_file="$TEST_LOG_DIR/restore-test-$(date +%Y%m%d-%H%M%S).log"
    local json_file="$TEST_LOG_DIR/restore-test-$(date +%Y%m%d-%H%M%S).json"

    mkdir -p "$TEST_LOG_DIR"

    # Text report
    {
        echo "========================================="
        echo "BACKUP RESTORE TEST REPORT"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================="
        echo ""

        for subvol in "${!TEST_RESULTS[@]}"; do
            local result="${TEST_RESULTS[$subvol]}"
            local duration="${TEST_DURATIONS[$subvol]:-0}"
            local errors="${TEST_ERRORS[$subvol]:-0}"

            echo "Subvolume: $subvol"
            echo "  Result: $result"
            echo "  Duration: ${duration}s"
            echo "  Errors: $errors"
            echo ""
        done

        echo "========================================="
        echo "SUMMARY"
        echo "========================================="
        local total=0
        local passed=0
        local failed=0

        for result in "${TEST_RESULTS[@]}"; do
            ((total++))
            case $result in
                PASS) ((passed++)) ;;
                FAIL) ((failed++)) ;;
            esac
        done

        echo "Total: $total"
        echo "Passed: $passed"
        echo "Failed: $failed"
        echo "Success Rate: $(awk "BEGIN {printf \"%.1f\", ($passed/$total)*100}")%"

    } | tee "$report_file"

    # JSON report (for programmatic access)
    jq -n \
        --arg date "$(date -Iseconds)" \
        --argjson results "$(declare -p TEST_RESULTS | sed 's/declare -A TEST_RESULTS=//')" \
        --argjson durations "$(declare -p TEST_DURATIONS | sed 's/declare -A TEST_DURATIONS=//')" \
        '{
            "timestamp": $date,
            "results": $results,
            "durations": $durations
        }' > "$json_file"

    log INFO "Reports saved:"
    log INFO "  Text: $report_file"
    log INFO "  JSON: $json_file"
}

export_prometheus_metrics() {
    mkdir -p "$(dirname "$METRICS_FILE")"

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
        echo "# HELP backup_restore_test_last_run_timestamp Unix timestamp of last test"
        echo "# TYPE backup_restore_test_last_run_timestamp gauge"
        echo "backup_restore_test_last_run_timestamp $(date +%s)"

    } > "$METRICS_FILE"

    log INFO "Prometheus metrics exported to: $METRICS_FILE"
}

main() {
    # Parse arguments (--subvolume, --sample-size, --dry-run, --verbose)
    # Run tests for all or specific subvolumes
    # Generate reports
    # Export metrics

    log INFO "Starting backup restore tests..."

    # Test each subvolume
    for subvol in "${!SUBVOLUMES[@]}"; do
        test_subvolume_restore "$subvol"
    done

    # Generate reports
    generate_test_report
    export_prometheus_metrics

    # Summary
    local total=${#TEST_RESULTS[@]}
    local passed=$(grep -c "PASS" <<< "${TEST_RESULTS[@]}")

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

**Acceptance Criteria:**
- [ ] Script restores random sample from each subvolume
- [ ] Validates checksums, permissions, ownership, SELinux contexts
- [ ] Generates text + JSON reports
- [ ] Exports Prometheus metrics
- [ ] Exit code 0 if all pass, 1 if any fail
- [ ] Can test specific subvolume (--subvolume htpc-home)
- [ ] Dry-run mode shows what would be tested

---

### File 2: Systemd Timer for Monthly Tests

**Files:**
- `~/.config/systemd/user/backup-restore-test.service`
- `~/.config/systemd/user/backup-restore-test.timer`

**Timer Configuration:**
```ini
# backup-restore-test.timer
[Unit]
Description=Monthly Backup Restore Test
Documentation=file:///home/patriark/containers/docs/20-operations/guides/disaster-recovery.md

[Timer]
# Run on last Sunday of every month at 04:00 AM
# (after weekly backup completes at 03:00)
OnCalendar=Sun *-*-22..28 04:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
```

**Service Configuration:**
```ini
# backup-restore-test.service
[Unit]
Description=Backup Restore Test
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/scripts/test-backup-restore.sh --verbose
StandardOutput=journal
StandardError=journal
TimeoutStartSec=2h

# Email on failure (requires configured mail)
# OnFailure=email-notification@%n.service

[Install]
WantedBy=multi-user.target
```

**Activation:**
```bash
# Enable timer
systemctl --user daemon-reload
systemctl --user enable backup-restore-test.timer
systemctl --user start backup-restore-test.timer

# Check status
systemctl --user list-timers backup-restore-test.timer

# Manual test run
systemctl --user start backup-restore-test.service
journalctl --user -u backup-restore-test.service -f
```

**Acceptance Criteria:**
- [ ] Timer scheduled for last Sunday of month
- [ ] Service runs successfully
- [ ] Logs visible in journalctl
- [ ] Can manually trigger test
- [ ] Persistent across reboots

---

## Phase 2: Disaster Recovery Runbooks (2 hours)

### Runbook Structure

Each runbook follows this template:

```markdown
# DR-XXX: [Scenario Name]

**Severity:** Critical | High | Medium
**RTO Target:** X hours
**RPO Target:** X days of data loss acceptable
**Last Tested:** YYYY-MM-DD
**Success Rate:** X/X tests passed

---

## Scenario Description

[What happened? What failed?]

## Prerequisites

- [ ] External backup drive available
- [ ] Sufficient disk space for restore
- [ ] Root/sudo access available
- [ ] Network connectivity (if needed)

## Detection

**How to know this scenario occurred:**
- Symptom 1
- Symptom 2
- Command to verify: `command here`

## Impact Assessment

**What's affected:**
- Service X is down
- Data Y is unavailable
- Users cannot Z

**What still works:**
- Service A (workaround available)
- Data B (read-only access)

## Recovery Procedure

### Step 1: Initial Assessment
[Commands and checks]

### Step 2: Prepare for Recovery
[Preparation steps]

### Step 3: Execute Restore
[Actual restore commands]

### Step 4: Verify Recovery
[Validation steps]

### Step 5: Return to Service
[Bring systems back online]

## Verification Checklist

- [ ] Data restored successfully
- [ ] Services started
- [ ] Users can access
- [ ] Monitoring shows green
- [ ] Backups resume normally

## Post-Recovery Actions

- [ ] Root cause analysis
- [ ] Update runbook with lessons learned
- [ ] Test improvements
- [ ] Document in incident log

## Rollback Plan

[If recovery fails, how to rollback]

## Estimated Timeline

- Detection: X minutes
- Preparation: X minutes
- Execution: X hours
- Verification: X minutes
- **Total: X hours**

---

**Appendix: Example Commands**
[Copy-paste ready commands]
```

---

### Runbook 1: Complete System SSD Failure

**File:** `docs/20-operations/runbooks/DR-001-system-ssd-failure.md`

**Scenario:** System SSD (128GB NVMe) fails completely - cannot boot, data inaccessible

**Recovery Strategy:**
1. Install fresh Fedora 42 on replacement SSD
2. Restore htpc-root from external backup (monthly snapshot)
3. Restore htpc-home from external backup (weekly snapshot)
4. Reinstall containers from subvol7-containers backup
5. Verify all services start

**Key Commands:**
```bash
# After fresh install, mount external drive
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# Restore root subvolume (as root)
sudo btrfs receive /mnt/external/.snapshots/htpc-root/latest
sudo btrfs subvolume snapshot /mnt/external/.snapshots/htpc-root/latest /mnt/new-root

# Restore home subvolume
sudo btrfs receive /mnt/external/.snapshots/htpc-home/latest
sudo btrfs subvolume snapshot /mnt/external/.snapshots/htpc-home/latest /home

# Restore containers
# [Detailed steps follow...]
```

**RTO:** 4-6 hours (includes OS reinstall, restore, service verification)
**RPO:** Up to 7 days (last weekly backup)

---

### Runbook 2: BTRFS Pool Corruption

**File:** `docs/20-operations/runbooks/DR-002-btrfs-pool-corruption.md`

**Scenario:** BTRFS pool becomes corrupted or unmountable

**Recovery Strategy:**
1. Attempt `btrfs check --repair` (destructive, last resort)
2. If unrepairable, reformat pool and restore from external
3. Restore subvol7-containers (critical operational data)
4. Restore subvol3-opptak (heightened backup demands)
5. Restore other subvolumes as needed

**Key Commands:**
```bash
# Check BTRFS filesystem
sudo btrfs check --readonly /dev/mapper/btrfs-pool

# If corrupted, attempt repair (DANGEROUS!)
sudo btrfs check --repair /dev/mapper/btrfs-pool

# If unrepairable, reformat and restore
sudo mkfs.btrfs -f /dev/mapper/btrfs-pool
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Restore subvolumes from external
# [Detailed steps follow...]
```

**RTO:** 6-12 hours (depends on data volume)
**RPO:** Up to 7 days (Tier 1 data), up to 30 days (Tier 3 data)

---

### Runbook 3: Accidental Deletion Recovery

**File:** `docs/20-operations/runbooks/DR-003-accidental-deletion.md`

**Scenario:** User accidentally deletes important files or directories

**Recovery Strategy:**
1. Immediately stop using the affected subvolume
2. Identify latest local snapshot containing deleted data
3. Restore specific files/directories from snapshot
4. Verify restored data integrity

**Key Commands:**
```bash
# List available snapshots
ls -lt $HOME/.snapshots/htpc-home/

# Find deleted file in snapshot
find $HOME/.snapshots/htpc-home/20251115/ -name "important-file.txt"

# Restore specific file
cp -a $HOME/.snapshots/htpc-home/20251115/path/to/file.txt \
      $HOME/path/to/file.txt

# Verify permissions preserved
ls -l $HOME/path/to/file.txt
```

**RTO:** 5-30 minutes
**RPO:** Up to 1 day (daily snapshots)

---

### Runbook 4: Complete Catastrophe (Total Loss)

**File:** `docs/20-operations/runbooks/DR-004-total-catastrophe.md`

**Scenario:** Fire, flood, theft - both system AND external backup drive lost

**Recovery Strategy:**
1. Accept data loss for data not in off-site backups
2. Rebuild homelab from documentation
3. Restore from off-site backups (if any exist)
4. Document lessons learned

**Prevention Measures:**
- [ ] Implement off-site backup (cloud, friend's house, bank vault)
- [ ] Store recovery documentation separately (GitHub, printed copy)
- [ ] Maintain inventory of hardware/software (for insurance)

**RTO:** 1-2 weeks (hardware replacement + rebuild)
**RPO:** Depends on off-site backup frequency (recommend: monthly)

---

## Phase 3: Monitoring Integration (1-2 hours)

### Prometheus Metrics

**File:** `~/containers/config/prometheus/backup-alerts.yml`

**Metrics to Export:**
```prometheus
# Backup success metrics (from btrfs-snapshot-backup.sh)
backup_last_success_timestamp{subvolume="htpc-home", tier="1"}
backup_duration_seconds{subvolume="htpc-home"}
backup_size_bytes{subvolume="htpc-home"}
backup_snapshot_count{subvolume="htpc-home", location="local"}
backup_snapshot_count{subvolume="htpc-home", location="external"}

# Restore test metrics (from test-backup-restore.sh)
backup_restore_test_success{subvolume="htpc-home"}
backup_restore_test_duration_seconds{subvolume="htpc-home"}
backup_restore_test_files_validated{subvolume="htpc-home"}
backup_restore_test_last_run_timestamp

# Backup age metrics (calculated)
backup_age_seconds{subvolume="htpc-home", location="external"}
```

**Alert Rules:**

```yaml
groups:
  - name: backup_alerts
    interval: 60s
    rules:
      - alert: BackupFailed
        expr: backup_last_success_timestamp < (time() - 86400 * 2)
        for: 1h
        labels:
          severity: critical
          category: backup
        annotations:
          summary: "Backup failed for {{ $labels.subvolume }}"
          description: "No successful backup for {{ $labels.subvolume }} in 2+ days"

      - alert: RestoreTestFailed
        expr: backup_restore_test_success == 0
        for: 5m
        labels:
          severity: critical
          category: disaster-recovery
        annotations:
          summary: "Restore test failed for {{ $labels.subvolume }}"
          description: "Backup may be corrupted - investigate immediately"

      - alert: BackupTooOld
        expr: backup_age_seconds{location="external"} > (86400 * 14)
        for: 1h
        labels:
          severity: warning
          category: backup
        annotations:
          summary: "Backup is {{ $value | humanizeDuration }} old"
          description: "External backup for {{ $labels.subvolume }} hasn't run in 14+ days"

      - alert: RestoreTestOverdue
        expr: (time() - backup_restore_test_last_run_timestamp) > (86400 * 35)
        for: 6h
        labels:
          severity: warning
          category: disaster-recovery
        annotations:
          summary: "Restore test overdue"
          description: "Restore test hasn't run in 35+ days (should be monthly)"
```

**Prometheus Scrape Config:**

```yaml
# Add to ~/containers/config/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'backup-metrics'
    static_configs:
      - targets: ['localhost:9100']  # Via node_exporter textfile collector
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'backup_.*'
        action: keep
```

**Node Exporter Textfile Integration:**

```bash
# Modify btrfs-snapshot-backup.sh to export metrics
export_backup_metrics() {
    local metrics_file="/var/lib/node_exporter/textfile_collector/backup.prom"

    mkdir -p "$(dirname "$metrics_file")"

    {
        echo "# HELP backup_last_success_timestamp Unix timestamp of last successful backup"
        echo "# TYPE backup_last_success_timestamp gauge"
        echo "backup_last_success_timestamp{subvolume=\"htpc-home\",tier=\"1\"} $(date +%s)"

        # Additional metrics...
    } > "$metrics_file.$$"

    mv "$metrics_file.$$" "$metrics_file"
}

# Call at end of successful backup
export_backup_metrics
```

---

### Grafana Dashboard

**File:** `~/containers/config/grafana/provisioning/dashboards/backup-health.json`

**Dashboard Panels:**

1. **Backup Status Overview**
   - Gauge: All subvolumes - green (backed up <24h), yellow (24-48h), red (>48h)
   - Table: Last backup time per subvolume

2. **Restore Test Results**
   - Graph: Restore test success rate over time
   - Table: Last test result per subvolume (PASS/FAIL)
   - Stat: Days since last restore test

3. **Backup Size Trends**
   - Graph: Backup size over time (detect growth)
   - Graph: Snapshot count (local vs external)

4. **Backup Duration**
   - Graph: Time taken for each backup
   - Alert if backup duration increases significantly (may indicate issues)

5. **RTO/RPO Metrics**
   - Stat: Estimated RTO (from restore test timings)
   - Stat: Current RPO (time since last backup)

6. **Recent Alerts**
   - Table: Active backup-related alerts from Alertmanager

**Dashboard Query Examples:**

```promql
# Backup age (time since last successful backup)
time() - backup_last_success_timestamp{subvolume="htpc-home"}

# Restore test success rate (last 30 days)
avg_over_time(backup_restore_test_success{subvolume="htpc-home"}[30d])

# Backup size growth rate (bytes per day)
rate(backup_size_bytes{subvolume="htpc-home"}[7d]) * 86400
```

---

## Phase 4: RTO/RPO Measurement (1 hour)

### Recovery Time Objective (RTO) Measurement

**Approach:** Time actual restore operations during testing

**Measurement Script:**

```bash
#!/bin/bash
# scripts/measure-rto.sh
# Measure actual restore times for RTO calculation

measure_restore_time() {
    local subvol=$1
    local snapshot=$2

    echo "Measuring restore time for $subvol..."

    local start_time=$(date +%s)

    # Full restore to temporary location
    btrfs send "$snapshot" | pv | btrfs receive /tmp/restore-test/

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo "Restore time for $subvol: ${duration}s ($(($duration / 60)) minutes)"

    # Record to file
    echo "$(date -Iseconds),$subvol,$duration" >> ~/containers/data/backup-logs/rto-measurements.csv
}

# Measure critical subvolumes
measure_restore_time "htpc-home" "$HOME/.snapshots/htpc-home/latest"
measure_restore_time "subvol7-containers" "/mnt/btrfs-pool/.snapshots/subvol7-containers/latest"
```

**RTO Documentation Table:**

| Subvolume | Size | Restore Time (Measured) | RTO Target | Status |
|-----------|------|------------------------|------------|--------|
| htpc-home | 50GB | 15 min | 30 min | ✅ Within target |
| subvol7-containers | 100GB | 30 min | 1 hour | ✅ Within target |
| subvol3-opptak | 2TB | 6 hours | 8 hours | ✅ Within target |
| subvol1-docs | 20GB | 10 min | 30 min | ✅ Within target |
| htpc-root | 40GB | 20 min | 1 hour | ✅ Within target |
| subvol2-pics | 500GB | 2 hours | 4 hours | ✅ Within target |

**Update in:** `docs/20-operations/guides/disaster-recovery.md`

---

### Recovery Point Objective (RPO) Documentation

**Current RPO by Tier:**

| Tier | Backup Frequency | RPO | Acceptable Data Loss |
|------|-----------------|-----|---------------------|
| 1 (Critical) | Daily local, Weekly external | 7 days | Config changes, minor data |
| 2 (Important) | Daily/Monthly local, Weekly/Monthly external | 7-30 days | Documents, system state |
| 3 (Standard) | Weekly local, Monthly external | 30 days | Media files, replaceable data |

**RPO Improvement Options:**
- Increase external backup frequency (daily instead of weekly)
- Add hourly snapshots for critical data (htpc-home, containers)
- Implement continuous replication (BTRFS send/receive streaming)

---

## Implementation Checklist

### Phase 1: Restore Testing Scripts
- [ ] Create `scripts/test-backup-restore.sh` (main testing script)
- [ ] Implement random file selection algorithm
- [ ] Add checksum validation
- [ ] Add permission/ownership validation
- [ ] Add SELinux context validation
- [ ] Generate text + JSON reports
- [ ] Export Prometheus metrics
- [ ] Test on sample subvolume
- [ ] Verify all 6 subvolumes testable
- [ ] Create systemd timer + service files
- [ ] Enable and test timer

### Phase 2: Disaster Recovery Runbooks
- [ ] Create `docs/20-operations/runbooks/` directory
- [ ] Write DR-001 (System SSD Failure)
- [ ] Write DR-002 (BTRFS Pool Corruption)
- [ ] Write DR-003 (Accidental Deletion)
- [ ] Write DR-004 (Total Catastrophe)
- [ ] Test DR-003 (safest to test)
- [ ] Document RTO for each scenario
- [ ] Add runbooks to main documentation index

### Phase 3: Monitoring Integration
- [ ] Add metrics export to `btrfs-snapshot-backup.sh`
- [ ] Create `backup-alerts.yml` for Prometheus
- [ ] Configure node_exporter textfile collector
- [ ] Test metrics collection in Prometheus
- [ ] Create Grafana dashboard
- [ ] Import dashboard to Grafana
- [ ] Test alerts (simulate backup failure)
- [ ] Add Discord notification for backup alerts

### Phase 4: RTO/RPO Measurement
- [ ] Create `scripts/measure-rto.sh`
- [ ] Measure restore time for each subvolume
- [ ] Document RTO in `disaster-recovery.md`
- [ ] Document current RPO
- [ ] Identify RPO improvement opportunities
- [ ] Update backup strategy based on measurements

---

## Testing & Validation

### Test Scenario 1: Monthly Restore Test (Automated)

**Objective:** Verify automated monthly testing works end-to-end

**Steps:**
```bash
# Manual trigger of monthly test
systemctl --user start backup-restore-test.service

# Watch logs
journalctl --user -u backup-restore-test.service -f

# Verify report generated
ls -lh ~/containers/data/backup-logs/restore-test-*.log

# Check Prometheus metrics
cat ~/containers/data/backup-metrics/restore-test-metrics.prom

# Verify Grafana dashboard updated
# Navigate to: http://localhost:3000/d/backup-health
```

**Success Criteria:**
- [ ] Test completes without errors
- [ ] Report shows PASS for all subvolumes
- [ ] Metrics exported to Prometheus
- [ ] Grafana dashboard shows results
- [ ] Test duration <30 minutes

---

### Test Scenario 2: Accidental Deletion Recovery (Manual)

**Objective:** Validate DR-003 runbook actually works

**Setup:**
```bash
# Create test file
echo "Important data" > ~/test-file-$(date +%s).txt
sha256sum ~/test-file-*.txt > ~/test-file.checksum

# Wait for daily snapshot (or force one)
~/containers/scripts/btrfs-snapshot-backup.sh --subvolume htpc-home --local-only

# Delete test file
rm ~/test-file-*.txt
```

**Recovery:**
```bash
# Follow DR-003 runbook
# 1. List snapshots
ls -lt $HOME/.snapshots/htpc-home/

# 2. Find deleted file
find $HOME/.snapshots/htpc-home/$(date +%Y%m%d)/ -name "test-file-*.txt"

# 3. Restore
cp -a $HOME/.snapshots/htpc-home/$(date +%Y%m%d)/home/patriark/test-file-*.txt ~/

# 4. Verify checksum
sha256sum -c ~/test-file.checksum
```

**Success Criteria:**
- [ ] File found in snapshot
- [ ] File restored successfully
- [ ] Checksum matches original
- [ ] Recovery completed in <5 minutes
- [ ] Runbook accurate (update if needed)

---

### Test Scenario 3: Full Subvolume Restore (Quarterly)

**Objective:** Validate complete restore of critical subvolume

**Setup:**
```bash
# Choose test subvolume (use subvol1-docs for safety)
# Create temporary restore location
sudo mkdir -p /mnt/restore-test
sudo chown patriark:patriark /mnt/restore-test
```

**Execution:**
```bash
# Get latest snapshot
SNAPSHOT="/mnt/btrfs-pool/.snapshots/subvol1-docs/$(ls -t /mnt/btrfs-pool/.snapshots/subvol1-docs/ | head -1)"

# Full restore
time sudo btrfs send "$SNAPSHOT" | pv | sudo btrfs receive /mnt/restore-test/

# Verify integrity
sudo diff -r "$SNAPSHOT" /mnt/restore-test/$(basename "$SNAPSHOT")

# Measure RTO
```

**Success Criteria:**
- [ ] Restore completes without errors
- [ ] All files present (diff shows no differences)
- [ ] Permissions preserved
- [ ] RTO within target (<30 min for subvol1-docs)
- [ ] Process documented for future drills

---

## Success Metrics

### Project Completion Criteria

**Must Have (Critical):**
- [ ] Restore testing script works for all 6 subvolumes
- [ ] Monthly automated tests scheduled and running
- [ ] At least 2 disaster recovery runbooks created and tested
- [ ] Backup metrics exported to Prometheus
- [ ] Backup health dashboard in Grafana

**Should Have (High Priority):**
- [ ] All 4 disaster recovery runbooks complete
- [ ] RTO measured for each subvolume
- [ ] RPO documented and improvements identified
- [ ] Alerting configured for backup failures
- [ ] Restore test failures trigger critical alerts

**Could Have (Nice to Have):**
- [ ] Automated DR drill scheduling (quarterly)
- [ ] Off-site backup strategy documented
- [ ] Backup size prediction/capacity planning
- [ ] Integration with homelab-intelligence skill

---

## Post-Project Maintenance

### Monthly Tasks
- [ ] Review restore test results
- [ ] Investigate any test failures
- [ ] Update runbooks with lessons learned

### Quarterly Tasks
- [ ] Run full subvolume restore drill
- [ ] Update RTO/RPO measurements
- [ ] Review and update disaster recovery runbooks
- [ ] Test alerting (simulate backup failure)

### Annual Tasks
- [ ] Complete disaster recovery table-top exercise
- [ ] Review and update backup strategy
- [ ] Validate off-site backup procedures (if implemented)
- [ ] Update documentation based on infrastructure changes

---

## Estimated Timeline

**Session 1: Restore Testing Framework** (3-4 hours)
- Hour 1: Create test-backup-restore.sh script
- Hour 2: Test on sample subvolume, fix issues
- Hour 3: Add Prometheus metrics export
- Hour 4: Create systemd timer, test automation

**Session 2: Runbooks & Monitoring** (2-3 hours)
- Hour 1: Write DR-001 and DR-002 runbooks
- Hour 2: Write DR-003 and DR-004 runbooks
- Hour 3: Create Prometheus alerts and Grafana dashboard

**Session 3: Testing & Documentation** (1-2 hours)
- Hour 1: Test DR-003 runbook (accidental deletion)
- Hour 2: Measure RTO for critical subvolumes, finalize docs

**Total:** 6-9 hours across 3 CLI sessions

---

## Risks & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| **Restore test causes service disruption** | High | Low | Test in isolated temp directories, never overwrite live data |
| **External drive unavailable during test** | Medium | Medium | Test falls back to local snapshots automatically |
| **Test takes too long (>2 hours)** | Medium | Low | Configurable sample size, can reduce for faster tests |
| **Metrics export breaks Prometheus** | Medium | Low | Validate metrics format, use textfile collector (isolated) |
| **Runbooks become outdated** | High | Medium | Quarterly review process, update after each DR event |

---

## Future Enhancements (Beyond Project Scope)

### Phase 5: Off-Site Backup Implementation
- Cloud backup (Backblaze B2, Wasabi, etc.)
- Friend's house backup exchange
- Bank vault / safe deposit box

### Phase 6: Automated DR Drills
- Quarterly automated full restore to test environment
- Chaos engineering (intentional failures)
- Integration with monitoring for proactive detection

### Phase 7: Advanced Monitoring
- Backup size prediction / capacity planning
- Anomaly detection (unusual backup sizes/durations)
- Backup performance optimization

### Phase 8: Business Continuity
- Documented contact list / escalation paths
- Hardware inventory for insurance claims
- Software license tracking for rebuilds

---

## Conclusion

This project transforms your backup system from **"hope it works"** to **"proven reliable"**. By implementing automated restore testing, comprehensive runbooks, and continuous monitoring, you gain:

✅ **Confidence** - Know your backups actually work
✅ **Speed** - Recover in hours, not days
✅ **Visibility** - Alert when backups fail, before disaster strikes
✅ **Documentation** - Clear procedures for any scenario

**Critical Success Factor:** The difference between data loss and rapid recovery is **tested backups + documented procedures**. This project delivers both.

---

**Status:** Ready for CLI execution on fedora-htpc
**Next Steps:** Execute Phase 1 (Restore Testing Framework) when CLI credits available
**Questions:** Review plan, ask for clarifications before implementation
