# Service Level Objectives (SLO) Framework

**Created:** 2025-11-27
**Status:** Active
**Purpose:** Define and track reliability targets for critical homelab services

## Overview

This framework implements Google SRE-style SLOs with multi-window burn-rate alerting to provide proactive reliability monitoring without alert fatigue.

## Core Concepts

### SLI (Service Level Indicator)
The actual measured metric. Examples:
- % of HTTP requests that return 2xx/3xx status codes
- % of requests that complete within 500ms
- % of time the service is available

### SLO (Service Level Objective)
The target reliability level. Examples:
- 99.5% of requests succeed (over 30 days)
- 95% of requests complete <500ms (over 7 days)

### Error Budget
The allowed failure rate. If SLO is 99.5%, error budget is 0.5%.
- Monthly budget: 0.5% = 216 minutes of downtime
- Daily budget: 0.5% = 7.2 minutes

### Burn Rate
How fast we're consuming error budget:
- 1x burn rate = consuming budget at exactly the expected rate
- 2x burn rate = will exhaust budget in 15 days (instead of 30)
- 10x burn rate = will exhaust budget in 3 days

## Defined SLOs

### 1. Jellyfin Media Streaming

**SLO-001: Availability**
- **Target:** 99.5% availability over 30 days
- **SLI:** `(traefik_service_requests_total{exported_service="jellyfin@file", code=~"2..|3.."} / traefik_service_requests_total{exported_service="jellyfin@file"}) * 100`
- **Error Budget:** 216 minutes/month
- **Rationale:** Media streaming should be highly available but occasional maintenance is acceptable

**SLO-002: Response Time**
- **Target:** 95% of requests complete within 500ms over 7 days
- **SLI:** Histogram quantile from `traefik_service_request_duration_seconds`
- **Rationale:** Fast response ensures smooth UI experience

---

### 2. Immich Photo Management

**SLO-003: API Availability**
- **Target:** 99.5% availability over 30 days
- **SLI:** `(traefik_service_requests_total{exported_service="immich@file", code=~"0|2..|3.."} / traefik_service_requests_total{exported_service="immich@file"}) * 100`
- **Error Budget:** 216 minutes/month (~3.6 hours)
- **Rationale:** At ~50 req/day, 99.9% allows only 1.5 failures/month (unrealistic). 99.5% allows ~7 failures/month. Note: code=0 (WebSocket) included as successful.

**SLO-004: Upload Success Rate**
- **Target:** 99.5% of uploads succeed over 7 days
- **SLI:** `(traefik_service_requests_total{exported_service="immich@file", method="POST|PUT", code=~"2.."} / traefik_service_requests_total{exported_service="immich@file", method="POST|PUT"}) * 100`
- **Rationale:** Photos must reliably upload or they're lost

---

### 3. Traefik Reverse Proxy

**SLO-005: Gateway Availability**
- **Target:** 99.95% availability over 30 days
- **SLI:** `avg_over_time(up{job="traefik"}[5m])`
- **Error Budget:** 21 minutes/month
- **Rationale:** Traefik is the gateway - it affects ALL services

**SLO-006: Request Latency**
- **Target:** 99% of requests <100ms over 24 hours
- **SLI:** Histogram quantile from `traefik_entrypoint_request_duration_seconds`
- **Rationale:** Reverse proxy should add minimal latency

---

### 4. ownCloud Infinite Scale (OCIS)

**SLO-007: File Operations Availability**
- **Target:** 99.5% availability over 30 days
- **SLI:** `(traefik_service_requests_total{exported_service="ocis@file", code=~"2..|3.."} / traefik_service_requests_total{exported_service="ocis@file"}) * 100`
- **Error Budget:** 216 minutes/month
- **Rationale:** File storage should be reliable for daily use

---

### 5. Authelia Authentication

**SLO-008: Authentication Availability**
- **Target:** 99.9% availability over 30 days
- **SLI:** `(traefik_service_requests_total{exported_service="authelia@file", code=~"2..|3.."} / traefik_service_requests_total{exported_service="authelia@file"}) * 100`
- **Error Budget:** 43 minutes/month
- **Rationale:** Auth failures block access to all protected services

**SLO-009: Authentication Latency**
- **Target:** 95% of auth requests <200ms over 24 hours
- **SLI:** Histogram quantile from `traefik_service_request_duration_seconds{exported_service="authelia@file"}`
- **Rationale:** Slow auth creates poor user experience

---

## Multi-Window Burn-Rate Alerting

We use Google's recommended multi-window, multi-burn-rate alerting to balance sensitivity and precision:

### Page (Critical Alert)
Fires when error budget is being consumed dangerously fast:
- **Short window:** 1-hour burn rate >14.4x AND 5-minute burn rate >14.4x
- **Meaning:** At this rate, will exhaust 2% of monthly budget in 1 hour
- **Action:** Immediate investigation required

### Ticket (Warning Alert)
Fires when error budget consumption is elevated but not critical:
- **Long window:** 6-hour burn rate >6x AND 30-minute burn rate >6x
- **Meaning:** At this rate, will exhaust 5% of monthly budget in 6 hours
- **Action:** Investigate when convenient, track trends

### Why Multi-Window?
- **Short + long windows:** Prevents false positives from brief spikes
- **Different burn rates:** Balances fast detection vs alert fatigue
- **Two severity levels:** Distinguishes urgent vs important

## Error Budget Policy

### When Error Budget is Healthy (>50% remaining)
- New feature rollouts allowed
- Experimental changes acceptable
- Normal deployment cadence

### When Error Budget is Low (<20% remaining)
- Freeze non-critical changes
- Focus on reliability improvements
- Increase monitoring

### When Error Budget is Exhausted (0% remaining)
- Feature freeze (except reliability fixes)
- Blameless postmortem required
- Identify and fix root causes

## Measurement Windows

- **Availability SLOs:** 30-day rolling window
- **Latency SLOs:** 7-day rolling window (more sensitive to recent changes)
- **Critical services:** 24-hour window for faster feedback

## Dashboard Organization

### SLO Overview Dashboard
- Error budget remaining for all services (bar chart)
- Current burn rates (heatmap)
- SLO compliance status (green/yellow/red)

### Per-Service Dashboard
- SLI trend over time
- Error budget consumption rate
- Recent incidents affecting SLO
- Top error contributors

## Monthly Discord Reports

**Automated Report Schedule:** 1st of each month at 9:00 AM (±15min randomization)

The monthly SLO report provides a comprehensive overview of service reliability:

### Report Content
- **Overall Status:** Health summary with color-coded status
  - 🟢 Green: All SLOs met
  - 🟠 Orange: 1-2 SLO violations
  - 🔴 Red: 3+ SLO violations
- **Per-Service Metrics:**
  - ✅/❌ Compliance status
  - Actual availability percentage (30-day rolling)
  - Error budget remaining
- **Key Insights:** Services monitored, SLOs met ratio, reporting period
- **Recommendations:** Automated guidance based on violation severity

### Manual Execution

To run the report immediately (for testing or ad-hoc reporting):
```bash
~/containers/scripts/monthly-slo-report.sh
```

The report sends directly to your Discord channel via the webhook configured in `alert-discord-relay`.

### View Scheduled Execution

Check next report time:
```bash
systemctl --user list-timers | grep monthly-slo-report
```

View service status:
```bash
systemctl --user status monthly-slo-report.timer
```

### Troubleshooting

**"No data" or "N/A" values:**
- Expected during first 30 days (SLOs require rolling window data)
- Check Prometheus is scraping Traefik: `curl http://localhost:9090/targets`
- Verify services have received traffic (idle services show N/A)

**Report not sent:**
- Check timer is active: `systemctl --user is-active monthly-slo-report.timer`
- View execution logs: `journalctl --user -u monthly-slo-report.service`
- Verify Discord webhook: `podman exec alert-discord-relay env | grep DISCORD_WEBHOOK_URL`

## Operations Guide

### Responding to Burn-Rate Alerts

**Critical Alert (14.4x burn rate):**
1. Check Alertmanager for active incident
2. Identify affected service and error types
3. Review recent deployments/changes
4. Mitigate issue (rollback, restart, etc.)
5. Document incident for postmortem

**Warning Alert (6x burn rate):**
1. Note the service and time of elevated errors
2. Check if pattern persists or was transient
3. Review logs for error patterns
4. Schedule investigation if recurring
5. Monitor error budget consumption

### Interpreting Monthly Reports

**Error Budget Remaining:**
- `>75%` - Excellent (green) - Safe to deploy features
- `50-75%` - Good (yellow) - Normal operations
- `25-50%` - Caution (orange) - Review recent incidents
- `<25%` - Critical (red) - Deployment freeze recommended

**Compliance Status:**
- ✅ Met: Service exceeded SLO target
- ❌ Violated: Service failed to meet target
  - Review error budget policy
  - Identify contributing incidents
  - Plan reliability improvements

### Using Grafana Dashboard

Access the SLO dashboard at: `https://grafana.patriark.org/d/slo-dashboard`

**Key Panels:**
1. **Error Budget Remaining** - Quick health check for all services
2. **Current Burn Rate** - Real-time consumption rate
3. **Availability Trend** - 7-day historical view
4. **Response Time Latency** - P95/P99 percentiles

## Implementation Status

- [x] SLO definitions documented (9 SLOs across 5 services)
- [x] Prometheus recording rules created (79 rules: SLI, error budget, burn rate)
- [x] Error budget calculations implemented (15 tracking rules)
- [x] Multi-window burn-rate alerts configured (11 alerts: critical + warning)
- [x] Grafana dashboards created (SLO dashboard + fixed 6 existing dashboards)
- [x] Monthly reporting automated (systemd timer + Discord webhook integration)

**Implementation Date:** 2025-11-27
**Status:** ✅ Production-ready

## References

- [Google SRE Book - Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook - Chapter 5: Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Implementing SLOs (Google Cloud)](https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring)
