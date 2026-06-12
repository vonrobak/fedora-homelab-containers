# Rate-limit soak closure — T2.2 thread ratified and finished

**Date:** 2026-06-12
**Status:** Closes the last open thread of T2.2 (rate-limit burst downsize) from
[2026-04-23-security-posture-punchlist-private.md](2026-04-23-security-posture-punchlist-private.md),
left "awaiting the 7-day soak" by
[2026-04-28-tier2-perip-verification-and-nextcloud-burst-downsize-private.md](2026-04-28-tier2-perip-verification-and-nextcloud-burst-downsize-private.md).
Origin: WP3 item 6 of the 2026-06-12 lessons.md loose-threads handoff.

## What the soak showed

The Nextcloud downsize (burst 1500→800, applied 2026-04-28) was watched for 7
days with a zero-429 pass criterion. No journal ever recorded the verdict. As
of today, **six weeks** past the change:

- `traefik_service_requests_total{code="429"}` has **zero series** — not zero
  rate, zero *series*: no request has ever been rate-limited within the
  Prometheus retention window. (Retention is 15d, so this directly proves the
  recent window; no 429 alert or Discord trace exists for the April–May gap
  either.)
- Measured 15d peak request rates (max 1-minute window, `max_over_time` over
  `rate()[1m]` subquery, by `exported_service`):

  | service | peak req/min | configured burst | headroom |
  |---|---|---|---|
  | nextcloud | 93 | 800 | 8.6x |
  | immich | 33 | 1500 → **800** | 24x (after downsize) |
  | qbittorrent | *(no traffic at all)* | 600 (kept) | n/a |

## Decisions

1. **Nextcloud burst=800 RATIFIED.** Clean soak, 8.6x headroom over the
   observed worst minute.
2. **Immich burst 1500→800 applied** — the batched follow-up the 2026-04-28
   plan staged behind Nextcloud's clean soak. Even 800 is 24x the observed
   peak; kept deliberately fat because the worst case (mobile-app first-sync /
   bulk upload) did not occur in the measurement window. A further drop needs
   a measurement taken *during* an actual sync, per the T2.2 decision tree.
3. **qBittorrent burst=600 KEPT** (decided, not deferred). Zero WebUI traffic
   in 15d makes the 3×-p99 rule meaningless; the structural floor is the
   ~500-resource initial WebUI page load, and 600 is already the tightest
   value that doesn't break it. Average 100/min is unchanged. It remains
   behind Authelia, so the rate limit is layer 2, not the gate.

## Verification

- `middleware.yml` is Traefik dynamic config — auto-reloaded, no restart.
  The Traefik API is not exposed on :8080 (metrics only), so verification was:
  (1) provider re-read logged at edit time with zero errors, and (2)
  `https://photos.patriark.org/` returns 200 through the full middleware
  chain including `rate-limit-immich@file` — an unparseable middleware would
  have dropped the router (404). Note for future sessions: Immich's host is
  `photos.patriark.org`, Navidrome's is `musikk.patriark.org` — probing
  `immich./navidrome.patriark.org` 404s by design, not by breakage.
- Watch item (passive): any `ImmichHigh4xxRate`-class signal or first 429
  series appearing on `immich@file` during the next mobile-app bulk upload.

## Lessons

Nothing new for lessons.md — the only near-lesson ("soaks need a written
verdict or they dangle forever") is already covered by the handoff/status.md
process this entry executes.
