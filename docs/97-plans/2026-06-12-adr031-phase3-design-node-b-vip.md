# ADR-031 Phase 3 Design — Node B (Pi 5) + keepalived VIP

**Date:** 2026-06-12
**Status:** Design accepted — build gated on hardware acquisition (owner saving for a Pi 5)
**Satisfies:** the "design session (VIP placement, second host choice)" gate on the DNS-resolver-HA arc ([roadmap](../96-project-supervisor/roadmap.md))
**Parent plan:** [2026-05-25-pihole-resolver-first-class-and-ha.md](2026-05-25-pihole-resolver-first-class-and-ha.md) (Phase 3 section)
**Resolver IaC home:** `htpc-mgmt` repo (private Forgejo) — roles `pihole`, `unbound`, `keepalived`, `pihole_backup`, `log2ram`, `node_exporter`, `ssh_hardening` already exist and are Phase-3-ready (keepalived template has VRID 53, templated priority, vault-supplied auth)

> **Addendum 2026-06-12 (post-handoff, IPs revised in place):** the originally chosen VIP
> `192.168.1.53` and node B `192.168.1.68` both sat inside DHCP/reserved space — the usable
> static range on this LAN is `.69–.254`. Owner reassigned: **VIP = `192.168.1.72`**,
> **node B = `192.168.1.169`** (inventory hostname `raspberrypi-b`). VRID 53 unchanged — the
> port-53 mnemonic lives in the VRID, not the IP. All addresses below reflect the new values.
>
> **htpc-mgmt pre-build half: DONE same day** (commits `4a3a325` + `98be16a` on htpc-mgmt main;
> record: `~/htpc-mgmt/docs/journals/2026-06-12-adr031-phase3-prebuilt.md`). Unicast VRRP,
> BACKUP+nopreempt at 150/100, FAULT-on-failure `chk_dns.sh` (handoff defects 1–2 fixed), notify
> hook to syslog, node B inventoried, vault auth_pass rotated + `diff: false` on the template
> task. keepalived remains inert (`keepalived_enabled: false`); node A carries intended config
> drift until build evening's real apply.

## Decisions

**D-1 — Node B hardware: Raspberry Pi 5, PoE-powered, in the server cabinet.**
Owner decision 2026-06-12: no spare device on hand; saving toward a Pi 5 with a multipurpose
role beyond backup resolver. Wired via a spare PoE switch port (satisfies ADR-031's
wired-Ethernet hardware constraint; clean cabling, no wall-wart).
- **8GB** preferred over 4GB for the multipurpose headroom (resolver alone needs <1GB).
- **NVMe over SD strongly recommended** (M.2 HAT, or a combined PoE+NVMe HAT): ADR-031 names
  SD-card death as the dominant Pi failure mode, and node B exists precisely to remove failure
  modes. SD card retained as recovery boot media.
- OS: Raspberry Pi OS Lite 64-bit — same Debian base as node A, so the Ansible roles apply
  unmodified.
- Rough budget: Pi 5 8GB ≈ 900–1,000 kr; PoE+(+NVMe) HAT ≈ 300–500 kr; 256GB NVMe ≈ 400–500 kr;
  case/mount ≈ 100–200 kr. **Total ≈ 1,700–2,200 kr.**

**D-2 — VRRP transport: unicast peers, not multicast.**
`unicast_src_ip`/`unicast_peer` between `.69` and `.169`. Multicast VRRP (224.0.0.18, proto 112)
can be silently eaten by IGMP-snooping settings on UniFi gear; unicast is ordinary IP between
two static LAN addresses and removes that entire debugging class. Requires a small extension to
the existing keepalived role template.

**D-3 — No preemption.**
Both nodes configured `state BACKUP` + `nopreempt`; node A priority 150, node B 100. One
failover per failure — when node A recovers (e.g. after maintenance), the VIP stays on node B
until manually failed back (or B fails). Config is replicated (D-6), so either node serving the
VIP is equally correct; flap-avoidance wins. Manual failback: restart keepalived on the
current MASTER during a quiet window.

**D-4 — Health check is functional, not liveness** (same philosophy as the Phase-2 blackbox
probes). `track_script`: resolve a known local record (`patriark.org` A via `127.0.0.1`) with
`dig +time=2 +tries=1`; interval 5s, fall 2, rise 2. A wedged-but-running Pi-hole releases the
VIP; a dead process does too. Script failure → FAULT state (do not merely lower priority).

**D-5 — VIP `192.168.1.72/24`, VRID 53** (as pre-decided in the plan; VRID already in the role
template). VRRP auth_pass via ansible-vault — never committed.

**D-6 — Config replication: nebula-sync as a quadlet on fedora-htpc**, in the containers repo
(digest-pinned per ADR-030, observable like every other workload). Direction A→B on a 6h
schedule + manual trigger before drills. Pi-hole v6 Teleporter API both ends.

**D-7 — Alert-path DNS end-state** (replaces the Phase-0 `9.9.9.9` interim):
`alertmanager` + `alert-discord-relay` get `DNS=192.168.1.72` (VIP), `DNS=192.168.1.69`,
`DNS=192.168.1.169` — survives VIP loss (VRRP dead) as long as either node answers. Host
`/etc/resolv.conf` (immutable) gains `nameserver 192.168.1.169` as internal-only fallback.
Afterwards the D7 perimeter-lockdown exception for `.70 → 9.9.9.9:53` becomes unnecessary —
remove it when enabling the UDM lockdown.

**D-8 — Cross-repo work split.**
- `htpc-mgmt`: node B inventory entry (`192.168.1.169`, per-host `keepalived_priority`),
  keepalived role extension (unicast peers, nopreempt, track_script), vault secret.
- `containers` repo: nebula-sync quadlet; Prometheus scrape additions (`node-exporter-pi-b`,
  blackbox dns probes for `.169` + VIP); alert additions (VIP-failover event, per-node down —
  single-node-down is a *warning*, VIP-probe-failure is *critical*); `routers.yml` pihole
  target → VIP; alert-container `DNS=` updates.

**D-9 — Power-domain note.** Node B is PoE-powered: its power domain is the switch, not a wall
outlet. When the UPS arc (trajectory T3) lands, the switch must be on it, or both resolvers can
die in the same brownout that the htpc survives. Recorded here so the UPS sizing includes the
PoE budget.

**Out of scope (deliberate, L-061):** the Pi 5's multipurpose ambitions (standby alert relay,
syslog target, rebuild-drill substrate) are *headroom reserved, nothing built* — each promotes
from Horizon on its own concrete need. Phase 3 ships a resolver.

## Pre-build work (no hardware required — can start any session)

1. ~~**htpc-mgmt:** extend keepalived role + node B inventory + vault~~ — **DONE 2026-06-12**
   (see addendum above).
2. **containers repo:** draft the nebula-sync quadlet and the new scrape/alert config as
   commented-out staging (a VIP probe before the VIP exists would page).
3. **Owner (UDM, copy-paste runbook):** DHCP reservation for the Pi 5 MAC on arrival; confirm
   nothing in the Policy Table would block unicast `.69 ↔ .169` traffic (ordinary IP — expected
   fine).

## Build sequence (hardware-arrival evening, ~2–3h)

1. Flash Pi OS Lite 64-bit → boot → reserve `.169` → cable to PoE port.
2. `ansible-playbook site.yml --limit node-b` (common, ssh_hardening, node_exporter, unbound,
   pihole, pihole_backup, keepalived; log2ram only if SD-booted).
3. Deploy nebula-sync quadlet → verify config parity (gravity counts, local records match).
4. Start keepalived on A, then B → VIP lands on A (first-up under nopreempt; start A first).
5. **Drills (all three, in order):**
   - *Kill MASTER:* `systemctl stop keepalived` on A → VIP on B within ~3×advert_int,
     `dig @192.168.1.72` loop never times out, failover + node-down alerts fire.
   - *Wedged resolver:* stop `pihole-FTL` only on the MASTER → track_script releases VIP.
   - *Recovery without flap:* restart A fully → VIP stays on B (nopreempt verified).
6. Cutover: UDM DHCP DNS = VIP + `.69` + `.169`; `routers.yml` pihole target → VIP;
   alert-container `DNS=` lines per D-7; host resolv.conf fallback.
7. Verify Phase-3 success criteria from the parent plan + blackbox probes green for `.169` and VIP.
8. Schedule the D7 perimeter lockdown follow-up (drop the `9.9.9.9` exception).

## Success criteria

Parent plan Phase 3 criteria, plus: all three drills pass; alert-path containers resolve with
node A *fully powered off*; `nopreempt` confirmed (no second failover on A's recovery).
