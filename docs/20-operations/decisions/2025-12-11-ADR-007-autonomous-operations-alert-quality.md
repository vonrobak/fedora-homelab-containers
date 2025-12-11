# ADR-007: Autonomous Operations Alert Quality & Prediction System

**Date:** 2025-12-11
**Status:** Accepted
**Decided by:** System architect
**Implements:** Integrated improvements from autonomous operations analysis

---

## Context

After 18 autonomous operation checks with 0 actions taken and persistent warning fatigue (4 warnings for 7+ days), a comprehensive analysis revealed three interconnected issues:

### Issue 1: Autonomous Passivity
- **Observation:** 18 checks, 0 actions (correct - system healthy)
- **Problem:** Swap cleanup disabled despite swap at 7824MB (exceeds 6289MB threshold)
- **Root Cause:** `auto_resource_pressure: false` in preferences.yml
- **Reality:** 0 actions is GOOD (healthy system), but resource-pressure playbook was unnecessarily disabled

### Issue 2: Persistent Warning Fatigue
- **Observation:** Same 4 warnings appearing for 7+ consecutive days
- **Breakdown:**
  - W004: Swap usage high (REAL, but below autonomous action threshold 75%)
  - W006: Certificate file not found (FALSE POSITIVE - permissions issue)
  - W007: Prometheus health check failed (FALSE POSITIVE - curl not in container)
  - W009: Loki health check failed (FALSE POSITIVE - curl not in container)
- **Impact:** Health score stuck at 80, alert fatigue, reduced signal-to-noise ratio

### Issue 3: Broken Prediction System
- **Observation:** Daily forecast showing "Warning: Prediction script had errors" for 7+ days
- **Root Causes:**
  1. `predict-resource-exhaustion.sh` capturing stderr with JSON (parse failures)
  2. Wrong JSON field name (`days_until_critical` vs `days_until_90pct`)
  3. `precompute-queries.sh` never scheduled (no cron/timer)
  4. Query cache 23 days stale
- **Impact:** No advance warning of resource exhaustion, stale query responses

---

## Decision

**We will implement a three-phase integrated improvement:**

1. **Enable swap cleanup automation** (ready to act when needed)
2. **Fix false positives + add intelligent warning management** (eliminate crying wolf)
3. **Repair prediction infrastructure** (see problems coming)

**Philosophy:** Keep current action thresholds, fix detection quality, acknowledge 0 actions = healthy system.

---

## Implementation

### Phase 1: Enable Swap Cleanup (Activation)

**Change:**
```yaml
# preferences.yml
auto_resource_pressure: true  # Was: false
```

**Rationale:**
- Swap at 7824MB exceeds warning threshold (6289MB / 20% of memory)
- Below autonomous action threshold (75% of ~47GB swap = 35GB)
- Enable playbook so system acts IF swap reaches 75%
- W004 becomes "known issue" since it's below action threshold

### Phase 2: Fix False Positives & Add Warning Management

**2A. Certificate Detection (W006)**

**Problem:** Script checking file with restricted permissions (acme.json is 600 for security)

**Solution:** HTTPS fallback method
```bash
# If acme.json not readable, verify HTTPS is working
curl -sf https://traefik.patriark.org | openssl x509 -noout -dates
```

**Result:** Certificate verified as valid (40 days remaining)

**2B. Health Check Detection (W007/W009)**

**Problem:** Using `podman exec <container> curl ...` but curl not installed in containers

**Solution:** Use podman's built-in healthcheck status
```bash
# Old: podman exec prometheus curl http://localhost:9090/-/healthy
# New: podman inspect prometheus --format '{{.State.Health.Status}}'
```

**Added:** Grace periods (15min system boot, 5min service start) to handle legitimate startup delays

**Result:** False positives eliminated, Prometheus and Loki showing healthy

**2C. Known Issues Framework**

**New Component:** `~/.claude/context/known-issues.yml`

**Purpose:** Document warnings that are expected/acceptable to prevent alert fatigue

**Features:**
- Warnings tagged with 🔕 [KNOWN ISSUE] in daily reports
- Don't reduce health score
- Example: W004 (swap high but below action threshold)

**Format:**
```yaml
known_issues:
  - code: W004
    message: "Swap usage high (below autonomous action threshold)"
    reason: "System uses swap for inactive pages. Cleanup triggers at 75%."
    suppress_until: "2025-12-31"
    suppress_in_reports: false  # Still show, just marked as "known"
```

**Integration:**
- `homelab-intel.sh`: Load and tag known issues
- `weekly-intelligence-report.sh`: Check for persistent warnings

**2D. Persistent Warning Escalation**

**New Feature:** 7-day persistence check in weekly intelligence report

**Logic:**
1. Check last 7 daily intel reports for each warning code
2. If warning appears in ALL 7 reports AND not in known-issues.yml
3. Escalate to Discord with "PERSISTENT UNKNOWN WARNING" alert

**Purpose:** Surface systemic issues that aren't being addressed

### Phase 3: Repair Prediction System

**3A. Fix daily-resource-forecast.sh**

**Problem 1:** Capturing stderr with stdout (mixing log messages with JSON)
```bash
# Old: "$PREDICT_SCRIPT" --output json > "$PREDICT_OUTPUT" 2>&1
# New: "$PREDICT_SCRIPT" --output json 2>/dev/null > "$PREDICT_OUTPUT"
```

**Problem 2:** Wrong JSON field name
```bash
# Old: jq -r '.disk.days_until_critical // "999"'
# New: jq -r '.days_until_90pct // "999"'
```

**Result:** Daily forecast now runs successfully (exit code 0)

**3B. Schedule precompute-queries.sh**

**Created:** `query-cache-refresh.timer` and `query-cache-refresh.service`

**Schedule:** Every 6 hours (00:00, 06:00, 12:00, 18:00)

**Rationale:**
- Query cache supports natural language system queries
- 6-hour refresh keeps responses current without excessive overhead
- Systemd timer more reliable than cron for user services

**3C. Verify daily-resource-forecast.timer**

**Status:** Already enabled and working
- Runs daily at 06:05 (after drift check at 06:00)
- Now succeeds after fixing the script

---

## Rationale

### Why Fix, Not Simplify?

The sophisticated prediction infrastructure (linear regression, query caching) is **appropriate** for the problem:
- Resource trends ARE linear over 7-14 day windows
- Query cache solves real performance problems
- Infrastructure is sound, just needed repair

### Why Keep Current Thresholds?

**User-selected approach:** "Keep current thresholds, acknowledge 0 actions = healthy"

- Disk threshold (80%) is appropriate for cleanup timing
- Swap threshold (75%) allows OS to use swap for inactive pages
- Memory threshold (90%) gives adequate warning time

### Why Suppress Known Issues?

**Problem:** False positives reduce trust in monitoring
**Solution:** Document expected behavior explicitly
**Result:** Health score reflects TRUE system state (80 → 90)

---

## Consequences

### What Becomes Better

✅ **Health Score Accuracy:** 80 → 90 (reflects reality, not false positives)
✅ **Alert Quality:** 3 false positives eliminated (W006, W007, W009)
✅ **Prediction System:** Working forecasts (599 days to 90% disk)
✅ **Query Cache:** Fresh responses (<6h old) from 23-day stale
✅ **Persistent Warning Detection:** 7-day escalation catches systemic issues
✅ **Known Issue Transparency:** Expected warnings clearly marked

### What Changes

⚠️ **Autonomous Behavior:** Will act when swap reaches 75% (was disabled)
⚠️ **Warning Interpretation:** Some warnings now marked as "known" vs "actionable"
⚠️ **Alert Volume:** Persistent warnings escalate to Discord (new alerts possible)

### Metrics Improvement

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Health Score | 80 | 90 | +10 points |
| False Positives/Day | 3 | 0 | -100% |
| Prediction Success | 0% | 100% | Fixed |
| Query Cache Age | 23 days | <6 hours | -96% |
| Autonomous Actions | 0/18 | 0/18 | No change (correct) |

### Known Issues After Implementation

**W004 (Swap Usage High):**
- **Status:** Known issue (below 75% action threshold)
- **Tagged:** 🔕 [KNOWN ISSUE]
- **Action:** Auto-cleanup will trigger IF swap reaches 75%
- **Rationale:** Linux uses swap for inactive pages, this is expected

**No Other Persistent Warnings:** W006, W007, W009 eliminated

---

## Alternatives Considered

### Alternative 1: Lower Autonomous Thresholds
**Rejected:** Would trigger unnecessary actions, system is healthy at current levels

### Alternative 2: Simplify Prediction System
**Rejected:** Sophisticated infrastructure is appropriate, just needed repair

### Alternative 3: Hide All Warnings
**Rejected:** Would mask real issues, known-issues framework is more nuanced

### Alternative 4: Don't Enable Swap Cleanup
**Rejected:** Playbook exists and is tested, might be needed in future

---

## Validation Results

### Immediate (2025-12-11)

```bash
# Health score improved
Health Score: 90/100 ✅

# False positives eliminated
No W006, W007, W009 warnings ✅

# Prediction system working
$ predict-resource-exhaustion.sh --type all
Current usage: 61.4%
Days until 90%: 599
Exit code: 0 ✅

# Query cache timer scheduled
NEXT: Thu 2025-12-11 18:00:10 CET
query-cache-refresh.timer ✅

# Known issues tagged
[W004] Swap usage high 🔕 [KNOWN ISSUE] ✅
```

### Future Validation (7+ days)

**Weekly Intelligence Report will test:**
- Persistent warning detection (if any new warnings persist 7 days)
- Known-issues suppression (W004 should not escalate)
- Query cache freshness (multiple successful refreshes)

**Autonomous Operations will test:**
- Swap cleanup trigger (if swap reaches 75%)
- Circuit breaker remains stable
- Decision confidence remains appropriate

---

## References

- **Implementation Plan:** `/home/patriark/.claude/plans/iridescent-forging-pudding.md`
- **Automation Reference:** `docs/20-operations/guides/automation-reference.md` (updated 2025-12-11)
- **Autonomous Operations:** `docs/20-operations/guides/autonomous-operations.md`
- **Known Issues YAML:** `~/.claude/context/known-issues.yml` (created 2025-12-11)
- **Query Cache Timer:** `~/.config/systemd/user/query-cache-refresh.timer` (created 2025-12-11)

---

## Review Schedule

**Next Review:** 2026-01-11 (30 days)

**Review Criteria:**
1. Has autonomous system taken any actions? (Were they appropriate?)
2. Any new persistent warnings emerged?
3. Prediction accuracy over 30 days?
4. Query cache hit rates and freshness?
5. Should any known-issues be removed or added?

---

**Status:** Implemented and validated
**Owner:** Homelab infrastructure (patriark)
**Impact:** High (improves monitoring reliability and autonomous operations readiness)
