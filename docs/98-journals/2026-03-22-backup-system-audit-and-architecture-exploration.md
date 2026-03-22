# 2026-03-22: BTRFS Backup System — Critical Audit and Architecture Exploration

## Context

Following the 2026-03-21 operational excellence revision, tonight's 02:00 backup run
surfaced new failure modes. subvol3-opptak failed with insufficient space for a full send
(needed 3189GB, had 3076GB), and the resulting exit code 1 triggered systemd's
`Restart=on-failure`, causing infinite crash-loops on a permanently unrecoverable error.

Manual intervention was required to:
1. Stop the crash-looping service (`systemctl --user stop btrfs-backup-daily.service`)
2. Free space on WD-18TB1
3. Run the backup manually — but `--subvolume subvol3-opptak` silently did nothing
   (the filter expects the short name `opptak`, not `subvol3-opptak`)
4. Re-run with `--subvolume opptak`, which succeeded after ~6 hours

This incident motivated a full critical audit of the script and its operational readiness
for serving as the foundation of a 3-2-1 backup strategy.

---

## Audit Findings

### What the script does well

- Tiered backup strategy with clear priority levels and separate schedules
- Graduated Time Machine-style local retention (14 daily + 6 weekly + 3 monthly)
- Drive-specific pin files supporting offsite rotation between WD-18TB and WD-18TB1
- Pinned parent protection during cleanup (incremental chain anchors survive retention)
- Partial receive cleanup on send/receive failure
- PIPESTATUS capture for the send|receive pipeline (detects failures on either side)
- Prometheus metrics export with atomic move (no partial reads)
- Dry-run mode for safe testing
- Nice/ionice scheduling to avoid impacting the system
- Monthly automated restore testing via `test-backup-restore.sh`

### Critical issues (will cause data loss or silent failure)

#### C1: `--subvolume` accepts wrong names — silent no-op

The filter on line 1616-1648 matches against short names (`opptak`, `home`, `containers`,
`docs`, `root`, `pics`, `multimedia`, `music`, `tmp`). But `--help` says
`--subvolume <name>` with no guidance on what `<name>` means. The config section uses
full names like `subvol3-opptak`. The log output says "Processing Tier 1: subvol3-opptak".

A backup tool that silently does nothing on unrecognized input is dangerous. The user
ran `--subvolume subvol3-opptak`, saw a clean summary, and assumed it worked. Only by
noticing the 0-second runtime did they catch the problem.

#### C2: Crash-loop on non-transient failure

`Restart=on-failure` with `RestartSec=30min` and no `StartLimitBurst`/`StartLimitIntervalSec`.
Tonight's space shortage is a permanent condition — retrying every 30 minutes is pointless.
The service restarts indefinitely until the next calendar day resets the state file (because
succeeded subvols get skipped but the failed one keeps failing). This also means systemd
reports the unit as perpetually "activating (auto-restart)", which poisons monitoring dashboards
and makes `systemctl --user status` misleading.

#### C3: State file in `/tmp` with no locking

`STATE_DIR="/tmp"` — the state file is world-readable in a shared directory with no file
locking. Two concurrent runs (manual + timer restart, or daily + weekly on Saturday at
close timing) will race on `echo >> $STATE_FILE` appends. Worse: because `set -euo pipefail`
is set, a corrupted state file could cause `grep` to behave unexpectedly.

More subtly: on Fedora, `/tmp` is tmpfs. A reboot mid-backup loses completed-today state.
This is actually fine (re-running after reboot is safe), but the lack of locking is not.

#### C4: No post-send integrity verification

After a 6-hour send of 3.2TB over USB, there's zero verification that the received snapshot
is complete and valid. No `btrfs scrub`, no file-count comparison, no checksum spot-check.
A truncated USB transfer or silent write error means you have a backup entry that isn't
actually restorable. The monthly `test-backup-restore.sh` catches this eventually, but for
Tier 1 data with "heightened backup demands", monthly verification of a daily backup leaves
a 30-day window of false confidence.

#### C5: `find_common_parent` ignores the pin file

The `find_common_parent()` function (line 784-811) independently scans for the newest local
snapshot that also exists on the external drive. It does not consult the pin file written by
`pin_parent()`. If a bug or race deleted the pinned parent from external, this function
would silently pick a different parent. The `btrfs send -p` might succeed but produce a
snapshot outside the expected incremental chain — a subtle corruption that wouldn't surface
until a restore attempt.

### Serious issues (degrade reliability)

#### S1: Duplicate log output

Every log line prints twice — once via `tee -a` (timestamped to file + stdout) and once
via the colored `echo` (to stderr/stdout). The journal captures both. This makes log
parsing unreliable and doubles the noise.

#### S2: Two systemd units running the same script

`btrfs-backup-daily.timer` (02:00 every day) and `btrfs-backup-weekly.timer` (Sat 04:00)
both execute the same script with no arguments. On Saturdays at 04:00, the weekly run finds
the daily's state file and skips Tier 1/2, then runs Tier 3. But if the daily run is
crash-looping (as tonight), the 04:00 weekly run races with a 30-min delayed retry.

#### S3: Daily `TimeoutStartSec=2h` is too short

Tonight's opptak full send took 6+ hours. Had it run under the daily systemd service,
systemd would have SIGTERM'd it at the 2-hour mark. Full re-sends happen when the
incremental chain breaks — this is not a rare edge case.

#### S4: `eval` in `run_cmd`

`run_cmd` uses `eval "$cmd"` for command execution. While the inputs are currently safe
(constructed from known paths), this is a shell injection footgun waiting for the day
a snapshot name contains special characters.

#### S5: No mutual exclusion (no lock file)

Nothing prevents two instances from running simultaneously. Manual + timer + weekly =
potential triple execution.

### Moderate issues (operational friction)

#### M1: Prometheus metrics report success=1 for schedule-skipped items

When a subvolume is skipped because "not Saturday" or "not 1st of month", the script
records `success=1` in metrics. Monitoring cannot distinguish "backed up successfully"
from "didn't run today". A subvolume that hasn't run in 6 days still shows success=1.

#### M2: Discord webhook not configured

`[WARNING] No Discord webhook configured` — failures are completely silent unless
someone reads journalctl. For a 3-2-1 backup system protecting irreplaceable data,
this is a significant gap.

#### M3: ~500 lines of copy-pasted backup functions

Nine nearly identical `backup_tierN_X()` functions with the same structure. A data-driven
approach would be ~80 lines. This isn't a reliability issue today, but it's maintenance
debt that will cause bugs when the shared logic next needs updating.

#### M4: `du -sb` space estimation is unreliable on BTRFS

The fallback size estimation uses `du -sb`, which reports referenced data on BTRFS. The
actual send-stream size depends on shared extents, reflinks, and metadata overhead.
Tonight it estimated 3189GB and the actual was close — but for subvolumes with heavy
reflinks this could be off by 2x in either direction.

### Sudoers gap

The existing `/etc/sudoers.d/btrfs-backup` allows:
```
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *
```

Missing: `btrfs subvolume show` (used for space estimation) and `btrfs filesystem show`
(used for diagnostics). The log shows `pam_unix(sudo:auth): conversation failed` —
the script tries `sudo btrfs subvolume show` during space estimation, fails silently,
and falls back to `du -sb`. Adding these two commands to sudoers would improve the
space estimation accuracy significantly.

---

## Proposed Fixes (Current Script)

### Fix 1: Validate `--subvolume` input (Critical, Low Risk)

**Change:** Check `SUBVOL_FILTER` against a list of valid short names at parse time.
Print valid options and exit 1 on mismatch. Also accept full names (`subvol3-opptak`)
by stripping the `subvolN-` prefix.

**Risk:** Minimal. Only affects argument parsing. Existing behavior for valid names
is unchanged. The only risk is that an external script or cron job passes an unexpected
name — but that's exactly the bug we're fixing.

### Fix 2: Add `StartLimitBurst` to systemd service (Critical, Low Risk)

**Change:** Add `StartLimitBurst=3` and `StartLimitIntervalSec=6h` to the `[Unit]`
section of `btrfs-backup-daily.service`. After 3 failures in 6 hours, systemd stops
retrying and the unit enters `failed` state (which is monitorable).

**Risk:** Minimal. If a genuinely transient failure (USB hiccup) occurs 4 times in
6 hours, the backup won't retry until the next timer trigger. This is acceptable —
3 retries is generous for a nightly backup.

### Fix 3: Add `flock` mutual exclusion (Critical, Low Risk)

**Change:** Add `flock -n /tmp/btrfs-backup.lock ...` or use `ExecStart=/usr/bin/flock -n
/tmp/btrfs-backup.lock %h/containers/scripts/btrfs-snapshot-backup.sh` in the systemd unit.

**Risk:** Very low. If a manual run holds the lock, the timer-triggered run exits
immediately. This is correct behavior — you don't want two backup runs fighting over
the same external drive.

### Fix 4: Fix duplicate logging (Serious, Low Risk)

**Change:** Remove the second `echo` in the `log()` function. The `tee -a` already
writes to both stdout and the log file. Use colorized output only via tee.

**Risk:** Low. Log format changes — any external tooling that parses journal output
may need adjustment. But the current double output is the bug, not the fix.

### Fix 5: Bump daily `TimeoutStartSec` (Serious, Low Risk)

**Change:** Increase from `2h` to `12h` in `btrfs-backup-daily.service`. Full re-sends
of subvol3-opptak take 6+ hours. With growth headroom, 12h is safe.

**Risk:** Low. A hung backup process would block for longer before being killed. But
the alternative (killing a valid 6-hour backup at 2 hours) is worse.

### Fix 6: Add post-send verification (Critical, Medium Risk)

**Change:** After successful send|receive, compare file count and total size between
source snapshot and received snapshot. Flag mismatches as errors and don't pin the
parent.

**Risk:** Medium. Adds sudo commands (`btrfs subvolume show` on the received snapshot).
Could slow down the backup (walking the received snapshot on USB). False positives from
BTRFS metadata differences would cause unnecessary full re-sends. Needs careful
threshold tuning — exact byte match is too strict, but a 10% tolerance might miss
real corruption.

### Fix 7: Track "skipped" vs "success" in Prometheus (Moderate, Low Risk)

**Change:** Record `success=2` (or a separate metric) for schedule-skipped items.
Alert on `backup_success == 0` (failure) and `time() - backup_last_success_timestamp > 48h`
(stale).

**Risk:** Low. Changes metric semantics — existing Grafana dashboards and alert rules
would need updating, but since the current metrics don't drive alerts anyway, this is
a clean break.

### Fix 8: Expand sudoers for `btrfs subvolume show` and `btrfs filesystem` (Moderate, Low Risk)

**Change:** Add to `/etc/sudoers.d/btrfs-backup`:
```
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume show *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs filesystem show *
```

**Risk:** Low. These are read-only commands — `subvolume show` displays metadata,
`filesystem show` displays filesystem info. Neither modifies state. The wildcard on
path arguments follows the same pattern as the existing rules.

### Fix 9: Configure Discord webhook (Moderate, Low Risk)

**Change:** Set the `DISCORD_WEBHOOK` env var or populate the webhook file that the
script already reads from.

**Risk:** Minimal. The notification code already exists and is tested. The only risk
is webhook URL exposure — keep it in a file outside git (already the pattern used).

### Fix 10: Wire `find_common_parent` to consult pin file first (Critical, Medium Risk)

**Change:** Modify `find_common_parent()` to first check `get_pinned_parent()`. If the
pinned parent exists on both local and external, use it. Only fall back to scanning if
the pin file is missing or the pinned snapshot was deleted.

**Risk:** Medium. Changes the parent selection logic for incremental sends. If the pin
file points to a snapshot that no longer exists on the external drive (e.g., it was
manually deleted), the function would fall back to scanning — same as today. But if
the pin file points to a snapshot that exists externally but is subtly different
(e.g., was recreated), the incremental send would fail. Safe in practice because
BTRFS checks UUID lineage during send, but warrants testing.

---

## Architecture Exploration: Time Machine-Style Autonomous Backups

The current script is a 1666-line bash program that has been patched reactively after
each incident. It works, but it was designed as a cron job with manual intervention
expected. The question is: can we build something that works like macOS Time Machine —
detect drive, snapshot, send, organize, clean up, all autonomously, without human
involvement?

### Design goals for an autonomous backup system

1. **Drive detection:** Automatically detect when a backup-enabled drive is connected
   (via udev), start backing up immediately, and stop cleanly when the drive is removed
2. **Space-aware retention:** Instead of fixed retention counts, dynamically adjust
   retention based on available drive space (keep as much history as fits)
3. **Incremental-first:** Always attempt incremental sends; fall back to full sends
   only when the chain is broken, with clear notification
4. **Integrity verification:** Post-send validation of every backup
5. **Idempotent:** Safe to run multiple times, safe to interrupt, safe to resume
6. **Observable:** Prometheus metrics, structured logging, failure notifications
7. **Single source of truth:** Configuration defines what to back up; the tool
   figures out the how and when

### Option A: Refactor current bash script (evolutionary)

**Approach:** Keep bash, but restructure around a data-driven config and fix all
identified issues. Replace the nine copy-pasted functions with a loop over a config
array. Add flock, udev trigger, and drive detection.

**Strengths:**
- Smallest change from current state; all existing logic is preserved
- No new dependencies or languages
- Systemd integration stays the same
- Can be done incrementally, one fix at a time

**Weaknesses:**
- Bash is fundamentally unsuited for the complexity this has reached. 1666 lines of
  bash with associative arrays, pipeline error handling, date arithmetic, and JSON
  construction is already past the maintainability threshold
- Adding drive detection (udev rules + systemd device units) and space-aware retention
  in bash will push it past 2000 lines
- No type safety, no structured error handling, no testability
- The `eval` pattern, quoting issues, and word-splitting risks only grow
- Hard to add features like progress reporting, parallel sends, or resumable transfers

**Estimated effort:** 2-3 sessions for fixes, 1-2 more for udev integration.

### Option B: Python rewrite with systemd and udev integration

**Approach:** Rewrite in Python, leveraging `subprocess` for btrfs commands, `pyudev`
for drive detection, and `systemd-notify` for watchdog integration. Configuration in
YAML/TOML. Structured logging with Python's `logging` module.

**Architecture sketch:**
```
~/.config/btrfs-backup/config.toml     # What to back up, retention policy
/etc/udev/rules.d/99-backup-drive.rules # Triggers on drive connect
~/.config/systemd/user/btrfs-backup.service  # Main service (socket-activated or triggered)

btrfs_backup/
├── __init__.py
├── config.py          # TOML config parsing, validation
├── drive.py           # Drive detection, mount verification
├── snapshot.py        # Create, send, receive, verify
├── retention.py       # Space-aware graduated retention
├── metrics.py         # Prometheus metrics export
├── notify.py          # Discord/ntfy notifications
└── cli.py             # CLI interface (backup, status, verify, list)
```

**Config example (config.toml):**
```toml
[global]
notification_url = "discord://webhook-url"
metrics_dir = "~/containers/data/backup-metrics"
lock_file = "/run/user/1000/btrfs-backup.lock"

[[subvolume]]
name = "htpc-home"
source = "/home"
tier = 1
local_schedule = "daily"
external_schedule = "daily"

[[subvolume]]
name = "subvol3-opptak"
source = "/mnt/btrfs-pool/subvol3-opptak"
tier = 1
local_schedule = "daily"
external_schedule = "daily"
note = "Heightened backup demands — irreplaceable recordings"

[[drive]]
label = "WD-18TB"
uuid = "647693ed-..."
role = "offsite-a"

[[drive]]
label = "WD-18TB1"
uuid = "..."
role = "offsite-b"

[retention]
strategy = "space-aware"   # or "fixed-count"
local_daily = 14
local_weekly = 6
local_monthly = 3
external_min_free_percent = 10
```

**Strengths:**
- Proper error handling with exceptions, context managers, type hints
- Testable with pytest — can mock btrfs commands and verify logic
- `pyudev` gives clean drive hot-plug detection
- Space-aware retention is natural to implement (sort snapshots by age, delete oldest
  until free space > threshold)
- Structured logging with JSON output for Loki
- TOML config is human-readable and validatable
- Progress reporting during long sends (parse btrfs send output or poll /proc)
- Can be packaged as a proper tool with `--status`, `--verify`, `--list` subcommands
- Python is already on Fedora (system dependency)

**Weaknesses:**
- Full rewrite — all existing logic must be re-implemented and re-tested
- Python subprocess calls to btrfs are no simpler than bash — still shelling out
- Adds Python as a runtime dependency for the backup system (it's already there,
  but now it must stay there)
- pyudev is an additional pip dependency (or Fedora package)
- Risk of introducing new bugs during rewrite — the current script's edge cases
  (pin files, graduated retention, partial cleanup) were learned the hard way

**Estimated effort:** 3-5 sessions for core rewrite, 1-2 for udev integration,
1-2 for testing and migration.

### Option C: Purpose-built daemon with TOML config (recommended)

**Approach:** A Python daemon that runs persistently, monitors for drive connection
via udev, manages the full backup lifecycle, and exposes a CLI for status and
manual triggers. Think of it as a personal Time Machine daemon purpose-built for
BTRFS and this homelab's specific needs.

**Architecture:**
```
btrfs-timemachine/
├── btm/
│   ├── daemon.py       # Main event loop: udev monitor + schedule + signal handling
│   ├── config.py       # TOML config with validation and defaults
│   ├── btrfs.py        # Typed wrappers around btrfs commands (snapshot, send, receive,
│   │                   #   show, scrub) — replaces raw subprocess with structured results
│   ├── planner.py      # Decides what to do: which subvols need backup, incremental vs
│   │                   #   full, which snapshots to prune — pure logic, fully testable
│   ├── executor.py     # Executes the plan: runs btrfs commands, handles errors, retries
│   ├── retention.py    # Space-aware + time-aware retention (Time Machine algorithm)
│   ├── verify.py       # Post-send integrity checks (file count, size, optional scrub)
│   ├── state.py        # Persistent state in SQLite: last successful send per subvol per
│   │                   #   drive, chain parent UUIDs, send durations for ETA estimation
│   ├── metrics.py      # Prometheus .prom file export
│   ├── notify.py       # Discord/ntfy/email notifications
│   └── cli.py          # `btm status`, `btm backup`, `btm verify`, `btm list`, `btm history`
├── config.toml
├── pyproject.toml
└── tests/
    ├── test_planner.py
    ├── test_retention.py
    └── test_btrfs_mock.py
```

**What makes this different from Option B:**

1. **Persistent daemon with udev monitoring.** Instead of "run script at 02:00, hope
   the drive is connected", the daemon watches for drive connection events. When a
   backup drive appears, it immediately starts working. When the drive disappears
   (safely ejected or physically removed), it stops cleanly. The daily schedule
   becomes a fallback, not the primary trigger.

2. **Planner/executor separation.** The planner is pure logic: given the current state
   (which subvols exist, which snapshots exist locally and on each drive, how much
   space is available), it produces a plan (list of actions). The executor runs the
   plan. This means the planner is fully testable without touching any filesystem,
   and `btm plan --dry-run` shows exactly what would happen.

3. **SQLite state tracking.** Instead of pin files scattered across snapshot directories,
   a single SQLite database tracks: last successful send per subvol per drive, the
   parent UUID used, send duration (for ETA estimation), verification results. This
   enables `btm history` and `btm status` commands that show the full backup state
   at a glance.

4. **Space-aware retention (the Time Machine algorithm).** Instead of "keep 14 daily,
   6 weekly, 3 monthly", the retention policy is: keep as much history as fits, with
   exponential thinning. When space runs low, delete the oldest snapshots first, but
   never delete the incremental chain anchor, and never delete the only copy of a
   snapshot. The retention engine respects tier priority — Tier 3 snapshots get pruned
   before Tier 1.

5. **Resumable sends.** If a send is interrupted (drive removed, system shutdown), the
   daemon detects the partial receive on next connection, cleans it up, and restarts
   from the last good state. No manual intervention.

6. **CLI for operational visibility.**
   ```
   $ btm status
   SUBVOLUME          LOCAL  WD-18TB  WD-18TB1  LAST SEND    CHAIN
   htpc-home          15     14       12        2h ago       incremental
   subvol3-opptak     15     1        0         6h ago       full (new)
   subvol7-containers 15     2        1         23h ago      incremental
   subvol1-docs       15     2        1         23h ago      incremental
   subvol4-multimedia 4      0        0         never        —

   Drives: WD-18TB1 mounted (4.4TB free / 17TB)
   Next scheduled: subvol2-pics in 5d (Saturday)
   ```

**Strengths:**
- True autonomous operation — closest to the Time Machine experience
- Drive hot-plug support via udev (back up immediately when drive is connected)
- Testable architecture (planner is pure logic, btrfs layer is mockable)
- SQLite state gives operational visibility and history
- Space-aware retention adapts to actual drive capacity
- CLI gives instant operational status without reading logs
- Resumable, idempotent, self-healing
- Can be packaged as a proper systemd user service with watchdog

**Weaknesses:**
- Largest engineering effort of the three options
- Daemon complexity: signal handling, graceful shutdown, state corruption recovery
- SQLite adds a dependency and a new failure mode (database corruption, though
  SQLite is extremely robust)
- udev integration requires a system-level rule file (needs sudo to install once)
- Risk of over-engineering — this is a single-machine homelab, not a fleet
- All the current script's hard-won edge case handling must be re-implemented

**Estimated effort:** 5-8 sessions for core implementation, 2-3 for testing and
migration, 1-2 for CLI polish.

### Recommendation: Option C (purpose-built daemon)

The current bash script has been patched through three major incidents and is at 1666
lines. Each incident reveals new failure modes that require more complex state
management, more careful error handling, and more operational tooling. Bash is the
wrong tool for this complexity level.

Option A (refactor bash) would fix today's bugs but won't prevent tomorrow's. The
fundamental problems — no drive detection, no space-aware retention, no post-send
verification, no operational CLI — require capabilities that bash doesn't provide well.

Option B (Python rewrite) is solid and would address most issues, but it's still a
cron-job architecture. Running at 02:00 and hoping the drive is connected is not
autonomous — it's automated.

Option C (purpose-built daemon) is the only option that achieves the stated goal:
**work like Time Machine**. Detect the drive, back up, organize, clean up, all without
human involvement. The additional complexity (daemon, SQLite, udev) is justified by
the value of the data being protected — subvol3-opptak contains irreplaceable
recordings, and the current system has failed silently for weeks at a time.

The practical path: **Fix the critical bash issues first (Fixes 1-3, 5, 8 — one
session), then build Option C in parallel.** The bash script continues to run nightly
while the daemon is developed and tested. Migration happens when the daemon passes
the same restore tests. The bash script becomes the fallback until confidence is
established.

### Sudo alternatives for btrfs commands

The current approach — NOPASSWD sudoers entries for specific btrfs commands — is the
standard and most appropriate solution for this use case. But alternatives exist:

**1. Run the entire script/daemon as root (simplest, least secure)**

Run the systemd service as a system service (`/etc/systemd/system/`) instead of a
user service. The script runs as root and needs no sudo. This trades granularity for
simplicity — the script can do anything, not just btrfs commands. For a single-user
homelab with physical access, this is defensible, but goes against the rootless
container philosophy.

**2. Linux capabilities on the btrfs binary (targeted, fragile)**

```bash
sudo setcap cap_sys_admin,cap_dac_read_search+ep /usr/sbin/btrfs
```

This lets any user run btrfs admin commands without sudo. Too broad — gives the
capability to ALL users, not just the backup script. Also fragile: package updates
overwrite the binary and lose the capabilities.

**3. Polkit rules (fine-grained, complex)**

Polkit can authorize specific users for specific actions without sudoers. But btrfs
commands don't go through Polkit — they're direct syscalls (ioctl on the filesystem).
Polkit is not applicable here.

**4. Dedicated backup user with group permissions (medium)**

Create a `backup` user, add it to a group that owns the snapshot directories, and
run the service as that user. Still needs sudo for `btrfs send/receive` (which require
root for the ioctl), so this doesn't actually eliminate the sudoers requirement.

**5. Systemd `AmbientCapabilities` (best alternative to sudoers)**

```ini
[Service]
AmbientCapabilities=CAP_SYS_ADMIN CAP_DAC_READ_SEARCH
CapabilityBoundingSet=CAP_SYS_ADMIN CAP_DAC_READ_SEARCH
```

This grants the necessary Linux capabilities to the service process without requiring
sudo at all. The service runs as the regular user but with elevated filesystem
capabilities. This is the most principled approach — capabilities are scoped to the
process, not granted via sudoers file. However, it requires running as a system
service (user services can't grant capabilities), and `CAP_SYS_ADMIN` is nearly
equivalent to root (it's the "escape hatch" capability).

**Recommendation:** Keep the sudoers approach but expand it with the two missing
read-only commands, and **scope the delete rule to snapshot directories only**.

The original `btrfs subvolume delete *` rule allows deletion of any subvolume on the
system — a hostile actor with shell access as patriark could delete production data
subvolumes. Scoping to snapshot directories limits the blast radius.

**Caveat:** Sudoers wildcards do simple string glob matching, not path canonicalization.
`btrfs subvolume delete /home/patriark/.snapshots/../../..` would match the rule.
However, `btrfs subvolume delete` only operates on actual BTRFS subvolumes (it fails
on regular directories), so path traversal would only succeed if the traversed target
is itself a subvolume. This is a known sudoers limitation, not a practical exploit
in this context.

The hardened sudoers file should be:

```
# BTRFS Backup Automation - Passwordless sudo for specific commands
# Created: 2025-11-12, Updated: 2026-03-22
# Purpose: Allow automated BTRFS snapshot backups via systemd user services
#
# Security: delete and snapshot scoped to snapshot directories only.
# send/receive need broad paths (source subvols vary, external drives vary).
# show commands are read-only.

# Snapshot creation — scoped to snapshot directories
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot -r /home /home/patriark/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot -r / /home/patriark/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume snapshot -r /mnt/btrfs-pool/* /mnt/btrfs-pool/.snapshots/*

# Snapshot deletion — scoped to snapshot directories only
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete /home/patriark/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete /mnt/btrfs-pool/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete /run/media/patriark/WD-18TB/.snapshots/*
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume delete /run/media/patriark/WD-18TB1/.snapshots/*

# Send/receive — broad paths needed (source subvols and external drives vary)
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *

# Read-only commands — for space estimation and diagnostics
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume show *
patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs filesystem show *
```

---

## Fixes Applied (2026-03-22)

All fixes applied to `scripts/btrfs-snapshot-backup.sh` and the systemd service files.

| # | Fix | Category | Files changed |
|---|-----|----------|---------------|
| 1 | Validate `--subvolume` input — rejects unknown names, accepts both short (`opptak`) and full (`subvol3-opptak`) names | Critical | script |
| 2 | `StartLimitBurst=3` + `StartLimitIntervalSec=6h` — stops crash-looping on permanent failures | Critical | daily + weekly service |
| 3 | `flock -n /tmp/btrfs-backup.lock` — mutual exclusion, prevents concurrent runs | Critical | daily + weekly service |
| 4 | Fix duplicate logging — file gets `>>` append, terminal gets colorized `echo` (was `tee` + `echo` = doubled output) | Serious | script |
| 5 | `TimeoutStartSec=12h` (was 2h) — full re-sends take 6+ hours | Serious | daily service |
| 7 | Schedule-skipped subvolumes report `success=2` in Prometheus (was `success=1`, indistinguishable from real success) | Moderate | script |
| 10 | `find_common_parent()` consults pin file first — prevents silent chain divergence | Critical | script |
| 11 | `--subvolume` overrides schedule gates — manual runs no longer blocked by "Saturdays only" / "1st of month" (except `never`) | New finding | script |
| 12 | `--help` header lists valid subvolume names | New finding | script |

### Fix 8 (sudoers expansion) applied manually by user.
### Fix 6 (post-send verification) and Fix 9 (Discord webhook) deferred to Option C rewrite.

### Additional observations during fix session

- **Weekly service had stale documentation path** — pointed to `backup-strategy-guide.md`
  instead of `docs/20-operations/guides/backup-strategy.md`. Fixed.
- **`run_cmd` verbose + dry-run double-logs** — in verbose+dry-run mode, `run_cmd` logs
  "Executing: ..." then "[DRY-RUN] Would execute: ...". Pre-existing, cosmetic only.
  Not worth fixing in the bash script; will be gone in Option C.

## Next Steps

1. **Done:** Fixes 1-5, 7, 8, 10-12 applied
2. **Remaining:** Fix 9 (Discord webhook) — requires webhook URL configuration
3. **Sudoers hardening:** Scope `delete` and `snapshot` rules to snapshot directories only
   (see hardened sudoers recommendation above)
4. **Decision made:** Option C (purpose-built Python daemon) for long-term architecture
5. **When starting Option C:** Begin with `btrfs.py` (typed wrappers) and `planner.py`
   (pure logic with tests) — these are useful regardless of final architecture
