# Storage & Data Architecture — Revised

**Owner:** patriark  
**Host:** `fedora-htpc`  
**FS stack:** LUKS → BTRFS  
**Goals:** Security, reliability, usability, performance, clean integration with Traefik/Tinyauth/Podman; future‑proofing for Nextcloud and databases.

---

## 1) High‑Level Architecture (Data Plane ↔ Control Plane)

```
[Clients]
   │ HTTPS
   ▼
[Traefik] — [Tinyauth] — [CrowdSec]
   │
   │ (Podman networks: reverse_proxy + per‑app nets)
   ▼
[App containers]
   │
   ▼
[Persistent volumes]
   │   ↳  Config (SSD)
   │   ↳  Hot data (SSD)  ← DB, caches, small metadata
   │   ↳  Cold data (HDD pool)  ← media, docs, photos, Nextcloud user data
   ▼
[LUKS‑encrypted BTRFS: system SSD + multi‑device HDD pool]
```

- **Config/metadata** lives on the **NVMe SSD** for low latency.
- **Bulk data** lives on the **BTRFS multi‑device HDD pool** with snapshots, quotas, and send/receive backups.
- **Databases and Redis** (for Nextcloud) will live on **SSD** (NOCOW) for durability + latency.

---

## 2) Concrete Layout

### 2.1 System SSD (128 GB NVMe, BTRFS)
- Subvolumes:
  - `@root` → `/`
  - `@home` → `/home`
  - `@containers-config` → `~/containers/config`
  - `@containers-scripts` → `~/containers/scripts`
  - `@containers-docs` → `~/containers/docs`

**Mount options (fstab):**
```
UUID=<nvme-uuid>  /              btrfs  subvol=@root,compress=zstd:3,ssd,discard=async,noatime  0 0
UUID=<nvme-uuid>  /home          btrfs  subvol=@home,compress=zstd:3,ssd,discard=async,noatime  0 0
```

### 2.2 Data Pool (HDDs, BTRFS multi‑device)
**Current devices:** 1×2 TB + 2×4 TB, adding +4 TB soon.  
**Target profiles:**
- **Data profile:** `raid1` (or `raid1c3` when 3+ devices and kernel supports) for redundancy.
- **Metadata:** `raid1` (or `raid1c3`), always redundant.

**Top‑level subvols (example names):**
```
/mnt/pool/
  ├─ @docs            (Nextcloud external dir)
  ├─ @pics            (Nextcloud external dir)
  ├─ @opptak          (Immich/Nextcloud)
  ├─ @multimedia      (Jellyfin media) [RO mounts to apps]
  ├─ @music           (Jellyfin media) [RO mounts to apps]
  ├─ @tmp             (build/cache/scratch)
  └─ @containers      (all container persistent data on pool)
       ├─ nextcloud/        (app data, not DB)
       ├─ databases/        (use SSD for DB; this path reserved for bulk DB exports)
       └─ jellyfin/
```

**Mount options (fstab):**
```
UUID=<pool-uuid>  /mnt/pool  btrfs  compress=zstd:5,space_cache=v2,noatime,autodefrag  0 0
```

**RO bind mounts for media to apps:**
```
# /etc/fstab or systemd .mount units
/mnt/pool/@multimedia  /srv/media/multimedia   none  bind,ro  0 0
/mnt/pool/@music       /srv/media/music        none  bind,ro  0 0
```

---

## 3) BTRFS Best‑Practice Controls

### 3.1 Profiles & conversion
- Create or convert to redundant profiles:
```
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/pool
# (raid1c3 if supported, with 3+ devices)
```

### 3.2 Quotas & project accounting (for Nextcloud users)
```
sudo btrfs quota enable /mnt/pool
sudo btrfs qgroup limit 500G /mnt/pool/@pics
sudo btrfs qgroup limit 1T   /mnt/pool/@docs
```

### 3.3 Snapshots & retention (per subvolume)
```
# Example snapshot scheme (hourly, daily, weekly via systemd-timers)
/mnt/pool/.snapshots/<subvol>/hourly-YYYYmmddHH
/mnt/pool/.snapshots/<subvol>/daily-YYYYmmdd
/mnt/pool/.snapshots/<subvol>/weekly-YYYYww
```
- Keep 24 hourly, 14 daily, 8 weekly by default.
- Use **read‑only** snapshots for integrity and backup source.

### 3.4 Send/receive off‑site
```
# initial
sudo btrfs send /mnt/pool/.snapshots/@docs/daily-20251023 | ssh backup "btrfs receive /backup/patriark/@docs"
# incremental
sudo btrfs send -p daily-20251023 daily-20251101 | ssh backup "btrfs receive /backup/patriark/@docs"
```

### 3.5 Scrub & SMART
- `btrfs scrub` monthly (timer): detects and repairs silent corruption.
- SMART weekly checks + email alerts.

### 3.6 NOCOW for DB/caches (on SSD)
```
# For paths that hold DB files (MariaDB) or Redis append-only logs
mkdir -p /home/patriark/containers/db
chattr +C /home/patriark/containers/db
```
> Keep backups/snapshots on a **COW** subvolume; only DB working dirs get NOCOW.

---

## 4) Podman Volumes & Mapping Policy

### 4.1 Principles
- **Configs** → SSD: `~/containers/config/<svc>`
- **Hot app data/DB/Redis** → SSD (NOCOW): `~/containers/db/<svc>`
- **Bulk data** → HDD pool subvols under `/mnt/pool/@containers/<svc>` (or domain‑specific subvols like `@docs`, `@pics`).
- **Media catalogs** mounted **read‑only** into services that only need to read (e.g., Jellyfin).

### 4.2 Example (Nextcloud)
- Web app container mounts:
```
Volume=%h/containers/config/nextcloud:/var/www/html:Z
Volume=/mnt/pool/@containers/nextcloud:/var/www/html/data:Z
```
- Database container mounts (SSD):
```
Volume=%h/containers/db/mariadb:/var/lib/mysql:Z
```

### 4.3 Example (Jellyfin)
```
Volume=%h/containers/config/jellyfin:/config:Z
Volume=/srv/media/multimedia:/media/multimedia:ro,Z
Volume=/srv/media/music:/media/music:ro,Z
```

---

## 5) Network Segmentation Model (Podman + Traefik)

### 5.1 Baseline networks
- `systemd-reverse_proxy` (10.89.2.0/24): Traefik, CrowdSec bouncer, Tinyauth.
- `nextcloud_net` (10.89.11.0/24): Nextcloud app.
- `db_net` (10.89.21.0/24): Databases/Redis (no direct internet‑facing apps).

**Rules:**
- Traefik joins **reverse_proxy** and per‑app nets that it must reach (e.g., `nextcloud_net`).
- Apps join their **own app net** plus (optionally) **reverse_proxy** only if Traefik cannot join the app net. Prefer the former for tighter isolation.
- Databases live **only** on `db_net`. Apps that need DB join `db_net` as a second network.

### 5.2 Quadlet snippets

**Traefik (dual‑homed):**
```
Network=systemd-reverse_proxy
Network=nextcloud_net
```

**Nextcloud (dual‑homed or single‑homed):**
```
Network=nextcloud_net
# Optional: also join reverse_proxy if Traefik is kept single-homed
# Network=systemd-reverse_proxy
```

**MariaDB:**
```
Network=db_net
```

### 5.3 Why this is safer
- L7 ingress (Traefik) is the only component that touches the public edge.
- App ↔ DB traffic never shares the same broadcast domain as reverse_proxy.
- Compromise blast radius is minimized per‑service.

---

## 6) Nextcloud + Existing Folders/Subvolumes

### 6.1 Options
1) **Nextcloud External Storage app** to mount existing subvols (`@docs`, `@pics`) as user‑visible folders.
   - Pros: No need to physically move. Nextcloud indexes via app; permissions stay POSIX.
   - Cons: Some apps expect internal storage; sharing/ACL nuances; previews may be slower.

2) **Bind‑mount existing subvols into Nextcloud data directory** under a dedicated user namespace (e.g., `/var/www/html/data/nc-files/docs → /mnt/pool/@docs`).
   - Pros: Becomes “native” storage; broad app compatibility; easy quotas via BTRFS qgroups.
   - Cons: Requires careful UID/GID and permission mapping; potential to bypass Nextcloud if the path is shared elsewhere.

**Recommendation:** Start with **External Storage** for `@docs` and `@pics`. For heavy use and app compatibility, migrate to **bind‑mount** under `data/` with strict permissions and separate subvolumes per logical area.

### 6.2 Risks & mitigations
- **Bypass risk:** If users can write to the same path outside Nextcloud, fileids get out of sync. → *Mitigation:* Make Nextcloud the **only** write path; mount read‑only elsewhere; run `occ files:scan --all` after controlled imports.
- **Permissions drift:** UID/GID mismatch between host and container user (`www-data`). → *Mitigation:* Use `podman unshare chown`, or mount via ACLs (`setfacl -m u:33:rwx`).
- **Snapshot visibility:** Snapshots mounted under the data tree can confuse file scans. → *Mitigation:* Mount snapshots outside Nextcloud’s data root; never expose `.snapshots` inside Nextcloud.
- **NOCOW mismatch:** Nextcloud data should stay **COW** (for snapshots/dedupe). Only DB/caches get NOCOW.
- **Case‑sensitivity:** Keep consistent (Linux default). Avoid SMB/CIFS case‑folding against the same dirs.
- **Preview/cache growth:** Large photo libraries explode preview cache. → Use Redis, enable `preview:generate-all` via timer, store previews on SSD if capacity allows.

---

## 7) Capacity & Growth Plan

- **Today:** ~90% of 10 TB used.
- **Action:** Add +4 TB, then rebalance/convert profiles to regain free space and ensure redundancy.
```
sudo btrfs device add /dev/sdX /mnt/pool
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/pool
```
- **Goal:** <80% usage after expansion. Set monitoring alert at 85%.
- **Cold archive tier:** Consider an external USB BTRFS disk for quarterly deep snapshots sent via `btrfs send`.

---

## 8) Operational Runbooks

### 8.1 Snapshot/backup timers (systemd user units)
- `btrfs-snap@.service` + `{hourly,daily,weekly}` timers per subvol.
- `btrfs-send@.service` + weekly off‑site replication.

### 8.2 Scrub/SMART
- `btrfs-scrub@.timer` monthly per device.
- `smartd` with email alerts.

### 8.3 Health checks
- Disk space thresholds with `btrfs fi usage` parsing.
- Alert on `unallocated` falling below 10% to avoid ENOSPC.

---

## 9) Security

- **Full‑disk encryption:** LUKS for HDDs and SSD; store LUKS headers backup offline.
- **RO mounts to apps** for media; **principle of least privilege** for bind mounts.
- **Secrets** on SSD with `chmod 600`, never in Git.
- **Integrity:** Prefer RO snapshots for backup sources.

---

## 10) Migration Checklist (to this layout)

1. Create subvolumes and mount points as above.
2. Enable BTRFS quotas and set initial qgroups.
3. Move configs to SSD; DB working dirs to SSD (NOCOW).
4. Mount media read‑only for consumers.
5. Create Podman networks `nextcloud_net` and `db_net`; re‑wire quadlets.
6. Add systemd snapshot/backup/scrub timers.
7. Validate with Nextcloud + Jellyfin end‑to‑end tests.

---

## 11) Appendix: Podman network creation

```
podman network create systemd-reverse_proxy
podman network create --subnet 10.89.11.0/24 nextcloud_net
podman network create --subnet 10.89.21.0/24 db_net
```

> Traefik container should be on `systemd-reverse_proxy` **and** any app nets it must reach. Databases only on `db_net`.

---

# Storage & Data Architecture — Tailored Addendum to 20251023-storage_data_architecture_revised.md (made after more detailed information about configuration, quadlets and directory structure, 2025‑10‑24)

This addendum applies real measurements from the host and refines the architecture and runbooks. Keep it with the main "Storage & Data Architecture — Revised" doc.

---

## 0) Tailored snapshot (from host outputs)

**Root/SSD (NVMe, 117.7 GB, BTRFS)**
- `/` from `subvol=root`, `/home` from `subvol=home`, `compress=zstd:1`.
- ~30 GiB free by usage (allocated nearly full—normal for BTRFS).
- Snapshots under `/home/patriark/.snapshots/...`.

**Data pool (BTRFS mounted at `/mnt`, label `htpc-btrfs-pool`)**
- **Devices:** `sda` 3.62 TiB + `sdb` 3.61 TiB + `sdc` 1.80 TiB → **Total 9.10 TiB**.
- **Usage:** **Used 8.23 TiB**, **Free ≈ 885 GiB**, **Unallocated 48 GiB**.
- **Profiles:** **Data = single**, **Metadata = RAID1**, **System = RAID1**.
- **Subvols:** `/mnt/btrfs-pool/subvol1-docs`, `/subvol2-pics`, `/subvol3-opptak`, `/subvol4-multimedia`, `/subvol5-music`, `/subvol6-tmp`, `/subvol7-containers`.

**Networking/containers**
- Networks: `systemd-reverse_proxy (10.89.2.0/24)`, `systemd-media_services`, `systemd-auth_services`, `web_services`, default `podman`.
- Running: `traefik`, `tinyauth`, `crowdsec`, `jellyfin` (dual-homed: media + reverse_proxy).
- Quadlets: none active (containers likely run manually).
- Security: SELinux **Enforcing**; firewalld zone `FedoraWorkstation` allows 80/443/tcp, 8096/tcp, 7359/udp, services mdns/samba/ssh.

---

## 1) Critical changes (host‑specific)

1. **Make Data redundant** (highest priority). Current **Data=single**; convert to **RAID1** now. Consider **RAID1c3** later if you keep ≥3 drives and tools support it.
```bash
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt
```
> Expect heavy I/O. Run during a quiet window. Ensure ≥15% free preferred; you have ~885 GiB free which is adequate.

2. **Enable qgroups** (for per-tree accounting & quotas):
```bash
sudo btrfs quota enable /mnt
sudo btrfs qgroup show -reF /mnt
```

3. **Read‑only media mounts** (principle of least privilege):
```bash
sudo mkdir -p /srv/media/{multimedia,music}
echo "/mnt/btrfs-pool/subvol4-multimedia /srv/media/multimedia none bind,ro 0 0" | sudo tee -a /etc/fstab
echo "/mnt/btrfs-pool/subvol5-music      /srv/media/music      none bind,ro 0 0" | sudo tee -a /etc/fstab
sudo mount -a
```

4. **Create per‑app networks** for Nextcloud & DB tier:
```bash
podman network create --subnet 10.89.11.0/24 nextcloud_net
podman network create --subnet 10.89.21.0/24 db_net
```
- Traefik joins **reverse_proxy + nextcloud_net**.
- Nextcloud joins **nextcloud_net + db_net**.
- MariaDB/Redis join **db_net only**.

5. **SSD placement for DB/Redis (NOCOW), COW for files**
```bash
mkdir -p $HOME/containers/db/{mariadb,redis}
chattr +C $HOME/containers/db/{mariadb,redis}
```

---

## 2) Nextcloud — Elegant Quadlet Implementation (tailored)

### 2.1 Host paths
- Configs (SSD): `%h/containers/config/{traefik,tinyauth,nextcloud}`
- DB/Redis (SSD, NOCOW): `%h/containers/db/{mariadb,redis}`
- Nextcloud data (COW, snapshots): `/mnt/btrfs-pool/subvol7-containers/nextcloud-data`
- Optional RO media (for previews): `/mnt/btrfs-pool/subvol4-multimedia`, `/mnt/btrfs-pool/subvol5-music`

### 2.2 Quadlets (drop in `~/.config/containers/systemd/`)

#### `container-traefik.container`
```ini
[Unit]
Description=Traefik Reverse Proxy
[Container]
Image=docker.io/library/traefik:v3.2
Network=systemd-reverse_proxy
Network=nextcloud_net
PublishPort=80:80
PublishPort=443:443
Volume=%h/containers/config/traefik:/etc/traefik:Z
[Install]
WantedBy=default.target
```

#### `container-tinyauth.container`
```ini
[Unit]
Description=Tinyauth
[Container]
Image=ghcr.io/steveiliop56/tinyauth:v4
Network=systemd-reverse_proxy
Volume=%h/containers/config/tinyauth:/config:Z
[Install]
WantedBy=default.target
```

#### `container-mariadb.container`
```ini
[Unit]
Description=MariaDB for Nextcloud
[Container]
Image=docker.io/library/mariadb:11
Network=db_net
Env=MYSQL_ROOT_PASSWORD=__set_me__
Env=MYSQL_DATABASE=nextcloud
Env=MYSQL_USER=nextcloud
Env=MYSQL_PASSWORD=__set_me__
Volume=%h/containers/db/mariadb:/var/lib/mysql:Z
[Install]
WantedBy=default.target
```

#### `container-redis.container`
```ini
[Unit]
Description=Redis for Nextcloud
[Container]
Image=docker.io/library/redis:7
Network=db_net
Volume=%h/containers/db/redis:/data:Z
[Install]
WantedBy=default.target
```

#### `container-nextcloud-fpm.container`
```ini
[Unit]
Description=Nextcloud PHP-FPM
[Container]
Image=docker.io/library/nextcloud:stable-fpm
Network=nextcloud_net
Network=db_net
Volume=%h/containers/config/nextcloud:/var/www/html:Z
Volume=/mnt/btrfs-pool/subvol7-containers/nextcloud-data:/var/www/html/data:Z
# Optional RO media for previews only
# Volume=/mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:ro,Z
# Volume=/mnt/btrfs-pool/subvol5-music:/media/music:ro,Z
[Install]
WantedBy=default.target
```

#### `container-nextcloud-nginx.container`
```ini
[Unit]
Description=Nextcloud Nginx (front for FPM)
[Container]
Image=docker.io/library/nginx:stable-alpine
Network=nextcloud_net
Volume=%h/containers/config/nextcloud/nginx.conf:/etc/nginx/nginx.conf:Z
Volume=%h/containers/config/nextcloud/conf.d:/etc/nginx/conf.d:Z
Volume=%h/containers/config/nextcloud:/var/www/html:Z
[Install]
WantedBy=default.target
```

Enable:
```bash
systemctl --user daemon-reload
systemctl --user enable --now container-{traefik,tinyauth,mariadb,redis,nextcloud-fpm,nextcloud-nginx}.service
```

### 2.3 Minimal Nginx for FPM (`%h/containers/config/nextcloud/nginx.conf`)
```nginx
worker_processes auto;
events { worker_connections 1024; }
http {
  include       /etc/nginx/mime.types;
  sendfile on;
  upstream php-handler { server nextcloud-fpm:9000; }
  server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php index.html /index.php$request_uri;

    location = /robots.txt  { allow all; log_not_found off; access_log off; }
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ { deny all; }

    location ~ \.php(?:$|/) {
      include fastcgi_params;
      fastcgi_split_path_info ^(.+\.php)(/.+)$;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      fastcgi_param PATH_INFO $fastcgi_path_info;
      fastcgi_pass php-handler;
      fastcgi_read_timeout 3600;
      fastcgi_buffering off;
    }
    location / { try_files $uri $uri/ /index.php$request_uri; }
  }
}
```

### 2.4 Traefik → Nextcloud with Tinyauth ForwardAuth (`%h/containers/config/traefik/dynamic.yml`)
```yaml
http:
  middlewares:
    tinyauth-forward:
      forwardAuth:
        address: "http://tinyauth:8080/verify"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Auth-User
          - X-Auth-Email
  routers:
    nextcloud:
      rule: "Host(`nextcloud.example.com`)"
      entryPoints: ["websecure"]
      service: nextcloud-nginx
      middlewares:
        - tinyauth-forward
  services:
    nextcloud-nginx:
      loadBalancer:
        servers:
          - url: "http://nextcloud-nginx:80"
```
> Adjust hostnames and any extra middlewares (rate limits, IP allowlists) to your policy. Exempt specific paths only if required by clients.

### 2.5 Nextcloud tuning
- **MariaDB 11 + Redis**; set `memcache.local`, `memcache.locking`, `memcache.distributed` in `config.php`.
- **CRON:** every 5 minutes via user timer:
```bash
systemd-run --user --on-calendar='*:0/5' --unit=nc-cron --property=RemainAfterExit=yes \
  podman exec nextcloud-fpm php -f /var/www/html/cron.php
```
- **Previews:** consider SSD if space allows; otherwise schedule preview generation off‑peak.

### 2.6 Integrating existing subvols
- **Start with External Storage app** mapping:
  - `subvol1-docs` → Docs
  - `subvol2-pics` → Pictures
  - `subvol3-opptak` → Opptak
- For apps requiring internal storage, **bind‑mount** into `data/` and make Nextcloud the **only writer**. Don’t expose `.snapshots` under `data/`.
- Fix ownership for container user (uid 33) if needed:
```bash
podman unshare chown -R 33:33 /mnt/btrfs-pool/subvol7-containers/nextcloud-data
```

---

## 3) Runbooks (aligned to your layout)

**Snapshots** (hourly/daily/weekly, read‑only) for `subvol1-docs`, `subvol2-pics`, `subvol3-opptak`, and `nextcloud-data`. Keep `.snapshots` **outside** the Nextcloud `data/` tree.

**Scrub** monthly per device; **SMART** weekly; alert at pool usage >85%.

**Send/receive**: weekly incremental to an external/offsite BTRFS target.

**Firewall**: keep 80/443 at Traefik only; no direct container ports to LAN unless explicitly required.

---

## 4) Risk notes (and mitigations)
- **Current Data=single** → **convert to RAID1** ASAP to avoid data loss on a single-disk failure.
- **Bypass writes** (if data is writable outside Nextcloud) → make Nextcloud the **only writer**, or mount RO elsewhere and run `occ files:scan` only for controlled imports.
- **SELinux** is enforcing → always use `:Z` on bind mounts; inspect denials with `audit2why` if needed.
- **Root SSD headroom** → set alert when free <20 GiB (`btrfs fi usage -T /`).

---

**End of addendum.**

