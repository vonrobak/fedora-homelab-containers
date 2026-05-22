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
| **2 — Dump** | **NOCOW, excluded from snapshots** | application-consistent logical dump → lands in Tier 1 → rides Urd offsite | PostgreSQL (immich, forgejo), MariaDB (nextcloud), MongoDB (gathio), Prometheus, Loki (`subvol8-db`) |
| **3 — Discard** | NOCOW, excluded, no backup | regenerable | *(currently empty)* |

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
| Loki | `loki` | `podman pause` + `podman cp` + unpause |

Backup coverage is observable: `db-dumps.prom` (node_exporter textfile) → `db_dump_*` series → `config/prometheus/alerts/db-dump-alerts.yml`. `scripts/db-restore-test.sh` (weekly, Sun 05:00) restores each latest dump into an ephemeral matching-version container and validates object counts (`db_restore_test_*` series).

### Implementation notes (discovered by testing — the non-obvious bits)

- **Metric label is `database`, not `service`.** The node_exporter scrape job sets a static `service="node_exporter"` target label that clobbers any `service` label on textfile metrics (`honor_labels: false`). Urd uses `subvolume`, dependency-metrics use `homelab_service`, for the same reason. **Any textfile metric must avoid the bare `service` label.**
- **Loki = `podman pause` + `podman cp`.** Loki is distroless (no shell/tar to exec) with 70k+ constantly-rotating files. Rejected: stop-rsync-start (~17 min downtime + WAL-rotation race), host-side tar (permission-denied on mode-600 WAL checkpoint files + slow), live `podman cp` (races on file rotation under load). Quadlet containers are *removed* on stop, so cp needs the container running or paused. `podman pause` (SIGSTOP) freezes the filesystem → consistent, complete copy in ~40 s; Promtail buffers during the freeze (Loki is regenerable, not a source of truth).
- **Nextcloud MariaDB root is locked down** (no password, no socket auth). The dump uses the app account `MYSQL_USER`/`MYSQL_PASSWORD`, which has `ALL` on its own database — the entire contents of that instance.
- **Secrets never leave the container.** Each dump runs *inside* the running container where the engine password already exists as env; nothing is passed as a host process arg or stored in the repo. Robust to the ADR-028 secret-store path split.
- **`zstd -f` is required** (a failed run leaves an empty `.tmp` that would otherwise block the next run).
- **Vaultwarden dump deferred.** Its image lacks `sqlite3` and the SQLite file is owned by a container subuid in the rootless namespace; a clean logical dump needs a sidecar-image decision. Vaultwarden is Tier-1 snapshot-protected meanwhile.

## Phase B — Offline migration into subvol8-db (DEFERRED / gated)

Move the four engines still in `subvol7` (`postgresql-immich`, `nextcloud-db/data`, `gathio-db`, `prometheus`) into `subvol8-db` (forgejo-db + loki are already there). **Gate:** the dump backbone must have a track record of passing restore tests first (it now exists); revisit with a `filefrag` baseline per ADR-025's criteria.

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
| loki | TSDB / logs | yes | `podman pause`+`cp` tar (Phase A) |
| ~~unifi-syslog~~ | append-only syslog | — | **moving to Tier 1** (subvol7, snapshot+offsite) — overrides ADR-027's placement; append-only forensic logs belong in the snapshot tier and the COW cost is negligible |
| *(Phase B)* postgresql-immich, nextcloud-db, gathio-db, prometheus | server engines | yes | dumps (Phase A) + offline migration (Phase B) |

New tenants follow the growth rule; update this table rather than writing a new ADR (unless the tier policy itself changes).

## Consequences

**Positive:** every database now has an application-consistent, offsite, restore-tested backup; the forgejo-db and loki holes are closed; NOCOW will actually work once Phase B completes; the architecture has a single durable growth rule.

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
