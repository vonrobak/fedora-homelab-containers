# Log-to-Metric Dashboard Panels

**Created:** 2026-01-11
**Purpose:** Dashboard panels for log-derived metrics from Promtail metric extraction

---

## Overview

These panels visualize metrics extracted from logs at ingestion time by Promtail. Add these panels to your existing SLO Dashboard in Grafana to gain real-time visibility into log-based error patterns.

**Metrics Source:** Promtail custom metrics (exposed at `promtail:9080/metrics`, scraped by Prometheus every 15s)

**Dashboard:** Add to existing SLO Dashboard at https://grafana.patriark.org

---

## Panel 1: Service Error Rate

**Purpose:** Track error rate across all systemd services (priority ≤3)

**Panel Type:** Graph (Time series)

**Query:**
```promql
rate(promtail_custom_service_errors_total[5m])
```

**Legend:** `{{syslog_id}}`

**Thresholds:**
- Warning: 0.03 (>10 errors in 5min)

**Unit:** errors/sec

---

## Panel 2: Immich Thumbnail Failure Rate

**Purpose:** Monitor thumbnail generation failures (indicates corrupt media files)

**Panel Type:** Graph (Time series)

**Query:**
```promql
rate(promtail_custom_immich_thumbnail_failures_total[1h]) * 3600
```

**Legend:** `Thumbnail failures/hour`

**Thresholds:**
- Warning: 5 (>5 failures in 1h)

**Unit:** failures/hour

**Recommended Action:** Failures indicate corrupt media files - check logs with:
```bash
journalctl --user -u immich-server.service --since "1 hour ago" | grep "AssetGenerateThumbnails.*ERROR"
```

---

## Panel 3: Nextcloud Cron Failures

**Purpose:** Detect background job failures (critical for file sync, CalDAV, previews)

**Panel Type:** Stat (Single value)

**Query:**
```promql
increase(promtail_custom_nextcloud_cron_failures_total[10m])
```

**Legend:** `Cron failures (10min)`

**Thresholds:**
- Critical: > 0

**Unit:** failures

**Recommended Action:** Check systemd timer status:
```bash
systemctl --user status nextcloud-cron.timer
```

---

## Panel 4: Jellyfin Transcoding Failure Rate

**Purpose:** Monitor transcoding failures (codec/hardware acceleration issues)

**Panel Type:** Graph (Time series)

**Query:**
```promql
rate(promtail_custom_jellyfin_transcoding_failures_total[30m]) * 1800
```

**Legend:** `Transcoding failures/30min`

**Thresholds:**
- Warning: 3 (>3 failures in 30min)

**Unit:** failures/30min

---

## Panel 5: Authelia Auth Failure Spike

**Purpose:** Detect authentication attacks or misconfigurations

**Panel Type:** Graph (Time series)

**Query:**
```promql
rate(promtail_custom_authelia_auth_failures_total[5m])
```

**Legend:** `Auth failures/sec`

**Thresholds:**
- Warning: 0.03 (>10 failures in 5min)

**Unit:** failures/sec

**Recommended Action:** Check CrowdSec decisions:
```bash
podman exec crowdsec cscli decisions list
```

---

## Panel 6: Container Restart Loop Detection

**Purpose:** Identify containers crashing/restarting unexpectedly

**Panel Type:** Graph (Time series)

**Query:**
```promql
rate(promtail_custom_container_unplanned_restarts_total[10m])
```

**Legend:** `{{container_name}} restarts/sec`

**Thresholds:**
- Critical: 0.005 (>3 restarts in 10min)

**Unit:** restarts/sec

**Recommended Action:** Check memory usage:
```bash
podman stats --no-stream
```

---

## Panel 7: Total Error Budget Consumption

**Purpose:** Aggregate view of all log-derived error rates

**Panel Type:** Bar gauge

**Query:**
```promql
sum by (syslog_id) (
  rate(promtail_custom_service_errors_total[5m])
)
```

**Legend:** `{{syslog_id}}`

**Unit:** errors/sec

**Orientation:** Horizontal

---

## Panel 8: Error Breakdown by Service

**Purpose:** Pie chart showing distribution of errors across services

**Panel Type:** Pie chart

**Query:**
```promql
sum by (syslog_id) (
  increase(promtail_custom_service_errors_total[24h])
)
```

**Legend:** `{{syslog_id}}`

**Unit:** errors (24h)

---

## Adding Panels to Grafana

### Method 1: Manual Creation

1. Navigate to https://grafana.patriark.org
2. Open SLO Dashboard
3. Click "Add" → "Visualization"
4. Select "Prometheus" datasource
5. Paste query from panel definition above
6. Configure panel settings (thresholds, units, legend)
7. Click "Apply"
8. Click "Save dashboard"

### Method 2: Import via JSON (Future)

Dashboard JSON provisioning to be added in future update.

---

## Alert Correlation

These panels correlate with alerts defined in `/home/patriark/containers/config/prometheus/rules/log-based-alerts.yml`:

| Panel | Alert | Severity | Threshold |
|-------|-------|----------|-----------|
| Service Error Rate | ServiceErrorRateHigh | warning | >10 errors in 5min |
| Immich Thumbnails | ImmichThumbnailFailureHigh | warning | >5 failures in 1h |
| Nextcloud Cron | NextcloudCronFailure | critical | >0 failures in 10min |
| Jellyfin Transcoding | JellyfinTranscodingFailureHigh | warning | >3 failures in 30min |
| Authelia Auth | AutheliaAuthFailureSpike | warning | >10 failures in 5min |
| Container Restarts | ContainerRestartLoop | critical | >3 restarts in 10min |

---

## Validation Queries

**Test queries directly in Prometheus:**

```bash
# Check metrics exist
podman exec prometheus wget -qO- \
  "http://localhost:9090/api/v1/query?query=promtail_custom_service_errors_total" | \
  jq -r '.data.result[] | "\(.metric.syslog_id): \(.value[1])"'

# Check current error rate
podman exec prometheus wget -qO- \
  "http://localhost:9090/api/v1/query?query=rate(promtail_custom_service_errors_total[5m])" | \
  jq -r '.data.result[] | "\(.metric.syslog_id): \(.value[1])"'
```

---

## Related Documentation

- **Log-to-Metric Implementation:** `docs/40-monitoring-and-documentation/guides/log-to-metric-implementation.md` (to be created)
- **Alert Rules:** `config/prometheus/rules/log-based-alerts.yml`
- **Promtail Config:** `config/promtail/promtail-config.yml` (metric extraction stages)
- **Daily Error Digest:** `docs/40-monitoring-and-documentation/guides/daily-error-digest.md`
- **SLO Framework:** `docs/40-monitoring-and-documentation/guides/slo-framework.md`

---

**Status:** ✅ Ready for Dashboard Integration
**Next Step:** Add panels to Grafana SLO Dashboard
