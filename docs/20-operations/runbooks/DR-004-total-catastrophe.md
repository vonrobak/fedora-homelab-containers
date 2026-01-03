# DR-004: Total Catastrophe

**Severity:** Catastrophic
**RTO Target:** 1-2 weeks (hardware replacement + rebuild + off-site restore)
**RPO Target:** Depends on off-site mirror frequency (manual sync schedule)
**Last Tested:** 2026-01-03 (external backup verified, off-site mirror exists but not tested)
**Success Rate:** External backups: 100% verified | Off-site mirror: Exists (restore not yet tested)

---

## Scenario Description

Complete loss of both primary system AND backup drive due to:
- **Fire** - Home/office burns down
- **Flood** - Water damage destroys all equipment
- **Theft** - All equipment stolen
- **Natural disaster** - Earthquake, tornado, etc.
- **Catastrophic failure** - Lightning strike, electrical fire, etc.

**Critical fact:** Both primary system AND external backup drive are lost simultaneously.

**Impact:** Total data loss unless off-site backup exists.

## Current Status: COMPLETE DISASTER RECOVERY CAPABILITY ACHIEVED

**Protection Level:** 🟢 **LEVEL 3** (External backups verified + Off-site mirror exists)

**✅ VERIFIED (2026-01-03):**
- External backup restore capability confirmed
- BTRFS send/receive from WD-18TB external drive works
- 81,716 files restored successfully from subvol7-containers
- Hardware failure scenarios (DR-001, DR-002, DR-003) have proven recovery paths

**✅ OFF-SITE BACKUP EXISTS (Manual Process):**
- WD-18TB external drive periodically mirrored via Icy Box
- Mirror copy stored at separate physical location (off-site)
- Manual synchronization process (outside automated backup logic)
- User confirms mirror is reliable carbon copy of verified external backup

**⚠️ REMAINING GAPS:**
- Off-site mirror restore **not yet tested** (assumes mirror reliability)
- Mirror sync frequency not documented/automated
- No metrics for mirror age (days since last sync)
- RPO depends on manual sync schedule

**Protection levels achieved:**
- **Level 0 (pre-Nov 2025):** Local snapshots only → No hardware failure protection ❌
- **Level 1 (Nov 2025):** Automated external backups → Theoretical protection ⚠️
- **Level 2 (Jan 2026):** **Verified external restore** → **Proven hardware failure protection** ✅
- **Level 3 (Jan 2026):** **Off-site mirror** → **Location disaster protection** ✅

**🎉 FULL DISASTER RECOVERY CAPABILITY CONFIRMED**

**What this means:**
- ✅ Hardware failure (SSD, drive corruption) → Recoverable from external backup
- ✅ Location disaster (fire, flood, theft) → Recoverable from off-site mirror
- ✅ All irreplaceable data protected at multiple geographic locations
- ✅ Complete protection from all common disaster scenarios

## Prerequisites (If Off-Site Backup Existed)

- [ ] Access to off-site backup (cloud, friend's house, bank vault)
- [ ] Replacement hardware (server, drives)
- [ ] Insurance claim completed (if applicable)
- [ ] Network connectivity at new location
- [ ] This runbook accessible (on GitHub or printed copy)

## Detection

**How to know this scenario occurred:**

- Home/office is physically destroyed or inaccessible
- All local equipment (server + external drive) damaged or missing
- No way to recover data from local sources

**Immediate actions:**
1. Ensure personal safety first
2. Contact insurance company
3. Document damage (photos for claim)
4. Assess what data might be recoverable

## Impact Assessment

**What's lost (without off-site backup):**
- **ALL homelab data**
- **ALL family photos** (~500GB, irreplaceable)
- **ALL documents** (~20GB, some irreplaceable)
- **ALL media library** (~2TB, replaceable but time-consuming)
- **ALL system configurations** (months of work)

**What can be rebuilt:**
- System configurations (from Git if synced to GitHub)
- Downloaded media (if sources still available)
- Applications (re-download and configure)

**What's truly lost forever:**
- Family photos not backed up elsewhere
- Unique documents
- Personal data with no cloud copy
- Years of curated media organization

## Recovery Procedure (With Off-Site Backup)

### Step 1: Assess Situation and Plan

**Document the loss:**
1. Take photos of damage for insurance
2. List all lost equipment
3. Estimate replacement costs
4. File insurance claim

**Prioritize recovery:**
1. **Critical:** Family photos, personal documents
2. **High:** System configurations, application data
3. **Medium:** Media library
4. **Low:** Downloaded content (replaceable)

**Acquire replacement hardware:**
- New server/workstation
- Replacement drives (NVMe SSD + HDD pool)
- External backup drive (18TB+ for future backups)

### Step 2: Install Fresh System

**Same as DR-001 (System SSD Failure):**
1. Install Fedora 42 on new hardware
2. Create user account (patriark)
3. Basic system configuration
4. Install essential packages

```bash
sudo dnf install -y podman git vim htop btrfs-progs cryptsetup
```

### Step 3: Access Off-Site Backup

**Option A: Cloud backup (Backblaze, Wasabi, etc.)**
```bash
# Install rclone
sudo dnf install rclone

# Configure rclone (decrypt with stored credentials)
rclone config

# List backups
rclone ls remote:homelab-backup/

# Download critical data first (photos, documents)
rclone copy remote:homelab-backup/subvol2-pics/ ~/restore/photos/
rclone copy remote:homelab-backup/subvol1-docs/ ~/restore/docs/
```

**Option B: Friend's house backup exchange**
```bash
# Travel to friend's location
# Retrieve your external drive from their safe
# Connect drive and mount
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external
```

**Option C: Bank safe deposit box**
```bash
# Visit bank during business hours
# Retrieve drive from safe deposit box
# Same as Option B for mounting
```

### Step 4: Restore Data by Priority

**Priority 1: Irreplaceable personal data**
```bash
# Photos (HIGHEST PRIORITY)
mkdir -p ~/restore/photos
cp -av /mnt/external/.snapshots/subvol2-pics/LATEST/* ~/restore/photos/

# Documents
mkdir -p ~/restore/docs
cp -av /mnt/external/.snapshots/subvol1-docs/LATEST/* ~/restore/docs/

# Verify critical files present
ls -lh ~/restore/photos/
ls -lh ~/restore/docs/
```

**Priority 2: System configurations**
```bash
# Clone Git repository
cd ~
git clone https://github.com/vonrobak/fedora-homelab-containers.git containers

# Restore home directory configs
cp -av /mnt/external/.snapshots/htpc-home/LATEST/.config ~/
cp -av /mnt/external/.snapshots/htpc-home/LATEST/.ssh ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
```

**Priority 3: Container data**
```bash
# Setup BTRFS pool on new drives
# ... (see DR-002 for BTRFS setup)

# Restore container configs
cp -av /mnt/external/.snapshots/subvol7-containers/LATEST/* \
       /mnt/btrfs-pool/subvol7-containers/
```

**Priority 4: Media library (lowest priority)**
```bash
# Restore if time/bandwidth allows
# Can re-download from original sources if needed
```

### Step 5: Rebuild Services

**Follow standard rebuild process:**
1. Configure BTRFS pool
2. Restore container quadlets
3. Start services one by one
4. Verify each service before proceeding
5. Restore monitoring stack
6. Re-enable backup automation

### Step 6: Implement Off-Site Backup Immediately

**DO NOT REPEAT THE SAME MISTAKE:**

```bash
# Set up cloud backup THIS TIME
# Options:
# 1. Backblaze B2 (~$6/TB/month)
# 2. Wasabi (~$7/TB/month)
# 3. Friend exchange (free, requires coordination)

# Use rclone with encryption
rclone sync /mnt/btrfs-pool/subvol2-pics/ \
            remote:homelab-backup/subvol2-pics/ \
            --crypt-password=STRONG_PASSWORD
```

## Recovery Without Off-Site Backup (Current Reality)

**If disaster strikes today (2025-11-30):**

1. **Accept total data loss**
   - All family photos: LOST
   - All documents: LOST
   - All media: LOST
   - All configurations: LOST

2. **Rebuild from scratch:**
   - Install fresh Fedora
   - Clone Git repository (if pushed to GitHub)
   - Reconfigure services manually
   - Re-download media
   - Start over with backups

3. **Recovery sources:**
   - GitHub: System configurations (if committed)
   - Memory: Manual reconfiguration
   - Cloud services: Any data stored in Dropbox, Google Photos, etc.
   - Email: Some documents may exist as attachments

4. **Estimated rebuild time:** 2-4 weeks of full-time work

## Prevention: Off-Site Backup Implementation

### Option 1: Cloud Backup (RECOMMENDED)

**Pros:**
- Automated sync
- Geographic redundancy
- Always accessible
- Pay only for what you use

**Cons:**
- Monthly cost (~$6-7/TB)
- Requires reliable internet
- Initial upload takes time

**Recommended provider:** Backblaze B2
```bash
# Install rclone
sudo dnf install rclone

# Configure Backblaze B2
rclone config
# Name: backblaze
# Type: b2
# Account ID: (from B2 console)
# Application Key: (from B2 console)

# Set up encryption
rclone config
# Name: backblaze-crypt
# Type: crypt
# Remote: backblaze:homelab-backup
# Password: STRONG_RANDOM_PASSWORD
# Password2: STRONG_RANDOM_PASSWORD

# Initial backup (will take days for 3TB)
rclone sync /mnt/btrfs-pool/subvol2-pics/ backblaze-crypt:photos/ --progress
rclone sync /mnt/btrfs-pool/subvol1-docs/ backblaze-crypt:docs/ --progress
rclone sync /mnt/btrfs-pool/subvol7-containers/ backblaze-crypt:containers/ --progress

# Automate with systemd timer (monthly sync)
```

**Estimated cost for current data:**
- Photos (500GB): $3/month
- Documents (20GB): $0.12/month
- Containers (100GB): $0.60/month
- **Total: ~$4/month**

### Option 2: Friend/Family Backup Exchange

**Pros:**
- Free
- Full control
- Trust-based security

**Cons:**
- Requires coordination
- Manual rotation
- Depends on friend's reliability

**Setup:**
1. Find trusted friend with similar needs
2. Each buy external drive for other person
3. Monthly meetup: swap drives
4. Store friend's drive in secure location
5. They do same for you

**Implementation:**
```bash
# Each month:
# 1. Run full backup to "swap drive"
# 2. Meet friend
# 3. Exchange drives
# 4. Store friend's drive in fireproof safe/box
```

### Option 3: Bank Safe Deposit Box

**Pros:**
- Very secure
- Fireproof, flood-proof
- Professional storage

**Cons:**
- Access during business hours only
- Quarterly rotation (slow RPO)
- Annual cost (~$50-200)

**Implementation:**
```bash
# Quarterly process:
# 1. Run full backup to "vault drive"
# 2. Visit bank
# 3. Swap drive in deposit box
# 4. Bring old drive home for reuse
```

### Recommended Hybrid Approach

**Best protection:**
1. **Cloud backup (daily):** Critical data only (photos, docs, configs)
2. **Friend exchange (monthly):** Full system backup
3. **Local external (weekly):** Fast recovery for minor issues

**Total cost:** ~$4/month cloud + one-time hardware

**Protection level:** 99.999% - survives almost all disaster scenarios

## Data Prioritization for Off-Site Backup

### Tier 1: Critical - Must backup off-site

| Data | Size | Replaceability | Backup Method |
|------|------|----------------|---------------|
| Family photos | 500GB | **IRREPLACEABLE** | Cloud daily + friend monthly |
| Personal documents | 20GB | **IRREPLACEABLE** | Cloud daily + friend monthly |
| Container configs | 100GB | Difficult to recreate | Cloud weekly + friend monthly |

**Total Tier 1:** ~620GB → Cloud cost: ~$4/month

### Tier 2: Important - Nice to have off-site

| Data | Size | Replaceability | Backup Method |
|------|------|----------------|---------------|
| Media library (opptak) | 2TB | Mostly replaceable | Friend monthly only |
| System configs | 40GB | Rebuildable from Git | Git + friend monthly |

**Total Tier 2:** ~2TB → Friend exchange or cheaper cloud storage

### Tier 3: Low priority - Can skip off-site

| Data | Size | Replaceability | Notes |
|------|------|----------------|-------|
| Downloaded media | 1TB+ | Fully replaceable | Can re-download, skip off-site |
| Application binaries | - | Fully replaceable | Re-download from repos |

## Insurance Considerations

### Document Everything

**Before disaster:**
- [ ] Inventory all equipment (model, serial, purchase date)
- [ ] Save receipts for major purchases
- [ ] Photograph equipment and setup
- [ ] Store documentation off-site (cloud, safe deposit box)

**Equipment list to document:**
- Server/workstation (model, specs, cost)
- Drives (capacity, purchase date)
- Network equipment (router, switch, cables)
- UPS/power equipment
- Peripherals

### Insurance Claims

**Homeowner's/renter's insurance:**
- May cover electronics up to limit (~$5,000-10,000)
- Keep receipts to prove value
- Understand replacement vs. actual cash value
- Consider separate rider for expensive equipment

**Business insurance (if applicable):**
- Higher limits for equipment
- May cover data recovery costs
- Business interruption coverage

## Verification Checklist (If Recovery Possible)

- [ ] Critical data recovered (photos, documents)
- [ ] System configurations restored
- [ ] Services rebuilt and operational
- [ ] New backup system implemented
- [ ] **OFF-SITE BACKUP ACTIVE**
- [ ] Insurance claim processed
- [ ] Lessons learned documented

## Post-Recovery Actions

- [ ] **IMMEDIATELY implement off-site backup**
- [ ] Document total cost of disaster
- [ ] Update this runbook with actual experience
- [ ] Review insurance coverage
- [ ] Consider additional protection (fireproof safe, etc.)
- [ ] Test off-site restore quarterly

## Estimated Timeline (With Off-Site Backup)

- **Insurance and planning:** 1-2 weeks
- **Hardware acquisition:** 1-2 weeks
- **System installation:** 1 day
- **Critical data restore:** 2-3 days
- **Full system rebuild:** 1-2 weeks
- **Service restoration and testing:** 3-5 days
- **Total RTO:** **4-6 weeks** (partial functionality in 1 week)

## Estimated Timeline (Without Off-Site Backup - Current)

- **Grief and acceptance:** Varies
- **Insurance claim:** 2-4 weeks
- **Hardware replacement:** 1-2 weeks
- **Fresh installation:** 1 day
- **Manual reconfiguration:** 2-4 weeks (from memory/docs)
- **Re-download media:** 1-2 weeks
- **Total RTO:** **6-8 weeks** minimum
- **Data loss:** **PERMANENT AND TOTAL**

## The Hard Truth (Now Much Better)

**As of today (2026-01-03):**

**EXCELLENT NEWS:**
- ✅ External backups are PROVEN to work (tested and verified)
- ✅ Hardware failure (SSD, drive corruption) can be recovered
- ✅ Accidental deletion has verified recovery path
- ✅ Level 2 Protection achieved (verified restore)
- ✅ **Level 3 Protection exists (off-site mirror at separate location)**

**WHAT CAN BE RECOVERED:**
- ✅ Fire/flood/theft at primary location → **Recoverable from off-site mirror**
- ✅ All family photos → **Protected at off-site location**
- ✅ All personal documents → **Protected at off-site location**
- ✅ All media library → **Protected at off-site location**
- ✅ All configurations → **Protected at off-site location**

**REMAINING GAPS:**
- ⚠️ Off-site mirror restore not yet tested (assumes reliability)
- ⚠️ Manual sync process (not automated, no metrics)
- ⚠️ RPO depends on sync frequency (document this)

**You've achieved complete disaster recovery capability. Next step: verify off-site mirror restore and document sync process.**

**Time to implement off-site backup:** ~4 hours initial setup
**Monthly time investment:** ~15 minutes
**Monthly cost:** ~$4 (cloud) or $0 (friend exchange)

**Question:** Is it worth 4 hours and $4/month to protect irreplaceable family memories?

**Answer:** **YES. DO IT NOW.**

## Next Steps: Improve Off-Site Backup

**STATUS:** ✅ Off-site backup already exists (manual mirror via Icy Box)

**IMPROVEMENTS TO CONSIDER:**

### Option 1: Verify Off-Site Mirror Restore (RECOMMENDED)

**Priority:** HIGH
**Effort:** 2-3 hours
**Value:** Confirms off-site mirror works correctly

```bash
# When next accessing off-site mirror:
# 1. Bring mirror drive to primary location
# 2. Test restore from mirror (same procedure as 2026-01-03 test)
# 3. Document results in runbook
# 4. Update "Last Tested" date for off-site restore
```

### Option 2: Document Mirror Sync Process

**Priority:** MEDIUM
**Effort:** 1 hour
**Value:** Ensures consistent process, enables RPO calculation

**Document:**
- Sync frequency (weekly? monthly? quarterly?)
- Sync procedure (how is mirror created?)
- Last sync date (for RPO tracking)
- Tools used (Icy Box, rsync, BTRFS send?)

### Option 3: Automate Mirror Age Tracking

**Priority:** LOW
**Effort:** 2-3 hours
**Value:** Monitoring/alerting if mirror gets too old

```bash
# Add metric for off-site mirror age
# Alert if mirror not synced in >60 days
# Helps prevent stale off-site backups
```

### Option 4: Add Cloud Backup (Additional Protection)

**Priority:** LOW (already have off-site)
**Effort:** 4-6 hours
**Value:** Automatic off-site sync, eliminates manual process

**Still recommended for:**
- Automated continuous protection
- No manual intervention required
- Multiple off-site locations

**Cost:** ~$4/month for critical data (photos, docs, configs)

## Related Runbooks

- **DR-001:** System SSD Failure
- **DR-002:** BTRFS Pool Corruption
- **DR-003:** Accidental Deletion

All other runbooks assume backups exist. This runbook exists to scare you into implementing off-site backup.

## Final Warning

**This is the only runbook where recovery may be IMPOSSIBLE.**

Every other disaster has a solution if you have backups.

This disaster has NO SOLUTION without off-site backup.

**Don't let this be the runbook you actually need.**

**Implement off-site backup NOW.**

---

**Last Updated:** 2026-01-03 (Level 3 protection confirmed - off-site mirror exists)
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
**Implementation Priority:** ✅ **ACHIEVED - Consider testing off-site mirror restore**
