---
type: ADR
title: "ADR-024: Application-Level Database Dump Backup"
description: "ADR (superseded by ADR-029) adding a nightly application-consistent database dump job for the stateful DB engines, without moving any data."
sensitivity: public
created: 2026-04-21
updated: 2026-05-22
---

# ADR-024: Application-Level Database Dump Backup

**Date:** 2026-04-18
**Status:** Superseded by ADR-029 (2026-05-22) — dump backbone implemented there
**Replaces (part 1 of 2):** ADR-023 (withdrawn)
**Companion:** ADR-025 (deferred NOCOW migration)

## Context

The homelab runs five stateful database engines inside `subvol7-containers`, which is snapshotted daily by Urd and sent incrementally to an external drive as the "sheltered" protection tier (ADR-021):

- **postgresql-immich** (PostgreSQL 14) — Immich photo metadata, ~2–10GB
- **nextcloud-db** (MariaDB) — file sync metadata, 155M
- **gathio-db** (MongoDB) — event data, 1.1M
- **prometheus** (TSDB) — metric history, 3.2G
- **loki** (TSDB) — log history, 574M

Current backup coverage is **snapshot-only**. Each nightly Urd run captures a BTRFS snapshot of `subvol7-containers` and sends the delta externally. Snapshots of a running database are crash-consistent at best. In principle this is recoverable (WAL replay, InnoDB crash recovery, etc.), but three practical gaps exist:

1. **No tested restore path.** Snapshots are taken nightly but restoring a single DB from a snapshot has never been exercised. In a real incident, the procedure would be improvised under pressure.
2. **No application-consistent backup.** For Postgres and MariaDB, application-consistent dumps have strictly higher integrity guarantees than crash-consistent filesystem snapshots — especially for large, busy databases.
3. **Prometheus history is load-bearing for the SLO framework and autonomous-operations decisions.** Loss of metric history would degrade operational awareness for the full 15d retention window. The current snapshot path protects the TSDB files but has the same crash-consistency caveats.

Snapshots will continue to exist and will continue to provide bulk recovery for config, logs, and non-DB container state. What's missing is an *application-consistent* layer for the DBs themselves.

This ADR adds that layer without moving any data. Storage layout optimization (NOCOW subvolume migration) is a separate concern addressed in ADR-025 and is explicitly out of scope here.

## Decision

Introduce a nightly database dump job that produces application-consistent backups for each stateful DB, writes them to `subvol7-containers/db-dumps/`, and is automatically protected by Urd via the existing `subvol7-containers` sheltered tier. Databases remain where they are — no storage migration.

### 1. Dump targets and tooling

A systemd user timer (`db-dump.timer`, `db-dump.service`) runs nightly at **01:30** — before Urd's 04:00 run so fresh dumps are included in the next external send.

| Engine | Service | Tool | Flags | Consistency |
|--------|---------|------|-------|-------------|
| PostgreSQL 14 | postgresql-immich | `pg_dump --format=custom` via container exec | `--no-owner --no-acl` piped through `zstd -T0` | Application-consistent (MVCC) |
| MariaDB | nextcloud-db | `mariadb-dump --single-transaction --routines --events` | zstd pipe | Application-consistent (InnoDB snapshot); assumes InnoDB-only schema (true for Nextcloud core) |
| MongoDB | gathio-db | `mongodump --archive` via container exec | Separate `zstd` step (avoid `--gzip` corrupt-edge-case on older builds) | Best-effort consistent (`--oplog` not needed for single-node) |
| Prometheus TSDB | prometheus | Admin API `POST /api/v1/admin/tsdb/snapshot?skip_head=false` + `tar \| zstd` | — | Crash-consistent at snapshot time, head captured |
| Loki TSDB | loki | Stop–rsync–start cycle (no snapshot API in single-binary mode) | zstd compress on final tarball | Application-consistent (stopped) |

**Notes from review:**

- `pg_dump --blobs` is deprecated in PG16 and redundant with `--format=custom`. Not used.
- `mongodump --archive --gzip` has corrupt-output edge cases on older builds; we split `mongodump --archive` from `zstd` to avoid.
- Loki is **included** in the dump pipeline — reversing the original plan to exclude it. Rationale: losing Loki history costs the ability to post-mortem the dump job itself if anything goes wrong. Cost of inclusion is low (~574M compressed, brief outage window during stop-rsync-start).

### 2. Output layout

```
/mnt/btrfs-pool/subvol7-containers/db-dumps/
├── postgresql-immich/YYYY-MM-DD.dump.zst
├── nextcloud-db/YYYY-MM-DD.sql.zst
├── gathio-db/YYYY-MM-DD.archive.zst
├── prometheus/YYYY-MM-DD.tar.zst
└── loki/YYYY-MM-DD.tar.zst
```

### 3. Retention

Local: **14 daily dumps kept per service.** Older dumps pruned by the dump job itself.

External: controlled entirely by Urd's existing `sheltered` tier on `subvol7-containers` — daily snapshots for 14 days, weekly/monthly thinning beyond that. The dump job does not coordinate with Urd; dumps are just files inside a subvolume Urd already protects.

Revisit retention if local footprint exceeds ~50GB (expected peak: ~30GB, dominated by Prometheus).

### 4. Prometheus admin API

Prometheus needs `--web.enable-admin-api` to expose the TSDB snapshot endpoint. This is a **Phase 0 precondition**, not a later step. The admin API adds endpoints that can delete metric data; before enabling, verify:

- Prometheus is not reachable over the network without Traefik in front (it is not — routing audit confirms the `reverse_proxy` network path is the only ingress, and the admin endpoint would be exposed through the standard router).
- The Traefik router for Prometheus applies the same Authelia middleware as other internal services.
- If the admin API needs stricter gating than the UI, add a path-specific middleware or bind the admin API to a separate listener.

Acceptable gate for this ADR: the admin API is reachable only by authenticated users through Traefik, matching the existing Prometheus UI access model. If audit reveals gaps, they are fixed before the flag is enabled.

### 5. Prometheus snapshot cleanup

The admin API creates `/prometheus/data/snapshots/<name>/` via hardlinks. Orphaned snapshot directories pin TSDB blocks and prevent compaction reclaim.

The dump job's Prometheus handler runs a defensive pre-clean:

```
rm -rf /prometheus/data/snapshots/*   # via container exec, older than 1h
```

Then creates the new snapshot, tars it, and deletes it. This makes the cleanup idempotent — a crashed previous run cannot accumulate orphans forever.

### 6. Restore testing

Restore testing is not optional. A dump nobody has restored is a dump you don't have.

`backup-restore-test.timer` is extended with a new test pass:

- **Weekly cadence** (Sunday 03:00, after the Saturday dumps).
- **Per-engine ephemeral restore:** spin up a throwaway container from the same image, restore the most recent dump, run engine-specific validation:
  - PostgreSQL: `pg_controldata`, row count against a known-stable table, `pg_checksums --check`
  - MariaDB: row count against a known-stable table, `CHECK TABLE` on a sample
  - MongoDB: collection count, sample query
  - Prometheus: `promtool tsdb analyze` on restored blocks
  - Loki: `loki-bundler validate` or equivalent
- **Prometheus metric written:** `db_restore_test_success{db="..."}` and `db_restore_test_last_timestamp{db="..."}`.

If the restore test fails, an alert fires and the dump for that service is treated as suspect until the next successful test.

### 7. Observability

A new Prometheus textfile metric file, co-located with Urd's:

```
~/containers/data/backup-metrics/db-dumps.prom
```

| Metric | Type | Labels | Consumer |
|--------|------|--------|----------|
| `db_dump_success` | gauge | `db` | `DBDumpFailed` alert (== 0) |
| `db_dump_last_success_timestamp` | gauge | `db` | `DBDumpStale` alert (age > 26h) |
| `db_dump_duration_seconds` | gauge | `db` | Trend monitoring |
| `db_dump_size_bytes` | gauge | `db` | `DBDumpSizeAnomaly` alert (50% delta) |
| `db_dump_last_run_timestamp` | gauge | — | `DBDumpJobNotRunning` alert (age > 2d) |
| `db_restore_test_success` | gauge | `db` | `DBRestoreTestFailed` alert (== 0) |
| `db_restore_test_last_timestamp` | gauge | `db` | `DBRestoreTestStale` alert (age > 8d) |

Alerts ship in `config/prometheus/alerts/db-dump-alerts.yml`. Naming mirrors Urd's `backup_*` pattern for consistency with existing Grafana panels.

## Phase 0 preconditions (before first dump run)

1. **Verify PostgreSQL checksums via `pg_controldata`.** The `postgresql-immich.container` quadlet sets `POSTGRES_INITDB_ARGS=--data-checksums`, so new clusters get checksums. Verify the live cluster matches. If not, flag as a separate remediation (not blocking this ADR — dumps don't depend on checksums).
2. **Enumerate per-service container UIDs** (needed for ACL planning in case the dump script runs as an unprivileged user):
   - postgresql-immich: subuid 100998
   - nextcloud-db: subuid 100998
   - gathio-db: subuid 100998
   - prometheus: subuid 165533
   - loki: subuid 110000

   The dump job runs as user `patriark` (uid 1000) and uses `podman exec` into each container, so container UID ownership is not the concern for dumps — but documenting these now prevents duplicated work in ADR-025.
3. **Audit Prometheus admin API exposure** per §4. Fix any gaps before enabling the flag.
4. **Confirm MongoDB tooling.** The gathio MongoDB image's `mongodump` version and its behavior with `--archive` (without `--gzip`).
5. **Create `subvol7-containers/db-dumps/` with per-service subdirectories**, owned by `patriark:patriark 0755`.

## Implementation

1. `scripts/db-dump.sh` — per-engine dump functions, retention pruning, metric emission. Exits non-zero on any dump failure.
2. `systemd/user/db-dump.service` + `db-dump.timer` — daily timer with jitter, `Nice=19`, idle I/O class.
3. `scripts/db-restore-test.sh` — per-engine ephemeral restore validation, invoked by existing `backup-restore-test.timer`.
4. `config/prometheus/alerts/db-dump-alerts.yml` — seven alerts from the metrics table.
5. Grafana panel: "DB Dump Health" — age of last success per DB, size trend, restore test status.
6. Quadlet edit: add `--web.enable-admin-api` to `quadlets/prometheus.container` Exec line.
7. Runbook: per-engine restore procedure in `docs/20-operations/runbooks/db-dump-restore.md`.

No container storage paths change. No service downtime required for rollout (except Loki's brief stop-rsync-start during each nightly dump).

## Consequences

### Positive

- **Application-consistent backups** for all DBs, replacing reliance on crash-consistent snapshots.
- **Tested restore paths.** Weekly restore validation catches silent corruption before an incident.
- **Prometheus history protected** via admin-API snapshot — preserving SLO framework and autonomous-operations inputs.
- **Strictly additive.** No storage migration, no downtime beyond Loki's brief window, no quadlet path changes, no Urd contract changes, no ACL reshuffling.
- **Reversible.** If the dump job causes problems, disable the timer. DBs continue operating normally with no cleanup required.
- **Independent of the NOCOW migration question.** If ADR-025 is later accepted, dumps continue working unchanged. If ADR-025 is permanently shelved, dumps still deliver the backup capability on their own.

### Negative

- **Loki outage window each night.** Stop-rsync-start cycle causes ~30s ingestion gap; promtail buffers during the window so no permanent log loss, but queries during the window return partial results. Acceptable given nightly cadence.
- **Disk footprint.** Local 14-day retention adds ~30GB peak to `subvol7-containers`. Pool has 3.6TB free; non-issue.
- **New failure surface.** The dump job itself can fail silently if alerting is misconfigured. Mitigated by the `DBDumpJobNotRunning` alert (age > 2d on `db_dump_last_run_timestamp`).
- **Fragmentation persists.** DBs remain in a COW'd snapshotted subvolume. If measurements later show fragmentation is actually hurting performance, ADR-025 will address it; this ADR does not.

### Constraints

- Dump job must be idempotent per night. Repeated runs within the same day overwrite the day's dump (naming by `YYYY-MM-DD`).
- Dump failures for one service must not abort the job — each engine runs in isolation and emits its own success/failure metric.
- Restore tests must use isolated containers (separate from production) and cleaned up after each run.

## Open questions

1. **Does the live postgresql-immich cluster have `data_checksums=on`?** Verifiable via `pg_controldata`; resolve in Phase 0.
2. **Is the gathio MongoDB version new enough for `mongodump --archive` without edge cases?** Verify in Phase 0.
3. **Does Prometheus admin API need path-level authentication stricter than the UI?** Traefik middleware audit in Phase 0.
4. **Should dumps eventually be encrypted at rest?** Deferred — external drives are LUKS-encrypted; local dumps on homelab disk match the existing container data trust level.

## Related

- **ADR-023 (withdrawn):** Original bundled design; this ADR is the strictly-additive half.
- **ADR-025:** NOCOW storage migration (deferred pending measurements); complements this ADR if later accepted.
- **ADR-021:** Urd integration contract; unchanged by this ADR.
- **ADR-020:** External backup strategy; dumps inherit this protection via `subvol7-containers`.
- **Review:** `docs/99-reports/2026-04-18-design-review-ADR-023-btrfs-storage-architecture-databases.md`.
