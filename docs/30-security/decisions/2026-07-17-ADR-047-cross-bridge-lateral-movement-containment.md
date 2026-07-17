---
type: ADR
title: "ADR-047: Cross-Bridge Lateral Movement Containment via Declared Edge Allow-List"
description: "Sketch/Proposed. Closes the honestly-declared gap in ADR-045: members of the two non-internal bridges (reverse_proxy, restricted-egress) can currently reach any port on any member of either bridge, because both carry Options=isolate=false and netavark's FORWARD chain default-accepts. Internet-exposed services (Vaultwarden, qBittorrent, Immich, …) therefore have unrestricted lateral reach to auth, git, and monitoring backends. This ADR proposes replacing default-open cross-bridge reachability with an enumerated per-edge allow-list, ideally on the netavark 2.0 / Podman 6 strict-isolation default (Fedora Workstation 45). Deferred until ADR-046 removes the cross-bridge DNS dependency (prerequisite) and the netavark 2.0 lever lands."
sensitivity: public
created: 2026-07-17
updated: 2026-07-17
---

# ADR-047: Cross-Bridge Lateral Movement Containment via Declared Edge Allow-List

**Status:** Proposed (design sketch / spike) — deferred, timeline-gated. Not yet
scheduled for implementation. Depends on [ADR-046](2026-07-17-ADR-046-retire-etc-hosts-dns-override.md)
(prerequisite) and best executed on the netavark 2.0 / Podman 6 default flip.

**Date:** 2026-07-17

---

## Context

### The gap, stated plainly

[ADR-045](2026-07-17-ADR-045-restricted-egress-tier.md) restricts **outbound
internet** egress for a set of members and does it well (prototype-proven nft filter,
fail-open, drift-alerted). But its D-clarification explicitly declares
**cross-bridge lateral movement OUT OF SCOPE**, and D6 **pins `Options=isolate=false`**
on both `reverse_proxy` and `restricted-egress` to keep Prometheus's cross-bridge
scrapes and Traefik's cross-bridge dials working. The consequence, verified live on
2026-07-17:

> Any member of `reverse_proxy` **or** `restricted-egress` can open a connection to
> **any port on any member of either bridge.**

Concretely, `qbittorrent` — an internet-exposed torrent client on `reverse_proxy`
only — successfully reached `authelia:9091`, `forgejo:3000`, and `prometheus:9090`
across the bridge (all 200, pinned IPs, no DNS). The same is true for every other
`reverse_proxy` member, including the internet-facing crown jewels (Vaultwarden,
Immich, Nextcloud, Jellyfin, Home Assistant).

### Why this matters

The homelab's threat model treats network segmentation as a primary containment
layer (CLAUDE.md principle 5, zero-trust; ADR-016 6a, network membership = attack
surface). An internet-exposed service is the likeliest compromise entry point. Today,
a compromised `reverse_proxy` member can pivot directly to:

- `authelia:9091` — the SSO brain (session/credential surface),
- `forgejo:3000` — the git forge (source + the homelab ledger),
- `prometheus:9090` / exporters — monitoring plane,
- every other application backend on `reverse_proxy`.

This is strictly *lateral* (east-west) reach; it does **not** breach the
`Internal=true` networks — DBs and backends on `monitoring`, `nextcloud`,
`auth_services`, `photos`, etc. remain properly isolated (verified: `nextcloud` →
`prometheus`-on-`monitoring` = blocked). So the exposure is bounded to the two
non-internal bridges, but that boundary includes the auth and git planes, which is
too much.

### Why it is default-open today (the mechanism)

Inside the rootless netns, `table inet netavark`'s `FORWARD` chain contains
`ip saddr 10.89.2.0/24 accept` and `ip saddr 10.89.11.0/24 accept` — a blanket
accept per bridge subnet — and `NETAVARK-ISOLATION-3` only drops traffic *from
isolated networks*, which neither of these is (`isolate=false`). `isolate=false` is
required today because netavark's current isolation is all-or-nothing per network:
turning it on would sever the **legitimate** cross-bridge edges below along with the
illegitimate ones.

### The legitimate cross-bridge edges (must survive any tightening)

Enumerated from `config/prometheus/prometheus.yml` and
`config/traefik/dynamic/routers.yml` (to be re-enumerated exactly at implementation
time — this is the current set):

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| prometheus (restricted-egress/monitoring) | traefik 10.89.2.69 | 8080 | metrics scrape |
| prometheus | crowdsec 10.89.2.70 | 6060 | metrics scrape |
| prometheus | navidrome 10.89.2.75 | 4533 | metrics scrape |
| prometheus | home-assistant 10.89.2.76 | 8123 | probe/scrape |
| prometheus (blackbox) | nextcloud 10.89.2.82 | 80 | status.php probe |
| traefik (reverse_proxy) | authelia 10.89.11.78 | 9091 | forward-auth + route |
| traefik | audiobookshelf 10.89.11.74 | 80 | route |
| traefik | forgejo 10.89.11.89 | 3000 | route |

Everything else cross-bridge is *incidental* and should drop.

## Decision (proposed — to be ratified after the spike below)

Replace **default-open** cross-bridge reachability with a **declared, tested per-edge
allow-list**: every legitimate `(src-subnet/host, dst-ip, dport)` above is explicitly
permitted; all other cross-bridge forwarding drops. The reachability matrix becomes an
artifact under version control and a validation gate, not an emergent property of
`isolate=false`.

Three implementation avenues, to be chosen in the spike:

### Option A — netavark 2.0 strict isolation + explicit allow (preferred, timeline-gated)

netavark 2.0 (targeted Podman 6 / Fedora Workstation 45) is expected to make strict
per-network isolation a first-class, supported default. Adopt it, then re-open **only**
the enumerated edges via the supported allow mechanism. This is the "as good as it
gets" endpoint: enforcement is a maintained platform default, not a pinned-open
workaround, and ADR-045 D6's `isolate=false` pin is *removed* rather than perpetuated.
**Cost:** must land after F45 upgrade; requires re-solving Prometheus scrape and
Traefik dial as explicit edges (both already IP-pinned, so tractable).

### Option B — nft companion table now (bridge to A)

A sibling to ADR-045's `table inet egress_filter`: `table inet lateral_filter` in the
rootless netns, applied by the same argv-not-stdin discipline (L-093) and reapplied by
a 1-minute timer (enforcer + sensor + drift alert), that drops cross-bridge
`FORWARD` traffic except the enumerated tuples. Available **today**, no F45 dependency,
reuses proven ADR-045 machinery. **Cost:** hand-rolled rules racing netavark's own
FORWARD chain ordering (must be validated to sit at the right hook priority);
another moving part to reboot-test. Reasonable as an *interim* if the exposure is
judged unacceptable before F45.

### Option C — DMZ bridge co-location (topological)

Put Traefik and the three internet-routed restricted-egress backends
(authelia/audiobookshelf/forgejo) on one purpose-built bridge, redesign Prometheus's
scrape path (e.g. Prometheus single-homed on `monitoring` with exporters reachable
there), so no cross-bridge dial is needed and strict isolation can be blanket-on.
**Cost:** the largest topology change; re-opens the network-membership questions
ADR-018/045 carefully settled. Lower favourite unless A/B prove awkward.

**Leaning:** A as the destination, B only if we decide we cannot wait for F45.
Decide in the spike.

### Audit-mode staging (mandatory for whichever option is chosen)

A default-drop containment filter fails destructively when the enumerated allow-list
is incomplete — an edge you forgot silently breaks a service the moment enforcement
flips on. **Before any rule drops a packet on the live fabric, run it in observe-only
mode:** the same match rules with `log`/`counter` in place of `drop`, so every packet
that *would* be dropped is recorded but still forwarded. Watch the counters/log for a
representative window (a full scrape cycle, a login, a route exercise of each
internet-facing service, an ABS/forgejo on-demand action) and confirm the only
would-drop hits are the illegitimate edges from the baseline matrix — any legitimate
edge showing up is a gap in the enumeration to fix *before* enforcing. Only then swap
`log` → `drop`.

This is distinct from ADR-045's fail-open egress filter: that one is safe to enforce
immediately because a missed allow just leaks (defense-in-depth, no outage); a
*containment* filter's missed allow is an outage, so it earns the observe-first step.
For Option A the equivalent is netavark's isolation in a logging posture (or a
temporary `lateral_filter` audit table alongside) before the `isolate=false` pin is
removed; for Option B it is the `lateral_filter` table itself shipped `log`-first.
Fold the audit window into the spike gate below.

## Prerequisite

ADR-046 must land first: while Traefik resolves the three cross-bridge backends by
**name** via the mounted `/etc/hosts`, any isolation change risks silently breaking
resolution as well as reachability, entangling two failure modes. With ADR-046's
pinned-IP URLs, resolution is DNS-independent and isolation can be tightened against a
stable, enumerated IP edge set.

## Spike / validation gate (before Status → Accepted)

1. **Enumerate** the exact live cross-bridge edge set (re-derive the table above from
   current `prometheus.yml` + `routers.yml` + any blackbox/probe jobs) and freeze it
   as the allow-list source of truth.
2. **Baseline** the full cross-bridge reachability matrix (the 2026-07-17 capture is
   the starting point) so "unchanged legitimate / closed illegitimate" is provable.
3. **Prototype** the chosen option in a throwaway netns/prototype (ADR-045 set the
   precedent: prove nft-table survival across restart/reload/create, hook priority vs
   netavark's FORWARD, DNS path intact) **before** touching the live fabric.
4. **Audit-mode window on the live fabric:** deploy the rules `log`/`counter`-only
   (per "Audit-mode staging" above), exercise every internet-facing service + scrape
   cycle for a representative window, and confirm the only would-drop hits are the
   baseline's illegitimate edges before any rule is switched to `drop`.
5. **Prove containment:** post-enforcement, `qbittorrent → authelia:9091` (and the
   other illegitimate edges) **drop**; every enumerated legitimate edge still 200s; all
   Prometheus targets healthy; every `*.patriark.org` route serves.
6. **Reboot + failure semantics:** define fail-open vs fail-closed deliberately (a
   *containment* boundary may warrant fail-closed with alerting, unlike ADR-045's
   fail-open egress filter — decide explicitly), and prove reconvergence.

## Consequences (when implemented)

- Compromise of an internet-exposed member can no longer pivot to the auth, git, or
  monitoring planes; lateral reach collapses to its declared, minimal edge set.
- The reachability matrix becomes a reviewed, tested artifact — directly serving the
  "carefully tailored, rely-on-it-for-the-foreseeable-future" goal.
- Option A additionally **retires** ADR-045 D6's `isolate=false` pin, converting a
  workaround into a supported default.
- Cost: one more enforced boundary to test and reboot-verify (B), or an F45-gated
  migration (A). Either way, network changes are prototype-first, never hot-path.

## References

- Prerequisite: ADR-046 (retire /etc/hosts override — DNS-independent backend URLs).
- Gap source: ADR-045 (D-clarification declares lateral movement out of scope; D6
  pins `isolate=false`).
- Model: ADR-045's `egress_filter` machinery (in-netns nft table, argv-apply L-093,
  timer as enforcer+sensor) is the template for Option B.
- Principle: ADR-016 6a (network membership = attack surface); CLAUDE.md zero-trust.
- Upstream: netavark 2.0 strict-isolation default (Podman 6 / Fedora Workstation 45,
  pending); Podman #27099 (rootless pasta SNAT — why host-level enforcement is out).
- Investigation: 2026-07-17 localhost-leak session (where the cross-bridge reach was
  measured).
