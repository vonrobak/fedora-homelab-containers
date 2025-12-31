# SLO Reporting Deep Dive - Issues & Fixes

**Date:** December 31, 2025
**Investigation:** SLO reporting logic, error budget calculations, service availability
**Status:** Critical issues identified with fixes proposed

---

## Executive Summary

Investigation revealed **3 critical bugs** in SLO reporting and **4 out of 5 services failing SLO targets**. The monthly report incorrectly shows "All SLOs Met" when in reality all user-facing services are significantly below their targets due to development/testing work.

**Key Findings:**
1. ❌ **Compliance metrics return null** - Recording rule bug prevents detection of SLO violations
2. ❌ **Error budget displays as negative percentages** - Confusing representation of over-budget state
3. ❌ **Overall status logic broken** - Reports "All SLOs Met" despite 4 violations
4. ⚠️ **Nextcloud: 1727 HTTP 503 errors** (7 days) - Highest error contributor
5. ⚠️ **Immich: 93.67% availability** vs 99.9% target - Worst performer (6.33% error rate!)
6. ✅ **Loki healthcheck issue identified** - Missing `wget` in container (cosmetic, service works)

---

## Bug #1: Compliance Metrics Return Null

### Problem

All compliance metrics (`slo:*:availability:compliant`) return `null` instead of 0 or 1.

### Root Cause

Prometheus recording rule uses comparison operator without `bool` modifier:

**Current (broken):**
```yaml
- record: slo:jellyfin:availability:compliant
  expr: |
    slo:jellyfin:availability:actual >= slo:jellyfin:availability:target
```

**Prometheus behavior:**
- If comparison is `true`: Returns the metric with value 1
- If comparison is `false`: Returns **empty vector** (no data)

When services are below target (comparison is false), the metric doesn't exist, so monthly report reads `null`.

### Impact

- Monthly report cannot determine SLO compliance
- Violation count always 0
- Overall status incorrectly shows "All SLOs Met"

### Fix

Add `bool` modifier to comparison operators in `/home/patriark/containers/config/prometheus/rules/slo-recording-rules.yml`:

```yaml
# Lines 172-174, 188-190, 204-206, 220-222, 232-234
- record: slo:jellyfin:availability:compliant
  expr: |
    slo:jellyfin:availability:actual >= bool slo:jellyfin:availability:target
```

This makes the comparison return `1` (true) or `0` (false) instead of metric-or-nothing.

**Apply to all 5 services:** Jellyfin, Immich, Authelia, Nextcloud, Traefik

---

## Bug #2: Error Budget Negative Percentages

### Problem

Error budget remaining displays as large negative percentages:
- Jellyfin: -281%
- Immich: **-6229%**
- Authelia: -474%
- Nextcloud: -715%

### Root Cause

The error budget formula is **mathematically correct** but handles over-budget scenarios poorly for display:

```yaml
# Budget consumed (fraction of budget used)
error_budget:jellyfin:availability:budget_consumed
expr: |
  clamp_min(
    (1 - slo:jellyfin:availability:actual) / (1 - slo:jellyfin:availability:target),
    0
  )

# Budget remaining (1.0 = 100% remaining, 0.0 = exhausted)
error_budget:jellyfin:availability:budget_remaining
expr: |
  clamp_max(1 - error_budget:jellyfin:availability:budget_consumed, 1)
```

**Example (Immich):**
- Target: 99.9% (error budget = 0.1%)
- Actual: 93.67% (actual errors = 6.33%)
- Budget consumed = 6.33% / 0.1% = **63.3x over budget**
- Budget remaining = 1 - 63.3 = **-62.3** (-6230% when displayed)

### Impact

- Confusing display in Discord reports
- Negative percentages don't clearly communicate "you're way over budget"
- Hard to understand severity at a glance

### Fix Option 1: Clamp Display to 0%

Modify monthly-slo-report.sh `format_pct()` function to show 0% minimum:

```bash
format_pct() {
    local val="$1"
    if [ "$val" = "null" ] || [ -z "$val" ]; then
        echo "N/A"
    else
        # Clamp to 0% minimum for cleaner display
        local pct=$(echo "$val * 100" | bc -l)
        if (( $(echo "$pct < 0" | bc -l) )); then
            echo "0.00% (exhausted)"
        else
            echo "$pct" | awk '{printf "%.2f%%", $1}'
        fi
    fi
}
```

**Display:**
- Jellyfin: `0.00% (exhausted)` instead of `-281%`
- Immich: `0.00% (exhausted)` instead of `-6229%`

### Fix Option 2: Show Over-Budget Multiple

Display how many times over budget:

```bash
format_error_budget() {
    local remaining="$1"
    local consumed="$2"  # Need to pass both values

    if [ "$remaining" = "null" ] || [ -z "$remaining" ]; then
        echo "N/A"
    elif (( $(echo "$remaining < 0" | bc -l) )); then
        # Over budget - show multiple
        local multiple=$(echo "scale=1; $consumed" | bc -l)
        echo "0% (${multiple}x over budget)"
    else
        echo "$remaining" | awk '{printf "%.2f%%", $1 * 100}'
    fi
}
```

**Display:**
- Jellyfin: `0% (3.8x over budget)`
- Immich: `0% (63.3x over budget)` - **clearly severe**
- Nextcloud: `0% (8.2x over budget)`

**Recommendation:** Use Option 2 (shows severity clearly)

---

## Bug #3: Overall Status Logic Broken

### Problem

Report shows `"All SLOs Met ✅"` when 4 out of 5 services are violating SLOs.

### Root Cause

Lines 110-114 in monthly-slo-report.sh:

```bash
overall_violations=0
[ "$jellyfin_compliant" = "0" ] && ((overall_violations++)) || true
[ "$immich_compliant" = "0" ] && ((overall_violations++)) || true
[ "$authelia_compliant" = "0" ] && ((overall_violations++)) || true
[ "$traefik_compliant" = "0" ] && ((overall_violations++)) || true
[ "$nextcloud_compliant" = "0" ] && ((overall_violations++)) || true
```

Since all `*_compliant` variables are `null` (Bug #1), the comparisons all fail, so `overall_violations` stays at 0.

### Impact

- Report always shows "All SLOs Met" regardless of actual state
- No visibility into service reliability problems

### Fix

After fixing Bug #1 (compliance metrics), this will automatically work. But add defensive check:

```bash
overall_violations=0
[ "$jellyfin_compliant" = "0" ] && ((overall_violations++)) || true
[ "$jellyfin_compliant" = "null" ] && ((overall_violations++)) || true  # Treat null as violation
[ "$immich_compliant" = "0" ] && ((overall_violations++)) || true
[ "$immich_compliant" = "null" ] && ((overall_violations++)) || true
# ... same for all services
```

**Better approach:** Fix Bug #1 first, then this works as designed.

---

## Service Availability Analysis

### Current State (30-Day Rolling Window)

| Service | Target | Actual | Status | Error Budget | Top Errors (7d) |
|---------|--------|--------|--------|--------------|-----------------|
| **Jellyfin** | 99.5% | 98.09% | ❌ Violated | 0% (3.8x over) | 321 x HTTP 404, 52 x HTTP 500 |
| **Immich** | 99.9% | 93.67% | ❌ **CRITICAL** | 0% (63x over) | 369 x HTTP 500, 205 x HTTP 0 |
| **Authelia** | 99.9% | 99.41% | ❌ Violated | 0% (5.7x over) | ~40 errors (various) |
| **Nextcloud** | 99.5% | 95.92% | ❌ Violated | 0% (8.2x over) | **1727 x HTTP 503** |
| **Traefik** | 99.95% | 99.998% | ✅ **Met** | ~60% remaining | Minimal errors |

### Key Insights

1. **Only Traefik meets SLO** - Gateway is reliable (99.998%)
2. **Immich is worst performer** - 93.67% availability (6.33% error rate!)
   - 369 HTTP 500 errors (internal server errors)
   - 205 HTTP 0 errors (connection timeouts/failures)
   - Likely due to development work mentioned by user
3. **Nextcloud has highest error volume** - 1727 HTTP 503 errors in 7 days
   - HTTP 503 = Service Unavailable
   - Suggests service restarts, overload, or dependencies down
4. **Jellyfin 404s likely normal** - Media requests for non-existent files
5. **All services exhausted error budgets** - Development/testing impact

### Error Patterns (Last 7 Days)

```
nextcloud@file - HTTP 503: 1727 errors  ← Highest volume
immich@file - HTTP 500: 369 errors
jellyfin@file - HTTP 404: 321 errors
immich@file - HTTP 0: 205 errors       ← Connection failures
```

**HTTP Status Code Meanings:**
- `503 Service Unavailable` - Service down, restarting, or dependencies unavailable
- `500 Internal Server Error` - Application crash/bug
- `404 Not Found` - Resource doesn't exist (often normal for media)
- `0 Connection Failed` - Timeout, network issue, or service completely down

---

## Loki Health Check Investigation

### Problem

Loki health check returns `unhealthy` despite service running normally for 3+ days.

### Root Cause

Loki container quadlet defines health check using `wget`:

```yaml
# Line 24 in ~/.config/containers/systemd/loki.container
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1
```

But Grafana's Loki container image doesn't include `wget` (minimal image).

**Evidence:**
- `podman exec loki curl http://localhost:3100/ready` → "curl: command not found"
- `podman exec loki wget http://localhost:3100/ready` → "wget: command not found"
- `podman healthcheck run loki` → "unhealthy"
- Service logs show Loki working normally (flushing streams, processing queries)

### Impact

**Low** - Cosmetic issue only. Service functions normally:
- Loki is running and processing logs
- Grafana can query Loki successfully
- Promtail is shipping logs
- Only healthcheck reporting fails

### Fix

Change healthcheck to use a command that exists in the container. Options:

**Option 1: Use netstat (likely available)**
```yaml
HealthCmd=netstat -tuln | grep 3100 || exit 1
```

**Option 2: Use process check**
```yaml
HealthCmd=pgrep -x loki || exit 1
```

**Option 3: Remove healthcheck** (Loki runs as single process, systemd restart handles failures)
```yaml
# Comment out or remove HealthCmd lines
```

**Recommendation:** Option 3 (remove healthcheck)
- Systemd already monitors the process
- If Loki crashes, systemd restarts it (`Restart=on-failure`)
- Healthchecks add complexity for minimal value in single-process containers

---

## Recommendations

### Priority 1: Fix SLO Reporting (High Priority)

**Impact:** Currently unable to track service reliability accurately

1. **Fix compliance metrics** (15 min)
   - Edit `/home/patriark/containers/config/prometheus/rules/slo-recording-rules.yml`
   - Add `bool` modifier to all 5 compliance rules (lines 172-234)
   - Reload Prometheus: `podman exec prometheus kill -SIGHUP 1`
   - Wait 2 minutes for recording rules to evaluate
   - Verify: `scripts/monthly-slo-report.sh` (should show violations)

2. **Fix error budget display** (10 min)
   - Edit `scripts/monthly-slo-report.sh`
   - Update `format_pct()` function to handle negative values
   - Show over-budget multiple for clarity
   - Test: Run script and check Discord output

3. **Update SLO framework docs** (5 min)
   - Remove OCIS references (line 82-89)
   - Replace with Nextcloud
   - Document known limitations during development periods

**Total Time:** 30 minutes

### Priority 2: Investigate Service Reliability (Medium Priority)

**Impact:** Services below reliability targets, user experience degraded

1. **Nextcloud HTTP 503 errors** (1-2 hours)
   - Query Loki for 503 error timeline: When did they occur?
   - Check Nextcloud logs for root cause
   - Possibilities:
     - Service restarts during updates/config changes
     - PHP-FPM exhaustion (need to increase workers?)
     - Database connection issues (PostgreSQL/Redis)
   - **Hypothesis:** Development/testing causing restarts

2. **Immich HTTP 500 + Connection Errors** (1 hour)
   - 93.67% availability is **very low** for production
   - Check Immich logs for internal errors
   - Check if related to ML/machine learning container issues
   - User mentioned "testing and development" - likely explains this
   - **Recommendation:** Accept during development, track improvement post-stabilization

3. **Set realistic SLO targets for development period** (30 min)
   - Current targets assume production stability
   - Consider temporary relaxed targets:
     - Immich: 95% (from 99.9%) during development
     - Nextcloud: 97% (from 99.5%) during development
   - Restore production targets once stable

**Total Time:** 2.5-3.5 hours

### Priority 3: Fix Loki Healthcheck (Low Priority)

**Impact:** Cosmetic only, service works fine

- Remove healthcheck from Loki quadlet
- Rely on systemd process monitoring
- **Time:** 2 minutes

---

## Proposed Action Plan

### Immediate (Tonight, <30 min)

1. ✅ Fix compliance metric recording rules (add `bool` modifier)
2. ✅ Fix error budget display in monthly report script
3. ✅ Test monthly report generation
4. ✅ Commit fixes to Git

### Short-Term (Next Week)

1. Investigate Nextcloud 503 errors (check logs, identify pattern)
2. Review Immich stability (errors correlate with development work?)
3. Decide on adjusted SLO targets during development vs production
4. Remove Loki healthcheck (cosmetic fix)

### Long-Term (January 2026)

1. Establish development vs production SLO policies
   - Different targets during active development
   - Stricter targets for production services
2. Set up SLO burn-rate alerting (already configured, but verify)
3. Monthly SLO reviews to track improvement
4. Document service-specific reliability patterns

---

## Files Requiring Changes

### 1. Prometheus SLO Recording Rules
**File:** `/home/patriark/containers/config/prometheus/rules/slo-recording-rules.yml`

**Lines to modify:**
- Line 172-174: Jellyfin compliance
- Line 188-190: Immich compliance
- Line 204-206: Authelia compliance
- Line 220-222: Nextcloud compliance
- Line 232-234: Traefik compliance

**Change:**
```yaml
# OLD
- record: slo:jellyfin:availability:compliant
  expr: |
    slo:jellyfin:availability:actual >= slo:jellyfin:availability:target

# NEW
- record: slo:jellyfin:availability:compliant
  expr: |
    slo:jellyfin:availability:actual >= bool slo:jellyfin:availability:target
```

### 2. Monthly SLO Report Script
**File:** `/home/patriark/containers/scripts/monthly-slo-report.sh`

**Function to modify:** `format_pct()` (lines 67-75)

**New implementation:**
```bash
# Format percentage with over-budget handling
format_pct() {
    local val="$1"
    if [ "$val" = "null" ] || [ -z "$val" ]; then
        echo "N/A"
    else
        local pct=$(echo "$val * 100" | bc -l 2>/dev/null || echo "0")
        if (( $(echo "$pct < 0" | bc -l 2>/dev/null || echo "0") )); then
            echo "0.00% (exhausted)"
        else
            printf "%.2f%%" "$pct"
        fi
    fi
}
```

### 3. SLO Framework Documentation (Optional)
**File:** `/home/patriark/containers/docs/40-monitoring-and-documentation/guides/slo-framework.md`

**Lines to update:** 82-89 (replace OCIS with Nextcloud)

### 4. Loki Healthcheck (Optional)
**File:** `/home/patriark/.config/containers/systemd/loki.container`

**Lines to remove:** 23-27 (HealthCmd and related config)

---

## Testing Validation

After applying fixes, validate with these commands:

```bash
# 1. Reload Prometheus rules
podman exec prometheus kill -SIGHUP 1
sleep 120  # Wait for recording rules to evaluate

# 2. Check compliance metrics (should now show 0 or 1, not null)
curl -s 'http://localhost:9090/api/v1/query?query=slo:jellyfin:availability:compliant' | jq '.data.result[0].value[1]'

# 3. Run monthly SLO report
~/containers/scripts/monthly-slo-report.sh

# 4. Verify Discord report shows:
#    - Overall status: "Multiple SLOs Violated" (not "All SLOs Met")
#    - Error budgets: "0.00% (exhausted)" or similar (not negative %)
#    - Compliance: Red X for Jellyfin, Immich, Authelia, Nextcloud
```

---

## Conclusion

The SLO reporting system has 3 critical bugs preventing accurate reliability tracking, all of which can be fixed in ~30 minutes. The underlying service reliability issues (Nextcloud 503s, Immich errors) are real but likely attributable to the development/testing work mentioned by the user.

**Key Takeaways:**
1. **Fix the reporting first** - Can't manage what you can't measure accurately
2. **Accept development-period instability** - 93-98% availability is expected during active development
3. **Track improvement over time** - January reports will show if services stabilize post-development
4. **Loki is fine** - Healthcheck issue is cosmetic, service works perfectly

**Recommended Focus:** Fix reporting bugs tonight, investigate service reliability next week when you have more time.

---

**Report Generated:** 2025-12-31 22:00 CET
**Investigator:** Claude Sonnet 4.5
**Next Review:** 2026-01-31 (February SLO report)
