# Podman Storage Migration: NVMe → BTRFS Pool (Execution)

**Date:** 2026-04-18
**Status:** Complete — all 31 containers running on BTRFS pool
**Plan:** [2026-03-28-podman-storage-migration.md](2026-03-28-podman-storage-migration.md)
**Duration:** ~25 minutes end-to-end; ~7 minutes of container downtime
**Motivation:** NVMe at 94% (109 GiB / 118 GiB), cascade risk escalating since 2026-03-26 promtail outage

---

## Summary

Moved the ~17 GB Podman overlay storage from `~/.local/share/containers/storage` (NVMe) to `/mnt/btrfs-pool/subvol7-containers/storage` (BTRFS pool, NOCOW) per the 2026-03-28 plan. All services restarted successfully. Three issues surfaced that the plan did not anticipate — none fatal, all worked around in-window.

---

## Issues the Plan Didn't Cover

### Issue 1: `podman stop --all` doesn't stick with quadlets

Running `podman stop --all --timeout 30` returned container IDs, but within seconds systemd restarted them via the quadlet-managed `.service` units. Seven containers bounced back up within 4 minutes.

**Fix:** Stop via `systemctl --user stop <service>` for each of the 31 quadlets. Traefik additionally required stopping `http.socket` and `https.socket` first (ADR-022 socket activation) — otherwise systemd logs `Stopping 'traefik.service', but its triggering units are still active` and the container relaunches on the next socket connection.

```bash
for svc in $(cat /tmp/all-quadlets.txt); do
  systemctl --user stop "${svc}.service"
done
systemctl --user stop http.socket https.socket traefik.service
```

### Issue 2: rsync as the regular user can't read subordinate-UID files

Rootless Podman stores overlay layer contents under subordinate UIDs (`/etc/subuid` range, e.g. UIDs 100000+ on the host). From a plain user shell these directories are unreadable: rsync logged ~550 "Permission denied" errors on paths like `overlay/<sha>/diff/var/cache/apt/archives/partial`.

The first rsync copied 370858 of 371422 files (96% of the tree, the full 17 GB of layer content — the missed files were all inside unreadable directory handles). That's close enough that a sanity check would say "done," but not actually complete.

**Fix:** re-run rsync inside the user namespace with `podman unshare`. Inside the unshared namespace, subordinate UIDs map to root and everything becomes readable:

```bash
podman unshare rsync -aHAX --delete \
  ~/.local/share/containers/storage/ \
  /mnt/btrfs-pool/subvol7-containers/storage/
```

After this pass: 371422 files both sides, exact match.

### Issue 3: Podman's SQLite DB has paths baked in at creation

Starting `podman info` after pointing `storage.conf` at the new path failed with:

```
Error: database static dir "/home/patriark/.local/share/containers/storage/libpod"
       does not match our static dir "/mnt/btrfs-pool/subvol7-containers/storage/libpod":
       database configuration mismatch
```

Podman 5.x uses SQLite (`db.sql` in the storage root) for container/image metadata. The `DBConfig` table records the `StaticDir`, `GraphRoot`, and `VolumeDir` it was created with. rsync preserves the binary verbatim, so the new path's DB still claimed the old path was its home.

**Fix:** update the three path fields in-place:

```bash
sqlite3 /mnt/btrfs-pool/subvol7-containers/storage/db.sql \
  "UPDATE DBConfig SET
     StaticDir='/mnt/btrfs-pool/subvol7-containers/storage/libpod',
     GraphRoot='/mnt/btrfs-pool/subvol7-containers/storage',
     VolumeDir='/mnt/btrfs-pool/subvol7-containers/storage/volumes';"
```

After this, `podman info` immediately showed the new paths and 30 images loaded without issue. No container metadata was lost — `podman ps -a` listed the 31 expected names (though all stopped, as expected after the systemctl shutdown).

**Note:** `podman system migrate` does not address this — that command is for UID remapping changes, not storage path moves. Editing the DB is the documented workaround for path migration in the Podman community.

---

## Timeline

| Time (CET) | Event |
|------------|-------|
| 11:16 | Target dir created, NOCOW applied, SELinux equivalence registered |
| 11:25 | `podman stop --all` executed — 7 containers bounced back via systemd |
| 11:28 | Stopped all 31 services via `systemctl --user stop`; Traefik required socket stops |
| 11:29 | First rsync pass began (58 MB/s, 4m20s total) |
| 11:33 | First rsync complete: 17 GB / 370858 files; 551 files missed (permission denied) |
| 11:34 | `podman unshare rsync` reconciled to 371422 / 371422 files |
| 11:35 | `restorecon -R` applied SELinux labels |
| 11:36 | `storage.conf` written |
| 11:37 | `podman info` failed — DBConfig mismatch |
| 11:38 | sqlite3 UPDATE on DBConfig paths; `podman info` succeeded |
| 11:39 | Core services started (Traefik, CrowdSec, Authelia, Redis) |
| 11:42 | All 31 containers running; most healthy, a few still in "starting" |
| 11:45 | Web-facing verification complete (15 subdomains checked) |

Total container downtime: ~11:28 → 11:39 = 11 minutes.

---

## Post-Migration State

- **Podman:** `graphRoot: /mnt/btrfs-pool/subvol7-containers/storage`, `graphRootAllocated: 16 TB`
- **All 31 quadlet services:** running; healthy after warmup
- **NVMe:** still 93% — the old `~/.local/share/containers/storage` (17 GB) remains in place per the plan's 24–48h soak requirement. Expected post-cleanup: ~78%
- **BTRFS pool:** 76% → 76% (17 GB added to an 11 TB pool is noise)

---

## Lessons Learned

1. **Quadlet-managed containers need systemctl-level control.** Any migration that assumes `podman stop --all` will leave containers stopped is wrong for this stack. Document this in the deployment skill — a `stop-all-quadlets` helper is a natural extension.

2. **Socket-activated services need their sockets stopped too.** ADR-022's socket activation was merged two days before this migration. The plan didn't mention it because it didn't exist yet. Any future maintenance procedure that stops Traefik needs `http.socket https.socket` in the shutdown order.

3. **`podman unshare` is the canonical way to touch rootless storage from the host.** This applies to any migration, backup verification, or filesystem operation against `~/.local/share/containers/storage`. Raw rsync / du / find will silently skip files.

4. **Podman 5.x SQLite has location-bound state.** If you move the storage, the DB follows but doesn't self-heal. This is a reasonable safety check (catches misconfiguration), but it means "rsync + point config at new path" is always a three-step move, not two. The UPDATE is idempotent and survives Podman upgrades.

5. **The 2026-03-28 plan is now incomplete.** The doc describes Steps 1–6 accurately but misses the three issues above. Either update that doc in place or supersede it with a reference to this execution journal. The plan's rollback procedure (remove `storage.conf`) is still correct and still works — verified by reading the path where Podman would fall back.

---

## Follow-Up Actions

- [ ] Update `2026-03-28-podman-storage-migration.md` with the three workarounds, or mark it superseded
- [ ] Close issue #139 (Root filesystem at 90% capacity) once old storage is removed
- [ ] After 24–48h soak: `rm -rf ~/.local/share/containers/storage` and verify NVMe drops below 80%
- [ ] Add a health check for journal persistence mode (open action from 2026-03-26 outage — same NVMe pressure that triggered that is what this migration addresses)

---

## Verification Commands (for future reference)

```bash
# Confirm Podman is reading from the new path
podman info | grep -E "graphRoot|runRoot"
# → graphRoot: /mnt/btrfs-pool/subvol7-containers/storage

# Confirm DB agrees with the current config
sqlite3 /mnt/btrfs-pool/subvol7-containers/storage/db.sql \
  "SELECT StaticDir, GraphRoot, VolumeDir FROM DBConfig;"

# Confirm NOCOW is still set (BTRFS can silently drop the flag on subvols under stress)
lsattr -d /mnt/btrfs-pool/subvol7-containers/storage
# → ---------------C------

# Confirm SELinux labels match
ls -Zd /mnt/btrfs-pool/subvol7-containers/storage \
       /home/patriark/.local/share/containers/storage
```
