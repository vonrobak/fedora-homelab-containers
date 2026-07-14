---
type: ADR
title: "ADR-036: Bake Policy Codification and Security-Release Exception Lane"
description: "ADR amending ADR-030 to codify the image bake policy (egress 7d / internal 3d) with tooling verdicts and a security-release CVE exception lane."
sensitivity: public
created: 2026-06-11
updated: 2026-06-11
---

# ADR-036: Bake Policy Codification and Security-Release Exception Lane

**Date:** 2026-06-10
**Status:** Accepted (implemented: bake-policy.yml, check-image-updates.sh verdicts,
adopt-baked.sh, service-url.sh)
**Amends:** ADR-030 (Container Supply-Chain Trust Model) — concretizes P3, adds the
exception lane. ADR-030's principles are unchanged.

---

## Context

ADR-030 P3 established the cooling-off interval as a *principle*: "a new digest is
adopted only after a bake interval," with the egress tier getting "the longest bake."
No number was ever written down, and no tooling enforced or even surfaced the
interval.

The first batch adoption under the executed Tier 1 migration (2026-06-10, PR #270)
exposed what that costs in practice:

- **The bake gate was manual.** `check-image-updates.sh` reported *availability* but
  not *age* — applying P3 meant 19 hand-run `skopeo inspect` calls to fetch creation
  dates and an ad-hoc threshold decision (≥7d egress / ≥3d internal) made on the
  spot rather than by policy.
- **The adopt loop was manual.** Nine adoptions took ~45 supervised minutes of
  pin → daemon-reload → restart → wait → verify, with verification hostnames
  guessed (twice wrongly) despite the truth sitting in `routers.yml` (ADR-016).
- **The bake principle was validated twice in one session.** `traefik:latest` moved
  *between the discovery sweep and the age check* (~30 min apart), and `mongo:7`
  moved again within the hour after adoption. Same-day digests are demonstrably
  churny; the interval is doing real work.
- **The doctrine tension was unresolved.** The bake interval deliberately trades
  CVE-patch latency for the ecosystem's poisoned-release detection latency. That
  trade is correct as a *default* here (defense-in-depth absorbs patch latency; a
  poisoned image starts inside the trust boundary), but ADR-030 provided no
  legitimate fast path for the case where the calculus inverts: a release fixing an
  actively-exploited CVE in an internet-facing service. A policy with no exception
  lane gets bypassed ad hoc — or worse, obeyed when it shouldn't be.

## Decision

### 1. Bake thresholds are policy, not prose

`config/supply-chain/bake-policy.yml` defines the P3 intervals:

| Tier | Definition | Bake |
|------|-----------|------|
| egress | quadlet on `reverse_proxy` network (`Network=systemd-reverse_proxy…`) | **7 days** |
| internal | everything else | **3 days** |

Age is measured from the image's `Created` timestamp (via skopeo) to now. A
rebuilt-but-unchanged upstream image resets the clock — accepted, because the error
is in the conservative direction.

### 2. Discovery annotates the gate

`check-image-updates.sh` resolves each available digest's age and emits a
`BAKED` / `TOO-YOUNG (wait Nd)` / `AGE-UNKNOWN` verdict per candidate, plus a
machine-readable JSON companion (`docs/99-reports/image-updates-YYYYMMDD.json`)
with full digests, ages, tiers, verdicts, and signature states. The JSON is the
input contract for batch adoption — no more hand-run skopeo sweeps or truncated
digests copied from text reports.

### 3. Batch adoption is wave-ordered and halt-on-failure

`scripts/adopt-baked.sh` adopts every `BAKED` candidate in dependency-ordered
waves — plumbing (exporters/syslog) → apps → core (gateway/auth/monitoring, one at
a time) → data (databases/caches, each followed by restarts of its dependent apps,
derived from quadlet `After=`/`Requires=` lines). Each service is verified
(systemd active + container healthcheck + HTTP through its Traefik route) before
the next is touched; the first failure halts the batch with rollback instructions.
Each adoption still flows through `pin-container-image.sh`, so the ADR-030 P6
signature gate applies unchanged. `--dry-run` prints the plan.

### 4. Exception lane: security releases may skip the bake

A release that fixes a **known-exploited or critical CVE in an egress-tier
service** MAY be adopted before its bake interval elapses:

```
scripts/adopt-baked.sh --allow-young <svc>     # or pin-container-image.sh directly
```

Conditions: the override is per-service and per-invocation (never standing), and
the commit message MUST name the CVE or security advisory that justified the skip.
This makes the fast path legitimate, auditable, and rare — the policy bends where
the threat model says it should, instead of being silently bypassed.

Trigger source: release-feed watching for the egress-tier crown jewels (Traefik,
Authelia, Nextcloud, Vaultwarden, Immich, Forgejo) is the owner's responsibility;
automation for this is future work, not a blocker.

### 5. Verification hostnames come from routing truth

`scripts/service-url.sh` derives a container's external URL from
`config/traefik/dynamic/routers.yml` (backend URL → service → plain `Host()`
rule). Corollary of ADR-016: routing config is the single source of truth, so
verification must read it, not guess.

## Consequences

**Positive**
- The monthly update ritual collapses to: `check-image-updates.sh` → review →
  `adopt-baked.sh` → commit. The bake gate is computed, not hand-applied.
- The P3 interval is now enforceable, tunable in one file, and visible in every
  report — including *when* each deferred candidate becomes adoptable.
- The exception lane resolves the "pin everything" vs "patch fast" doctrine
  tension explicitly: bake by default, skip deliberately with a named CVE.
- Halt-on-failure batches mean a bad image stops the train instead of riding it.

**Negative / accepted**
- Maximum patch latency for routine updates equals the bake interval. Accepted:
  single user, layered auth in front of everything, instant BTRFS + git rollback.
- Image `Created` date is an approximation of release age; registry rebuilds
  shorten apparent age never lengthen it — errors defer, never rush.
- Two more scripts to maintain; both are thin orchestration over existing
  primitives (`pin-container-image.sh`, `skopeo`, `systemctl`).

**Neutral**
- Thresholds (7d/3d) are first guesses; tune in `bake-policy.yml` as experience
  accumulates. Raising the egress bake raises supply-chain safety and patch
  latency together — the file is the dial.

## References

- ADR-030 — Container Supply-Chain Trust Model (P1 deliberate adoption, P3 bake
  principle, P4 blast-radius tiers, P6 signature gate)
- ADR-016 — Configuration Design Principles (routing truth in dynamic config)
- PR #270 — first batch adoption; the session that motivated this ADR
- `scripts/check-image-updates.sh`, `scripts/adopt-baked.sh`,
  `scripts/service-url.sh`, `config/supply-chain/bake-policy.yml`
