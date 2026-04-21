# ADR-023: Shared Mount Propagation for Monitoring Containers

**Date:** 2026-04-21
**Status:** Accepted
**Related:** ADR-021 (Urd backup integration — the downstream victim)

## Context

Urd uses removable LUKS-encrypted BTRFS drives in an IcyBox dock as offsite backup targets. Every time the user swaps drives (e.g. WD-18TB ↔ WD-18TB1), the next unlock fails:

```
Error unlocking /dev/sdX: Failed to activate device: File exists
```

The `/dev/mapper/luks-<UUID>` node stays ACTIVE with Open count ≥ 1 after the host unmounts. `cryptsetup close` and `dmsetup remove --force` both fail with "Device or resource busy". `lsof`/`fuser` on the host show nothing. Symptom recurs on every swap; the only working workaround is restarting the monitoring containers.

### Root cause

Both monitoring containers recursively bind-mount host `/`:

- `cadvisor.container` — `Volume=/:/rootfs:ro`
- `node_exporter.container` — `Volume=/:/host:ro,rslave`

Podman 5.8 performs this as a recursive bind regardless of quadlet wording. Any drive mounted at `/run/media/patriark/<LABEL>` at container start time (e.g. after `AutoUpdate=registry` restarts the container while a drive is attached, or after a reboot with the drive present) gets captured as a submount inside the container's mount namespace, pinning the LUKS dm-mapper.

Propagation flags should unstick this, but don't:

- **`rslave`** — the kernel requires CAP_SYS_ADMIN in the user namespace that owns the source mount to establish a slave relation. Rootless Podman creates a new user namespace, and host `/` is owned by the initial userns, so `rslave` is silently downgraded to `private`. Host unmount events never propagate into the container. Verified live: `/proc/<pid>/mountinfo` showed the node_exporter `/host` bind with no `master:X` field despite the quadlet requesting rslave.
- **`rprivate`** / default — same problem: no propagation.
- **`nsenter -t <pid> -m -- umount`** inside the container's mount namespace — fails with `Permission denied` because the rootless container lacks mount caps in its userns. Not a viable recovery path.

### Why not scope down the bind

Non-recursive bind (`--mount type=bind,bind-nonrecursive=true`) fails with `mount "/": Invalid argument` when the source is `/` in rootless mode — crun's `open_tree()` without `AT_RECURSIVE` is rejected on a host-owned root mount. Verified by direct test. Works for sub-paths like `/etc` but not `/`.

Replacing the `/` bind with a hand-picked list of directories loses filesystem-collector visibility for any mountpoint not explicitly bound in. We'd have to re-declare every filesystem we want metrics on, and re-add new ones as they appear.

## Decision

Use **`rshared`** propagation on the root bind for both monitoring containers. This puts the container's bind into the same peer group as the host mount, so host unmount events propagate into the container and release the LUKS dm-mapper reference automatically on drive removal.

**Symmetry concern — irrelevant here.** `rshared` is bidirectional in general, but in rootless Podman the container lacks CAP_SYS_ADMIN in its userns, so it cannot initiate umount/mount operations that would propagate back to the host. Propagation is effectively one-way (host → container) for us, matching the `rslave` semantics we wanted.

**Filesystem metrics filter.** In parallel, `node_exporter` is configured with `--collector.filesystem.mount-points-exclude` extended to skip `/run/media/.+` — so removable backup drives don't clutter Prometheus with per-drive filesystem series that come and go.

## Configuration

**`quadlets/cadvisor.container`:**
```
Volume=/:/rootfs:ro,rshared
```

**`quadlets/node_exporter.container`:**
```
Volume=/:/host:ro,rshared
Exec=--path.rootfs=/host --collector.textfile.directory=/textfile-metrics \
     --collector.filesystem.mount-points-exclude=^/(dev|proc|run/(credentials/.+|media/.+)|sys|var/lib/(docker|containers)/.+|sysroot)($|/)
```

## Consequences

**Positive:**
- Drive swaps no longer leave zombie dm-mappers. No more post-swap restart of monitoring stack.
- Host `umount` events (periodic or drive-swap triggered) propagate into both containers cleanly.
- `/run/media` no longer emits filesystem metrics for drives that come and go.

**Neutral:**
- Mount propagation now runs in both directions at the kernel level. Cannot be exploited by the rootless container (no mount caps), and both containers are trusted components of the monitoring stack.
- `cadvisor` continues to use the systemd cgroup factory (not the podman socket factory — pre-existing behavior independent of this change).

**Negative:**
- None measured. Metrics coverage unchanged for `/`, `/boot`, `/boot/efi`, `/home`, `/mnt` (verified post-deployment).

## Constraint for future monitoring containers

Any future container that bind-mounts host paths which contain dynamic/removable mountpoints (e.g. `/run/media`, `/mnt/*` for USB devices) MUST use `rshared` propagation on the root bind — OR limit the bind to a non-recursive scope that cannot reach those paths — to avoid recreating the zombie-mapper failure mode.

## Verification

Deployed 2026-04-21. Post-deployment checks:

1. `grep -E " /host | /rootfs " /proc/<pid>/mountinfo` now shows `shared:<N>` (was absent).
2. `node_filesystem_size_bytes` still reports `/`, `/boot`, `/boot/efi`, `/home`, `/mnt`; no `/run/media/*` series.
3. `cadvisor` reports 80+ cgroup entries under `/user.slice/.../container.slice/*.service` (unchanged).
4. Both services `active (running)` with passing healthchecks.

End-to-end drive-swap validation pending next Urd offsite rotation.
