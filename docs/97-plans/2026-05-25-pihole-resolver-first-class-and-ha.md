# Plan: Pi-hole Resolver — First-Class Integration & High Availability

**Date Created:** 2026-05-25
**Status:** Proposed
**Last Updated:** 2026-05-25 (Phase 0 container step implemented + verified)
**Implements:** ADR-031 (`../00-foundation/decisions/2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md`)
**Prior context:** `../98-journals/2026-05-21-pihole-dns-and-adr018-investigation-handoff.md`

## Objective

Turn the sole LAN resolver (Pi-hole + unbound on the Pi at `192.168.1.69`) into a first-class
homelab service: redundant, observable, managed-as-code, SSO-secured, backed-up, and deliberately
updated — per ADR-031. Sequenced so the **self-masking DNS dependency in the alert path is removed
first** and **redundancy lands before** the work that depends on it.

## Background (verified 2026-05-25)

- Prometheus is on `reverse_proxy` (10.89.2.79) + `monitoring` (10.89.4.79) → **can scrape the Pi
  directly**; no new pathway needed.
- UnPoller (`quadlets/unpoller.container`) is the **dual-network template** for monitoring a LAN
  device: `Network=systemd-reverse_proxy:ip=…` (reach device) + `Network=systemd-monitoring` (be
  scraped). Reuse it.
- `blackbox_exporter` is **not deployed** (known gap in `99-reports/2026-04-17-service-configuration-review.md`).
- `alertmanager` + `alert-discord-relay` resolve only via `192.168.1.69` (no fallback) → alert path
  dies with the Pi.
- DHCP is on the **UDM Pro**, not Pi-hole → resolvers can be DNS-only; HA stays simple.
- IP plan: node A `192.168.1.69` (existing), node B `192.168.1.68` (new reservation),
  **VIP `192.168.1.53`** (mnemonic: port 53). Adjust to taste.
  > **Adjusted 2026-06-12 (Phase 3 design session):** `.53`/`.68` sit in DHCP/reserved space
  > (usable static range is `.69–.254`). Final: **node B `192.168.1.169`, VIP `192.168.1.72`**,
  > VRID 53 keeps the mnemonic. Phase 3 IPs in this doc are superseded by
  > [the design doc](2026-06-12-adr031-phase3-design-node-b-vip.md) — follow that at build evening.

---

## Approach

### Phase 0 — De-risk the alert path *(small, do first — ADR-031 D2)*

Stop the dead-man's-switch before any larger work.

1. Add a **secondary resolver** to the egress-only alert containers:
   - `quadlets/alertmanager.container`: `DNS=192.168.1.69` → keep, add `DNS=9.9.9.9` (interim).
   - `quadlets/alert-discord-relay.container`: add explicit `DNS=192.168.1.69` + `DNS=9.9.9.9`.
2. Give the **host** a fallback resolver (NetworkManager: secondary `dns=` entry, not replacing
   Pi-hole as primary).
3. `daemon-reload` + restart the two services; verify they still resolve with Pi-hole up, and still
   resolve with Pi-hole simulated-down (block `.69` temporarily / stop Pi-hole briefly).

> End state (after Phase 3) replaces `9.9.9.9` with the VIP + both node IPs so filtering is retained.

### Phase 1 — First-class single node *(ADR-031 D3, D4, D7, D8 + hardening)*

Bring the *existing* node up to contract before cloning it.

1. **Config-as-code (D3).** Create `ansible/` (or `provisioning/pihole/`) with an idempotent
   playbook for: Pi-hole install/config, unbound (recursive, DNSSEC on), `node_exporter`,
   `keepalived` (installed but Phase-3-activated), `log2ram` (reduce SD writes), SSH hardening
   (key-only, no passwords, LAN-restricted). Commit sanitised config; secrets via Ansible Vault or
   out-of-band.
2. **Wired + reserved (D3 hardware note).** Confirm the node is on **wired Ethernet** with a UDM
   DHCP reservation. (A resolver on Wi-Fi is out — see ADR-031.)
3. **SSO admin via Traefik (D4).** In `config/traefik/dynamic/`:
   - Add an `ip-allowlist` middleware (private + WireGuard ranges) in `middleware.yml`.
   - Add router `pihole` in `routers.yml`: `pihole.patriark.org` → `http://192.168.1.69:80`
     (later: → the VIP), middleware chain
     `crowdsec-bouncer@file, rate-limit@file, ip-allowlist@file, authelia@file, security-headers@file`.
     **No public DNS record** — internal split-horizon only.
   - Verify Traefik can reach the LAN IP (it's on `reverse_proxy`); apply ADR-018 `/etc/hosts`
     handling only if a multi-network resolution issue actually appears (do **not** pre-emptively).
4. **Backups (D8).** Cron on the node: nightly Teleporter/config export → `rsync` into an
   Urd-snapshotted host directory. Confirm the path is within Urd's backup set.
5. **Perimeter DNS enforcement (D7).** On the UDM: firewall rules blocking outbound 53 + known DoH
   endpoints from client VLANs except the resolver node(s). Stage carefully; add allow-exceptions
   for any device with a hardcoded public resolver. *(Hand the owner copy-paste UDM blocks — FIDO2
   SSH can't be driven from here.)*
   - **Sequencing caveat:** this lockdown blocks the homelab host's (.70) outbound 53 to `9.9.9.9`,
     which would disable the Phase-0 alert-container fallback. Before enabling D7, either add a scoped
     allow-exception for .70→9.9.9.9:53, or (cleaner) move the alert-container fallback off `9.9.9.9`
     onto the second node's internal IP once Phase 3 exists.

### Phase 2 — Observability *(ADR-031 D5)*

1. **node_exporter scrape.** Add a `node-exporter-pi` job to `config/prometheus/prometheus.yml`
   targeting `192.168.1.69:9100` (later add node B + VIP).
2. **pihole-exporter.** New `quadlets/pihole-exporter.container` on the UnPoller dual-network
   pattern; config points at the Pi v6 API (token via Podman secret). Add `pihole` scrape job
   (`pihole-exporter:<port>` on the monitoring network).
3. **blackbox_exporter (the primary signal).** New `quadlets/blackbox-exporter.container` +
   `config/blackbox/blackbox.yml` with a `dns` probe module. Add a `blackbox-dns` scrape job using
   the `__param_target` relabel pattern, targeting each node IP **and the VIP**.
4. **Alerts** in `config/prometheus/alerts/` (new file, e.g. `dns-resolver-alerts.yml`):
   per-node `up==0`, blackbox DNS-probe failure (per node + VIP), VIP-failover, Pi temp/disk.
   Route critical (VIP probe failing = real outage) → discord-critical; single-node-down → warning.
5. **Grafana dashboard** for resolver health (query rate, block rate, cache hit, per-node up,
   probe latency, temp).

### Phase 3 — High availability: second node *(ADR-031 D1, D6)*

1. **Provision node B** with the **same Ansible playbook** (`192.168.1.68`, wired, reserved).
2. **keepalived VIP (D1).** Activate VRRP on both nodes for VIP `192.168.1.53`; node A MASTER
   (higher priority), node B BACKUP; **authenticated VRRP**; health-check script tied to Pi-hole/DNS
   liveness so a wedged Pi-hole releases the VIP.
3. **Config replication (D6).** Deploy `nebula-sync` (new `quadlets/nebula-sync.container` or on a
   node) syncing node A → node B via the Pi-hole v6 Teleporter API on a schedule. *(Confirm Pi-hole
   v6; v5 needs different tooling.)*
4. **Log centralisation (D6).** Promtail/syslog on both nodes → existing Loki `syslog` path.
5. **Cut clients over to the VIP.** UDM DHCP DNS = **VIP primary + node A + node B** secondaries.
   Update `pihole.patriark.org` router target and the alert-path `DNS=` entries to **VIP + both node
   IPs**, replacing the Phase-0 `9.9.9.9` interim.
7. **Host fallback (deferred from Phase 0 per owner decision).** The host's immutable `/etc/resolv.conf`
   stayed Pi-hole-only (fail-closed) through Phases 0–2 to avoid leaking to a public resolver. Now add
   the **second node's internal IP** as secondary: `chattr -i /etc/resolv.conf`, append
   `nameserver 192.168.1.68` (or the VIP), `chattr +i`. Still filtered, no public leak, and no D7
   allow-exception needed since the fallback is internal.
6. **Failover drill.** Stop Pi-hole on node A; confirm VIP migrates to node B within seconds,
   resolution continues, the failover alert fires, and node-A-down alert fires.

### Follow-up (separate decision, do not bundle)

- **ADR-018 obsolescence review** per the 2026-05-21 handoff — adjacent to the static-IP/VIP work but
  Traefik-internal and unrelated. Track as its own task/ADR.

---

## Success Criteria

- **Phase 0:** alert containers + host resolve external names with Pi-hole *down*; no other change.
- **Phase 1:** node rebuildable from the Ansible playbook; `pihole.patriark.org` serves HTTPS, gated
  by Authelia, reachable only from LAN/WireGuard, absent from public DNS; nightly export lands in
  Urd's set; client-VLAN DNS egress is blocked except the resolver.
- **Phase 2:** Prometheus shows `up==1` for node + pihole + blackbox jobs; a deliberately wrong
  upstream / stopped Pi-hole makes the **blackbox DNS probe fail** (proving functional > liveness);
  alerts visible in `/rules`; dashboard populated.
- **Phase 3:** killing the MASTER migrates the VIP to BACKUP in seconds with uninterrupted
  resolution; `nebula-sync` shows node B config matching node A; both nodes' logs in Loki; DHCP hands
  out VIP + both nodes.

## Verification

```bash
# Phase 0 — alert path survives DNS loss (run on fedora-htpc)
podman exec alertmanager getent hosts discord.com            # resolves with Pi-hole up
systemctl --user stop pihole 2>/dev/null || true             # or block 192.168.1.69 at host fw
podman exec alertmanager getent hosts discord.com            # still resolves via fallback
# (restore Pi-hole afterward)

# Phase 1 — admin plane
curl -I https://pihole.patriark.org                          # 302 → Authelia, valid TLS
dig +short pihole.patriark.org @1.1.1.1                      # empty (no public record)

# Phase 2 — monitoring + functional probe
podman exec prometheus promtool check rules /etc/prometheus/alerts/dns-resolver-alerts.yml
podman exec prometheus wget -qO- \
  'http://localhost:9090/api/v1/query?query=up{job=~"node-exporter-pi|pihole|blackbox-dns"}' | head -c 400
podman exec prometheus wget -qO- \
  'http://localhost:9090/api/v1/query?query=probe_success{job="blackbox-dns"}' | head -c 400

# Phase 3 — failover drill + replication (run against the nodes)
dig +short example.com @192.168.1.53                         # VIP answers
# stop Pi-hole on MASTER, then re-query the VIP within a few seconds:
dig +short example.com @192.168.1.53                         # BACKUP now answers via migrated VIP
```

## Rollback

- **Phase 0:** revert the two quadlets + NM change; `daemon-reload` + restart. Pure addition of a
  secondary resolver — removing it restores prior behaviour.
- **Phase 1:** Traefik changes are `git revert` + Traefik restart (single-file `hosts` bind mount is
  inode-bound — restart, don't just edit). Firewall rules are removable on the UDM. Ansible is
  additive.
- **Phase 2:** each exporter/job/alert is isolated; `git revert` the quadlet/scrape/alert file.
  Removing them cannot affect existing alerting.
- **Phase 3:** keepalived/nebula-sync are separate services — stop them and revert DHCP to the single
  Pi IP to return to today's topology. BTRFS snapshots + `git revert` underneath.

## Progress Log

- 2026-05-25 — Plan drafted from ADR-031. Status: Proposed. Owner chose keepalived VIP (active/passive),
  Traefik internal-only + SSO admin, and ADR + plan as the first deliverable. Sequence: Phase 0 → 1 →
  2 → 3; ADR-018 review tracked separately.
- 2026-05-25 — **Phase 0 container step DONE + verified.** Added `DNS=192.168.1.69` + `DNS=9.9.9.9` to
  `alertmanager.container` and `alert-discord-relay.container` (the latter previously inherited
  network DNS only). Both restarted healthy; `podman inspect` shows `[192.168.1.69 9.9.9.9]`; both
  resolve external names; `9.9.9.9` reachable from the network. **Host step BLOCKED on a finding:**
  `/etc/resolv.conf` is **immutable-pinned** (`chattr +i`) to Pi-hole only (deliberate fail-closed;
  systemd-resolved disabled). NM applies DNS at device level but cannot rewrite the file. Host fallback
  **deferred to Phase 3 per owner decision** — host stays fail-closed/Pi-hole-only now; the fallback
  will be the *internal* second node (no public leak, no D7 exception needed). Critical alert path is
  already protected at the container level regardless. **Phase 0 = COMPLETE** (host step intentionally
  deferred, not skipped).
