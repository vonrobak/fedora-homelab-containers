# HA Rate-Limit Rollback — Closing Out ADR-022

**Date:** 2026-04-21
**Status:** Live config re-aligned with `main` HEAD; follow-up rate-limit work identified
**Related:** ADR-022 (socket activation, merged PR #135)

## Context

ADR-022 restored real client source IPs at Traefik on 2026-04-16 by moving to
systemd socket activation, bypassing the `rootlessport` SNAT. The ADR explicitly
flagged rate-limit retuning as follow-up work — values like
`rate-limit-home-assistant: burst=600` were sized for "all external users share
one bucket" and stopped making sense once per-IP buckets became real again.

## What actually happened

The `rate-limit-home-assistant` middleware was introduced on 2026-04-12 as a
hot-fix for the iOS HA cold-start bursting through the standard 100/50 bucket
(launchpad — `docs/99-reports/2026-04-12-nat-security-model-violation.md`). Its
own comment cited the shared NAT IP as the sizing rationale.

**Drift surfaced during the rollback:** the 2026-04-12 hot-fix was deployed live
(Traefik autoloaded it via bind-mounted `config/`) but **never committed to git**.
`main` HEAD never carried `rate-limit-home-assistant` — only the working tree
did. Editing `middleware.yml` to remove it and `routers.yml` to route HA back to
`rate-limit@file` produced zero net diff against HEAD, because HEAD already
reflected the intended post-ADR-022 state. The rollback was de-facto a
drift correction, not a schema change.

Transient `ERR error="middleware rate-limit-home-assistant@file does not exist"`
appeared once at the file-reload boundary (middleware.yml reloaded before
routers.yml in that cycle), resolved on the next poll. HA confirmed live at
HTTP 200.

## What's now live

- HA router middleware chain: `crowdsec-bouncer@file → rate-limit@file → security-headers-ha@file`
- Rate limit per client: 100 avg / 50 burst / 1 min — generous headroom for the
  ~80 parallel JS chunks on a cold iOS app launch, per real client.
- `rate-limit-home-assistant` middleware: gone from both git and disk.

## Follow-up (out of scope for this session)

- **Still oversized, still NAT-era:** `rate-limit-qbittorrent` (300/600),
  `rate-limit-immich` (500/2000), `rate-limit-nextcloud` (600/3000). Each was
  sized for legitimate bulk ops (thumbnail grids, PROPFIND tree walks) so the
  retune needs per-service reasoning rather than a blanket cut.
- **ADR-022 environmental verifications** — confirm organic CrowdSec drops on
  real external IPs and independent per-IP rate-limit buckets under load.
  Passive observation, needs a sampling window.
- **Vaultwarden event log** — `EVENTS_DAYS_RETAIN` still unset; forensic gap.
- **authelia-portal middleware stripped** — working tree has `rate-limit@file`,
  `circuit-breaker@file`, `retry@file` removed from `sso.patriark.org`,
  uncommitted. Not touched this session — separate decision.

## Lesson

Traefik autoreload from a bind-mounted config directory means **live config can
silently drift from git**. Hot-fixes under pressure need a "did you commit this?"
step or the drift is invisible until something else pulls the files.
