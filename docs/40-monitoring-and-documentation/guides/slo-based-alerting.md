# SLO-Based Alerting - Implementation Guide

**Created:** 2025-12-19
**Status:** Production
**Approach:** Google SRE Book - Multi-Window, Multi-Burn-Rate Methodology

---

## Overview

This homelab uses **SLO-based alerting** instead of traditional symptom-based alerts. This is the same approach used by Google, Netflix, and other tech giants to achieve world-class reliability.

**Philosophy:** Alert on **user-impacting degradation** (SLO violations), not individual component failures.

---

## Why SLO-Based Alerting?

### The Problem with Symptom-Based Alerts

Traditional alerting fires on symptoms:
- "CPU >90%" - But is this affecting users?
- "Disk >80%" - But is the service degraded?
- "Container restarted" - But did users notice?

**Result:** Alert fatigue from false positives and noise.

### The SLO-Based Solution

SLO alerting fires on **actual user impact**:
- "Error rate increasing - users experiencing failures"
- "Latency degraded - users waiting longer than SLO promises"
- "Upload success rate dropping - users can't upload photos"

**Result:** Every alert means users are impacted RIGHT NOW.

---

## Multi-Window, Multi-Burn-Rate Alerting

### The Four-Tier Approach

Our implementation uses **4 tiers** of burn rate detection to catch issues at different time scales:

```
┌─────────┬──────────────┬───────────────┬──────────────┬─────────────┐
│ Tier    │ Windows      │ Budget Left   │ Severity     │ Action      │
├─────────┼──────────────┼───────────────┼──────────────┼─────────────┤
│ Tier 1  │ 1h + 5m      │ 2% (58 min)   │ Critical     │ Page        │
│ Tier 2  │ 6h + 30m     │ 5% (2.4 hrs)  │ Warning      │ Ticket      │
│ Tier 3  │ 1d + 2h      │ 10% (3 days)  │ Warning      │ Ticket      │
│ Tier 4  │ 3d + 6h      │ 20% (7 days)  │ Info         │ Review      │
└─────────┴──────────────┴───────────────┴──────────────┴─────────────┘
```

### Why Multiple Windows?

**Two windows per tier** prevent false positives:
- **Long window** (1h, 6h, 1d, 3d) - Detects the trend
- **Short window** (5m, 30m, 2h, 6h) - Confirms it's ongoing

**Both must be elevated** before the alert fires.

**Example:**
```
Scenario: Brief 2-minute outage

Without short window:
- 1h window sees 3.3% error rate
- Alert fires (false positive - issue already resolved)

With short window (5m):
- 1h window: 3.3% (elevated)
- 5m window: 0% (normal - issue resolved)
- Alert does NOT fire ✓
```

---

## Our SLO Targets

| Service  | SLO Target | Error Budget | Allowed Downtime/Month |
|----------|-----------|--------------|------------------------|
| Jellyfin | 99.5%     | 0.5%         | 216 minutes (~3.6 hrs) |
| Immich   | 99.5%     | 0.5%         | 216 minutes (~3.6 hrs) |
| Authelia | 99.9%     | 0.1%         | 43 minutes             |
| Traefik  | 99.95%    | 0.05%        | 21 minutes             |
| OCIS     | 99.5%     | 0.5%         | 216 minutes            |

---

## Alert Interpretation Guide

### Tier 1: CRITICAL (Page Immediately)

**Trigger:** Burn rate >14.4x normal

**Meaning:** At current error rate, **monthly error budget exhausts in <3 hours**

**Example:**
```
Alert: SLOBurnRateTier1_Jellyfin
Burn Rate (1h): 20x normal
Budget Remaining: 30%

Translation: Jellyfin is failing 20% of requests. If this continues for 3 more
hours, we'll consume the entire monthly error budget and violate our SLO.
```

**Action:** Drop everything and investigate immediately.

---

### Tier 2: WARNING (Create Ticket)

**Trigger:** Burn rate >6x normal

**Meaning:** Budget exhausts in <1 day

**Example:**
```
Alert: SLOBurnRateTier2_Immich
Burn Rate (6h): 8x normal
Budget Remaining: 60%

Translation: Immich error rate is elevated. If this continues for 24 hours,
we'll exhaust the monthly budget.
```

**Action:** Investigate within hours. Can wait until business hours but don't ignore.

---

### Tier 3: WARNING (Plan Remediation)

**Trigger:** Burn rate >3x normal

**Meaning:** Budget exhausts in <1 week

**Action:** Monitor trend. Consider freezing non-critical changes to preserve reliability.

---

### Tier 4: INFO (Long-term Trend)

**Trigger:** Burn rate >1.5x normal

**Meaning:** Budget exhausts in ~2 weeks

**Action:** Review in monthly SLO report. No immediate action needed.

---

## Error Budget Forecasting

We calculate **days until budget exhaustion** based on current 3-day burn rate:

```promql
error_budget:jellyfin:availability:days_remaining =
  (budget_remaining / current_3d_burn_rate) * 30
```

**Usage:**
- **>14 days:** Healthy, no concerns
- **7-14 days:** Monitor, consider change freeze
- **3-7 days:** Active issue, investigate
- **<3 days:** Critical, immediate action

---

## Migration from Symptom Alerts to SLO Alerts

### Phase 1: Run Both (Current State)

Keep traditional alerts AND SLO alerts running in parallel. Compare:
- When do symptom alerts fire vs. SLO alerts?
- Are symptom alerts actionable?
- Do SLO alerts catch the same issues?

### Phase 2: Tune SLO Sensitivity

If SLO alerts fire too late:
- Lower burn rate thresholds
- Add intermediate tiers

If SLO alerts fire too often:
- Raise burn rate thresholds
- Increase `for` duration

### Phase 3: Disable Redundant Symptom Alerts

**Candidates for Deletion:**
```yaml
# These are covered by SLO alerts:
- HighCPUUsage              # → SLO latency tier
- MemoryPressureHigh        # → SLO latency tier
- ContainerNotRunning       # → SLO availability tier
- GrafanaDown               # → Not user-facing (keep)
- JellyfinDown              # → SLO availability tier

# Keep these (not covered by SLOs):
- DiskSpaceCritical         # Infrastructure health
- BackupFailed              # Data safety
- CertificateExpiringSoon   # Preventive
- CrowdSecDown              # Security
```

### Phase 4: Pure SLO Alerting

Only alert on:
1. **SLO violations** (user impact)
2. **Infrastructure health** (disk, backups)
3. **Security** (auth failures, attacks)

---

## Querying SLO Metrics

### Check Current SLO Compliance

```bash
# All services
curl -s 'http://localhost:9090/api/v1/query?query={__name__=~"slo:.*:actual"}' | \
  jq -r '.data.result[] | "\(.metric.__name__ | sub("slo:"; "") | sub(":actual"; "")): \(.value[1])"'

# Specific service
curl -s 'http://localhost:9090/api/v1/query?query=slo:jellyfin:availability:actual*100'
```

### Check Error Budget Remaining

```bash
curl -s 'http://localhost:9090/api/v1/query?query=error_budget:jellyfin:availability:budget_remaining*100'
```

### Check Burn Rate

```bash
# Current 1h burn rate
curl -s 'http://localhost:9090/api/v1/query?query=burn_rate:jellyfin:availability:1h'

# All burn rates for a service
curl -s 'http://localhost:9090/api/v1/query?query={__name__=~"burn_rate:jellyfin:.*"}'
```

### Forecast Budget Exhaustion

```bash
curl -s 'http://localhost:9090/api/v1/query?query=error_budget:jellyfin:availability:days_remaining'
```

---

## Troubleshooting

### Alert Firing But Service Seems Fine

**Check both windows:**
```bash
# Long window (trend)
curl -s 'http://localhost:9090/api/v1/query?query=burn_rate:jellyfin:availability:1h'

# Short window (current)
curl -s 'http://localhost:9090/api/v1/query?query=burn_rate:jellyfin:availability:5m'
```

If long window is elevated but short window is normal → **Issue resolved**, alert will clear soon.

### No Alerts But SLO is Violated

Check if you're in the error budget:
```bash
curl -s 'http://localhost:9090/api/v1/query?query=error_budget:jellyfin:availability:budget_remaining'
```

If budget is >0%, you're still within SLO even with errors. This is expected! Error budgets exist to be spent.

### SLO Metrics Missing

Check Prometheus has been running long enough:
- Tier 1 alerts: Requires 1h of data
- Tier 2 alerts: Requires 6h of data
- Tier 3 alerts: Requires 1d of data
- Tier 4 alerts: Requires 3d of data

---

## References

- **Google SRE Book:** Chapter 5 - "Eliminating Toil"
- **Google SRE Workbook:** Chapter 5 - "Alerting on SLOs"
- **Multi-Window Alert Paper:** https://sre.google/workbook/alerting-on-slos/

---

## Files

**Recording Rules:**
- `/config/prometheus/rules/slo-recording-rules.yml` - SLIs, SLOs, error budgets
- `/config/prometheus/rules/slo-burn-rate-extended.yml` - Extended burn rate windows

**Alert Rules:**
- `/config/prometheus/alerts/slo-multiwindow-alerts.yml` - Multi-window burn rate alerts
- `/config/prometheus/alerts/slo-burn-rate-alerts.yml.disabled` - Old 2-window alerts (disabled)

**Dashboard:**
- Grafana: https://grafana.patriark.org/d/slo-dashboard (if configured)
