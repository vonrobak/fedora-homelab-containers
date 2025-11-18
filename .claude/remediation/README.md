# Auto-Remediation Framework

**Created:** 2025-11-18 (Session 4B)
**Purpose:** Automated fixes for common homelab issues

---

## Overview

The Auto-Remediation Framework provides **intelligent, automated recovery** from common system issues. Combined with the Context Framework, Claude can detect problems and offer or execute fixes based on proven solutions.

**Key Features:**
- **Safe by default:** Dry-run mode, confirmation prompts for risky operations
- **Logged operations:** All actions tracked with before/after metrics
- **Rollback capable:** Where possible, changes can be reversed
- **Context-aware:** References issue history for proven solutions

---

## Available Playbooks

### 1. Disk Cleanup (`disk-cleanup.yml`)

**Trigger:** System SSD > 75% usage
**Risk Level:** LOW (safe operations)
**Confirmation Required:** No

**Actions:**
- Rotate systemd journal logs (7-day retention)
- Prune unused Podman images (7+ days old)
- Clean Podman build cache
- Remove old backup logs (30+ days)
- Clean stale Jellyfin transcode files (1+ day old)

**Expected Space Freed:** 5-15GB

**Usage:**
```bash
# Dry run
cd .claude/remediation/scripts
./apply-remediation.sh --playbook disk-cleanup --dry-run

# Execute
./apply-remediation.sh --playbook disk-cleanup
```

---

### 2. Service Restart (`service-restart.yml`)

**Trigger:** Service failed/unhealthy state
**Risk Level:** LOW (standard restart)
**Confirmation Required:** No

**Actions:**
- Capture pre-restart logs
- Graceful service stop
- Verify stopped state
- Start service
- Verify active state

**Usage:**
```bash
# Dry run
./apply-remediation.sh --playbook service-restart --service prometheus --dry-run

# Execute
./apply-remediation.sh --playbook service-restart --service prometheus
```

---

### 3. Drift Reconciliation (`drift-reconciliation.yml`)

**Trigger:** check-drift.sh detects config mismatch
**Risk Level:** MEDIUM (modifies running services)
**Confirmation Required:** YES

**Actions:**
- Backup current quadlet file
- Regenerate from pattern (using deployment-log.json)
- Validate quadlet syntax
- Reload systemd
- Restart service
- Verify drift resolved

**Usage:**
```bash
# Check drift first
cd .claude/skills/homelab-deployment/scripts
./check-drift.sh jellyfin

# If drift detected, reconcile (NOT YET IMPLEMENTED IN ENGINE)
cd ../../../remediation/scripts
./apply-remediation.sh --playbook drift-reconciliation --service jellyfin
```

---

### 4. Resource Pressure (`resource-pressure.yml`)

**Trigger:** High swap usage (>6GB) or low available memory
**Risk Level:** MEDIUM (may restart services)
**Confirmation Required:** YES

**Actions:**
- Clear system caches (safe)
- Identify memory-intensive services
- Compact Jellyfin transcode cache
- Restart high-memory services if needed
- Verify swap/memory improvement

**Expected Improvement:** 20-40% swap reduction

**Usage:**
```bash
# Dry run
./apply-remediation.sh --playbook resource-pressure --dry-run

# Execute (NOT YET IMPLEMENTED IN ENGINE)
./apply-remediation.sh --playbook resource-pressure
```

---

## Execution Engine

**Script:** `.claude/remediation/scripts/apply-remediation.sh`

**Current Implementation Status:**
- ✅ **disk-cleanup:** Fully implemented and tested
- ✅ **service-restart:** Fully implemented
- ⚠️ **drift-reconciliation:** Playbook ready, execution engine pending
- ⚠️ **resource-pressure:** Playbook ready, execution engine pending

**Features:**
- Dry-run mode (`--dry-run`)
- Detailed logging (saved to `../../data/remediation-logs/`)
- Pre-checks and post-checks
- Colored output for readability
- Force mode (`--force`) to override thresholds

---

## Integration with Context Framework

### Issue History Integration

When remediation executes, it references issue history:

```bash
# Example: Disk cleanup references ISS-001
"System disk at 84%. Last time (ISS-001), freed 12GB via journal rotation + image pruning.
 Running same cleanup now..."
```

### Deployment Log Integration

Drift reconciliation uses deployment history:

```bash
# Example: Regenerate Jellyfin from deployment log
"Drift detected in jellyfin. Your deployment-log shows:
 - Pattern: media-server-stack
 - Memory: 4G
 - Networks: reverse_proxy, media_services, monitoring
 Regenerating from pattern. Proceed? (y/n)"
```

---

## Safety Features

### Confirmation Prompts

High-risk operations require user confirmation:
- Drift reconciliation (modifies running services)
- Resource pressure (may restart services)
- Any operation with `requires_confirmation: true`

### Dry-Run Mode

Always test before executing:
```bash
./apply-remediation.sh --playbook disk-cleanup --dry-run
```

Shows what would be executed without making changes.

### Backups

Operations that modify configs create backups:
- Drift reconciliation: `~/containers/backups/quadlets/<timestamp>/`
- Restoration: Documented in playbook rollback section

### Logging

All operations logged with metrics:
- Before/after disk usage
- Space freed
- Service status
- Action duration
- Errors/warnings

**Log location:** `~/containers/data/remediation-logs/`

**Log format:** `<playbook>-<timestamp>.log`

---

## Common Workflows

### Workflow 1: System Disk Nearly Full

```bash
# 1. Check current usage
df -h /

# 2. Run homelab-intel for full assessment
~/containers/scripts/homelab-intel.sh

# 3. Execute disk cleanup
cd .claude/remediation/scripts
./apply-remediation.sh --playbook disk-cleanup

# 4. Verify improvement
df -h /
```

### Workflow 2: Service Not Responding

```bash
# 1. Check service status
systemctl --user status prometheus.service

# 2. Check if drift is the issue
cd .claude/skills/homelab-deployment/scripts
./check-drift.sh prometheus

# 3. If no drift, restart service
cd ../../../remediation/scripts
./apply-remediation.sh --playbook service-restart --service prometheus

# 4. Verify service healthy
systemctl --user status prometheus.service
podman healthcheck run prometheus
```

### Workflow 3: High Swap Usage

```bash
# 1. Check memory/swap status
free -h
podman stats --no-stream

# 2. Identify memory consumers
./apply-remediation.sh --playbook resource-pressure --dry-run

# 3. Review recommended actions
# (currently shows what would be done)

# 4. Execute if appropriate
# ./apply-remediation.sh --playbook resource-pressure
```

---

## Extending the Framework

### Adding a New Playbook

1. Create playbook YAML in `.claude/remediation/playbooks/`
2. Follow existing playbook structure:
   - Metadata (name, version, risk_level)
   - Triggers (conditions)
   - Pre-checks
   - Actions
   - Post-checks
   - Logging
   - Rollback procedures

3. Implement execution logic in `apply-remediation.sh`

**Template:**
```yaml
---
name: "My Playbook"
version: "1.0"
created: "YYYY-MM-DD"
risk_level: "low|medium|high"
requires_confirmation: false|true

triggers:
  - condition: "some_metric > threshold"
    description: "Description"

actions:
  - name: "Action description"
    command: "command to run"
    expected_exit: 0
    estimated_freed: "X GB"
    reversible: true|false

# ... (see existing playbooks for full structure)
```

---

## Testing Recommendations

### Before Production Use

1. **Dry-run mode:** Always test with `--dry-run` first
2. **Non-critical service:** Test on non-essential services first
3. **Backup verification:** Ensure backups created and restorable
4. **Rollback test:** Verify rollback procedures work
5. **Metrics validation:** Confirm before/after metrics accurate

### Test Scenarios

```bash
# Test 1: Disk cleanup (safe, can test in production)
./apply-remediation.sh --playbook disk-cleanup --dry-run
./apply-remediation.sh --playbook disk-cleanup

# Test 2: Service restart (test on homepage first, low-impact)
./apply-remediation.sh --playbook service-restart --service homepage --dry-run
./apply-remediation.sh --playbook service-restart --service homepage

# Test 3: Force mode (override thresholds for testing)
./apply-remediation.sh --playbook disk-cleanup --force
```

---

## Troubleshooting

### Playbook Execution Failed

1. Check log file: `~/containers/data/remediation-logs/<playbook>-<timestamp>.log`
2. Review error messages
3. Verify pre-checks passed
4. Check playbook file syntax (YAML validation)

### Services Failed After Remediation

1. Check service logs: `journalctl --user -u <service>.service`
2. Verify configuration: `systemctl --user status <service>.service`
3. Check for drift: `.claude/skills/homelab-deployment/scripts/check-drift.sh <service>`
4. Restore from backup if drift reconciliation was involved

### Disk Cleanup Didn't Free Expected Space

1. Check what was actually cleaned in log file
2. Verify journal log size: `journalctl --user --disk-usage`
3. Check Podman image list: `podman images`
4. Manual investigation: `du -sh ~/containers/*`

---

## Statistics (as of 2025-11-18)

**Playbooks Created:** 4
- disk-cleanup (fully implemented)
- service-restart (fully implemented)
- drift-reconciliation (playbook ready)
- resource-pressure (playbook ready)

**Estimated Capabilities:**
- Disk cleanup: 5-15GB recovery
- Service recovery: <60 seconds downtime
- Drift fixes: Automated reconciliation
- Memory pressure: 20-40% swap reduction

**System Context:**
- Current SSD usage: 84% (perfect test case!)
- Current swap: 7.4GB (above threshold)
- Services monitored: 20 containers
- Issue history: 12 issues (7 resolved with documented solutions)

---

## Next Steps (Future Enhancements)

### Session 4B Completion:
- [ ] Implement drift-reconciliation in execution engine
- [ ] Implement resource-pressure in execution engine
- [ ] Test all playbooks in production
- [ ] Enhance homelab-intelligence skill to suggest remediations

### Future Features:
- [ ] Scheduled auto-remediation (cron integration)
- [ ] Alertmanager integration (trigger on alerts)
- [ ] Claude skill triggers (auto-suggest remediation)
- [ ] Multi-playbook chaining (cleanup + restart)
- [ ] Remediation history analytics

---

**Maintainer:** patriark
**Status:** Session 4B in progress
**Documentation:** Full Session 4 plan in `docs/99-reports/2025-11-15-session-4-hybrid-plan.md`
