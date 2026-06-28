# HomeAssistantHigh4xxRate fired on a single client-closed connection — 499 was being counted as a 4xx error

**Date:** 2026-06-28
**Status:** Fixed — 499 excluded from all four `*High4xxRate` numerators; HA min-traffic guard `0.001 → 0.002`. promtool clean, Prometheus reloaded, live rule confirmed.
**Origin:** A Discord `HomeAssistantHigh4xxRate` warning ("4xx rate above 10% for 10 minutes") fired with no owner activity on HA. Investigation traced it to a benign client disconnect.

---

## What happened

The alert watches the Traefik `home-assistant@file` service for `>10%` 4xx over a 30m window, `for: 10m`. HA's Traefik traffic is ~37 req/day, so any 30m window holds only 1–2 requests.

At **14:38:59 CEST** the HA companion app did a routine token refresh — `POST /auth/token` from `192.168.1.1` (a phone on home wifi, hairpin-NAT'd through the UDM Pro) — and **closed the connection ~114ms in, before Traefik relayed the response**. Traefik logged it as **code 499** ("client closed request").

The alert numerator matched `code=~"4.."`, which **includes 499**. With only ~2 requests in the window and one being the 499, the ratio pegged at exactly **50%**, held there past the 10m `for:`, and fired.

## Why it's a false positive

499 is a **client-side disconnect** (backgrounded app, closed tab, network blip on a long-poll / token refresh) — it never indicates a server-side client error. The alert's own description lists 403/404/429 as the concern; 499 doesn't belong there. There was zero real fault:

- HA service `active`, healthcheck exit 0, no errors in container logs.
- Absolute counts over the alert window: `499=1`, connection-level `code-0=1`, **zero** real 403/404/429/500.

It self-resolved once the 499 aged out of the 30m window (~15:09 CEST).

## The fix

Two changes to `config/prometheus/alerts/slo-multiwindow-alerts.yml`, group `denylist_services_4xx_compensating`:

1. **Exclude 499 from all four numerators** (`code=~"4.."` → `code=~"4..", code!="499"`): Nextcloud, Home Assistant, Navidrome, Audiobookshelf. The 499 exclusion alone would have prevented this incident — the numerator drops to 0%.
2. **HA min-traffic guard `0.001 → 0.002` req/s** (~1.8 → ~3.6 req/30m): defense-in-depth so a lone event can't dominate a 1–2 request window. The prior 0.001 cleared on the single 499.

## Honest limits

Ratio alerting is inherently noisy at HA's volume. To *guarantee* a single stray 4xx (e.g. the HA iOS app's periodic `GET /api/ios/config` 404s) can't trip a 10% threshold, the window needs ≥10 requests — but HA averages <1 req/30m, so a guard that strict would effectively disable the alert. The 499 exclusion is the real fix; the guard bump is a modest hardening, not a full solution. An absolute-4xx-count gate would be the cleaner long-term design if these keep recurring.

## Follow-on hardening (same PR)

- **Added a min-traffic guard to Navidrome and Audiobookshelf** (`> 0.01` req/s ≈ 3 req/5m, matching Nextcloud). Both are idle most of the time with session bursts (Navidrome ~0 req/24h at measurement, Audiobookshelf ~278 req/24h, median 0, peak ~34 req/5m) — the same single-event-trip profile HA had, previously unguarded. The ratio is now only evaluated under real use.

## Side findings (not actioned)

- The repo's `data/traefik-logs/` is a stale orphan (0-byte `access.log`, rotated `.gz` frozen at 2026-01-16). Live logs are on the BTRFS pool (`/mnt/btrfs-pool/subvol7-containers/traefik-logs`, per `quadlets/traefik.container:29`). Harmless; a candidate for deletion.

**Diagnostic note:** Traefik access-log timestamps are **UTC**; the system runs `+0200`. The log's `12:38:59` is `14:38:59` local — reconcile timezones before concluding a log "stopped updating."
