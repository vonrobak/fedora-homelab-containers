# Backup & Dump Observability — Cross-Repo Session with Urd (Plan C)

**Date:** 2026-05-25
**Context:** Execute [Plan C: Backup & Dump Observability](../97-plans/2026-05-25-backup-observability.md) —
raise the signal quality of backup monitoring without bloat. Backups are produced by **Urd**, a
separate repo (`~/projects/urd`), so part of the work had to be verified and implemented there and
handed back. Shipped as PR #237 (`f6492f8`), coordinated with Urd PR #145 (v0.21.0).

## What Was Done

- **Verified ground truth before writing anything**, which overturned three plan assumptions (see
  Lessons). Then implemented against reality, not the plan's stale framing.
- **Alerts:** gated `ExternalBackupMissing` on Urd's new `backup_external_expected` (removes the lone
  live false positive, `subvol6-tmp`); fixed a *dead* `BtrfsPoolSpaceWarning`; added
  `BtrfsPoolSpaceCritical`, `BackupPoolMetadataExhaustion`, `BackupDestinationPoolSpace{Warning,Critical}`,
  and `DbDumpSizeAnomaly`.
- **Dashboard:** added pool free-% + metadata gauges, dump-size trend (log), restore-test recency to
  `backup-health.json`; fixed the "Active Backup Alerts" table to match on `category` labels (it was
  silently missing `ExternalBackupMissing` and `DbDump*`).
- **Cross-repo:** authored a structured verification prompt for the Urd session; Urd implemented and
  returned two new metrics (`backup_external_expected`, `backup_pool_total_bytes`); cross-checked their
  ADR draft against mine and completed the ADR-021 contract tables.
- **Deployed in order:** waited for Urd v0.21.0 + a real `urd backup` run (#88) to emit the series →
  confirmed scrape → hot-reloaded Prometheus → **firing-alert count went from 1 to 0**, no rule errors.

## Lessons Learned

### On the monitoring itself

- **Verify the *producer*, not just the metric name.** The plan said "read `btrfs-snapshot-backup.sh`
  and have the backup script emit a label." That script has been disabled since the Urd cutover
  (ADR-021); the real emitter is Urd writing `data/backup-metrics/backup.prom`. Editing the obvious
  file would have changed nothing. **Trace a metric to its actual emitter before touching "the obvious
  source."**
- **A dead alert is worse than no alert — it's invisible failure wearing a green badge.**
  `BtrfsPoolSpaceWarning` queried `mountpoint="/mnt/btrfs-pool"`; the real mountpoint is `/mnt`, so the
  selector returned **zero series** and the rule had silently never fired. It had been masking a data
  pool sitting at ~80% used. This rhymes with the plan's own cautionary tale (the `restore_test_*`
  producer was dead for weeks). **An alert is only real if its selector returns data — confirm the
  series exists, don't assume the rule's presence means coverage.**
- **`promtool` proves syntax, live queries prove behavior.** Every new expression was run as an instant
  query against Prometheus to confirm it returned 0 (no false-fire) *and*, for the fixed warning, the
  one intended true-positive. `promtool check rules` would have passed a rule that never matches
  anything — exactly the dead-alert failure mode.
- **Reason explicitly about absent-metric behavior.** Because `backup_external_expected` is emitted
  *only* as `1` (absent otherwise), the gated `… and on(subvolume) backup_external_expected == 1`
  returns nothing until the series exists — which **fully suppresses** the alert, real misses included.
  An alert that depends on a not-yet-live metric isn't "inert" by default; it can be silently
  *suppressing*. Know which.

### On working efficiently across repos

- **Hand the owning repo a structured prompt, not a question.** The effective pattern was: (1) state
  *my* observed ground truth so they could confirm/correct, (2) ask falsifiable, specific questions,
  (3) request a defined output format, (4) explicitly invite them to implement if cheap. The Urd
  session came back with not just answers but two merged metrics and an ADR draft. A vague "can you
  check backups?" would have produced a fraction of that.
- **Let structural boundaries pick your asks.** node_exporter *cannot* see the offsite drive (excluded
  per ADR-023), so a destination free-% alert *must* get its total from Urd. Recognizing "who can
  physically see what" is what separated the genuine cross-repo asks from things I could do locally.
  Don't ask the other repo for what your side already has.
- **The contract has two homes; cross-check both.** The interface lives in ADR-021 (consumer) *and*
  Urd ADR-105 / CHANGELOG (producer). My amendment recorded the change in prose but left the canonical
  ADR-021 tables reading stale ("Not yet consumed"); the Urd session's draft caught exactly that.
  **A cross-repo doc change needs a round-trip — each side spots the staleness the other can't see.**
- **Pin concrete refs in the handoff.** "Urd PR #145", "v0.21.0", "run #88" made the deploy interlock
  actionable and auditable, versus "the new Urd version."
- **Sequencing is a correctness property across repos.** "Merge Urd → run a real backup → confirm the
  series scraped → *then* reload Prometheus" wasn't politeness; reversing it would have blinded a
  data-loss-critical alert. Cross-repo ordering deserves the same rigor as a migration.

### Meta

- **Memory paid for itself.** `project_backup_system` (Urd is sole producer) and `reference_urd_project`
  immediately flagged the plan's stale "edit the shell script" framing — a verification that would
  otherwise have cost several wrong turns.

## What These Tools Now Enable (Future)

The new metrics aren't just alerts — they're a small capacity/health telemetry surface to build on:

1. **Capacity forecasting & proactive drive rotation.** With `backup_pool_total_bytes` + `free_bytes` +
   the existing `backup_subvolume_churn_bytes_per_second`, a `predict_linear` panel can estimate the
   WD-18TB exhaustion date and trigger the offsite swap / retention tuning *before* it's urgent.
   WD-18TB is already at 84% used — this is the highest-value next build, not a hypothetical.
2. **Scheduled BTRFS metadata balance.** `backup_pool_metadata_utilization_ratio` (/mnt at 0.86) gives
   the early signal to run a targeted `btrfs balance -m` *ahead* of the metadata-ENOSPC cliff, instead
   of discovering it when snapshots start failing.
3. **"Backups are restorable" as a first-class SLO.** The restore-test recency panel + the
   `DbRestoreTestOverdue` guard turn restore freshness into a measurable objective — the direct
   antidote to the silent-producer-death failure mode that bit us in May.
4. **Dump-size anomaly as a cross-domain data-health canary.** A ballooning dump usually means an app
   problem (runaway table, DB-logged spam) *before* the app alerts on itself. `DbDumpSizeAnomaly` is
   cheap early warning for application data health, not just backup hygiene.
5. **Headroom-aware retention.** Urd already emits `backup_subvolume_estimated_local_pinned_delta_bytes`
   (UPI 044 seed). The homelab could surface "you have room to keep N more snapshots of X" — retention
   tuning driven by data instead of guesswork.
6. **Converge on the pool metrics.** Migrate dashboards/alerts off the legacy unlabeled
   `backup_external_free_bytes` onto the labeled `backup_pool_*` family, then deprecate the legacy
   series (coordinated ADR-105 change). One consistent capacity model across source and destination.

## Next Steps

- **Watch items (live, not firing):** WD-18TB 16.6% free (warn 15%), /mnt 19.8% free (warn 15%),
  /mnt metadata 0.86 (exhaustion 0.95). The nearest signals — the alerts now exist to catch them.
- **Highest-value follow-up:** the capacity-forecast panel (#1 above) for the offsite drive.
- **Deferred:** deprecate `backup_external_free_bytes` (coordinated with Urd, ADR-105).
- **Open from the plan's siblings:** Plan A (Prometheus metric diet) is the natural next monitoring
  workstream; the `loki` dump ghost-series noticed here is likely one of its inputs.
