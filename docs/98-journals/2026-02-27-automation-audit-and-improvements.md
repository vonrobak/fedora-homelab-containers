# Automation Audit and Improvement Proposals

**Date:** 2026-02-27
**Scope:** Full audit of scripts/, timers, and automation efficiency
**Trigger:** automation-reference.md was 2+ months stale; scripts directory bloat

---

## Audit Summary

### What was done

1. **Archived 22 scripts** — one-off fixes, applied migrations, completed tests, and superseded tools moved to `scripts/archived/`. Reduced active scripts from ~77 to 55.

2. **Rewrote automation-reference.md** — complete overhaul:
   - Added 14 undocumented timers (was 11, now 25 documented)
   - Added 32 previously undocumented scripts
   - Simplified from 10 tiers to functional categories
   - Documented update workflow (6-script chain that was completely undocumented)
   - Documented analytics subdirectory and security subdirectory
   - Removed stale references (claude-code-analyzer skill, etc.)

3. **Cross-reference validation** — verified no active script, timer, or skill references any archived script.

### Key findings

| Metric | Before | After |
|--------|--------|-------|
| Active scripts in scripts/ | ~77 | 55 |
| Documented timers | 11 | 25 |
| Documented scripts | ~40 | 55 + subdirectories |
| Archived scripts | 6 | 28 |
| Tier structure | 10 tiers | 12 functional categories |

---

## Automation Improvement Proposals

### Proposal 1: Reduce dependency-metrics-export frequency (5 min → 15 min)

**Problem:** `dependency-metrics-export.timer` runs every 5 minutes (288 times/day), consuming ~2.6s CPU per run = **12.5 minutes of CPU per day**. But the dependency graph it exports only changes when services are added or removed — roughly once per month.

**Evidence:**
- `dependency-graph.json` was last modified at 06:03 today (once daily by `discover-dependencies.sh`)
- The 5-minute export just re-reads the same JSON file and writes the same Prometheus metrics
- 20MB memory per run is modest, but the CPU cost adds up

**Proposal:** Change timer from `OnCalendar=*:0/5` to `OnCalendar=*:0/15` (every 15 minutes). Dependency metrics don't need sub-minute freshness — a 15-minute scrape interval is more than adequate for a graph that changes monthly.

**Savings:** ~8 minutes CPU/day, 192 fewer process spawns/day.

**Risk:** Minimal. Prometheus scrape interval is typically 15-60s, but the metrics themselves are almost always static. Alert-worthy dependency changes (service crashes) are already caught by container healthchecks within seconds.

---

### Proposal 2: Make autonomous-operations conditional on predictive-maintenance output

**Problem:** `autonomous-operations.timer` runs daily at 06:30 and consistently finds "No actions to execute." Yet it consumes **up to 3.3GB memory peak** and **5.7s CPU** per run. It hasn't taken a single autonomous action since 2025-12-24 (over 2 months of daily no-ops).

**Evidence:**
```
feb. 25: No actions to execute (2.4G memory peak)
feb. 26: No actions to execute (391M memory peak)
feb. 27: No actions to execute (3.3G memory peak, 5.7s CPU)
```

The memory spikes suggest it's running full system assessment (`autonomous-check.sh`) even when there's nothing to act on.

**Proposal:** Add a lightweight pre-check gate. Before running the full OODA assessment, check if any upstream signal indicates action might be needed:
1. Check if `predictive-maintenance-check` (06:00) found anything critical
2. Check if `daily-drift-check` (06:00) found drift
3. Check if any alert is currently firing
4. If all clear, skip the expensive assessment entirely

Implementation sketch:
```bash
# In autonomous-execute.sh, add early-exit check:
PRED_LOG=$(ls -t .claude/data/remediation-logs/predictive-maintenance-*.log | head -1)
DRIFT_STATUS=$(journalctl --user -u daily-drift-check.service -n 5 --no-pager | grep -c "DRIFT DETECTED")
FIRING=$(curl -s http://localhost:9093/api/v2/alerts | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if grep -q "No critical predictions" "$PRED_LOG" && [ "$DRIFT_STATUS" -eq 0 ] && [ "$FIRING" -eq 0 ]; then
    echo "All signals clear, skipping full assessment"
    exit 0
fi
```

**Savings:** ~3GB memory peak and ~5s CPU daily when system is healthy (which is most days). The full assessment still runs when something actually needs attention.

**Risk:** Low. We're only skipping the assessment when three independent signals all agree the system is healthy. Any actual problem (drift, resource pressure, firing alert) still triggers the full OODA loop.

---

### Proposal 3: Add remediation log rotation

**Problem:** Remediation logs accumulate indefinitely. Currently **99 log files** spanning from 2025-11-18 to present. Most are daily `predictive-maintenance` logs that say "No critical predictions. System healthy." These will grow ~365 files/year.

**Evidence:**
```
.claude/data/remediation-logs/: 99 log files
- 77 predictive-maintenance (daily, mostly "system healthy")
- 10 database-maintenance (weekly)
- 6 drift-reconciliation (historical, 2025-11)
- 4 slo-violation-remediation (historical)
- 3 disk-cleanup (historical)
```

**Proposal:** Add remediation log rotation to `maintenance-cleanup.sh`:
```bash
# Rotate remediation logs older than 90 days
find .claude/data/remediation-logs/ -name "*.log" -mtime +90 -delete

# Compress logs older than 30 days
find .claude/data/remediation-logs/ -name "*.log" -mtime +30 -exec gzip {} \;
```

**Savings:** Prevents unbounded log growth. Current disk impact is small (~100 files), but this is about good hygiene before it becomes a problem.

**Risk:** None for operational logs. The monthly analytics reports (`analytics/generate-monthly-report.sh`) only look at the last month's data.

---

### Proposal 4: Consolidate daily morning Discord notifications

**Problem:** Between 06:00-07:00, up to 5 separate Discord notifications can fire:
1. `daily-drift-check` (06:00) — if drift found
2. `daily-resource-forecast` (06:05) — if concerning
3. `autonomous-operations` (06:30) — if action taken
4. `daily-error-digest` (07:00) — if errors > threshold
5. `auto-doc-update` — no Discord, but runs in the same window

In practice, most mornings produce 0-1 notifications (the system is healthy). But on a bad day, this is a notification storm from 5 separate scripts.

**Proposal:** Create a single **daily morning digest** that aggregates the output of drift, forecast, errors, and autonomous ops into one Discord message. Individual scripts continue to run separately (preserving independent scheduling and logging), but Discord notification is consolidated.

Implementation approach:
- Each script writes a status summary to a shared `/tmp/daily-digest/` directory
- A new `daily-morning-digest.sh` runs at 07:30 (after all components finish + RandomizedDelaySec margin), reads the summaries, and sends one consolidated Discord message
- Individual scripts lose their `--notify` / Discord webhook calls

**Savings:** Reduces Discord noise from potentially 5 messages to 1. More actionable — single message with full context vs. scattered alerts.

**Risk:** Medium. Delays notification of drift/forecast from 06:00 to 07:30. Acceptable since these are informational, not incident alerts. Actual incidents still route through Alertmanager → PagerDuty/Discord in real-time.

---

### Proposal 5: Eliminate precompute-queries.sh or reduce to daily

**Problem:** `query-cache-refresh.timer` runs every 6 hours to pre-compute cached query results. But looking at the script, it calls `query-homelab.sh` with canned questions like "What services are using the most memory?" and "Show me disk usage." These are interactive queries that a human would run ad-hoc.

**Questions:**
- How often is `query-homelab.sh` actually used interactively? If rarely, the cache is being warmed for nobody.
- The cache could be generated once daily (at 07:00 alongside auto-doc-update) instead of 4 times/day.

**Proposal:** Reduce from every 6 hours to daily at 07:05 (right after auto-doc-update when fresh system data is available). If `query-homelab.sh` usage drops to near-zero, consider removing the timer entirely and letting queries compute on-demand (they take <10s).

**Savings:** 3 fewer runs/day. Minor CPU savings but reduces timer clutter.

**Risk:** Low. Queries that hit a stale cache will be ~6h stale instead of ~6h stale (same worst case). On-demand queries still work without the cache.

---

## Observations (Not Proposals)

### The autonomous operations framework is over-engineered for current stability

The full OODA framework (autonomous-check → autonomous-execute → verify-outcome → write-metrics) was built to handle a system that needed active intervention. In practice, the system has been stable enough that:

- Autonomous operations hasn't taken an action since 2025-12-24
- Predictive maintenance reports "system healthy" every day
- The only active remediation playbooks are `predictive-maintenance` (daily no-op) and `database-maintenance` (weekly VACUUM)

This isn't a problem to fix — the framework is valuable insurance for when things go wrong. But it's worth noting that 24 timers running daily/weekly/monthly represents significant complexity overhead for a system that mostly runs itself.

### Remediation analytics suite may be reporting on nothing

`scripts/analytics/` has 5 scripts for analyzing remediation effectiveness, trends, ROI, and recommendations. The `remediation-monthly-report.timer` generates monthly reports. But since remediation actions have been essentially zero since late December, these reports are likely empty or trivially "100% success rate on 0 actions."

Worth revisiting if/when the system becomes less stable and remediation playbooks see real use.

---

## Implementation Log

All 5 proposals implemented in a single session:

### Proposal 1: dependency-metrics-export timer → 15 min
- Changed `~/.config/systemd/user/dependency-metrics-export.timer` from `*:0/5` to `*:0/15`
- Saves ~8 min CPU/day, 192 fewer process spawns

### Proposal 2: Pre-check gate for autonomous operations
- Added `signals_all_clear()` function to `autonomous-execute.sh`
- Checks: predictive maintenance logs, drift status (journalctl), firing alerts (Alertmanager API)
- Skips full OODA assessment when all three signals are clear
- `--force` flag bypasses the gate for manual runs
- Saves ~3GB memory peak and ~5s CPU daily on healthy days

### Proposal 3: Remediation log rotation
- Added Section 5 to `maintenance-cleanup.sh`
- Deletes `.log` files >90 days, compresses >30 days with gzip
- Runs weekly with existing maintenance-cleanup timer

### Proposal 4: Consolidated morning Discord digest
- Created `scripts/daily-morning-digest.sh` with timer/service at 07:30
- Modified 4 scripts to write JSON status to `/tmp/daily-digest/`:
  - `daily-drift-check.sh` → `drift-check.json`
  - `daily-resource-forecast.sh` → `resource-forecast.json`
  - `autonomous-execute.sh` → `autonomous-ops.json`
  - `daily-error-digest.sh` → `error-digest.json`
- Digest script sends one Discord message if any issues, skips silently if all clear
- Critical events (circuit breaker, emergency stop) still send via autonomous-execute.sh directly

### Proposal 5: query-cache-refresh → daily at 07:05
- Changed `~/.config/systemd/user/query-cache-refresh.timer` from `00,06,12,18:00:00` to `07:05:00`
- Runs after auto-doc-update (07:00) when fresh system data is available
- Saves 3 unnecessary cache rebuilds per day

### Documentation
- Updated `automation-reference.md`: timer counts (26), frequencies, daily execution order, script descriptions
- Timer count: 25 → 26 (added daily-morning-digest)
- Script count: 55 → 56 (added daily-morning-digest.sh)
