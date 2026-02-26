# SLO System Diagnostic and Quick Fixes

**Date:** 2026-02-26
**Type:** System diagnostic and bug fixes
**Outcome:** 5 bugs fixed across 4 files, 55 days of blind data collection resolved

---

## Context

Ran `analyze-slo-trends.sh` on February data and discovered the entire CSV was null — 246 data points across 25 days, zero actual values. Investigated the full SLO pipeline from Prometheus recording rules through snapshot collection to trend analysis.

## Root Cause: BoltDB Warning Corrupts JSON

The `query_prom()` function in both `daily-slo-snapshot.sh` and `monthly-slo-report.sh` used `2>&1` to merge stderr into stdout before piping to `jq`. In interactive shells this is harmless, but when running as a systemd service, Podman emits a BoltDB deprecation warning to stderr:

```
time="..." level=warning msg="The deprecated BoltDB database driver is in use..."
```

This warning prepends to the JSON response, breaking `jq` parsing. The `|| echo "null"` fallback kicks in, producing null for every query. This has been broken since **Jan 9, 2026** — the first timer-triggered run after the initial manual test.

**Fix:** `2>&1` → `2>/dev/null` in both scripts.

**Reproduced with:** `systemd-run --user --wait --pipe -- bash -c 'podman exec prometheus wget ... 2>&1'` confirmed the warning appears only in systemd context.

## Current SLO Performance (Live from Prometheus)

| Service | 30d SLI | Target | Error Budget | Status |
|---------|---------|--------|--------------|--------|
| Authelia | 100.00% | 99.9% | Full | Excellent |
| Jellyfin | 99.98% | 99.5% | 96% | Excellent |
| Traefik | 99.99% | 99.95% | 73% | Healthy |
| Immich | 99.91% | 99.5% | 83% | Healthy |
| Nextcloud | 99.00% | 99.5% | Exhausted | Non-compliant |
| Home Assistant | 97.72% | 99.5% | Exhausted | Non-compliant |

### Nextcloud (99.00%)

Biggest error contributor: 590 503s from a past incident (>7d ago, already 0 in recent windows). Will naturally age out of the 30d rolling window in ~3 weeks. Ongoing drag: ~16 403s/day (CrowdSec/rate-limit blocks). Last 24h is 99.85% (healthy).

### Home Assistant (97.72%)

Low-traffic amplification problem. Only 1,449 total requests in 30 days (~48/day). Just 33 404 errors are responsible for the entire SLO violation — each 404 costs 0.07% of the SLI. The 404s are ongoing (~2/day), likely from bots or misconfigured clients. Not a reliability problem, but the SLI definition makes it look like one.

## Burn Rate NaN Issue

All request-based burn rates returned `NaN` during quiet hours because `rate(total[1h])` = 0 when there's no traffic, producing 0/0. Changed formula from `1 - (success/total)` to `(total - success) / clamp_min(total, 1e-10)`. When traffic=0: `(0-0)/1e-10 = 0` (no errors, correct). 20 rules across 5 services updated.

## All Fixes Applied

| Fix | File | Detail |
|-----|------|--------|
| Snapshot null bug | `scripts/daily-slo-snapshot.sh` | `2>&1` → `2>/dev/null` |
| Monthly report same bug | `scripts/monthly-slo-report.sh` | `2>&1` → `2>/dev/null` |
| Immich target mismatch | `scripts/daily-slo-snapshot.sh` | `0.999` → `0.995` (matches recording rules since Feb 7) |
| Home Assistant missing | `scripts/daily-slo-snapshot.sh` | Added to SERVICES array with 0.995 target |
| Home Assistant in trends | `scripts/analyze-slo-trends.sh` | Added to service loop and count |
| Burn rate NaN | `config/prometheus/rules/slo-recording-rules.yml` | 20 rules rewritten with `clamp_min` denominator |

## Verification

- `systemd-run` test confirmed snapshot now produces real values in systemd context
- Prometheus reloaded without errors (SIGHUP)
- Burn rates return `0` instead of `NaN` for idle services
- All 6 services tracked in daily snapshots

## Future Considerations

- **SLI refinement:** Current SLI counts all 4xx as failures. For low-traffic services like HA, consider only counting 5xx. The 403/404 errors are client-side, not service availability failures.
- **Traefik burn rate:** Returns null (pre-existing, uses `up` metric with different formula). Low priority since Traefik availability is 99.99%.
- **Podman BoltDB migration:** The underlying warning is about migrating from BoltDB to SQLite before Podman 6.0 (mid-2026). Worth doing proactively.
