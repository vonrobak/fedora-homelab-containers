# Nextcloud Operational Runbook

**Service:** Nextcloud File Sync and Collaboration  
**Purpose:** Step-by-step operational procedures  
**Audience:** System administrators  
**Last Updated:** 2025-12-20

---

## Table of Contents

1. [User Management](#user-management)
2. [FIDO2/WebAuthn Device Management](#fido2webauthn-device-management)
3. [External Storage Management](#external-storage-management)
4. [Backup and Restore](#backup-and-restore)
5. [Maintenance Tasks](#maintenance-tasks)
6. [Disaster Recovery](#disaster-recovery)
7. [Troubleshooting Scenarios](#troubleshooting-scenarios)

---

## User Management

### Create New User Account

**Prerequisites:** Admin access to Nextcloud web UI

**Procedure:**
1. Navigate to https://nextcloud.patriark.org
2. Authenticate with FIDO2 device (touch YubiKey or use Touch ID)
3. Click profile icon (top right) → **Settings**
4. Left sidebar → **Users**
5. Click **New user** button
6. Fill in fields:
   - **Username:** lowercase, no spaces (e.g., `bjorn`)
   - **Display name:** Full name (e.g., `Bjørn Hansen`)
   - **Password:** Generate strong password or leave empty for passwordless
   - **Email:** User's email address (optional)
   - **Groups:** Select groups (e.g., `family`, `users`)
   - **Quota:** Set storage limit (e.g., `100 GB`)
7. Click **Add user**

8. **Optional - Configure Passwordless for New User:**
   - User must log in (with temp password if set)
   - User goes to Settings → Personal → Security
   - User registers FIDO2 devices (YubiKey, fingerprint, etc.)
   - User generates backup codes
   - Admin can then disable password requirement

**Verification:**
- User appears in user list
- User can log in with credentials
- User's quota is enforced

**Rollback:**
- Click trash icon next to user → Confirm deletion

---

### Modify User Account

**Procedure:**
1. Settings → **Users**
2. Find user in list
3. Click on user row to expand options
4. Modify:
   - **Quota:** Change storage limit
   - **Groups:** Add/remove group membership
   - **Display name:** Update full name
   - **Disable/Enable:** Toggle user access
5. Changes auto-save

**Common Modifications:**

**Increase Quota:**
- Click quota dropdown → Select new limit or type custom value

**Reset Password:**
- Click three dots menu → **Set password**
- Enter new password → Save
- User must use new password on next login

**Add to Group:**
- Click groups field → Select group from dropdown
- User immediately gains group permissions

**Disable User (Temporary):**
- Toggle switch next to user → **Disabled**
- User cannot log in but files remain

---

### Delete User Account

**⚠️ WARNING:** This is permanent. All user files and data will be deleted.

**Procedure:**
1. **Backup user data first:**
   ```bash
   # Create backup
   sudo tar -czf ~/nextcloud-backup-USERNAME-$(date +%Y%m%d).tar.gz \
     /mnt/btrfs-pool/subvol7-containers/nextcloud/data/data/USERNAME/
   ```

2. **Delete from Web UI:**
   - Settings → Users
   - Find user in list
   - Click **trash icon** (⚠️ far right)
   - Confirm deletion: Type username → Click **Delete user**

3. **Verification:**
   - User no longer appears in user list
   - User data directory deleted: `/mnt/btrfs-pool/subvol7-containers/nextcloud/data/data/USERNAME/`
   - Shares owned by user are removed

**Post-Deletion Cleanup:**
- Review and reassign orphaned shares
- Check external storage access permissions
- Update group folder memberships

---

## FIDO2/WebAuthn Device Management

### Register New FIDO2 Device

**Prerequisites:** User logged in, physical device available

**Procedure:**
1. Settings → **Personal** → **Security**
2. Scroll to **FIDO2/WebAuthn Passwordless Authentication**
3. Click **Add security key**
4. Browser prompts: "Use security key to sign in"
5. **Insert and touch device:**
   - YubiKey: Insert USB key, touch gold contact
   - Touch ID: Place finger on sensor
   - Fingerprint reader: Scan finger
6. **Name the device:**
   - Example: "YubiKey 5 NFC - Backup"
   - Click **Add**
7. Device appears in registered devices list

**Verification:**
- Device shows in list with name and registration date
- Test login: Log out → "Log in with a device" → Touch new device

**Troubleshooting:**
- **Browser doesn't prompt:** Check HTTPS (WebAuthn requires secure context)
- **Device not recognized:** Try different USB port, check compatibility
- **Already registered:** Device can only be registered once per user

---

### Remove Lost/Stolen Device

**Procedure:**
1. **Log in with different device** (not the lost one!)
2. Settings → Personal → Security
3. Scroll to **FIDO2/WebAuthn devices**
4. Find lost device in list
5. Click **Remove** button next to device name
6. Confirm removal

**Verification:**
- Device no longer appears in list
- Attempting to use removed device shows error

**Security Note:**
- Lost YubiKeys cannot be used by finder (domain-bound)
- However, remove from list to prevent confusion
- Generate new backup codes after device loss

---

### Generate Backup Codes

**Purpose:** Emergency access if all FIDO2 devices unavailable

**Procedure:**
1. Settings → Personal → Security
2. Scroll to **Two-factor backup codes**
3. Click **Generate new codes**
4. **10 single-use codes** displayed:
   ```
   ABCD-EFGH-IJKL
   MNOP-QRST-UVWX
   ... (8 more)
   ```
5. **Important:**
   - **Print codes** → Store in secure location (safe, drawer)
   - **Or save to password manager** (Vaultwarden)
   - Codes shown only once!
6. Click **I have saved the codes**

**Using Backup Code:**
1. Navigate to login page
2. Click **Use backup code** link (instead of device login)
3. Enter one code → Submit
4. Logged in ✅
5. **Immediately register new device** (backup code is now used/invalid)

**Security Best Practices:**
- Generate 10 codes, store securely
- Each code works once only
- After using code, generate new set
- Never store codes in plain text on computer

---

## External Storage Management

### Add New External Storage Mount

**Prerequisites:** Storage path exists in container

**Procedure:**

**1. Add Volume to Container (if new):**
```bash
# Edit nextcloud.container
vim ~/.config/containers/systemd/nextcloud.container

# Add volume line in "External storage" section
Volume=/mnt/btrfs-pool/subvolX-name:/external/mount-name:Z

# Save and restart
systemctl --user daemon-reload
systemctl --user restart nextcloud.service
```

**2. Configure in Web UI:**
1. Settings → Administration → **External storage**
2. Click **Add storage** → **Local**
3. Configuration:
   - **Folder name:** Display name (e.g., "Family Photos")
   - **Configuration → External Storage:** `/external/mount-name`
   - **Available for:** Select users/groups (or leave blank for all)
4. Click **checkmark** to save
5. **Verify:** Green checkmark appears (connection successful)

**3. Test Access:**
- Navigate to **Files** app
- External storage appears in sidebar
- Click folder → Files should be visible
- Try creating file (if read-write) or viewing file (if read-only)

**Common Storage Types:**
- **Read-only media:** `:ro,Z` suffix (e.g., Immich photos, music)
- **Read-write shared:** `:Z` suffix (e.g., family documents)
- **User-specific:** Mount under user directory path

---

### Remove External Storage Mount

**Procedure:**

**1. Remove from Web UI:**
1. Settings → Administration → External storage
2. Find mount in list
3. Click **trash icon** (far right)
4. Confirm removal

**2. Remove Volume from Container (optional):**
```bash
# Edit nextcloud.container
vim ~/.config/containers/systemd/nextcloud.container

# Remove or comment out Volume= line
# Volume=/mnt/btrfs-pool/subvolX-name:/external/mount-name:Z

# Save and restart
systemctl --user daemon-reload
systemctl --user restart nextcloud.service
```

**Verification:**
- Mount no longer appears in Files app
- External storage list shows mount removed

---

## Backup and Restore

### Full System Backup

**Procedure:**

**1. Enable Maintenance Mode:**
```bash
podman exec -u www-data nextcloud php occ maintenance:mode --on
```

**2. Create BTRFS Snapshots:**
```bash
# Nextcloud data
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol7-containers \
  /mnt/btrfs-pool/snapshots/nextcloud-full-$(date +%Y%m%d-%H%M%S)

# User documents (if on separate subvolume)
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol1-docs \
  /mnt/btrfs-pool/snapshots/docs-$(date +%Y%m%d-%H%M%S)

# User photos
sudo btrfs subvolume snapshot -r \
  /mnt/btrfs-pool/subvol2-pics \
  /mnt/btrfs-pool/snapshots/pics-$(date +%Y%m%d-%H%M%S)
```

**3. Backup Database:**
```bash
# Export database
podman exec nextcloud-db mysqldump \
  -u nextcloud \
  --single-transaction \
  --quick \
  --lock-tables=false \
  nextcloud > ~/containers/backups/nextcloud-db-$(date +%Y%m%d-%H%M%S).sql

# Compress backup
gzip ~/containers/backups/nextcloud-db-$(date +%Y%m%d-%H%M%S).sql
```

**4. Backup Configuration:**
```bash
# Config file
cp /mnt/btrfs-pool/subvol7-containers/nextcloud/data/config/config.php \
   ~/containers/backups/config.php.$(date +%Y%m%d-%H%M%S)

# Quadlet files
cp ~/.config/containers/systemd/nextcloud*.container \
   ~/containers/backups/quadlets/
```

**5. Disable Maintenance Mode:**
```bash
podman exec -u www-data nextcloud php occ maintenance:mode --off
```

**Verification:**
```bash
# Check snapshot exists
sudo btrfs subvolume list /mnt/btrfs-pool | grep nextcloud

# Check database backup
ls -lh ~/containers/backups/nextcloud-db-*.sql.gz

# Test config backup
cat ~/containers/backups/config.php.* | grep dbhost
```

---

### Restore from Backup

**⚠️ WARNING:** This will overwrite current data. Use with caution.

**Procedure:**

**1. Stop Services:**
```bash
systemctl --user stop nextcloud.service nextcloud-db.service nextcloud-redis.service
```

**2. Restore Data from BTRFS Snapshot:**
```bash
# List available snapshots
sudo btrfs subvolume list /mnt/btrfs-pool | grep nextcloud

# Delete current subvolume
sudo btrfs subvolume delete /mnt/btrfs-pool/subvol7-containers/nextcloud

# Restore from snapshot (make read-write copy)
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/snapshots/nextcloud-full-20251220-140000 \
  /mnt/btrfs-pool/subvol7-containers/nextcloud
```

**3. Restore Database (optional if data snapshot includes DB):**
```bash
# Start database
systemctl --user start nextcloud-db.service

# Wait for database to be ready
sleep 10

# Drop existing database
podman exec nextcloud-db mysql -u root -e "DROP DATABASE nextcloud;"
podman exec nextcloud-db mysql -u root -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# Restore from SQL dump
gunzip < ~/containers/backups/nextcloud-db-20251220-140000.sql.gz | \
  podman exec -i nextcloud-db mysql -u nextcloud nextcloud
```

**4. Restart Services:**
```bash
systemctl --user start nextcloud-db.service nextcloud-redis.service nextcloud.service
```

**5. Verification:**
```bash
# Check status
systemctl --user status nextcloud.service

# Check web access
curl -f https://nextcloud.patriark.org/status.php

# Check files in web UI
# Login → Files → Verify data is present
```

**6. Run Integrity Check:**
```bash
podman exec -u www-data nextcloud php occ maintenance:repair
podman exec -u www-data nextcloud php occ files:scan --all
```

---

## Maintenance Tasks

### Update Nextcloud (Minor Version)

**Example:** 30.0.1 → 30.0.2

**Procedure:**

**1. Backup First:**
```bash
# Run full backup (see above)
```

**2. Enable Maintenance Mode:**
```bash
podman exec -u www-data nextcloud php occ maintenance:mode --on
```

**3. Pull New Image:**
```bash
# Check current version
podman exec nextcloud cat /usr/src/nextcloud/version.php | grep versionstring

# Pull latest 30.x.x
podman pull docker.io/library/nextcloud:30

# Or use auto-update
podman auto-update
```

**4. Restart Container:**
```bash
systemctl --user restart nextcloud.service
```

**5. Run Upgrade:**
```bash
# Container auto-runs upgrade on start
# Watch logs:
podman logs -f nextcloud

# Or manually trigger:
podman exec -u www-data nextcloud php occ upgrade
```

**6. Disable Maintenance Mode:**
```bash
podman exec -u www-data nextcloud php occ maintenance:mode --off
```

**7. Verification:**
```bash
# Check version
podman exec nextcloud cat /usr/src/nextcloud/version.php | grep versionstring

# Check status
podman exec -u www-data nextcloud php occ status

# Check web UI
curl -f https://nextcloud.patriark.org/status.php
```

---

### Database Optimization

**Run Monthly** to maintain performance

**Procedure:**
```bash
# 1. Enable maintenance mode
podman exec -u www-data nextcloud php occ maintenance:mode --on

# 2. Add missing database indices
podman exec -u www-data nextcloud php occ db:add-missing-indices

# 3. Add missing columns (if any)
podman exec -u www-data nextcloud php occ db:add-missing-columns

# 4. Convert filecache to BigInt (for large instances)
podman exec -u www-data nextcloud php occ db:convert-filecache-bigint

# 5. Optimize MariaDB tables
podman exec nextcloud-db mysql -u root -e "OPTIMIZE TABLE nextcloud.oc_filecache;"
podman exec nextcloud-db mysql -u root -e "OPTIMIZE TABLE nextcloud.oc_share;"

# 6. Disable maintenance mode
podman exec -u www-data nextcloud php occ maintenance:mode --off
```

**Expected Duration:** 5-30 minutes depending on database size

---

### Clean Up Old Files

**Remove Trashed Files Older Than 30 Days:**
```bash
podman exec -u www-data nextcloud php occ trashbin:cleanup --all-users
```

**Remove Old File Versions:**
```bash
# Remove versions older than 30 days
podman exec -u www-data nextcloud php occ versions:cleanup
```

**Remove Orphaned Files:**
```bash
podman exec -u www-data nextcloud php occ files:cleanup
```

---

## Disaster Recovery

### Scenario 1: Complete Data Loss

**Situation:** Nextcloud data directory corrupted/deleted

**Recovery Procedure:**

**1. Assess Damage:**
```bash
ls -la /mnt/btrfs-pool/subvol7-containers/nextcloud/data/
# If empty or corrupted, proceed
```

**2. Restore from Latest BTRFS Snapshot:**
```bash
# Stop services
systemctl --user stop nextcloud.service nextcloud-db.service nextcloud-redis.service

# Delete corrupted subvolume
sudo btrfs subvolume delete /mnt/btrfs-pool/subvol7-containers/nextcloud

# Restore from snapshot
LATEST_SNAPSHOT=$(sudo btrfs subvolume list /mnt/btrfs-pool | grep nextcloud-full | tail -1 | awk '{print $NF}')
sudo btrfs subvolume snapshot /mnt/btrfs-pool/${LATEST_SNAPSHOT} /mnt/btrfs-pool/subvol7-containers/nextcloud

# Restart services
systemctl --user start nextcloud-db.service nextcloud-redis.service nextcloud.service
```

**3. Verify Recovery:**
```bash
curl -f https://nextcloud.patriark.org/status.php
# Login via web UI and check files
```

**Recovery Time Objective (RTO):** 15 minutes
**Recovery Point Objective (RPO):** Last snapshot (daily recommended)

---

### Scenario 2: Database Corruption

**Situation:** MariaDB database corrupted

**Recovery Procedure:**

**1. Stop Nextcloud:**
```bash
systemctl --user stop nextcloud.service
```

**2. Attempt Repair:**
```bash
# Check for corruption
podman exec nextcloud-db mysqlcheck -u root --all-databases --check

# Attempt auto-repair
podman exec nextcloud-db mysqlcheck -u root --all-databases --auto-repair
```

**3. If Repair Fails, Restore from Backup:**
```bash
# Find latest SQL backup
ls -lht ~/containers/backups/nextcloud-db-*.sql.gz | head -1

# Restore (see Restore from Backup section above)
```

**4. Restart and Verify:**
```bash
systemctl --user start nextcloud.service
curl -f https://nextcloud.patriark.org/status.php
```

**RTO:** 30 minutes
**RPO:** Last database backup

---

### Scenario 3: Lost FIDO2 Devices

**Situation:** All YubiKeys lost/stolen, cannot log in

**Recovery Procedure:**

**1. Use Backup Code:**
- Navigate to https://nextcloud.patriark.org
- Click "Use backup code"
- Enter one of the 10 printed backup codes
- Logged in ✅

**2. Register New FIDO2 Device:**
- Settings → Personal → Security → FIDO2/WebAuthn
- Click "Add security key"
- Register new YubiKey or use Touch ID

**3. Remove Lost Devices:**
- Find old devices in list
- Click "Remove" for each lost device

**4. Generate New Backup Codes:**
- Settings → Security → Two-factor backup codes
- Generate new codes
- Print and store securely

**RTO:** Immediate (if backup codes accessible)
**Prevention:** Store backup codes in secure location (safe, password manager)

---

## Troubleshooting Scenarios

### Issue: Login Fails with "Invalid credentials"

**Symptoms:** Web UI login shows error despite correct password

**Diagnosis:**
1. **Check if passwordless auth is enabled:**
   - Try "Log in with a device" instead of password
   - Touch FIDO2 device

2. **Check if user exists:**
   ```bash
   podman exec -u www-data nextcloud php occ user:list | grep username
   ```

3. **Check authentication backend:**
   ```bash
   podman logs nextcloud | grep -i "auth\|login"
   ```

**Solutions:**
- **Passwordless user:** Use FIDO2 device, not password
- **Password forgotten:** Admin resets via Settings → Users → Set password
- **Account locked:** Check brute-force protection, wait or admin unlocks

---

### Issue: Files Not Syncing on iOS

**Symptoms:** Nextcloud iOS app shows "sync failed"

**Diagnosis:**
1. **Check network connectivity:**
   - Try accessing https://nextcloud.patriark.org in Safari
   - Should load login page

2. **Check app credentials:**
   - Settings (iOS) → Nextcloud → Account
   - Verify server URL and username

3. **Check CalDAV/WebDAV:**
   ```bash
   curl -I https://nextcloud.patriark.org/remote.php/dav/
   # Should return 401 (auth required)
   ```

**Solutions:**
- **Re-authenticate:** Remove and re-add account in Nextcloud app
- **Check auto-upload:** Disable and re-enable in app settings
- **Check storage:** Ensure user quota not exceeded

---

### Issue: External Storage Shows Red X

**Symptoms:** External storage mount shows red X instead of green checkmark

**Diagnosis:**
1. **Check volume mount exists in container:**
   ```bash
   podman exec nextcloud ls -la /external/
   # Should show mount point
   ```

2. **Check mount path in Web UI:**
   - Settings → Administration → External storage
   - Verify path matches container mount (e.g., `/external/user-documents`)

3. **Check permissions:**
   ```bash
   podman exec nextcloud ls -la /external/user-documents/
   # Should be readable by www-data (UID 33)
   ```

**Solutions:**
- **Fix path:** Edit external storage config, correct path
- **Remount volume:** Restart Nextcloud service
- **Fix permissions:** `podman exec nextcloud chown -R www-data:www-data /external/mount`

---

### Issue: High Database Load

**Symptoms:** `podman stats` shows nextcloud-db using 100% CPU

**Diagnosis:**
```bash
# Check active queries
podman exec nextcloud-db mysql -u root -e "SHOW PROCESSLIST;"

# Check slow queries
podman logs nextcloud-db | grep -i "slow"

# Check NOCOW attribute
lsattr -d /mnt/btrfs-pool/subvol7-containers/nextcloud-db/data
```

**Solutions:**
- **Kill long-running query:** `podman exec nextcloud-db mysql -u root -e "KILL <ID>;"`
- **Add missing indices:** `podman exec -u www-data nextcloud php occ db:add-missing-indices`
- **Optimize tables:** See Maintenance Tasks section
- **Verify NOCOW:** Rebuild database with NOCOW if missing

---

## Emergency Contacts & Escalation

**Primary Contact:** patriark  
**Secondary Contact:** Claude Code documentation

**Escalation Path:**
1. Check this runbook
2. Check service guide: `docs/10-services/guides/nextcloud.md`
3. Check logs: `journalctl --user -u nextcloud.service`
4. Check Nextcloud community forums
5. Check ADRs for design rationale

**Critical Service Dependencies:**
- Traefik (reverse proxy) - must be running
- CrowdSec (IP reputation) - should be running
- Network infrastructure - DNS must resolve

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-20 | patriark + Claude Code | Initial runbook creation |

---

**Runbook Status:** ✅ Production Ready  
**Review Cycle:** Quarterly  
**Next Review:** 2025-03-20
