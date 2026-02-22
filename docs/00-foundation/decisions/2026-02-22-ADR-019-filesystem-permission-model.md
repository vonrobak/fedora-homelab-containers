# ADR-019: Filesystem Permission Model

**Status:** Accepted
**Date:** 2026-02-22
**Context:** Samba-era permissions causing write failures in Nextcloud external storage

---

## Context

The homelab filesystem grew organically from a Samba file server into a multi-service container platform. Three BTRFS subvolumes (subvol1-docs, subvol2-pics, subvol3-opptak) still carried Samba-era group ownership (`patriark:samba`, GID 1001) and SGID bits (mode 2775). The Downloads directory used world-writable mode 2777 as a workaround.

**Problem:** Rootless Podman's UID namespace mapping means container processes run as host UIDs outside the owner's primary group. Specifically, Nextcloud's `www-data` (container UID 33) maps to host UID 100032, which has no relationship to the `samba` group (GID 1001). Since GID 1001 has no subgid mapping in rootless containers, it appears as `nogroup` — and the `samba` group ownership provides zero access benefit to any container.

**Impact:** Nextcloud external storage mounts failed writes on subvol1-docs, subvol2-pics, and Downloads because host UID 100032 fell into "others" (r-x only on 2775, or needed the 2777 workaround on Downloads).

**Trigger:** SLO burn rate investigation (2026-02-22) traced 502 errors to Nextcloud write failures on external storage mounts.

## Decision

**Standardize all BTRFS subvolumes to `patriark:patriark` (0755) ownership. Use POSIX ACLs for cross-UID container write access. Decommission Samba.**

### Permission Model

| Path | Owner | Mode | ACLs | Reason |
|------|-------|------|------|--------|
| subvol1-docs | patriark:patriark | 0755 | `user:100032:rwx` (access+default) | Nextcloud www-data writes |
| subvol2-pics | patriark:patriark | 0755 | `user:100032:rwx` (access+default) | Nextcloud www-data writes |
| subvol3-opptak | patriark:patriark | 0755 | None | Read-only in Nextcloud; Immich writes as owner (UID 1000) |
| subvol4-multimedia | patriark:patriark | 0755 | None | Read-only in Nextcloud; Jellyfin reads as owner |
| subvol5-music | patriark:patriark | 0755 | None | Read-only access only |
| subvol6-tmp | patriark:patriark | 0755 | None | Host-only (except Downloads) |
| subvol6-tmp/Downloads | patriark:patriark | 0755 | `user:100032:rwx` (access+default) | Nextcloud www-data writes |
| subvol7-containers | patriark:patriark | 0755 | None | Container root = host patriark = owner |

### Key Principles

1. **Owner-based access by default:** Container root (UID 0) maps to host UID 1000 (patriark) via rootless Podman. Files owned by `patriark` are writable by container root without ACLs.

2. **ACLs for non-root container users:** When a container process runs as a non-root user (e.g., Nextcloud's www-data, UID 33 → host 100032), POSIX ACLs grant explicit access.

3. **Default ACLs for inheritance:** Default ACLs on directories ensure new files/subdirectories automatically inherit the correct permissions.

4. **No world-writable, no SGID:** These are legacy patterns from Samba that serve no purpose in a container-only environment.

### Implementation

```bash
# Phase 0: BTRFS snapshots for rollback
sudo btrfs subvolume snapshot -r /mnt/btrfs-pool/subvol1-docs /mnt/btrfs-pool/.snapshots/subvol1-docs-pre-perms

# Phase 1: Decommission Samba
sudo systemctl stop smb.service nmb.service
sudo systemctl disable smb.service nmb.service
sudo firewall-cmd --permanent --remove-service=samba --remove-service=samba-client
sudo firewall-cmd --reload

# Phase 2: Fix Downloads (replace 2777 with ACLs)
sudo chmod 0755 /mnt/btrfs-pool/subvol6-tmp/Downloads
sudo setfacl -R -m u:100032:rwx /mnt/btrfs-pool/subvol6-tmp/Downloads
sudo setfacl -R -d -m u:100032:rwx /mnt/btrfs-pool/subvol6-tmp/Downloads

# Phase 3: Standardize subvolumes
sudo chgrp -R patriark /mnt/btrfs-pool/subvol{1-docs,2-pics,3-opptak}
# Remove SGID, set 0755/0644
```

**Automated script:** `scripts/optimize-permissions.sh`
**Drift detection:** `scripts/verify-permissions.sh`

## Consequences

### Positive

**Clean permission model:** Single, consistent ownership pattern across all subvolumes. No ambiguity about which group or mode is correct.

**Explicit access grants:** POSIX ACLs make container access visible and auditable (`getfacl` shows exactly who can access what).

**Default ACL inheritance:** New files automatically get correct permissions. No manual fixup needed after file creation.

**Samba decommissioned:** Eliminates unused attack surface (ports 139/445 closed). Samba was slated for decommission since Dec 2025.

**Drift detection:** `verify-permissions.sh` catches permission regressions before they cause service failures.

### Negative

**ACL complexity:** POSIX ACLs are less visible than standard UNIX permissions (`ls -l` shows `+` suffix but not details). Operators must use `getfacl` to inspect.

**Recursive operations on spinning disks:** Initial migration takes 5-15 minutes on 53K files across HDDs.

**Samba re-enable cost:** If Samba is needed again, must re-add group ownership and firewall rules (mitigated: package kept installed, snapshots available).

### Neutral

**No service restarts needed:** Kernel checks permissions at access time, so running containers see changes immediately.

**BTRFS CoW impact:** `chgrp` and `chmod` on BTRFS trigger metadata-only CoW (not full data copy). Impact is minimal.

## Alternatives Considered

**1. Keep Samba-era permissions (status quo):** Rejected — the `samba` group provides zero benefit to containers and the permission model is confusing. World-writable Downloads is a security antipattern.

**2. Supplementary groups in containers:** Podman supports `--group-add` but rootless containers cannot map arbitrary host GIDs. The `samba` GID (1001) has no subgid mapping.

**3. Run Nextcloud as root (UID 0 → host 1000):** Would eliminate ACL need but Nextcloud explicitly drops to www-data for security. Overriding this is unsupported.

**4. Bind-mount with `:U` flag (user namespace remapping):** Podman's `:U` flag recursively chowns on every container start. Prohibitively slow for large volumes and destructive to shared mounts.

## Supersedes

- `docs/20-operations/guides/permission-optimization-nextcloud.md` (2025-12-29) — that guide recommended keeping Samba-era permissions. This ADR reverses that recommendation based on evidence that the permission model causes container write failures.

## Verification

```bash
# Drift detection (run periodically)
./scripts/verify-permissions.sh

# Manual verification
getfacl /mnt/btrfs-pool/subvol1-docs
getfacl /mnt/btrfs-pool/subvol2-pics
stat -c '%U:%G %a' /mnt/btrfs-pool/subvol{1..7}-*

# Nextcloud write test
podman exec -u www-data nextcloud touch /external/user-documents/.test
podman exec -u www-data nextcloud rm /external/user-documents/.test
```

## References

- Investigation: SLO burn rate analysis session (2026-02-22)
- Previous guide: `docs/20-operations/guides/permission-optimization-nextcloud.md` (superseded)
- ADR-001: Rootless Containers (UID namespace mapping)
- ADR-013: Nextcloud Native Authentication
- Memory: Rootless container UID mapping (MEMORY.md)
