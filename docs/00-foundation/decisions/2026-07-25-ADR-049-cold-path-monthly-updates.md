---
type: ADR
title: "ADR-049: Cold-Path Monthly Updates with Critical-Tier Live Verification"
description: "ADR amending ADR-036 to stop restarting the fleet twice: monthly batches pin and pre-pull only, the reboot performs the rollout, and live adopt-restart-verify is retained for ADR-035 boot tier A and for urgent single adoptions."
sensitivity: public
created: 2026-07-25
updated: 2026-07-25
---

# ADR-049: Cold-Path Monthly Updates with Critical-Tier Live Verification

**Date:** 2026-07-25
**Status:** Accepted (implementation pending — `adopt-baked.sh` and
`monthly-update.sh` not yet changed)
**Amends:** ADR-036 (Bake Policy and Exception Lane) — changes *when* adoption is
applied and verified, not *what* is adopted. The P3 bake thresholds, the discovery
verdicts, the JSON contract, and the CVE exception lane are unchanged.
**Relates to:** ADR-030 P1 (deliberate adoption), ADR-035 (boot-time I/O tiering),
L-049 (smoke-test the real workload)

---

## Context

ADR-036 automated an adopt loop that had cost "~45 supervised minutes" of manual
pin → daemon-reload → restart → wait → verify. It removed the manual toil, but it
preserved the *shape* of the ritual: adopt, restart, health-wait, HTTP-verify — one
service at a time, on a live system, halting on the first failure.

That shape is now the dominant cost. The 2026-07-25 monthly run adopted 17 updates
and spent roughly 30 minutes inside the serial adoption loop, against a prior-era
ritual (stop services → update → dnf → reboot) that took about ten minutes end to
end. The run also revealed that the expenditure buys much less than it appears to.

### The harness produced only false positives

Two services halted the batch. Neither was a defective image:

- **navidrome** was recorded as a 502 failure. `HEALTH_TIMEOUT=120` expired while the
  new version ran two schema migrations and rebuilt its artist search index
  (`startupTime=4m38s`). The service was healthy minutes later with no intervention.
- **loki** failed to start twice under the I/O contention of the concurrent batch:
  the container reached `Created`, emitted no application output, and exceeded
  `TimeoutStartSec=120`. The same image starts in 551 ms on an idle system. Root
  cause was never proven.

**Real image defects caught: zero.** Both halts were artifacts of fixed timeouts
meeting a machine the batch itself had loaded.

### The harness cannot see the defect class that actually bites

The month's one genuine breakage was vaultwarden 1.36.0 against Bitwarden clients
2026.6.1 and 2026.7.0: login succeeded, the vault rendered empty, because the client
SDK rejected the server's cipher response shape. Throughout, the harness's own check
— `curl https://vault.patriark.org/` → 200 — was true. The server was healthy; the
clients could not decode it. The breakage was found by a human opening the app.

Route-level verification asserts *"Traefik received a response,"* not *"the workload
works."* It is structurally blind to API-compatibility, decode, and
authentication-flow regressions — which is where container updates actually break.

### When a reboot follows, every service is restarted twice

The pre-reboot pass is the hostile one:

| | Live adopt pass | Reboot |
|---|---|---|
| Ordering | wave heuristic | ADR-035 boot tiers |
| Concurrent load | serving real traffic | none |
| Image pulls | inline, serialized with restarts | already present |
| Slow start | **hard fail at 120 s, batch halts** | systemd retries, tiers stagger |

Slowness that is *benign at boot* is a *hard failure during adoption*. The
post-reboot I/O storm is already documented as expected and self-resolving; ADR-035
exists precisely to stagger it. The adopt path takes the same storm and converts it
into halt-on-failure. It is not a better test environment than the reboot — it is a
worse one, and it costs half an hour.

## Decision

Adoption splits into two paths, selected by whether a reboot follows.

### 1. Cold path — the default for the monthly ritual

No service restarts before the reboot. The reboot *is* the rollout.

1. **Discover** — `check-image-updates.sh`, unchanged (verdicts + JSON).
2. **Pin** — write every adopted digest. The ADR-030 P6 signature gate runs here; it
   is a registry operation and costs nothing.
3. **Pre-pull** — fetch every pinned digest, parallel and unattended. A reboot onto
   unpulled digests is slow at best and fails at worst.
4. **Commit + PR** — the PR review remains the ADR-030 P1 deliberate-trust moment.
5. **`prepare-for-reboot.sh` → dnf → reboot.**
6. **Verify once, after the reboot** — `post-reboot-verify.sh` across the whole
   fleet, plus the human smoke list below.

The halt gate moves earlier and gets cheaper: **a signature failure or a pull
failure means do not reboot.** Both are fast, deterministic, and cannot be
manufactured by system load.

### 2. Live path — ADR-035 boot tier A, and urgent single adoptions

Boot tier A keeps the current adopt → restart → health-verify behaviour, run
*before* the reboot:

> alertmanager, authelia, forgejo-db, gathio-db, nextcloud-db, nextcloud-redis,
> postgresql-immich, redis-authelia, redis-immich, traefik

The criterion is **"can this service's failure obstruct diagnosis or recovery of the
others?"** — strictly that is traefik and the auth pair, since a broken front door
removes the means of investigating everything else. Boot tier A is a slight
over-approximation (it also sweeps in databases, which fail loudly and locally), and
the over-approximation is accepted: it reuses metadata that already exists in every
quadlet rather than introducing a bespoke list that will drift, and it errs in the
conservative direction. Tier A is also cheap to verify — mostly healthchecks with no
HTTP route and no migration-heavy startup.

`--live` additionally selects this behaviour for any service when no reboot is
planned. This is the path the 2026-07-25 vaultwarden fix required and should
continue to use: an urgent adoption with no reboot behind it must be proven working
immediately.

### 3. Fixed timeouts are not load-bearing in the cold path

`HEALTH_TIMEOUT` and `TimeoutStartSec` gate nothing on the cold path, because
nothing is restarted. On the live path they must accommodate migration-heavy
startups — today's 120 s default is demonstrably too tight (navidrome: 4m38s) and
should be raised or made per-service.

### 4. Verification ends with a human smoke list

Per L-049, `post-reboot-verify.sh` output is not sufficient. The ritual ends with a
short manual exercise of real workloads — one vault unlock, one login, one upload,
one playback. Four manual checks would have caught the vaultwarden breakage; the
seventeen automated HTTP 200s did not.

## Consequences

**Positive**

- The monthly ritual returns to roughly 15 minutes, most of it unattended pulling.
- Services restart once instead of twice.
- Failures caused by batch-induced contention disappear, because there is no batch
  of concurrent restarts on a live system.
- The gates that remain (signature, pull) are deterministic and load-independent.
- Verification happens where it is meaningful — after the reboot, on the
  configuration that will actually run — instead of on a transient intermediate state
  that is discarded minutes later.

**Negative / accepted risks**

- **Attribution weakens.** Roughly 27 non-tier-A digests apply at once. If something
  is broken after the reboot, the bisect surface is wider than a halted serial batch.
  Accepted: per-service rollback is a one-line `git revert` of the pin plus a
  restart, failures are rare, and the serial harness's actual hit rate on real
  defects this month was zero.
- **Non-critical breakage is discovered on a rebooted system.** Accepted, because
  tier A — the services whose failure would obstruct diagnosis — is still verified
  live beforehand.
- **The "catch it in the act" property is lost for tier B/C.** Accepted for the same
  empirical reason.

**Rollback**

Unchanged and unaffected: `git revert` the pin commit (or the single quadlet line)
and restart, with BTRFS snapshots as the second path.

## Implementation notes

Not yet built. The work is:

- `adopt-baked.sh`: add `--cold` (pin + pull, no restart) and `--live`; make boot
  tier A automatically live within a cold run; raise or per-service the health
  timeout on the live path.
- `monthly-update.sh`: default to cold; keep `--live` for the no-reboot case; move
  the verification step after the reboot instruction rather than before it.
- `post-reboot-verify.sh`: confirm it covers the full fleet, and have it print the
  human smoke list as its closing output.
