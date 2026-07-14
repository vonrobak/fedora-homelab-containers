---
type: ADR
title: "ADR-021: Urd Replaces Shell Script for BTRFS Backup Management"
description: "ADR replacing the ~1700-line bash backup script with Urd, a purpose-built Rust tool for BTRFS snapshot lifecycle and offsite sends."
sensitivity: public
created: 2026-03-29
updated: 2026-06-04
---

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

### Drive-swap safety (ADR-023)

Urd's drive-rotation pattern (swapping LUKS-encrypted BTRFS drives in the IcyBox dock) was pinning `/dev/mapper/luks-<UUID>` via recursive bind mounts in the monitoring stack. ADR-023 resolves this by putting `cadvisor` and `node_exporter` on `rshared` propagation so host unmounts propagate into the containers. Any future container that bind-mounts host paths reaching `/run/media` must follow the same pattern.

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
| `backup_snapshot_count` | gauge | `subvolume`, `location` | `ExternalBackupMissing` alert (external == 0, gated by `backup_external_expected`) |
| `backup_duration_seconds` | gauge | `subvolume` | `BackupSlowDuration` alert (> 1h) |
| `backup_send_type` | gauge | `subvolume` | Grafana dashboard |
| `backup_external_drive_mounted` | gauge | — | Grafana dashboard |
| `backup_external_free_bytes` | gauge | — | Grafana dashboard |
| `backup_subvolume_churn_bytes_per_second` | gauge | `subvolume` | `backup-health` Grafana dashboard (added Urd v0.16, [UPI 030](https://github.com/vonrobak/urd/pull/108)) |
| `backup_subvolume_last_full_send_bytes` | gauge | `subvolume` | `backup-health` Grafana dashboard (added Urd v0.16, [UPI 030](https://github.com/vonrobak/urd/pull/108)) |
| `backup_external_expected` | gauge | `subvolume` | `ExternalBackupMissing` gate (== 1; line absent = local-only by design). Urd [PR #145](https://github.com/vonrobak/urd/pull/145) |
| `backup_pool_free_bytes` | gauge | `uuid`, `role`, `label` | `BackupDestinationPoolSpace{Warning,Critical}` numerator (role=destination); pool gauges (UPI 043) |
| `backup_pool_total_bytes` | gauge | `uuid`, `role`, `label` | `BackupDestinationPoolSpace{Warning,Critical}` denominator (role=destination). Urd [PR #145](https://github.com/vonrobak/urd/pull/145) |
| `backup_pool_metadata_utilization_ratio` | gauge | `uuid`, `role`, `label` | `BackupPoolMetadataExhaustion` alert (> 0.95) (UPI 043) |

**Drift telemetry (Urd v0.16+).** Urd computes a rolling time-windowed churn rate per
subvolume from `wire_bytes` of recent successful sends, and emits two gauges:

- `backup_subvolume_churn_bytes_per_second` — present for subvolumes whose latest
  in-window send was incremental. Absent for cold-start subvolumes and for subvolumes
  whose latest in-window send was a full send.
- `backup_subvolume_last_full_send_bytes` — present for subvolumes whose latest
  in-window send was a full send (e.g. transient or storage-critical subvolumes that
  re-baseline). Absent otherwise.

The two are mutually exclusive by design: a subvolume has either a churn rate (last
send was incremental) or a last-full-send size (last send was a full send), never both.

Two panels in the `backup-health` Grafana dashboard surface these gauges for capacity
planning: a churn-rate timeseries (per-subvolume) and a last-full-send-size barchart.
No alerts consume these yet — thresholds will be defined once enough data has
accumulated to establish per-subvolume baselines (target: ~2–4 weeks post-deployment).

### File paths

| Path | Purpose |
|------|---------|
| `~/.config/urd/urd.toml` | Urd configuration |
| `~/.local/share/urd/urd.db` | SQLite run history |
| `~/.local/share/urd/heartbeat.json` | Health signal — read by Urd's own Sentinel daemon. **Not consumed by the homelab.** See note below. |
| `~/containers/data/backup-metrics/backup.prom` | Prometheus metrics (shared with homelab) |
| `~/containers/data/backup-logs/` | Log directory |

**On `heartbeat.json`.** The heartbeat is an internal Urd contract between its nightly
runner and the Sentinel daemon. The homelab consumes Urd state exclusively through the
Prometheus textfile (`backup.prom`); there is no JSON parser on this side and none is
planned. Urd versions the heartbeat schema (`schema_version`, currently `3` as of UPI
030) for its own internal evolution. If a future homelab feature ever needs to read the
heartbeat directly, add a new ADR entry covering the parser's schema tolerance — do not
quietly take a dependency on the JSON shape.

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

## Amendment 2026-05-16 (Urd UPI 043): pool-observability metrics + heartbeat v4

Urd UPI 043 adds pool-level observability as additive on-disk contracts: four new
Prometheus gauges and a heartbeat schema bump v3 → v4 (additive only). The Urd-side
canonical text is the Amendment 2026-05-15 (UPI 043) section of Urd ADR-105
(`~/projects/urd/docs/00-foundation/decisions/2026-03-24-ADR-105-backward-compatibility-contracts.md`).
This amendment mirrors it from the homelab consumer side.

The Urd PR for UPI 043 is gated on this amendment merging on the homelab side
(Urd plan R7 cross-repo interlock).

### New Prometheus metrics (additive; existing metrics unchanged)

All four gauges arrive in `~/containers/data/backup-metrics/backup.prom` at the
next Urd run after UPI 043 ships. Existing alerts and dashboard panels are
unaffected — no alert or dashboard widget currently references these names.

| Metric | Labels | Cadence / shape | Homelab use |
|--------|--------|-----------------|-------------|
| `backup_pool_free_bytes` | `uuid`, `role`, `label` | Snapshot per backup run. `role ∈ {source, destination}`. Identity is `uuid`; `label` is informational (drive label for destinations, canonical mountpoint for sources). | **Consumed since 2026-05-25 (PR #145 amendment, below):** numerator of `BackupDestinationPoolSpace*` (role=destination); also a `backup-health` pool gauge. |
| `backup_pool_metadata_utilization_ratio` | `uuid`, `role`, `label` | 0.0–1.0 from `/sys/fs/btrfs/<uuid>/allocation/metadata/`. Covers source and destination pools. | **Consumed since 2026-05-25 (PR #145 amendment, below):** `BackupPoolMetadataExhaustion` (> 0.95); also a `backup-health` gauge. |
| `backup_subvolume_local_snapshot_count` | `subvolume` | Line **absent** when local snapshots are not configured for the subvolume. Coexists with the legacy `backup_snapshot_count{subvolume,location="local"}` — same physical fact, different contract shape (`Option::None`-as-absent vs. always-present). | **Not yet consumed.** Existing dashboards continue to use `backup_snapshot_count{location="local"}`. |
| `backup_subvolume_estimated_local_pinned_delta_bytes` | `subvolume` | Wire-bytes-derived estimate (mean over in-window incrementals × local snapshot count). Emit policy: `Some(0)` when local snapshots disabled or `local_snapshot_count == 0` (known zero, distinct from unknown); line **absent** in cold-start (`local_snapshot_count > 0` and `mean_incremental_bytes` unknown). | Primarily a UPI 044 input (headroom-aware retention recommendations, downstream Urd work). **Not yet consumed.** |

The single-drive global `backup_external_free_bytes` is unchanged — sacred under
ADR-105. The new per-pool `backup_pool_free_bytes` is additive, not a rename.

### Heartbeat schema v4 (informational — no homelab consumer)

Urd bumps `~/.local/share/urd/heartbeat.json` from `schema_version: 3` to
`schema_version: 4`. Additions are strict-additive over v3:

- Two new top-level fields:
  - `pools: Vec<PoolHeartbeat>` — deduplicated BTRFS pools (source + mounted destinations).
  - `drives: Vec<DriveHeartbeat>` — configured destination drives, mounted or not.
- Three new per-subvolume fields:
  - `pool_uuid: Option<String>` — joins the subvolume to a `PoolHeartbeat` by UUID; `None` when pool detection failed.
  - `local_snapshot_count: Option<u32>` — `Some(_)` iff local snapshots are configured for the subvolume.
  - `estimated_local_pinned_delta_bytes: Option<u64>` — same emit policy as the Prometheus metric above (`Some(0)` for known zero; `None` for cold-start).

All new fields use `#[serde(default, skip_serializing_if = …)]` on the Urd side,
so an older reader (v3-aware) parsing a v4 payload sees the new fields as unknown
keys and ignores them, and a v4 reader parsing a v3 payload gets empty vecs and
`None` for the new fields.

**The homelab still consumes Urd state exclusively through the Prometheus
textfile** (`backup.prom`). The position recorded in the original "On
`heartbeat.json`" note above is unchanged: there is no homelab-side parser for
`heartbeat.json`, and none is planned. A v3-reader-on-v4-payload tolerance test
in this repo would have nothing to exercise; the equivalent test on the Urd side
(`heartbeat_v3_reader_tolerates_v4_unknown_fields` in `src/heartbeat.rs`) is the
load-bearing one. A v4 sample payload is checked in at
`docs/00-foundation/decisions/fixtures/urd-heartbeat-v4-sample.json` as a
manual tolerance fixture (Urd plan R-cross-repo-1 escape) and as a
forward-compatibility seed for any future homelab parser. The fixture parses as
valid JSON under stdlib `json.load`; that is the entire current acceptance test.

### Heartbeat contract softening (Urd-side wording change)

The v3 heartbeat contract in Urd ADR-105 said: *consumers MUST check
`schema_version` and refuse to interpret fields from a higher version.* The v4
contract softens this to: *consumers SHOULD check version; MAY refuse.* Additive
bumps are forward-compatible by serde default; **field removal** still requires
an ADR-105 amendment and a major schema bump.

This softening has no behavioral effect on the homelab because there is no
heartbeat consumer on this side, but it makes the cross-repo R7 interlock
contractually meaningful: it explicitly licenses the kind of additive bump that
a v3-aware homelab parser would tolerate by default if one is ever added.

### Verification done before merging this amendment

- Audited `config/prometheus/alerts/*.yml` and
  `config/grafana/provisioning/dashboards/json/backup-health.json`: no alert or
  dashboard widget references any of the four new metric names or any v3
  heartbeat field that v4 changes. New gauges are additive; pre-existing
  `backup_snapshot_count{location="local"}` is preserved as the dashboard's
  local-snapshot source of truth.
- Manual JSON parse of the v4 fixture passes:
  `python3 -c "import json; json.load(open('docs/00-foundation/decisions/fixtures/urd-heartbeat-v4-sample.json'))"`.

### Dashboard surfacing — deferred

Surfacing `backup_pool_free_bytes` and `backup_pool_metadata_utilization_ratio`
as a "BTRFS pool health" panel in the `backup-health` Grafana dashboard, and
deciding whether to swap `backup_snapshot_count{location="local"}` for the new
`backup_subvolume_local_snapshot_count` in existing widgets, are UX choices and
sit outside the contract change recorded by this amendment. Track as a separate
follow-up issue.

## Amendment 2026-05-25 (Urd PR #145): expected-external + pool-total metrics, now consumed

Backup-observability Plan C (`docs/97-plans/2026-05-25-backup-observability.md`) needed two
gaps closed that only Urd can fill. Urd PR #145 (`feat/external-expected-and-pool-total`) adds
both as additive, ADR-105-safe gauges. This amendment registers them and records that several
previously-"Not yet consumed" metrics now back live alerts.

### New Prometheus metrics (additive; existing metrics unchanged)

Both arrive in `backup.prom` at the **next `urd backup` run after PR #145 merges** — they do
not exist until then (alerts that reference them are inert, returning no series, until first
emission; see deploy-ordering note below).

| Metric | Labels | Cadence / shape | Homelab use |
|--------|--------|-----------------|-------------|
| `backup_external_expected` | `subvolume` | `1` iff the subvolume has an external destination configured (`send_enabled` AND ≥1 drive in scope); **line absent otherwise**. Same `subvolume` key as `backup_snapshot_count`. | **Consumed** by `ExternalBackupMissing`, which now gates on `… and on(subvolume) backup_external_expected == 1`. Removes the `subvol6-tmp` false positive (local-only by design, `send_enabled=false`). |
| `backup_pool_total_bytes` | `uuid`, `role`, `label` | Total capacity (statvfs), same key as `backup_pool_free_bytes`; free+total read in one statvfs pass so they never skew within a run. Snapshot per backup run. | **Consumed** by `BackupDestinationPoolSpace{Warning,Critical}` (`free/total` on `role="destination"`) — node_exporter cannot see the offsite drive (ADR-023), so the total must come from Urd. |

### Consumption status change (UPI-043 metrics)

`backup_pool_metadata_utilization_ratio` is now **consumed** by `BackupPoolMetadataExhaustion`
(`> 0.95`, all roles). `backup_pool_free_bytes{role="destination"}` is consumed as the numerator
above. Source-pool free-% (`/`, `/mnt`) is intentionally **not** taken from Urd — node_exporter
covers those live and continuously, whereas Urd's pool gauges refresh only once per nightly run
(`urd-sentinel` never writes `backup.prom`). Treat all `backup_pool_*` values as up to ~24h stale.

### Deploy ordering (load-bearing)

`ExternalBackupMissing`'s join is empty until `backup_external_expected` is live, which **fully
suppresses the alert (real misses included)** in the interim. Deploy the homelab alert changes
only after PR #145 is merged and one `urd backup` run has emitted the new series. A break-glass
fallback (`backup_snapshot_count{location="external",subvolume!="subvol6-tmp"} == 0`) is recorded
inline in `backup-alerts.yml` for shipping earlier.

### Follow-up (not in this amendment)

`backup_external_free_bytes` is legacy, superseded by `backup_pool_free_bytes{role="destination"}`
(+ total) but still an ADR-105 backward-compat contract — its deprecation is a separate
coordinated change. Dashboard surfacing (Plan C item 5) remains the deferred UX follow-up noted
under UPI-043.

## Amendment 2026-06-04 (Urd CLI output contract: documented, not consumed)

Urd's v0.13.0 CHANGELOG (2026-04-21) closes its `notes`-channel entry with *"see the homelab
ADR-021 update for future JSON-consumer precedent."* That update was drafted on 2026-04-20 but
never merged; this amendment lands it, **re-verified against the current Urd release (v0.24.0,
2026-06-03)** rather than the v0.13.0 it was first written for. Like the "On `heartbeat.json`"
note above, it records a deliberate *non-consumption* boundary — so it is in scope even though
CLI output is not one of the five "Keeping This ADR Current" triggers. The point is precisely to
record that the homelab does **not** depend on this surface, and what a future consumer would
have to do.

### The boundary

The homelab consumes Urd state **exclusively through the Prometheus textfile** (`backup.prom`)
and the alerts and dashboards built on it. Urd's CLI text output (`urd status` / `urd backup` /
`urd`) and its machine-readable JSON form are **not parsed by any homelab script or alert, and
none is planned.** This is also the direction Urd itself points consumers: its reference docs
classify CLI output as non-contractual and steer monitoring to the heartbeat and Prometheus
metrics instead (`~/projects/urd/docs/20-reference/cli.md` §Output mode, §Stability classes —
*"prefer the heartbeat … and metrics … over parsing CLI output"*). Nothing below is a dependency —
it is precedent for a hypothetical future consumer.

### Output channels (`BackupSummary`)

`urd backup` produces a `BackupSummary` (`~/projects/urd/src/output.rs`) with two parallel
human-facing string arrays:

| Channel | Type | Meaning |
|---------|------|---------|
| `warnings` | `[]string` | Problems the operator may need to act on (pin failures, partial sends, skipped operations that matter). |
| `notes` | `[]string` | By-design informational outcomes that need no action — e.g. the storage guard deliberately retaining snapshots. Added in Urd v0.13.0; the rationale is **Urd ADR-113 (do-no-harm invariant)** — when the guard holds a planned deletion to avoid storage pressure, that is a success, not a warning. |

Both fields have been stable in shape through v0.24.0 *in practice* (the UPI 053 `PromiseStatus`
refactor left the serialized form unchanged) — but that is observation, not a guarantee. Urd offers
**no backward-compatibility contract** on this surface; see **Stability & canonical source** below.

### JSON shape (no `--json` flag on backup/status)

`urd backup` / `urd status` have **no `--json` flag** — they emit JSON only when stdout is **not**
a TTY (`OutputMode::Daemon`, via `is_terminal()` in `src/output.rs`), at which point `BackupSummary`
is serialized with serde. (The one literal `--json` flag in Urd is on the separate `urd events`
command, itself classified non-contractual — so the surface here is genuinely flag-less.) `warnings`
and `notes` are **always serialized**: neither carries `skip_serializing_if`, so both keys are
**always present, rendered as `[]` when empty** (unlike the sibling `transitions` field, which *is*
omitted when empty). A consumer may therefore rely on the *keys* existing as arrays, but **not** on
their values, ordering, or string content. (The original 2026-04-20 draft claimed a bare `--json`
flag and empty-omission; both were wrong and are corrected here.)

### v0.13.0 semantic narrowing (UPI 026 "trust-repair")

In v0.13.0 the cleanup outcome moved from `warnings` to `notes`: the old `"Space recovered — N
skipped deletion(s)"` warning is now the note `"space guard held — N snapshot(s) retained."` A
future consumer that counts items in `warnings` should treat this narrowing as **already in
effect** (it shipped 2026-04-21), not as a pending change. No homelab alert is affected — none
parses this surface.

### Post-upgrade acknowledgment (historical one-shot)

v0.13.0 also prepends a one-time line to `urd status` / `urd backup` / `urd` for returning users
whose previously-`blocked` subvolumes became `healthy` (marker `trust-repair-v0_13_0`, gated on
prior run history; fresh installs see nothing). It fires at most once per user. It is **never a
JSON field**, but — a sharp edge worth recording — the preamble is prepended **unconditionally; it
is not gated on output mode** (`src/commands/acknowledgment.rs`), so on its single firing in daemon
(non-TTY) mode it would emit a raw text line *ahead of* the JSON document, making that one output
non-parseable. On this host it was consumed months ago (inert since), so this is harmless today; it
is recorded so a future JSON consumer knows the preamble is **not** output-mode-safe. (Urd-side fix
tracked separately — see the note in the PR thread.)

### Stability & canonical source

**Stability — the decision-critical point.** `warnings` / `notes` ride on Urd's **Daemon (non-TTY)
JSON output**, which Urd explicitly classifies as *internal, additive-evolution, with **no formal
backward-compatibility contract*** — the opposite of the ADR-105-grade guarantee the Prometheus
metrics carry. Urd's reference docs say so directly and steer consumers elsewhere: *"Daemon JSON
output — Internal … no formal contract. Use heartbeat / metrics for monitoring"* and *"Interactive
(TTY) text format — Evolving. Do not parse."* (`~/projects/urd/docs/20-reference/cli.md` §Stability
classes, §Output mode). A future homelab parser **MUST** treat the shape as volatile and **MUST
NOT** rely on field ordering or string content; it **MAY** rely only on the `warnings` / `notes`
keys being present as (possibly empty) arrays.

**Canonical source.** The authoritative contract for this surface is Urd's
**`docs/20-reference/cli.md`** (§Output mode + §Stability classes) — **not** ADR-105 and **not**
ADR-113. ADR-105 governs only four *on-disk* formats — snapshot names, directory layout, pin files,
and Prometheus textfile metrics — and **expressly places presentation-layer output out of scope**
(Urd ADR-105 Amendment 2026-05-15). The metrics this homelab *does* consume ride on that ADR-105
contract; these CLI channels do not. Provenance and rationale, not stability: UPI 026 (Trust Repair,
`docs/95-ideas/2026-04-20-design-026-trust-repair.md`) + CHANGELOG `[0.13.0]` **introduced** the
channels, and **ADR-113 (do-no-harm)** is the **rationale** for routing space-guard retention to
`notes` rather than `warnings` — none of the three is a contract. (The 2026-04-20 draft cited
ADR-105 as the contract authority; that was wrong on two counts — ADR-105 doesn't cover this
surface, *and* the real authority is `cli.md` — both corrected here.) If the homelab ever adds a
parser for this surface, add an ADR-021 entry recording the schema-tolerance assumptions **first** —
do not quietly take a dependency on the shape, exactly as stated for `heartbeat.json` above.

## Related
- **ADR-020:** Daily external backups (strategy — still valid, implementation superseded)
- **Urd project:** `~/projects/urd/` — CLAUDE.md, ADRs 100–111, status.md
- **Urd design plan:** `docs/00-foundation/decisions/2026-03-23-urd-btrfs-time-machine-design.md`
- **Urd ADR-105 Amendment 2026-05-15 (UPI 043):** canonical pool-observability + heartbeat v4 contract text.
- **Urd [PR #145](https://github.com/vonrobak/urd/pull/145):** canonical source for `backup_external_expected` + `backup_pool_total_bytes` (Urd CHANGELOG `[Unreleased]`).
- **Urd `docs/20-reference/cli.md` (§Output mode, §Stability classes):** canonical contract for the `warnings`/`notes` CLI output channels — classified *no formal contract* (Amendment 2026-06-04). UPI 026 design + CHANGELOG `[0.13.0]` = provenance; Urd ADR-113 (do-no-harm) = `notes`-routing rationale.
- **Backup alerts:** `config/prometheus/alerts/backup-alerts.yml`
- **Node exporter integration:** `quadlets/node_exporter.container` (textfile collector mount)
