# Plan C: Backup & Dump Observability

**Date Created:** 2026-05-25
**Status:** Proposed
**Last Updated:** 2026-05-25
**Implements:** Report [2026-05-25 Monitoring Stack Deep-Dive](../99-reports/2026-05-25-monitoring-stack-deep-dive.md) §6
**Reconciles with:** ADR-029 (Three-Tier DB Storage + Dump Backup), ADR-021 (Urd), `backup-alerts.yml`,
`db-dump-alerts.yml`, `scripts/btrfs-snapshot-backup.sh`, `scripts/db-dump.sh`, `~/projects/urd`

## Objective

Raise the **signal quality** of backup observability without adding bulk. Backups are already
well-instrumented (11 alerts + restore tests); this plan fixes the one noisy alert, closes two real
coverage gaps (pool capacity, dump growth), and tidies the dashboard. Per owner decision, the **1.5 GB
nightly Prometheus dump is kept as-is** — effort goes to the items below instead.

## Background (verified 2026-05-25)

- The **only firing alert** in the whole stack is `ExternalBackupMissing{subvolume="subvol6-tmp"}`
  (`backup_snapshot_count{location="external"} == 0`, `for: 12h`, warning). `subvol6-tmp` is
  scratch/temp data; the alert has no concept of "not expected to be external."
- Urd already emits `backup_pool_free_bytes` and `backup_pool_metadata_utilization_ratio` (UPI-043),
  but **it is unconfirmed whether Prometheus scrapes them** and there is **no pool-capacity alert**.
- `db_dump_size_bytes` is collected (Prometheus dump 1.55 GB, Immich 82.6 MB, …) but **never alerted**.
- `LowSnapshotCount` is intentionally disabled (owner watches the Grafana panel).
- Context: the `backup_restore_test_*` producer was silently dead until **2026-05-24** (a `set -e` +
  `((var++))` footgun) — the alerts were correct but received no data. Reinforces "verify the signal
  arrives, not just that the alert exists."

## Approach

### 1. Fix `ExternalBackupMissing` noise (highest priority — it's the live false-positive)

First **confirm intent**: read `scripts/btrfs-snapshot-backup.sh` to determine whether `subvol6-tmp`
is *supposed* to be sent externally.

- **If tmp is intentionally local-only:** make the alert ignore non-external subvolumes. Cleanest:
  have the backup script emit a label/metric marking which subvolumes are expected-external (e.g.
  `backup_external_expected{subvolume=...} 1`), and gate the alert:
  `backup_snapshot_count{location="external"} == 0 and on(subvolume) backup_external_expected == 1`.
  Fallback (no script change): add `subvolume!="subvol6-tmp"` to the alert expr with a comment.
- **If tmp *should* be external and genuinely isn't:** this is a real miss — fix the send schedule in
  the script; keep the alert. (Determine which case before writing the fix.)

### 2. BTRFS pool free-space alert (B2)

- **Verify scrape first:** query `backup_pool_free_bytes` / `backup_pool_metadata_utilization_ratio`
  in Prometheus. If empty, Urd's pool metrics aren't reaching the textfile collector / scrape — wire
  that up (confirm Urd writes them to the node_exporter textfile dir, or add a scrape) **before**
  adding the alert.
- Then add to `backup-alerts.yml`:
  - `BtrfsPoolSpaceWarning` — free below ~15% (warning).
  - `BtrfsPoolSpaceCritical` — free below ~7% (critical) — a full pool breaks snapshots *and* dumps.
  - `BtrfsPoolMetadataExhaustion` — `backup_pool_metadata_utilization_ratio > 0.95` (BTRFS metadata
    exhaustion can ENOSPC even with data space free — a classic silent killer).
- Use slow repeat intervals (capacity is slow-moving; match the existing `DiskSpaceCritical` 24h cadence).

### 3. Dump-size-growth alert (B3)

Add `DbDumpSizeAnomaly` to `db-dump-alerts.yml`: fire when a dump exceeds, e.g., **2× its own 14-day
median** (`db_dump_size_bytes > 2 * quantile_over_time(0.5, db_dump_size_bytes[14d])`), warning,
per-`database`. Catches a runaway DB or a misconfigured dump before it pressures the 4.6 GB dump set.
Exclude/relax for `prometheus` (its size tracks TSDB, addressed by Plan A's diet).

### 4. `LowSnapshotCount` + documentation (B4)

- Leave `LowSnapshotCount` disabled, but add an in-rule comment stating the decision and that the
  signal lives on the `backup-health` dashboard.
- Confirm the `backup-health.json` dashboard actually has a per-subvolume snapshot-count panel.

### 5. backup-health dashboard polish

Promote the new signals to first-class panels on `backup-health.json`:
- BTRFS pool free-space + metadata-utilization gauges (from B2).
- `db_dump_size_bytes` trend per database (makes B3 visually verifiable).
- Restore-test recency (`time() - db_restore_test_last_timestamp`) — given the May 2026 dead-metric
  incident, surfacing freshness guards against silent producer failure.

## Success Criteria

- `ExternalBackupMissing` no longer fires for scratch subvolumes; firing-alert count returns to **0**
  in steady state.
- `backup_pool_free_bytes` confirmed present in Prometheus; pool warning/critical/metadata alerts load
  and `promtool check rules` passes.
- `DbDumpSizeAnomaly` loads and does not false-fire against current 14-day-stable dump sizes.
- `backup-health` dashboard shows pool space, dump-size trend, and restore-test recency.

## Verification

```bash
podman exec prometheus promtool check rules /etc/prometheus/alerts/backup-alerts.yml \
  /etc/prometheus/alerts/db-dump-alerts.yml
# confirm the metrics the new alerts depend on actually exist:
for q in backup_pool_free_bytes backup_pool_metadata_utilization_ratio db_dump_size_bytes backup_external_expected; do
  podman exec prometheus wget -qO- "http://localhost:9090/api/v1/query?query=$q" | head -c 200; echo
done
# confirm ExternalBackupMissing is no longer firing:
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=ALERTS%7Balertname%3D%22ExternalBackupMissing%22,alertstate%3D%22firing%22%7D'
# backup-health dashboard: pool + dump-size + restore-recency panels populate
```

## Rollback

`git revert` the alert-file and dashboard-JSON changes. If Plan C touches `btrfs-snapshot-backup.sh`
(expected-external label), revert it separately; the script keeps emitting existing metrics regardless.

## Notes

- Cross-repo: pool-metric wiring may require a change in `~/projects/urd` (textfile output) rather than
  this repo — flag and coordinate if so (see `reference_urd_project`).
- This plan deliberately does **not** touch the Prometheus dump, retention, or the dump schedule.

## Progress Log

- 2026-05-25 — Plan drafted from deep-dive report. Status: Proposed. Item 1 is the only live
  false-positive and should ship first.
- 2026-05-25 — **Ground-truth verification (branch `feat/backup-observability`).** Several plan
  assumptions corrected against the live system:
  - **Producer is Urd, not the shell script.** `scripts/btrfs-snapshot-backup.sh` is disabled
    (ADR-021, sole backup = Urd since 2026-03-25). The "have the backup script emit a label" path in
    item 1 / item 2 must target `~/projects/urd`, which writes `data/backup-metrics/backup.prom`
    (scraped via node_exporter textfile collector).
  - **Item 2 scrape already works.** `backup_pool_free_bytes` (3), `backup_pool_metadata_utilization_ratio`
    (3), `db_dump_size_bytes` (6) all confirmed present in Prometheus — no wiring needed. Pool metrics
    are keyed `{uuid,role,label}` (NOT `subvolume`): source `/`, source `/mnt`, destination `WD-18TB`.
  - **Dead alert found:** `BtrfsPoolSpaceWarning` queried `mountpoint="/mnt/btrfs-pool"` (0 series) —
    real mountpoint is `/mnt`. Fixed. **/mnt is at 19.8% free**, so the corrected warning fires on
    reload (true positive, pool ~80% used / ~3.1 TB free; previously masked).
  - **subvol6-tmp** is the only subvolume with `external==0` (send_type=2). Item 1 needs the
    expected-external intent confirmed in Urd before the gate is written.
  - **db_dump_size_bytes** has only ~3 days of history (14-day median widens over time). A stale
    `loki` series appears in range queries but not instant (not in current dump).
  - **Shipped this branch (no Urd dependency, promtool-clean, verified non-false-firing):**
    fixed `BtrfsPoolSpaceWarning` (/mnt); added `BtrfsPoolSpaceCritical` (/mnt <10%);
    `BackupPoolMetadataExhaustion` (>0.95, group `backup_pool_alerts`); `DbDumpSizeAnomaly`
    (2× 14-day median AND >50 MiB, excl. prometheus); reaffirmed `LowSnapshotCount` disabled w/ note.
  - **Gated on Urd handoff (2026-05-25):** (1) item 1 clean fix needs `backup_external_expected{subvolume}`;
    (2) destination free-% alert needs `backup_pool_total_bytes` (node_exporter can't see the offsite
    drive per ADR-023; WD-18TB ~18% free — highest-value gap). Dashboard polish (item 5) staged until
    the final metric set lands.
- 2026-05-25 — **Urd handoff received (PR #145, written, not yet run).** Both metrics implemented &
  additive (ADR-105 safe). Confirmed: subvol6-tmp is local-only by design (`send_enabled=false`);
  WD-18TB = 18.00 TB, **84% used / 16.6% free**; `backup_pool_*` refresh once per nightly run
  (sentinel never writes `.prom`); `db_dump_*`/`db_restore_test_*` are homelab-owned (not Urd).
  - **Implemented item 1 + item 2-destination:** `ExternalBackupMissing` now gates on
    `and on(subvolume) backup_external_expected == 1`; added `BackupDestinationPoolSpaceWarning` (<15%)
    + `BackupDestinationPoolSpaceCritical` (<7%). Both inert (return 0) until the new series emit.
    Break-glass fallback for item 1 recorded inline.
  - **ADR-021 amended** (2026-05-25, PR #145 section): registers both new series as consumed; records
    deploy-ordering and the source-pool (node_exporter) vs destination-pool (Urd) split.
  - ⚠️ **DEPLOY ORDERING:** merge Urd PR #145 + run `urd backup` (emit series) BEFORE deploying/reloading
    these rules — the `backup_external_expected` join otherwise suppresses ExternalBackupMissing entirely.
  - **Item 5 dashboard polish DONE:** added pool free-% + metadata gauges, dump-size trend (log scale),
    and restore-test recency to `backup-health.json`; fixed the "Active Backup Alerts" table to match on
    `category=~"backup|disaster-recovery"` (was a name regex missing `ExternalBackupMissing`/`DbDump*`).
  - **Threshold decision (owner, 2026-05-25):** `BtrfsPoolSpaceWarning` set to 15% (not 20%) so it does
    not page on today's steady 19.8% free; `BtrfsPoolSpaceCritical` (<10%) escalates. Revisit if /mnt
    usage climbs. All other new alerts verified to return 0 against live data.
  - **Status: COMPLETE pending Urd PR #145 merge + first run** (then deploy/reload, honoring ordering).
