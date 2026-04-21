# Podman Storage Migration: NVMe → BTRFS Pool

**Date:** 2026-03-28
**Status:** Executed 2026-04-18 — see [execution journal](2026-04-18-podman-storage-migration-execution.md) for what actually happened
**Estimated downtime:** 10–15 minutes (all services) — actual: ~11 minutes
**Risk:** Medium — affects all 30 containers, but fully reversible

> **Execution surfaced three issues this plan did not anticipate.** Inline callouts below
> mark the affected steps. Read the execution journal before running this procedure again.
> Summary: (1) `podman stop --all` does not hold with quadlets, (2) rsync from a plain
> user shell cannot read rootless subordinate-UID files, (3) Podman 5.x SQLite has
> path-bound `DBConfig` that requires an in-place UPDATE after the move.

## Context

`~/.local/share/containers/storage` (Podman overlay storage — image layers, metadata,
container runtime state) consumes ~17 GB on the NVMe system drive (118G total, 63% used).
This is not application data (already on BTRFS pool) — it's the container image filesystem
that all 30 containers boot from.

Moving to `/mnt/btrfs-pool/subvol7-containers/storage` frees NVMe space. Trade-off:
container startup marginally slower (BTRFS HDD vs NVMe), negligible at runtime since
data I/O already goes to the BTRFS pool.

## Pre-Migration (can do now, no downtime)

```bash
# 1. Prune dangling images (already done — saved ~16 GB)
podman image prune -f --filter "dangling=true"

# 2. Create target directory with NOCOW (before any data lands)
sudo mkdir -p /mnt/btrfs-pool/subvol7-containers/storage
sudo chown 1000:1000 /mnt/btrfs-pool/subvol7-containers/storage
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/storage

# 3. Set SELinux equivalence so containers get correct labels
sudo semanage fcontext -a -e /home/patriark/.local/share/containers/storage \
  /mnt/btrfs-pool/subvol7-containers/storage

# 4. Verify SELinux rule is registered
sudo semanage fcontext -l | grep subvol7-containers/storage
```

## Migration (maintenance window)

### Step 1 — Stop all containers

> ⚠ **Execution note (2026-04-18):** `podman stop --all` does **not** stick with quadlets
> — systemd restarts each container via its `.service` unit within seconds. Stop at the
> systemd layer instead. Traefik additionally requires stopping its socket units first
> (ADR-022 socket activation), else the next connection relaunches the container.

```bash
# Confirm what's running
podman ps --format "{{.Names}}" | sort

# Stop all quadlet services (not `podman stop`)
for svc in $(systemctl --user list-units --type=service --state=running \
               --no-legend | awk '/\.service/{print $1}' | grep -v user@); do
  systemctl --user stop "$svc"
done

# Traefik's sockets must stop first — ADR-022 socket activation
systemctl --user stop http.socket https.socket traefik.service

# Verify nothing running
podman ps -q | wc -l   # Should be 0
```

### Step 2 — Copy storage

> ⚠ **Execution note (2026-04-18):** rootless Podman stores overlay layer contents under
> subordinate UIDs (100000+). A plain user rsync silently skips those directories with
> "Permission denied" — in the 2026-04-18 run, 551 of 371422 files were missed, all
> inside unreadable directory handles. Run rsync inside `podman unshare` so subordinate
> UIDs map to root. Do **not** rely on file-count delta alone to verify — the miss was
> 0.1% of files but included live overlay state.

```bash
# rsync inside the user namespace — subordinate UIDs become readable
# -aHAX preserves hardlinks, ACLs, xattrs (all critical for overlay)
podman unshare rsync -aHAX --delete --info=progress2 \
  ~/.local/share/containers/storage/ \
  /mnt/btrfs-pool/subvol7-containers/storage/

# Verify exact file-count match (not approximate)
find ~/.local/share/containers/storage | wc -l
find /mnt/btrfs-pool/subvol7-containers/storage | wc -l
# Must be equal — if not, re-run the rsync

# Apply SELinux labels to copied data
sudo restorecon -R -v /mnt/btrfs-pool/subvol7-containers/storage
```

### Step 3 — Configure Podman to use new location
```bash
# Create user storage.conf (takes precedence over /etc/containers/storage.conf)
mkdir -p ~/.config/containers
cat > ~/.config/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
rootless_storage_path = "/mnt/btrfs-pool/subvol7-containers/storage"
EOF
```

### Step 4 — Verify before starting services

> ⚠ **Execution note (2026-04-18):** `podman info` fails with `database configuration
> mismatch` at this point. Podman 5.x's SQLite DB (`db.sql`) records the `StaticDir`,
> `GraphRoot`, and `VolumeDir` it was created with, and rsync preserves the DB verbatim
> — so the new path's DB still claims the old path as its home. `podman system migrate`
> does **not** fix this (that command is for UID remapping changes). Update the paths
> in-place before continuing.

```bash
# Patch the DB to match the new location (idempotent, survives Podman upgrades)
sqlite3 /mnt/btrfs-pool/subvol7-containers/storage/db.sql \
  "UPDATE DBConfig SET
     StaticDir='/mnt/btrfs-pool/subvol7-containers/storage/libpod',
     GraphRoot='/mnt/btrfs-pool/subvol7-containers/storage',
     VolumeDir='/mnt/btrfs-pool/subvol7-containers/storage/volumes';"

# Confirm Podman sees the new location
podman info 2>/dev/null | grep -i graphroot
# Expected: graphRoot: /mnt/btrfs-pool/subvol7-containers/storage

# Confirm images are visible
podman images | head -10

# Confirm container definitions intact
podman ps -a --format "{{.Names}}" | sort
```

### Step 5 — Restart all services
```bash
systemctl --user daemon-reload

# Start services (systemd dependencies handle ordering)
systemctl --user start podman-restart.service 2>/dev/null

# Or start key services explicitly:
systemctl --user start traefik.service
systemctl --user start crowdsec.service
systemctl --user start authelia.service
systemctl --user start prometheus.service grafana.service loki.service

# Start remaining application services
systemctl --user start nextcloud.service
systemctl --user start immich-server.service
systemctl --user start jellyfin.service
systemctl --user start vaultwarden.service
systemctl --user start home-assistant.service
systemctl --user start audiobookshelf.service navidrome.service
systemctl --user start homepage.service
systemctl --user start qbittorrent.service
systemctl --user start gathio.service
```

### Step 6 — Validate
```bash
# Quick health check
podman ps --format "table {{.Names}}\t{{.Status}}" | sort

# Verify web access
curl -sI https://homepage.patriark.org | head -1
curl -sI https://grafana.patriark.org | head -1

# Run full health check
~/containers/scripts/homelab-intel.sh
```

## Rollback (if anything goes wrong)

```bash
# 1. Stop everything (see Step 1 — use systemctl, not `podman stop --all`)

# 2. Remove the override config
rm ~/.config/containers/storage.conf

# 3. Verify Podman falls back to default
podman info 2>/dev/null | grep -i graphroot
# Expected: graphRoot: /home/patriark/.local/share/containers/storage

# 4. Restart services
systemctl --user daemon-reload
# (start services as in Step 5)
```

Original data at `~/.local/share/containers/storage` is untouched until explicit cleanup.

## Post-Migration Cleanup (after 24–48 hours of stable operation)

> ⚠ **Execution note (2026-04-20):** Two caveats from the 2026-04-18 run:
> 1. Use `podman unshare rm -rf` — a plain `rm` can't traverse subordinate-UID
>    directories and will leave files behind.
> 2. If `/home` is BTRFS with snapshots (urd), `df` will **not** show space freed
>    immediately. Blocks stay pinned until every snapshot referencing the old tree
>    ages out under retention policy. Under `htpc-home`'s `daily=14, weekly=8` that
>    can mean up to ~8 weeks of drain. This is expected, not a failure.

```bash
# Only after confirming everything works reliably
podman unshare rm -rf ~/.local/share/containers/storage

# Verify NVMe space freed (will drain gradually if snapshots reference the old tree)
df -h /home
```

## Checklist

- [ ] Pre-migration steps completed (NOCOW, SELinux, prune)
- [ ] All containers stopped
- [ ] rsync completed successfully
- [ ] SELinux labels applied
- [ ] storage.conf created
- [ ] `podman info` shows new graphRoot
- [ ] `podman images` lists all images
- [ ] All services started and healthy
- [ ] Web access verified (Traefik routing works)
- [ ] Health score checked via homelab-intel.sh
- [ ] Ran stable for 24–48 hours
- [ ] Old storage removed
