# Daily Error Digest

**Created:** 2026-01-11
**Purpose:** Proactive error monitoring via automated daily Loki log analysis

---

## Overview

The daily error digest automatically queries Loki for the last 24 hours of errors across all log sources (systemd journal, Traefik access logs, remediation decisions) and sends a summary to Discord if errors exceed a configurable threshold.

**Benefits:**
- **Proactive visibility** into emerging issues before they become critical
- **Aggregated view** across multiple log sources in one digest
- **Actionable insights** with top error sources and recommendations
- **Reduces alert fatigue** (only notifies when threshold exceeded)

---

## Components

### Script: `scripts/daily-error-digest.sh`

Queries three Loki job sources:

1. **Systemd Journal** (`{job="systemd-journal"}`)
   - Filters: `priority <= 3` (ERROR, CRITICAL, ALERT, EMERGENCY)
   - Groups by: systemd unit (service name)

2. **Traefik Access Logs** (`{job="traefik-access"}`)
   - Filters: HTTP `status >= 500` (server errors)
   - Groups by: service name and status code

3. **Remediation Decisions** (`{job="remediation-decisions"}`)
   - Filters: `success="false"` (failed autonomous operations)
   - Groups by: playbook name

### Systemd Timer: `daily-error-digest.timer`

- **Schedule:** Daily at 07:00 (± 5 min randomization)
- **Persistent:** Runs on next boot if missed
- **Requires:** Loki and Grafana containers running

### Systemd Service: `daily-error-digest.service`

- **Type:** Oneshot (runs once per trigger)
- **Timeout:** 120s (generous for Loki queries)
- **Resources:** 10% CPU quota, 256MB memory max
- **Logging:** systemd journal (`journalctl --user -u daily-error-digest.service`)

---

## Configuration

### Thresholds

Edit `scripts/daily-error-digest.sh`:

```bash
ERROR_THRESHOLD=10  # Send to Discord if total errors > threshold
LOOKBACK_HOURS=24   # How far back to query (hours)
```

**Default:** 10 errors minimum to trigger Discord notification

### Discord Webhook

Automatically retrieved from `alert-discord-relay` container environment. No manual configuration needed.

---

## Usage

### Manual Execution

```bash
# Run digest immediately
~/containers/scripts/daily-error-digest.sh

# Check output
journalctl --user -u daily-error-digest.service -n 50
```

### Timer Management

```bash
# Check next scheduled run
systemctl --user list-timers | grep daily-error-digest

# Trigger immediately (bypass timer)
systemctl --user start daily-error-digest.service

# View status
systemctl --user status daily-error-digest.timer

# Disable (stop automated runs)
systemctl --user stop daily-error-digest.timer
systemctl --user disable daily-error-digest.timer
```

---

## Discord Notification Format

**Embed colors:**
- 🔵 **Blue** (< 25 errors): Informational
- 🟡 **Yellow** (25-49 errors): Warning
- 🔴 **Red** (≥ 50 errors): Critical

**Sections:**
- **Summary:** Total error count and lookback period
- **Systemd Errors:** Top 5 failing services with counts
- **Traefik 5xx:** Top 5 backend services with HTTP status codes
- **Remediation Failures:** Top 5 failing playbooks with counts
- **Recommendations:** Contextual next steps based on error patterns

---

## Example Output

**Healthy system (below threshold):**
```
═══════════════════════════════════════════════════════
   DAILY ERROR DIGEST - Last 24h
═══════════════════════════════════════════════════════

▶ Querying systemd journal for errors (priority <= 3)...
  Found: 0 systemd errors

▶ Querying Traefik for 5xx errors...
  Found: 0 Traefik 5xx errors

▶ Querying remediation failures...
  Found: 0 failed remediations

Summary:
  Systemd errors:        0
  Traefik 5xx:           0
  Remediation failures:  0
  Total errors:          0

✓ Error count below threshold (10), skipping Discord notification
═══════════════════════════════════════════════════════
```

**System with errors (Discord sent):**
```
Summary:
  Systemd errors:        15
  Traefik 5xx:           8
  Remediation failures:  2
  Total errors:          25

Systemd Errors (15):
  • immich-server.service (8)
  • nextcloud.service (4)
  • loki.service (3)

Traefik 5xx (8):
  • immich (HTTP 500): 5
  • nextcloud (HTTP 503): 3

Remediation Failures (2):
  • disk-cleanup (1)
  • service-restart (1)

Recommendations:
  • Investigate systemd service failures
  • Review backend service health (5xx = server errors)
```

---

## Troubleshooting

### No Errors Detected (But You See Errors)

**Check Loki ingestion:**
```bash
# Verify Promtail is running
systemctl --user status promtail.service

# Check Loki connectivity
podman exec grafana curl -s "http://loki:3100/ready"

# Test query manually
podman exec grafana curl -s -G "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="systemd-journal"} | json | priority <= "3"' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000"
```

### Discord Not Sent

**Check webhook availability:**
```bash
# Get webhook from container
podman exec alert-discord-relay env | grep DISCORD_WEBHOOK_URL

# Test manually
curl -H "Content-Type: application/json" \
  -d '{"content":"Test from homelab"}' \
  "$DISCORD_WEBHOOK_URL"
```

### Timer Not Running

```bash
# Check timer active
systemctl --user is-active daily-error-digest.timer

# Enable if disabled
systemctl --user enable --now daily-error-digest.timer

# Check logs for errors
journalctl --user -u daily-error-digest.timer -n 20
```

---

## Integration with Monitoring Stack

### Prometheus Metrics (Future Enhancement)

Log-to-metric feedback loops (Week 2-3 plan):

```bash
# Create recording rules from log patterns
# - immich_thumbnail_failures_total (from systemd logs)
# - traefik_backend_5xx_total (from Traefik logs)
# - remediation_failure_rate (from remediation logs)

# Add alerts on derived metrics
# - Alert if immich thumbnail failure rate > 10/hour
# - Alert if traefik 5xx rate > 5/min for any service
# - Alert if remediation failure rate > 20%
```

### Grafana Dashboards

Future panels:
- Error trend over time (daily digest results)
- Top failing services (from digest aggregations)
- Error distribution (systemd vs Traefik vs remediations)

---

## Related Documentation

- **Loki Query Guide:** `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md`
- **Monitoring Stack:** `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- **Automation Reference:** `docs/20-operations/guides/automation-reference.md`

---

**Status:** ✅ Operational (deployed 2026-01-11)
**Next Run:** Daily at 07:00 (check `systemctl --user list-timers`)
