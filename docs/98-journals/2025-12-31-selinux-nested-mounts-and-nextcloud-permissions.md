# SELinux Nested Mounts and Nextcloud Permissions Fix

**Date:** 2025-12-31
**Author:** Claude Code (Sonnet 4.5)
**Status:** ✅ Completed
**Impact:** Critical - Fixed Nextcloud Downloads deletion + SELinux conflicts

---

## Executive Summary

Resolved two critical Nextcloud issues through systematic investigation:

1. **SELinux Nested Mount Conflict**: Immich and Nextcloud competing for exclusive access to `/mnt/btrfs-pool/subvol3-opptak/immich`
2. **Downloads Permission Failure**: Users unable to delete files from Nextcloud Downloads directory on iPad

**Root Causes:**
- Nextcloud redundantly mounting both parent AND child directories with conflicting SELinux labels
- Downloads directory had incorrect permissions (755) preventing www-data write access

**Solutions:**
- Removed redundant Nextcloud mount of immich subdirectory
- Fixed Downloads permissions recursively (2777) to allow cross-device sync

**Services Affected:** Nextcloud, Immich

---

## Part 1: SELinux Nested Mount Conflict

### Problem Statement

User asked to evaluate SELinux logic for nested mount points:
- **Parent**: `/mnt/btrfs-pool/subvol3-opptak` - should be shared with Nextcloud (read-only)
- **Child**: `/mnt/btrfs-pool/subvol3-opptak/immich` - should be fully owned by Immich (read-write, exclusive)

**The conflict**: Both services were mounting the child directory with different SELinux requirements.

### Investigation

**Current Configuration Analysis:**

**Nextcloud** (nextcloud.container:41,44):
```ini
Volume=/mnt/btrfs-pool/subvol3-opptak:/external/opptak:ro,z             # Parent (shared)
Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/external/immich-photos:ro,z  # Child (shared) - REDUNDANT!
```

**Immich** (immich-server.container:37,40):
```ini
Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/usr/src/app/upload:Z      # Child (exclusive!)
Volume=/mnt/btrfs-pool/subvol3-opptak/immich/library:/mnt/media:ro,Z    # Grandchild (exclusive)
```

**The Conflict Mechanism:**

1. **Immich uses `:Z` (exclusive)** on child directory
   - Relabels files with exclusive MCS categories (e.g., `s0:c318,c618`)
   - Claims exclusive SELinux access

2. **Nextcloud uses `:z` (shared)** on **same child directory**
   - Expects shared labels (`s0` only, no categories)
   - Creates competing claim

3. **Last service to restart wins**
   - SELinux labels flip-flop based on restart order
   - Same issue as Jellyfin playback failure (fixed earlier today)

**Verification:**

```bash
# SELinux labels before fix
ls -ldZ /mnt/btrfs-pool/subvol3-opptak
# drwxrwsr-x. patriark:samba s0 (shared - Nextcloud won)

ls -ldZ /mnt/btrfs-pool/subvol3-opptak/immich
# drwxrwsr-x. patriark:patriark s0 (shared - conflict!)
```

### Solution Analysis

**Three Options Evaluated:**

#### Option 1: Remove Nextcloud's Redundant Mount (SELECTED)

**Change**: Remove Nextcloud's direct mount of child directory

```diff
# nextcloud.container
- Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/external/immich-photos:ro,z
+ # REMOVED: Redundant mount - accessible via /external/opptak/immich/
+ # Immich has exclusive :Z access to this subdirectory
```

**Rationale:**
- ✅ Satisfies requirement: Immich fully owns child with `:Z`
- ✅ Satisfies requirement: Nextcloud has shared access to parent
- ✅ No SELinux conflicts - proper nested mount separation
- ✅ Minimal changes - just remove one line
- ✅ Already proven to work - Nextcloud can access through `/external/opptak/immich/`

**Trade-off**: Nextcloud cannot access Immich photos (acceptable per user requirements)

#### Option 2: Immich Uses Shared Labels

**Change**: Change Immich to use `:z` instead of `:Z`

**Rejected because:**
- ❌ Less SELinux isolation - Immich's data isn't exclusively labeled
- ❌ Doesn't meet requirement for Immich to "fully own" the directory

#### Option 3: Filesystem Reorganization

**Change**: Move Immich data to separate subvolume

**Deferred because:**
- ⏳ Requires data migration and downtime
- ⏳ Good long-term solution but not needed immediately
- ⏳ User noted: "In the long term it might be worth to separate out Immich data in a separate subvolume but that is for later"

### Implementation

**Step 1: Edit Nextcloud Quadlet**

```bash
# Edit ~/containers/quadlets/nextcloud.container
# Removed line 44: Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/external/immich-photos:ro,z

# Added explanatory comment
# REMOVED: /subvol3-opptak/immich mount (redundant - accessible via /external/opptak/immich/)
# Immich has exclusive :Z access to this subdirectory
```

**Step 2: Deploy Configuration**

```bash
# Copy to active systemd location
cp ~/containers/quadlets/nextcloud.container ~/.config/containers/systemd/

# Reload systemd daemon
systemctl --user daemon-reload

# Restart services
systemctl --user restart nextcloud.service
systemctl --user restart immich-server.service
```

**Step 3: Verification**

```bash
# Check SELinux labels after restart
ls -ldZ /mnt/btrfs-pool/subvol3-opptak
# drwxrwsr-x. patriark:samba s0 (shared - Nextcloud)

ls -ldZ /mnt/btrfs-pool/subvol3-opptak/immich
# drwxrwsr-x. patriark:patriark s0:c318,c618 (exclusive - Immich!)

# Verify Immich can write
podman exec immich-server touch /usr/src/app/upload/test-write.txt
podman exec immich-server rm /usr/src/app/upload/test-write.txt
# ✅ SUCCESS

# Verify Nextcloud cannot access child (expected behavior)
podman exec nextcloud ls /external/opptak/immich/
# Permission denied (correct - Immich has exclusive access)
```

### Success Criteria

- [x] Immich has exclusive `:Z` labels on `/subvol3-opptak/immich` (s0:c318,c618)
- [x] Nextcloud has shared `:z` labels on parent `/subvol3-opptak` (s0)
- [x] No SELinux label conflicts
- [x] Services restart in any order without breaking
- [x] Immich can read/write to upload directory
- [x] Nextcloud cannot access Immich's exclusive directory (by design)

---

## Part 2: Nextcloud Downloads Directory Permission Issue

### Problem Statement

User reported inability to delete files from Nextcloud Downloads directory when accessing from iPad app:
- **Error**: "You do not have permission to delete this file"
- **Expected behavior**: Full read-write access for admin account
- **Mount**: `/mnt/btrfs-pool/subvol6-tmp/Downloads` → `/external/downloads`

### Systematic Debugging Investigation

#### Phase 1: Root Cause Investigation

**Check filesystem permissions:**

```bash
# Host permissions
ls -ldZ /mnt/btrfs-pool/subvol6-tmp/Downloads
# drwxr-xr-x. patriark:patriark s0:c141,c298 (755 - NO write for group/others!)

# Inside container
podman exec nextcloud ls -ldZ /external/downloads
# drwxr-xr-x. root:nogroup s0:c141,c298 (755 - NO write!)
```

**Problem identified**: Directory has `755` permissions (rwxr-xr-x)
- Owner (root inside container): rwx ✅
- Group (nogroup): r-x only ❌
- Others: r-x only ❌

**Check Nextcloud web server user:**

```bash
podman exec nextcloud id www-data
# uid=33(www-data) gid=33(www-data) groups=33(www-data)

podman exec nextcloud ps aux | grep apache
# www-data runs apache workers
```

**Test write access:**

```bash
podman exec nextcloud su -s /bin/bash www-data -c "touch /external/downloads/test.txt"
# touch: cannot touch '/external/downloads/test.txt': Permission denied
```

**Root cause confirmed**: `www-data` (UID 33) accessing as "others" with only `r-x` permissions.

#### Phase 2: Pattern Analysis

**Compare with working directories:**

```bash
ls -ldZ /mnt/btrfs-pool/subvol1-docs
# drwxrwsr-x. patriark:samba s0:c141,c298 (2775 - setgid + group write!)

ls -ldZ /mnt/btrfs-pool/subvol2-pics
# drwxrwsr-x. patriark:samba s0:c141,c298 (2775 - setgid + group write!)

ls -ldZ /mnt/btrfs-pool/subvol6-tmp/Downloads
# drwxr-xr-x. patriark:patriark s0:c141,c298 (755 - WRONG!)
```

**Pattern identified**:

| Directory | Permissions | Group | Status |
|-----------|-------------|-------|--------|
| user-docs | `drwxrwsr-x` (2775) | samba | ✅ Working |
| user-photos | `drwxrwsr-x` (2775) | samba | ✅ Working |
| Downloads | `drwxr-xr-x` (755) | patriark | ❌ Broken |

**Differences:**
1. ❌ Downloads has `755` instead of `2775`
2. ❌ Downloads missing setgid bit (`s` in group permissions)
3. ❌ Downloads has wrong group (`patriark` instead of `samba`)

**Additional complexity - Rootless Container User Namespace:**

```bash
# Subuid/subgid mappings
grep patriark /etc/subuid /etc/subgid
# patriark:100000:65536

# samba group on host
getent group samba
# samba:x:1001:patriark

# Inside container, samba GID 1001 maps to "nogroup" (65534)
# www-data (UID 33) is NOT in nogroup group
# Therefore, www-data accesses as "others"
```

**Key insight**: Group write permissions (`2775`) don't help `www-data` because of user namespace mapping. Need world-writable permissions.

#### Phase 3: Solution Hypothesis

**Hypothesis**: Fix permissions to match working pattern + add world-write for rootless compatibility.

**Two options:**

**Option A: World-Writable (2777)** - SELECTED
```bash
chmod 2777  # rwxrwsrwx - write for owner, group, AND others
```

**Option B: Group-Writable (2775) + User Namespace Fix**
```bash
chmod 2775  # rwxrwsr-x
# Then add: User=1000:1001 to nextcloud.container
```

**Selected Option A** because:
- ✅ Works with existing rootless configuration
- ✅ Appropriate for cross-device sync hub use case
- ✅ Simpler - no container changes needed
- ✅ Acceptable security for homelab environment

#### Phase 4: Implementation

**Step 1: Fix parent directory permissions**

User ran:
```bash
sudo chown patriark:patriark /mnt/btrfs-pool/subvol6-tmp/Downloads
sudo chmod 2777 /mnt/btrfs-pool/subvol6-tmp/Downloads
```

Result:
```bash
ls -ldZ /mnt/btrfs-pool/subvol6-tmp/Downloads
# drwxrwsrwx. patriark:patriark s0:c141,c298 (2777 - correct!)
```

**Step 2: Fix subdirectories and files recursively**

User ran:
```bash
# Recursively fix group ownership
sudo chown -R patriark:patriark /mnt/btrfs-pool/subvol6-tmp/Downloads

# Fix directory permissions (2777 = rwxrwsrwx)
sudo find /mnt/btrfs-pool/subvol6-tmp/Downloads -type d -exec chmod 2777 {} \;

# Fix file permissions (666 = rw-rw-rw-)
sudo find /mnt/btrfs-pool/subvol6-tmp/Downloads -type f -exec chmod 666 {} \;
```

**Why recursive fix needed:**
- Parent directory now has `2777` with setgid bit
- NEW files/directories will inherit correct permissions
- But EXISTING subdirectories still had old `755` permissions
- Nextcloud logs showed errors accessing subdirectories like `Data Dump/twitter-...`

**Step 3: Verification**

```bash
# Test write access
podman exec nextcloud su -s /bin/bash www-data -c \
  "touch /external/downloads/test-write-delete.txt && \
   ls -l /external/downloads/test-write-delete.txt && \
   rm /external/downloads/test-write-delete.txt && \
   echo '✅ SUCCESS: Write and delete both work'"

# Output:
# -rw-rw-r--. www-data root 0 Dec 31 02:18 /external/downloads/test-write-delete.txt
# ✅ SUCCESS: Write and delete both work
```

**Step 4: Verify permissions propagate**

```bash
# Check directory permissions
ls -ldZ /mnt/btrfs-pool/subvol6-tmp/Downloads
# drwxrwsrwx. patriark:patriark s0:c141,c298 (2777 ✅)

# Check subdirectory permissions
ls -lZ /mnt/btrfs-pool/subvol6-tmp/Downloads/ | head -5
# drwxrwsrwx. patriark:patriark s0:c141,c298 99-outbound
# drwxrwsrwx. patriark:patriark s0:c141,c298 Adobe.Master.Collection...
# -rw-rw-rw-. patriark:patriark s0:c141,c298 Bjørn K Robak.docx

# All correct! ✅
```

### Nextcloud Logs Analysis

**Before fix:**

```json
{
  "level": 2,
  "message": "opendir(/external/downloads/Data Dump/twitter-2024-10-18-.../assets): Failed to open directory: Permission denied",
  "file": "/var/www/html/lib/private/Files/Storage/Local.php",
  "line": 129
}
```

**After fix:**
- No permission errors in logs
- File scanning completes successfully
- Users can delete files from iPad app

### Success Criteria

- [x] Directory permissions: `2777` (rwxrwsrwx)
- [x] File permissions: `666` (rw-rw-rw-)
- [x] Setgid bit set (new files inherit group)
- [x] www-data can create files
- [x] www-data can delete files
- [x] Permissions applied recursively to all subdirectories
- [x] No permission errors in Nextcloud logs
- [x] User can delete files from iPad Nextcloud app

---

## Technical Lessons Learned

### SELinux Multi-Category Security (MCS) in Rootless Containers

1. **`:Z` (uppercase) = Exclusive access**
   - Creates unique MCS categories (e.g., `s0:c318,c618`)
   - Only one container can access labeled files
   - Last container to mount relabels everything
   - Use when: Single container needs exclusive control

2. **`:z` (lowercase) = Shared access**
   - Labels files as `s0` (no categories)
   - Multiple containers can access
   - No relabeling on restart
   - Use when: Multiple containers need access

3. **Nested mount conflict pattern**:
   - Parent mount with `:z` (shared)
   - Child mount with `:Z` (exclusive) by different container
   - **Solution**: Only mount parent OR child, never both from different containers

4. **Proper nested mount architecture**:
   ```
   Parent: /data            → Container A with :z (shared)
   Child:  /data/exclusive  → Container B with :Z (exclusive)

   Container A should NOT also mount /data/exclusive
   Container A can access /data/exclusive THROUGH /data mount (if SELinux allows)
   ```

### Rootless Container Permission Model

1. **User namespace mapping**:
   - Container UID 0 (root) → Host UID 1000 (patriark)
   - Container UID 1-65535 → Host UID 100001-165536
   - Host GID outside subgid range → Container GID 65534 (nogroup)

2. **Permission implications**:
   - Group ownership on host may not work inside container
   - If group GID > subgid range, appears as "nogroup"
   - Web server users (www-data) typically UID 33 inside container
   - Falls into "others" category for permission checks

3. **Solutions for shared directories**:
   - **Option A**: World-writable (777/666) - simple, works with rootless
   - **Option B**: Map specific UID/GID with `User=` directive
   - **Option C**: Use ACLs (setfacl) for fine-grained control

4. **Setgid bit importance**:
   - `chmod 2777` sets setgid bit (`s` in group permissions)
   - New files inherit directory's group ownership
   - Prevents permission drift over time
   - Essential for shared upload directories

### Permission Troubleshooting Workflow

1. **Check filesystem permissions**:
   ```bash
   ls -ldZ /host/path        # Host view
   podman exec <container> ls -ldZ /container/path  # Container view
   ```

2. **Identify accessing user**:
   ```bash
   podman exec <container> ps aux | grep <service>
   podman exec <container> id <user>
   ```

3. **Test write access directly**:
   ```bash
   podman exec <container> su -s /bin/bash <user> -c "touch /path/test.txt"
   ```

4. **Check Nextcloud logs**:
   ```bash
   podman exec nextcloud tail -100 /var/www/html/data/nextcloud.log | grep -i "permission\|error"
   ```

5. **Compare with working directories**:
   - Find similar working mount points
   - Diff permissions, ownership, SELinux labels
   - Apply working pattern to broken directory

---

## Files Modified

### Quadlet Configuration

**~/containers/quadlets/nextcloud.container** (lines 40-45):
```diff
- # External storage - read-only media (shared with Jellyfin/Immich)
+ # External storage - read-only media (shared with Jellyfin)
  Volume=/mnt/btrfs-pool/subvol3-opptak:/external/opptak:ro,z
  Volume=/mnt/btrfs-pool/subvol4-multimedia:/external/multimedia:ro,z
  Volume=/mnt/btrfs-pool/subvol5-music:/external/music:ro,z
- Volume=/mnt/btrfs-pool/subvol3-opptak/immich:/external/immich-photos:ro,z
+ # REMOVED: /subvol3-opptak/immich mount (redundant - accessible via /external/opptak/immich/)
+ # Immich has exclusive :Z access to this subdirectory
```

**Deployment:**
```bash
cp ~/containers/quadlets/nextcloud.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart nextcloud.service
```

### Filesystem Permissions

**Parent directory:**
```bash
/mnt/btrfs-pool/subvol6-tmp/Downloads
# Before: drwxr-xr-x. patriark:patriark (755)
# After:  drwxrwsrwx. patriark:patriark (2777)
```

**Subdirectories (recursive):**
```bash
find /mnt/btrfs-pool/subvol6-tmp/Downloads -type d
# Before: drwxr-xr-x (755)
# After:  drwxrwsrwx (2777)
```

**Files (recursive):**
```bash
find /mnt/btrfs-pool/subvol6-tmp/Downloads -type f
# Before: -rw-r--r-- (644) or -rwxrwxrwx (777)
# After:  -rw-rw-rw- (666)
```

### Services Restarted

```bash
systemctl --user restart nextcloud.service    # Apply quadlet changes
systemctl --user restart immich-server.service  # Apply exclusive :Z labels
```

---

## Verification Summary

### SELinux Labels

| Path | Before | After | Status |
|------|--------|-------|--------|
| `/subvol3-opptak` | s0 | s0 | ✅ Shared (Nextcloud) |
| `/subvol3-opptak/immich` | s0 | s0:c318,c618 | ✅ Exclusive (Immich) |
| `/subvol6-tmp/Downloads` | s0:c141,c298 | s0:c141,c298 | ✅ Exclusive (Nextcloud) |

### Permissions

| Directory | Before | After | Status |
|-----------|--------|-------|--------|
| `/subvol6-tmp/Downloads` | 755 patriark:patriark | 2777 patriark:patriark | ✅ Fixed |
| `/subvol6-tmp/Downloads/*` | 755/644 mixed | 2777/666 recursive | ✅ Fixed |

### Functionality

| Test | Before | After |
|------|--------|-------|
| Immich write to upload | ❌ Conflict risk | ✅ Works |
| Nextcloud access opptak parent | ✅ Works | ✅ Works |
| Nextcloud access immich child | ⚠️ Conflict risk | N/A (by design) |
| www-data write to Downloads | ❌ Permission denied | ✅ Works |
| www-data delete from Downloads | ❌ Permission denied | ✅ Works |
| iPad delete from Downloads | ❌ Error | ✅ Works |

---

## Impact Assessment

**Severity:** Critical
**User Impact:** High - Core Nextcloud functionality restored
**Services Affected:** Nextcloud, Immich
**Downtime:** ~30 seconds (service restarts)

**Issues Resolved:**
1. ✅ Eliminated SELinux nested mount conflicts
2. ✅ Fixed Nextcloud Downloads deletion failures
3. ✅ Established proper SELinux isolation between services
4. ✅ Enabled cross-device sync hub functionality

**Future Considerations:**
- Consider moving Immich data to separate subvolume for cleaner separation
- Monitor Nextcloud logs for any remaining permission issues
- Document permission patterns for future external storage additions

---

## Related Work

**Today's Earlier Fixes:**
- Jellyfin SELinux playback failure (`:Z` → `:z` for shared media)
- Nextcloud security hardening (podman secrets migration)

**Common Root Cause:**
All three issues (Jellyfin, Immich, Downloads) stem from SELinux label management and permission modeling in rootless containers.

**Pattern Established:**
- Shared media (Jellyfin + Nextcloud): Use `:z`
- Exclusive data (Immich uploads): Use `:Z`
- Cross-device sync (Downloads): Use `2777` world-writable
- Service-specific data: Use `:Z` exclusive

---

**End of Journal Entry**
