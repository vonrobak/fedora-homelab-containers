# 2025-12-21: Nextcloud Background Jobs Implementation & Error Resolution

**Date:** 2025-12-21
**Type:** System Enhancement + Bug Fix
**Status:** Complete ✅
**Impact:** Reliable maintenance tasks + leveraged network segmentation for security

---

## Summary

Implemented systemd-based background job execution for Nextcloud and resolved accumulated error conditions through network-aware whitelisting and secret management fixes.

**Key Achievements:**
- ✅ Systemd-based cron executing every 5 minutes (replacing inefficient AJAX mode)
- ✅ Network segmentation leveraged for intelligent rate limit bypass
- ✅ Redis authentication fixed (secret newline issue)
- ✅ Error count reduced from 861 accumulated to zero new errors

---

## Problem 1: Background Jobs Not Executing

### Issue
Nextcloud UI warning: "Last background job execution ran 20 hours ago. Something seems wrong."
- User switched from AJAX to Cron mode, but no system cron configured
- 861 errors accumulated in logs

### Root Cause
Nextcloud requires external cron execution every 5 minutes for maintenance tasks:
- File scanning, preview generation
- Calendar/contact sync processing
- Trash cleanup, session management
- Share notifications

AJAX mode (browser-triggered) is inefficient and unreliable.

### Solution: Systemd Timer Integration

**Created systemd units:**
```
~/.config/systemd/user/nextcloud-cron.service
~/.config/systemd/user/nextcloud-cron.timer
```

**Configuration:**
- **Schedule:** Every 5 minutes (`*:00/5:00`) with 30s random delay
- **Command:** `podman exec --user www-data nextcloud php -f /var/www/html/cron.php`
- **Timeout:** 300s (handles occasional heavy jobs)
- **Persistent:** Catches up missed runs after downtime

**Architecture alignment:**
- Follows ADR-002: Systemd over other orchestration
- Same pattern as autonomous-operations.timer, monthly-slo-report.timer
- Observable via journalctl, integrates with monitoring

**Scheduling decision:**
Runs every 5 minutes 24/7 (not limited to sleep hours) because:
- Nextcloud's design: processes 1 job per execution
- Lightweight: <5s typical execution time
- Time-sensitive: calendar sync, sharing, notifications
- No interference: different purpose/scale than daily maintenance tasks

---

## Problem 2: Prometheus Rate Limiting (861 Errors)

### Issue
Nextcloud logs filled with HTTP 429 errors:
```
remoteAddr: 10.89.4.62 (Prometheus)
userAgent: Prometheus/3.8.1
message: "Reached maximum delay"
Code: 429 (Too Many Requests)
```

Prometheus scraping `/serverinfo/api/v1/info` every minute triggered brute force protection.

### Solution: Network Segmentation Whitelist

**Network topology leveraged:**
```
Prometheus:  10.89.4.12  (systemd-monitoring)
Nextcloud:   10.89.4.13  (systemd-monitoring)
             10.89.10.4  (systemd-nextcloud)
             10.89.2.11  (systemd-reverse_proxy)
```

**Nextcloud configuration:**
```php
'ratelimit.protection.enabled' => true,
'ratelimit.whitelist' => ['10.89.4.0/24'],  // Monitoring network
'trusted_proxies' => ['10.89.2.0/24', '10.89.4.0/24']
```

**Result:** Zero rate limit errors from monitoring network while maintaining protection for external users.

**Defense in depth benefit:**
- Precise whitelisting (only monitoring tools bypass limits)
- External attackers still face full brute force protection
- Observable security boundaries via network segmentation

---

## Problem 3: Redis Authentication Failures

### Issue
Background job errors:
```
RedisException: NOAUTH Authentication required
RedisException: WRONGPASS invalid username-password pair
```

### Root Cause
Podman secret contained trailing newline:
```bash
Secret file: "q3ZT7uuvZR/vSqLmgILVlZgWLU7gQNPBg3nhNWcRiNU\n"  (44 bytes)
Nextcloud:   "q3ZT7uuvZR/vSqLmgILVlZgWLU7gQNPBg3nhNWcRiNU"    (43 bytes)
```

Redis read password with newline, Nextcloud connected without it.

### Solution
```bash
# Recreate secret without trailing newline
podman secret rm nextcloud_redis_password
echo -n "PASSWORD" | podman secret create nextcloud_redis_password -
systemctl --user restart nextcloud-redis.service
```

**Verification:**
- 3 consecutive cron runs: zero Redis errors
- Redis health check: PASSED
- Commands processed: 217+

---

## Technical Highlights

### Background Job Execution (UTC Confusion Resolution)

Initial diagnosis showed jobs "not due" despite being overdue:
```
Next execution: 2025-12-21T22:14:28+00:00
Current time:   2025-12-21T23:10:xx CET
```

**Resolution:** Nextcloud uses UTC internally; all timestamps correct when viewed in UTC:
- Host: 23:10 CET = 22:10 UTC
- Job next run: 22:20 UTC (10 minutes from now)
- System working correctly, timezone display caused confusion

### Systemd Timer Design

**Why every 5 minutes, not longer:**
- Nextcloud processes 1 job per cron execution (by design)
- 17 overdue jobs = 85 minutes to catch up (gradual)
- Short runs (<5s) prevent timeout issues
- Frequent execution ensures responsive task processing

---

## Verification & Monitoring

**Background jobs:**
```bash
systemctl --user list-timers | grep nextcloud
# Next: 2min 54s | Last: completed successfully

podman exec --user www-data nextcloud php occ background-job:list
# 29 jobs executed since 22:00 UTC (recent activity)
```

**Error resolution:**
- Before: 861 accumulated errors
- After: 0 new errors (monitoring period confirms)
- Rate limiting: 0 errors from monitoring network
- Redis: 0 authentication errors

---

## Files Modified

**Created:**
- `~/.config/systemd/user/nextcloud-cron.service`
- `~/.config/systemd/user/nextcloud-cron.timer`

**Configuration changes:**
- Nextcloud `config.php`: Added rate limit whitelist, trusted proxies
- Podman secret: `nextcloud_redis_password` (recreated without newline)

---

## Lessons Learned

1. **Network segmentation provides precise security controls**
   Monitoring network (10.89.4.0/24) whitelisted for metrics without exposing attack surface

2. **Podman secrets need explicit newline handling**
   Use `echo -n` when creating secrets from command line

3. **Systemd timers are reliable cron replacements**
   Persistent=true handles downtime, RandomizedDelaySec prevents thundering herd

4. **UTC vs local time in containerized apps**
   Nextcloud stores all timestamps in UTC; display timezone differs from storage

---

## Impact

**Operational:**
- Nextcloud maintenance tasks now executing reliably every 5 minutes
- Monitoring network can collect metrics without triggering defensive mechanisms
- Redis caching fully functional (session storage, distributed cache)

**Architectural:**
- Demonstrated practical value of network segmentation (defense in depth)
- Extended systemd timer pattern to application-level maintenance
- Observable system: journalctl integration, clear execution logs

**Security:**
- Maintained brute force protection for external users
- Whitelisted trusted networks using precise CIDR blocks
- Zero-trust boundaries enforced via network segmentation
