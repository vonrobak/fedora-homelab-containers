# Filesystem Permission Optimization & Samba Decommission

**Date:** 2026-02-22
**Trigger:** Nextcloud SLO burn rate investigation traced 502 errors to external storage write failures
**Result:** Clean POSIX ACL permission model, Samba decommissioned, drift detection added

## Root Cause

Nextcloud external storage mounts (Documents, Photos, Downloads) failed writes because:
1. Subvol1-3 had Samba-era ownership (`patriark:samba`, mode 2775)
2. The `samba` GID (1001) has no rootless Podman subgid mapping — provides zero container access
3. Nextcloud's www-data (container UID 33 → host 100032) fell into "others" (r-x only)
4. Downloads used world-writable 2777 as a workaround

## Changes

**Samba decommission (Phase 1):**
- Stopped and disabled `smb.service` / `nmb.service`
- Removed firewall services `samba` / `samba-client`
- Removed `patriark` from `samba` group
- Package kept installed (zero cost, easy rollback)

**Downloads fix (Phase 2):**
- Replaced mode 2777 with 0755 + POSIX ACLs (`user:100032:rwx` access+default)

**Subvolume standardization (Phase 3):**
- `chgrp -R patriark` on subvol1-docs (17K items), subvol2-pics (28K), subvol3-opptak (91K)
- Removed all SGID bits, set dirs 0755, files 0644
- Re-applied ACLs on subvol1/subvol2 after chmod (mask correction)

**New files:**
- `scripts/optimize-permissions.sh` — sudo script for all phases (with BTRFS snapshots)
- `scripts/verify-permissions.sh` — drift detection (6 checks, matches security-audit.sh style)
- `docs/00-foundation/decisions/2026-02-22-ADR-019-filesystem-permission-model.md`

**Modified files:**
- `scripts/security-audit.sh` — removed ports 139/445 from expected ports
- `docs/20-operations/guides/permission-optimization-nextcloud.md` — marked superseded by ADR-019

## Bugs Hit During Execution

1. **`((STEP++))` silent exit:** When STEP=0, result is falsy → `set -e` kills script silently. Fix: `|| true`
2. **Wrong Downloads path:** Script had `/subvol6-tmp/10-downloads`, correct is `/subvol6-tmp/Downloads`
3. **`chmod` resets ACL mask:** `chmod 0755` sets mask to `r-x`, limiting named ACL entries to `#effective:r-x`. Fix: re-apply ACLs after chmod

## Verification

All 9 service access tests passed:
- Nextcloud www-data: write Documents, Photos, Downloads ✅
- Nextcloud www-data: read Multimedia, Music, Opptak ✅
- Immich: read+write library ✅
- Jellyfin: read media ✅
- Nextcloud file rescan: complete ✅
- Health score: 95/100 (SSD at 75% — pre-existing)

## Rollback

BTRFS read-only snapshots available until manually deleted:
```bash
sudo btrfs subvolume delete /mnt/btrfs-pool/.snapshots/subvol{1-docs,2-pics,3-opptak,6-tmp}-pre-perms
```
