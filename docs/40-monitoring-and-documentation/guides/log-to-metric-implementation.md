# Log-to-Metric Feedback Loop Implementation

**Created:** 2026-01-11
**Status:** ✅ Operational
**Purpose:** Real-time error detection via log-derived Prometheus metrics

---

## Overview

**Problem:** Loki is excellent for post-incident analysis, but requires manual queries. Errors accumulate in logs without real-time alerting until they cause SLO violations.

**Solution:** Extract metrics from logs at ingestion time (via Promtail), expose as Prometheus counters, alert on rate/increase patterns.

**Result:** Proactive detection of specific errors BEFORE they cause service-level failures.

---

## Architecture

### Data Flow

```
[1] Systemd Journal
    ↓
[2] Promtail (metric extraction at ingestion)
    ↓ (logs to Loki)   ↓ (metrics to :9080/metrics)
[3] Loki               [4] Prometheus (scrapes every 15s)
    ↓                       ↓
[5] Post-incident      [6] Real-time alerts
    analysis               (rate/increase queries)
```

### Why This Works

**Traditional approach:**
- Logs → Loki → Manual queries → Discovery after incident
- **Lag:** Minutes to hours

**Log-to-metric approach:**
- Logs → Promtail metric extraction → Prometheus → Alerts
- **Lag:** 15-30 seconds (scrape interval + evaluation)

**Key insight:** We're extracting metrics at the **same place we're already parsing logs for Loki**. Zero additional overhead.

---

## Implementation Details

### Component 1: Promtail Metric Extraction

**File:** `/home/patriark/containers/config/promtail/promtail-config.yml`

**How it works:**

Promtail's pipeline stages can extract metrics from logs as they're ingested:

```yaml
scrape_configs:
  - job_name: systemd-journal
    pipeline_stages:
      # First: Extract JSON fields
      - json:
          expressions:
            message: MESSAGE
            priority: PRIORITY
            syslog_id: SYSLOG_IDENTIFIER

      # Second: Label extraction (for Loki)
      - labels:
          priority:
          syslog_id:

      # Third: METRIC EXTRACTION
      - match:
          selector: '{priority=~"[0-3]"}'  # Priority ≤3 = errors
          stages:
            - metrics:
                service_errors_total:
                  type: Counter
                  description: "Total service errors (priority ≤3)"
                  source: priority
                  config:
                    action: inc
```

**Pipeline execution:**
1. JSON parsing extracts `priority` field
2. Match selector filters for errors (priority ≤3)
3. Metrics stage increments counter `promtail_custom_service_errors_total`
4. Counter exposed at `http://promtail:9080/metrics`

**Metric naming:** All Promtail custom metrics get `promtail_custom_` prefix automatically.

---

### 6 Metrics Extracted

#### 1. Service Errors (Priority ≤3)

**Metric:** `promtail_custom_service_errors_total`

**Pattern:**
```yaml
- match:
    selector: '{priority=~"[0-3]"}'
    stages:
      - metrics:
          service_errors_total:
            type: Counter
            config:
              action: inc
```

**Labels:** `syslog_id` (service name)

**Use case:** Track error rate across all systemd services

---

#### 2. Immich Thumbnail Failures

**Metric:** `promtail_custom_immich_thumbnail_failures_total`

**Pattern:**
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
              match_all: true
              action: inc
```

**Labels:** `syslog_id="immich-server"`

**Use case:** Detect corrupt media files causing thumbnail generation to fail

---

#### 3. Nextcloud Cron Failures

**Metric:** `promtail_custom_nextcloud_cron_failures_total`

**Pattern:**
```yaml
- match:
    selector: '{syslog_id=~"nextcloud.*"}'
    stages:
      - regex:
          expression: '.*(failed|error|ERROR|not found).*'
      - metrics:
          nextcloud_cron_failures_total:
            type: Counter
            config:
              match_all: true
              action: inc
```

**Labels:** `syslog_id` (nextcloud, nextcloud-cron)

**Use case:** Ensure background jobs running (file sync, CalDAV, previews)

---

#### 4. Jellyfin Transcoding Failures

**Metric:** `promtail_custom_jellyfin_transcoding_failures_total`

**Pattern:**
```yaml
- match:
    selector: '{syslog_id="jellyfin"}'
    stages:
      - regex:
          expression: '.*Transcoding.*ERROR.*'
      - metrics:
          jellyfin_transcoding_failures_total:
            type: Counter
            config:
              match_all: true
              action: inc
```

**Labels:** `syslog_id="jellyfin"`

**Use case:** Monitor codec/hardware acceleration issues

---

#### 5. Authelia Auth Failures

**Metric:** `promtail_custom_authelia_auth_failures_total`

**Pattern:**
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
              match_all: true
              action: inc
```

**Labels:** `syslog_id="authelia"`

**Use case:** Detect authentication attacks or credential issues

---

#### 6. Container Unplanned Restarts

**Metric:** `promtail_custom_container_unplanned_restarts_total`

**Pattern:**
```yaml
- match:
    selector: '{syslog_id="podman"}'
    stages:
      - regex:
          expression: '.*(container died|container killed|Exited with error).*'
      - metrics:
          container_unplanned_restarts_total:
            type: Counter
            config:
              match_all: true
              action: inc
```

**Labels:** `syslog_id="podman"`

**Use case:** Identify containers crashing due to memory exhaustion or errors

---

### Component 2: Prometheus Scraping

**File:** `/home/patriark/containers/config/prometheus/prometheus.yml`

**Scrape config:**
```yaml
- job_name: promtail
  static_configs:
    - targets:
        - promtail:9080
```

**How it works:**
- Prometheus scrapes `http://promtail:9080/metrics` every 15s
- Discovers all `promtail_custom_*` metrics automatically
- Stores as time-series data (same as other metrics)

**Verify scraping:**
```bash
podman exec prometheus wget -qO- \
  "http://localhost:9090/api/v1/query?query=promtail_custom_service_errors_total"
```

---

### Component 3: Alert Rules

**File:** `/home/patriark/containers/config/prometheus/rules/log-based-alerts.yml`

**Alert examples:**

```yaml
groups:
  - name: log_based_alerts
    rules:
      # High error rate alert
      - alert: ServiceErrorRateHigh
        expr: rate(promtail_custom_service_errors_total[5m]) > 0.03
        for: 5m
        labels:
          severity: warning
          category: reliability
        annotations:
          summary: "High error rate in {{ $labels.syslog_id }}"
          description: |
            Service {{ $labels.syslog_id }} logging {{ $value | humanize }} errors/sec.
            Check logs: journalctl --user -u {{ $labels.syslog_id }}.service --priority=err -n 20

      # Cron failure alert (any failure is critical)
      - alert: NextcloudCronFailure
        expr: increase(promtail_custom_nextcloud_cron_failures_total[10m]) > 0
        for: 1m
        labels:
          severity: critical
          category: background_jobs
        annotations:
          summary: "Nextcloud background jobs failing"
          description: |
            Cron failed {{ $value }} times in 10min.
            Check: systemctl --user status nextcloud-cron.timer
```

**Alert philosophy:**
- **Rate-based:** Detect sustained error patterns (e.g., >10 errors in 5min)
- **Increase-based:** Detect ANY occurrence of critical errors (e.g., cron failures)
- **Service-specific thresholds:** Tuned to each service's normal behavior

**View alerts:**
```bash
# Active alerts
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/alerts"

# Alert rules
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[] | select(.name == "log_based_alerts")'
```

---

## Benefits

### 1. Proactive Detection

**Before:**
- Immich thumbnail failures accumulate silently
- Discover issue when user reports broken thumbnails
- Manually query Loki to find root cause

**After:**
- Alert fires after 5 failures in 1 hour
- Investigate immediately with provided log query
- Fix corrupt media file before more users affected

### 2. SLO Protection

**Before:**
- Errors cause SLO violation (e.g., Immich 93.67% availability)
- Triggered after 43 minutes of errors (monthly error budget)
- Reactively fix after SLO already breached

**After:**
- Alert fires within 15-30 seconds of error pattern
- Remediate before SLO violation (predictive)
- Preserve error budget

### 3. Context-Rich Alerts

**Alert annotations include:**
- Exact error rate/count
- Service name with label substitution
- Recommended diagnostic commands
- Links to relevant documentation

**Example:**
```
Alert: ServiceErrorRateHigh
Service: immich-server
Rate: 0.05 errors/sec
Action: journalctl --user -u immich-server.service --priority=err -n 20
```

### 4. Correlation with Existing Metrics

**Log-derived metrics work with Prometheus ecosystem:**
```promql
# Correlate error rate with memory usage
rate(promtail_custom_service_errors_total{syslog_id="immich-server"}[5m])
  and on(syslog_id)
container_memory_usage_bytes{name="immich-server"} > 4e9

# Correlate auth failures with CrowdSec bans
rate(promtail_custom_authelia_auth_failures_total[5m])
  and on()
crowdsec_decisions_total > 0
```

---

## Deployment Workflow

### 1. Update Promtail Configuration

```bash
# Edit config
nano ~/containers/config/promtail/promtail-config.yml

# Add metric extraction stage (see examples above)

# Validate config
podman run --rm -v ~/containers/config/promtail:/etc/promtail:Z \
  grafana/promtail:latest \
  -config.file=/etc/promtail/promtail-config.yml \
  -dry-run

# Restart Promtail
systemctl --user restart promtail.service

# Verify metrics exposed
curl -s http://localhost:9080/metrics | grep promtail_custom_
```

### 2. Update Prometheus Alert Rules

```bash
# Edit alert rules
nano ~/containers/config/prometheus/rules/log-based-alerts.yml

# Add alert rule (see examples above)

# Reload Prometheus
podman exec prometheus kill -SIGHUP 1
sleep 30

# Verify alert loaded
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[] | select(.name == "log_based_alerts")'
```

### 3. Test Alert

```bash
# Generate test errors
journalctl --user -u <service>.service --priority=err -n 1

# Wait 15s for Prometheus scrape

# Query metric
podman exec prometheus wget -qO- \
  "http://localhost:9090/api/v1/query?query=rate(promtail_custom_service_errors_total[5m])"

# Check if alert fires (after `for` duration)
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/alerts"
```

---

## Troubleshooting

### Metric Not Appearing

**Symptom:** `promtail_custom_<metric>_total` not in Prometheus

**Diagnose:**
```bash
# 1. Check Promtail exposing metric
curl -s http://localhost:9080/metrics | grep <metric>

# 2. If not, check Promtail logs
journalctl --user -u promtail.service -n 50

# 3. Validate Promtail config
podman run --rm -v ~/containers/config/promtail:/etc/promtail:Z \
  grafana/promtail:latest \
  -config.file=/etc/promtail/promtail-config.yml \
  -dry-run
```

**Common causes:**
- Regex doesn't match any logs (test in Loki Explore)
- Match selector syntax error (check for proper `'{}'` wrapping)
- RE2 regex unsupported (no lookaheads, use simple patterns)
- Promtail failed to restart after config change

### Alert Not Firing

**Symptom:** Metric exists but alert doesn't fire

**Diagnose:**
```bash
# 1. Check metric value exceeds threshold
podman exec prometheus wget -qO- \
  "http://localhost:9090/api/v1/query?query=rate(promtail_custom_service_errors_total[5m])"

# 2. Check alert rule loaded
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[] | select(.name == "log_based_alerts")'

# 3. Check alert health
podman exec prometheus wget -qO- "http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[].rules[] | select(.name == "ServiceErrorRateHigh") | {health, lastError}'
```

**Common causes:**
- `for` duration not elapsed (alert pending)
- Threshold too high for current error rate
- Alert rule syntax error (check `health: "ok"`)
- Prometheus not reloaded after rule change

### High False Positive Rate

**Symptom:** Alert fires frequently for normal operations

**Solution:** Adjust thresholds or add filters

```yaml
# Increase threshold
expr: rate(promtail_custom_service_errors_total[5m]) > 0.1  # Was 0.03

# Add label filter to exclude known-noisy services
expr: rate(promtail_custom_service_errors_total{syslog_id!~"noisy-service|debug-service"}[5m]) > 0.03

# Increase evaluation window
expr: rate(promtail_custom_service_errors_total[15m]) > 0.02  # Was 5m
```

### Metric Counter Not Incrementing

**Symptom:** Metric exists but value is 0 despite matching logs

**Diagnose:**
```bash
# 1. Verify logs match pattern in Loki
# Go to Grafana Explore → Loki datasource
# Query: {syslog_id="immich-server"} |= "AssetGenerateThumbnails" |= "ERROR"

# 2. Check regex syntax in Promtail config
cat ~/containers/config/promtail/promtail-config.yml | grep -A 5 "expression:"

# 3. Test regex with sample log line
echo "Sample log line" | grep -P '<your-regex>'
```

**Common causes:**
- Regex too specific (try broader pattern)
- Regex uses unsupported RE2 features (lookaheads, backreferences)
- Match selector doesn't match labels (check `{syslog_id="..."}'`)
- `match_all: true` missing (only increments on regex match)

---

## Performance Considerations

### Overhead

**Promtail metric extraction:**
- **CPU:** Negligible (<1% increase)
- **Memory:** ~5-10MB per 1000 metrics
- **Latency:** No impact on log ingestion

**Prometheus scraping:**
- **Storage:** ~1KB/metric/scrape (15s interval)
- **Query:** Standard Prometheus performance

**Why low overhead?**
- Metrics extracted during **existing** log parsing (no extra pass)
- Counters only (no histograms or summaries)
- Regex evaluated on pre-filtered logs (match selector narrows scope)

### Scaling

**Recommended limits:**
- **Metrics per service:** 5-10 max
- **Total custom metrics:** <50
- **Regex complexity:** Keep simple (avoid backtracking)

**If exceeding limits:**
- Use recording rules to aggregate metrics
- Increase Prometheus scrape interval (30s, 60s)
- Add `match` selectors to reduce regex evaluations

---

## Future Enhancements

### 1. Predictive Burn-Rate Alerts

**Goal:** Warn 4-6 hours before SLO violations

```yaml
- record: slo:immich:availability:hours_to_exhaustion
  expr: |
    (slo:immich:availability:error_budget_remaining * 3600)
    /
    rate(promtail_custom_immich_thumbnail_failures_total[1h])

- alert: ImmichSLOExhaustionPredicted
  expr: slo:immich:availability:hours_to_exhaustion < 6
  for: 10m
```

**Timeline:** Week 3-4 (from approved plan)

### 2. Grafana Dashboard Panels

**Goal:** Visualize log-derived metrics in SLO dashboard

**Panels:**
- Service error rate (time series)
- Error breakdown by service (pie chart)
- Alert firing history (stat)

**Timeline:** Complete (see `log-to-metric-dashboard-panels.md`)

### 3. Additional Metrics

**Candidates:**
- Traefik 5xx errors (from access logs)
- Remediation failure rate (from decision logs)
- Certificate expiration warnings (from Let's Encrypt logs)
- Database connection pool saturation (from Postgres logs)

---

## Related Documentation

- **Daily Error Digest:** `docs/40-monitoring-and-documentation/guides/daily-error-digest.md`
- **Dashboard Panels:** `docs/40-monitoring-and-documentation/guides/log-to-metric-dashboard-panels.md`
- **SLO Framework:** `docs/40-monitoring-and-documentation/guides/slo-framework.md`
- **Loki Queries:** `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md`
- **Monitoring Stack:** `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`

---

**Status:** ✅ Operational (deployed 2026-01-11)
**Metrics:** 6 log-derived metrics exposed
**Alerts:** 8 alert rules loaded and healthy
**Next Steps:** Add predictive burn-rate alerts (Week 3-4)
