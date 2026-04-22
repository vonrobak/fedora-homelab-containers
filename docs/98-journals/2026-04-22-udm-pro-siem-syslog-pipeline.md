# UDM Pro SIEM Syslog Pipeline — Build Retrospective

**Date:** 2026-04-22
**PR:** _pending_
**ADR:** [ADR-027](../00-foundation/decisions/2026-04-22-ADR-027-forward-nocow-workloads-subvol8-db.md)
**Context:** UDM Pro frequently surfaces "network intrusion attempt" notifications (both LAN-local flows and external scans hitting `192.168.1.70`). None of those events landed in Loki, so there was no way to correlate UDM IDS signals with Traefik access logs during incident review. The SIEM Server setting on UDM forwards raw syslog over UDP. This build wires that stream into the existing Promtail → Loki pipeline.

---

## What shipped

| File | Change |
|---|---|
| `quadlets/syslog.network` | NEW — dedicated `Internal=true` network (`10.89.7.0/24`) for the syslog ingestion tier |
| `quadlets/unifi-syslog.container` | NEW — linuxserver/syslog-ng, UDP 1514 bound to LAN IP only, static IP `10.89.7.69` |
| `config/unifi-syslog/syslog-ng.conf` | NEW — receive UDP on `0.0.0.0:1514`, write parseable template to `udm.log` |
| `config/promtail/promtail-config.yml` | `+ job_name: unifi-syslog` — tails `udm.log`, regex-parses, labels `program/facility/priority` |
| `quadlets/promtail.container` | `+ Volume=/mnt/btrfs-pool/subvol8-db/unifi-syslog:/var/log/unifi-syslog:ro,z` |
| `config/logrotate/unifi-syslog` | NEW — daily × 14, `copytruncate` to avoid cross-user podman signaling |
| `docs/00-foundation/decisions/2026-04-22-ADR-027-forward-nocow-workloads-subvol8-db.md` | NEW — forward-only NOCOW placement policy |

Defense-in-depth on ingress:
1. **firewalld rich rule** — `source address="192.168.1.1/32" port=1514 proto=udp accept` (authoritative source filter; runs before Podman's NAT layer).
2. **LAN-IP-bound PublishPort** — `192.168.1.70:1514:1514/udp`, not `0.0.0.0`.
3. **Dedicated `Internal=true` network** — the syslog receiver has no path to internet egress.
4. **File-based ingestion into Loki** — Promtail tails `udm.log` via a read-only bind mount, no network coupling between the receiver and the monitoring stack.

End-to-end verification: UDM ubios-udapi-server DHCP renewals on eth8 (public WAN) land in Loki via `{job="unifi-syslog"}`. Promtail metrics: `promtail_read_lines_total{path=".../udm.log"} 33`, `promtail_sent_entries_total{host="loki:3100"} 5215`, zero send errors.

---

## Lessons

### LSIO + bind mount + rootless Podman: run the container as root

syslog-ng refused to create `udm.log`, reporting `Error opening file for writing ... error='No such file or directory (2)'` against a directory that existed, was writable, and had the expected SELinux label. Spent real debugging time on this before the right frame clicked.

The frame that was wrong: "ENOENT means the path doesn't exist — something about the bind mount or SELinux is hiding it." Every hypothesis along that axis (`:U`, `:Z`, MCS labels, subvol8-db traversal ACLs, rootless userns mount visibility) was a dead end. The frame that was right: LSIO containers run the service as `abc` (uid 1000 inside container), the bind mount was owned by `root` inside container (uid 1000 on host = `patriark`), and a non-root process cannot create files in a 0755 root-owned directory. syslog-ng reports the permission failure as ENOENT in this path — misleading, not malicious.

Fix: `Environment=PUID=0` + `Environment=PGID=0`. In rootless Podman, container uid 0 maps to host uid 1000, which matches the bind mount owner. No subuid dance, no `:U` flag, no host-side chown — the idiomatic rootless Podman pattern when the workload is write-only and unprivileged work-inside-the-container is acceptable.

**Lesson:** when an LSIO container hits "can't open file" on a bind mount, the first hypothesis should be "who is the container process, and who owns the mount host-side." In rootless Podman, `PUID=0 PGID=0` is often the cleanest answer for write-only sidecars. The `:U` flag looks attractive but plays badly with `:Z` (SELinux relabel happens at mount time, then `:U` tries to chown the relabeled dir, and LSIO's s6-overlay re-chowns on top — it's a three-way race that rarely ends well).

### `chattr +C` on kernel 6.19 returned EINVAL; NOCOW wasn't needed here anyway

After `btrfs subvolume create /mnt/btrfs-pool/subvol8-db` and `btrfs property set subvol8-db compression none`, the next step per ADR-025's design was `chattr +C` to inherit NOCOW on new files. The command returned `chattr: Invalid argument while setting flags on /mnt/btrfs-pool/subvol8-db`, both on the subvolume root and on the first subdirectory. Didn't trace the kernel-level reason — there's a known interaction between `btrfs property set compression none` and NOCOW flag manipulation in some kernel versions, and the failure was surfaced early enough to re-evaluate whether NOCOW was load-bearing for this tenant at all.

It wasn't. `unifi-syslog` writes append-only logs, rotated daily, on a subvolume that isn't in the Urd snapshot set. The specific failure mode NOCOW prevents — COW amplification on random writes to files pinned by snapshots — does not apply to any of those three conditions for this workload. Skipping NOCOW here is correct, not a compromise.

The ADR-025 deferred question (five existing DBs in `subvol7-containers`) is different. Those workloads *do* need NOCOW, and the `chattr +C` failure is a blocker for that migration. But `unifi-syslog` doesn't carry that constraint, so the blocker doesn't transfer.

**Lesson:** when a platform primitive fails, re-derive whether you actually need it for this workload before investing in a workaround. The NOCOW reflex is correct for DB migrations; it's overhead for a log-receiver on an unsnapshotted subvolume. ADR-027 documents this so the next person adding a tenant doesn't waste the same cycles.

### Separating "new placement" from "migrate existing" — the cleanest ADR decision of the build

The `subvol8-db` subvolume was created as part of ADR-025's preparation work, but ADR-025 explicitly defers the migration of existing DBs pending 60 days of measurements. When `unifi-syslog` needed a write-hot storage home, the instinct was to either (a) wait for ADR-025 to resolve, or (b) drop the workload in `subvol7-containers` and carry migration debt.

Both were wrong answers. The right answer is that "place new greenfield workloads" and "migrate five live production DBs" are different decisions with different risk profiles. Greenfield placement has no migration step, no rollback artifact to protect, no service to restart carefully — it's a pure write of new data to a chosen location. The measurement-gated caution ADR-025 correctly insists on for existing DBs doesn't transfer.

Splitting the decision into ADR-027 took about 20 minutes and produced a cleaner invariant: new NOCOW-candidates go on `subvol8-db`, forward only. ADR-025 is untouched; its 2026-06-18 review date stands. Future tenants add a row to ADR-027's tenant table, not a new ADR.

**Lesson:** when a deferred ADR blocks an unrelated new decision, check whether the deferral's premises actually apply to the new case. Often they don't, and the right move is a companion ADR that carves out the narrower forward-looking question cleanly. Don't paper over the distinction by retrofitting the deferred ADR's scope — that loads its measurement gate with work it wasn't designed to arbitrate.

### Rootless Podman UDP NAT rewrites source IPs — rely on host-side filtering

UDM packets arrive at `unifi-syslog` with `src=10.89.7.69` (the container's gateway), not `192.168.1.1`. Rootless Podman's pasta networking NATs UDP sources, so any in-container source-based filtering (syslog-ng `netmask()`) is operating on rewritten addresses and is not a trust boundary. The authoritative trust boundary is the firewalld rich rule on the host — it runs before NAT, sees the real source, and rejects non-UDM packets at the earliest possible point.

This is why the syslog-ng config has no `netmask()` filter and the comment explicitly names firewalld as authoritative. Two layers that look similar are not always redundant — one of them is actually doing the work. Writing that down in the config file itself (not just the ADR) was worth the three extra lines; the next person editing this config shouldn't have to re-derive why the obvious filter is missing.

**Lesson:** in-container network filters are application-layer conveniences, not security controls, whenever the container runtime NATs its inputs. The rule lives at the runtime boundary (firewalld, nftables, or the provider network), not inside the container.

### Quadlet-generated units cannot be `enable`d

Tried `systemctl --user enable unifi-syslog.service` out of muscle memory; it failed with "Unit is transient or generated." The `[Install] WantedBy=default.target` block in the `.container` file handles auto-wiring at quadlet-generation time — the correct deploy sequence is `daemon-reload` + `start`, never `enable`. Well-documented in podman's docs, but a reflex to unlearn coming from non-quadlet systemd.

---

## Follow-ups

- **Prometheus alert:** "no UDM events in 10 min" — UDM Pro is a primary security signal; silent receiver failure is a real blind spot.
- **Grafana dashboard panel:** UDM event rate by `program` label, with IDS/IPS facility highlighted. Makes the "is the UDM actually talking to us" question a glance-level check.
- **Filter tuning after 24–48h of real traffic:** the bootstrap config writes everything to one file. Once real event patterns are visible in Loki, split noisy programs (DHCP renewals, link-state churn) from security-relevant ones (IDS matches, firewall drops) into separate destinations or separate log-level filters.
- **ADR-025 unchanged:** measurement window continues. The `chattr +C` EINVAL finding is a known unknown for the DB migration day, but not a blocker to resolve now.

---

## Scope note

This build touched the syslog ingestion pipeline only. Did not alter Traefik routing, did not open any new internet-facing ports, did not change the monitoring stack's existing scrape targets. The `subvol8-db` tenant count went from zero to one; ADR-027 documents the forward-placement policy so the second tenant can land without re-litigating the placement question.
