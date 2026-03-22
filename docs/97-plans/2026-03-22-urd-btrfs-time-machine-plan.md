# Urd: BTRFS Time Machine for Linux

## Context

The homelab's backup system is a 1710-line bash script (`scripts/btrfs-snapshot-backup.sh`) that has been patched through three major incidents. It works but has reached its maintainability limit. The 2026-03-22 journal entry documents a critical audit (15 issues found) and recommends Option C: a purpose-built tool replacing the bash script entirely.

**Name:** Urd — the Norse norn who tends the Well of Urd and knows all that has passed.

**Ambition:** Build a distributable "Time Machine for BTRFS on Linux" that starts as a homelab tool and grows into something others can use.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | **Rust** | Distributable binary, type safety, no runtime deps. Bash script covers us while we build. |
| Drive detection | **udev-first** | True Time Machine behavior. Scheduled fallback (02:00) as nice-to-have for large ops. |
| Execution model | **Hybrid** | Triggered service for backups + small persistent sentinel for drive monitoring/notifications. |
| State management | **SQLite + TOML** | TOML config (what to back up), SQLite state (what has been backed up). Clean separation. |
| CLI name | **`urd`** | `urd status`, `urd backup`, `urd verify`, `urd history` |
| Project location | **`~/projects/urd`** | Separate git repo, own Cargo workspace. |
| Notifications | **Deferred** | Build after core is battle-tested. Desktop (notify-send) + Discord for critical. |

## Project Structure

```
~/projects/urd/
  Cargo.toml
  src/
    main.rs               # CLI entry point (clap), dispatches to commands
    cli.rs                 # Clap command/argument definitions
    config.rs              # TOML config loading, validation, defaults
    types.rs               # Core domain types: Subvolume, Drive, Tier, Schedule, Snapshot
    plan.rs                # Backup planner: reads state, decides operations (pure logic)
    executor.rs            # Executes planned operations (snapshot, send, receive, delete)
    btrfs.rs               # Low-level btrfs command wrappers (trait-based for testing)
    retention.rs           # Retention engine (graduated + count-based)
    chain.rs               # Incremental chain tracking (pin files, parent resolution)
    state.rs               # SQLite state database (history, run records)
    metrics.rs             # Prometheus .prom file writer (atomic tmp+rename)
    drives.rs              # External drive detection (mount check, space via statvfs)
    sentinel.rs            # Drive monitor daemon (Phase 5)
    error.rs               # Error types (thiserror)
    commands/
      mod.rs
      backup.rs            # `urd backup`
      status.rs            # `urd status`
      verify.rs            # `urd verify`
      history.rs           # `urd history`
      plan_cmd.rs          # `urd plan` (dry-run planning)
      init.rs              # `urd init` (state import)
  config/
    urd.toml.example       # Reference config
  systemd/
    urd-backup.service     # Oneshot backup service
    urd-backup.timer       # Nightly fallback timer
    urd-sentinel.service   # Drive monitor (Phase 5)
  udev/
    99-urd-backup.rules    # Drive plug events (Phase 5)
  tests/
    integration/           # Tests requiring 2TB-backup drive (#[ignore])
  README.md
  LICENSE
```

## Configuration Schema (TOML)

Location: `~/.config/urd/urd.toml`

```toml
[general]
state_db = "~/.local/share/urd/urd.db"
metrics_file = "~/containers/data/backup-metrics/backup.prom"
log_dir = "~/containers/data/backup-logs"

[local_snapshots]
roots = [
  { path = "~/.snapshots", subvolumes = ["htpc-home", "htpc-root"] },
  { path = "/mnt/btrfs-pool/.snapshots", subvolumes = [
    "subvol1-docs", "subvol2-pics", "subvol3-opptak",
    "subvol4-multimedia", "subvol5-music", "subvol6-tmp", "subvol7-containers"
  ]}
]

[[drives]]
label = "WD-18TB"
mount_path = "/run/media/patriark/WD-18TB"
snapshot_root = ".snapshots"
role = "primary"

[[drives]]
label = "WD-18TB1"
mount_path = "/run/media/patriark/WD-18TB1"
snapshot_root = ".snapshots"
role = "offsite"

[[drives]]
label = "2TB-backup"
mount_path = "/run/media/patriark/2TB-backup"
snapshot_root = ".snapshots"
role = "test"

[[subvolumes]]
name = "htpc-home"
short_name = "htpc-home"
source = "/home"
tier = 1
local_schedule = "daily"
external_schedule = "daily"
external_retention = 14

[[subvolumes]]
name = "subvol3-opptak"
short_name = "opptak"
source = "/mnt/btrfs-pool/subvol3-opptak"
tier = 1
local_schedule = "daily"
external_schedule = "daily"
external_retention = 14

# ... (all 9 subvolumes, see full config in urd.toml.example)

[retention.graduated]
daily_keep = 14
weekly_keep = 6
monthly_keep = 3
```

## Architecture: Key Design Principles

### 1. Planner/Executor Separation (most important)

The planner is a **pure function**: `fn plan(config, state, now, filters) -> BackupPlan`. It produces a list of `PlannedOperation` variants:

```rust
enum PlannedOperation {
    CreateSnapshot { source, dest },
    SendIncremental { parent, snapshot, dest_dir, drive },
    SendFull { snapshot, dest_dir, drive },
    DeleteSnapshot { path, reason },
    PinParent { local_dir, snapshot_name, drive },
}
```

`urd plan` prints the plan. `urd backup --dry-run` prints it. `urd backup` executes it. The planner is fully unit-testable without touching any filesystem.

### 2. BtrfsOps Trait (testing seam)

```rust
pub trait BtrfsOps {
    fn create_readonly_snapshot(&self, source: &Path, dest: &Path) -> Result<()>;
    fn send_receive(&self, snapshot: &Path, parent: Option<&Path>, dest: &Path) -> Result<()>;
    fn delete_subvolume(&self, path: &Path) -> Result<()>;
    fn subvolume_show(&self, path: &Path) -> Result<SubvolumeInfo>;
}
```

`RealBtrfs` calls `sudo btrfs` via `std::process::Command`. `MockBtrfs` records calls for testing. This is the only module that shells out.

### 3. Never Lose Data, Always Continue

Individual subvolume failures do NOT abort the run. Failed sends trigger partial cleanup. Pin files are only updated on success. Exit code 1 if any subvolume failed, 0 if all succeeded/skipped.

### 4. Backward Compatibility

- Snapshot naming: `YYYYMMDD-shortname` preserved exactly
- Directory structure: same locations as bash script
- Pin files: `.last-external-parent-{DRIVE_LABEL}` format preserved (read+write)
- Prometheus metrics: identical names, labels, value semantics

## SQLite Schema

```sql
CREATE TABLE runs (
    id INTEGER PRIMARY KEY,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    mode TEXT NOT NULL,        -- "full", "local-only", "external-only", "dry-run"
    result TEXT NOT NULL       -- "success", "partial", "failure"
);

CREATE TABLE operations (
    id INTEGER PRIMARY KEY,
    run_id INTEGER REFERENCES runs(id),
    subvolume TEXT NOT NULL,
    operation TEXT NOT NULL,   -- "snapshot", "send_incremental", "send_full", "delete", "pin"
    drive_label TEXT,
    duration_secs REAL,
    result TEXT NOT NULL,      -- "success", "failure", "skipped"
    error_message TEXT,
    bytes_transferred INTEGER
);

CREATE TABLE snapshots (
    id INTEGER PRIMARY KEY,
    subvolume TEXT NOT NULL,
    name TEXT NOT NULL,        -- "20260322-opptak"
    location TEXT NOT NULL,    -- "local" or drive label
    path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    is_pinned INTEGER DEFAULT 0,
    UNIQUE(subvolume, name, location)
);
```

## CLI Commands

```
urd backup [--dry-run] [--local-only] [--external-only] [--tier N] [--subvolume NAME] [--verbose]
urd plan   [same filters as backup]     # Print planned operations without executing
urd status                              # Drives, chain health, snapshot counts, last run
urd history [--subvolume X] [--last N] [--failures]
urd verify  [--subvolume X] [--drive LABEL]  # Chain integrity, pin file validation
urd init                                # First-run: create config, import existing state
```

`urd status` example output:
```
SUBVOLUME          LOCAL  WD-18TB  WD-18TB1  LAST SEND    CHAIN
htpc-home          15     14       12        2h ago       incremental
subvol3-opptak     15     1        0         6h ago       full (new)
subvol7-containers 15     2        1         23h ago      incremental

Drives: WD-18TB1 mounted (4.4TB free / 17TB)
Next scheduled: subvol2-pics in 5d (Saturday)
```

## Rust Crates

| Crate | Purpose |
|-------|---------|
| `clap` 4.x | CLI with derive macros |
| `serde` + `toml` | Config parsing |
| `rusqlite` (bundled) | SQLite state DB |
| `chrono` | Date/time, ISO week calc |
| `thiserror` + `anyhow` | Error handling |
| `nix` | statvfs for disk space |
| `colored` | Terminal colors |
| `tabled` | Table formatting for status/history |
| `dirs` | XDG directory resolution |
| `log` + `env_logger` | Structured logging |
| `udev` | Phase 5: drive monitoring |

**Not using:** tokio/async (unnecessary for sequential I/O-bound btrfs ops).

## Implementation Phases

### Phase 1: Skeleton + Config + Plan (Sessions 1-2)

**Goal:** `urd plan` reads config, discovers real snapshots, prints correct planned operations.

- Install Rust toolchain
- `cargo init`, add dependencies
- `config.rs` — TOML parsing, validation, tilde expansion
- `types.rs` — All domain types (Tier, Schedule, SnapshotName, PlannedOperation)
- `cli.rs` — clap setup
- `plan.rs` — planner logic (schedule checking, snapshot discovery, parent resolution)
- `chain.rs` — pin file reading
- `retention.rs` — graduated + count-based retention (pure functions)
- `commands/plan_cmd.rs` — wire up `urd plan`
- Unit tests for config, retention, plan

**Deliverable:** `urd plan` on live system matches what bash script would do.

### Phase 2: Execute + State + Metrics (Sessions 3-4)

**Goal:** `urd backup` creates snapshots, sends to 2TB-backup, manages retention, writes metrics.

- `btrfs.rs` — RealBtrfs + MockBtrfs implementations
- `executor.rs` — sequential operation execution with error handling + partial cleanup
- `state.rs` — SQLite schema, run/operation recording
- `metrics.rs` — Prometheus .prom writer (exact format match)
- `drives.rs` — drive detection, space checks via statvfs
- `chain.rs` — pin file writing
- `commands/init.rs` — `urd init` (import existing snapshots/pin files)
- `commands/backup.rs` — `urd backup` (planner + executor)
- Integration tests on 2TB-backup drive

**Deliverable:** Successful backup cycle to test drive. `urd backup --dry-run` on production matches bash.

### Phase 3: CLI + Parallel Run (Sessions 5-6)

**Goal:** Full CLI, parallel running with bash script for validation.

- `commands/status.rs` — mounted drives, chain health, snapshot counts, last run
- `commands/history.rs` — SQLite queries, formatted table
- `commands/verify.rs` — chain integrity, pin file validation
- Create systemd units (urd-backup.service + timer)
- Parallel run: Urd at 02:00, bash at 03:00
- Compare Prometheus metrics between both systems
- Fix behavioral differences

**Deliverable:** Both systems running nightly with equivalent results.

### Phase 4: Cutover + Polish (Session 7)

**Goal:** Urd is sole backup system.

- Disable bash script timer, enable urd-backup.timer
- Colored terminal output
- Error message quality pass
- `--help` polish
- Write ADR-021 for the migration
- Archive bash script to `scripts/archive/`

### Phase 5: Sentinel + udev (Session 8, deferred)

**Goal:** Automatic backup on drive plug-in.

- `sentinel.rs` — udev event listener, debounce (wait for LUKS+mount)
- `urd-sentinel.service` — persistent user service
- udev rules for WD-18TB drives
- Desktop notification hooks (infrastructure only — notification system built separately)

## Migration Strategy

1. **`urd init`** scans existing snapshot directories, reads pin files, populates SQLite
2. **Parallel running** (2 weeks): Urd at 02:00, bash at 03:00, compare metrics
3. **Cutover:** disable bash timer, enable Urd timer, monitor 1 week
4. Pin file format maintained throughout — both systems can coexist

## Testing Prerequisites

**Sudoers entries needed for 2TB-backup drive** (user must add manually):
```
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete /run/media/patriark/2TB-backup/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive /run/media/patriark/2TB-backup/.snapshots/*
```

Existing `btrfs send *` and `btrfs subvolume snapshot -r` entries cover the local side.

## Verification Plan

After each phase:

1. **Phase 1:** `urd plan` output matches manual calculation of what bash script would do for the same date/drive state
2. **Phase 2:** Successful backup to 2TB-backup drive. Restore a file from the backup and verify byte-for-byte match. `backup.prom` output matches format exactly.
3. **Phase 3:** After 2 weeks parallel run, diff Prometheus metrics between Urd and bash script runs. All subvolumes, all drives, all metrics must match.
4. **Phase 4:** One week of sole Urd operation with no intervention. Grafana dashboards show continuity.
5. **Phase 5:** Plug in test drive, verify backup starts within 60 seconds.

## Critical Files Reference

- `~/containers/scripts/btrfs-snapshot-backup.sh` — behavior to match
- `~/containers/data/backup-metrics/backup.prom` — metrics format to reproduce
- `~/.config/systemd/user/btrfs-backup-daily.service` — systemd patterns to follow
- `~/.snapshots/htpc-home/.last-external-parent-WD-18TB1` — pin file format
- `/etc/sudoers.d/btrfs-backup` — scope constraints for btrfs commands
