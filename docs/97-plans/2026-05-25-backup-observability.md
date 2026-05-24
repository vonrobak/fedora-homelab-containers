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
