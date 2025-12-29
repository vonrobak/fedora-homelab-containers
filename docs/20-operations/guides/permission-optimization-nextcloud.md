# Permission Optimization for Nextcloud Migration

**Date:** 2025-12-29
**Status:** Recommendation
**Context:** Migrating from Samba to Nextcloud as primary file distribution method

## Current State

### Subvolume Ownership Analysis

| Subvolume | Current Ownership | Permissions | Purpose | Services |
|-----------|------------------|-------------|---------|----------|
| `subvol1-docs` | `patriark:samba` (1000:1001) | 2775 | Documents | Nextcloud |
| `subvol2-pics` | `patriark:samba` (1000:1001) | 2775 | Pictures | Nextcloud |
| `subvol3-opptak` | `patriark:samba` (1000:1001) | 2775 | Recordings | Immich + Nextcloud |
| `subvol4-multimedia` | `patriark:patriark` (1000:1000) | 755 | Media | Jellyfin + Nextcloud |
| `subvol5-music` | `patriark:patriark` (1000:1000) | 755 | Music | (Future) |
| `subvol6-tmp` | `patriark:patriark` (1000:1000) | 755 | Temporary | (Host) |
| `subvol7-containers` | `patriark:patriark` (1000:1000) | 755 | Container data | (All containers) |

### Container User Mapping (Rootless Podman)

All containers (Nextcloud, Immich, Jellyfin) run as **root (UID 0) inside the container**, which maps to **UID 1000 (patriark) outside** via rootless podman user namespaces.

**User namespace mapping:**
```
Inside container → Outside host
UID 0           → UID 1000 (patriark)
UID 1           → UID 100001
UID 1000        → UID 101000
```

## Recommendation: Keep Current Permissions

### ✅ **RECOMMENDED: Leave permissions as-is**

**Rationale:**

1. **Functionally equivalent**: The `samba` group (GID 1001) ownership is **harmless** for container access because:
   - Containers run as UID 0 inside → UID 1000 outside (patriark)
   - With permissions `2775` (rwxrwsr-x), the **owner** (patriark/1000) has full read/write/execute
   - Containers access files as the owner, not the group
   - The setgid bit (2xxx) only affects *new* files created (they inherit group `samba`)

2. **No performance impact**: Group ownership has zero performance impact on file access

3. **Future flexibility**: Keeping the `samba` group allows:
   - Easy re-enablement of Samba if needed (just start the service)
   - Multi-protocol access (e.g., Samba + Nextcloud simultaneously for migration period)
   - No need to recursively chown thousands of files

4. **Working configuration**: Current permissions are already proven to work:
   - Nextcloud external storage mounts working
   - Immich accessing subvol3-opptak correctly (after recent fix)
   - Jellyfin accessing subvol4-multimedia

5. **Risk avoidance**: Changing ownership/permissions on large directory trees:
   - Time-consuming (hours for millions of files)
   - Risk of errors or interruptions
   - May trigger unnecessary BTRFS copy-on-write operations
   - Could temporarily disrupt running services

### Container Access Verification

All containers can access files because they run as **patriark (UID 1000)** from the host's perspective:

```bash
# Nextcloud (root inside = UID 1000 outside)
podman exec nextcloud ls -la /mnt/docs  # Can access subvol1-docs

# Immich (root inside = UID 1000 outside)
podman exec immich-server ls -la /usr/src/app/upload  # Can access subvol3-opptak/immich

# Jellyfin (root inside = UID 1000 outside)
podman exec jellyfin ls -la /media  # Can access subvol4-multimedia
```

## Alternative: Clean Ownership (Not Recommended)

If you want "aesthetically cleaner" permissions (purely cosmetic), you could:

```bash
# Change group from 'samba' to 'patriark' for subvol1-3
sudo chgrp -R patriark /mnt/btrfs-pool/subvol1-docs
sudo chgrp -R patriark /mnt/btrfs-pool/subvol2-pics
sudo chgrp -R patriark /mnt/btrfs-pool/subvol3-opptak
```

**⚠️ Warnings:**
- **Not necessary** for functionality
- **Time-consuming** (potentially hours depending on file count)
- **BTRFS impact** on subvol3-opptak (may trigger extensive snapshots)
- **Service disruption** if done while containers are running

## Setgid Bit Explanation

The `2775` permission (instead of `0775`) has the **setgid bit** set:
- **Effect**: New files/directories created inherit the parent directory's group (`samba`)
- **Original purpose**: Ensured Samba-created files were accessible to all Samba users
- **Current impact**: Minimal - containers create files as `patriark:patriark` by default, overriding setgid in most cases
- **Safe to keep**: No negative effects

## Immich Special Case: subvol3-opptak

The Immich directory structure:
```
/mnt/btrfs-pool/subvol3-opptak/        (patriark:samba, 2775)
└── immich/                             (patriark:patriark, 2775)
    ├── backups/                        (patriark:patriark, 2775)
    ├── thumbs/                         (patriark:patriark, 2775)
    ├── library/                        (patriark:patriark, 2775)
    └── upload/                         (patriark:patriark, 2775)
```

**Current status:** Working correctly after recent container restart (config/traefik/dynamic/routers.yml:92)
**Recommendation:** Leave as-is

## Decision

**✅ KEEP CURRENT PERMISSIONS**

No action required. The `samba` group ownership on subvol1-3 is:
- Functionally harmless
- Historically accurate (reflects previous Samba usage)
- Allows easy rollback if needed
- Avoids risky, time-consuming recursive operations

## Post-Samba Removal Checklist

After stopping Samba service:

- [x] Verify Nextcloud can access subvol1-docs and subvol2-pics
- [x] Verify Immich can access subvol3-opptak/immich
- [x] Verify Jellyfin can access subvol4-multimedia
- [ ] Monitor for 1 week - if no issues, consider permanent
- [ ] Document in monthly review that Samba group is legacy

## References

- **ADR-001:** Rootless Containers - User namespace mapping
- **ADR-013:** Nextcloud Native Authentication
- Journal: 2025-12-20-nextcloud-deployment-and-ocis-decommission.md
- Journal: Current session - Immich permission fix
