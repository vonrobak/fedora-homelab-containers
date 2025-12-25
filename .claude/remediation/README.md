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

# Execute
./apply-remediation.sh --playbook resource-pressure
```

---

### 5. Predictive Maintenance (`predictive-maintenance.yml`)

**Trigger:** Forecast shows critical resource exhaustion within 7 days
**Risk Level:** LOW (proactive cleanup before issues occur)
**Confirmation Required:** No

**Actions:**
- Run predictive analytics to forecast resource usage
- If disk forecasted to reach critical threshold (>85% in 7 days):
  - Preemptively execute disk cleanup
- Log prediction for trending analysis
- Generate recommendations for manual review

**Expected Impact:** Prevents future issues before they occur

**Usage:**
```bash
# Dry run
./apply-remediation.sh --playbook predictive-maintenance --dry-run

# Execute
./apply-remediation.sh --playbook predictive-maintenance
```

---

### 6. Self-Healing Restart (`self-healing-restart.yml`)

**Trigger:** Service failed or in restart loop
**Risk Level:** MEDIUM (restarts service after diagnosis)
**Confirmation Required:** No

**Actions:**
- Diagnose failure cause (OOM, crash, dependency failure)
- If OOM detected:
  - Log recommendation to increase memory limit
- If restart loop detected:
  - Clear failed state before restart
- Restart service with clean state
- Monitor for stability (30 seconds)

**Expected Result:** Service restored to healthy state with root cause identified

**Usage:**
```bash
# Dry run
./apply-remediation.sh --playbook self-healing-restart --service prometheus --dry-run

# Execute
./apply-remediation.sh --playbook self-healing-restart --service prometheus
```

---

### 7. Database Maintenance (`database-maintenance.yml`)

**Trigger:** Manual/scheduled weekly maintenance
**Risk Level:** MEDIUM (may cause temporary performance impact)
**Confirmation Required:** Yes

**Actions:**
- PostgreSQL VACUUM ANALYZE (Immich database)
  - Reclaims space from deleted records
  - Updates query planner statistics
- Redis memory analysis (Authelia sessions)
  - Reports memory usage and key counts
- Loki retention check
- Generate maintenance report

**Expected Impact:** Improved database performance, space reclamation

**Usage:**
```bash
# Dry run
./apply-remediation.sh --playbook database-maintenance --dry-run

# Execute
./apply-remediation.sh --playbook database-maintenance
```

---

## Execution Engine

**Script:** `.claude/remediation/scripts/apply-remediation.sh`

**Current Implementation Status (as of 2025-12-23):**
- ✅ **disk-cleanup:** Fully implemented and tested
- ✅ **service-restart:** Fully implemented and tested
- ✅ **drift-reconciliation:** Fully implemented
- ✅ **resource-pressure:** Fully implemented and tested
- ✅ **predictive-maintenance:** Fully implemented and tested (NEW)
- ✅ **self-healing-restart:** Fully implemented and tested (NEW)
- ✅ **database-maintenance:** Fully implemented and tested (NEW)

**Features:**
- Dry-run mode (`--dry-run`)
- Detailed logging (saved to `../../data/remediation-logs/`)
- Pre-checks and post-checks
- Colored output for readability
- Force mode (`--force`) to override thresholds

**Integration with Autonomous Operations (Session 6):**
- ✅ **Fully integrated (2025-11-30)** - Autonomous operations now calls remediation playbooks via apply-remediation.sh
- **Architecture:** Clean separation between decision-making (autonomous-execute.sh) and execution (remediation playbooks)
- **Benefits:** Single source of truth, eliminated code duplication, easier testing and maintenance
- See: `docs/99-reports/2025-11-30-remediation-integration-implementation.md` for details

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

## Analytics & Intelligence

**Phase 6 (2025-12-25):** Comprehensive analytics suite for data-driven insights

**Location:** `~/containers/scripts/analytics/`

### Available Analytics Tools

#### 1. Effectiveness Scoring (`remediation-effectiveness.sh`)

Calculate 0-100 effectiveness scores for each playbook using weighted algorithm:
- Success Rate (40%): Percentage of successful executions
- Impact (30%): Disk reclaimed, services recovered (playbook-specific)
- Execution Time (20%): Faster = higher score (<30s = perfect)
- Prediction Accuracy (10%): For predictive-maintenance only

**Score Interpretation:**
- ≥80: Excellent
- 60-79: Good
- <60: Needs Improvement

**Usage:**
```bash
# Summary table for all playbooks
~/containers/scripts/analytics/remediation-effectiveness.sh --summary --days 30

# Specific playbook details
~/containers/scripts/analytics/remediation-effectiveness.sh --playbook disk-cleanup --days 7
```

#### 2. Trend Analysis (`remediation-trends.sh`)

Identify patterns and trends over time:
- Execution frequency trends (first half vs second half comparison)
- Success rate trends (performance improvement/degradation)
- Most common root causes (self-healing incidents)
- Most active playbooks (execution volume ranking)

**Usage:**
```bash
# Last 30 days analysis
~/containers/scripts/analytics/remediation-trends.sh --last 30d

# Weekly trends
~/containers/scripts/analytics/remediation-trends.sh --last 7d
```

#### 3. ROI Calculation (`remediation-roi.sh`)

Quantify return on investment for automation:
- Time Savings: Manual (30 min/task) vs Automated (2 min/task)
- Incidents Prevented: Predictive maintenance × 30% conversion rate
- Services Recovered: Self-healing success count
- Manual Interventions Avoided: Total successful remediations

**Usage:**
```bash
# Monthly ROI report
~/containers/scripts/analytics/remediation-roi.sh --last 30d

# Quick summary
~/containers/scripts/analytics/remediation-roi.sh --summary
```

#### 4. Recommendations (`remediation-recommendations.sh`)

Generate actionable optimization suggestions:
- Memory limit adjustments (>2 OOM events)
- Disk cleanup frequency tuning (>2x per week)
- Database maintenance effectiveness
- Service override candidates (100% success rate)
- Predictive maintenance underutilization
- Low effectiveness playbooks (<60% success)

**Usage:**
```bash
# Last 30 days recommendations
~/containers/scripts/analytics/remediation-recommendations.sh --last 30d
```

#### 5. Monthly Reports (`generate-monthly-report.sh`)

Generate comprehensive monthly markdown reports combining all analytics:
- Executive summary with key metrics
- Top performing playbooks
- Incidents prevented
- Effectiveness analysis
- Trend analysis
- ROI summary
- Recommendations
- Next steps

**Output:** `~/containers/docs/99-reports/remediation-monthly-YYYYMM.md`

**Usage:**
```bash
# Generate report for last month (default)
~/containers/scripts/analytics/generate-monthly-report.sh

# Generate report for specific month
~/containers/scripts/analytics/generate-monthly-report.sh --month 2025-12
```

**Automation:** Monthly reports generated automatically on 1st of each month at 08:00 via systemd timer (`remediation-monthly-report.timer`)

### Metrics Collection

All remediation executions automatically tracked in:
- `~/containers/.claude/remediation/metrics-history.json` - Playbook executions
- `~/containers/.claude/remediation/chain-metrics-history.jsonl` - Chain executions

**Metrics Tracked:**
- Timestamp, playbook/chain name, status (success/failure)
- Duration, disk reclaimed, services restarted
- OOM events detected, root cause (for self-healing)

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

## Statistics (as of 2025-12-23)

**Playbooks Created:** 7
- disk-cleanup (✅ fully implemented and tested)
- service-restart (✅ fully implemented and tested)
- drift-reconciliation (✅ fully implemented)
- resource-pressure (✅ fully implemented and tested)
- predictive-maintenance (✅ fully implemented and tested - NEW)
- self-healing-restart (✅ fully implemented and tested - NEW)
- database-maintenance (✅ fully implemented and tested - NEW)

**Estimated Capabilities:**
- Disk cleanup: 5-15GB recovery (verified in production)
- Service recovery: <60 seconds downtime
- Drift fixes: Automated reconciliation
- Memory pressure: 20-40% swap reduction
- Predictive maintenance: Proactive remediation 7 days before critical thresholds
- Self-healing restart: Intelligent service recovery with root cause detection
- Database maintenance: PostgreSQL VACUUM, Redis analysis, maintenance reports

**System Context:**
- Current SSD usage: 75% (improved from 84%)
- Current swap: ~4GB (improved)
- Services monitored: ~20 containers
- Issue history: 12 documented issues (7 resolved with documented solutions)
- Autonomous operations: 11 checks, 0 actions executed yet

**Utilization Assessment:**
- **Manual usage:** Working well for disk-cleanup and service-restart ✅
- **Autonomous usage:** Fully integrated - all actions use remediation playbooks ✅
- **Overall utilization:** 100% - remediation framework now fully utilized

---

## Known Gaps & Recommendations

### ~~Gap 1: Autonomous Operations Integration~~ ✅ RESOLVED

**Status:** ✅ Implemented 2025-11-30

**Solution:** Refactored autonomous-execute.sh to call remediation playbooks
```bash
# Autonomous operations now delegates to remediation framework:
execute_disk_cleanup() {
    "$APPLY_REMEDIATION" \
        --playbook disk-cleanup \
        --log-to "$DECISION_LOG" \
        2>&1 | tee -a "$LOG_FILE"
}
```

**Results:**
- ✅ Single source of truth achieved
- ✅ Eliminated 85 lines of duplicated logic
- ✅ Easier testing and maintenance
- ✅ Decision log tracks all remediation executions

### ~~Gap 2: Incomplete Playbook Implementation~~ ✅ RESOLVED

**Status:** ✅ Implemented 2025-12-23

**Solution:** All 7 playbooks now fully implemented in execution engine:
- ✅ drift-reconciliation (completed)
- ✅ resource-pressure (completed and tested)
- ✅ predictive-maintenance (NEW - completed and tested)
- ✅ self-healing-restart (NEW - completed and tested)
- ✅ database-maintenance (NEW - completed and tested)

**Results:**
- ✅ Complete remediation arsenal for autonomous operations
- ✅ Proactive maintenance capabilities (predictive-maintenance)
- ✅ Intelligent service recovery (self-healing-restart)
- ✅ Database health operations (database-maintenance)

### Gap 3: No Automated Triggers

**Current:** All remediation is manual (user-initiated)

**Recommendation:** Add triggers:
- Alertmanager webhook → Execute remediation
- Scheduled health checks → Auto-remediate if threshold exceeded
- Autonomous operations → Call playbooks (per Gap 1)

---

## Future Enhancements

### ~~Phase 1: Complete Session 4B~~ ✅ COMPLETE
- [x] Implement drift-reconciliation in execution engine
- [x] Implement resource-pressure in execution engine
- [x] Test all 4 playbooks end-to-end

### ~~Phase 2: Integrate with Autonomous Ops~~ ✅ COMPLETE
- [x] Refactor autonomous-execute.sh to call remediation playbooks
- [x] Add --log-to parameter to apply-remediation.sh for decision-log
- [x] Test autonomous operations with remediation integration
- [x] Update autonomous operations documentation

### ~~Phase 2A: Arsenal Expansion~~ ✅ COMPLETE (2025-12-23)
- [x] **predictive-maintenance.yml** - Proactive remediation before failure
- [x] **self-healing-restart.yml** - Smart service restart with root cause detection
- [x] **database-maintenance.yml** - Automated database health operations
- [x] Test all 3 new playbooks (dry-run + real execution)
- [x] Update documentation

**Total Time:** ~6 hours (implementation + testing + documentation)

### ~~Phase 3: Alertmanager Integration~~ ✅ COMPLETE (2025-12-23)
- [x] **webhook-routing.yml** - Alertmanager webhook configuration
- [x] **execute-remediation-webhook.sh** - Webhook endpoint handler
- [x] Webhook routing rules for all remediation playbooks
- [x] Integration testing with Alertmanager

**Total Time:** ~2 hours (implementation + testing + documentation)

### ~~Phase 4: Resource Pressure Intelligence~~ ✅ COMPLETE (2025-12-23)
- [x] **predict-resource-exhaustion.sh** - 7-14 day forecasting
- [x] CPU, memory, disk, and swap trend analysis
- [x] Integration with predictive-maintenance playbook
- [x] Testing and validation

**Total Time:** ~2 hours (implementation + testing)

### ~~Phase 5: Multi-Playbook Chaining~~ ✅ COMPLETE (2025-12-24)
- [x] **execute-chain.sh** - Orchestration engine for playbook sequences
- [x] **3 chain configurations:** full-recovery, predictive-preemption, database-health
- [x] Conditional execution, varied failure strategies
- [x] State management and resume capability
- [x] Chain metrics tracking (JSONL format)
- [x] Testing and bug fixes (arithmetic post-increment with set -e)

**Total Time:** ~4 hours (implementation + testing + bug fixes)

### ~~Phase 6: History Analytics~~ ✅ COMPLETE (2025-12-25)
- [x] **remediation-effectiveness.sh** - Playbook effectiveness scoring (0-100)
- [x] **remediation-trends.sh** - Execution pattern and trend analysis
- [x] **remediation-roi.sh** - ROI calculation (time saved, incidents prevented)
- [x] **remediation-recommendations.sh** - Optimization suggestions
- [x] **generate-monthly-report.sh** - Comprehensive monthly reports
- [x] **Systemd timer** - Automated monthly report generation
- [x] Bug fixes: bc syntax, printf locale issues, tr deletion

**Total Time:** ~3 hours (implementation + testing + bug fixes + documentation)

### Phase 7: Future Enhancements
- [ ] Grafana "Remediation Intelligence" dashboard
- [ ] Slack/Discord webhook integration for monthly reports
- [ ] Machine learning for incident prediction
- [ ] Anomaly detection in execution patterns
- [ ] Scheduled auto-remediation (cron/timer beyond current webhook integration)
- [ ] Rollback automation for failed remediations

---

**Maintainer:** patriark
**Status:** ✅ Phases 1-6 complete - Full remediation framework operational
**Playbook Count:** 7 playbooks + 3 chains
**Analytics:** 5 scripts + automated monthly reporting
**Last Updated:** 2025-12-25
**Documentation:**
- Implementation: `docs/98-journals/2025-12-*-remediation-phase-*.md`
- Analysis: `docs/99-reports/2025-11-30-context-remediation-analysis.md`
- Monthly Reports: `docs/99-reports/remediation-monthly-*.md` (automated)
