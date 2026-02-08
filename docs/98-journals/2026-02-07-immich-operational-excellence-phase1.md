# Immich Operational Excellence: Phase 1 - Server Verification & Monitoring Fix

**Date:** 2026-02-07
**Author:** Claude Opus 4.6
**Status:** Phase 1 complete. Phases 2-6 pending (client testing, resilience, documentation finalization).

---

## Summary

Immich was identified as having recurring SLO failures, occasional Discord alerts for thumbnail failures, and a 3-month-stale service guide referencing the wrong URL. A comprehensive investigation revealed that the SLO compliance failures were largely caused by a **systemic WebSocket accounting bug** across the entire SLO framework, not by Immich instability. After fixing the bug, adjusting the SLO target to match Immich's traffic profile, eliminating an NaN metric, and overhauling the service guide, Immich is now correctly monitored and ready for multi-device client testing.

**Key outcome:** Immich availability jumped from 96.8% to 98.87% without any service changes -- purely by fixing how we measure it.

---

## Findings

### The WebSocket Code=0 Bug (Systemic, All Services)

**This is the most important discovery of the session and affects the entire SLO framework.**

Traefik reports WebSocket connections with HTTP status `code="0"`. This is not an error -- it's how Traefik internally represents a successful WebSocket upgrade, which doesn't map to a traditional HTTP response code. However, all SLO recording rules used `code=~"2..|3.."` to identify successful requests, which excluded WebSocket connections entirely.

**Impact by service over 30 days:**

| Service | WebSocket code=0 | Total Requests | False Failure Rate |
|---------|-----------------|----------------|-------------------|
| Home Assistant | 437 | ~2,800 | ~15.6% |
| Immich | 31 | 1,504 | ~2.1% |
| Jellyfin | 12 | ~800 | ~1.5% |
| Nextcloud | 0 | ~15,000 | 0% |
| Authelia | 0 | ~4,000 | 0% |

Home Assistant has been the worst affected -- 437 WebSocket connections silently counted as failures. This likely explains many historical SLO violations that were attributed to actual service issues.

**Fix applied:** Changed `code=~"2..|3.."` to `code=~"0|2..|3.."` across three files:
- `config/prometheus/rules/slo-recording-rules.yml` (SLI calculations, 30d SLO compliance, burn rates)
- `config/prometheus/rules/slo-burn-rate-extended.yml` (extended burn rate windows)

**Gotcha for future reference:** Any new service added to SLO monitoring that supports WebSocket must use the `code=~"0|2..|3.."` pattern, not `code=~"2..|3.."`. This should be added to the deployment pattern templates.

### Immich 502 Errors: Residual, Not Active

The 16 HTTP 502 errors in the 30-day window all trace back to the February 2 thumbnail failure incident (7,222 failures in burst, resolved by container recreation on Feb 4). There are:
- **Zero** 502 errors in the current Prometheus 15-day retention window
- **Zero** errors in Immich server journal logs over the past 7 days
- **Zero** thumbnail failures in the Promtail counter
- **Zero** container restarts since the Feb 4 recovery

The 502s will roll out of the 30d SLO window naturally. No remediation needed.

### Upload SLO NaN: PromQL Division-by-Zero Edge Case

`sli:immich:uploads:success_ratio` returned NaN because Immich receives ~50 requests/day, and uploads (POST/PUT/PATCH) are infrequent. When the 5-minute rate window contains zero uploads, both numerator and denominator are 0, producing `0/0 = NaN`.

**Key PromQL lesson:** NaN is not the same as "no data" (empty vector). The `or` operator only fires for empty vectors, not NaN. This means the common pattern `(expr) or vector(1)` does NOT protect against NaN.

**What doesn't work:**
```promql
# FAILS: NaN or vector(1) = NaN (NaN is a value, not absent)
(success / total) or vector(1)

# FAILS: NaN and (0) = NaN (NaN propagates through and)
(success / total) and (total > bool 0) or (0 * total + 1)
```

**What works:**
```promql
# Prevent division by zero using clamp_min, then add 1 when total was 0
clamp_max(
  success / clamp_min(total, 0.001) + (total < bool 0.001),
  1
)
```

This evaluates to:
- When `total > 0`: `success / total + 0` = actual ratio (clamped to max 1)
- When `total = 0`: `0 / 0.001 + 1` = `0 + 1` = `1` (100% -- no failures when no requests)

**Gotcha for future reference:** Any SLO ratio that can have a zero denominator needs this `clamp_min` + conditional addition pattern, not `or vector(1)`.

### SLO Target Calibration: 99.9% Was Unrealistic

At ~50 requests/day (~1,500/month), a 99.9% SLO target allows only **1.5 failed requests per month**. A single transient 502 consumes 66% of the error budget. Two consecutive failures during a restart exhaust it entirely.

**New target: 99.5%** (matching Jellyfin and Nextcloud).
- Error budget: 0.5% = ~7.5 failed requests/month = **216 minutes of downtime equivalent**
- This accommodates occasional container restarts, Traefik reloads, and transient errors
- Still meaningful as an availability indicator (a real outage will breach it quickly)

The 99.9% target was appropriate for high-traffic services (Authelia: ~4,000 req/month, Traefik: direct `up` metric). For low-traffic services, SLO targets must account for the statistical reality that each failure has outsized impact.

**Gotcha for future reference:** When adding a new service to SLO monitoring, estimate its request volume first. If <200 req/day, start at 99.5%. Only escalate to 99.9% for services with >1,000 req/day.

### Prometheus Retention Is 15 Days, SLO Window Is 30 Days

Prometheus retention is configured at 15 days, but SLO compliance uses `increase(...[30d])` -- a 30-day window. This works because Prometheus can evaluate `increase()` over ranges longer than retention by using the oldest available data point and extrapolating, but it means:

1. Root cause investigation of errors older than 15 days requires Loki (log retention is longer)
2. The 30d SLO calculation becomes increasingly approximate as data points age out
3. After a major incident, it takes a full 30 days for the SLO to fully recover, even though the Prometheus data showing the incident disappears after 15 days

This is not a bug but something to be aware of when interpreting SLO compliance numbers.

### Immich v2.5.5 Available

During the investigation, Immich server logs showed it detected v2.5.5 as available (released Feb 6, 2026). The current deployment pins v2.5.2. This is worth evaluating for the update cycle but is not urgent -- the current version is stable and healthy.

### Loki Log Format: Binary Byte Arrays

When querying Loki via its HTTP API directly, journal log entries are returned as arrays of byte values (e.g., `[27,91,51,50,109,...]`), not readable strings. These are the raw bytes from the systemd journal export format including ANSI escape codes. Practical consequence: for Immich log analysis, always prefer `journalctl --user -u immich-server.service` over direct Loki API queries. Use Loki/LogQL through Grafana Explore for a decoded view.

---

## Changes Made

### Prometheus Recording Rules (`config/prometheus/rules/slo-recording-rules.yml`)

| Change | Scope | Impact |
|--------|-------|--------|
| `code=~"2..\|3.."` → `code=~"0\|2..\|3.."` | All 5 services, all rule groups | WebSocket connections correctly counted as successful |
| `slo:immich:availability:target` 0.999 → 0.995 | Immich only | Realistic target for ~50 req/day traffic |
| `error_budget:immich:...:budget_total` 0.001 → 0.005 | Immich only | Matches new 99.5% target |
| `sli:immich:uploads:success_ratio` rewritten | Immich uploads only | Eliminates NaN when no uploads in window |

### Prometheus Extended Burn Rates (`config/prometheus/rules/slo-burn-rate-extended.yml`)

| Change | Scope |
|--------|-------|
| `code=~"2..\|3.."` → `code=~"0\|2..\|3.."` | All 4 services (1d, 2h, 3d windows) |

### Documentation

| File | Change |
|------|--------|
| `docs/10-services/guides/immich.md` | Complete rewrite: correct URL, version, 3-network topology, static IPs, SLO section, middleware chain, actual resource usage, removed stale GPU deployment focus |
| `docs/40-monitoring-and-documentation/guides/slo-framework.md` | SLO-003 target 99.9% → 99.5%, updated SLI expression |
| `docs/40-monitoring-and-documentation/guides/slo-based-alerting.md` | Immich target and error budget updated |
| `docs/40-monitoring-and-documentation/guides/slo-calibration-process.md` | Immich target and rationale updated |
| `scripts/monthly-slo-report.sh` | Discord embed target 99.90% → 99.50% |

### Metrics State After Fixes

| Metric | Before | After |
|--------|--------|-------|
| `sli:immich:availability:ratio` | 96.8% | 98.87% |
| `sli:immich:uploads:success_ratio` | NaN | 1.0 |
| `slo:immich:availability:target` | 0.999 | 0.995 |
| `error_budget:immich:...:budget_consumed` | 3,197% | 226% |
| `error_budget:immich:...:budget_remaining` | -3,097% | -126% |

The error budget is still negative because the 16 historical 502 errors from the Feb 2 incident are still in the 30d window. As these roll out over the next ~3 weeks, availability will climb above 99.5% and the error budget will turn positive -- assuming no new incidents.

---

## Infrastructure Health Snapshot (2026-02-07)

| Container | Health | Memory | CPU | Static IPs |
|-----------|--------|--------|-----|------------|
| immich-server | Healthy | 277MB / 4G | 0.15% | 10.89.2.12, 10.89.5.5, 10.89.4.22 |
| immich-ml | Healthy | 19MB / 4G | 0.66% | 10.89.5.2 |
| postgresql-immich | Healthy | 32MB / 1G | 0.32% | 10.89.5.3 |
| redis-immich | Healthy | 13MB / 512M | 0.24% | 10.89.5.4 |

**Storage:** 136GB photo library, 786MB ML model cache
**Version:** v2.5.2 (pinned), v2.5.5 available
**Restarts since Feb 4:** 0
**Errors in past 7 days:** 0
**Traefik middleware chain:** crowdsec-bouncer → rate-limit-immich → compression → security-headers (circuit-breaker + retry removed after stress test, see 2026-02-08 journal)
**Traefik /etc/hosts:** immich-server → 10.89.2.12 (verified)

---

## Gotchas Reference (Quick Lookup for Future Sessions)

1. **WebSocket code=0 is success.** Traefik reports WS connections as `code="0"`. Always use `code=~"0|2..|3.."` in SLO rules. Affects Immich, Jellyfin, Home Assistant.

2. **NaN is not empty in PromQL.** `or vector(1)` does not catch NaN. Use `clamp_min(denominator, 0.001)` to prevent division by zero.

3. **SLO targets must match traffic volume.** At <200 req/day, use 99.5%. At >1,000 req/day, consider 99.9%. Each failure at 50 req/day consumes ~2% of a 99.9% error budget.

4. **Prometheus retains 15 days; SLOs use 30-day windows.** Incident data disappears from Prometheus before SLO recovery completes. Use Loki for historical investigation.

5. **Loki raw API returns byte arrays for journal logs.** Use `journalctl` or Grafana Explore, not direct Loki HTTP API, for readable Immich logs.

6. **Immich has no native Prometheus metrics endpoint** (as of v2.5.2). All monitoring relies on Traefik request metrics + Promtail log scraping. No `/metrics` endpoint available.

7. **immich-server is on 3 networks** (reverse_proxy, photos, monitoring). First network must be `reverse_proxy` for internet access (default route).

8. **Immich ML start period is 600s** (10 minutes). This is intentional -- the first boot downloads ML models. Do not reduce this or the healthcheck will fail during cold start.

9. **Thumbnail failure alert uses Promtail counter, not Prometheus scrape.** The pipeline is: systemd journal → Promtail regex → `promtail_custom_immich_thumbnail_failures_total` → Prometheus. If Promtail restarts, the counter resets (acceptable -- alert uses `increase()`, not absolute value).

10. **immich-server cannot use User=1000:1000.** Immich's folder integrity check fails with explicit UID mapping in quadlets. The container runs as its internal default user.

---

## Addendum: Hand-Off for Phases 2-6

This section is a briefing for the next Claude Code session to continue the Immich operational excellence work.

### Context

The user's goal is to make Immich the **primary photo management app across all devices** -- the single source of truth for photos and videos. This is not just a technical project; Immich will become a life companion for preserving memories. The reliability, trust, and confidence that come from thorough testing and monitoring are essential to this goal.

Phase 1 (server-side verification and monitoring fixes) is complete. The infrastructure is healthy, monitoring is now accurate, and the service guide is current. What remains is human-in-the-loop client testing across all devices, resilience validation, and the future 30GB photo library import.

### What Was Done (Phase 1)

- All 4 containers verified healthy with correct static IPs and network topology
- **WebSocket code=0 bug fixed** across all SLO rules (was counting WS as failures)
- **Upload SLO NaN fixed** (PromQL division-by-zero edge case)
- **Immich SLO target lowered** from 99.9% to 99.5% (realistic for ~50 req/day)
- Service guide completely rewritten with correct URL (photos.patriark.org), version, topology
- All SLO documentation updated to reflect new target
- Zero errors in past 7 days, zero restarts, all metrics producing valid data

### What Remains

**Phase 2: Client Device Testing** (user-driven, Claude assists with monitoring)

The user needs to test Immich across 4 devices:
- **Fedora HTPC** (browser): Primary workstation
- **iPad Pro** (Immich app): Tablet testing
- **iPhone** (Immich app): Primary mobile camera device -- most critical for auto-backup
- **Gaming PC** (browser): Secondary desktop

Test matrix per device:

| Test | Pass Criteria |
|------|---------------|
| Login at photos.patriark.org | Dashboard loads, library visible |
| Browse timeline | Thumbnails render, scroll smooth |
| ML search ("beach", faces) | Relevant results returned |
| Upload single photo | Appears in timeline, metadata correct |
| Upload 10+ batch | All appear, no errors in `podman logs immich-server` |
| Upload video | Plays back, thumbnail generated |
| HEIC from iPhone | Thumbnail generates correctly |
| Download photo | File integrity preserved (byte-identical) |
| Create album + share link | Accessible in incognito browser |
| Delete + restore from trash | Trash behavior correct |
| Favorite | Appears in favorites view |

Mobile-specific (iPhone + iPad Pro):
- Auto-backup setup and verification
- Background upload (lock screen, switch apps)
- WiFi-only toggle behavior
- Upload resume after airplane mode toggle
- Live Photo and Portrait mode uploads

**Phase 3: Cross-Device Sync**
- Upload on iPhone, verify visible on iPad/browser within 30 seconds
- Upload from 2 devices simultaneously
- Upload 10 face-containing photos, observe ML processing time and clustering

**Phase 4: Resilience Testing**
- `systemctl --user restart immich-server.service` -- verify no 502s, auto-reconnection
- Upload 50+ photos in burst -- monitor `podman stats immich-server` for memory
- Upload corrupt/truncated JPEG -- verify graceful error handling
- Airplane mode mid-upload on mobile -- verify resume

**Phase 5: SLO Validation**
- After 2-3 weeks, check that availability has climbed above 99.5% as 502s roll out
- Verify error budget is positive
- Run `~/containers/scripts/monthly-slo-report.sh` and verify correct Immich data in Discord embed
- Consider: if Immich becomes primary photo app with heavy daily use, traffic will increase substantially -- reassess SLO target at that point

**Phase 6: Documentation Finalization**
- Journal entry with test results from Phases 2-4
- Consider creating a runbook for Immich incident response (thumbnail failures, 502 patterns)
- Update CLAUDE.md if any new patterns emerge from testing

### Future: 30GB Photo Library Import

After Immich reaches operational excellence (all phases passed), there is a planned import of ~30GB of mixed media. The recommended approach (from the plan) is:

1. **Pre-sort on filesystem** using EXIF data + filename patterns + dimensions
   - Personal photos (camera captures) → upload to main library (appears in timeline)
   - Screenshots, downloads, receipts → mount as external library (searchable but not in timeline)
2. **Sorting heuristics:** EXIF camera model present = likely photo; iOS screenshot dimensions (1170x2532, 1284x2778) = screenshot; filename patterns like `IMG_` vs `Screenshot_`
3. **External library mount:** Add `Volume=...secondary:/mnt/media/secondary:ro,Z` to immich-server quadlet
4. **Configure in Immich Admin** > External Libraries
5. All media gets ML processing regardless of library

This import should be its own journal entry and done with monitoring active to validate Immich handles the load gracefully.

### Key Files for Next Session

| Purpose | Path |
|---------|------|
| Server quadlet | `quadlets/immich-server.container` |
| ML quadlet | `quadlets/immich-ml.container` |
| PostgreSQL quadlet | `quadlets/postgresql-immich.container` |
| Redis quadlet | `quadlets/redis-immich.container` |
| Traefik routing | `config/traefik/dynamic/routers.yml` (immich-secure section) |
| SLO recording rules | `config/prometheus/rules/slo-recording-rules.yml` |
| SLO burn rates | `config/prometheus/rules/slo-burn-rate-extended.yml` |
| Thumbnail alert | `config/prometheus/rules/log-based-alerts.yml` |
| Service guide | `docs/10-services/guides/immich.md` |
| SLO framework | `docs/40-monitoring-and-documentation/guides/slo-framework.md` |
| This journal | `docs/98-journals/2026-02-07-immich-operational-excellence-phase1.md` |

### Useful Commands for Testing

```bash
# Monitor during testing (run in separate terminals)
podman logs immich-server -f
podman stats immich-server immich-ml postgresql-immich redis-immich

# Quick health check
podman healthcheck run immich-server immich-ml postgresql-immich redis-immich

# Check SLO status
for m in sli:immich:availability:ratio sli:immich:uploads:success_ratio error_budget:immich:availability:budget_remaining; do
  val=$(podman exec prometheus wget -qO- "http://localhost:9090/api/v1/query?query=$m" 2>&1 | grep -oP '"([0-9.eNa+-]+)"' | tail -1 | tr -d '"')
  echo "$m = $val"
done

# Check for errors after testing
journalctl --user -u immich-server.service --since "1 hour ago" | grep -i "error\|fail"
```

### Note on Immich's Importance

The user has expressed that Immich becoming the primary photo management solution is a deeply personal goal. This is not about uptime percentages -- it is about trust. Every photo uploaded is a moment that matters. The testing phases ahead are about building the confidence that those moments are safe, accessible, and beautifully organized across every device the user touches. Treat this with the care it deserves.
