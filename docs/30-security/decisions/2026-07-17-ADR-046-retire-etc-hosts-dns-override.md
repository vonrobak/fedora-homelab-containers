---
type: ADR
title: "ADR-046: Retire the Traefik /etc/hosts DNS Override — Backend Resolution via Pinned URLs"
description: "Successor to ADR-018's DNS-override half. The aardvark multi-network ordering bug that justified mounting a full /etc/hosts into Traefik is no longer reproducible on Podman 5.7.1 with a single-homed Traefik; the file now serves only cross-bridge name resolution for three restricted-egress members and is a standing footgun (it silently dropped loopback, leaking ~16k localhost DNS queries/day). This ADR moves backend resolution into routers.yml as pinned IPs and removes the mount. Explicitly security-neutral: it changes name resolution only, not L3 reachability. The separate lateral-movement question (isolate=false between non-internal bridges) is scoped OUT to a dedicated ADR."
sensitivity: public
created: 2026-07-17
updated: 2026-07-17
---

# ADR-046: Retire the Traefik /etc/hosts DNS Override — Backend Resolution via Pinned URLs

**Status:** Proposed — requires the migration + validation gate below before adoption.
Supersedes the **DNS-override half** of [ADR-018](../../00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md).
The **static-IP + IPRange convention** of ADR-018 is retained unchanged (independently
justified by the 2026-03-01 IPAM-collision outage) — only the `/etc/hosts` mount is retired.

**Date:** 2026-07-17

---

## Context

### What ADR-018 mounted, and why

In February 2026, `aardvark-dns` returned a multi-homed backend's addresses in
undefined order. Traefik, then attached to three networks, would intermittently
resolve a backend to its `monitoring` IP and dial it over the wrong network,
producing a storm of "untrusted proxy" 400s. Podman closed the ordering behaviour
WONT_FIX (issue #14262). ADR-018's mitigation was a static host-mapping file
(`config/traefik/hosts`) bind-mounted as Traefik's entire `/etc/hosts`, forcing every
backend name to its `reverse_proxy` IP regardless of DNS.

### Two things changed since

1. **The original bug is no longer reproducible.** Traefik has been single-homed on
   `reverse_proxy` since the 2026-03-18 network-minimalism amendment (ADR-018's own
   tail). On Podman 5.7.1 / current aardvark, querying aardvark directly from inside
   Traefik returns exactly one A record per same-bridge backend, stable across
   repeats (`nslookup jellyfin 10.89.2.1` → `10.89.2.81`, every time). The multi-IP
   ordering hazard requires a multi-homed *client*; Traefik is not one anymore.

2. **The file was quietly repurposed by ADR-045.** Three restricted-egress members —
   `authelia` (10.89.11.78), `audiobookshelf` (10.89.11.74), `forgejo` (10.89.11.89)
   — live on a bridge Traefik does not share, so aardvark answers `NXDOMAIN` for them
   from `reverse_proxy`. The routers in `routers.yml` dial them by name
   (`http://authelia:9091`), so today **only the `/etc/hosts` file makes those three
   names resolve.** The other ten entries (all 10.89.2.x, same bridge as Traefik) are
   redundant belt-and-suspenders — aardvark resolves them correctly.

### The footgun that triggered this ADR

Because the mount *replaces* podman's generated `/etc/hosts` wholesale, it also
dropped the loopback entries podman normally injects. Traefik's quadlet healthcheck
(`wget http://localhost:8080/ping`, every 10s) therefore fell through to DNS —
musl → aardvark → pasta → Pi-hole — leaking an A+AAAA `localhost` pair every ~11s,
~16k queries/day, enough to make `localhost` Pi-hole's #1 permitted domain
(2026-07-17 investigation; hotfixed in PR #341 by re-adding loopback lines). The
class of bug is the real lesson: **a hand-maintained full `/etc/hosts` replacement is
a standing trap** — every implicit entry podman would have provided must be
remembered by hand, and the failure is silent (resolution still "works", just via the
wrong path).

### Separating the two axes (this matters for the security framing)

The owner's concern is that this cross-bridge arrangement lets services traverse
horizontally, weakening network segmentation. That concern is **valid but orthogonal
to this file**:

- **Name resolution** (what `/etc/hosts` does) — maps a name to an IP. Removing or
  changing it cannot grant or deny any connection; a caller with the literal IP is
  entirely unaffected.
- **L3 reachability** (what actually permits traversal) — `authelia:9091` is
  dialable from `reverse_proxy` because **both bridges carry `Options=isolate=false`
  and netavark's `FORWARD` chain accepts `ip saddr <either-subnet>`**. Verified
  2026-07-17: `qbittorrent` (on `reverse_proxy` only, internet-exposed) reaches
  `authelia:9091`, `forgejo:3000`, and `prometheus:9090` cross-bridge, all 200 —
  **using pinned IPs, no DNS involved.** ADR-045 D6 pins `isolate=false`
  deliberately, to keep Prometheus's cross-bridge scrape and Traefik's cross-bridge
  dial working, explicitly freezing this against netavark 2.0's planned
  strict-isolation default.

This ADR therefore makes **no security claim**. It removes a footgun and aligns
resolution with ADR-016 (routing lives in `routers.yml`). The lateral-movement
posture is unchanged by design and is addressed separately (see "Out of scope").

## Decision

### D1 — Backend URLs in `routers.yml` carry pinned IPs, not names

Replace name-based service URLs with the pinned static IP plus a name comment, e.g.:

```yaml
services:
  authelia:
    loadBalancer:
      servers:
        - url: "http://10.89.11.78:9091"   # authelia (restricted-egress, cross-bridge)
```

This is exactly the pattern `prometheus.yml` already uses for its cross-bridge
scrapes (`10.89.2.69:8080` # traefik, etc.) — pinned IP + comment, kernel routing, no
DNS in the path. The IPs are already statically assigned and frozen by ADR-018's
retained convention, so this introduces no new coupling: it moves an
already-existing IP dependency from a side-car `/etc/hosts` file into the single file
that owns routing. Only the three cross-bridge members strictly require it; for
uniformity and to kill the ambiguity permanently, **all** backend URLs are pinned.

### D2 — Remove the `/etc/hosts` mount from the Traefik quadlet

Delete `Volume=%h/containers/config/traefik/hosts:/etc/hosts:ro,Z`. Traefik regains
podman's generated `/etc/hosts` (correct loopback, no maintenance surface). The
`config/traefik/hosts` file is deleted. The loopback hotfix from PR #341 becomes moot
and is removed with the file.

### D3 — Retain ADR-018's static-IP + IPRange convention verbatim

`.69+` static assignments, `.2–.68` IPAM lease range, consistent last octet per
service — all unchanged. This convention earned its keep independently in the
2026-03-01 collision (a dynamic IP landing on a static one caused a 7h outage) and is
what makes D1's pinned URLs stable. **This ADR does not touch it.**

### D4 — Security-neutrality is an explicit invariant, not a side effect

The migration must be verified to change **zero** reachability: the same cross-bridge
pairs reachable before are reachable after, and no new pair opens. This is a
name-resolution refactor. Any observed change in the L3 reachability matrix is a bug
in the migration, not an intended effect.

## Out of scope — the lateral-movement question (future ADR)

The owner's deeper worry — that a compromised internet-exposed service (Vaultwarden,
qBittorrent, Immich, …) on `reverse_proxy` can currently open connections to any
service on `reverse_proxy` **or** `restricted-egress` — is real, is **not** addressed
here, and deserves its own carefully-tested ADR. Captured facts for that work:

- **Mechanism:** `Options=isolate=false` on both bridges + netavark's default-accept
  `FORWARD` chain. ADR-045 D6 pins this open on purpose (cross-bridge scrape/dial).
- **Current blast radius:** any `reverse_proxy` or `restricted-egress` member can
  reach any port on any member of *either* bridge. Internal networks (`Internal=true`
  DBs/backends) are **not** reachable this way — those remain properly isolated
  (verified: `nextcloud` → `prometheus` on `monitoring` = blocked/000).
- **The netavark 2.0 / Podman 6 lever (owner's hypothesis, confirmed plausible):**
  netavark 2.0 (targeted for Podman 6 / Fedora Workstation 45, a few months out)
  flips the default toward strict per-network isolation. That is the natural
  enforcement point — but adopting it means **re-solving** the two things
  `isolate=false` currently buys us:
    1. Prometheus's cross-bridge scrapes (→ move Prometheus onto `monitoring`-only
       with exporters reachable, or an explicit scrape-path allowance).
    2. Traefik's cross-bridge dial to the three restricted-egress backends (→ an
       explicit, minimal cross-bridge allow, or co-locating Traefik + those backends
       on a purpose-built DMZ bridge).
  Doing D1/D2 *now* (pinned IPs, no name dependency) is a clean prerequisite: once
  routing no longer depends on cross-bridge DNS, the isolation ADR can tighten
  reachability without simultaneously untangling a name-resolution web.
- **Recommended framing for that ADR:** an explicit per-edge cross-bridge allow-list
  (netavark `NETAVARK-ISOLATION` custom rules or an `egress_filter`-style companion
  table keyed on the exact `(src-subnet, dst-ip, dport)` tuples that Prometheus and
  Traefik actually need), so the reachability matrix becomes *declared and tested*
  rather than *default-open*. This directly answers the "as good as it gets" goal:
  every permitted cross-bridge edge is enumerated, everything else drops.

Whether ADR-045 is itself "slightly hacky" folds into that ADR: its **egress**
filter (outbound to internet) is sound and prototype-proven; its acceptance of
**default-open cross-bridge lateral movement** (D-clarification, "OUT OF SCOPE") is
the honestly-declared gap the next ADR should close, ideally on the netavark 2.0
timeline so enforcement is a supported default rather than a pinned-open workaround.

## Validation gate (must pass before Status → Accepted)

1. **Reachability matrix unchanged.** Capture the cross-bridge `(caller → target:port
   → code)` matrix for a representative set (traefik→each backend; qbittorrent→authelia/
   forgejo/prometheus; nextcloud→prometheus[blocked]) before and after. Must be
   identical. (Baseline captured 2026-07-17 during this investigation.)
2. **Every Traefik route still serves.** `curl -I` every `*.patriark.org` route →
   expected 200/302 (SSO redirect), including the three cross-bridge backends
   (sso/auth, audiobookshelf, git).
3. **Loopback correct without the mount.** `podman exec traefik getent hosts
   localhost` → `127.0.0.1`; healthcheck healthy; **zero** `localhost` queries in a
   ≥60s `podman unshare --rootless-netns tcpdump` spanning ≥5 healthcheck cycles.
4. **Survives restart + reboot.** Routing intact after `systemctl --user restart
   traefik` and after a full reboot (no `/etc/hosts` file to go stale).
5. **Original bug stays dead.** Confirm Traefik still resolves each same-bridge
   backend to a single correct IP via aardvark (spot-check post-migration), so
   removing the override did not resurrect a routing hazard.

## Migration plan

1. Rewrite `config/traefik/dynamic/routers.yml` service URLs to pinned IPs + name
   comments (D1). Traefik file-provider auto-reloads.
2. Capture the post-change reachability matrix and route sweep (gate 1–2).
3. Remove the `Volume=…/hosts:/etc/hosts` line from `traefik.container`; delete
   `config/traefik/hosts`; `daemon-reload` + restart Traefik (D2).
4. Run gate 3–5.
5. On green: this ADR → Accepted; ADR-018 annotated as superseded-in-part. Open the
   follow-up isolation ADR referenced in "Out of scope".

Rollback: `git revert` the branch and restart Traefik — the `/etc/hosts` mount and
file return atomically. Low-risk: routing config is file-provider, reload is seconds,
and the running services read this worktree so a revert is immediately live.

## Consequences

- **Positive:** removes a silent footgun (full `/etc/hosts` replacement); routing
  resolution lives in one file (ADR-016); loopback can never regress again; no
  cross-bridge DNS dependency, which unblocks a future strict-isolation ADR.
- **Positive:** IP dependency becomes explicit and co-located with the route it
  serves, instead of implicit in a separate mounted file.
- **Neutral / cost:** `routers.yml` service URLs now carry IPs — but they already
  depend on those IPs transitively, and the static-IP convention (retained) keeps
  them stable; the name comment preserves readability.
- **Neutral:** security posture (lateral reachability) is deliberately unchanged;
  the real hardening is the separate isolation ADR.
- **Explicitly not solved here:** cross-bridge lateral movement between non-internal
  bridges. Tracked for a dedicated, netavark-2.0-aligned ADR.

## References

- Supersedes (in part): ADR-018 (static IP + `/etc/hosts` override) — DNS-override half.
- Related: ADR-045 (restricted-egress tier; D6 pins `isolate=false`), ADR-016
  (routing in dynamic config), ADR-030 T4 (egress observatory).
- Trigger investigation: 2026-07-17 localhost-DNS-leak root cause; hotfix PR #341.
- Upstream: Podman #14262 (DNS order WONT_FIX); netavark 2.0 strict-isolation
  (Podman 6 / Fedora Workstation 45, pending).
