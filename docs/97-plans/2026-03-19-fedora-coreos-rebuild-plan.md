# Fedora CoreOS Homelab Rebuild Plan

**Status:** DRAFT
**Created:** 2026-03-19
**Target:** Fedora CoreOS (replacing Fedora Workstation 43)
**Scope:** Full rebuild of 30 containers, 16 service groups — same services, improved architecture
**Prerequisite:** New ADR-020 required before execution

---

## Executive Summary

Rebuild the homelab on Fedora CoreOS to gain an immutable OS base with automatic updates (Zincati), declarative provisioning (Ignition/Butane), and simplified container orchestration using Podman pods. The migration consolidates 8 networks down to 4 by grouping tightly-coupled services into pods (shared localhost networking), eliminates the multi-network DNS resolution problem (ADR-018) for pod-internal communication, and brings the OS itself under configuration-as-code via Butane.

---

## Phase 1: Pre-Migration Preparation (on current Fedora Workstation)

### 1.1 Secrets Export

Export all 27 Podman secrets to an encrypted migration bundle:

```bash
# scripts/migration/export-secrets.sh
# Use tmpfs to avoid secrets touching persistent storage
TMPDIR=$(mktemp -d --tmpdir=/dev/shm migration-secrets.XXXXXX)
chmod 700 "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

podman secret ls --format '{{.Name}}' | while read name; do
  podman secret inspect "$name" --showsecret | jq -r '.SecretData' | base64 -d > "$TMPDIR/$name"
done
tar czf - -C "$(dirname "$TMPDIR")" "$(basename "$TMPDIR")" | gpg --symmetric > migration-secrets.tar.gz.gpg
```

### 1.2 Database Dumps (stop services first)

```bash
# MariaDB (Nextcloud)
podman exec nextcloud-db mariadb-dump -u root --all-databases > nextcloud-db.sql

# PostgreSQL (Immich)
podman exec postgresql-immich pg_dumpall -U immich > immich-db.sql

# MongoDB (Gathio)
podman exec gathio-db mongodump --archive=/data/dump.archive

# Redis/Valkey: BGSAVE triggers RDB snapshot (already in data dirs)
```

### 1.3 BTRFS Snapshots

```bash
for sv in subvol{1..7}-*; do
  btrfs subvolume snapshot -r "/mnt/btrfs-pool/$sv" "/mnt/btrfs-pool/.snapshots/migration-$sv"
done
```

### 1.4 Config Archive

```bash
git stash && tar czf containers-repo-backup.tar.gz ~/containers/
podman save localhost/alert-discord-relay:latest > alert-discord-relay-image.tar
```

### 1.5 Hardware Inventory for Butane

Collect before provisioning:
- AMD Radeon Vega GPU device paths (`/dev/dri/renderD128`, `/dev/dri/card1`)
- BTRFS pool disk identifiers (`/dev/disk/by-id/...`)
- Network interface name
- Pi-hole DNS: `192.168.1.69`

---

## Phase 2: Butane/Ignition Provisioning

### 2.1 Butane Config

Create `coreos/homelab.bu` — transpiled to `ignition.json` via `butane`:

```yaml
variant: fcos
version: "1.6.0"

passwd:
  users:
    - name: patriark
      uid: 1000
      groups: [wheel, systemd-journal]
      ssh_authorized_keys:
        - "ssh-ed25519 AAAA... patriark@homelab"

storage:
  filesystems:
    - device: /dev/disk/by-id/<DISK-ID>   # Existing BTRFS pool — do NOT format
      path: /mnt/btrfs-pool
      format: btrfs
      wipe_filesystem: false               # CRITICAL: preserve existing data
      mount_options: [compress=zstd:3, noatime, space_cache=v2]
      with_mount_unit: true

  directories:
    - path: /var/home/patriark/containers
      user: { id: 1000 }
      group: { id: 1000 }
    - path: /var/home/patriark/containers/quadlets
      user: { id: 1000 }
      group: { id: 1000 }
    - path: /var/home/patriark/containers/config
      user: { id: 1000 }
      group: { id: 1000 }
    - path: /var/home/patriark/containers/data
      user: { id: 1000 }
      group: { id: 1000 }
    - path: /var/home/patriark/containers/secrets
      user: { id: 1000 }
      group: { id: 1000 }
      mode: 0700

  links:
    - path: /var/home/patriark/.config/containers/systemd
      target: /var/home/patriark/containers/quadlets
      user: { id: 1000 }
      group: { id: 1000 }

  files:
    - path: /var/lib/systemd/linger/patriark
      mode: 0644

    - path: /etc/firewalld/zones/public.xml
      contents:
        inline: |
          <?xml version="1.0" encoding="utf-8"?>
          <zone target="default">
            <short>Public</short>
            <service name="ssh"/>
            <port protocol="tcp" port="80"/>
            <port protocol="tcp" port="443"/>
            <!-- Jellyfin and HA ports are LAN-only; do NOT expose to internet -->
            <!-- Port forward only 80/443 on UDM Pro. 8096/8123 for local network access only -->
            <rule family="ipv4">
              <source address="192.168.1.0/24"/>
              <port protocol="tcp" port="8096"/>
            </rule>
            <rule family="ipv4">
              <source address="192.168.1.0/24"/>
              <port protocol="tcp" port="8123"/>
            </rule>
            <port protocol="udp" port="7359"/>
          </zone>

    - path: /etc/sysctl.d/99-homelab.conf
      contents:
        inline: |
          fs.inotify.max_user_watches=524288
          fs.inotify.max_user_instances=512
          net.core.somaxconn=65535
          net.ipv4.ip_unprivileged_port_start=80

    - path: /etc/sudoers.d/patriark-btrfs
      mode: 0440
      contents:
        inline: |
          patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs subvolume *
          patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs send *
          patriark ALL=(root) NOPASSWD: /usr/sbin/btrfs receive *
          patriark ALL=(root) NOPASSWD: /usr/bin/chattr +C *

    - path: /usr/local/bin/setup-nocow.sh
      mode: 0755
      contents:
        inline: |
          #!/bin/bash
          for dir in prometheus loki postgresql-immich nextcloud-db gathio-db \
                     audiobookshelf/config navidrome redis-immich redis-authelia \
                     nextcloud-redis vaultwarden; do
            target="/mnt/btrfs-pool/subvol7-containers/$dir"
            mkdir -p "$target"
            chattr +C "$target" 2>/dev/null || true
            chown 1000:1000 "$target"
          done

    - path: /etc/zincati/config.d/55-homelab.toml
      contents:
        inline: |
          [updates]
          strategy = "periodic"
          [updates.periodic]
          time_zone = "Europe/Oslo"
          [[updates.periodic.window]]
          days = [ "Sat" ]
          start_time = "04:00"
          length_minutes = 120

systemd:
  units:
    - name: zincati.service
      enabled: true

    - name: setup-nocow.service
      enabled: true
      contents: |
        [Unit]
        Description=Set NOCOW on database directories
        After=mnt-btrfs\\x2dpool.mount
        ConditionPathExists=!/var/lib/setup-nocow-done
        [Service]
        Type=oneshot
        ExecStart=/usr/local/bin/setup-nocow.sh
        ExecStartPost=/usr/bin/touch /var/lib/setup-nocow-done
        RemainAfterExit=true
        [Install]
        WantedBy=multi-user.target

    - name: enable-linger@patriark.service
      enabled: true
      contents: |
        [Unit]
        Description=Enable loginctl linger for %i
        After=systemd-logind.service
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/loginctl enable-linger %i
        RemainAfterExit=true
        [Install]
        WantedBy=multi-user.target
```

### 2.2 rpm-ostree Layering (Minimal)

Only layer what cannot be containerized:

```
rpm-ostree install btrfs-progs git vim-minimal
```

Everything else (Podman, systemd, firewalld, SELinux) is already in the FCOS base image.

### 2.3 Zincati Auto-Updates

Configured in Butane above — OS updates restricted to Saturday 04:00-06:00 Europe/Oslo, matching the existing weekly backup window.

---

## Phase 3: Network Topology Redesign

### 3.1 Pod Groupings (Shared localhost replaces internal networks)

**Pod 1: nextcloud-pod** (replaces `nextcloud` network)
| Container | Port | Env Change |
|-----------|------|------------|
| nextcloud | 80 | `MYSQL_HOST=127.0.0.1`, `REDIS_HOST=127.0.0.1` |
| nextcloud-db | 3306 | — |
| nextcloud-redis | 6379 | — |

**Pod 2: immich-pod** (replaces `photos` network)
| Container | Port | Env Change |
|-----------|------|------------|
| immich-server | 2283 | `DB_HOSTNAME=127.0.0.1`, `REDIS_HOSTNAME=127.0.0.1`, `IMMICH_MACHINE_LEARNING_URL=http://127.0.0.1:3003` |
| immich-ml | 3003 | — |
| postgresql-immich | 5432 | — |
| redis-immich | 6379 | — |

**Pod 3: gathio-pod** (replaces `gathio` network)
| Container | Port | Env Change |
|-----------|------|------------|
| gathio | 3000 | MongoDB connection → `127.0.0.1:27017` |
| gathio-db | 27017 | — |

**Pod 4: auth-pod** (replaces `auth_services` network)
| Container | Port | Env Change |
|-----------|------|------------|
| authelia | 9091 | `redis.host=127.0.0.1` in `configuration.yml` |
| redis-authelia | 6379 | — |

**NOT podded** (remain standalone containers):
- Traefik, CrowdSec (gateway layer, standalone)
- Jellyfin (GPU passthrough, standalone on `reverse_proxy` + `media_services`)
- Home Assistant + Matter Server (needs mDNS/SSDP, keep on `home_automation`)
- All monitoring containers (Prometheus needs multi-network scraping)
- Homepage, Vaultwarden, Audiobookshelf, Navidrome, qBittorrent (simple single containers)

### 3.2 Network Reduction: 8 → 4

| Network | Subnet | Internal | Purpose | Status |
|---------|--------|----------|---------|--------|
| `reverse_proxy` | 10.89.2.0/24 | No | Internet-facing, Traefik | **Keep** |
| `monitoring` | 10.89.4.0/24 | Yes | Prometheus scraping | **Keep** |
| `home_automation` | 10.89.6.0/24 | No | HA + Matter (mDNS) | **Keep** |
| `media_services` | 10.89.1.0/24 | No | Jellyfin | **Keep** |
| `nextcloud` | 10.89.10.0/24 | Yes | — | **Delete** (pod) |
| `photos` | 10.89.5.0/24 | Yes | — | **Delete** (pod) |
| `gathio` | 10.89.0.0/24 | Yes | — | **Delete** (pod) |
| `auth_services` | 10.89.3.0/24 | Yes | — | **Delete** (pod) |

### 3.3 Static IP Assignments (Updated)

Pods get a single IP on `reverse_proxy`. IPs are backwards-compatible with the current `/etc/hosts` file:

| Entity | reverse_proxy IP | monitoring IP | Notes |
|--------|-----------------|---------------|-------|
| traefik | 10.89.2.69 | — | Unchanged |
| crowdsec | 10.89.2.70 | — | Unchanged |
| vaultwarden | 10.89.2.71 | — | Unchanged |
| alertmanager | 10.89.2.72 | 10.89.4.72 | Unchanged |
| homepage | 10.89.2.73 | — | Unchanged |
| audiobookshelf | 10.89.2.74 | — | Unchanged |
| navidrome | 10.89.2.75 | — | Unchanged |
| home-assistant | 10.89.2.76 | — | Unchanged |
| grafana | 10.89.2.77 | 10.89.4.77 | Unchanged |
| auth-pod | 10.89.2.78 | — | Was authelia only |
| prometheus | 10.89.2.79 | 10.89.4.79 | Unchanged |
| immich-pod | 10.89.2.80 | — | Was immich-server only |
| jellyfin | 10.89.2.81 | — | Unchanged |
| nextcloud-pod | 10.89.2.82 | — | Was nextcloud only |
| loki | 10.89.2.83 | 10.89.4.83 | Unchanged |
| gathio-pod | 10.89.2.84 | — | Was gathio only |
| qbittorrent | 10.89.2.85 | — | Unchanged |
| alert-discord-relay | 10.89.2.86 | 10.89.4.86 | Unchanged |
| unpoller | 10.89.2.87 | 10.89.4.87 | Unchanged |

Traefik's `/etc/hosts` references the same IPs — Traefik resolves container names to pod IPs via the hosts file.

---

## Phase 4: Quadlet File Design

### 4.1 Pod Quadlet Files (.pod)

Example — `quadlets/nextcloud.pod`:
```ini
[Unit]
Description=Nextcloud Pod (App + MariaDB + Redis)
After=network-online.target reverse_proxy-network.service

[Pod]
PodName=nextcloud-pod
Network=reverse_proxy:ip=10.89.2.82

[Install]
WantedBy=default.target
```

Container quadlets updated to reference pods:
```ini
# In nextcloud.container:
Pod=nextcloud.pod
# Remove all Network= lines (inherited from pod)
# Change MYSQL_HOST=127.0.0.1, REDIS_HOST=127.0.0.1
```

Apply same pattern for `immich.pod`, `gathio.pod`, `auth.pod`.

### 4.2 CoreOS Path Considerations

FCOS uses `/var/home/` instead of `/home/`. The `%h` systemd specifier resolves correctly, so quadlet `Volume=%h/...` lines work unchanged. Audit absolute paths in scripts.

### 4.3 Build Quadlet for Custom Image

`quadlets/alert-discord-relay.build`:
```ini
[Build]
ImageTag=localhost/alert-discord-relay:latest
File=Containerfile
SetWorkingDirectory=%h/containers/services/alert-discord-relay
```

### 4.4 Image Quadlets for Pinned Versions

`quadlets/immich-server.image`:
```ini
[Image]
Image=ghcr.io/immich-app/immich-server:v2.5.6
```

Same for `immich-ml.image` and `postgresql-immich.image`.

---

## Phase 5: Storage Setup and Data Migration

### 5.1 BTRFS Pool

The BTRFS pool is on a separate data drive — it survives OS reinstall. The Butane config mounts it without formatting. All 7 subvolumes remain in place.

### 5.2 Container Data

`subvol7-containers` already holds all persistent container data. Paths are identical. Clone the git repo for config:

```bash
git clone <repo-url> /var/home/patriark/containers
```

### 5.3 Secret Re-Creation

```bash
# Use tmpfs to avoid plaintext secrets on persistent storage
TMPDIR=$(mktemp -d --tmpdir=/dev/shm migration-import.XXXXXX)
chmod 700 "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

gpg --decrypt migration-secrets.tar.gz.gpg | tar xz -C "$TMPDIR"
for secret_file in "$TMPDIR"/migration-secrets.*/*; do
  podman secret create "$(basename "$secret_file")" "$secret_file"
done
```

### 5.4 Database Restoration

1. Start database containers only (within pods)
2. Restore: `mariadb < dump.sql`, `psql < dump.sql`, `mongorestore`
3. Verify integrity
4. Start application containers

---

## Phase 6: Deployment Order

### 6.1 Core Infrastructure (strict order)

1. Networks (4 `.network` files)
2. CrowdSec (standalone)
3. Traefik (standalone, depends on CrowdSec)
4. Auth pod (authelia + redis)
5. Verify: `curl -I https://sso.patriark.org`

### 6.2 Application Pods

6. nextcloud-pod → verify `curl -I https://nextcloud.patriark.org`
7. immich-pod → wait for ML startup (600s) → verify `/api/server/ping`
8. gathio-pod → verify `curl -I https://events.patriark.org`

### 6.3 Standalone Services

9. Jellyfin (verify GPU: `ls /dev/dri/`, may need `rpm-ostree install mesa-va-drivers-freeworld`)
10. Home Assistant + Matter Server
11. Vaultwarden, Homepage, Audiobookshelf, Navidrome, qBittorrent

### 6.4 Monitoring Stack

12. Node Exporter, cAdvisor
13. Loki, Promtail
14. Prometheus (update scrape targets for pod IPs)
15. Alertmanager, Alert Discord Relay
16. Grafana, UnPoller

---

## Phase 7: Operational Tooling

### 7.1 Script Compatibility

**Work unchanged** (~40 scripts): All pure bash + podman scripts (homelab-intel.sh, security-audit.sh, auto-doc-orchestrator.sh, validate-traefik-config.sh, etc.)

**Need modification** (~5 scripts):
- `update-before-reboot.sh` — replace `dnf` with `rpm-ostree`
- `btrfs-snapshot-backup.sh` — adjust `sudo` paths
- `pre-update-snapshot.sh` / `post-update-health-check.sh` — adapt for rpm-ostree

**New scripts needed:**
- `scripts/coreos-update-status.sh` — rpm-ostree status + Zincati state
- `scripts/coreos-rollback.sh` — wrapper for `rpm-ostree rollback`
- `scripts/coreos-metrics-collector.sh` — export rpm-ostree metrics for node_exporter textfile collector

### 7.2 CoreOS-Specific Monitoring

Add Prometheus textfile metrics for:
- `coreos_deployments` — number of rpm-ostree deployments
- `coreos_pending_update` — whether OS update is pending

### 7.3 Backup Strategy

BTRFS snapshot backup works identically — `btrfs-progs` is layered via rpm-ostree, `sudo` access configured in Butane. External drive mount at `/run/media/patriark/WD-18TB*`.

---

## Phase 8: Validation and Cutover

### 8.1 Pre-Cutover Checklist

```bash
# All containers running and healthy
podman ps --format '{{.Names}} {{.Status}}' | grep -v healthy

# Service accessibility
for svc in sso vault nextcloud photos jellyfin grafana ha events musikk audiobookshelf torrent home; do
  curl -sf -o /dev/null -w "%{http_code} $svc\n" "https://$svc.patriark.org"
done

# Database integrity
podman exec nextcloud-db mariadb -e "SELECT COUNT(*) FROM nextcloud.oc_users;"
podman exec postgresql-immich psql -U immich -c "SELECT count(*) FROM assets;"

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'

# Security + health
./scripts/security-audit.sh --level 2
./scripts/homelab-intel.sh
```

### 8.2 Cutover

1. Stop all containers on old system
2. Final BTRFS snapshot
3. Boot CoreOS, start services
4. Run validation
5. Update port forwarding on UDM Pro if IP changed

### 8.3 Rollback

- Boot from old Fedora Workstation (keep installable)
- BTRFS read-only snapshots enable instant restore
- Database dumps provide second safety net

---

## File Inventory

### Create

```
coreos/homelab.bu                           # Butane config
quadlets/nextcloud.pod                      # Pod definitions (4 files)
quadlets/immich.pod
quadlets/gathio.pod
quadlets/auth.pod
quadlets/alert-discord-relay.build          # Build quadlet
quadlets/immich-server.image                # Pinned images (3 files)
quadlets/immich-ml.image
quadlets/postgresql-immich.image
scripts/migration/export-secrets.sh         # Migration helpers
scripts/migration/import-secrets.sh
scripts/migration/validate-migration.sh
scripts/coreos-metrics-collector.sh         # CoreOS monitoring
scripts/coreos-update-status.sh
docs/00-foundation/decisions/ADR-020-*.md   # Migration ADR
```

### Modify

```
quadlets/{nextcloud,nextcloud-db,nextcloud-redis}.container     # Add Pod=, remove Network=
quadlets/{immich-server,immich-ml,postgresql-immich,redis-immich}.container
quadlets/{gathio,gathio-db}.container
quadlets/{authelia,redis-authelia}.container
config/authelia/configuration.yml           # redis.host → 127.0.0.1
config/prometheus/prometheus.yml            # Update scrape targets
config/traefik/hosts                        # Verify pod name resolution
scripts/update-before-reboot.sh             # dnf → rpm-ostree
CLAUDE.md                                  # CoreOS conventions
```

### Delete

```
quadlets/nextcloud.network
quadlets/photos.network
quadlets/gathio.network
quadlets/auth_services.network
```

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Pod networking breaks Traefik discovery | High | Test pod IP + /etc/hosts before cutover |
| GPU drivers missing on CoreOS | Medium | Layer mesa-va-drivers, test before cutover |
| SELinux policy differences on FCOS | Medium | Test all :Z mounts, review audit.log |
| Database corruption during migration | Critical | Full dumps + BTRFS snapshots (double safety) |
| Rootless pods behave differently | Medium | Test each pod individually first |
| rpm-ostree layering breaks updates | Low | Minimize layers (3 packages only) |
| Zincati auto-update breaks services | Medium | Saturday maintenance window, test rollback |
| Home directory path (/var/home/) | Low | %h handles this; audit absolute paths |
