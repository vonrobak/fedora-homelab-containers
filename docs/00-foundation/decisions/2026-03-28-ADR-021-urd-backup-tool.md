# ADR-021: Urd Replaces Shell Script for BTRFS Backup Management

**Date:** 2026-03-28
**Status:** Accepted
**Supersedes:** ADR-020 (implementation only — the backup strategy decisions in ADR-020 remain valid)

## Context

ADR-020 established daily incremental external sends with graduated retention, implemented in `btrfs-snapshot-backup.sh` (~1700 lines of bash). The script worked but had fundamental limitations:

- **Fragile error handling.** Bash makes it difficult to isolate per-subvolume failures. A single error in the send pipeline could abort the entire run, leaving other subvolumes unprotected.
- **No safety guarantees.** Retention cleanup and pin file protection depended on careful scripting with no compile-time or type-level enforcement. The [backup script audit (PR #130)](https://github.com/patriark/containers/pull/130) found 9 operational reliability issues.
- **No monitoring between runs.** The script ran once at 02:00, then was blind until the next night. A drive unmounting at 03:00 went unnoticed for 24 hours.
- **No promise model.** The script thought in operations (snapshot, send, prune). The user had to mentally map operations to "is my data safe?" — there was no first-class concept of protection state.

In parallel, a Rust-based tool called **Urd** was developed specifically to address these gaps. Urd reached production readiness and cut over as the sole backup system on 2026-03-25.

## Decision

Replace `btrfs-snapshot-backup.sh` with [Urd](https://github.com/patriark/urd), a purpose-built Rust tool for BTRFS snapshot lifecycle management.

### What Urd provides

- **Promise-based model.** Subvolumes declare a protection level (resilient/protected/guarded). Urd derives retention, intervals, and drive requirements, then reports whether promises are being kept (PROTECTED / AT RISK / UNPROTECTED).
- **Pure-function planner.** Config + filesystem state → plan → execute. The planner never touches the filesystem; the executor never decides what to do. 389 tests validate the logic.
- **Per-subvolume error isolation.** A failed send for one subvolume never aborts the run. Other subvolumes proceed normally.
- **Defense-in-depth pin protection.** Three independent layers prevent pinned parent snapshots (incremental chain anchors) from accidental deletion: unsent protection, planner exclusion, executor re-check.
- **Sentinel daemon.** A passive monitoring process (`urd sentinel run`) polls for drive mounts, heartbeat changes, and promise state transitions between nightly runs. Catches problems in minutes, not hours.
- **Drive-aware chains.** Independent incremental chain state per external drive, with UUID fingerprinting to detect drive swaps.
- **Prometheus-compatible metrics.** Atomic writes to `.prom` textfile, same metric names as the old script for monitoring continuity.

### What stays the same

The backup *strategy* from ADR-020 is unchanged — Urd implements the same model:
- Daily incremental sends for Tier 1/2, monthly for Tier 3
- Graduated local retention (dense recent, thinned older)
- Dual pin files per external drive for independent chains
- Graceful handling of absent external drives

## Integration Contract

These are the touchpoints between Urd and the homelab infrastructure. **Update this ADR when any of these change.**

### Systemd units

| Unit | Schedule | Description |
|------|----------|-------------|
| `urd-backup.timer` | `*-*-* 04:00:00` (±5min jitter) | Nightly backup run |
| `urd-backup.service` | Triggered by timer | `urd backup --confirm-retention-change`, 6h timeout, Nice=19/idle I/O |
| `urd-sentinel.service` | Continuous (Type=simple) | Passive monitor, restart-on-failure, Nice=19/idle I/O |

Source files: `~/projects/urd/systemd/`, installed to `~/.config/systemd/user/`.

### Prometheus metrics

Urd writes to `~/containers/data/backup-metrics/backup.prom`, collected by node-exporter's textfile collector (mounted read-only into the node-exporter container).

Key metrics consumed by homelab alerts (`config/prometheus/alerts/backup-alerts.yml`):

| Metric | Type | Labels | Used by |
|--------|------|--------|---------|
| `backup_success` | gauge | `subvolume` | `BackupFailed` alert (== 0) |
| `backup_last_success_timestamp` | gauge | `subvolume` | `BackupStale` alert (age > 2d) |
| `backup_script_last_run_timestamp` | gauge | — | `BackupScriptNotRunning` alert (age > 2d) |
| `backup_snapshot_count` | gauge | `subvolume`, `location` | `ExternalBackupMissing` alert (external == 0) |
| `backup_duration_seconds` | gauge | `subvolume` | `BackupSlowDuration` alert (> 1h) |
| `backup_send_type` | gauge | `subvolume` | Grafana dashboard |
| `backup_external_drive_mounted` | gauge | — | Grafana dashboard |
| `backup_external_free_bytes` | gauge | — | Grafana dashboard |

### File paths

| Path | Purpose |
|------|---------|
| `~/.config/urd/urd.toml` | Urd configuration |
| `~/.local/share/urd/urd.db` | SQLite run history |
| `~/.local/share/urd/heartbeat.json` | Health signal (Sentinel reads this) |
| `~/containers/data/backup-metrics/backup.prom` | Prometheus metrics (shared with homelab) |
| `~/containers/data/backup-logs/` | Log directory |

### Notification path

Urd currently logs to journald. Discord notifications are planned (Sentinel active mode). When implemented, they should use the existing `alert-discord-relay` container or a direct webhook — TBD.

## Decommissioned Components

| Component | Status | Action needed |
|-----------|--------|---------------|
| `scripts/btrfs-snapshot-backup.sh` | Replaced | Remove after 30-day confidence period (~2026-04-25) |
| `btrfs-backup-daily.timer` | Disabled | Remove unit files |
| `btrfs-backup-daily.service` | Disabled | Remove unit files |
| `btrfs-backup-weekly.timer` | Disabled | Remove unit files (was already replaced by daily in ADR-020) |
| `btrfs-backup-weekly.service` | Disabled | Remove unit files |

The `backup-restore-test.timer`/`.service` are independent of Urd and remain active.

## Consequences

### Positive
- **Compiler-enforced safety.** Type system prevents classes of bugs that bash cannot catch. 389 tests validate backup logic including edge cases.
- **Promise-based UX.** "Is my data safe?" has a first-class answer: `urd status`.
- **Continuous monitoring.** Sentinel catches drive disconnects and missed backups between nightly runs.
- **Metric continuity.** Same Prometheus metric names — existing alerts and Grafana dashboards work without changes.
- **Independent development.** Urd evolves in its own repo with its own ADRs (100–111), test suite, and release cycle. The homelab consumes it as a black box through the integration contract above.

### Negative
- **External dependency.** Urd is a separate project. Homelab backup reliability now depends on a Rust binary rather than a script visible in this repo. Mitigated by: Urd is also authored/maintained by the homelab owner.
- **Build requirement.** Requires `cargo build --release` and a Rust toolchain. The old script had zero build dependencies.
- **Two repos to reason about.** Backup debugging may require context from both `~/containers/` and `~/projects/urd/`. Mitigated by: this ADR documents the integration contract; Urd's own docs cover its internals.

### Risks
- **Urd is under active development.** Config schema redesign (ADR-111) and Sentinel active mode are in progress. Breaking changes to the integration contract (metric names, systemd units, file paths) must be reflected back in this ADR.

## Keeping This ADR Current

This ADR documents the **integration boundary**, not Urd's internals. It needs updating only when:

1. **Systemd units change** — new services, renamed timers, different schedules
2. **Prometheus metrics change** — renamed metrics, new labels, changed semantics
3. **File paths change** — metrics file, config location, heartbeat path
4. **Notification path changes** — Discord integration, new alert channels
5. **Decommissioned components are cleaned up** — remove from the table above

Urd's internal architecture, retention algorithms, config schema, and CLI commands are documented in the [Urd project](https://github.com/patriark/urd) and do not belong in this ADR.

## Related
- **ADR-020:** Daily external backups (strategy — still valid, implementation superseded)
- **Urd project:** `~/projects/urd/` — CLAUDE.md, ADRs 100–111, status.md
- **Urd design plan:** `docs/00-foundation/decisions/2026-03-23-urd-btrfs-time-machine-design.md`
- **Backup alerts:** `config/prometheus/alerts/backup-alerts.yml`
- **Node exporter integration:** `quadlets/node_exporter.container` (textfile collector mount)
