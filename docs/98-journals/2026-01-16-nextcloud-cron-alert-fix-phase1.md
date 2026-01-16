# NextcloudCronStale Alert Fix - Phase 1

**Date:** 2026-01-16 (Evening)
**Status:** ✅ Complete
**Component:** Promtail Metric Extraction
**Context:** Part of 5-phase alerting system redesign (breezy-wobbling-kettle plan)

---

## Problem

The NextcloudCronStale alert (created this morning as a fix) continued firing despite:
- Nextcloud cron running successfully every 5 minutes
- Logs showing "Finished nextcloud-cron.service" messages
- No actual service failures

**Alert firing reason:** Prometheus metric `promtail_custom_nextcloud_cron_success_total` did not exist, causing `changes() == 0` to evaluate true.

---

## Root Cause

Promtail metric extraction pipeline had incorrect configuration syntax:

**Initial Attempt (Failed):**
```yaml
- regex:
    source: message  # ❌ Incorrect syntax for Promtail
    expression: '^Finished nextcloud-cron\.service'
```

**Issue:** The `source: message` parameter is not valid syntax for regex stages in Promtail pipelines when used within a `match` block.

---

## Investigation Process

### 1. Verified Cron Was Running
```bash
$ systemctl --user status nextcloud-cron.timer
Trigger: Every 5 minutes ✓

$ journalctl --user -u nextcloud-cron.service | grep Finished
jan. 16 23:25:35 Finished nextcloud-cron.service ✓
jan. 16 23:40:16 Finished nextcloud-cron.service ✓
```

### 2. Checked Promtail Metrics Endpoint
```bash
$ podman exec prometheus wget -qO- 'http://promtail:9080/metrics' | grep nextcloud_cron
# No output - metric doesn't exist ❌
```

### 3. Examined JSON Log Structure
```json
{
  "MESSAGE": "Finished nextcloud-cron.service - Nextcloud Background Jobs (Cron).",
  "SYSLOG_IDENTIFIER": "systemd",
  "PRIORITY": "6"
}
```

- JSON parser extracts MESSAGE → `message` label ✓
- Selector `{syslog_id="systemd"}` matches ✓
- Regex should match "Finished nextcloud-cron.service" ✓

### 4. Compared with Working Metrics

**Immich metric (working pattern):**
```yaml
- match:
    selector: '{syslog_id="immich-server"}'
    stages:
      - regex:
          expression: '.*AssetGenerateThumbnails.*ERROR.*'
      - metrics:
          immich_thumbnail_failures_total:
            type: Counter
            config:
              match_all: true  # ← Key difference
              action: inc
```

**Authelia metric (working pattern):**
```yaml
- match:
    selector: '{syslog_id="authelia"}'
    stages:
      - regex:
          expression: '.*Authentication.*(failed|denied|invalid).*'
      - metrics:
          authelia_auth_failures_total:
            type: Counter
            config:
              match_all: true  # ← Key difference
              action: inc
```

**Pattern:** No `source:` parameter, uses `match_all: true`

---

## Solution Applied

**File:** `/home/patriark/containers/config/promtail/promtail-config.yml`

**Final working configuration:**
```yaml
- match:
    selector: '{syslog_id="systemd"}'
    pipeline_name: "nextcloud_cron_success"
    stages:
      - regex:
          expression: '.*Finished nextcloud-cron\.service.*'
      - metrics:
          nextcloud_cron_success_total:
            type: Counter
            description: "Increments on each successful cron completion (use changes() for staleness detection)"
            config:
              match_all: true
              action: inc
```

**Changes made:**
1. ✅ Removed incorrect `source: message` parameter
2. ✅ Simplified regex to `'.*Finished nextcloud-cron\.service.*'`
3. ✅ Added `match_all: true` to match working pattern

---

## Deployment Process

### 1. Configuration Edit
```bash
# Edit config/promtail/promtail-config.yml
# Apply changes per solution above
```

### 2. Restart Promtail
```bash
$ systemctl --user restart promtail.service
# Config auto-reloads but restart ensures clean state
```

### 3. Clear Position File (One-time)
```bash
# Required to reprocess historical logs and see immediate results
$ systemctl --user stop promtail.service
$ podman exec promtail sh -c "echo 'positions: {}' > /tmp/positions.yaml"
$ systemctl --user start promtail.service
```

**Note:** Clearing positions.yaml was only needed for immediate validation. In production, new log entries will increment the metric normally.

### 4. Verify Metric Extraction
```bash
$ podman exec prometheus wget -qO- 'http://promtail:9080/metrics' | grep nextcloud_cron
promtail_custom_nextcloud_cron_success_total{...} 4
✅ Metric exists!
```

### 5. Verify Prometheus Scrape
```bash
$ podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=promtail_custom_nextcloud_cron_success_total'
{"data":{"result":[{"value":["1768604983.508","4"]}]}}
✅ Prometheus has metric!
```

### 6. Verify Alert Resolution
```bash
$ podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=changes(promtail_custom_nextcloud_cron_success_total[10m])'
{"data":{"result":[{"value":["1768605000","1"]}]}}
✅ changes() = 1 (not 0, alert condition NOT met)

$ podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts' | jq '.data.alerts[] | select(.labels.alertname == "NextcloudCronStale")'
# No output
✅ Alert resolved!
```

---

## Validation Results

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| Cron executes every 5min | Timer active | Trigger every 5min | ✅ |
| Metric exists in Promtail | Metric present | Value: 4 | ✅ |
| Prometheus scrapes metric | Scraped successfully | Value: 4 | ✅ |
| changes() function works | > 0 when cron runs | Value: 1 | ✅ |
| Alert resolved | Not firing | Not in active alerts | ✅ |
| Discord notification stops | No more alerts | Confirmed | ✅ |

---

## Key Learnings

### 1. Promtail Regex Stage Syntax
**Within `match` blocks:** The regex stage operates on the log line content AFTER JSON parsing. The `source:` parameter is not used in this context.

**Correct pattern:**
```yaml
- match:
    selector: '{label="value"}'
    stages:
      - regex:
          expression: 'pattern'  # Operates on message field automatically
      - metrics:
          metric_name:
            config:
              match_all: true  # Required for proper matching
```

### 2. Position File Behavior
- Promtail saves file positions in `/tmp/positions.yaml`
- On restart, resumes from saved position
- To reprocess logs: Clear positions file (one-time testing only)
- In production: Metric will increment naturally with new log entries

### 3. Metric Validation Process
1. Check Promtail metrics endpoint: `promtail:9080/metrics`
2. Check Prometheus scrape: Query API
3. Verify alert condition: Test PromQL expression
4. Confirm alert status: Check active alerts

---

## Comparison: Before vs After

| Aspect | Before (Broken) | After (Fixed) |
|--------|-----------------|---------------|
| **Metric Exists** | ❌ No | ✅ Yes (value: 4) |
| **Regex Syntax** | `source: message` (invalid) | Standard expression |
| **Config Match** | `match_all: true` missing | Included |
| **Prometheus** | No data | Scraping successfully |
| **Alert Status** | Firing (false positive) | Resolved ✅ |
| **Discord Alerts** | Continuous spam | Silent |

---

## Next Steps

**Completed:**
- ✅ Phase 1: Fixed Promtail metric extraction
- ✅ Alert resolved
- ✅ Metric incrementing on each cron execution

**Remaining (from 5-phase plan):**
- ⏳ Phase 2: Migrate logs to BTRFS storage
- ⏳ Phase 3: Eliminate fragile log-based metrics
- ⏳ Phase 4: Alert consolidation (51 → 48 alerts)
- ⏳ Phase 5: Meta-monitoring (detect monitoring failures)

---

## Related Documentation

- Plan: `~/.claude/plans/breezy-wobbling-kettle.md` - Complete 5-phase alerting redesign
- Morning fix: `docs/98-journals/2026-01-16-alert-system-redesign.md` - Initial "absence of success" pattern
- Investigation: `docs/99-reports/alert-false-positives-analysis-2026-01-16.md` - Root cause analysis
- Alert config: `config/prometheus/rules/log-based-alerts.yml` - Alert definitions
- Promtail config: `config/promtail/promtail-config.yml` - Metric extraction pipelines

---

**Status:** Phase 1 complete | Alert resolved | Ready for Phase 2
**Time invested:** ~1.5 hours (investigation + implementation + validation)
**Outcome:** ✅ NextcloudCronStale alert no longer firing, metric extraction working correctly
