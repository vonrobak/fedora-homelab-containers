# UDM-Pro Threat Notifications During Fedora 44 Upgrade — Investigation

**Date:** 2026-05-13
**Status:** Closed. No intrusion. Documented forensics paths to memory. This journal also seeds a future `/create-skill "network investigator"` session.
**Trigger:** During the Fedora Workstation 43 → 44 dnf-system-upgrade reboot of fedora-htpc, the UniFi mobile app pushed several "Threat Detected and Blocked" notifications. One was perceived as `fedora-htpc 6c:84 → fedora-htpc 6c:84` (self-to-self), raising suspicion of compromise or LAN-side anomaly.

---

## What turned out to be true

1. **No intrusion.** Every threat alert UDM-Pro has logged in 53 days (677 events) is external scan traffic. 100% are `ET TOR` (Tor exit/relay node connections) or `ET CINS` (poor-reputation IP lists). Every single one was blocked by Suricata.

2. **No reboot-correlated spike.** May 13 had 7 push notifications — *below* the weekly average (May 9 had 17, May 7 had 12, May 8 had 4). The reboot window (~20:42–20:57, identified via syslog-ng reconnect loop on port 1514) coincided with 3 of those 7 routine alerts, which gave the impression of a flurry.

3. **No self-to-self traffic exists.** All 677 alerts have a single src/dst MAC pair: `9c:05:d6:4a:39:cb` (UDM WAN MAC) → `d4:5d:64:50:6c:84` (fedora-htpc NIC MAC). Zero alerts with fedora-htpc as source MAC. No IPv6 alerts (no AAAA records exist for `patriark.org` anyway). No Tailscale/Wireguard tunnels running. The `ipsalert` mongo collection on this firmware is empty.

4. **The "fedora-htpc → fedora-htpc" notification body is a UniFi mobile app rendering quirk.** The push notification log (`/data/unifi-core/logs/cloud.notifications.log`) only stores the title (`"Threat Detected and Blocked"`); the body is constructed client-side and falls back to rendering both endpoints as the destination's device name when the source has no LAN client match. Cosmetic only — the underlying alert is always `<external IP> → fedora-htpc`.

---

## What was non-obvious and worth keeping

- **UDM-Pro firmware 5.0.16 stores IDS alerts in `/var/log/ulog/threat.log`, not `eve.json`.** Custom Ubiquiti JSON-per-line format with a syslog prefix. Strip the prefix with `sed 's/^[^{]*//'` before jq — do NOT use `grep -oE "{.*}"` because BusyBox ERE handles `{` weirdly.
- **The controller's `alarm` and `ipsalert` mongo collections are empty on this firmware.** Push notifications are rendered directly from threat.log entries; there is no persistent alarm store to query. Don't waste time on those collections.
- **`sqlite3` is not installed on UDM-Pro.** The `/data/uos/db/alarms.db` SQLite file exists but you'd need to scp it off-box to query it.
- **For WAN-inbound traffic, `src_mac` in Suricata events is the UDM's WAN MAC, not the actual remote MAC.** This matters when classifying alerts — "internal source" cannot be inferred from src_mac alone for inbound traffic.
- **Port 1514 syslog disconnect/reconnect loop is a reliable reboot marker** for fedora-htpc (Promtail/syslog-ng forwarder). Useful for pinpointing outage windows without host-side log access.
- **Push notification volume baseline:** ~7–17/day are routine on this homelab's public IP. The vast majority is meaningless noise from TOR/CINS scanners that Suricata already blocked. The user could safely disable these pushes (or disable the ET TOR / ET CINS rule categories in UniFi → Security → IPS) without losing real signal.

All of the above is now in memory under `reference_udm_forensics.md`.

---

## Future skill: `/create-skill "network investigator"`

This session repeatedly hit the pattern: *something looks wrong at the network layer; find which component owns the data; SSH or grep into it; parse a vendor-specific log format; correlate across components.* It's slow and error-prone to redo from scratch each time. Worth packaging as a skill.

### Skill purpose

Diagnose network-layer anomalies across the homelab's full stack — from the public-IP edge (UDM-Pro) through the reverse proxy (Traefik), the security middleware (CrowdSec, Authelia), the container network fabric (Podman, 8 networks), and the observability pipeline (Promtail → Loki → Grafana). Distinguish real threats from background noise; pinpoint outage windows; correlate symptoms across layers.

### What the skill should bundle

**Tools:** Bash (heavy use), Read, Grep, Glob, WebFetch (for vendor docs).

**Component-by-component playbook** (each section: log paths, parsing gotchas, mongo/sqlite/API access, useful one-liners):

1. **UDM-Pro** — see `~/.claude/projects/-home-patriark-containers/memory/reference_udm_forensics.md` (already complete). Includes Suricata threat.log, push notification log, controller mongo, BusyBox parsing gotchas, FIDO2 SSH constraint (`reference_udm_pro_ssh.md`).

2. **Traefik** — access log at `/mnt/btrfs-pool/subvol7-containers/traefik-logs/access.log`, filtered to 4xx/5xx only (filter is in `config/traefik/traefik.yml`); dashboard at `traefik.patriark.org`; dynamic routing at `config/traefik/dynamic/routers.yml` (ADR-016: all routing here, never in labels); the empty-query gotcha is documented in `2026-04-28-traefik-access-empty-query-investigation.md`.

3. **CrowdSec** — `cscli decisions list`, `cscli alerts list`, bouncer logs; integration with Traefik via `crowdsec-bouncer@file` middleware (ADR-008 fail-fast ordering).

4. **Authelia** — auth logs, Redis session store; OIDC vs forward-auth flows; YubiKey/WebAuthn paths (ADR-006).

5. **Podman networks** — 8 networks (see `AUTO-NETWORK-TOPOLOGY.md`); first `Network=` line gets default route (gotcha); static IPs + `/etc/hosts` override pattern (ADR-018) for multi-network containers; `podman network inspect`, `podman inspect <ctr> | jq '.[0].NetworkSettings'`.

6. **DNS** — internal split-horizon via UDM; external via Porkbun + ACME DNS-01; `dig +short A/AAAA <host> @<server>`; verify `/etc/hosts` overrides in containers via `podman exec <ctr> getent ahosts <host>`. Note: as of 2026-05-13 there are no AAAA records — the homelab is IPv4-only externally.

7. **Promtail / Loki** — Promtail config at `config/promtail/promtail-config.yml`; syslog receiver on UDP/TCP 1514 (this port being broken is a reliable reboot marker for fedora-htpc); LogQL queries via Grafana; `count_over_time({job="..."}[5m])` empty-vector gotcha (genuine quiet stack vs. broken pipeline).

8. **Container-to-container traffic** — `conntrack -L` on the host; `podman inspect` for IP-in-network; the hairpin NAT trap (containers querying `patriark.org` get the public IP and traffic loops via UDM unless `/etc/hosts` override is present).

### Documentation pointers to embed in the skill

The skill should know to consult these on-disk references when it doesn't know an answer (rather than hallucinating):

- `CLAUDE.md` (philosophy, conventions, gotchas catalog)
- `docs/AUTO-NETWORK-TOPOLOGY.md` (auto-generated; 8 networks, IPs, members)
- `docs/AUTO-SERVICE-CATALOG.md` (auto-generated; 30 containers, ports, networks)
- `docs/AUTO-DEPENDENCY-GRAPH.md` (4-tier critical path)
- `docs/00-foundation/decisions/` — ADR-008 (CrowdSec), ADR-016 (routing centralization), ADR-018 (multi-net static IPs), ADR-022 (NAT/socket activation)
- `docs/30-security/guides/` (7 guides + IR runbooks)
- `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`
- The `auto-doc-orchestrator.sh` regenerates the AUTO-* docs in ~2s — run it first if state seems stale.

### External vendor documentation the skill should be able to WebFetch

- Suricata rule reference (alert signature meanings, severity ladder)
- Emerging Threats (ET) rule catalog (TOR / CINS / EXPLOIT / MALWARE category semantics)
- Traefik v3 docs (dynamic config schema, middleware ordering)
- CrowdSec scenarios + decisions API
- UniFi Network Application API docs (mca-dump, controller endpoints)
- Podman networking docs (slirp4netns vs pasta vs CNI; SELinux `:Z` label)

### Behavioral conventions for the skill

- **Verify before recommending.** Memory references can name files/flags that have been renamed or removed — check existence first. (Already in feedback memory.)
- **Don't declare features absent/present from one UI surface.** Hedge or ask. (Already in feedback memory.)
- **Hand the user copy-paste blocks for UDM-Pro commands** rather than attempting SSH — FIDO2 hardware-key constraint. (Already in `reference_udm_pro_ssh.md`.)
- **Distinguish noise from signal early.** Most threat-intel alerts are background scans on a public IP. Establish a baseline (`/data/unifi-core/logs/cloud.notifications.log` daily counts) before treating a spike as anomalous.
- **Correlate timestamps across components.** A reboot/outage on fedora-htpc shows up as: syslog-ng disconnect on UDM (port 1514) ↔ `journalctl --boot=-1` on the host ↔ Traefik access-log gap ↔ Loki ingest rate drop. Always cross-check 2+ sources before concluding.
- **Pre-flight: verify timestamps are in the same timezone.** UDM logs are local time with `+0200` offset; container logs are typically UTC. Misalignment by 2h has burned investigations before.

### Suggested skill description (for SKILL.md frontmatter)

> Network-layer investigator for the homelab. Diagnoses anomalies, intrusion alerts, connectivity outages, and DNS/routing weirdness across the UDM-Pro edge, Traefik reverse proxy, CrowdSec/Authelia security middleware, Podman networks, and Promtail/Loki observability stack. Use when: a UDM mobile-app threat notification needs verification, a service is unreachable and the cause spans multiple layers, an outage window needs to be pinpointed from logs, you suspect hairpin NAT / DNS resolution issues, you need to distinguish background scan noise from real threats. Do NOT use for: writing new network configs (use homelab-deployment), pure host-OS debugging (use systematic-debugging), or designing new architecture (use infrastructure-architect).

### Starting point for the future session

1. `cat ~/.claude/projects/-home-patriark-containers/memory/reference_udm_forensics.md` — most of the UDM section already drafted.
2. `cat docs/98-journals/2026-05-13-udm-pro-threat-notifications-investigation.md` — this file.
3. Run `/create-skill "network investigator"` with the structure above as input.
4. Skill should follow the same conventions as `homelab-deployment` and `security-auditor` (look at their SKILL.md files for tone/structure).
5. Consider whether some sections (Traefik, CrowdSec, Podman, Loki) need their own reference memory files first, mirroring `reference_udm_forensics.md`. Probably yes — they can be drafted incrementally as investigations surface non-obvious facts about each layer.

---

## Files referenced

- `/var/log/ulog/threat.log` (UDM-Pro Suricata IDS)
- `/var/log/suricata/suricata.log` (UDM-Pro Suricata operational)
- `/data/unifi-core/logs/cloud.notifications.log` (UDM-Pro push notifications)
- `/var/log/messages` (UDM-Pro syslog — syslog-ng reconnect markers)
- `~/.claude/projects/-home-patriark-containers/memory/reference_udm_forensics.md` (NEW)
- `~/.claude/projects/-home-patriark-containers/memory/reference_udm_pro_ssh.md` (existing)
