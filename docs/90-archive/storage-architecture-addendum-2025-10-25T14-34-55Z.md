
# Storage Architecture — Command Reference & Maintenance Addendum  
*(fedora-htpc — 2025-10-25)*  

This addendum complements the main “Storage & Data Architecture — Authoritative (Rev.2)” document.  
It provides:  
1. **A practical guide to system investigation commands**, grouped logically with commentary and recommended flags.  
2. **Maintenance procedures** tailored to your current system state:  
   - system SSD (`/`) — BTRFS, unencrypted  
   - data pool (`/mnt`) — BTRFS multi-device, unencrypted  
   - external backup (`/run/media/patriark/WD-18TB`) — BTRFS inside LUKS container  

---

## 1) System Inspection & Information Commands

### 1.1 Disk and Block Layer
| Purpose | Command & Notes |
|----------|----------------|
| **Show block devices and mountpoints** | `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID,FSTYPE`  → overview of SSD, HDD pool, and external drives. |
| **List filesystem labels and UUIDs** | `blkid`  → useful for verifying fstab entries. |
| **Check partitions and SMART devices** | `sudo fdisk -l`  → lists partition tables; confirm `/dev/sdX` for new drives before adding to pool. |
| **SMART health summary** | `sudo smartctl -H /dev/sdX` → pass/fail check. <br>`sudo smartctl -A /dev/sdX | egrep "Reallocated|Pending|Hours"` → focus on key attributes. |
| **Monitor temperatures (optional)** | `sudo hddtemp /dev/sd[a-e]` or via `smartctl -A`. |

> *Tip:* Regularly run `sudo smartctl -a /dev/sdX | less` monthly; look for increasing reallocated or pending sectors.

---

### 1.2 BTRFS — Topology & Usage
| Purpose | Command & Notes |
|----------|----------------|
| **List all BTRFS filesystems and devices** | `sudo btrfs filesystem show`  → identifies which block devices belong to `/mnt`. |
| **Detailed usage report** | `sudo btrfs fi usage -T /mnt` → shows total, used, unallocated, and profile (RAID level). Add `-h` for human-readable sizes. |
| **Per-chunk distribution** | `sudo btrfs filesystem df /mnt` → lists how much space is allocated to Data/Metadata/System. |
| **Device-level statistics** | `sudo btrfs device stats /mnt` → reveals read/write/csum errors per drive. |
| **Current balance or rebalance status** | `sudo btrfs balance status /mnt` → “no balance found” = idle. |
| **Scrub status** | `sudo btrfs scrub status /mnt` → last run date and any errors. Use `sudo btrfs scrub start -Bd /mnt` to run manually (blocking). |

> *Guidance:*  
> - Expect `Data, single` now → will become `Data, RAID1` after conversion.  
> - Run a scrub monthly (systemd timer or manually).  

---

### 1.3 Subvolumes, Snapshots, and Quotas
| Purpose | Command & Notes |
|----------|----------------|
| **List subvolumes** | `sudo btrfs subvolume list -p /mnt` and `sudo btrfs subvolume list -p /` for SSD. Shows IDs, parents, and creation times. |
| **Create a snapshot (manual example)** | `sudo btrfs subvolume snapshot -r /mnt/btrfs-pool/subvol1-docs /mnt/btrfs-pool/.snapshots/subvol1-docs/$(date +%Y%m%d%H)-hourly`  → `-r` makes it read-only. |
| **Delete a snapshot** | `sudo btrfs subvolume delete <path>` |
| **Show snapshot tree sizes** | `sudo du -sh /mnt/btrfs-pool/.snapshots/* | sort -h` |
| **Enable quota tracking** | `sudo btrfs quota enable /mnt` (once). |
| **List qgroups** | `sudo btrfs qgroup show -reF /mnt | head` |
| **Set quota limit** | `sudo btrfs qgroup limit 500G /mnt/btrfs-pool/subvol2-pics` |

> *Tip:* Always make snapshots read-only (`-r`) if they are sources for `btrfs send`.  

---

### 1.4 Filesystem Health and Integrity
| Purpose | Command & Notes |
|----------|----------------|
| **Verify structure** | `sudo btrfs check --readonly /dev/sdX`  → run only on unmounted volumes (or readonly mode). |
| **Run scrub with output** | `sudo btrfs scrub start -Bd /mnt`  → checksums and repairs from mirror if available. |
| **SMART consistency check** | `sudo smartctl -x /dev/sdX`  → complete report. |
| **Find unallocated chunks** | `sudo btrfs fi usage -T /mnt | grep Unallocated` → keep >10%. |
| **Show filesystem errors in logs** | `sudo journalctl -k | grep BTRFS` → kernel BTRFS messages. |

---

### 1.5 Podman & Container Storage
| Purpose | Command & Notes |
|----------|----------------|
| **List running containers** | `podman ps --format "{{.Names}}	{{.Networks}}"` |
| **Inspect container volumes** | `podman volume inspect <name>` or list all with `podman volume ls` |
| **Show custom networks** | `podman network ls` |
| **Inspect a network in detail** | `podman network inspect <network>` → view CIDR, connected containers, and assigned IPs. |
| **Locate container storage root** | `podman info | grep -A3 "store:"` → see where overlay volumes are stored. |

---

### 1.6 Backup Verification
| Purpose | Command & Notes |
|----------|----------------|
| **Mount external backup drive** | `sudo mount /dev/mapper/WD-18TB /run/media/patriark/WD-18TB` (if not auto-mounted) |
| **Check backup filesystem** | `sudo btrfs fi usage -T /run/media/patriark/WD-18TB` |
| **Verify snapshots on backup** | `sudo btrfs subvolume list -p /run/media/patriark/WD-18TB/.snapshots` |
| **Run diff between snapshot generations** | `sudo btrfs send -p oldsnap newsnap --dry-run` |
| **Check available space** | `df -h /run/media/patriark/WD-18TB` |

---

## 2) Maintenance Procedures (Tailored for Current System)

### 2.1 Monthly Integrity Tasks
1. **Run a BTRFS scrub** on the pool and SSD:
   ```bash
   sudo btrfs scrub start -Bd /mnt
   sudo btrfs scrub start -Bd /
   ```
2. **Run SMART tests:**
   ```bash
   sudo smartctl -t short /dev/sda
   sudo smartctl -t short /dev/sdb
   sudo smartctl -t short /dev/sdc
   ```
3. **Check free space:**
   ```bash
   sudo btrfs fi usage -T /mnt
   ```

---

### 2.2 Snapshot & Retention Routine
**Data pool snapshots**  
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmddHH-hourly`  
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-daily`  
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-weekly`  
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-monthly`

**System SSD snapshots**  
- `~/.snapshots/home/YYYYmmddHH-hourly`  
- `~/.snapshots/home/YYYYmmdd-daily`  
- `~/.snapshots/home/YYYYmmdd-weekly`  
- `~/.snapshots/home/YYYYmmdd-monthly`  
- `~/.snapshots/root/YYYYmmdd-monthly`

> Retain latest 24 hourly / 14 daily / 8 weekly / 6 monthly snapshots.

---

### 2.3 Backup Cycle
**Weekly incremental send:**
```bash
sudo btrfs send -p /mnt/btrfs-pool/.snapshots/subvol1-docs/20251018-daily   /mnt/btrfs-pool/.snapshots/subvol1-docs/20251025-daily   | sudo btrfs receive /run/media/patriark/WD-18TB/.snapshots/subvol1-docs
```

**Quarterly full snapshot sweep:**
```bash
for sv in /mnt/btrfs-pool/subvol[1-7]*; do
  sudo btrfs subvolume snapshot -r "$sv" /mnt/btrfs-pool/.snapshots/$(basename "$sv")/$(date +%Y%m%d)-monthly
done
```

---

### 2.4 Pool Expansion & Rebalancing
```bash
sudo btrfs device add /dev/sdX /mnt
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt
watch -n 10 'sudo btrfs balance status /mnt'
```

Rebalance annually:
```bash
sudo btrfs balance start -dusage=50 /mnt
```

---

### 2.5 Cleanup & Space Reclaim
- **Delete old snapshots:**  
  `sudo find /mnt/btrfs-pool/.snapshots -type d -mtime +90 -exec btrfs subvolume delete {} +`
- **Defragment active subvols:**  
  `sudo btrfs filesystem defragment -r -v /mnt/btrfs-pool/subvol1-docs`
- **Remove deleted subvolume metadata:**  
  `sudo btrfs balance start -dusage=0 /mnt`

---

### 2.6 Monitoring & Alerts
- **Disk space alert:** custom cron or `systemd` script parsing `btrfs fi usage -T /mnt`.
- **Email notifications:** via `smartd` and `btrfs-maintenance` timers.
- **Log review:** `sudo journalctl -k | grep BTRFS`

---

### 2.7 Recovery Notes
```bash
# Mount degraded (if disk fails)
sudo mount -o degraded,ro /dev/sd[a-c] /mnt

# Replace failed device
sudo btrfs device remove /dev/sdX /mnt
sudo btrfs device add /dev/sdY /mnt
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt
```

---

### 2.8 Quarterly Health Review Checklist
| Task | Tool / Command | Expectation |
|-------|----------------|--------------|
| Scrub results | `btrfs scrub status /mnt` | No errors |
| SMART summary | `smartctl -H /dev/sd[a-c]` | PASSED |
| Space report | `btrfs fi usage -T /mnt` | <85% used, >10% unallocated |
| Snapshot inventory | `btrfs subvolume list -p /mnt | grep .snapshots` | All key subvols covered |
| Backup test | Mount backup, run `btrfs send --dry-run` | No errors |
| Podman networks | `podman network ls` | All expected networks present |

---

**End of Addendum — Fedora-HTPC (2025-10-25)**
