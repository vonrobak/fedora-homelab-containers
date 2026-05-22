# ADR-025: Database Storage Migration to NOCOW Subvolume (Deferred)

**Date:** 2026-04-18
**Status:** Superseded by ADR-029 (2026-05-22) — migration runbook consolidated there as Phase B (still gated)
**Replaces (part 2 of 2):** ADR-023 (withdrawn)
**Companion:** ADR-024 (dump-based backup — accepted and shipping first)
**Earliest review for acceptance:** 2026-06-18 (60 days after ADR-024 begins running)

## Context

BTRFS has a known antipattern: files with `chattr +C` (NOCOW) inside a snapshotted subvolume do not actually retain NOCOW behavior. The first write to any extent shared with a snapshot forces copy-on-write regardless of the NOCOW flag. Every snapshot pins the old extents, so each daily snapshot effectively re-COWs the write-hot regions of database files.

Our current state has this problem, inconsistently applied:

- `nextcloud-db` (MariaDB 155M): **no NOCOW** — fully COW'd, inside snapshotted subvol
- `loki` (TSDB 574M): **no NOCOW** — fully COW'd, inside snapshotted subvol
- `postgresql-immich`: NOCOW flag inheritance unclear, but defeated by snapshots regardless
- `gathio-db`: NOCOW set, but defeated by snapshots
- `prometheus`: NOCOW set, but defeated by snapshots

The theoretically correct solution is a dedicated NOCOW subvolume (`subvol8-db`) excluded from Urd snapshots, with application-level dumps providing backup coverage. The predecessor ADR-023 proposed this migration and bundled it with introducing dump-based backup.

The adversarial review of ADR-023 raised a fundamental objection: **the migration's premise is theoretical, not measured.** On a 30-container homelab with light load, the practical cost of COW-induced fragmentation may be well below any threshold that justifies the risk of migrating five production databases. The correct decision order is:

1. Ship dumps first (ADR-024) — strictly additive, low-risk, delivers most of the backup value.
2. Gather baseline measurements on DBs-in-place for 60 days.
3. Decide whether migration is justified by evidence.

This ADR documents the migration plan so it's ready to execute if measurements justify, but defers acceptance until the measurements exist.

## Decision (deferred)

**If measurements show the COW-in-snapshotted-subvol antipattern is costing measurable performance or backup-window impact**, migrate the five affected databases to a dedicated NOCOW subvolume `subvol8-db` at `/mnt/btrfs-pool/subvol8-db`, excluded from Urd. Backup coverage transfers fully to the ADR-024 dump path (already operational by that point).

**If measurements show the antipattern is not costing anything measurable**, this ADR stays Deferred indefinitely or is itself withdrawn. DBs remain in `subvol7-containers` and the ADR-024 dump path is the sole backup mechanism — which is the complete, correct, and sufficient solution.

## Acceptance criteria — what evidence justifies migration

Migration is justified if **any one** of the following measurements shows a material problem:

### 1. Fragmentation

Run monthly for 60 days after ADR-024 ships:

```
filefrag -v /mnt/btrfs-pool/subvol7-containers/{postgresql-immich,nextcloud-db,gathio-db,prometheus,loki}/**/*
```

Thresholds:
- **Accept migration** if any single DB file shows >5000 extents sustained, OR if aggregate extent count across DB files grows >50% over a 30-day window.
- **Defer indefinitely** if extent counts stabilize below 1000 per file.

### 2. Query latency (Immich PG specifically, as the largest DB)

Grafana panel tracking Immich's `/api` p99 latency, added as part of ADR-024's observability work.

Thresholds:
- **Accept migration** if Immich API p99 > 500ms sustained for 7+ days with DB I/O as the confirmed culprit (`iostat` on the pool shows sustained >80% utilization attributable to the Immich PG container).
- **Defer indefinitely** if p99 stays below 200ms.

### 3. Snapshot send duration

Urd already emits `backup_duration_seconds{subvolume="subvol7-containers"}`.

Thresholds:
- **Accept migration** if median send duration grows >3× over 60 days *and* analysis traces the growth to DB churn (via `btrfs subvolume find-new` on the DB directories).
- **Defer indefinitely** if send duration is flat or growth tracks linearly with non-DB data growth.

### 4. Operator pain

A softer criterion but legitimate: if DB-in-COW-subvol causes unexpected operational issues (e.g., snapshot cleanup failing, pool fragmentation warnings in dmesg, unexpected space pressure from snapshot residency), those count as evidence.

All four criteria must be evaluated together. A single data point doesn't justify migration; a pattern across criteria does.

## Proposed design (if accepted)

### Storage layout

```
/mnt/btrfs-pool/subvol8-db (NEW)       [NOCOW inherited, compression=none, NOT in Urd]
├── postgresql-immich/                 [subuid 100998; traversal ACL required]
├── nextcloud-db/                      [subuid 100998]
├── gathio-db/                         [subuid 100998]
├── prometheus/                        [subuid 165533]
└── loki/                              [subuid 110000]
```

Compression is explicitly disabled via `btrfs property set subvol8-db compression none` — every listed engine already compresses at the page/chunk layer; stacking zstd on top wastes CPU with no storage benefit.

### What moves vs stays

**Moves to subvol8-db:** the five databases above.

**Stays on subvol7-containers:** Redis (redis-immich, nextcloud-redis) — RDB persistence is whole-file rewrite pattern, not affected by COW fragmentation; snapshots retain session state meaningfully; size is trivial. All non-DB container state (configs, logs, caches) also stays.

### ACL model

`subvol8-db` uses ACLs per ADR-019's pattern, but with **two layers** of access because the subvolume itself must be traversable by each container's subuid:

1. **Parent-level traversal ACLs** on `subvol8-db/`:
   ```
   setfacl -m u:100998:--x /mnt/btrfs-pool/subvol8-db   # postgres/maria/mongo
   setfacl -m u:165533:--x /mnt/btrfs-pool/subvol8-db   # prometheus
   setfacl -m u:110000:--x /mnt/btrfs-pool/subvol8-db   # loki
   ```

2. **Per-service directory ACLs** on `subvol8-db/<service>/`:
   ```
   setfacl -R -m u:<subuid>:rwx /mnt/btrfs-pool/subvol8-db/<service>
   setfacl -R -d -m u:<subuid>:rwx /mnt/btrfs-pool/subvol8-db/<service>
   ```

Omitting either layer causes the container to fail at startup with a traversal error that doesn't clearly point at the ACL — this is the most likely cause of a failed migration if executed carelessly.

### Urd integration

`subvol8-db` is **not** added to Urd. This is deliberate: the DBs' live files are not what we back up. The backup is the dumps in `subvol7-containers/db-dumps/` produced by ADR-024's pipeline.

To maintain operator legibility, add a note to Urd's config (or a CLAUDE.md reference) making this explicit: "subvol8-db is intentionally excluded — DB backup is via application-level dumps (ADR-024), not filesystem snapshots."

### Data checksums

NOCOW disables BTRFS data checksums. Each engine must provide its own integrity checking:

| Engine | Integrity mechanism | Default state |
|--------|---------------------|---------------|
| PostgreSQL | `data_checksums` at `initdb` time | Quadlet sets `POSTGRES_INITDB_ARGS=--data-checksums`; live state to be verified before migration via `pg_controldata` |
| MariaDB/InnoDB | `innodb_checksum_algorithm=crc32` | Default on MariaDB 10.5+ |
| MongoDB/WiredTiger | Page-level checksums | Default |
| Prometheus TSDB | Per-chunk CRC32 | Default |
| Loki | Per-chunk checksums | Default |

### Migration procedure (if executed)

Per-service, ordered smallest-first to build confidence: gathio-db → nextcloud-db → loki → prometheus → postgresql-immich.

For each service:

1. **Stop the service** and any dependents.
2. **Take a final dump** via the ADR-024 tooling — this is the rollback artifact.
3. **Create target directory** in `subvol8-db/<service>/` with correct ACLs (parent traversal + per-service rwx + default).
4. **Move the data**:
   - For PostgreSQL: **do not run initdb on the host**. The container's entrypoint creates the cluster with the env-configured flags. Empty the target dir, start the container with an empty data volume, let initdb happen inside the container, stop, then restore from the dump.
   - For MariaDB/MongoDB/Loki/Prometheus: `rsync -aHX --numeric-ids <source>/ <target>/`. **No `cp --reflink`, no `--inplace`**. Post-copy verify with `lsattr` (expect `C` flag) and `filefrag -v` (expect no shared extents).
5. **Update the quadlet** `Volume=` line to the new path.
6. **`systemctl --user daemon-reload && systemctl --user start <service>.service`**.
7. **Verify service health** via its HTTP/TCP probe and container logs.
8. **Rename source dir** to `<service>.pre-migration-YYYY-MM-DD` and retain for 14 days.
9. **Trigger a manual dump** to confirm the dump pipeline still works against the new location.
10. **Run the restore test** against the fresh dump to confirm end-to-end.

### Defensive migration tooling

If migration is accepted, the procedure above is implemented as a tool, not executed by hand:

- `scripts/migrate-db-to-subvol8.sh <service>` — per-service migration with:
  - Dry-run by default; `--execute` required for destructive steps
  - Hard enforcement of `rsync` flags (no environment-inherited aliases)
  - Post-copy verification: `lsattr` shows `C` flag on every copied file, `filefrag` confirms no shared extents
  - ACL verification: every expected ACL is present before the service is started
  - Service-health verification before the source dir is renamed
  - Rollback subcommand: `migrate-db-to-subvol8.sh rollback <service>` that reverses the quadlet edit, re-mounts the old dir, and restarts

The tool is itself reviewed before migration proceeds — this is the riskiest moment in the migration path and improvised shell commands are not acceptable.

### Observability gap during Prometheus migration

Moving Prometheus takes 5–10 minutes (dump + rsync + restart). During this window:

- Metric ingestion stops; Grafana renders gaps as nulls.
- Alerts with `for: 5m` may miss state transitions.
- Autonomous-operations OODA loops must be paused (they're triggered by cron; disable the relevant timer for the migration window).
- Plan the migration window during low-activity hours (early morning weekday) to minimize lost context.

## If the measurements say "don't migrate"

If 60 days of evidence say the COW-in-snapshotted-subvol cost is negligible, the right action is:

- Mark this ADR **Withdrawn** with a note explaining why (a valuable historical record — "we almost did this and measurement said no").
- Keep ADR-024 as the complete backup solution.
- Accept the fragmentation cost as part of the homelab's operating envelope.

This is a legitimate and likely outcome. It is not a failure of this ADR; it is the ADR doing its job — preventing a preemptive optimization that isn't earning its keep.

## Preconditions for triggering acceptance

Before this ADR can move from Deferred to Accepted, all of these must hold:

1. **ADR-024 has been operational for at least 60 days** and its dumps have passed at least four weekly restore tests per service without failure.
2. **At least one of the acceptance criteria above is met** based on real measurements in the Grafana dashboard.
3. **The defensive migration tool is written and reviewed**, not just planned.
4. **A specific migration window is scheduled** with stakeholder awareness (the homelab owner, since that's the stakeholder).
5. **A tested rollback path exists** — the tool's `rollback` subcommand has been exercised against a non-production service (e.g., spin up a throwaway Postgres, migrate it, roll it back, verify).

## Consequences (if accepted)

### Positive

- NOCOW actually works — no snapshot interference, write-in-place on HDD for DB workloads.
- `subvol7-containers` snapshot deltas shrink when DB churn is removed. External send times drop; snapshot residency shrinks.
- Cleaner storage model: DBs in their own subvolume, aligned with BTRFS best practice.

### Negative

- **Loss of crash-consistent snapshot rollback for DBs.** Bad Immich migration? Restore path is "yesterday's dump," not "reset to 10 minutes ago." Dumps are the only recovery — but that's already true operationally; snapshots of running DBs are not a trusted recovery path today.
- **Migration risk surface.** Five services move in sequence; each is a potential failure point. Mitigated by dry-run tool, small-first ordering, per-service dump as rollback artifact.
- **Operational complexity increases.** New subvolume to manage, new ACL pattern to maintain, Urd status no longer covers these services (documented, but a real UX cost).

### Constraints

- Dumps must be fully operational and tested *before* migration begins — ADR-024 is a hard dependency.
- Every migration step must be reversible per-service before moving to the next.
- If any service's migration fails in a way that can't be cleanly rolled back, the remaining services stay in `subvol7-containers`. Partial migration is acceptable; forced completion is not.

## Alternatives considered (if measurements justify action, but not this plan)

**1. Move DBs to NVMe.** Rejected — NVMe is 90% full (13GB free). Not viable regardless.

**2. Keep current layout, fix NOCOW flags that are missing.** Rejected — NOCOW is defeated by snapshots anyway. Doesn't solve the actual problem.

**3. Disable snapshots on subvol7-containers.** Rejected — container configs genuinely benefit from snapshot-based rollback for config mistakes. Cure worse than disease.

**4. Nested subvolume inside subvol7-containers instead of top-level subvol8-db.** Rejected in the predecessor ADR on "legibility" grounds. Reconsidered in review: nested would work semantically. Top-level was retained because (a) it surfaces clearly in `btrfs subvolume list`, (b) it matches the existing subvolume naming pattern, (c) it makes the Urd exclusion explicit in the top-level structure. Nested remains a legitimate fallback if top-level encounters unforeseen issues.

**5. Periodic `btrfs filesystem defragment` on DB dirs.** Rejected — running defrag on files in a snapshotted subvolume unshares extents, doubling space use. Would cost significant pool space per run.

**6. Disable `autodefrag` globally.** Considered. `autodefrag` primarily affects COW files; NOCOW files (if they exist) are immune. For a mixed workload (docs, media, containers) on HDD, autodefrag is net-beneficial. Disabling it to optimize for DB workload would regress everything else. Not pursued.

## Open questions (to resolve during measurement window)

1. **What are the actual filefrag counts?** Unknown today. Single most important missing input.
2. **Does Immich API p99 correlate with Postgres container I/O?** Unknown today. Requires Grafana panel instrumentation as part of ADR-024.
3. **How much of `subvol7-containers` snapshot delta is DB churn?** Unknown today. Requires `btrfs subvolume find-new` or similar analysis.
4. **Does rootless Podman have any interaction with nested subvolumes we haven't accounted for?** Unknown. If top-level approach encounters unexpected issues, this becomes the fallback question to investigate.
5. **Would the Urd project benefit from a "known excluded subvolumes" config field** so `urd status` can explicitly show "subvol8-db: excluded by design" rather than silently not covering it? Out of scope here; flag for the Urd project's own ADR list.

## Related

- **ADR-023 (withdrawn):** Original bundled design; split into ADR-024 + this ADR.
- **ADR-024 (accepted):** Dump-based backup. Hard dependency — must be operational and tested before this ADR can become Accepted.
- **ADR-021:** Urd integration contract. Unchanged by this ADR (exclusion is by omission, not by contract change).
- **ADR-020:** External backup strategy. Dumps from ADR-024 inherit this; live DB files in subvol8-db deliberately do not.
- **ADR-019:** Filesystem permission model. Extended with the two-layer ACL pattern documented above.
- **Review:** `docs/99-reports/2026-04-18-design-review-ADR-023-btrfs-storage-architecture-databases.md`.

## Revisiting this ADR

Revisit no earlier than 2026-06-18. At that time:

- Read the 60-day Grafana baseline.
- Evaluate against the acceptance criteria above.
- If accepted: build the migration tool, schedule the window, execute.
- If not accepted: mark this ADR **Withdrawn** and update ADR-024 to reflect that it is the complete solution.
- If inconclusive: extend the measurement window by another 60 days and revisit.
