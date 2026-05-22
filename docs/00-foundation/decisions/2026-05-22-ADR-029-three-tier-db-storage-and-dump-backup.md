# ADR-029: Three-Tier Database Storage + Dump Backup

**Date:** 2026-05-22
**Status:** Accepted (Phase A implemented); Phase B deferred/gated
**Supersedes:** ADR-024 (dump-based backup), ADR-025 (deferred DB migration), ADR-027 (forward-only NOCOW placement)
**Plan:** worked out 2026-05-22 (debate → plan → implementation)

## Context

The homelab's database storage was governed by three overlapping ADRs that had drifted from ground truth:

- **ADR-024** (dump-based backup) was *accepted but never built*.
- **ADR-027** (forward-only NOCOW placement) put new write-hot engines on `subvol8-db` and required DB tenants to be backed up "via ADR-024 dumps" — but those dumps didn't exist.
- **ADR-025** (migrate the five existing DBs to `subvol8-db`) was deferred pending measurements.

The net effect was a **live backup hole**: `forgejo-db` (PostgreSQL) and `loki` sat in the un-snapshotted `subvol8-db` with **no backup of any kind**. Meanwhile `gathio-db` and `prometheus` carried `chattr +C` (NOCOW) *inside the snapshotted `subvol7-containers`* — the COW-defeated-by-snapshots antipattern, live.

This ADR consolidates the three into one coherent architecture, ships the missing backbone, and records the runbook for the gated migration.

**Storage ground truth:** `htpc-btrfs-pool` is a 4-device BTRFS pool (`/dev/sd{a,b,c,d}`, 3.64 TiB each), Single data profile (no RAID). Offsite Urd sends to WD-18TB drives are the sole redundancy against disk failure.

## Decision

### Organize storage by *recovery model*, not data type

Every byte lands in a tier whose BTRFS treatment matches how it would actually be recovered:

| Tier | BTRFS treatment | Backup mechanism | Members |
|------|-----------------|------------------|---------|
| **1 — Snapshot** | COW, Urd snapshot, sent offsite | btrfs snapshot + `btrfs send` | user data, configs, app state, **SQLite DBs, Redis** (subvol1–7, /home) |
| **2 — Dump** | **NOCOW, excluded from snapshots** | application-consistent logical dump → lands in Tier 1 → rides Urd offsite | PostgreSQL (immich, forgejo), MariaDB (nextcloud), MongoDB (gathio), Prometheus (`subvol8-db`); SQLite (vaultwarden) dumped but stays Tier 1 |
| **3 — Discard** | NOCOW, excluded, no backup | regenerable | **Loki** (`subvol8-db`) — see implementation note |

NOCOW only behaves as NOCOW **because Tier 2 is excluded from snapshots** — with no snapshot to share extents, there is no copy-on-first-write, so fragmentation cannot accumulate. Live DB files get write-in-place performance on spinning disks; the *backup artifact* is a small, compressed, application-consistent, version-portable dump that is COW-snapshotted and replicated offsite. Performance and recoverability are decoupled and each is optimal.

### The tier boundary: own-checksums + native dump tool

NOCOW disables BTRFS data checksums, so it is only safe for engines that carry **their own** integrity checking — PostgreSQL (`data_checksums`), MariaDB/InnoDB (crc32), MongoDB/WiredTiger, Prometheus/Loki (per-chunk CRC32). **SQLite and Redis do not** self-checksum by default; under NOCOW they would lose their only integrity guarantee for zero fragmentation benefit (both are small / whole-file-rewrite / append patterns), and Vaultwarden would lose useful snapshot rollback. They stay in Tier 1.

**Growth rule (one yes/no, for every future service):** *Does it run as its own engine with native page/chunk checksums and a native dump tool? → Tier 2 (`subvol8-db`) + add to the dump job. Otherwise (SQLite, Redis) → Tier 1 with its app.* (This is ADR-027's NOCOW-candidate criteria, restated as the durable rule.)

## Phase A — Dump backbone (IMPLEMENTED 2026-05-22)

`scripts/db-dump.sh` (nightly via `db-dump.timer` @ 01:30, before Urd's 04:00) dumps every Tier-2 engine to `subvol7-containers/db-dumps/<svc>/YYYY-MM-DD.<ext>.zst`, which Urd already snapshots and sends offsite. Per-engine failure isolation; idempotent per day; per-engine retention.

| Engine | Container | Method |
|--------|-----------|--------|
| Immich PG | `postgresql-immich` | `pg_dump --format=custom --compress=0` |
| Forgejo PG | `forgejo-db` | `pg_dump --format=custom --compress=0` |
| Nextcloud | `nextcloud-db` | `mariadb-dump --single-transaction` as the **app user** (root is locked down) |
| Gathio | `gathio-db` | `mongodump --archive` |
| Prometheus | `prometheus` | admin-API `tsdb/snapshot` + tar (retention 7, dump ≈1.5 GB) |
| Vaultwarden | `vaultwarden` | host `sqlite3 .backup` (online) + `PRAGMA integrity_check` (stays Tier 1; dump is a bonus) |

Backup coverage is observable: `db-dumps.prom` (node_exporter textfile) → `db_dump_*` series → `config/prometheus/alerts/db-dump-alerts.yml`. `scripts/db-restore-test.sh` (weekly, Sun 05:00) restores each latest dump into an ephemeral matching-version container and validates object counts (`db_restore_test_*` series).

### Implementation notes (discovered by testing — the non-obvious bits)

- **Metric label is `database`, not `service`.** The node_exporter scrape job sets a static `service="node_exporter"` target label that clobbers any `service` label on textfile metrics (`honor_labels: false`). Urd uses `subvolume`, dependency-metrics use `homelab_service`, for the same reason. **Any textfile metric must avoid the bare `service` label.**
- **Loki is Tier 3 (not dumped).** It was briefly dumped via `podman pause` + `podman cp` (distroless image → can't exec tar; quadlet containers are *removed* on stop → can't cp a stopped one; host-side tar hits mode-600 WAL perms; live cp races on rotation). But a nightly dump **froze loki ~15 min** on a cold cache — 70k small files read seek-bound from HDD after Prometheus's 1.5 GB dump evicts the page cache (the warm-cache "~40 s" was a fluke). For regenerable log data (Promtail re-ingests; the originating systems are the source of truth) that trade isn't worth it, so loki is excluded from backup. If ever wanted, a weekly cadence would amortize the freeze.
- **Nextcloud MariaDB root is locked down** (no password, no socket auth). The dump uses the app account `MYSQL_USER`/`MYSQL_PASSWORD`, which has `ALL` on its own database — the entire contents of that instance.
- **Secrets never leave the container.** Each dump runs *inside* the running container where the engine password already exists as env; nothing is passed as a host process arg or stored in the repo. Robust to the ADR-028 secret-store path split.
- **`zstd -f` is required** (a failed run leaves an empty `.tmp` that would otherwise block the next run).
- **Vaultwarden: host `sqlite3 .backup` (no sidecar needed).** Initially assumed to need a sidecar (no `sqlite3` in the image). Ground truth corrected it: the SQLite is host-owned (uid 1000, mode 644) and the host has `sqlite3`, so an online `.backup` (backup API — safe alongside the live writer) + `PRAGMA integrity_check` gives an application-consistent copy with no container involvement. Vaultwarden stays Tier 1 (snapshotted); the dump is an extra offsite, restore-tested safety net for the most security-critical store. *Lesson: re-check the assumption before engineering around it.*

## Phase B — Offline migration into subvol8-db (DEFERRED / gated)

Move the four engines still in `subvol7` (`postgresql-immich`, `nextcloud-db/data`, `gathio-db`, `prometheus`) into `subvol8-db` (forgejo-db + loki are already there). **Gate:** (a) restore-test track record (the job now exists — let it run a few Sundays); (b) **measurement — DONE 2026-05-22, justifies migration:** subvol7 DBs show heavy COW-in-snapshot fragmentation (nextcloud `oc_filecache.ibd` = 11,777 extents; gathio max 2,362; immich PG mean 6.3 / max 1,862) vs the subvol8 NOCOW reference (forgejo PG mean 0.9 / max 8, loki mean 1.0) — a near-controlled same-engine comparison (immich vs forgejo PostgreSQL). Baseline saved under `data/backup-logs/`, regenerate via `scripts/filefrag-baseline.sh`; (c) build `scripts/migrate-db-to-subvol8.sh` first.

**The unlock — the clean offline window:** run `scripts/update-before-reboot.sh`, which calls `graceful-shutdown.sh`. With every container cleanly stopped, on-disk DB state is *cleanly consistent*, so the move is a plain offline `rsync` — not a live migration. This collapses the risk surface of the original ADR-025 plan (no initdb-in-container, no Prometheus observability-gap choreography).

Per service, with all containers stopped:
1. `mkdir` the empty target; **`chattr -m` then `chattr +C`** — the `m` (no-compress) flag inherited from the `compression=none` subvol root is mutually exclusive with `+C`, so a bare `chattr +C` returns EINVAL (ADR-027's documented workaround).
2. `rsync -aHX --numeric-ids <src>/ <target>/` — **no `--reflink`, no `--inplace`** (reflink shares extents and silently defeats NOCOW).
3. Assert `lsattr -d` shows `C` and `filefrag -v` shows no shared extents.
4. Two-layer ACLs (ADR-019): parent-traversal `--x` for each container subuid + per-service `rwx` + default ACL.
5. Update the quadlet `Volume=`, `daemon-reload`, start, healthcheck — **including the ADR-028 secret-mount check** (`podman run --rm --secret <name> alpine true`).
6. PostgreSQL: verify checksums with `pg_controldata` (the quadlet sets `--data-checksums`, likely already on); only enable in place if off.
7. Keep `<svc>.pre-migration-<DATE>` for 14 days. Per-service reversible (revert `Volume=`, restart); worst case restore from the prior night's dump.

A defensive tool (`scripts/migrate-db-to-subvol8.sh`, dry-run default, `--execute` gate, rollback subcommand, hard-enforced no-reflink + post-copy NOCOW assertions) is to be built before Phase B executes.

## subvol8-db tenant table (absorbed from ADR-027)

| Tenant | Workload | NOCOW | Backup |
|--------|----------|-------|--------|
| forgejo-db | PostgreSQL | yes | `pg_dump` (Phase A) |
| loki | TSDB / logs | yes | **none — Tier 3, regenerable** (nightly dump froze it ~15 min on cold cache; dropped) |
| ~~unifi-syslog~~ | append-only syslog | — | **moved to Tier 1** (subvol7, snapshot+offsite) — overrides ADR-027's placement; append-only forensic logs belong in the snapshot tier and the COW cost is negligible |
| *(Phase B)* postgresql-immich, nextcloud-db, gathio-db, prometheus | server engines | yes | dumps (Phase A) + offline migration (Phase B) |

New tenants follow the growth rule; update this table rather than writing a new ADR (unless the tier policy itself changes).

## Consequences

**Positive:** every database (PostgreSQL, MariaDB, MongoDB, Prometheus, plus vaultwarden SQLite) now has an application-consistent, offsite, restore-tested backup; the forgejo-db hole is closed (loki is reclassified Tier 3 — regenerable, accepted no-backup); NOCOW will actually work once Phase B completes; the architecture has a single durable growth rule.

**Negative / accepted:** Prometheus dumps are full TSDB snapshots (~1.5 GB/night, no dedup) — local retention is shortened to 7 and offsite growth is governed by Urd's subvol7 retention; a future option is dumping Prometheus weekly rather than daily. `--web.enable-admin-api` exposes destructive TSDB endpoints to the unauthenticated monitoring network (accepted; external path is Authelia-fronted; only the snapshot endpoint is used). Live DB files in `subvol8-db` have no filesystem-snapshot rollback — recovery is via dumps, which is the intended model.

## Follow-ups

- Move `unifi-syslog` → subvol7 (quadlet + `config/logrotate/unifi-syslog` + verify promtail path).
- `filefrag` baseline before deciding Phase B.
- Vaultwarden sidecar dump.
- Build `scripts/migrate-db-to-subvol8.sh` before Phase B.

## Related

- **ADR-024 / ADR-025 / ADR-027** — superseded by this ADR (content consolidated above).
- **ADR-019** filesystem permission model (two-layer ACLs) · **ADR-021** Urd integration · **ADR-028** secret-store path split.
- Implementation: `scripts/db-dump.sh`, `scripts/db-restore-test.sh`, `systemd/db-dump.*`, `systemd/db-restore-test.*`, `config/prometheus/alerts/db-dump-alerts.yml`.
