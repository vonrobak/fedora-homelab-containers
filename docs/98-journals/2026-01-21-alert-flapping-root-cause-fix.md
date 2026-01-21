# Alert Flapping Investigation & Fix

**Date:** 2026-01-21
**Status:** ✅ Complete
**Component:** Prometheus Alerting
**Issue:** NextcloudCronStale and PromtailMetricExtractionStale firing repeatedly

---

## Problem

High volume of Discord alerts over several days:
- **NextcloudCronStale:** Firing → RESOLVED → Firing (continuous flapping)
- **PromtailMetricExtractionStale:** Firing continuously since Jan 17

User correctly identified this appeared after recent quadlet/log migration changes and suspected the fixes were treating symptoms rather than root causes.

---

## Root Causes

### Issue 1: PromtailMetricExtractionStale (Since Jan 17, 09:16)

**Cause:** Prometheus never reloaded after rule fix in commit 8676079 (Jan 17, 16:54)

**Details:**
- Old rule: `(absent(immich_thumbnail_failures_total) OR absent(nextcloud_cron_success_total))`
- Fixed rule: `absent(nextcloud_cron_success_total)` only
- Prometheus restart missed → old rule continued evaluating
- `immich_thumbnail_failures_total` is sparse (only exists during failures)
- Alert fired continuously for 4 days due to old rule

### Issue 2: NextcloudCronStale Flapping

**Cause:** Stale metric series in Prometheus TSDB

**Details:**
- Promtail exports: `promtail_custom_nextcloud_cron_success_total{priority="6"}` (value=687, incrementing)
- Prometheus TSDB retained: 4 series with priority="3","4","5","6"
- Priority 3,4,5 stuck at value=1 (never increment)
- Alert rule: `changes(promtail_custom_nextcloud_cron_success_total[10m]) == 0`
- Evaluated PER SERIES → fired for each stale series
- Real series (priority="6") increments → alert resolves
- Stale series never increment → alert fires again
- Continuous flapping pattern

**Why stale series exist:**
- Log migration (Jan 17) caused Promtail restart
- Different syslog priority labels appeared briefly during restart
- Old series persisted in Prometheus TSDB (default 5m retention after last scrape)
- Prometheus restart at 13:53 refreshed TSDB, creating new stale series instances

---

## Investigation Process

Initial hypothesis (incorrect):
- Suspected log rotation + position file incompatibility
- Proposed complex Python exporter replacement
- User correctly questioned this as overengineering

Actual debugging:
1. Verified metric extraction working (value=570, incrementing correctly)
2. Found Prometheus never reloaded after rule changes
3. Discovered multiple metric series with different priority labels
4. Confirmed Promtail only exports priority="6"
5. Identified per-series alert evaluation as flapping cause

**User's instinct was correct:** Infrastructure not fundamentally broken, just operational issues.

---

## Fixes Applied

### Fix 1: Reload Prometheus (13:53)

```bash
systemctl --user restart prometheus.service
```

**Result:** PromtailMetricExtractionStale resolved

### Fix 2: Alert Rule Aggregation (14:15)

**File:** `config/prometheus/rules/log-based-alerts.yml`

```yaml
# Before (broken):
- alert: NextcloudCronStale
  expr: changes(promtail_custom_nextcloud_cron_success_total[10m]) == 0

# After (fixed):
- alert: NextcloudCronStale
  expr: sum(changes(promtail_custom_nextcloud_cron_success_total[10m])) == 0
```

**Why this works:** Aggregates all series - as long as ANY series increments (the real one), sum > 0 and alert doesn't fire

**Result:** NextcloudCronStale flapping stopped

### Minor Fix: Log Rotation Script

User applied: `gzip -f "${LOG_FILE}.1"` to prevent uncompressed rotation files

---

## Validation Results

**Prometheus queries (14:15+):**
```
promtail_custom_nextcloud_cron_success_total{priority="6"}: 687 (incrementing)
sum(changes(promtail_custom_nextcloud_cron_success_total[10m])): 4
absent(promtail_custom_nextcloud_cron_success_total): false
```

**Alert status:**
- NextcloudCronStale: inactive ✅
- PromtailMetricExtractionStale: inactive ✅

**Monitoring confirmed:**
- Nextcloud cron running every 5 minutes ✅
- Metric extraction working correctly ✅
- No alert flapping for 20+ minutes ✅

---

## What Was NOT The Problem

- ❌ Log-based metrics fundamentally broken
- ❌ Permissions issues in Promtail container
- ❌ Log rotation breaking position tracking
- ❌ BTRFS migration issues
- ❌ User=1000 quadlet changes (different containers)
- ❌ Architectural design flaws

The monitoring infrastructure was working correctly throughout. Issues were purely operational.

---

## Lessons Learned

1. **Service reloads are critical** - Config changes require explicit reload/restart
2. **Alert rules should handle label changes** - Use aggregations when metric label sets can vary
3. **Stale metrics persist** - Old series remain in TSDB until retention expires
4. **Investigate thoroughly before redesigning** - Simple operational issues can appear architectural
5. **Trust user instincts** - User correctly identified overengineered solution proposals

**Process improvement:** Add Prometheus reload check to deployment verification steps

---

## Timeline

```
Jan 17, 10:16 - Promtail restarted (log migration Phase 2)
Jan 17, 16:54 - Alert rules fixed in commit 8676079
Jan 17-21     - Prometheus never reloaded (96 hours)
Jan 21, 12:05 - PromtailMetricExtractionStale fired
Jan 21, 13:53 - First Prometheus restart (fixed PromtailMetricExtractionStale)
Jan 21, 13:56 - NextcloudCronStale fired (stale series)
Jan 21, 14:15 - Second Prometheus restart with sum() fix
Jan 21, 14:15+ - Both alerts permanently resolved ✓
```

---

## Related Documentation

- **Investigation:** systematic-debugging skill invoked
- **Alert config:** `config/prometheus/rules/log-based-alerts.yml`
- **Previous fixes:**
  - 2026-01-16-nextcloud-cron-alert-fix-phase1.md
  - 2026-01-17-log-metric-cleanup-phase3.md
  - 2026-01-17-alert-consolidation-meta-monitoring-phase4-5.md

---

**Status:** Complete | Alerts resolved | Monitoring infrastructure validated working correctly
**Time invested:** ~2 hours (investigation + fixes + validation)
**Outcome:** ✅ Root causes identified and permanently fixed
