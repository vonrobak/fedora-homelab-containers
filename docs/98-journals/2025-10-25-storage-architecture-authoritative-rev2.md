
# Storage & Data Architecture — Authoritative (Updated 2025-10-25, Rev.2)

**Owner:** patriark  
**Host:** `fedora-htpc`  
**FS stack:** BTRFS (un­encrypted) + LUKS-encrypted backup drives  
**Goals:** Security, reliability, usability, performance, clean integration with Traefik/Tinyauth/Podman; future-proofing for Nextcloud and databases.

---

## 1) High-Level Architecture (Data ↔ Control)

```
[Clients]
   │ HTTPS
   ▼
[Traefik] — [Tinyauth] — [CrowdSec]
   │
   │ (Podman networks per app + reverse_proxy)
   ▼
[App containers]
   │
   ▼
[Persistent volumes]
   │   ↳  Config (SSD)
   │   ↳  Hot data (SSD, NOCOW for DB/Redis only)
   │   ↳  Cold data (BTRFS HDD pool)  ← media, docs, photos, Nextcloud user data
   ▼
[BTRFS: system SSD mounted / + multi-device HDD pool mounted /mnt; external backup drives use LUKS]
```

---

## 2) Concrete Layout (canonical)

## 🗂️ Directory Structure Tree

```
/home/patriark/containers/
│
├── config/                          # Service configurations
│   ├── traefik/
│   │   ├── traefik.yml             # Static configuration
│   │   ├── dynamic/                # Dynamic configurations
│   │   │   ├── routers.yml         # Route definitions
│   │   │   ├── middleware.yml      # Security & auth
│   │   │   ├── tls.yml             # TLS options
|   |   │   ├── security-headers-strict.yml     # user needs help getting a deeper understanding of this
│   │   │   └── rate-limit.yml      # Rate limiting rules
│   │   ├── letsencrypt/            # SSL certificates
│   │   │   └── acme.json           # Let's Encrypt data
│   │   └── certs/                  # (deprecated)
│   │
│   ├── crowdsec/                   # CrowdSec config (auto-generated)
│   ├── jellyfin/                   # Jellyfin configuration
│   └── tinyauth/                   # (config via env vars)
│
├── data/                           # Persistent service data
│   ├── crowdsec/
│   │   ├── db/                     # Decision database
│   │   └── config/                 # Runtime config
│   ├── jellyfin/                   # Media library metadata
│   └── nextcloud/                  # (to be created)
│
├── scripts/                        # Automation scripts
│   ├── cloudflare-ddns.sh          # DNS updater - with cron or systemd (do not remember) jobs to update every 30 mins
|   ├── collect-storage-info.sh     # recent and very useful script but with some errors that needs to be revised
|   ├── deploy-jellyfin-with-traefik.sh # probably legacy and ready for archival or revision
|   ├── fix-podman-secrets.sh       # legacy - might be ready for archival or thorough scrutiny
|   ├── homelab-diagnose.sh         # probably legacy - ready for revision
|   ├── jellyfin-manage.sh          # legacy but probably useful - needs to be revisited and explained
|   ├── jellyfin-status.sh          # same as above
|   ├── organize-docs.sh            # this might be a useful tool to organize files in documentation directory but likely needs revision as data structure is changed since it was written
|   ├── security-audit.sh           # legacy but might contain some valid checks
|   ├── show-pod-status.sh          # legacy but likely 
|   └── survey.sh                   # recent but with some bugs - needs revision to be useful
│
├── secrets/                        # Sensitive data (chmod 600)
│   ├── cloudflare_token           # API token
│   ├── cloudflare_zone_id         # Zone ID
|   ├── redis_password              # Likely legacy from previous failed Authelia experiment
|   └── smtp_password               # Definitely legacy from previous failed Authelia experiment
│
├── backups/                        # Configuration backups in addition to btrfs snapshots - likely superfluous
│
├── docs/                  # Documentation
├──     00-foundation/
│       ├── day01-learnings.md
│       ├── day02-networking.md
│       ├── day03-pod-commands.md
│       ├── day03-pods.md
│       ├── day03-pods-vs-containers.md
│       └── podman-cheatsheet.md
├──     10-services/
│       ├── day04-jellyfin-final.md
│       ├── day06-complete.md
│       ├── day06-quadlet-success.md
│       ├── day06-traefik-routing.md
│       ├── day07-yubikey-inventory.md
│       └── quadlets-vs-generated.md
├──     20-operations/
│       ├── 20251023-storage_data_architecture_revised.md
│       ├── DAILY-PROGRESS-2025-10-23.md
│       ├── HOMELAB-ARCHITECTURE-DIAGRAMS.md
│       ├── HOMELAB-ARCHITECTURE-DOCUMENTATION.md
│       ├── NEXTCLOUD-INSTALLATION-GUIDE.md
│       ├── QUICK-REFERENCE.md
│       ├── readme-week02.md
│       ├── storage-layout.md
│       └── TODAYS-ACHIEVEMENTS.md
├──     30-security/
│       └── TINYAUTH-GUIDE.md
├──     90-archive/
│       ├── 20251024-storage_data_architecture-and-2fa-proposal.md
│       ├── 2025-10-24-storage_data_architecture_tailored_addendum.md
│       ├── checklist-week02.md
│       ├── DOMAIN-CHANGE-SUMMARY.md
│       ├── progress.md
│       ├── quick-reference.bak-20251021-172023.md
│       ├── quick-reference.bak-20251021-221915.md
│       ├── quick-reference.md
│       ├── quick-reference-v2.md
│       ├── quick-start-guide-week02.md
│       ├── readme.bak-20251021-172023.md
│       ├── readme.bak-20251021-221915.md
│       ├── readme.md
│       ├── revised-learning-plan.md
│       ├── SCRIPT-EXPLANATION.md
│       ├── summary-revised.md
│       ├── TOMORROW-QUICK-START.md
│       ├── week02-failed-authelia-but-tinyauth-goat.md
│       ├── week02-implementation-plan.md
│       └── week02-security-and-tls.md
└── 99-reports/
        ├── 20251024-configurations-quadlets-and-more.md
        ├── 20251025-storage-architecture-authoritative.md
        ├── 20251025-storage-architecture-authoritative-rev2.md
        ├── authelia-diag-20251020-183321.txt
        ├── failed-authelia-adventures-of-week-02-current-state-of-system.md
        ├── homelab-diagnose-20251021-165859.txt
        ├── latest-summary.md
        ├── pre-letsencrypt-diag-20251022-161247.txt
        ├── script2-week2-authelia-dual-domain.md
        └── system-state-20251022-213400.txt

/home/patriark/.config/containers/systemd/          # quadlet configuration directory
├── auth_services.network           # podman bridge network - currently idle with no services
├── crowdsec.container              # CrowdSec service definition
├── jellyfin.container              # Jellyfin service definition
├── media_services.network          # Media Services podman bridge network 
├── reverse_proxy.network           # Reverse Proxy podman bridge network - members: all
├── tinyauth.container              # Tinyauth service definition
└── traefik.container               # Traefik service definition
```

### 2.1 System SSD (BTRFS)
Subvolumes:
- `root` → `/`
- `home` → `/home`

SSD folders:
- `~/containers/config/<svc>` — configs
- `~/containers/db/<svc>` — DB/Redis (apply `chattr +C` once when creating)
- `~/containers/docs` — Podman container documentation
- `~/containers/scripts` — Automation and analysis scripts
- `~/containers/secrets` — secrets relevant to podman containers and automation scripts are stored here. 600 permission for files and 700 set for directory.
- `~/containers/quadlets` → symlink to `~/.config/containers/systemd`

Snapshots:
- `~/.snapshots/home/YYYYmmddHH-hourly`
- `~/.snapshots/home/YYYYmmdd-daily`
- `~/.snapshots/home/YYYYmmdd-weekly`
- `~/.snapshots/home/YYYYmmdd-monthly`
- `~/.snapshots/root/YYYYmmdd-monthly`

Mount options (SSD): `compress=zstd:1,ssd,discard=async,noatime`

> **Encryption:** System SSD is *not encrypted*.

### 2.2 Data Pool (BTRFS multi-device)
**Mountpoint (actual):** `/mnt` — the BTRFS pool itself is mounted here; all subvolumes reside under `/mnt/btrfs-pool/`.

**Top-level subvolumes (authoritative names):**
```
/mnt/btrfs-pool/
  ├─ subvol1-docs           (Documents. Mostly personal and work related. Intended for Nextcloud with read and write permissions)
  ├─ subvol2-pics           (Pictures. Art collection, wallwapers, memes etc. Intended for Nextcloud with read and write permissions)
  ├─ subvol3-opptak         (Private mobile picture and video recordings as well as video productions and OBS streams; intended for Nextcloud with read and write permissions but heightened demands for backups)
  ├─ subvol4-multimedia     (Jellyfin media; read-only to consumers)
  ├─ subvol5-music          (Jellyfin media; read-only to consumers)
  ├─ subvol6-tmp            (temporary/cache areas)
  └─ subvol7-containers     (container persistent data; e.g. nextcloud-data)
```
subvol 1 to 5 are also smb shares on local network.

Snapshots:
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmddHH-hourly`
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-daily`
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-weekly`
- `/mnt/btrfs-pool/.snapshots/<subvol>/YYYYmmdd-monthly`

**fstab reference:**
```ini
# Data pool — mounted at /mnt (actual state)
UUID=<pool-uuid>  /mnt  btrfs  compress=zstd:1,space_cache=v2,noatime,autodefrag,commit=120  0 0

# Read-only binds for media consumers
/mnt/btrfs-pool/subvol4-multimedia  /srv/media/multimedia  none  bind,ro  0 0
/mnt/btrfs-pool/subvol5-music       /srv/media/music       none  bind,ro  0 0
```

> **Encryption:** The data pool is also *not encrypted*; only backup drives use LUKS.

---

## 3) Podman Networks — Verified (as of 2025‑10‑25)

| Network name              | CIDR        | Members (examples)                              | Notes |
|---------------------------|-------------|--------------------------------------------------|-------|
| `systemd-reverse_proxy`   | 10.89.2.0/24| traefik (`10.89.2.3`), tinyauth (`.5`), crowdsec (`.2`), jellyfin (as `eth1`, `.4`) | Public ingress / L7 zone |
| `systemd-media_services`  | 10.89.1.0/24| jellyfin (`10.89.1.2`)                          | Media plane |
| `systemd-auth_services`   | 10.89.3.0/24| *(none listed)*                                 | Reserved for auth services | currently idle
| `web_services`            | 10.89.0.0/24| *(none listed)*                                 | General-purpose web apps | currently idle
| `podman` (default)        | 10.88.0.0/16| *(none listed)*                                 | Default bridge; prefer app-specific nets |

> For Nextcloud stack: add `nextcloud_net (10.89.11.0/24)` and `db_net (10.89.21.0/24)` as needed.

---

## 4) BTRFS Controls & Policies

- **Profiles:** convert to `Data=RAID1`, `Metadata/System=RAID1` after adding the 4 TB disk.
- **Compression:** `zstd:1` (matching current mounts).
- **Quotas:** enable qgroups, set limits per subvol as needed.
- **Snapshots:** 24 hourly / 14 daily / 8 weekly, read-only.
- **Send/Receive:** replicate to 18 TB LUKS-encrypted backup drives.
- **Scrub & SMART:** monthly scrub, weekly SMART monitoring.

---

## 5) Step-by-Step — Add 4 TB Disk and Convert to RAID1

1. **Identify the new disk:**
   ```bash
   lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID,FSTYPE
   sudo btrfs filesystem show
   ```

2. **Add the disk to the pool:**
   ```bash
   sudo btrfs device add /dev/sdX /mnt
   sudo btrfs filesystem show
   ```

3. **Convert profiles:**
   ```bash
   sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt
   watch -n 10 'sudo btrfs balance status /mnt'
   ```

4. **Verify:**
   ```bash
   sudo btrfs fi usage -T /mnt
   sudo btrfs filesystem df /mnt
   ```

5. **Enable quotas & set limits:**
   ```bash
   sudo btrfs quota enable /mnt
   sudo btrfs qgroup show -reF /mnt | head
   sudo btrfs qgroup limit 500G /mnt/btrfs-pool/subvol2-pics
   ```

6. **Re-enable snapshot & backup timers** once rebalance finishes.

---

## 6) Backup & 3‑2‑1 Strategy

- **Primary:** local BTRFS snapshots.  
- **Secondary:** `btrfs send` → 18 TB external (LUKS-encrypted).  
- **Tertiary:** clone to off-site 18 TB drive annually.

---

## 7) Encryption & Security Notes

- **Encryption:** System SSD and data pool are *not encrypted*; only backup drives (the 18 TB externals) use LUKS encryption.  
- Keep LUKS header backups offline and verify they unlock properly.  
- Bind media to apps **read-only**; use `:Z` SELinux label on Podman binds.  
- Store secrets on SSD with `chmod 600`; never in Git.

---

## 8) Operational Runbooks (condensed)

- Snapshots: per-subvol timers, should be considered according to data type in each subvolume
- Replication: weekly incremental `btrfs send`.
- Scrub: monthly.
- SMART: weekly.  
- Space: warn at >85% usage or unallocated <10%.

---


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
**End of document.**
