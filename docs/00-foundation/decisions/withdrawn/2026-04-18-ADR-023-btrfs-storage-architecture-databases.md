---
type: ADR
title: "ADR-023: BTRFS Storage Architecture for Database Workloads (WITHDRAWN)"
description: "Withdrawn ADR that bundled database dumps with a NOCOW migration; split after adversarial review into ADR-024 and ADR-025, preserved for historical record."
sensitivity: public
created: 2026-04-21
updated: 2026-04-21
---

# ADR-023: BTRFS Storage Architecture for Database Workloads (WITHDRAWN)

**Date:** 2026-04-18
**Status:** Withdrawn (2026-04-18) — never accepted, replaced after adversarial review
**Replaced by:** ADR-024 (dump-based backup) + ADR-025 (deferred NOCOW migration)
**Review:** `docs/99-reports/2026-04-18-design-review-ADR-023-btrfs-storage-architecture-databases.md`

## Why this was withdrawn

This ADR bundled two orthogonal changes — introducing application-level database dumps (strictly additive, low-risk) and migrating databases to a dedicated NOCOW subvolume (preemptive optimization, higher-risk) — into a single plan. Parallel reviews by `infrastructure-architect` and `arch-adversary` agreed that:

1. The dump-based backup change is valuable and should ship independently.
2. The NOCOW migration was premised on theoretical fragmentation symptoms that had not been measured on the live system. On a 30-container homelab with light load, the symptoms may be below any threshold that justifies migration risk.
3. Bundling the two forced the low-risk change to carry the risk profile of the higher-risk change.

The plan was split:

- **ADR-024:** Ships dump-based backup now. Databases stay where they are in `subvol7-containers`. Dumps land in `subvol7-containers/db-dumps/` and Urd protects them via the existing sheltered tier.
- **ADR-025:** Defines the NOCOW migration plan but marks it Deferred pending 60 days of baseline measurements (filefrag counts, query p99, snapshot send duration). If measurements justify, ADR-025 becomes Accepted; if not, it stays Deferred or is itself withdrawn.

The content below is preserved unchanged for historical record. Do not implement from this document — refer to ADR-024 and ADR-025.

---

## Original ADR content (preserved for historical record)

**Date:** 2026-04-18
**Status at withdrawal:** Proposed
**Original Supersedes:** None (extends the storage model implicit in ADR-009, ADR-019, ADR-020, ADR-021)

## Context

The homelab's BTRFS storage grew organically. Media, user documents, container configs, and database state all coexist inside `subvol7-containers`, which is snapshotted daily by Urd and sent incrementally to an external drive as the "sheltered" protection tier (ADR-021).

Recent investigation surfaced a structural flaw in this layout: **databases with NOCOW set (`chattr +C`) inside a snapshotted subvolume do not actually remain NOCOW.** The BTRFS extent tree forces copy-on-write on the first modification of any extent shared with a snapshot, regardless of the NOCOW flag on the file. The flag is preserved on newly allocated extents but the initial write after each snapshot allocates a new extent — effectively reinstating COW on the write-hot region of every database file, every day.

Symptoms this produces on our 4×4TB HDD pool:

1. **Fragmentation returns** despite NOCOW. Database files accumulate thousands of small extents over time, degrading sequential scan and checkpoint performance.
2. **Write amplification.** Every snapshot window causes the DB to re-COW hot pages on next write. On spinning rust with 100-200 random IOPS per drive, this is an order of magnitude more expensive than on SSD.
3. **`autodefrag` interaction.** The pool is mounted with `autodefrag,compress=zstd:1,commit=120`. Autodefrag does not touch genuinely NOCOW files, but the snapshot-induced COW pages become eligible, increasing background I/O pressure.
4. **Snapshot bloat.** Each daily snapshot pins the old extents until retention drops the snapshot. A 3.2G Prometheus TSDB with daily churn adds multi-GB to the pool's snapshot residency even though we never restore from a snapshot for these workloads.
5. **Inconsistent implementation.** Audit of the current state:
   - `postgresql-immich`: NOCOW not set (directory inherited, but unclear if child extents are NOCOW)
   - `nextcloud-db` (MariaDB 155M): **NOCOW not set** — fully COW'd
   - `gathio-db` (MongoDB 1.1M): NOCOW set (but defeated by snapshots)
   - `prometheus` (3.2G): NOCOW set (but defeated by snapshots)
   - `loki` (574M): **NOCOW not set** — fully COW'd

   Two critical databases have zero NOCOW protection, and the ones that do are partially defeated. This is not a working design.

### Hardware constraint

The NVMe (128GB) is 90% full with OS, `/home`, and user content. It cannot host database data without displacing existing workloads. All bulk storage must live on the 4×4TB HDD pool. Therefore the question is *how* to host databases on BTRFS-on-HDD correctly, not *whether* to move them off.

### Data ownership constraint

The BTRFS pool runs Single profile (no RAID). External backups to WD-18TB drives are the sole protection against disk failure (ADR-020). Any storage layout must preserve backup coverage for business-critical database state.

## Decision

Introduce a dedicated NOCOW subvolume for database workloads, excluded from the snapshot-based backup path, with application-level dumps providing backup coverage that Urd protects through the existing `subvol7-containers` path.

### 1. Create `subvol8-db`

```
/mnt/btrfs-pool/subvol8-db/    (NOCOW inherited, not in Urd)
├── postgresql-immich/
├── nextcloud-db/
├── gathio-db/
├── prometheus/
└── loki/
```

The subvolume has the NOCOW attribute set **before** any data lands inside it, so new files inherit NOCOW automatically. Compression is disabled via `btrfs property set /mnt/btrfs-pool/subvol8-db compression none` because every listed engine already compresses at the page/chunk layer; stacking zstd on top wastes CPU with no storage benefit.

### 2. Workload assignment

**Move to `subvol8-db` (NOCOW, not snapshotted):**

| Service | Engine | Size | Reason |
|---------|--------|------|--------|
| postgresql-immich | PostgreSQL 14 | ~2–10GB | Heavy random write, WAL churn, critical |
| nextcloud-db | MariaDB | 155M | InnoDB random write, metadata-heavy |
| gathio-db | MongoDB | 1.1M | WiredTiger write amplification |
| prometheus | TSDB | 3.2G | High-rate append, 15d compaction cycle |
| loki | TSDB | 574M | Per-chunk rewrites, compaction |

**Stays on `subvol7-containers` (COW, snapshotted):**

| Service | Reason |
|---------|--------|
| redis-immich, nextcloud-redis | RDB persistence is whole-file rewrite; AOF is append; snapshots retain recent state meaningfully |
| traefik-logs | Append-mostly, rotated independently |
| immich-ml-cache | Ephemeral, recomputable |
| jellyfin-config, navidrome, audiobookshelf | Small SQLite, low write rate — COW overhead negligible |

Redis is the borderline case. RDB's whole-file rewrite pattern does not trigger the fragmentation problem NOCOW solves, and its size is trivial. Keeping it in the snapshotted subvol preserves point-in-time recovery for authn session state.

### 3. Backup strategy: application-level dumps

Database backups shift from filesystem snapshots to **engine-native dumps**, written to a directory that *is* inside the snapshotted subvolume:

```
/mnt/btrfs-pool/subvol7-containers/db-dumps/
├── postgresql-immich/YYYY-MM-DD.dump.zst
├── nextcloud-db/YYYY-MM-DD.sql.zst
└── gathio-db/YYYY-MM-DD.archive.zst
```

A systemd user timer (`db-dump.timer`, `db-dump.service`) runs nightly at **01:30** (before Urd's 04:00 run, so the freshest dumps are included in the next external send).

Dump tooling per engine:

| Engine | Tool | Flags | Consistency |
|--------|------|-------|-------------|
| PostgreSQL | `pg_dump --format=custom` piped through `zstd` | `--blobs`, `--no-owner`, `--no-acl` | Application-consistent (MVCC) |
| MariaDB | `mariadb-dump --single-transaction --routines --events` | zstd pipe | Application-consistent (InnoDB snapshot) |
| MongoDB | `mongodump --archive --gzip` | — | Best-effort consistent (`--oplog` if needed) |
| Prometheus | Admin API TSDB snapshot + tar/zstd | `POST /api/v1/admin/tsdb/snapshot?skip_head=false` | Crash-consistent at snapshot time |

**Prometheus preservation rationale.** Prometheus history is load-bearing for the SLO framework, Grafana dashboards, and capacity-trend analysis. Losing it on disk failure is not acceptable.

The dump path uses Prometheus's built-in admin API (`/api/v1/admin/tsdb/snapshot`), which creates a hardlink-based snapshot of the TSDB inside `/prometheus/snapshots/<timestamp>/`. Since TSDB blocks are immutable once written, hardlinks produce a crash-consistent view with near-zero additional space until the next block compaction. The dump job then tars the snapshot directory through `zstd -T0 --long`, writes the result to `db-dumps/prometheus/`, and deletes the hardlink snapshot. Expected compressed size: ~1–2GB per dump given TSDB's internal gorilla encoding already limits zstd's additional ratio.

This requires adding `--web.enable-admin-api` to the Prometheus quadlet's `Exec=` line. The admin API is reachable only on the container network (no external exposure), so the risk surface is internal only.

Retention: **14 daily dumps kept locally**, older dumps pruned. Urd's `sheltered` tier on `subvol7-containers` preserves daily snapshots for 14 days plus graduated tiers out to ~5 months, so the effective dump history on the external drive extends well beyond 14 days.

Retention is a **separate concern** from Urd's snapshot retention. Urd controls how long DB *dumps* persist on the external drive (by virtue of snapshotting `subvol7-containers` which contains the dump directory). The local dump retention in `db-dumps/` is controlled by the dump job itself — this ADR proposes 14 dailies as a starting point; revisit after operational experience.

### 4. TSDB handling: Prometheus dumped, Loki accepts loss

Both TSDBs live in `subvol8-db` for the performance benefits (NOCOW + no snapshots). They differ in backup treatment:

- **Prometheus** is dumped nightly via the admin API snapshot path described in §3. The SLO framework, Grafana dashboards, and autonomous-operations decision loops all depend on metric history; loss would degrade operational awareness for weeks as the 15d retention refills.
- **Loki** is **not dumped.** On total loss, the historical log index is gone but `promtail` resumes ingestion from the journal tail and new container logs, and the homelab's log retention needs are shorter than Prometheus's metric needs. Logs also exist in the journald source, which is not protected by this ADR but is at least a second copy. If Loki loss becomes operationally painful, extending the dump job to include Loki's store via filesystem rsync-of-stopped-service is a reasonable follow-up — flagged in Open Questions.

### 5. DB-level checksums replace BTRFS checksums

NOCOW disables BTRFS data checksums. Each engine must carry its own integrity checking:

- **PostgreSQL:** enable `data_checksums` — requires `initdb --data-checksums`. The Immich migration is an opportunity to re-initdb the cluster with checksums on (previously off). Verified via `pg_checksums --check` after migration.
- **MariaDB/InnoDB:** `innodb_checksum_algorithm=crc32` is default on MariaDB 10.5+. Already in effect.
- **MongoDB/WiredTiger:** page-level checksums enabled by default.
- **Prometheus:** TSDB block format has per-chunk CRC32. Head segment replay detects corruption.
- **Loki:** per-chunk checksums in the store schema.

### 6. Urd integration

`subvol8-db` is **not** added to Urd's subvolume list. Urd never snapshots it, never sends it externally, never alerts on its absence.

Instead, a new Prometheus textfile metric file written by the dump job integrates into the existing observability path:

```
~/containers/data/backup-metrics/db-dumps.prom
```

Metrics (mirroring Urd's naming):

| Metric | Type | Labels | Consumer |
|--------|------|--------|----------|
| `db_dump_success` | gauge | `db` | `DBDumpFailed` alert (== 0) |
| `db_dump_last_success_timestamp` | gauge | `db` | `DBDumpStale` alert (age > 26h) |
| `db_dump_duration_seconds` | gauge | `db` | Trend monitoring |
| `db_dump_size_bytes` | gauge | `db` | `DBDumpSizeAnomaly` alert (50% delta) |
| `db_dump_last_run_timestamp` | gauge | — | `DBDumpJobNotRunning` alert (age > 2d) |

The metric file sits in the same directory as Urd's `backup.prom` and is collected by the same `node_exporter` textfile mount — no new container wiring required.

### 7. Mount options unchanged

The global `/mnt` mount retains `compress=zstd:1,space_cache=v2,autodefrag,commit=120,noatime`. Rationale:

- **autodefrag:** remains valuable for COW'd subvolumes on HDD. NOCOW files are immune regardless.
- **compress=zstd:1:** beneficial for docs/pics/multimedia. Overridden to `none` on subvol8-db via BTRFS property.
- **commit=120:** preserves write batching benefits. DB engines fsync independently when they need durability.

## Architecture

```
/mnt/btrfs-pool/                          [4×4TB HDD, Single profile, autodefrag, zstd:1]
├── subvol1-docs                          [COW, snapshot, Urd sheltered]
├── subvol2-pics                          [COW, snapshot, Urd fortified]
├── subvol3-opptak                        [COW, snapshot, Urd fortified]
├── subvol4-multimedia                    [COW, snapshot, Urd recorded]
├── subvol5-music                         [COW, snapshot, Urd sheltered]
├── subvol6-tmp                           [COW, snapshot, Urd custom]
├── subvol7-containers                    [COW, snapshot, Urd sheltered]
│   ├── (existing container data)
│   └── db-dumps/                         [NEW — nightly DB dumps land here]
└── subvol8-db (NEW)                      [NOCOW, compression=none, NOT in Urd]
    ├── postgresql-immich/
    ├── nextcloud-db/
    ├── gathio-db/
    ├── prometheus/
    └── loki/
```

Backup flow for DB data:
```
01:30 — db-dump.service runs
         pg_dump | zstd       → subvol7-containers/db-dumps/postgresql-immich/
         mariadb-dump…        → subvol7-containers/db-dumps/nextcloud-db/
         mongodump            → subvol7-containers/db-dumps/gathio-db/
         Prom admin-API + tar → subvol7-containers/db-dumps/prometheus/
         (loki: no dump)
         Writes db-dumps.prom metrics
04:00 — urd-backup.service runs
         Snapshots subvol7-containers (includes fresh dumps)
         Incremental send to WD-18TB
```

## Migration Plan

Per-service migration, ordered by risk (smallest DB first to build confidence):

### Phase 0 — Infrastructure (no service impact)

1. `btrfs subvolume create /mnt/btrfs-pool/subvol8-db`
2. `chattr +C /mnt/btrfs-pool/subvol8-db` (inherited by new files/dirs)
3. `btrfs property set /mnt/btrfs-pool/subvol8-db compression none`
4. Set ownership per ADR-019: `patriark:patriark 0755`, ACLs added per-service as needed
5. Create `/mnt/btrfs-pool/subvol7-containers/db-dumps/` with per-service subdirs
6. Deploy `scripts/db-dump.sh` + systemd user units (`db-dump.service`, `db-dump.timer`)
7. Run dump job manually against current (pre-migration) DBs to validate tooling and verify dumps restore cleanly in a sandbox

### Phase 1 — Per-service migration

For each service (suggested order: gathio-db → nextcloud-db → loki → prometheus → postgresql-immich):

**Prometheus extra step:** add `--web.enable-admin-api` to the `Exec=` line in `quadlets/prometheus.container` as part of the migration PR. The flag must be live before the first dump run succeeds.


1. `systemctl --user stop <service>.service` (and any dependent services)
2. Take a final engine-native dump — this is the fallback if the move goes wrong
3. For DB engines that benefit from a fresh initdb (PostgreSQL): initdb new cluster in `subvol8-db/<service>/` with `--data-checksums`, restore from dump
4. For engines that don't: `rsync -aHX --numeric-ids` from old path to new path. **Must not use `cp --reflink`** — reflink preserves extent sharing and defeats NOCOW. Verify with `lsattr` after move that files show `C` flag.
5. Update the quadlet file's `Volume=` line to point at the new path
6. `systemctl --user daemon-reload && systemctl --user start <service>.service`
7. Verify service health (ADR-010 validation): HTTP/TCP probe, container logs clean, dependent services healthy
8. Rename old directory to `<service>.pre-migration` — retained for 14 days as rollback safety net
9. After 14 days clean operation, delete the `.pre-migration` directory

### Phase 2 — Observability

1. Deploy `config/prometheus/alerts/db-dump-alerts.yml` with the four alerts listed above
2. Add Grafana panel: "DB Dump Health" — age of last success per DB, size trend
3. Update `docs/20-operations/runbooks/` with per-engine restore runbook (part of the DR runbook set)

### Phase 3 — Cleanup

1. Remove now-empty DB directories from `subvol7-containers`
2. Verify Urd's next run reflects reduced `subvol7-containers` churn (snapshot delta should shrink noticeably)
3. Update `AUTO-NETWORK-TOPOLOGY.md` and `AUTO-SERVICE-CATALOG.md` regeneration inputs so paths reflect new layout
4. Update `CLAUDE.md` "Common Gotchas" — replace the "BTRFS NOCOW for databases" note with a pointer to this ADR

## Consequences

### Positive

- **NOCOW actually works.** No snapshot interference; write-in-place on HDD for DB workloads, substantially reducing fragmentation and write amplification.
- **Consistent backup model.** All DBs protected by application-consistent dumps, not crash-consistent snapshots. Restore is a well-understood operation for every engine.
- **Simpler capacity accounting.** `subvol7-containers` snapshot deltas shrink when DB churn is removed. External drive fills slower; incremental send times drop.
- **Urd unchanged.** No new subvolumes for Urd to manage, no new retention policies, no new drive requirements. The integration contract in ADR-021 stays intact.
- **Checksums upgraded.** Moving to `data_checksums=on` in PostgreSQL is a standing hygiene improvement that the migration makes free.
- **TSDB hygiene.** Loki stops consuming backup I/O for data that has low recovery value. Prometheus shifts to a cheaper, application-consistent snapshot path (admin API) instead of the current filesystem-snapshot-of-COW-data approach.

### Negative

- **Loss of point-in-time rollback for DBs.** If a bad Immich migration corrupts the DB, the restore path is "yesterday's dump," not "reset to 10 minutes ago via snapshot." Mitigated by: snapshot-based rollback of a running DB was never actually safe (crash-consistent at best); dumps are application-consistent and tested.
- **Dump job is a new failure surface.** If the dump job stops running, data is at risk silently. Mitigated by: `DBDumpJobNotRunning` and `DBDumpStale` alerts, plus the `db-dump-alerts.yml` file is short and auditable.
- **Migration requires downtime per service.** Each move stops the service for minutes to (for Immich) potentially up to an hour depending on dump/restore time. Scheduled during low-use windows.
- **No BTRFS data checksums on DB files.** We delegate to engine-level checksums. If an engine's checksum coverage has gaps (unlikely), silent corruption could reach us. Mitigated by: all five engines have production-grade integrity checking.

### Constraints

- **Dump size is bounded by `subvol7-containers` free space.** 14 daily compressed dumps of current DBs ≈ 2–10GB total. Plenty of headroom.
- **`rsync` during migration must avoid `--inplace` and reflink.** The move procedure must produce genuinely new extents in the NOCOW directory; any shortcut that preserves reflinks defeats NOCOW silently.
- **Restore procedure must be tested.** Each engine's restore path is documented and exercised as part of the existing `backup-restore-test.timer` infrastructure (extended to cover DB dumps).

## Alternatives Considered

**1. Move DBs to NVMe.** Rejected — NVMe is 90% full with 13GB free. DB growth (especially Immich as photo library grows) would quickly exhaust it. Would also concentrate failure risk on a single drive with no RAID.

**2. Keep current layout, fix NOCOW flags.** Rejected — does not solve the snapshot-forces-COW problem. Sets NOCOW correctly but snapshots still defeat it on the first write after each snapshot. This is the design flaw, not the flag application.

**3. Disable snapshots on `subvol7-containers`.** Rejected — container configs genuinely benefit from snapshot-based rollback (bad quadlet edit, bad config change). The cure is worse than the disease.

**4. Nested subvolume for DBs inside subvol7-containers.** Rejected — snapshots of a parent subvolume do not include nested subvolumes, which would technically work. But this creates an invisible-to-casual-inspection structure: an operator looking at `subvol7-containers` snapshots would not realize DBs are missing from them. Top-level `subvol8-db` is more honest.

**5. Filesystem freeze + snapshot for DBs.** Rejected — requires `fsfreeze` + coordinated `pg_start_backup`/`pg_stop_backup` (or equivalent per engine) around every snapshot. Operationally complex; doesn't solve the fragmentation problem; snapshots still exist.

**6. Move TSDBs out of BTRFS entirely (e.g., xfs partition).** Rejected — no spare disk partition is available and repartitioning the pool to steal capacity is disproportionate work for a derived-data workload.

## Open Questions

1. **Does Immich PG currently have `data_checksums=on`?** Needs verification before migration. If yes, rsync-based move is acceptable; if no, initdb+restore is the correct path.
2. **Should `/home` DBs (authelia SQLite, grafana) be included?** `/home` is not in Urd. These DBs are small and rarely written, but they lack backup coverage today. Out of scope for this ADR but flagged as a follow-up.
3. **Does `db-dump.service` need user or system scope?** User scope aligns with Urd (`systemctl --user`). System scope would simplify permissions for services running as other UIDs. Defaulting to user scope unless a blocker emerges during implementation.
4. **Loki dump on second pass?** If operational experience shows Loki loss is painful (e.g., log-based alerts missing context after a restore), extend the dump job with a stop-rsync-start cycle or investigate Loki's boltdb-shipper flush-on-demand. Accept loss initially; revisit after 90 days of operation.
5. **Local dump retention — 14 days right?** 14 dailies × ~2GB Prometheus dominant = ~30GB local footprint. Comfortable for current pool state, but Prometheus churn may grow as metric cardinality grows. Monitor `db_dump_size_bytes` trend; revise retention downward if local footprint exceeds 50GB.

## Related

- **ADR-009:** Config vs Data Directory Strategy — establishes the host path layout this ADR refines
- **ADR-019:** Filesystem Permission Model — ACL approach applies to new subvolume
- **ADR-020:** Daily External Backups — tiered protection model; `subvol7-containers` carries DB dumps
- **ADR-021:** Urd Backup Tool — integration contract; `subvol8-db` is deliberately outside it
- **Urd project:** `~/projects/urd/` — backup engine, unchanged by this ADR
- **`docs/20-operations/runbooks/`:** DR runbooks — extend with DB restore procedures
- **`CLAUDE.md` Common Gotchas:** "BTRFS NOCOW for databases" — updated to reference this ADR after implementation

## Keeping This ADR Current

This ADR describes a storage *architecture*, not a point-in-time migration. It should be updated when:

1. A new database service is added to the homelab (decide: `subvol8-db` or `subvol7-containers`?)
2. The dump job's metric names, paths, or schedule change
3. Engine-level checksum settings change (e.g., new PostgreSQL major version with different defaults)
4. Urd's integration contract changes in ways that affect DB dump coverage
5. Hardware changes make NVMe hosting of DBs feasible (re-evaluate)
