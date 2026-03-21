# 2026-03-21: BTRFS Backup Script — Operational Excellence Revision

## Incident Summary

Weekly external backup failed silently for 2+ weeks. User discovered manually on 2026-03-21
that subvol1-docs, subvol3-opptak, and subvol7-containers had no valid external backup.

### Root Cause Chain

1. **March 7**: subvol5-music full send failed (external drive nearly full at 92%).
   subvol6-tmp also failed. Script logged only "Command failed" — no reason captured.
2. **March 14**: subvol3-opptak and subvol7-containers incremental sends failed.
   The parent snapshot existed on both sides, but sends failed (likely disk space again
   from incomplete receives left behind).
3. **March 21**: subvol3-opptak and subvol7-containers have **no common parent** anymore.
   Local retention (15 daily) deleted the snapshot that was last sent externally (20260307).
   Script fell back to full send — ran for 3 hours, then failed (disk full).
   subvol1-docs incremental also failed.
4. Script reported "Completed" after every run. Exit code 0. No notification.
   User had no indication anything was wrong.

### Fundamental Flaws Identified

| # | Problem | Impact |
|---|---------|--------|
| 1 | No disk space pre-check | Multi-hour sends fail silently |
| 2 | No stderr capture from btrfs send/receive | "Command failed" with no reason |
| 3 | Local retention deletes the last common parent | Breaks incremental chain permanently |
| 4 | No end-of-run failure summary | Script says "Completed" even when subvols fail |
| 5 | Exit code always 0 | systemd Restart=on-failure never triggers correctly |
| 6 | Failed receives leave orphan subvolumes | Disk fills with incomplete data |
| 7 | No notification to user | Failures accumulate silently for weeks |
| 8 | Retries re-run everything from the top | 4x retry overhead, hours wasted |

## Fixes Implemented

All changes in `scripts/btrfs-snapshot-backup.sh` (1042 → 1361 lines).

### 1. Disk space pre-check (`check_external_space()`)
- Checks available space via `df` before every send
- For full sends: estimates required size from `btrfs subvolume show` (exclusive data),
  falls back to `du -sb` when btrfs show requires password
- For incrementals: requires at least 10GB headroom
- Aborts with clear error before starting a multi-hour send

### 2. Stderr capture in send/receive
- Replaced `eval`/`run_cmd` with dedicated pipeline capturing stderr from both sides
- Checks `PIPESTATUS` array for send and receive exit codes independently
- Logs actual error messages (e.g., "No space left on device")

### 3. Pinned parent mechanism
- After successful external send, writes `.last-external-parent` marker file
- `cleanup_old_snapshots()` never deletes the pinned snapshot
- Ensures incremental chain anchor survives regardless of retention count
- New send updates the pin (old parent can then be cleaned up normally)

### 4. Failure tracking + summary
- `FAILED_SUBVOLS[]`, `SUCCEEDED_SUBVOLS[]`, `SKIPPED_SUBVOLS[]` arrays
- `print_summary()` at end of every run shows counts and failure reasons
- Clear indication of which subvolumes need manual attention

### 5. Non-zero exit code
- `exit 1` when any subvolume fails
- Makes systemd `Restart=on-failure` work correctly

### 6. Partial receive cleanup
- On send/receive failure, checks for incomplete subvolume at destination
- Deletes it with `btrfs subvolume delete` before returning
- Prevents disk fill from abandoned partial receives

### 7. Discord notification
- Uses existing `alert-discord-relay` webhook pattern
- Sends embed listing failed subvolumes with reasons
- Only fires on failures, not success

### 8. Retry state tracking
- Writes completed subvolumes to `/tmp/btrfs-backup-completed-YYYYMMDD`
- Skips already-completed subvolumes on retry
- Auto-cleans stale state files from previous days
- Dry-run mode does not write state files

## Live Testing

Testing against offsite backup drive (WD-18TB1) with 3-month-old snapshots.
This drive has no common parent with current local snapshots — exercises full send path.

### Test Environment
- **Offsite drive**: /run/media/patriark/WD-18TB1 (17T, 262GB free at start)
- **Ephemeral drive**: /run/media/patriark/2TB-backup (1.9T, 1.1TB free)
- **Test subvolumes**: subvol7-containers (8GB), subvol1-docs (11GB)

### Iteration Log

#### Iteration 1: Dry run — space check bug
- `btrfs subvolume show` needs sudo password interactively → exclusive size returns empty
- Space check showed "estimated=0GB" — misleading but didn't block
- **Fix**: Added `du -sb` fallback when btrfs show fails

#### Iteration 2: Dry run — arithmetic error from du
- `du -sb` output contained newline that broke bash arithmetic
- **Fix**: Added `head -1 | tr -cd '0-9'` to sanitize du output

#### Iteration 3: Dry run — verified
- Space check now shows: `available=261GB, estimated=8GB (source: du)` — correct
- No common parent detected correctly → falls back to full send
- Summary, pinning, retry detection all working in dry-run mode

#### Iteration 4: Dry run state file leak
- Dry-run was writing to state file, causing second dry-run to skip everything
- **Fix**: `mark_completed()` now checks `DRY_RUN` before writing state

#### Iteration 5: Live test — subvol7-containers (SUCCESS)
- Full send of 8GB to offsite drive (no common parent)
- Completed in 626s (~10 minutes), used ~12GB on external (btrfs overhead)
- Pin file created: `.last-external-parent` = `20260321-containers`
- State file tracking works

#### Iteration 6: Retry skip test (SUCCESS)
- Re-ran `--subvolume containers` immediately after
- Output: `subvol7-containers already completed today, skipping (retry)`
- Shows `Retry run — previously completed: subvol7-containers`
- 0 seconds, correctly skipped

#### Iteration 7: Live test — subvol1-docs (SUCCESS)
- Full send of 11GB to offsite drive (no common parent)
- Completed in 223s (~4 minutes)
- Pin file created, state file updated with both subvolumes

#### Iteration 8: Space check rejection — subvol3-opptak (CORRECT FAILURE)
- 3.2TB subvolume vs 236GB available
- `Space check (full send): available=236GB, estimated=3189GB (source: du)`
- `Insufficient space for full send: need ~3189GB, have 236GB`
- Rejected instantly — no wasted hours. Exit code 1.

#### Iteration 9: `set -e` bug discovery and fix
- Script exiting before reaching `print_summary()` on failures
- Root cause: backup functions `return 1`, `set -e` kills script in `main()`
- **Fix**: Added `|| true` after each backup function call in `main()`
- Failures tracked in `FAILED_SUBVOLS` array, summary and exit code handled at end

#### Iteration 10: Multi-subvolume mixed success/failure — tier 1 (VALIDATED)
- Ran all tier 1 with `--tier 1`
- **htpc-home**: Incremental send found common parent, but failed mid-transfer with
  `No space left on device` (stderr captured perfectly: showed exact file causing failure).
  Partial receive cleaned up automatically — `20260321-htpc-home` not left on disk.
- **subvol3-opptak**: Space check rejected immediately (3189GB > 235GB)
- **subvol7-containers**: Destination snapshot already existed, correctly skipped
- Summary: `Succeeded (1): subvol7-containers` / `FAILED (2): htpc-home, subvol3-opptak`
- Exit code: 1
- All critical paths validated: stderr capture, partial cleanup, space check, retry, summary

## Bugs Found and Fixed During Testing

| # | Bug | When Found | Fix |
|---|-----|-----------|-----|
| 1 | `btrfs subvolume show` needs sudo (not in NOPASSWD list) | Iteration 1 | `du -sb` fallback |
| 2 | `du -sb` output newline breaks bash arithmetic | Iteration 2 | `head -1 \| tr -cd '0-9'` |
| 3 | Dry-run writes to state file | Iteration 4 | Check `DRY_RUN` in `mark_completed()` |
| 4 | `set -e` kills script before summary on failure | Iteration 9 | `\|\| true` on backup function calls |

## Compression Validation

### Discovery: Offsite drive missing compression

The offsite drive (WD-18TB1) was automounted by udisks2 **without** `compress=zstd:3`.
The fstab entry only targets `/run/media/patriark/WD-18TB` (primary drive mount point).
Both drives share LUKS UUID `b6b38ff1-...` and btrfs label "WD-18TB" (cloned drives),
but udisks2 automounts to `WD-18TB1` when the primary mount point path exists.

**Fix applied:**
1. Immediate: `sudo mount -o remount,compress=zstd:3 /run/media/patriark/WD-18TB1`
2. Permanent: udisks2 config needed at `/etc/udisks2/mount_options.conf` matching
   `/dev/disk/by-label/WD-18TB` with `btrfs_defaults=compress=zstd:3,nosuid,nodev`

### Re-send with compression

Deleted uncompressed snapshots, re-sent with `compress=zstd:3` active:

| Subvolume | Duration | Uncompressed | On-disk | Compressible portion | Ratio |
|-----------|----------|-------------|---------|---------------------|-------|
| containers | 559s (was 626s) | 13GB | 10GB | 3.3GB → 1.0GB zstd | **31%** |
| docs | 194s (was 223s) | 11GB | 10GB | 1.1GB → 260MB zstd | **22%** |

**Key findings:**
- Compressible data (configs, databases, text) achieves 69-78% size reduction
- btrfs correctly skips already-compressed data (images, binaries) — no wasted CPU
- Transfer time also improved (less I/O): containers 11% faster, docs 13% faster
- Total savings on these two subvolumes: ~3.1GB
- The 2026-02-02 evaluation predicted "30-40% on configs" — actual is 69-78% (better)

## Bugs Found and Fixed During Testing

| # | Bug | When Found | Fix |
|---|-----|-----------|-----|
| 1 | `btrfs subvolume show` needs sudo (not in NOPASSWD list) | Iteration 1 | `du -sb` fallback |
| 2 | `du -sb` output newline breaks bash arithmetic | Iteration 2 | `head -1 \| tr -cd '0-9'` |
| 3 | Dry-run writes to state file | Iteration 4 | Check `DRY_RUN` in `mark_completed()` |
| 4 | `set -e` kills script before summary on failure | Iteration 9 | `\|\| true` on backup function calls |
| 5 | Offsite drive automounted without compression | Compression test | `mount -o remount`, needs permanent udisks2 config |

## Current State (End of Session)

- **Offsite drive (WD-18TB1)**: 240GB free (99% full), compression active (remount)
- **subvol7-containers**: Chain re-established, compressed (pinned: 20260321)
- **subvol1-docs**: Chain re-established, compressed (pinned: 20260321)
- **subvol3-opptak**: Needs space freed (~3.2TB full send required)
- **htpc-home**: Needs space freed (incremental failed with ENOSPC)
- **Primary drive (WD-18TB)**: Not connected (was swapped out for offsite testing)
- **2TB-backup drive**: Available at /run/media/patriark/2TB-backup (1.1TB free)

---

## Handoff: Work Remaining for Future Session

### Immediate (before next Saturday backup)

1. **Create udisks2 mount config** — `/etc/udisks2/mount_options.conf`:
   ```
   [/dev/disk/by-label/WD-18TB]
   btrfs_defaults=compress=zstd:3,nosuid,nodev
   btrfs_allow=compress,compress-force,datacow,nodatacow,datasum,nodatasum,autodefrag,noautodefrag,degraded,device,discard,nodiscard,subvol,subvolid,space_cache
   ```
   This ensures both WD-18TB drives always get compression when automounted by udisks2.

2. **Swap back to primary drive (WD-18TB)** and re-establish incremental chains
   for subvol1, subvol3, subvol7. The primary drive has more recent snapshots
   (up to 20260314) so some incrementals may work. Check with `--dry-run` first.

3. **Verify the primary drive has compression in fstab** — already confirmed:
   `UUID=b6b38ff1-... /run/media/patriark/WD-18TB btrfs compress=zstd:3,...`

### Script refinements to consider

4. **Retention policy review** — The current retention was configured before the
   pinned parent mechanism was added. Now that the incremental chain anchor is
   protected, the retention counts could potentially be adjusted:
   - Local daily retention of 15 may be more than needed now that pins protect parents
   - External weekly retention of 8 (= 2 months) seems reasonable
   - Monthly retention concept is not actually implemented in the script — the
     `cleanup_old_snapshots` function doesn't distinguish weekly from monthly.
     All external snapshots use a single pattern and single retention count.
     This means "8 weekly + 12 monthly" in the config is aspirational, not real.
     **This is a known gap that needs design work.**

5. **Backup frequency** — The 2026-02-02 evaluation proposed increasing Tier 1
   external backups from weekly to 2-3x/week. Now that incrementals are cheap
   and the pinned parent protects the chain, this is lower risk. The script
   already checks `$(date +%u) -eq 6` (Saturday) — changing to
   `[[ $(date +%u) =~ ^(2|4|6)$ ]]` (Tue/Thu/Sat) would triple external frequency
   with minimal storage impact since incrementals are small.

6. **Add `btrfs subvolume show` to sudoers NOPASSWD** — This would let the
   space check use exclusive data size (more accurate than `du` for snapshots).
   Add to `/etc/sudoers.d/btrfs-backup`:
   ```
   patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume show *
   ```

7. **Discord notification testing** — The webhook file is at
   `config/alertmanager/discord-webhook.txt`. The notification function works
   but wasn't tested live (webhook not accessible from CLI context). Test by
   running the script when it will produce a failure, then check Discord.

8. **Prometheus alert for broken incremental chain** — The script now logs
   "Sending full snapshot" when no common parent exists. A Prometheus metric
   like `backup_incremental_chain_broken{subvolume="X"} 1` would let Grafana
   alert on this before it becomes a space problem.

### Context for the drives

- **WD-18TB (primary)**: Always connected via SATA, fstab-managed, has recent
  snapshots up to 20260314/20260307 depending on subvolume. Compression via fstab.
- **WD-18TB1 (offsite)**: Swapped in periodically, udisks2-managed, has old
  snapshots (3+ months). Needs udisks2 config for compression. Currently mounted
  with compression (remount), has fresh chains for containers + docs.
- **2TB-backup**: Surplus ephemeral drive, 1.1TB free. Available for experiments.
- Both WD drives share the same LUKS UUID and btrfs label (cloned).
