# Storage-Health Monitoring (btrfs dev-stats + SMART)

**Status:** Part 1 of 2 (early-warning observability). Part 2 = scheduled `btrfs scrub`.
**Context:** ADR-029. The pool is **Single data profile — no live redundancy**, so a disk
failure is a *restore* event and bit rot is not auto-repaired on data. Early warning is
therefore the primary defense. Capacity alerting already existed; this adds the two
missing layers: continuous per-device error counters and SMART in the Discord alert path.

## What it monitors

| Layer | Source | Privilege | Cadence | Catches |
|---|---|---|---|---|
| **BTRFS dev-stats** | `btrfs device stats` | **none** (root-free) | 15 min | Per-device write/read/flush/**corruption**/generation errors the kernel hits during *normal* I/O — the earliest signal, between scrubs |
| **SMART** | `smartctl --json` | root (scoped sudo) | hourly | Drive-firmware pre-failure: health self-assessment, pending/reallocated/offline-uncorrectable sectors, temperature, NVMe wear |

The two are complementary (filesystem view vs. firmware view); them disagreeing is itself
diagnostic. dev-stats covers the pool **and** mounted backup drives; SMART covers the
fixed internal disks (4 pool members + the NVMe). Removable LUKS2 backups are covered at
the filesystem level by dev-stats when mounted.

## Components

- `scripts/btrfs-dev-stats-collector.sh` → `btrfs_device_errors{filesystem,device,type}` (+ present/last-run)
- `scripts/smartmon-collector.sh` → `smartmon_*` (health, sectors, temp, NVMe wear)
- `systemd/btrfs-dev-stats.{service,timer}` (user, 15 min) · `systemd/smartmon.{service,timer}` (user, hourly)
- `config/sudoers.d/homelab-storage-health` — least-privilege, read-only `smartctl` on the fixed devices
- `config/prometheus/alerts/storage-health.yml` — 10 alerts → Alertmanager → Discord by `severity`

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

## Part 2 — scheduled scrub (planned)

`btrfs scrub` (bit-rot *detection*, and metadata repair) over the pool + backups, run as a
heavily-throttled, Urd-coordinated, staggered timer. Deferred to its own PR because it puts
sustained read load on the live HDD pool (recall the boot I/O storm) and warrants a
supervised first run. Will add `btrfs scrub start|status` lines to the sudoers grant and
`btrfs_scrub_*` metrics/alerts (split `uncorrectable`=critical vs `corrected`=warning).
