# Storage-Health Monitoring (btrfs dev-stats + SMART)

**Status:** Both parts implemented. Part 1 (dev-stats + SMART) is deployed and live; Part 2
(scrub) is installed, with its timers enabled by the owner after a supervised first run.
**Context:** ADR-029. The pool is **Single data profile — no live redundancy**, so a disk
failure is a *restore* event and bit rot is not auto-repaired on data. Early warning is
therefore the primary defense. Capacity alerting already existed; this adds the two
missing layers: continuous per-device error counters and SMART in the Discord alert path.

## What it monitors

| Layer | Source | Privilege | Cadence | Catches |
|---|---|---|---|---|
| **BTRFS dev-stats** | `btrfs device stats` | **none** (root-free) | 15 min | Per-device write/read/flush/**corruption**/generation errors the kernel hits during *normal* I/O — the earliest signal, between scrubs |
| **SMART** | `smartctl --json` | root (scoped sudo) | hourly | Drive-firmware pre-failure: health self-assessment, pending/reallocated/offline-uncorrectable sectors, temperature, NVMe wear |
| **BTRFS scrub** | `btrfs scrub` | root (scoped sudo) | monthly | Reads every block + verifies checksums — bit-rot *detection* (and metadata repair from the RAID1 mirror) |

The two are complementary (filesystem view vs. firmware view); them disagreeing is itself
diagnostic. dev-stats covers the pool **and** mounted backup drives; SMART covers the
fixed internal disks (4 pool members + the NVMe). Removable LUKS2 backups are covered at
the filesystem level by dev-stats when mounted.

## Components

- `scripts/btrfs-dev-stats-collector.sh` → `btrfs_device_errors{filesystem,device,type}` (+ present/last-run)
- `scripts/smartmon-collector.sh` → `smartmon_*` (health, sectors, temp, NVMe wear)
- `scripts/btrfs-scrub.sh` → `btrfs_scrub_*` (per-fs state files rendered into one `.prom`)
- `systemd/btrfs-dev-stats.{service,timer}` (15 min) · `systemd/smartmon.{service,timer}` (hourly)
- `systemd/btrfs-scrub-internal.{service,timer}` (pool+/home, 1st Sun) · `systemd/btrfs-scrub-backups.{service,timer}` (backups, 3rd Sun, Urd-guarded)
- `config/sudoers.d/homelab-storage-health` — least-privilege: read-only `smartctl` + `btrfs scrub` on exact devices/mountpoints
- `config/prometheus/alerts/storage-health.yml` — 13 alerts → Alertmanager → Discord by `severity`

Metrics land in `~/containers/data/backup-metrics/*.prom` (node_exporter textfile collector,
written as user 1000 — same contract as `db-dump.sh`).

## Install

```bash
# 1. SMART sudo grant (one-time, root). Read-only, exact-args, no wildcards.
sudo install -m 0440 -o root -g root \
    ~/containers/config/sudoers.d/homelab-storage-health \
    /etc/sudoers.d/homelab-storage-health
sudo visudo -c            # must print: .../homelab-storage-health: parsed OK

# 2. Install + enable the user timers (hand-written units are copied, not symlinked).
install -m 0644 ~/containers/systemd/btrfs-dev-stats.{service,timer} \
                ~/containers/systemd/smartmon.{service,timer} \
                ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now btrfs-dev-stats.timer smartmon.timer

# 3. Activate the alerts (prometheus auto-loads alerts/*.yml on reload).
podman exec prometheus wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Verify

```bash
# Collectors produce valid metrics
systemctl --user start btrfs-dev-stats.service smartmon.service
cat ~/containers/data/backup-metrics/btrfs-dev-stats.prom    # per-device counters, all 0 on healthy hw
cat ~/containers/data/backup-metrics/smartmon.prom           # smartmon_devices_collected should be 5 post-sudoers

# Prometheus sees them + the rules loaded
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=btrfs_device_errors' | jq '.data.result | length'
podman exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=smartmon_device_smart_healthy'
```

If `smartmon_devices_collected` stays `0` after install, the sudoers grant isn't matching —
confirm the smartctl argv in the script equals the `Cmnd_Alias` byte-for-byte.

## Operating notes

- **dev-stats counters are persistent** — any nonzero is abnormal. After replacing a disk
  or clearing a transient, zero them: `sudo btrfs dev stats -z /mnt`.
- **Single data / RAID1 metadata** (pool): a scrub (Part 2) can self-heal *metadata* but
  not *data*; a `corruption` error here means a file to restore from backup. `/home` is
  Metadata=single — its NVMe health matters most (covered by the NVMe SMART alerts).
- Alerts route to Discord by `severity` (critical = act now / data-loss-adjacent; warning =
  trend to watch). Same path as the backup alerts.

## Part 2 — scheduled scrub

`scripts/btrfs-scrub.sh` reads every block and verifies checksums (bit-rot **detection**;
on the pool it can also **repair metadata** from the RAID1 mirror, but not data). Metrics:
`btrfs_scrub_{uncorrectable,corrected}_errors`, `…_last_completion_timestamp`,
`…_duration_seconds`, `…_exit_code` per `filesystem`. Alerts split the profile reality:
**uncorrectable = critical** (data to restore), **corrected = warning** (a disk whispering),
plus **overdue** (pool/home, >45 d).

**Throttling** (this pool serves every service — see the 2026-06 boot I/O storm):
`btrfs scrub start -B -d -c 3 --limit 80m` = foreground + per-device + idle ioprio + a hard
80 MiB/s/device cap (restored after), and the units add `Nice=19` + `IOSchedulingClass=idle`.

**Schedule (staggered, clear of Urd's 04:00):**
- `btrfs-scrub-internal.timer` — pool `/mnt` + `/home`, **1st Sunday 14:00**
- `btrfs-scrub-backups.timer` — WD-18TB + 2TB-backup, **3rd Sunday 14:00**, with an
  `ExecCondition` that skips if `urd-backup.service` is active, and a per-drive mount guard
  (no-op when a removable backup is unplugged).

### Install (after a supervised first run)

The sudoers grant already includes scrub if you re-installed `homelab-storage-health` after
this change (it now holds `HOMELAB_SCRUB`). Re-install if needed, then **scrub once by hand
while watching I/O** before trusting the timer:

```bash
sudo install -m 0440 -o root -g root \
    ~/containers/config/sudoers.d/homelab-storage-health /etc/sudoers.d/homelab-storage-health
sudo visudo -c

install -m 0644 ~/containers/systemd/btrfs-scrub-internal.{service,timer} \
                ~/containers/systemd/btrfs-scrub-backups.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload

# Supervised first run — watch that services stay responsive under the throttled scrub:
systemctl --user start btrfs-scrub-internal.service &
# in another pane: watch -n5 'cat /proc/pressure/io; echo; sudo btrfs scrub status /mnt'
# Jellyfin/Immich/etc. should stay responsive. If I/O pressure spikes, lower --limit in
# scripts/btrfs-scrub.sh AND the sudoers line (keep them byte-for-byte identical), re-install.

# Once comfortable, enable the monthly timers:
systemctl --user enable --now btrfs-scrub-internal.timer btrfs-scrub-backups.timer
```

The pool scrub of ~11 TiB at 80 MiB/s/device runs **several hours** — expected. Watch the
first completion's `btrfs_scrub_corrected_errors` (sdc has 8 reallocated sectors and is the
likeliest source of a corrected/metadata blip).

> **Note:** `--limit` is fixed at `80m` in both the script and the sudoers line because sudo
> matches the exact argv. To change the cap, edit *both* in lockstep.
