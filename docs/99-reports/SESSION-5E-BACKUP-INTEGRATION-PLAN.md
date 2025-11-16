# Session 5E: Backup Integration & Recovery Automation

**Status**: Ready for Implementation
**Priority**: HIGH
**Estimated Effort**: 6-8 hours across 2-3 CLI sessions
**Dependencies**: Existing backup infrastructure, Session 4 (Context Framework)
**Synergy**: Complements Project A (Disaster Recovery Testing)
**Branch**: TBD (create `feature/backup-integration` during implementation)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Architecture Overview](#architecture-overview)
4. [Core Components](#core-components)
5. [Integration Patterns](#integration-patterns)
6. [Implementation Phases](#implementation-phases)
7. [Recovery Automation](#recovery-automation)
8. [Testing Strategy](#testing-strategy)
9. [Success Metrics](#success-metrics)
10. [Future Enhancements](#future-enhancements)

---

## Executive Summary

**What**: Intelligent backup integration that makes BTRFS snapshots a first-class citizen in deployment workflows, with automated recovery and proactive backup health monitoring.

**Why**:
- Current backups run on schedule, but not integrated with deployments
- No automatic snapshots before risky operations
- Recovery is manual and untested
- Backup health not monitored proactively
- No coordination between backup timing and system activity

**How**:
- Integrate snapshot creation into homelab-deployment skill
- Create backup-aware wrappers for risky operations
- Automate recovery procedures with validation
- Monitor backup health and predict issues
- Optimize backup timing using traffic patterns

**Key Deliverables**:
- `scripts/backup-wrapper.sh` - Snapshot wrapper for any operation (200 lines)
- `scripts/auto-recovery.sh` - Automated rollback from snapshots (300 lines)
- `scripts/backup-health-check.sh` - Validate backup integrity (250 lines)
- `.claude/context/backup-history.json` - Track snapshot/recovery events
- Updated homelab-deployment skill with backup integration
- `docs/20-operations/guides/backup-integration.md` - Usage guide

---

## Problem Statement

### Current State: Scheduled But Isolated

Your backup infrastructure is **functional but disconnected** from workflows:

**What Works**:
- ✅ Automated daily snapshots via `btrfs-snapshot-backup.sh`
- ✅ Tier-based retention (daily, weekly, monthly)
- ✅ 6 subvolumes backed up consistently
- ✅ BTRFS snapshots are fast and space-efficient

**What's Missing**:

**Problem 1: No Pre-Deployment Snapshots**
```
Current Workflow:
1. Deploy Immich (5 services)
2. Something breaks
3. Realize: No snapshot before deployment
4. Manual recovery: Restore from last night's backup (stale data)

Desired Workflow:
1. homelab-deployment: "Creating pre-deployment snapshot..."
2. Deploy Immich
3. If failure: Auto-rollback to pre-deployment snapshot (instant, no data loss)
```

**Problem 2: Untested Recovery**
```
Current State:
- Backups run daily: ✅
- Recovery tested: ❌ Never
- RTO (Recovery Time Objective): Unknown
- RPO (Recovery Point Objective): ~24 hours (last backup)

Risk:
- Backups may not actually work (corrupt snapshots?)
- Don't know how long recovery takes
- Manual recovery is error-prone under pressure
```

**Problem 3: No Backup Health Monitoring**
```
Current State:
- Backup script logs success/failure
- No proactive monitoring of backup health
- No alerts if snapshots fail
- No validation of snapshot integrity

Result:
- Could be backing up corrupt data for weeks without knowing
```

**Problem 4: Suboptimal Backup Timing**
```
Current Timing:
- Daily backups at 2:00 AM (arbitrary choice)

Better Timing:
- Analyze system activity patterns
- Run backups during low-traffic windows
- Avoid backups during maintenance windows
- Coordinate with deployment schedules
```

---

### Desired State: Backup-First Operations

**Vision**: Every risky operation automatically snapshots before, validates after, and can rollback instantly.

**Example Interaction** (Deployment):
```
User: "Deploy Immich using homelab-deployment skill"

homelab-deployment (enhanced):
1. Pre-flight checks (health, dependencies)
2. 🔄 Create pre-deployment snapshot (subvol7-containers)
3. Deploy Immich services (5 containers)
4. Post-deployment validation
   - All services healthy? ✅
   - Snapshot marked as "deployment-immich-2025-11-16-success"

If validation fails:
   - 🚨 Deployment failed, rolling back to snapshot...
   - 🔄 Restore pre-deployment snapshot
   - ✅ System restored to pre-deployment state
   - 📝 Log failure to .claude/context/backup-history.json
```

**Example Interaction** (Recovery):
```
User: "Jellyfin is broken, restore from backup"

auto-recovery.sh:
1. Find latest snapshot for subvol7-containers
2. Show preview: "Restore to 2 hours ago? (y/n)"
3. User confirms
4. Stop affected services
5. Restore snapshot
6. Restart services
7. Validate health
8. ✅ Recovery complete (2 minutes total)
```

---

## Architecture Overview

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    RISKY OPERATION REQUEST                           │
│  Examples:                                                           │
│  - Deploy new service                                                │
│  - Update existing service configuration                            │
│  - Manual system changes                                             │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│           BACKUP WRAPPER (scripts/backup-wrapper.sh)                 │
│                                                                      │
│  Decision: Should we snapshot before this operation?                │
│                                                                      │
│  Criteria:                                                           │
│  - Operation affects persistent data? (YES)                         │
│  - Operation is reversible? (NO → snapshot)                         │
│  - Last snapshot > 1 hour old? (YES → snapshot)                     │
│                                                                      │
│  If YES: Create pre-operation snapshot                              │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              CREATE SNAPSHOT (BTRFS)                                 │
│                                                                      │
│  btrfs subvolume snapshot \                                         │
│    /mnt/btrfs-pool/subvol7-containers \                             │
│    /mnt/btrfs-pool/snapshots/subvol7-containers-pre-deploy-...      │
│                                                                      │
│  Naming: <subvol>-<type>-<operation>-<timestamp>                    │
│  Example: subvol7-containers-pre-deploy-immich-20251116-143000      │
│                                                                      │
│  Metadata: Tag with operation details                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              EXECUTE OPERATION                                       │
│  - Deploy service                                                    │
│  - Update configuration                                              │
│  - Apply changes                                                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              POST-OPERATION VALIDATION                               │
│                                                                      │
│  Check:                                                              │
│  - Services still healthy?                                          │
│  - No new errors in logs?                                           │
│  - System responsive?                                                │
│                                                                      │
│  ┌──────────────────────────────────────┐                           │
│  │ Validation PASSED?                   │                           │
│  │  YES → Mark snapshot as successful   │                           │
│  │        Log to backup-history.json    │                           │
│  │  NO  → Trigger auto-recovery         │                           │
│  └──────────────────────────────────────┘                           │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼ (Validation FAILED)
┌─────────────────────────────────────────────────────────────────────┐
│           AUTO-RECOVERY (scripts/auto-recovery.sh)                   │
│                                                                      │
│  1. Stop affected services                                          │
│  2. Restore pre-operation snapshot                                  │
│  3. Restart services                                                 │
│  4. Re-validate health                                               │
│  5. Log recovery to backup-history.json                             │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│       BACKUP HISTORY (.claude/context/backup-history.json)           │
│                                                                      │
│  {                                                                   │
│    "snapshots": [                                                    │
│      {                                                               │
│        "timestamp": "2025-11-16T14:30:00Z",                         │
│        "subvolume": "subvol7-containers",                           │
│        "type": "pre-deploy",                                        │
│        "operation": "deploy-immich",                                │
│        "snapshot_name": "subvol7-...-20251116-143000",              │
│        "outcome": "success",                                         │
│        "size_mb": 12450                                             │
│      }                                                               │
│    ],                                                                │
│    "recoveries": [                                                   │
│      {                                                               │
│        "timestamp": "2025-11-15T10:15:00Z",                         │
│        "subvolume": "subvol7-containers",                           │
│        "restored_snapshot": "subvol7-...-20251115-091200",          │
│        "reason": "deployment-validation-failed",                    │
│        "duration_seconds": 120,                                      │
│        "outcome": "success"                                          │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│           BACKUP HEALTH MONITORING                                   │
│                                                                      │
│  Periodic checks (homelab-intelligence integration):                │
│  - Snapshot creation rate (should be daily + on-demand)             │
│  - Snapshot age (no gaps >24h?)                                     │
│  - Snapshot integrity (validate random samples)                     │
│  - Disk space for snapshots (<10% of pool)                          │
│  - Recovery test results (from Project A)                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### Component 1: Backup Wrapper

**File**: `scripts/backup-wrapper.sh`

**Purpose**: Wrap any risky operation with automatic snapshotting.

**Usage**:
```bash
# Wrap a deployment
./scripts/backup-wrapper.sh \
  --subvolume subvol7-containers \
  --operation "deploy-immich" \
  --command "./scripts/deploy-stack.sh immich.yml"

# Wrap a manual change
./scripts/backup-wrapper.sh \
  --subvolume subvol6-config \
  --operation "update-traefik-config" \
  --command "nano ~/containers/config/traefik/traefik.yml"
```

**Implementation** (200 lines):
```bash
#!/bin/bash
# scripts/backup-wrapper.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/.claude/context"
BACKUP_HISTORY="$CONTEXT_DIR/backup-history.json"
SNAPSHOT_BASE="/mnt/btrfs-pool/snapshots"

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subvolume)
                SUBVOLUME="$2"
                shift 2
                ;;
            --operation)
                OPERATION="$2"
                shift 2
                ;;
            --command)
                COMMAND="$2"
                shift 2
                ;;
            --auto-rollback)
                AUTO_ROLLBACK=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
}

# Create pre-operation snapshot
create_snapshot() {
    local subvol=$1
    local operation=$2

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_name="${subvol}-pre-${operation}-${timestamp}"
    local snapshot_path="${SNAPSHOT_BASE}/${snapshot_name}"

    echo "🔄 Creating pre-operation snapshot: $snapshot_name"

    btrfs subvolume snapshot \
        "/mnt/btrfs-pool/${subvol}" \
        "$snapshot_path" > /dev/null

    # Log to backup history
    log_snapshot "$subvol" "$operation" "$snapshot_name" "pre-operation"

    echo "✅ Snapshot created: $snapshot_path"
    echo "$snapshot_name"  # Return snapshot name
}

# Log snapshot to backup history
log_snapshot() {
    local subvol=$1
    local operation=$2
    local snapshot_name=$3
    local type=$4

    local size_bytes=$(btrfs subvolume show "${SNAPSHOT_BASE}/${snapshot_name}" 2>/dev/null | grep -oP 'Size:\s+\K\d+' || echo "0")
    local size_mb=$((size_bytes / 1024 / 1024))

    local entry=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "subvolume": "$subvol",
  "type": "$type",
  "operation": "$operation",
  "snapshot_name": "$snapshot_name",
  "size_mb": $size_mb,
  "outcome": "pending"
}
EOF
)

    # Initialize if needed
    [[ ! -f "$BACKUP_HISTORY" ]] && echo '{"snapshots": [], "recoveries": []}' > "$BACKUP_HISTORY"

    # Append
    local updated=$(jq ".snapshots += [$entry]" "$BACKUP_HISTORY")
    echo "$updated" > "$BACKUP_HISTORY"
}

# Update snapshot outcome
update_snapshot_outcome() {
    local snapshot_name=$1
    local outcome=$2

    local updated=$(jq \
        --arg name "$snapshot_name" \
        --arg outcome "$outcome" \
        '(.snapshots[] | select(.snapshot_name == $name) | .outcome) = $outcome' \
        "$BACKUP_HISTORY")

    echo "$updated" > "$BACKUP_HISTORY"
}

# Execute wrapped command
execute_command() {
    local command=$1

    echo "▶️  Executing: $command"
    echo ""

    if eval "$command"; then
        echo ""
        echo "✅ Command completed successfully"
        return 0
    else
        echo ""
        echo "❌ Command failed (exit code: $?)"
        return 1
    fi
}

# Post-operation validation
validate_operation() {
    echo ""
    echo "🔍 Validating operation..."

    # Basic checks
    local checks_passed=true

    # Check 1: All services still running
    local stopped_services=$(systemctl --user list-units --type=service --state=failed --no-pager --no-legend | wc -l)
    if (( stopped_services > 0 )); then
        echo "  ❌ Found $stopped_services failed services"
        checks_passed=false
    else
        echo "  ✅ All services running"
    fi

    # Check 2: No critical errors in last 5 minutes
    local recent_errors=$(journalctl --user --since "5 minutes ago" --priority err --no-pager | wc -l)
    if (( recent_errors > 5 )); then
        echo "  ⚠️  Warning: $recent_errors errors in last 5 minutes"
        # Non-critical, just warn
    else
        echo "  ✅ No critical errors"
    fi

    if [[ "$checks_passed" == "true" ]]; then
        echo "✅ Validation passed"
        return 0
    else
        echo "❌ Validation failed"
        return 1
    fi
}

# Auto-rollback
auto_rollback() {
    local snapshot_name=$1

    echo ""
    echo "🚨 Operation failed validation, rolling back..."
    echo ""

    "$SCRIPT_DIR/auto-recovery.sh" \
        --snapshot "$snapshot_name" \
        --auto-confirm

    return $?
}

# Main
main() {
    parse_args "$@"

    # Validate required args
    if [[ -z "${SUBVOLUME:-}" ]] || [[ -z "${OPERATION:-}" ]] || [[ -z "${COMMAND:-}" ]]; then
        echo "Usage: $0 --subvolume <name> --operation <desc> --command <cmd> [--auto-rollback]"
        exit 1
    fi

    # Create snapshot
    local snapshot_name=$(create_snapshot "$SUBVOLUME" "$OPERATION")

    echo ""

    # Execute command
    if execute_command "$COMMAND"; then
        # Validate
        if validate_operation; then
            update_snapshot_outcome "$snapshot_name" "success"
            echo ""
            echo "🎉 Operation completed successfully"
            echo "   Snapshot: $snapshot_name (kept for safety)"
            exit 0
        else
            update_snapshot_outcome "$snapshot_name" "validation_failed"

            if [[ "${AUTO_ROLLBACK:-false}" == "true" ]]; then
                if auto_rollback "$snapshot_name"; then
                    echo "✅ Rollback successful"
                    exit 2  # Rolled back
                else
                    echo "❌ Rollback failed"
                    exit 3
                fi
            else
                echo ""
                echo "⚠️  Operation completed but validation failed"
                echo "   Snapshot available for manual rollback: $snapshot_name"
                exit 2
            fi
        fi
    else
        update_snapshot_outcome "$snapshot_name" "command_failed"

        if [[ "${AUTO_ROLLBACK:-false}" == "true" ]]; then
            if auto_rollback "$snapshot_name"; then
                echo "✅ Rollback successful"
                exit 2
            else
                echo "❌ Rollback failed"
                exit 3
            fi
        else
            echo ""
            echo "❌ Command failed"
            echo "   Snapshot available for manual rollback: $snapshot_name"
            exit 1
        fi
    fi
}

main "$@"
```

---

### Component 2: Auto-Recovery Script

**File**: `scripts/auto-recovery.sh`

**Purpose**: Automated snapshot restoration with validation.

**Usage**:
```bash
# Interactive recovery (list snapshots, choose one)
./scripts/auto-recovery.sh --subvolume subvol7-containers

# Direct recovery from specific snapshot
./scripts/auto-recovery.sh --snapshot subvol7-containers-pre-deploy-immich-20251116-143000

# Auto-confirm (non-interactive)
./scripts/auto-recovery.sh --snapshot <name> --auto-confirm
```

**Implementation** (300 lines):
```bash
#!/bin/bash
# scripts/auto-recovery.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/.claude/context"
BACKUP_HISTORY="$CONTEXT_DIR/backup-history.json"
SNAPSHOT_BASE="/mnt/btrfs-pool/snapshots"

# List available snapshots for subvolume
list_snapshots() {
    local subvol=$1

    echo "Available snapshots for $subvol:"
    echo ""

    ls -1dt "${SNAPSHOT_BASE}/${subvol}"-* 2>/dev/null | while read -r snapshot_path; do
        local snapshot_name=$(basename "$snapshot_path")
        local snapshot_date=$(stat -c %y "$snapshot_path" | cut -d' ' -f1,2 | cut -d. -f1)
        local age=$((($(date +%s) - $(stat -c %Y "$snapshot_path")) / 3600))

        echo "  $snapshot_name"
        echo "    Date: $snapshot_date ($age hours ago)"
    done

    echo ""
}

# Confirm recovery
confirm_recovery() {
    local snapshot_name=$1

    if [[ "${AUTO_CONFIRM:-false}" == "true" ]]; then
        return 0
    fi

    local snapshot_date=$(stat -c %y "${SNAPSHOT_BASE}/${snapshot_name}" | cut -d' ' -f1,2 | cut -d. -f1)

    echo "⚠️  You are about to restore from snapshot:"
    echo "   Name: $snapshot_name"
    echo "   Date: $snapshot_date"
    echo ""
    echo "This will:"
    echo "  1. Stop affected services"
    echo "  2. Replace current data with snapshot data"
    echo "  3. Restart services"
    echo ""
    read -p "Continue? (yes/no): " -r
    echo ""

    if [[ "$REPLY" != "yes" ]]; then
        echo "Recovery cancelled"
        return 1
    fi

    return 0
}

# Determine affected services
get_affected_services() {
    local subvolume=$1

    # Map subvolumes to services
    case "$subvolume" in
        subvol7-containers)
            # All container services
            systemctl --user list-units --type=service --state=running --no-pager --no-legend \
                | grep -E '(jellyfin|traefik|prometheus|grafana|authelia|immich)' \
                | awk '{print $1}'
            ;;
        subvol6-config)
            # Services that depend on configs
            echo "traefik.service"
            echo "authelia.service"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Stop services
stop_services() {
    local services=("$@")

    if [[ ${#services[@]} -eq 0 ]]; then
        return 0
    fi

    echo "🛑 Stopping affected services..."
    for service in "${services[@]}"; do
        echo "  Stopping $service"
        systemctl --user stop "$service" || true
    done
    echo ""
}

# Start services
start_services() {
    local services=("$@")

    if [[ ${#services[@]} -eq 0 ]]; then
        return 0
    fi

    echo "▶️  Starting services..."
    for service in "${services[@]}"; do
        echo "  Starting $service"
        systemctl --user start "$service" || true
    done
    echo ""
}

# Restore snapshot
restore_snapshot() {
    local subvolume=$1
    local snapshot_name=$2

    local subvol_path="/mnt/btrfs-pool/${subvolume}"
    local snapshot_path="${SNAPSHOT_BASE}/${snapshot_name}"
    local backup_path="/mnt/btrfs-pool/${subvolume}.recovery-backup-$(date +%Y%m%d-%H%M%S)"

    echo "🔄 Restoring snapshot..."

    # Step 1: Rename current subvolume (backup)
    echo "  Creating safety backup of current state..."
    mv "$subvol_path" "$backup_path"

    # Step 2: Create new subvolume from snapshot
    echo "  Restoring snapshot data..."
    btrfs subvolume snapshot "$snapshot_path" "$subvol_path" > /dev/null

    echo "✅ Snapshot restored"
    echo "   Original data backed up to: $(basename "$backup_path")"
    echo ""
}

# Validate recovery
validate_recovery() {
    local services=("$@")

    echo "🔍 Validating recovery..."

    # Wait for services to stabilize
    sleep 5

    # Check all services running
    local all_running=true
    for service in "${services[@]}"; do
        if ! systemctl --user is-active "$service" >/dev/null 2>&1; then
            echo "  ❌ $service failed to start"
            all_running=false
        else
            echo "  ✅ $service running"
        fi
    done

    if [[ "$all_running" == "true" ]]; then
        echo "✅ Recovery validation passed"
        return 0
    else
        echo "❌ Recovery validation failed"
        return 1
    fi
}

# Log recovery
log_recovery() {
    local subvolume=$1
    local snapshot_name=$2
    local duration=$3
    local outcome=$4

    local entry=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "subvolume": "$subvolume",
  "restored_snapshot": "$snapshot_name",
  "reason": "manual-recovery",
  "duration_seconds": $duration,
  "outcome": "$outcome"
}
EOF
)

    [[ ! -f "$BACKUP_HISTORY" ]] && echo '{"snapshots": [], "recoveries": []}' > "$BACKUP_HISTORY"

    local updated=$(jq ".recoveries += [$entry]" "$BACKUP_HISTORY")
    echo "$updated" > "$BACKUP_HISTORY"
}

# Main
main() {
    local subvolume=""
    local snapshot_name=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subvolume)
                subvolume="$2"
                shift 2
                ;;
            --snapshot)
                snapshot_name="$2"
                shift 2
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    # If no snapshot specified, list and prompt
    if [[ -z "$snapshot_name" ]]; then
        if [[ -z "$subvolume" ]]; then
            echo "Usage: $0 --snapshot <name> [--auto-confirm]"
            echo "   or: $0 --subvolume <name>"
            exit 1
        fi

        list_snapshots "$subvolume"
        read -p "Enter snapshot name to restore: " -r snapshot_name
    fi

    # Extract subvolume from snapshot name if needed
    if [[ -z "$subvolume" ]]; then
        subvolume=$(echo "$snapshot_name" | grep -oP '^subvol\d+-\w+')
    fi

    # Confirm
    confirm_recovery "$snapshot_name" || exit 1

    # Get affected services
    local services=($(get_affected_services "$subvolume"))

    # Execute recovery
    local start_time=$(date +%s)

    stop_services "${services[@]}"
    restore_snapshot "$subvolume" "$snapshot_name"
    start_services "${services[@]}"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Validate
    if validate_recovery "${services[@]}"; then
        log_recovery "$subvolume" "$snapshot_name" "$duration" "success"
        echo ""
        echo "🎉 Recovery completed successfully in ${duration}s"
        exit 0
    else
        log_recovery "$subvolume" "$snapshot_name" "$duration" "failed"
        echo ""
        echo "❌ Recovery validation failed"
        echo "   Manual intervention required"
        exit 1
    fi
}

main "$@"
```

---

### Component 3: Backup Health Check

**File**: `scripts/backup-health-check.sh`

**Purpose**: Validate backup integrity and identify issues.

**Checks**:
1. Snapshot creation rate (daily expected)
2. Snapshot age gaps (no >24h gaps)
3. Snapshot integrity (verify readable)
4. Disk space usage (<10% of pool)
5. Recovery test results (from Project A)

**Usage**:
```bash
# Run health check
./scripts/backup-health-check.sh

# Output:
# Backup Health Check Report
# ==========================
#
# Snapshot Coverage:
#   ✅ subvol7-containers: 94 snapshots (newest: 2h ago, oldest: 30d ago)
#   ✅ subvol6-config: 94 snapshots (newest: 2h ago, oldest: 30d ago)
#   ✅ subvol5-logs: 94 snapshots (newest: 2h ago, oldest: 30d ago)
#
# Snapshot Gaps:
#   ✅ No gaps >24h detected
#
# Integrity:
#   ✅ Random sample check (5 snapshots): All readable
#
# Disk Usage:
#   ✅ Snapshots use 12.4 GB (4.2% of pool)
#
# Recovery Tests:
#   ⚠️  Last recovery test: 15 days ago
#   Recommendation: Run recovery test (Project A)
#
# Overall Health: GOOD
```

**Implementation** (250 lines - similar structure to homelab-intel.sh)

---

## Integration Patterns

### Pattern 1: Deployment-Triggered Snapshots

**Integration**: homelab-deployment skill automatically snapshots before deployment.

**Enhancement to homelab-deployment**:
```bash
# In .claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh

# Before deployment
echo "Creating pre-deployment snapshot..."
SNAPSHOT_NAME=$(./scripts/backup-wrapper.sh \
  --subvolume subvol7-containers \
  --operation "deploy-${SERVICE_NAME}" \
  --command "echo 'snapshot-only'" \
  --no-execute)  # Just snapshot, don't execute yet

# Deploy
deploy_service "$SERVICE_NAME" "$PATTERN"

# Validate
if validate_deployment "$SERVICE_NAME"; then
    echo "✅ Deployment successful, snapshot marked as success"
else
    echo "❌ Deployment failed, rolling back..."
    ./scripts/auto-recovery.sh --snapshot "$SNAPSHOT_NAME" --auto-confirm
fi
```

---

### Pattern 2: Configuration Change Protection

**Use Case**: Protect critical config changes (Traefik, Authelia).

**Implementation**:
```bash
# Wrap config edits
./scripts/backup-wrapper.sh \
  --subvolume subvol6-config \
  --operation "update-traefik-middleware" \
  --command "nano ~/containers/config/traefik/dynamic/middleware.yml" \
  --auto-rollback
```

**Result**: If validation fails after edit, auto-rollback to previous config.

---

### Pattern 3: Scheduled Snapshot Optimization

**Enhancement**: Optimize backup timing using traffic analysis.

**Integration with Session 5B** (Predictive Analytics):
```bash
# Find optimal backup window (low traffic)
OPTIMAL_TIME=$(./scripts/find-optimal-maintenance-window.sh | head -1)

# Update crontab
echo "$OPTIMAL_TIME root /path/to/btrfs-snapshot-backup.sh" >> /etc/cron.d/backups
```

---

### Pattern 4: Proactive Backup Alerts

**Integration**: Alert before backup disk space exhaustion.

**Using Session 5B** (Predictive Analytics):
```bash
# Predict when snapshot disk usage will hit 10% (threshold)
./scripts/predict-resource-exhaustion.sh --resource /mnt/btrfs-pool

# If prediction: "Snapshots will exceed 10% in 14 days"
# → Alert: "Backup retention should be reduced or pool expanded"
```

---

## Implementation Phases

### Phase 1: Core Backup Wrapper (2-3 hours)

**Session 5E-1: Snapshot Automation**

**Tasks**:
1. Create `scripts/backup-wrapper.sh` (200 lines)
2. Create `.claude/context/backup-history.json`
3. Test wrapping simple operations:
   ```bash
   # Test 1: Wrap echo command
   ./scripts/backup-wrapper.sh \
     --subvolume subvol7-containers \
     --operation "test" \
     --command "echo 'test success'"

   # Verify snapshot created
   ls -lh /mnt/btrfs-pool/snapshots/ | grep test
   ```

**Success Criteria**:
- ✅ Snapshots created before operations
- ✅ backup-history.json populated
- ✅ Snapshot naming convention consistent
- ✅ Metadata logged correctly

**Deliverables**:
- `scripts/backup-wrapper.sh`
- `.claude/context/backup-history.json`

---

### Phase 2: Auto-Recovery Implementation (2-3 hours)

**Session 5E-2: Automated Rollback**

**Tasks**:
1. Create `scripts/auto-recovery.sh` (300 lines)
2. Test recovery workflow:
   ```bash
   # Create test snapshot
   btrfs subvolume snapshot \
     /mnt/btrfs-pool/subvol7-containers \
     /mnt/btrfs-pool/snapshots/subvol7-containers-test-20251116

   # Make a change
   touch /mnt/btrfs-pool/subvol7-containers/TEST_FILE

   # Recover
   ./scripts/auto-recovery.sh --snapshot subvol7-containers-test-20251116

   # Verify TEST_FILE is gone
   [[ ! -f /mnt/btrfs-pool/subvol7-containers/TEST_FILE ]] && echo "✅ Recovery works"
   ```

3. Integrate with backup-wrapper.sh (auto-rollback flag)

**Success Criteria**:
- ✅ Recovery restores snapshot data correctly
- ✅ Services stopped/started automatically
- ✅ Validation checks work
- ✅ Recovery logged to backup-history.json

**Deliverables**:
- `scripts/auto-recovery.sh`
- Updated `scripts/backup-wrapper.sh` with auto-rollback

---

### Phase 3: Deployment Integration (2 hours)

**Session 5E-3: Skill Integration**

**Tasks**:
1. Update homelab-deployment skill:
   - Add pre-deployment snapshot call
   - Add post-deployment validation
   - Add auto-rollback on failure

2. Test integrated deployment:
   ```bash
   # Deploy test service with backup protection
   .claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh \
     --pattern cache-service \
     --service-name test-redis \
     --memory 512M

   # Verify snapshot created and validated
   ```

3. Update skill documentation

**Success Criteria**:
- ✅ All deployments automatically snapshot
- ✅ Rollback works on deployment failure
- ✅ Users are informed of snapshot activity
- ✅ backup-history.json tracks all deployments

**Deliverables**:
- Updated homelab-deployment skill
- Integration tests passed

---

## Recovery Automation

### Automated Recovery Scenarios

**Scenario 1: Deployment Failure**
```
Trigger: Post-deployment validation fails
Action: Auto-rollback to pre-deployment snapshot
Result: System restored to pre-deployment state (instant)
```

**Scenario 2: Config Corruption**
```
Trigger: Traefik fails to start after config edit
Action: Auto-rollback to last known-good config snapshot
Result: Service restored (within 2 minutes)
```

**Scenario 3: Data Corruption**
```
Trigger: User reports data corruption
Action: Present recent snapshots, allow selection
Result: Data restored from chosen point-in-time
```

**Scenario 4: Disaster Recovery**
```
Trigger: System disk failure
Action: Restore all subvolumes from snapshots (Project A)
Result: Full system recovery
```

---

## Testing Strategy

### Unit Tests

**Test 1: Snapshot Creation**
```bash
# Test wrapper creates snapshot
./scripts/backup-wrapper.sh --subvolume subvol7-containers --operation "test" --command "echo test"

# Verify
[[ -d "/mnt/btrfs-pool/snapshots/subvol7-containers-pre-test-*" ]] && echo "✅ Pass"
```

**Test 2: Auto-Rollback**
```bash
# Test rollback on command failure
./scripts/backup-wrapper.sh \
  --subvolume subvol7-containers \
  --operation "test-fail" \
  --command "exit 1" \
  --auto-rollback

# Verify rollback logged
jq '.recoveries | length' backup-history.json  # Should be > 0
```

---

### Integration Tests

**Test 1: Full Deployment Workflow**
```bash
# Deploy service
# Simulate failure (kill service immediately)
# Verify auto-rollback
# Verify service state restored
```

**Test 2: Recovery from Snapshot**
```bash
# Create snapshot
# Modify data
# Recover
# Verify data matches snapshot
```

---

## Success Metrics

### Quantitative Metrics

1. **Snapshot Coverage**
   - Target: 100% of deployments snapshot before execution
   - Measure: backup-history.json snapshot count vs deployment count

2. **Recovery Time Objective (RTO)**
   - Target: <5 minutes for any single-service recovery
   - Measure: Average duration_seconds in backup-history.json

3. **Recovery Success Rate**
   - Target: >95% of auto-recoveries succeed
   - Measure: recovery.outcome == "success" / total recoveries

### Qualitative Metrics

1. **User Confidence**
   - "I'm not afraid to make changes anymore"
   - "Recovery is instant and painless"

2. **Operational Safety**
   - Zero data loss from failed deployments
   - All risky operations protected by snapshots

---

## Future Enhancements

### Enhancement 1: Incremental Snapshots

**Current**: Full snapshots (BTRFS does this efficiently already)

**Enhancement**: Track incremental differences for analysis.

---

### Enhancement 2: Cross-Subvolume Dependencies

**Enhancement**: When restoring subvol7-containers, offer to restore matching subvol6-config snapshot.

---

### Enhancement 3: Cloud Backup Integration

**Enhancement**: Sync critical snapshots to cloud storage (Backblaze B2, AWS S3).

---

## Documentation

### Usage Guide

**File**: `docs/20-operations/guides/backup-integration.md`

**Contents**:
- How backup integration works
- When snapshots are created automatically
- How to manually wrap operations
- How to recover from snapshots
- Backup health monitoring

---

## Conclusion

Session 5E delivers **backup-first operations** that:

✅ Automatically snapshot before risky operations
✅ Validate changes and rollback on failure
✅ Reduce recovery time from hours to minutes
✅ Eliminate data loss from failed deployments
✅ Provide confidence to make changes safely

**Timeline**: 6-8 hours across 2-3 sessions
**Prerequisites**: Existing BTRFS backup infrastructure, Session 4 (Context Framework)
**Value**: Transform backups from "insurance policy" to "operational superpower"

Ready to make recovery effortless! 🛡️
