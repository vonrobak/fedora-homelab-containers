---
type: ADR
title: "ADR-042: VPN Egress Sidecar for qBittorrent (gluetun + ProtonVPN)"
description: "ADR routing qBittorrent's egress through a gluetun ProtonVPN sidecar with a kill-switch via network-namespace sharing, off the home WAN IP."
sensitivity: public
created: 2026-07-01
updated: 2026-07-02
---

# ADR-042: VPN Egress Sidecar for qBittorrent (gluetun + ProtonVPN)

**Date:** 2026-07-01
**Status:** Accepted (Phase 1 — VPN + kill-switch; port forwarding deferred to Phase 2)

---

## Context

qBittorrent runs on the `reverse_proxy` network in passive/outbound-only mode and
egresses its BitTorrent swarm — ~360 concurrent connections to random peer IPs
(observed via the Tier 4 egress observatory, ADR-030 P7) — **directly on the home
WAN IP**. This is the "troublesome traffic" symptom: a residential IP originating
hundreds of peer connections lands on scan/abuse lists and generates downstream
noise. It is also the one service the egress observatory cannot classify — it is a
`peer_swarm_services` member (count-only), a documented blind spot in
`config/supply-chain/known-egress.md`.

Prior art in this repo deliberately noted qBittorrent has **no VPN** (known-egress.md,
"Adjacent finding") as a pending privacy/security decision. This ADR takes it.

**Sovereignty tension.** The project minimizes external dependencies (digital
sovereignty). A commercial VPN is an external trust dependency, which cuts against
that grain. It is nonetheless the right call *for torrent egress specifically*: the
goal is an exit IP that is **shared, no-logs, and legally buffered** — properties a
self-hosted VPS exit cannot provide (a personal VPS just relocates an attributable
IP and adds no anonymity set). The dependency is scoped to one service's egress and
introduces no data-ownership loss.

## Decision

**Route qBittorrent's egress through a `gluetun` VPN sidecar via network-namespace
sharing, with a kill-switch.**

1. **Sidecar + netns sharing.** New `gluetun` container (digest-pinned, ADR-030) holds
   the `reverse_proxy` slot `10.89.2.85`. qBittorrent joins its namespace
   (`Network=container:gluetun`) and has **no other interface** — so a tunnel failure
   cannot leak to the WAN (gluetun's firewall is a kill-switch by construction).
2. **Provider: ProtonVPN over WireGuard.** Consolidates trust on Proton (already used
   for `proton-bridge`) — one provider, one bill, WireGuard performance. The WireGuard
   private key is a **secret sourced from OpenBao via htpc-mgmt `secretctl`**
   (ADR-041); handle name `gluetun_wireguard_key`. Never `podman secret create` here.
3. **Phase 1 = outbound-only (no port forwarding).** Matches qBittorrent's current
   passive mode; the privacy/kill-switch goal is fully met without it. Port forwarding
   (better ratios; ProtonVPN NAT-PMP via gluetun + a gluetun→qBittorrent port-sync
   hook) is **Phase 2**, taken only if ratios warrant the added moving parts.
4. **Routing unchanged in spirit.** Traefik's `qbittorrent` service re-points from
   `http://qbittorrent:8085` to `http://gluetun:8085`; `torrent.patriark.org`,
   Authelia, CrowdSec, rate-limit all stay. DNS moves into the tunnel (drop
   qBittorrent's `DNS=192.168.1.69`) so lookups don't leak outside the VPN.
5. **Observatory re-baseline (honest scope).** qBittorrent leaves the `reverse_proxy`
   tier; **gluetun becomes the sampled egress-tier container and inherits
   `peer_swarm_services` (count-only)** — because the shared-netns socket table still
   shows the peer IPs (the observatory reads `/proc/<pid>/net/tcp`, which is
   pre-tunnel at L3). The swarm noise is *not* eliminated from the observatory; what
   changes is the **wire**: only an encrypted WireGuard flow to the ProtonVPN endpoint
   leaves the router. gluetun's real off-host destination (the VPN endpoint) is added
   to the egress baseline as expected.

**Exit selection (Phase 1 implementation, set 2026-07-01).** Exit country = **Estonia**
(`SERVER_COUNTRIES=Estonia`), chosen for its strong digital-rights posture. **`PORT_FORWARD_ONLY=on`
is mandatory, not cosmetic:** gluetun equates port-forward-capable with P2P-enabled, and Estonia's
Proton footprint is only 5 logical servers — 2 standard P2P (**EE#13, EE#23**, Tallinn) and 3
**Secure Core** (CH-EE, SE-EE) on which ProtonVPN **blocks P2P**. Without the filter gluetun could
randomly land on a Secure Core node and torrents would fail "No P2P traffic permitted". This filter
only *selects* the server; it does not enable port forwarding (Phase 2's `VPN_PORT_FORWARDING=on`).
Trade-off: only 2 usable servers ⇒ **no in-country fallback** — with the kill-switch, both being down
means qBittorrent is offline (accepted; monitor tunnel health post-cutover). Note the ProtonVPN
WireGuard key is **account-wide**, so the country generated in the dashboard need not match
`SERVER_COUNTRIES` — exit country is a gluetun-side, config-only change (no key regen).

## Consequences

- **The WAN IP no longer originates torrent traffic** — the presenting problem is
  fixed. Egress is a single encrypted tunnel to ProtonVPN.
- **Airtight kill-switch.** qBittorrent cannot transmit if the tunnel is down (no
  fallback interface exists). qBittorrent `BindsTo=gluetun.service` for clean lifecycle.
- **New external dependency**, accepted and scoped (this ADR's Context). Availability:
  if ProtonVPN/gluetun is down, qBittorrent has no network — acceptable for a
  best-effort download service.
- **Observatory:** honest — swarm visibility moves to gluetun (still count-only). A
  kill-switch *leak* is prevented at the firewall layer, not detected at the socket
  layer (both tunneled and untunneled peer sockets look identical in `/proc`).
- **Rootless caveat:** gluetun needs `/dev/net/tun` + `NET_ADMIN`; on rootless it uses
  userspace WireGuard (wireguard-go). Kernel-WG sysctls (`src_valid_mark`) are not
  required. Verify the tunnel establishes at deploy (leak-test gate below).
- **Deploy gate (L-049):** not done until (a) `curl -I https://torrent.patriark.org`
  works through gluetun, (b) qBittorrent's public IP (via its own tracker announce /
  a checkip through the tunnel) is the **ProtonVPN** IP, not the WAN IP, and (c) a
  **leak test**: stop gluetun → qBittorrent has zero connectivity (no WAN fallback).

## Alternatives considered

- **Self-hosted VPS WireGuard exit** — rejected: relocates an attributable IP, no
  shared anonymity set, no legal buffer; more sovereign but worse for the actual goal.
- **Mullvad / IVPN** — fine privacy, but both removed port forwarding, foreclosing
  Phase 2; ProtonVPN keeps the option open and consolidates on Proton.
- **`Internal=true` / do nothing** — N/A (qBittorrent needs internet) / rejected (the
  presenting problem persists).

## Related

- ADR-030 P7 (Tier 4 egress observatory; `peer_swarm_services`), ADR-036 (bake policy).
- ADR-041 (OpenBao secret handles; htpc-mgmt ADR-007 canonical for the mechanism).
- ADR-018 (static-IP multi-network) — gluetun holds the static slot for a clean route.
- `config/supply-chain/known-egress.md` "Adjacent finding" (the no-VPN note this closes).
