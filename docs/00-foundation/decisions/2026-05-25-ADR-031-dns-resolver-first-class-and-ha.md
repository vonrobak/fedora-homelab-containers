---
type: ADR
title: "ADR-031: DNS Resolver — First-Class Integration & High Availability"
description: "ADR making the Pi-hole DNS resolver a first-class, redundant service — managed-as-code, monitored, SSO admin, and a keepalived HA VIP."
sensitivity: public
created: 2026-05-25
updated: 2026-05-25
---

# ADR-031: DNS Resolver — First-Class Integration & High Availability

**Date:** 2026-05-25
**Status:** Accepted (implementation phased — see `docs/97-plans/2026-05-25-pihole-resolver-first-class-and-ha.md`)

---

## Context

The Raspberry Pi at `192.168.1.69` runs Pi-hole + unbound and is the **sole recursive
resolver for the entire LAN**. It is simultaneously the most load-bearing device in the
homelab and the least integrated into it:

- Administered over **unauthenticated HTTP** (`http://192.168.1.69/admin`) — no TLS, no SSO.
- Managed by **ad-hoc SSH** from whichever workstation is reachable (MacBook address drifts;
  workhorse at `.71`).
- **Not in Git** (no config-as-code), **not backed up by Urd**, **not scraped by Prometheus**,
  **no redundancy**.

It fails the implicit service contract that every containerised service in this homelab already
meets. A "first-class citizen" here means meeting that contract across six dimensions:
**redundancy, observability, managed-as-code, a secured admin plane, backed-up state, and
deliberate updates.**

### The finding that orders the work (recon 2026-05-25)

The DNS resolver sits *beneath* the monitoring/alerting plane, so **its outage hides its own
alarm.** Measured, not assumed:

- `alertmanager` and `alert-discord-relay` resolve via `DNS=192.168.1.69` with **no fallback**.
- The host `/etc/resolv.conf` and both container networks (`reverse_proxy`, `monitoring`) point
  **only** at `.69`.
- Therefore, if the Pi dies, Alertmanager **cannot resolve `discord.com`** to report that it died.
  The failure is **self-masking** — the smoke detector is wired to the same fuse as the fire.

This is why **redundancy must precede monitoring**: monitoring a self-masking single point of
failure reports the outage at the same moment it causes it. Redundancy is the actual fix;
monitoring then tells you "one node is down, fix it at leisure" while resolution continues.

### Favourable constraints already in place

- **Prometheus can already reach the Pi directly** — it sits on `reverse_proxy` (10.89.2.79, LAN
  egress) *and* `monitoring`. No new scrape pathway is needed.
- **UnPoller already establishes the pattern** for monitoring an external LAN device (dual-network:
  `reverse_proxy` to reach the device, `monitoring` to be scraped by Prometheus).
- **`blackbox_exporter` is already a documented monitoring gap** — its DNS probe is the natural
  primary signal for this work.
- **DHCP is served by the UDM Pro, not Pi-hole** — so the resolvers can be **DNS-only**, which
  keeps high-availability failover simple (no DHCP failover to engineer).

## Decision

Elevate the LAN resolver to a first-class, redundant, observable, secured homelab service via the
decisions below. Concrete sequencing lives in the implementation plan; this ADR is the contract.

### D1 — Redundancy precedes monitoring; HA is active/passive, not load-balanced

Two Pi-hole + unbound nodes with **identical config**, fronted by a **keepalived VRRP Virtual IP**
(e.g. `192.168.1.53`). Whichever node is MASTER holds the VIP; on failure the BACKUP claims it
within seconds, transparently to clients. DHCP (on the UDM) hands out the **VIP as primary DNS plus
both real node IPs as secondaries** (defence in depth).

Active/active load-balancing is **rejected**: at homelab query volumes it buys nothing while
splitting query logs/stats across nodes and complicating the failure model. Active/passive with a
fast VIP gives the "takes over duties" behaviour cleanly. Resolvers are **DNS-only** (DHCP stays on
the UDM).

### D2 — The alert/egress path must not depend on the monitored resolver

The alert-delivery containers (`alertmanager`, `alert-discord-relay`), the host resolver, and the
container network defaults are configured with a resolver fallback **independent of any single
node**:

- **End state:** VIP primary + both node IPs as secondaries (stays filtered *and* redundant).
- **Interim** (before the second node exists): a public resolver (e.g. `9.9.9.9`) as
  **secondary only** — removes the dead-man's-switch immediately while primary stays Pi-hole.

A failure that takes out DNS must still be able to phone home.

### D3 — The resolver is managed as code, not hand-administered

Pi-hole, unbound, keepalived, and node-level settings are provisioned by an **idempotent Ansible
playbook** — the non-quadlet equivalent of "in Git, reproducible." The playbook is the mechanism
that makes the second node an *exact twin* and any node rebuildable from a dead SD card. Sanitised
configs are committed; secrets stay out of Git.

### D4 — The admin plane is secured and centralised — never raw HTTP, never internet-exposed

The Pi-hole admin UI is fronted by **Traefik** (TLS termination + **Authelia SSO** + a
**LAN/WireGuard IP-allowlist** middleware) with **no public DNS record** (split-horizon). Routing
is defined in `config/traefik/dynamic/routers.yml` per **ADR-016**, never in container labels. This
converts today's unauthenticated-over-HTTP admin into SSO-gated HTTPS while structurally preventing
internet exposure.

### D5 — Observability is layered, and the primary signal is functional, not liveness

Three layers, reusing the UnPoller pattern:

- **`node_exporter`** on each node — host/hardware health (temperature throttling, SD/disk wear,
  uptime), scraped directly by Prometheus.
- **`pihole-exporter`** (host-side container, dual-network like UnPoller; requires a Pi-hole v6 API
  token) — query / block / client statistics.
- **`blackbox_exporter`** with a **DNS probe module** — performs a *real* query against the VIP and
  each node and validates the answer. **This is the primary alert source.** A wedged-but-running
  resolver passes liveness and fails the functional probe: *"process up" ≠ "DNS answering
  correctly."*

Alerts: per-node down, blackbox DNS-probe failure (per node + VIP), VIP-failover event, node
temperature/disk. Grafana dashboards added.

### D6 — Config replication and log centralisation are distinct mechanisms

The owner's "syncs configs and logs" requirement is satisfied by **two independent paths**, not one
tool:

- **Config** (adlists, allow/deny, local DNS records) replicates primary→replica via
  **`nebula-sync`** — the Pi-hole **v6** successor to the now-defunct Gravity Sync. *(Confirm the
  Pi-hole major version first; tooling differs for v5.)*
- **Logs** centralise separately into **Loki** (Promtail/syslog from each node into the existing
  `syslog` path), giving unified query history alongside every other service.

### D7 — DNS is enforced at the perimeter

The UDM blocks outbound port 53 and known DoH endpoints from all client VLANs **except the resolver
nodes**, forcing all DNS through Pi-hole. This is both a security control and the **structural fix
for the browser-DoH bypass class** that produced the 2026-05-21 "nothing blocked" symptom (resolved
tactically via the Vivaldi secure-DNS toggle; this makes it un-bypassable).

### D8 — The resolver inherits the homelab's backup and update discipline

A nightly Pi-hole Teleporter/config export is rsynced into an **Urd-snapshotted** host directory,
bringing the resolver into the existing backup system (ADR-021 / ADR-029). Pi-hole / unbound / OS
updates follow the **deliberate, reviewed cadence** in the spirit of ADR-030 (no unattended upgrades
on load-bearing infrastructure), documented as a runbook.

### Hardware constraint

A resolver must be on **wired Ethernet** with a DHCP reservation (or static IP). Wi-Fi is rejected
for this role — the owner has already observed Wi-Fi address drift, and a resolver on Wi-Fi is a
recurring-outage source. This rules out Wi-Fi-only boards (e.g. Pi Zero 2 W) for the second node
unless given wired Ethernet via USB; a wired Pi (3B+/4/5) is preferred.

## Consequences

### Positive

- The DNS single point of failure is removed; the alert path survives a resolver outage.
- The resolver becomes reproducible (Ansible), observable (3-layer + functional probe), backed-up
  (Urd), and SSO-secured (Traefik) — it finally meets the service contract.
- The DoH bypass class is closed at the perimeter.
- The second node also mitigates SD-card failure (the dominant Pi hardware failure mode).

### Negative

- Two devices to maintain instead of one; keepalived + nebula-sync are new moving parts.
- The Ansible playbook is upfront effort before the redundancy payoff lands.
- Perimeter DNS lockdown (D7) can break a device that hardcodes a public resolver — mitigated with a
  scoped allow exception.

### Risks

- **VRRP split-brain** (both nodes claim the VIP) if priorities/auth are misconfigured — mitigated
  with authenticated VRRP, correct MASTER/BACKUP priorities, and alerting on failover events.
- **Silent nebula-sync drift** if replication fails unnoticed — mitigated by alerting on replication
  staleness.
- **Filtering weakened on the alert path** if a public tertiary resolver is used — accepted, scoped
  to egress-only containers (`alertmanager`, `alert-discord-relay`).

## Alternatives Considered

- **Dual-DNS via DHCP only (no VIP).** Simplest, but client-side failover is slow and uneven
  (multi-second resolver timeouts) and OS-dependent. Rejected as the *primary* mechanism; retained
  as the secondary belt-and-suspenders alongside the VIP.
- **Active/active load-balancing (dnsdist / anycast).** Overkill at homelab query volumes; splits
  query logs/stats; complicates the failure model. Rejected.
- **Govern DNS HA from the UDM as the single source of truth.** A sound instinct that conflates three
  layers. *Assignment* ("which DNS address do clients use?") already lives on the UDM via DHCP and
  stays there — it hands out the VIP. *Failover* and *resolution/filtering* should not move to the UDM:
  it has no native health-checked-handout mechanism (custom scripting on a closed appliance gets wiped
  by firmware updates and is gated behind FIDO2-touch SSH), and the only UDM-native option — hand out
  primary + secondary IPs and let clients fail over — *is* the rejected dual-DNS model above. The
  decisive inversion: the VIP yields **more** single-source-of-truth, not less — the UDM advertises one
  stable address and clients never know two nodes exist, so failover is server-side and invisible.
  Config replication (`nebula-sync`, D6) is also an irreducible Pi-to-Pi concern the UDM cannot own,
  since it cannot hold Pi-hole's filtering config. The UDM remains the assignment authority; HA stays on
  the nodes. *(The UDM being a hard SPOF for the whole LAN does not weaken this: the failures the second
  node guards against — SD-card death, a bad Pi-hole/unbound update, a node reboot — are not UDM
  failures, and the UDM cannot mitigate them.)* Rejected as the failover/resolution owner.
- **Local TLS on the Pi (Caddy/nginx) instead of Traefik.** More moving parts on the node,
  inconsistent with ADR-016's centralised routing. Rejected.
- **Leave as-is and just add monitoring.** Rejected — monitoring a self-masking SPOF reports the
  outage simultaneously with causing it. Redundancy is the fix; monitoring is the complement.

## Adjacent, not bundled

The **ADR-018** (`config/traefik/hosts` + static-IP) obsolescence review is **Traefik-internal and
unrelated** to DNS HA. The static-IP / VIP work here is a natural moment to *revisit* ADR-018, but it
must remain a **separate decision** — per the 2026-05-21 handoff, do not conflate the two.

## Related

- **ADR-016** — Configuration Design Principles (admin route lives in `routers.yml`, not labels)
- **ADR-018** — Static IP Multi-Network Services (adjacent; reviewed separately)
- **ADR-008** — CrowdSec Security Architecture (admin route reuses the middleware chain)
- **ADR-003** — Monitoring Stack (observability layers plug into the existing stack)
- **ADR-021 / ADR-029** — Urd backup + DB/storage (D8 backup integration)
- **ADR-030** — Container Supply-Chain Trust Model (deliberate-update discipline extended to the Pi)
- Implementation plan: `docs/97-plans/2026-05-25-pihole-resolver-first-class-and-ha.md`
- Prior investigation: `docs/98-journals/2026-05-21-pihole-dns-and-adr018-investigation-handoff.md`

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** Owner request to elevate the Pi-hole resolver to a first-class, secured, observable,
redundant homelab service; recon revealed a self-masking DNS dependency in the alert-delivery path.
