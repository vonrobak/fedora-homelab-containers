# Storage & Data Architecture — Tailored Addendum (2025‑10‑24)

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

