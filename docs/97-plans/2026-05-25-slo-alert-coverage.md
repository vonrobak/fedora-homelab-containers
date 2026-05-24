# Plan B: SLO & Alert Coverage

**Date Created:** 2026-05-25
**Status:** Proposed
**Last Updated:** 2026-05-25
**Implements:** Report [2026-05-25 Monitoring Stack Deep-Dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) §4, §5
**Reconciles with:** `slo-framework.md`, `slo-based-alerting.md`, ADR-003

## Objective

Close the alerting gaps on the owner's **most-valued surface** — the SLO dashboard — so that the
things it *charts* are also things it *alerts on*. Every change here reuses recording rules that
**already exist**; we are adding alert rules and a few thin recording rules, not new pipelines.

## Background (verified 2026-05-25)

- Burn-rate alerts live in `config/prometheus/alerts/slo-multiwindow-alerts.yml`, 4-tier pattern
  (`SLOBurnRateTier{1..4}_<Service>`, thresholds 14.4× / 6× / 3× / 1.5× over paired windows).
- Recording rules live in `config/prometheus/rules/slo-recording-rules.yml` +
  `slo-burn-rate-extended.yml`.
- **G1 (🔴):** `burn_rate:traefik:availability:{1h,5m,6h,30m,1d,2h,3d}` rules exist, the SLO dashboard
  charts Traefik, the monthly report includes it — but there is **no `SLOBurnRateTier*_Traefik` alert**.
- **G2 (🟡):** `sli:<svc>:latency:p95` rules exist for ~6 services, charted in panel 5, **no alert**.
- **G3 (🟡):** `sli:immich:uploads:success_ratio` exists, but no target / error-budget / burn-rate / alert.
- **G4 (🟡):** `NextcloudSustained5xxLowVolume` + `HomeAssistantSustained5xxLowVolume` exist; Navidrome
  (similar low traffic) has no equivalent.
- `slo_compliance` rule group evaluates in 0.364 s every 30 s (10× the next group).

## Approach

### 1. Traefik SLO burn-rate alerts (G1 — highest priority)

Add `SLOBurnRateTier1_Traefik … Tier4_Traefik` to `slo-multiwindow-alerts.yml`, copying the existing
service blocks and substituting the already-present `burn_rate:traefik:availability:*` series. Traefik
uses the `up`-based SLI (no NaN risk), so the expressions are the simplest of the set.

- Target 99.95%, 21-min monthly budget (per `slo-framework.md`).
- Tier 1 → critical (page); Tiers 2–3 → warning; Tier 4 → info, matching the other services' routing.
- Rationale comment: gateway failure is the only single point that fails *every* downstream SLO.

### 2. Latency burn alerts (G2)

Add latency alerts for the latency-sensitive services where slow ≈ broken — start with **Authelia**
(200 ms target), **Traefik** (p99 100 ms), **Jellyfin** (500 ms). Two tiers each:

- Tier 1 (critical): `sli:<svc>:latency:p95 > <target>` sustained over a short+long window pair.
- Tier 2 (warning): same metric, longer window / smaller multiple.

Keep it deliberately small (3 services × 2 tiers) — latency alerts are easy to over-add. HA/Nextcloud
latency stays dashboard-only (WebSocket-heavy, 1 s budget already lenient).

### 3. Immich-upload SLO (G3)

Extend the framework for uploads (SLI already exists):

- Add to `slo-recording-rules.yml`: `slo:immich:uploads:target` (0.995),
  `error_budget:immich:uploads:{total,consumed,remaining}` mirroring the availability budget rules.
- Add to `slo-burn-rate-extended.yml`: `burn_rate:immich:uploads:*` for the four window pairs.
- Add `SLOBurnRateTier1_ImmichUploads` + `Tier2` alerts (uploads are user-data-loss-adjacent → at
  least page + ticket; Tier 3/4 optional).
- Add the upload error budget to the SLO dashboard (one panel row) so the new alert has a visual home.

### 4. Navidrome low-volume 5xx (G4)

Add `NavidromeSustained5xxLowVolume` to `slo-multiwindow-alerts.yml`, mirroring the Nextcloud/HA
compensating alerts (threshold scaled to Navidrome's actual request rate — measure first, then set
e.g. ">N 5xx in 6h at <0.5 req/s"). Closes the last instance of the 2026-04-21 incident class.

### 5. `slo_compliance` eval cost

Lower-priority tuning. Options (pick one in implementation):
- Move the 30-day rolling-compliance rules into their own group with a **longer eval interval**
  (e.g. 1–2 min) — compliance does not need 30 s freshness.
- Or split the heaviest expressions out so they don't serialize behind cheaper SLI rules.
Document the trade-off (slightly staler compliance %, much cheaper eval) in the rule file.

### 6. Documentation

- Update `slo-framework.md`: mark Traefik availability, the three latency SLOs, and Immich-upload as
  **now alerted** (today they read as monitored-only).
- Add an inline comment in `slo-recording-rules.yml` near the Immich block citing the calibration
  rationale (99.9% → 99.5% at ~50 req/day) currently isolated to the guide.

## Success Criteria

- `promtool check rules` passes on all changed files; `amtool config check` passes.
- New alerts visible in Prometheus `/rules` and Alertmanager routing dry-run hits the right receivers
  (critical → discord-critical, warning → discord-warnings, etc.).
- A synthetic burn (temporary low threshold in a scratch copy) fires `SLOBurnRateTier1_Traefik` and
  `SLOBurnRateTier1_ImmichUploads` as expected.
- SLO dashboard gains the Immich-upload budget panel; all existing panels unchanged.
- `slo_compliance` group eval time drops (or its interval lengthens) with no loss of dashboard data.

## Verification

```bash
podman exec prometheus promtool check rules /etc/prometheus/alerts/slo-multiwindow-alerts.yml \
  /etc/prometheus/rules/slo-recording-rules.yml /etc/prometheus/rules/slo-burn-rate-extended.yml
podman exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml   # if amtool present
# confirm the recording rules the new alerts depend on actually return data:
for q in burn_rate:traefik:availability:1h sli:authelia:latency:p95 sli:immich:uploads:success_ratio; do
  podman exec prometheus wget -qO- "http://localhost:9090/api/v1/query?query=$q" | head -c 200; echo
done
# optional: promtool test rules with a unit-test fixture for the new burn-rate alerts
```

## Rollback

Each addition is isolated; `git revert` the alert/rule file. New recording rules only add series
(no mutation). Removing the new alerts cannot affect existing alerting.

## Progress Log

- 2026-05-25 — Plan drafted from deep-dive report. Status: Proposed. Sequence after Plan A (smaller
  TSDB makes burn-rate queries cheaper) but independent of it.
