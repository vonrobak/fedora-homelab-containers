
# Storage & Data Architecture — Authoritative (Updated 2025-10-25)

**Owner:** patriark 
**Host:** `fedora-htpc`
**FS stack:** LUKS → BTRFS only on external back up drives. System SSD and btrfs-pool are both currently unencrypted.
**Goals:** Security, reliability, usability, performance, clean integration with Traefik/Tinyauth/Podman; future‑proofing for Nextcloud and databases. Future services like Immich, Grafana+Prometheus+Loki and others in pipeline.

---

## 1) High‑Level Architecture (Data ↔ Control)

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

```

- **Configs/metadata** on **NVMe SSD** for low latency.
- **Bulk data** on **BTRFS multi‑device HDD pool** with snapshots, quotas, and send/receive backups.
- **Databases and Redis** on **SSD** (NOCOW) for durability + latency; user files stay **COW** for snapshotting.

---

## 2) Concrete Layout (canonical)

### 2.1 System SSD (BTRFS)
Subvolumes:
- `root` → `/`
- `home` → `/home`

SSD folders relating to podman homelab services:
- `~/containers/config/<svc>` — configs
- `~/containers/db/<svc>` — DB/Redis (apply `chattr +C` once when creating) - not yet configured
- `~/containers/docs` — documentation folder. Be mindful of directory structure
- `~/containers/scripts`, `~/containers/secrets`
- `~/containers/quadlets` → symlink to `~/.config/containers/systemd`

Recommended mount opts (SSD): `compress=zstd:1,ssd,discard=async,noatime`

### 2.2 Data Pool (BTRFS multi‑device)
**Mountpoint to use in documentation:** `/mnt/btrfs-pool`

> **Note:** If your system currently mounts the pool at `/mnt`, either keep it and set `POOL=/mnt` when running commands, or switch fstab to mount the pool at `/mnt/btrfs-pool`. All paths below assume `POOL=/mnt/btrfs-pool`.

**Top‑level subvolumes (authoritative names):**
```
{
POOL
}/
  ├─ subvol1-docs           (Documents. Intended for Nextcloud)
  ├─ subvol2-pics           (Pictures. Art collection, wallpapers, memes etc. Intended for Nextcloud)
  ├─ subvol3-opptak         (Private mobile recordings. Intended for Immich and Nextcloud)
  ├─ subvol4-multimedia     (Jellyfin media; read‑only to consumers)
  ├─ subvol5-music          (Jellyfin media; read‑only to consumers)
  ├─ subvol6-tmp            (temporary/cache areas)
  └─ subvol7-containers     (container persistent data; e.g. nextcloud-data)
```

**Suggested fstab entries:**
```ini
# Data pool — mount at /mnt/btrfs-pool (update UUID to match your pool)
UUID=<pool-uuid>  /mnt/btrfs-pool  btrfs  compress=zstd:1,space_cache=v2,noatime,autodefrag,commit=120  0 0

# Read‑only binds for media consumers
/mnt/btrfs-pool/subvol4-multimedia  /srv/media/multimedia  none  bind,ro  0 0
/mnt/btrfs-pool/subvol5-music       /srv/media/music       none  bind,ro  0 0
```

---

## 3) Podman Networks — Current, Verified

The following user‑defined bridges exist and are in use:

| Network name              | CIDR        | Members (examples)                              | Notes |
|---------------------------|-------------|--------------------------------------------------|-------|
| `systemd-reverse_proxy`   | 10.89.2.0/24| traefik (`10.89.2.3`), tinyauth (`.5`), crowdsec (`.2`), jellyfin (as `eth1`, `.4`) | Public ingress L7 zone. |
| `systemd-media_services`  | 10.89.1.0/24| jellyfin (`10.89.1.2`)                          | Media plane for Jellyfin. |
| `systemd-auth_services`   | 10.89.3.0/24| *(no members shown in dump)*                     | Reserved for auth‑adjacent apps. |
| `web_services`            | 10.89.0.0/24| *(no members shown in dump)*                     | General web app network (currently idle). |
| `podman` (default)        | 10.88.0.0/16| *(no members in dump)*                           | Default bridge; prefer app‑specific nets. |

**Principles:**
- Keep Traefik on **`systemd-reverse_proxy`** and (optionally) join per‑app nets it must reach.
- Media consumers (e.g., Jellyfin) join their **service net** and optionally **reverse_proxy** for ingress.
- Databases/Redis should live on a dedicated **db_net** (create when deploying), and apps that need DB join it as a **second** network.

> If you add Nextcloud: create `nextcloud_net (10.89.11.0/24)` and `db_net (10.89.21.0/24)`. Traefik joins `systemd-reverse_proxy` + `nextcloud_net`; Nextcloud joins `nextcloud_net` (+ `db_net`); MariaDB/Redis **only** on `db_net`.

---

## 4) BTRFS Controls & Policies

- **Profiles:** target **Data = RAID1** and **Metadata/System = RAID1** (or `raid1c3` when available and with ≥3 devices). 
- **Compression:** `zstd:1` for parity with current mounts (increase later if desired).
- **Quotas:** enable qgroups on the pool; use per‑subvolume limits for Nextcloud/others.
- **Snapshots:** read‑only snapshots per key subvol; retention guideline **24 hourly / 14 daily / 8 weekly**.
- **Send/Receive:** replicate snapshots to the external 18 TB BTRFS; keep an off‑site yearly clone.
- **Scrub & SMART:** monthly scrubs; weekly SMART with alerts.

---

## 5) Nextcloud & Existing Subvolumes

**Option A: External Storage app** mounting `subvol1-docs`, `subvol2-pics`, `subvol3-opptak`.
**Option B: Bind‑mount into `nextcloud-data`** under `subvol7-containers/nextcloud-data` for tighter integration.
- Make Nextcloud the **only writer** to any bind‑mounted trees.
- Keep user files on **COW** subvols; **NOCOW** only for DB/Redis on SSD.
- Do **not** expose `.snapshots` within the Nextcloud data tree.

---

## 6) Backup & 3‑2‑1 (as implemented)

- **Primary:** RO BTRFS snapshots.
- **Secondary:** `btrfs send` to **18 TB external** at `/run/media/patriark/WD-18TB/.snapshots`.
- **Tertiary/off‑site:** clone to second 18 TB annually.
- Refresh pool exports after the RAID conversion (below) to realign with current state.

---

## 7) Step‑by‑Step: Add 4 TB Disk **and** Convert Data → RAID1

Assumptions:
- New disk is physically installed and visible as, e.g., `/dev/sdX` (replace `sdX` accordingly).
- Pool is mounted at **`/mnt/btrfs-pool`**. If not, set `POOL=/mnt` in the snippets.

### 7.1 Pre‑flight checks (read‑only / safe)
```bash
export POOL=/mnt/btrfs-pool   # or /mnt if that's your current mount
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID,FSTYPE
sudo btrfs filesystem show
sudo btrfs fi usage -T "$POOL"
sudo btrfs scrub status "$POOL"
```

**Confirm:**
- Pool is healthy (no uncorrectable errors).
- You have headroom for metadata movement (new 4 TB will provide plenty).

### 7.2 Add the disk to the pool
```bash
# Replace /dev/sdX with the new 4TB device node
sudo btrfs device add /dev/sdX "$POOL"

# Verify it’s listed
sudo btrfs filesystem show
```

### 7.3 Convert profiles to RAID1 (data + metadata)
```bash
# Convert both data and metadata; this will rebalance across all devices
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 "$POOL"

# Monitor progress (poll)
watch -n 10 'sudo btrfs balance status "$POOL"'
```

> Expect heavy I/O; run during a quiet window. You can pause/resume:
```bash
# Pause
sudo btrfs balance pause "$POOL"
# Resume
sudo btrfs balance resume "$POOL"
```

### 7.4 Post‑convert verification
```bash
sudo btrfs fi usage -T "$POOL"
sudo btrfs filesystem df "$POOL"
sudo btrfs device stats "$POOL"
```

Look for `Data, RAID1` and `Metadata, RAID1`. Ensure **Unallocated** is reasonable (>10% ideally) and that usage dropped below the alert threshold.

### 7.5 Optional: advance to `raid1c3` (future)
When kernel/progs and free space allow (and with ≥3 devices), you can increase redundancy:
```bash
sudo btrfs balance start -dconvert=raid1c3 -mconvert=raid1c3 "$POOL"
```

### 7.6 Quotas & per‑tree accounting
```bash
sudo btrfs quota enable "$POOL"
sudo btrfs qgroup show -reF "$POOL" | head

# Example limits (adapt to your needs)
sudo btrfs qgroup limit 500G "$POOL/subvol2-pics"
sudo btrfs qgroup limit 1T   "$POOL/subvol1-docs"
```

### 7.7 Re‑enable snapshot/backup cadence
- Re‑run snapshot timers after the balance finishes.  
- Perform a fresh **incremental btrfs send** to the 18 TB external target for each protected subvolume.

---

## 8) Operational Runbooks (concise)

- **Snapshots:** per‑subvol systemd timers; retain 24/14/8.  
- **Replication:** weekly incremental `btrfs send` off‑site; yearly clone refresh.  
- **Scrub:** monthly per device.  
- **SMART:** weekly; alert on reallocated/pending sectors.  
- **Space guard:** alert at 85% pool usage or when **Unallocated** < 10%.

---

## 9) Security Notes

- Full‑disk encryption with LUKS; keep header backups offline.  
- Bind media to apps **read‑only**; apply SELinux labels with `:Z` on Podman binds.  
- Secrets on SSD with strict permissions; never in Git.

---

### Appendix A — Quick reference commands

```bash
# Pool status
sudo btrfs fi usage -T /mnt/btrfs-pool
sudo btrfs device stats /mnt/btrfs-pool
sudo btrfs balance status /mnt/btrfs-pool

# Snapshots (example layout)
/mnt/btrfs-pool/.snapshots/<subvol>/hourly-YYYYmmddHH
/mnt/btrfs-pool/.snapshots/<subvol>/daily-YYYYmmdd
/mnt/btrfs-pool/.snapshots/<subvol>/weekly-YYYYww
```

---

**End of document.**
