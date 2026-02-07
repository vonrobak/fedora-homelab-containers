# SLO Target Calibration Process

**Created:** 2026-01-09
**Status:** Active - Data Collection Phase
**Purpose:** Document the process for calibrating SLO targets based on actual performance data

---

## Overview

This guide documents the process for collecting and analyzing SLO performance data to calibrate targets based on observed 95th percentile availability rather than initial estimates.

**Key Principle:** SLO targets should be based on **realistic achievable performance**, not aspirational goals that cause constant violations.

---

## Data Collection

### Automated Daily Snapshots

**Script:** `/home/patriark/containers/scripts/daily-slo-snapshot.sh`

**Schedule:** Daily at 23:50 (via systemd timer: `daily-slo-snapshot.timer`)

**Data Captured:**
- Timestamp
- Service name
- Availability actual (30-day rolling window)
- Availability target
- Error budget remaining
- Compliance status (1=met, 0=violated)

**Storage:** `/home/patriark/containers/data/slo-snapshots/slo-daily-YYYY-MM.csv`

**Retention:** 90 days (automatically pruned)

### Services Tracked

| Service | Current Target | SLO ID | Rationale |
|---------|----------------|--------|-----------|
| **Jellyfin** | 99.50% | SLO-001 | Media streaming, maintenance acceptable |
| **Immich** | 99.50% | SLO-003 | Photo management (lowered from 99.9% - unrealistic at ~50 req/day) |
| **Authelia** | 99.90% | SLO-008 | Auth failures block all services |
| **Traefik** | 99.95% | SLO-005 | Gateway affects ALL services |
| **Nextcloud** | 99.50% | SLO-007 | File storage for daily use |

---

## Analysis Process

### Monthly Analysis Script

**Script:** `/home/patriark/containers/scripts/analyze-slo-trends.sh`

**Usage:**
```bash
# Analyze current month
~/containers/scripts/analyze-slo-trends.sh

# Analyze specific month
~/containers/scripts/analyze-slo-trends.sh 2026-01
```

**Metrics Calculated:**
- **Mean availability:** Average performance over collection period
- **95th percentile:** Recommended SLO target (achievable 95% of time)
- **Min/Max:** Performance range
- **Compliance days:** Days meeting vs violating target
- **Recommendations:** Whether to adjust targets based on p95

### Calibration Timeline

**Phase 1: Initial Data Collection (Jan 9 - Jan 31, 2026)**
- Daily snapshots collected automatically
- 22+ data points minimum for meaningful analysis
- Current targets remain unchanged during collection

**Phase 2: Analysis & Calibration (Feb 1, 2026)**
- Run `analyze-slo-trends.sh 2026-01` for January analysis
- Review recommendations per service
- Calculate realistic targets: **p95 - 0.5% buffer**
- Document calibration decisions in journal

**Phase 3: Implementation (Feb 2-5, 2026)**
- Update Prometheus recording rules with new targets
- Update SLO framework documentation
- Monitor for 7 days to validate new targets

**Phase 4: Ongoing Validation (Feb 12+)**
- Monthly reviews of SLO compliance
- Re-calibrate if sustained violations occur
- Document any target adjustments

---

## Calibration Methodology

### Why 95th Percentile?

**Google SRE Principle:** SLOs should be based on what you can realistically achieve, not what sounds impressive.

**Benefits:**
- Accounts for occasional incidents (5% of days can have issues)
- Prevents alert fatigue from unrealistic targets
- Allows for planned maintenance and deployments
- Focuses attention on actual outages vs transient blips

### Buffer Calculation

**Formula:** `Calibrated Target = p95 - 0.5%`

**Example:**
- Service achieves 99.8% at 95th percentile
- Calibrated target: 99.8% - 0.5% = **99.3%**
- This allows for error budget consumption while remaining compliant most of the time

**Why -0.5% buffer?**
- Provides headroom for future incidents
- Accounts for seasonal variation
- Prevents targets from being "too tight" to achieve

### Special Considerations

**Traefik (Gateway):**
- Highest target (99.95%) because downtime affects ALL services
- Should maintain tighter target even if p95 allows higher

**Authentication (Authelia):**
- High target (99.90%) because auth failures block access
- Consider keeping aggressive target for critical security service

**Media/Files (Jellyfin, Nextcloud):**
- More lenient targets (99.50%) acceptable
- Users tolerate occasional maintenance windows
- Focus on user experience over raw uptime

---

## Decision Framework

### When to Adjust Targets DOWN

**Indicators:**
- 95th percentile consistently below current target
- >50% of days in violation
- Error budget frequently exhausted
- Realistic incidents (not misconfigurations)

**Action:** Lower target to p95 - 0.5% to reflect achievable reliability

**Example:**
```
Service: Immich
Current Target: 99.90%
Observed p95: 98.5%
Recommendation: Adjust to 98.0% (98.5% - 0.5%)
Rationale: Service experiences regular incidents, current target unrealistic
```

### When to Adjust Targets UP

**Indicators:**
- 95th percentile significantly above current target
- 100% compliance over 3+ months
- Error budget consistently >75% remaining
- No architectural limitations preventing higher reliability

**Action:** Increase target by 0.1-0.2% increments

**Example:**
```
Service: Traefik
Current Target: 99.95%
Observed p95: 99.99%
Recommendation: Increase to 99.97% (tighten 0.02%)
Rationale: Service demonstrates exceptional stability
```

### When to Keep Targets UNCHANGED

**Indicators:**
- 95th percentile within ±0.3% of current target
- 60-80% compliance (some violations, but manageable)
- Error budget consumption rate is sustainable
- No architectural changes planned

**Action:** Maintain current target, continue monitoring

---

## January 2026 Baseline (Initial Data)

**Collection Start:** January 9, 2026
**First Snapshot:** 10:06 CET

**Initial 30-Day Rolling Window Performance:**
| Service | Availability | Target | Budget | Status | Notes |
|---------|--------------|--------|--------|--------|-------|
| **Traefik** | 100.00% | 99.95% | +93.11% | ✅ COMPLIANT | Exceptional stability |
| **Authelia** | 99.87% | 99.90% | -25% | ❌ VIOLATION | Very close, minor incident |
| **Nextcloud** | 99.03% | 99.50% | -95% | ❌ VIOLATION | December incidents in window |
| **Jellyfin** | 97.71% | 99.50% | -358% | ❌ VIOLATION | December incidents in window |
| **Immich** | 89.01% | 99.90% | -10,889% | ❌ MAJOR | December major incident |

**Context:** Rolling 30-day window includes December incidents. As January progresses and system remains stable, these numbers will improve as old incident data ages out.

**Next Analysis:** February 1, 2026 (with 22+ days of January data)

---

## Operational Procedures

### Check Timer Status

```bash
# Verify timer is active
systemctl --user status daily-slo-snapshot.timer

# Check next run time
systemctl --user list-timers | grep slo-snapshot

# View recent execution logs
journalctl --user -u daily-slo-snapshot.service -n 20
```

### Manual Snapshot

```bash
# Force snapshot immediately
~/containers/scripts/daily-slo-snapshot.sh

# Verify data captured
tail -5 ~/containers/data/slo-snapshots/slo-daily-$(date +%Y-%m).csv
```

### View Historical Data

```bash
# View all January snapshots
cat ~/containers/data/slo-snapshots/slo-daily-2026-01.csv

# Count data points per service
tail -n +2 ~/containers/data/slo-snapshots/slo-daily-2026-01.csv | cut -d',' -f2 | sort | uniq -c

# View specific service trend
grep "jellyfin" ~/containers/data/slo-snapshots/slo-daily-2026-01.csv
```

### Run Analysis

```bash
# Analyze current month (needs 3+ data points for meaningful results)
~/containers/scripts/analyze-slo-trends.sh

# Analyze previous month
~/containers/scripts/analyze-slo-trends.sh 2026-01
```

---

## Troubleshooting

### No Data Collected

**Symptom:** CSV file empty or missing

**Causes & Fixes:**
1. Timer not enabled: `systemctl --user enable --now daily-slo-snapshot.timer`
2. Prometheus not accessible: `podman exec prometheus wget -O- http://localhost:9090/-/healthy`
3. Script permissions: `chmod +x ~/containers/scripts/daily-slo-snapshot.sh`

### Analysis Shows "No Data"

**Symptom:** `analyze-slo-trends.sh` reports no data

**Causes & Fixes:**
1. Wrong month specified: Check filename matches `slo-daily-YYYY-MM.csv`
2. CSV header only: Script needs 1+ day of actual data
3. Prometheus recording rules not active: Check `/config/prometheus/rules/slo-recording-rules.yml` loaded

### Percentile Calculations Wrong

**Symptom:** p95 shows 0% or unrealistic values

**Causes & Fixes:**
1. Not enough data points: Need 3+ snapshots for meaningful percentile
2. Single data point: p95 calculation requires multiple samples
3. Wait until more data collected (script works correctly with 5+ days)

---

## Integration with Monthly Reports

The existing **monthly SLO report** (sent via Discord on 1st of each month) continues to operate independently:

**Report Script:** `/home/patriark/containers/scripts/monthly-slo-report.sh`
**Timer:** `monthly-slo-report.timer`
**Schedule:** 1st of month at 10:00 (±15min)

**Relationship:**
- Monthly report = **compliance status** (did we meet targets?)
- Daily snapshots = **calibration data** (should we adjust targets?)
- Both use same Prometheus metrics (`slo:*:availability:actual`)

---

## References

- [SLO Framework Guide](slo-framework.md) - Core SLO definitions and concepts
- [Google SRE Book - Chapter 4](https://sre.google/sre-book/service-level-objectives/) - SLO theory
- [Implementing SLOs](https://sre.google/workbook/implementing-slos/) - Practical guidance
- Prometheus recording rules: `/home/patriark/containers/config/prometheus/rules/slo-recording-rules.yml`

---

**Keywords:** SLO, calibration, 95th percentile, error budget, reliability engineering, data-driven operations, Course 2, Q1 2026
