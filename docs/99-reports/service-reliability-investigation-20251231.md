# Service Reliability Investigation - December 31, 2025

**Investigation Date:** 2025-12-31
**Scope:** Nextcloud 503 errors (1727) and Immich availability issues (93.67%)
**Status:** ✅ Complete - Root causes identified

## Executive Summary

Investigation of December SLO violations revealed **permission-related issues** as the primary root cause for both Nextcloud and Immich errors, compounded by manual service restarts outside maintenance windows. Both services have `AutoUpdate=registry` enabled with weekly updates scheduled for Sundays at 03:00, which is appropriate.

**Key Finding:** The low availability metrics were caused by a combination of:
1. **External storage permission errors** (Nextcloud)
2. **Thumbnail permission errors** (Immich)
3. **Manual service restarts** during testing/development work (Dec 28, Dec 31)
4. **Database deadlocks** under concurrent load (Nextcloud)

**Impact:**
- Nextcloud: 1727 HTTP 503 errors over 7 days (96.24% availability)
- Immich: 369 HTTP 500 errors + 205 timeouts (93.67% availability)

## Timeline of Events

### December 28 (Saturday)

**03:00** - Scheduled podman-auto-update (no updates available)

**19:30** - Immich thumbnail permission errors begin:
```
ERROR EACCES: permission denied, access '/usr/src/app/upload/thumbs/.../thumbnail.webp'
```

**19:46** - Manual Immich restart (likely user fixing permissions)
- **Result:** 342 HTTP 500 errors during restart window

### December 29 (Sunday)

**Residual Immich errors:** 27 HTTP 500 errors (clearing permission issue backlog)

### December 30 (Monday)

**Immich clean:** 0 errors (permission issues resolved)

### December 31 (Tuesday)

**02:19:18** - Nextcloud manual restart
**02:19:34** - Immich-server manual restart (16 seconds later)
- **Note:** Outside scheduled auto-update window (03:00)
- **Cause:** Unknown (user may have triggered manually)

### Continuous Issues (Dec 25-31)

**Nextcloud external storage errors:**
- Permission denied on `/external/downloads/`
- Permission denied on `/external/music/`
- Database deadlocks during file operations
- Storage unavailable exceptions
- **6 service restarts** over 7 days (Dec 29, 30, 31 multiple times)

## Root Cause Analysis

### Nextcloud 503 Errors (1727 occurrences)

**Primary Root Cause:** External storage permission misconfiguration

**Contributing Factors:**

1. **External Storage Permission Errors**
   - `/external/downloads/Data Dump/twitter-2024-10-18.../assets` - Permission denied
   - `/external/music/` - Permission denied
   - Results in "Storage not available" exceptions

2. **Database Deadlocks**
   ```
   SQLSTATE[40001]: Serialization failure: 1213 Deadlock found
   when trying to get lock; try restarting transaction
   ```
   - Occurs during concurrent file deletion operations
   - PostgreSQL serialization failures under load

3. **Background Scan Interruptions**
   ```
   User admin still has unscanned files after running background scan,
   background scan might be stopped prematurely
   ```
   - Caused by permission errors preventing complete scans

4. **Service Restarts**
   - 6 restarts in 7 days (some manual, some auto-update related)
   - Each restart causes brief unavailability → 503 errors

**Evidence:**
- Nextcloud logs show repeated permission denied errors
- External storage paths are inaccessible to Nextcloud container
- Database contention during high-concurrency operations
- AutoUpdate=registry triggers weekly restarts (Sundays 03:00)

### Immich HTTP 500 Errors (369 occurrences)

**Primary Root Cause:** Thumbnail file permission errors

**Timeline:**
- Dec 28 19:30 - Permission errors begin (thumbnails inaccessible)
- Dec 28 19:46 - Manual restart to fix (caused 342 errors during restart)
- Dec 29 - Residual errors clearing (27 errors)
- Dec 30-31 - Clean operation (0 errors)

**Contributing Factors:**

1. **Thumbnail Permission Issues**
   ```
   EACCES: permission denied, access
   '/usr/src/app/upload/thumbs/.../thumbnail.webp'
   ```
   - User-generated thumbnails became inaccessible
   - Likely caused by file ownership change or permission reset

2. **Manual Service Restart**
   - Restart at 19:46 on Dec 28 caused brief outage
   - Traefik returned 500 errors during container startup

3. **Connection Timeouts (201 over 7 days)**
   - HTTP code 0 errors indicate client-side connection drops
   - May be related to slow ML inference or database queries

**Evidence:**
- Immich logs show permission denied on thumbnail access
- Service restart coincides with error spike (342 errors)
- Errors ceased after permissions were fixed
- AutoUpdate=registry enabled (weekly Sunday 03:00)

## Service Health Status

### Nextcloud Stack

| Component | Status | Uptime | Notes |
|-----------|--------|--------|-------|
| nextcloud | ✅ Running | 23h | AutoUpdate enabled |
| nextcloud-db (MariaDB) | ✅ Running | 23h | AutoUpdate enabled |
| nextcloud-redis | ✅ Running | 3 days | Healthy |

**Current Issues:**
- External storage permissions still unresolved
- Database deadlocks under concurrent load

### Immich Stack

| Component | Status | Uptime | Notes |
|-----------|--------|--------|-------|
| immich-server | ✅ Running | 21h | AutoUpdate enabled, v2.4.1 |
| immich-ml | ✅ Running | 3 days | Healthy, v2.4.1 |
| postgresql-immich | ✅ Running | 3 days | Healthy |
| redis-immich | ✅ Running | 3 days | Healthy |

**Current Issues:**
- ✅ Thumbnail permissions resolved (no errors since Dec 30)
- Resource usage normal (241MB RAM)

## AutoUpdate Configuration Analysis

**Schedule:** Sundays at 03:00 (via `podman-auto-update-weekly.timer`)

**Affected Services:**
- ✅ Nextcloud (AutoUpdate=registry)
- ✅ Immich-server (AutoUpdate=registry)
- ✅ Immich-ML (AutoUpdate=registry)
- ✅ All database containers (AutoUpdate=registry)

**Assessment:**
- **Timing:** Sunday 03:00 is reasonable (low traffic, before vulnerability scan at 06:00)
- **Frequency:** Weekly is appropriate per ADR-015 (Container Update Strategy)
- **Impact:** Brief downtime (<30s per service) acceptable for security updates

**Observations:**
- Dec 28 auto-update at 03:00 had no updates available (no journal entries)
- Dec 31 restarts at 02:19 were **NOT auto-update** (wrong time)
- Manual restarts likely for troubleshooting or testing

**Recommendation:** Keep current auto-update configuration. Focus on permission fixes.

## Impact Assessment

### Nextcloud

**Error Budget Analysis:**
- **Target:** 99.50% availability
- **Actual:** 96.24% availability
- **Gap:** -3.26% (658% over error budget)
- **Errors:** 1727 HTTP 503 over 7 days = 247 errors/day avg

**User Impact:**
- Brief unavailability during service restarts
- File access errors on external storage paths
- Background scanning incomplete

### Immich

**Error Budget Analysis:**
- **Target:** 99.90% availability
- **Actual:** 93.67% availability
- **Gap:** -6.23% (6230% over error budget!)
- **Errors:** 369 HTTP 500 + 205 timeouts over 7 days

**User Impact:**
- Unable to view thumbnails during Dec 28-29 (permission errors)
- Brief unavailability during restarts
- Slowness/timeouts (201 connection drops)

**Note:** User acknowledged "testing and development work" during this period, which explains the concentrated errors on Dec 28.

## Recommendations

### Priority 1: Fix Nextcloud External Storage Permissions

**Issue:** External storage mounts are inaccessible due to permission mismatch

**Solution:**
1. Identify Nextcloud container UID/GID:
   ```bash
   podman exec nextcloud id www-data
   ```

2. Check external storage permissions:
   ```bash
   ls -la /mnt/btrfs-pool/*/downloads /mnt/btrfs-pool/*/music
   ```

3. Fix ownership (adjust UID:GID to match container):
   ```bash
   sudo chown -R <nextcloud-uid>:<nextcloud-gid> /external/downloads /external/music
   ```

4. Verify Nextcloud can access:
   ```bash
   podman exec nextcloud ls -la /external/downloads /external/music
   ```

**Expected Result:** "Storage not available" errors resolved, 503 errors drop significantly

### Priority 2: Address Nextcloud Database Deadlocks

**Issue:** Concurrent file operations cause PostgreSQL deadlocks

**Potential Solutions:**

**Option A: Tune PostgreSQL for Nextcloud workload**
- Increase `max_locks_per_transaction` (default: 64)
- Consider statement timeout settings
- Review isolation level (currently using default)

**Option B: Review Nextcloud concurrency settings**
- Check `config.php` for preview generation concurrency
- Consider staggering background jobs

**Recommended Action:**
1. Monitor deadlock frequency after fixing external storage permissions
2. If deadlocks persist, tune PostgreSQL settings

### Priority 3: Monitor Immich for Recurrence

**Issue:** Thumbnail permission errors (resolved Dec 30)

**Monitoring:**
1. Watch for permission errors in logs:
   ```bash
   podman logs immich-server --tail 100 | grep -i "EACCES\|permission denied"
   ```

2. Set up Prometheus alert for HTTP 500 spikes:
   ```yaml
   alert: ImmichHighErrorRate
   expr: rate(traefik_service_requests_total{service="immich",code="500"}[5m]) > 0.01
   for: 5m
   ```

3. Check thumbnail directory ownership periodically:
   ```bash
   podman exec immich-server ls -la /usr/src/app/upload/thumbs/ | head -20
   ```

**Expected Result:** Early detection if permission issues recur

### Priority 4: Consider SLO Adjustment During Development

**Issue:** Development/testing work causes SLO violations (acceptable trade-off)

**Options:**

**Option A: Document development windows**
- Exclude known development periods from SLO calculations
- Add annotation to Grafana during testing

**Option B: Create separate development SLOs**
- Lower availability target during active development
- Separate production vs. development metrics

**Option C: Accept current approach**
- Keep strict SLOs as aspirational targets
- Acknowledge testing impact in monthly reports

**Recommended:** Option C (current approach is fine). SLO violations during development are expected and acceptable.

### Priority 5: Investigate Dec 31 02:19 Restarts

**Issue:** Both Nextcloud and Immich restarted at 02:19 (outside auto-update window)

**Questions:**
- Was this manual intervention?
- Triggered by a script or timer?
- Related to testing/development?

**Action:**
- Review user actions on Dec 31 around 02:19
- Check for custom timers or cron jobs
- Consider adding logging for manual restarts

## Testing Plan

### Validation Steps

1. **Fix Nextcloud external storage permissions**
   - Apply recommended chown commands
   - Verify Nextcloud can list files in /external/downloads and /external/music
   - Monitor for 24 hours, expect 503 errors to drop to near-zero

2. **Monitor Immich stability**
   - No action needed (already stable since Dec 30)
   - Continue monitoring for permission errors

3. **Verify auto-update schedule**
   - Confirm next run: Jan 4 (Sunday) 03:00
   - Monitor for brief downtime during update window
   - Verify services recover cleanly

### Success Criteria

- **Nextcloud:** <10 HTTP 503 errors per day (from 247/day avg)
- **Immich:** Maintain 0 HTTP 500 errors (current state)
- **Both:** Clean auto-update on Jan 4 03:00 with <30s downtime

## Lessons Learned

1. **External storage requires explicit permission management**
   - Rootless containers run as specific UID/GID
   - Host filesystem permissions must match container user
   - SELinux contexts must allow access (`:Z` label)

2. **Permission changes can break running services**
   - Immich thumbnail permissions changed unexpectedly
   - Likely due to manual file operations or backup/restore

3. **AutoUpdate is not the culprit**
   - Weekly Sunday 03:00 schedule is appropriate
   - Most errors occurred outside auto-update windows
   - Permission issues were the actual root cause

4. **Development activity impacts production SLOs**
   - Testing/development work (Dec 28) caused concentrated errors
   - Consider separate development environment for testing
   - Or accept SLO violations during known development windows

5. **Correlation analysis is powerful**
   - Timeline correlation revealed manual restarts vs auto-update
   - Permission errors coincided with error spikes
   - Logs provided definitive root cause evidence

## Appendices

### Appendix A: Investigation Scripts

All investigation scripts created during this analysis:

1. `/tmp/investigate-nextcloud-503.sh` - Nextcloud error timeline and status
2. `/tmp/nextcloud-deeper-analysis.sh` - AutoUpdate config and detailed logs
3. `/tmp/investigate-immich-errors.sh` - Immich error timeline and dependencies
4. `/tmp/immich-deeper-analysis.sh` - Resource usage and configuration
5. `/tmp/check-auto-update.sh` - Auto-update schedule and correlation
6. `/tmp/final-analysis.sh` - Timeline reconstruction and triggers

### Appendix B: Prometheus Queries Used

**Nextcloud 503 errors (7 days):**
```promql
increase(traefik_service_requests_total{exported_service="nextcloud@file",code="503"}[7d])
```

**Immich 500 errors (daily breakdown):**
```promql
increase(traefik_service_requests_total{exported_service="immich@file",code="500"}[1d])
```

**Immich connection timeouts:**
```promql
increase(traefik_service_requests_total{exported_service="immich@file",code="0"}[7d])
```

### Appendix C: Related Documentation

- **ADR-015:** Container Update Strategy (`:latest` tags + AutoUpdate)
- **SLO Framework:** `docs/40-monitoring-and-documentation/guides/slo-framework.md`
- **SLO Investigation:** `docs/99-reports/slo-investigation-20251231.md` (root cause for reporting bugs)

---

**Investigation Completed:** 2025-12-31
**Next Review:** After implementing Priority 1 fix (Nextcloud permissions)
**Follow-up:** Validate during next monthly SLO report (January 2026)
