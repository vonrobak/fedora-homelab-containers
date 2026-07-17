---
type: ADR
title: "ADR-045: Restricted-Egress Tier — LAN-Only Network with In-Netns nft Filter"
description: "ADR adding the missing middle tier of a three-tier egress model: a restricted-egress network whose members get LAN reachability but no internet, enforced by an nft filter inside the rootless netns with fail-open semantics and mandatory drift detection."
sensitivity: public
created: 2026-07-17
updated: 2026-07-17
---

# ADR-045: Restricted-Egress Tier — LAN-Only Network with In-Netns nft Filter

**Date:** 2026-07-17
**Status:** Accepted. Executes GH#334 (design handoff from the htpc-mgmt wayfinder
map #3, tickets #4–#8, private tracker — decision trail, research note, and prototype
findings live there). Substrate side (host `nftables` package declared, coupling
documented) shipped in htpc-mgmt on 2026-07-17. Complements ADR-030 T4 (egress
observatory) and encodes the 2026-02-02 wrong-network-egress incident lesson as
topology.

---

## Context

A class of containers needs **LAN reachability but must never reach the internet**:
today `pihole-exporter` (polls the Pi at 192.168.1.69), `unpoller` (polls the UDM Pro
at 192.168.1.1), and `prometheus` (scrapes the Pi's node_exporter and, cross-bridge,
pinned reverse_proxy IPs). All three sat on `reverse_proxy` **purely for the default
route** — full internet egress they never legitimately use. `Internal=true` is not an
option: internal networks contribute no default route at all, which would sever the
LAN reach these services exist for (the "zero-egress candidates are not safe to
internalize" finding).

Host-level enforcement is impossible for rootless containers: pasta SNATs all egress
to host-origin, so host nftables sees no per-container source to attribute
(maintainer-acknowledged, podman discussion #27099). The only viable enforcement
point is **inside the rootless netns**, where per-bridge subnets are still visible.

All mechanism claims below were **runtime-proven in a live throwaway prototype
(2026-07-17)**: a custom nft table in the rootless netns survives container
restarts, network reloads, and network creates; netavark rewrites only its own
`table inet netavark`; the DNS path keeps working; cross-bridge scrapes keep working.

## Decision

### D1 — Three-tier egress model

| Tier | Mechanism | Egress | Members |
|------|-----------|--------|---------|
| `internal` | `Internal=true` networks | none (no default route) | DBs, backends (unchanged) |
| **`restricted-egress`** | non-internal network + in-netns nft filter | **LAN + container bridges only** | pihole-exporter, unpoller, prometheus |
| open | default-allow | unrestricted | rest of the fleet (unchanged) |

The new network is pinned like every fleet network: `Subnet=10.89.11.0/24`,
`Gateway=10.89.11.1`, `Internal=false` (quadlet `restricted-egress.network` →
`systemd-restricted-egress`).

### D2 — Enforcement: a separate nft table inside the rootless netns

`table inet egress_filter`, defined in and applied by `egress-filter-apply.sh` as a
single `podman unshare --rootless-netns nft '<commands>'` invocation — **argv, not
stdin and not a file path**. File paths don't cross the userns mount namespace (as
the handoff design noted), and deployment testing (2026-07-17) found the handoff's
stdin route (`nft -f -`) is **racy through podman unshare**: `nft` intermittently
read empty stdin and exited 0 — a successful parse of nothing, i.e. a silent
enforcement no-op that only the drift metric caught. argv is deterministic. Never
merged into `table inet netavark`: netavark rewrites its own table selectively; a
separate table survives its churn (prototype-observed).

Rules are **subnet-keyed** (members need no IP pinning for the filter):

- `ip saddr 10.89.11.0/24 ip daddr { 192.168.1.0/24, 10.89.0.0/16, 169.254.1.1 } accept`
- `ip saddr 10.89.11.0/24 counter drop`

`169.254.1.1` is pasta's `--dns-forward` shim — DNS keeps resolving for members
(aardvark forwards upstream itself). **Caveat: DNS tunneling remains an open
channel**; the egress observatory (ADR-030 T4) is the alerting complement, not this
filter. The LAN accept is deliberately the single flat VLAN the members actually
need (192.168.1.0/24) — widen consciously if a member ever needs IoT/WireGuard
ranges. No IPv6 egress path exists under pasta today; the `inet`-family table is
where a v6 rule lands if one ever appears.

### D3 — Reapply loop: user timer as enforcer AND sensor

The netns and every rule in it **die with the last bridge container and on
reboot** — reapply is the core problem, not the rules. `egress-filter.timer`
(1-minute cadence) runs `egress-filter-apply.sh`: idempotent apply (add + flush
prelude), then emits a textfile-collector metric set (netns/table presence,
drop counters, member count, single-homing violations, run timestamp). Netns absent
→ exit 0. No quadlet coupling, no `ExecStartPost` hooks, no path units.

### D4 — Failure semantics: fail-open + mandatory drift detection

Members run regardless of filter state — this is **defense-in-depth, not a
containment boundary**; an unfiltered member is no worse than the default-allow
fleet it just left. Convergence target: ≤1 min of the netns existing; **absence
>5 min alerts** (`EgressFilterAbsent`, plus `EgressFilterCollectorStale` for a dead
timer). The post-reboot unfiltered burst inside the first minute is explicitly
accepted.

### D5 — Single-homing invariant

**A restricted-egress member must not join any other non-internal network.**
Internal networks contribute no default route, so a compliant member has exactly
one default route — wrong-network egress becomes structurally impossible instead of
luck-dependent (the 2026-02-02 incident lesson encoded as topology). Policed
**live** by the timer (enumerates the network's members and their networks — even a
hand-run `podman network connect` is caught within a minute) and alerted as
critical (`EgressFilterSingleHomingViolation`). A commit-time quadlet lint is the
recommended declare-time complement (future work).

Corollaries applied with this ADR:

- **Prometheus's Traefik router is removed** (unused since fall 2025; Grafana is
  the UI and queries prometheus over `monitoring`) — this is what makes all three
  members single-homed-clean. Authelia's domain entry removed with it.
- **Zero new multi-homing anywhere** — in particular Traefik stays single-homed on
  `reverse_proxy`; multi-homing it with name-based backend URLs is the exact
  2026-02-02 failure topology.

### D6 — Deterministic scrape paths

Prometheus now shares **no network** with traefik/crowdsec: those jobs scrape the
pinned `reverse_proxy` IPs (10.89.2.69/.70) cross-bridge — pinned IP + kernel
routing, no DNS. unpoller/pihole-exporter now share **two** networks with
prometheus (names resolve ambiguously): those jobs scrape pinned `monitoring` IPs
(10.89.4.97/.96). `Options=isolate=false` is pinned in the `restricted-egress` and
`reverse_proxy` network quadlets, freezing today's cross-bridge forwarding against
netavark 2.0's planned strict-isolation default flip (declare-time pin; applies on
network recreation).

## Validation gate

1. LAN target reachable from a member-network container; a public IP **drops**.
2. A non-member still reaches the internet (no collateral filtering).
3. All prometheus targets healthy post-swap (traefik, crowdsec, unpoller, pihole,
   node-exporter-pi, blackbox probes, navidrome, home-assistant).
4. Timer metrics present; `egress_filter_singlehome_violations == 0`.
5. Both survive a real reboot — timer reconverges ≤1 min of the netns existing.

## Consequences

- Compromise of an exporter/prometheus can no longer exfiltrate directly to the
  internet (modulo DNS tunneling — observatory covers); lateral movement is
  limited to LAN + bridges, which these services touch by design.
- `prometheus.patriark.org` no longer routes (404 at Traefik); the DNS record can
  be retired at leisure.
- One more 1-minute user timer; cost is a few podman inspects + one nft apply.
- Future members: join the network, stay single-homed — the filter needs no
  per-member changes.
