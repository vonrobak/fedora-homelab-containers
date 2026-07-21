---
type: Runbook
title: "DR-004: Total Catastrophe"
description: "Disaster-recovery runbook for total catastrophe — simultaneous loss of primary system and backup drive, recovered via off-site backup."
sensitivity: public
created: 2025-11-30
updated: 2026-07-21
---

# DR-004: Total Catastrophe

**Severity:** Catastrophic
**RTO Target:** 1-2 weeks (hardware replacement + rebuild + off-site restore)
**RPO Target:** Depends on off-site drive rotation cadence — [Urd](https://github.com/vonrobak/urd)
(ADR-021) now tracks this automatically as a `role = "offsite"` drive (`WD-18TB1`) with an
*observed* rotation forecast; check `urd status` for the live number rather than assuming
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

**✅ OFF-SITE BACKUP EXISTS (Physical Rotation, Urd-Tracked):**
- `WD-18TB1` is registered in Urd (`~/.config/urd/urd.toml`) as a second drive per subvolume with
  `role = "offsite"`, alongside the always-connected `WD-18TB` (`role = "primary"`)
- It's physically rotated in periodically; whenever it's mounted, the same `urd-backup.timer` run
  that sends to `WD-18TB` also sends to it — no separate manual sync step
- While disconnected, `urd status` still reports its `PROTECTED` state from the last known send
  and shows an *observed* rotation cadence/forecast (derived from actual connect history, not a
  config value) — this answers "what's the mirror's real RPO" without manual tracking

**⚠️ REMAINING GAPS:**
- Off-site mirror restore **not yet tested** (assumes mirror reliability)
- No alerting yet if the observed rotation cadence drifts significantly past forecast (i.e. the
  drive hasn't come home in longer than usual) — `urd status`/`urd doctor` must be checked
  manually

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

**Actual implemented path: retrieve the `WD-18TB1` rotation drive**
```bash
# Retrieve WD-18TB1 from its off-site location
# Connect and unlock (same LUKS procedure as WD-18TB)
sudo cryptsetup open /dev/sdX WD-18TB1
sudo mount /dev/mapper/WD-18TB1 /mnt/external

# Same .snapshots/<subvolume>/<YYYYMMDD-HHMM-shortname>/ layout as the primary drive
ls -lh /mnt/external/.snapshots/
```

**Cloud backup (Backblaze, Wasabi, etc.) — NOT currently implemented.** No `rclone` config or
cloud remote exists on this host as of 2026-07-21; this remains a future-improvement option (see
"Next Steps" below), not a fallback you can actually reach for today.

### Step 4: Restore Data by Priority

**Priority 1: Irreplaceable personal data**
```bash
# Photos (HIGHEST PRIORITY)
mkdir -p ~/restore/photos
LATEST_PICS=$(ls -t /mnt/external/.snapshots/subvol2-pics/ | head -1)
cp -av "/mnt/external/.snapshots/subvol2-pics/$LATEST_PICS"/* ~/restore/photos/

# Documents
mkdir -p ~/restore/docs
LATEST_DOCS=$(ls -t /mnt/external/.snapshots/subvol1-docs/ | head -1)
cp -av "/mnt/external/.snapshots/subvol1-docs/$LATEST_DOCS"/* ~/restore/docs/

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
LATEST_HOME=$(ls -t /mnt/external/.snapshots/htpc-home/ | head -1)
cp -av "/mnt/external/.snapshots/htpc-home/$LATEST_HOME/.config" ~/
cp -av "/mnt/external/.snapshots/htpc-home/$LATEST_HOME/.ssh" ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*

# Restore Urd's own config so it can be reinstalled and pointed at the same drives/subvolumes
cp -av "/mnt/external/.snapshots/htpc-home/$LATEST_HOME/.config/urd" ~/.config/
```

**Priority 3: Container data**
```bash
# Setup BTRFS pool on new drives
# ... (see DR-002 for BTRFS setup)

# Restore container configs
LATEST_CONTAINERS=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)
cp -av "/mnt/external/.snapshots/subvol7-containers/$LATEST_CONTAINERS"/* \
       /mnt/btrfs-pool/subvol7-containers/
```

For any single known-missing file rather than a whole-directory restore, reinstall Urd first
(Priority 2 restores its config) and use `urd get FILE --at DATE` instead of hunting through
snapshot directories by hand (see DR-003).

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

### Step 6: Re-establish Off-Site Rotation Immediately

The disaster that triggered this runbook destroyed **both** `WD-18TB` and `WD-18TB1` — the
off-site rotation that would have protected you was, by definition, not in rotation at the time.
Don't rebuild with only one external drive:

```bash
# Acquire a NEW second external drive
# Adopt it into Urd's identity system
urd drives adopt

# Confirm both drives are tracked with primary/offsite roles in urd.toml, then
# re-establish the physical rotation habit (see "off-site rotation cadence" below)
urd status
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

## Off-Site Backup: What's Actually Implemented

**Physical drive rotation, Urd-tracked (live today):** `WD-18TB1` is registered in
`~/.config/urd/urd.toml` as `role = "offsite"` for every subvolume that also has `WD-18TB` as
`role = "primary"`. Whenever it's connected, the normal `urd-backup.timer` run sends to it same
as the primary — there's no separate manual sync step or script. Its rotation cadence is
*observed*, not configured: Urd derives "how often does this drive come home" from actual connect
history and reports it in `urd status` (`rotation.cadence_secs`, `rotation.forecast_secs`).

This is a **single off-site copy**, not a cloud/friend/bank-vault multi-tier scheme — if `WD-18TB1`
is at the same physical location as the primary system when disaster strikes, it offers no
protection. The rotation only helps if it's actually away from the house when needed.

**Not implemented, and not currently planned:** cloud backup (Backblaze/Wasabi/rclone), a
friend/family drive exchange, or a bank safe-deposit rotation. If off-site protection needs to
survive a *simultaneous* primary + off-site-drive loss (e.g. both were home during the disaster),
one of these remains the real gap — see "Next Steps" below.

**Replaceability, for prioritizing a time-constrained restore:**

| Data | Replaceability | Notes |
|------|----------------|-------|
| Family photos, personal documents | **Irreplaceable** | Restore first |
| Container configs, system configs | Difficult to recreate | Git (`~/containers`) covers most of it independent of Urd |
| Media library, music, multimedia | Mostly replaceable | Re-downloadable, lowest restore priority |

All pool subvolumes receive the same primary+offsite Urd treatment (`urd.toml`'s per-subvolume
`priority` field affects scheduling order, not which drives they're sent to) — there's no
differentiated "critical gets cloud, everything else doesn't" tiering to configure.

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

**As of 2026-07-21 (originally established 2026-01-03, now Urd-tracked since ADR-021):**

**WHAT CAN BE RECOVERED:**
- ✅ Fire/flood/theft at primary location → **Recoverable from `WD-18TB1`, if it was actually
  off-site when the disaster hit**
- ✅ All family photos, personal documents, media library, configurations → protected in the
  same nightly `urd-backup.timer` send as the primary drive, whenever `WD-18TB1` is connected

**REMAINING GAPS:**
- ⚠️ Off-site mirror restore not yet tested (assumes reliability)
- ⚠️ No alerting on rotation drift (drive not coming home on its usual observed cadence) —
  `urd status`/`urd doctor` must be checked manually; nothing pages if the rotation stalls
- ⚠️ Single off-site copy, not a multi-location scheme — see "What's Actually Implemented" above
  for the honest limits of this

## Next Steps: Improve Off-Site Backup

**STATUS:** ✅ Off-site rotation exists and is Urd-tracked (`WD-18TB1`, `role = "offsite"`)

**IMPROVEMENTS TO CONSIDER:**

### Option 1: Verify Off-Site Mirror Restore (RECOMMENDED — still open)

**Priority:** HIGH
**Effort:** 2-3 hours
**Value:** Confirms the off-site drive restores correctly, not just that it receives sends

```bash
# When WD-18TB1 is next connected:
# 1. Test restore from it (same procedure as the WD-18TB test on 2026-01-03)
# 2. Document results in this runbook
# 3. Update "Last Tested" date for off-site restore
```

### Option 2: Rotation Drift Alerting

**Priority:** MEDIUM
**Effort:** 1-2 hours
**Value:** Pages if `WD-18TB1`'s connect cadence drifts well past its observed forecast — sync
frequency and RPO tracking are already solved by Urd's `rotation.cadence_secs`/`forecast_secs`
(see `urd status`); what's missing is turning that into an alert instead of a manual check

### Option 3: Add Cloud Backup (Additional Protection)

**Priority:** LOW (single off-site copy already exists)
**Effort:** 4-6 hours
**Value:** A second, geographically independent off-site copy — protects against the "both drives
were home during the disaster" gap that a single rotation drive can't cover

Not currently planned; would need `rclone` installed and a remote configured from scratch (see
Step 3 above — nothing exists today).

## Related Runbooks

- **DR-001:** System SSD Failure
- **DR-002:** BTRFS Pool Corruption
- **DR-003:** Accidental Deletion

All other runbooks assume backups exist. This runbook exists to scare you into implementing off-site backup.

## Final Warning

**This is the only runbook where recovery may be IMPOSSIBLE.**

Every other disaster has a solution if you have backups.

This disaster has NO SOLUTION if `WD-18TB1` was at the primary location when it happened — a
single-drive rotation only protects against a disaster that catches the rotation drive away.

**Don't let this be the runbook you actually need. Verify the off-site restore, and keep the
rotation drive actually rotating.**

---

**Last Updated:** 2026-07-21 (Rewritten around Urd — ADR-021 superseded the manual Icy Box mirror
process on 2026-03-25; off-site rotation is now tracked automatically via `role = "offsite"`)
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
**Implementation Priority:** ⚠️ Off-site rotation exists but restore is unverified — see "Next Steps"
