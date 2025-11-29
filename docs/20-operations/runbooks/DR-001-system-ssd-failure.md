# DR-001: System SSD Failure

**Severity:** Critical
**RTO Target:** 4-6 hours
**RPO Target:** Up to 7 days (last weekly backup)
**Last Tested:** Not yet tested
**Success Rate:** Not yet tested in production

---

## Scenario Description

Complete failure of the system NVMe SSD (128GB) that contains:
- Operating system (Fedora 42)
- `/home/patriark` directory
- System configuration files
- Boot loader and kernel

This could result from:
- SSD wear-out (NAND flash exhaustion)
- Controller failure
- Physical damage
- Firmware corruption
- Power surge damage

**Impact:** System cannot boot, all local data inaccessible.

## Prerequisites

- [ ] Replacement SSD available (minimum 128GB NVMe)
- [ ] External backup drive accessible (WD-18TB)
- [ ] Fedora installation media (USB drive)
- [ ] Network connectivity for package installation
- [ ] This runbook accessible (printed or on another device)

## Detection

**How to know this scenario occurred:**

- System fails to boot (stuck at BIOS/UEFI)
- BIOS/UEFI doesn't detect NVMe drive
- Boot error: "No bootable device found"
- SMART errors indicating drive failure
- Sudden system shutdown followed by boot failure

**Verification steps:**
```bash
# From BIOS/UEFI
# Check if NVMe drive appears in boot device list
# If not visible → hardware failure

# From Fedora live USB
lsblk  # Check if NVMe drive is detected
sudo smartctl -a /dev/nvme0n1  # Check SMART status (if readable)
```

## Impact Assessment

**What's affected:**
- **Total system unavailability** - cannot boot
- Home directory data (`/home/patriark`)
- System configuration (`/etc/*`)
- Installed packages and applications
- Boot configuration

**What still works:**
- External backup drive (contains all critical data)
- BTRFS pool (if separate drives) - media/data intact
- Network services (if BTRFS pool separate)

**Data loss risk:**
- Last 7 days of home directory changes (since last weekly backup)
- System packages installed in last 30 days (monthly root backup)
- Any data not backed up to external drive

## Recovery Procedure

### Step 1: Prepare Recovery Environment

**Install replacement SSD:**
1. Power off system completely
2. Open case, install new NVMe SSD
3. Close case, boot to BIOS/UEFI
4. Verify new SSD detected in BIOS

**Boot from Fedora installation media:**
1. Insert Fedora USB installer
2. Boot from USB (F12 or BIOS boot menu)
3. Select "Test this media & start Fedora"
4. Wait for live environment to load

### Step 2: Install Fresh Fedora System

**Run Fedora installer:**
```bash
# From live environment
sudo anaconda

# Installation options:
# - Language: English (or preferred)
# - Keyboard: Norwegian/US (or preferred)
# - Timezone: Europe/Oslo (or preferred)
# - Disk: Select new NVMe SSD
# - Partitioning: Automatic (or manual if specific layout needed)
# - User: Create user "patriark" with sudo privileges
# - Hostname: fedora-htpc
```

**Installation settings:**
- **Partitioning:** Automatic (creates EFI + root BTRFS)
- **Software:** Minimal install (add packages later from backup)
- **User account:** Same username as backup (`patriark`)

**Complete installation:**
- Click "Begin Installation"
- Wait for installation (15-20 minutes)
- Reboot when prompted
- Remove installation media

### Step 3: Mount External Backup Drive

**Connect and unlock external drive:**
```bash
# List available drives
lsblk

# Unlock LUKS encrypted drive (should be /dev/sdX)
sudo cryptsetup open /dev/sdX WD-18TB

# Create mount point
sudo mkdir -p /mnt/external

# Mount drive
sudo mount /dev/mapper/WD-18TB /mnt/external

# Verify mount
ls -lh /mnt/external/.snapshots/
```

### Step 4: Restore Home Directory

**Find latest home backup:**
```bash
# List available home snapshots
ls -lt /mnt/external/.snapshots/htpc-home/

# Identify latest snapshot
LATEST_HOME=$(ls -t /mnt/external/.snapshots/htpc-home/ | head -1)
echo "Restoring from: $LATEST_HOME"
```

**Restore home directory:**
```bash
# Backup current (empty) home directory
sudo mv /home/patriark /home/patriark.orig

# Restore home from snapshot
sudo cp -a /mnt/external/.snapshots/htpc-home/$LATEST_HOME /home/patriark

# Fix ownership (installer may have created with different UID)
sudo chown -R patriark:patriark /home/patriark

# Verify restoration
ls -la /home/patriark/
```

**Restore SSH keys and GPG keys:**
```bash
# SSH keys should be restored automatically
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub

# Test SSH key
ssh-add -l

# GPG keys (if backed up)
gpg --list-secret-keys
```

### Step 5: Restore System Configuration

**Option A: Selective restoration (recommended)**

Restore only essential system configs:
```bash
# Find latest root snapshot
LATEST_ROOT=$(ls -t /mnt/external/.snapshots/htpc-root/ | head -1)

# Restore specific configs
sudo cp -a /mnt/external/.snapshots/htpc-root/$LATEST_ROOT/etc/fstab /etc/fstab.backup
sudo cp -a /mnt/external/.snapshots/htpc-root/$LATEST_ROOT/etc/hostname /etc/hostname
sudo cp -a /mnt/external/.snapshots/htpc-root/$LATEST_ROOT/etc/hosts /etc/hosts

# Review before applying
diff /etc/fstab /etc/fstab.backup

# Restore systemd units (if customized)
sudo cp -a /mnt/external/.snapshots/htpc-root/$LATEST_ROOT/etc/systemd/system/* \
         /etc/systemd/system/
```

**Option B: Full root restore (advanced)**

Only if you need complete system state:
```bash
# THIS IS DANGEROUS - only for advanced recovery
# Creates full BTRFS restore of root filesystem
# NOT RECOMMENDED for most scenarios
```

### Step 6: Restore Container Configuration

**Mount BTRFS pool (if separate drives):**
```bash
# Check if BTRFS pool is intact
lsblk
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Verify containers data
ls -lh /mnt/btrfs-pool/subvol7-containers/
```

**If BTRFS pool is intact:**
```bash
# Containers config is already on BTRFS pool
# Just need to restore ~/containers symlinks/references

cd ~
git clone https://github.com/vonrobak/fedora-homelab-containers.git containers
cd containers

# Verify config points to BTRFS pool
ls -lh config/
```

**If BTRFS pool is NOT intact:**
```bash
# Restore containers from external backup
LATEST_CONTAINERS=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)

sudo mkdir -p /mnt/btrfs-pool/subvol7-containers
sudo cp -a /mnt/external/.snapshots/subvol7-containers/$LATEST_CONTAINERS/* \
         /mnt/btrfs-pool/subvol7-containers/
```

### Step 7: Reinstall Essential Packages

**Restore from package list (if backed up):**
```bash
# If you backed up package list
# sudo dnf install $(cat ~/package-list.txt)

# Or install essential packages manually
sudo dnf install -y \
    podman \
    git \
    vim \
    htop \
    tmux \
    btrfs-progs \
    cryptsetup
```

**Enable Podman for rootless:**
```bash
systemctl --user enable podman.socket
loginctl enable-linger patriark
```

### Step 8: Restore Services

**Restore systemd user services:**
```bash
# Copy quadlet files
mkdir -p ~/.config/containers/systemd/
cp -a /mnt/external/.snapshots/htpc-home/$LATEST_HOME/.config/containers/systemd/* \
      ~/.config/containers/systemd/

# Reload systemd
systemctl --user daemon-reload

# List services
systemctl --user list-unit-files | grep container

# Start critical services
systemctl --user start traefik.service
systemctl --user start prometheus.service
systemctl --user start grafana.service
```

**Verify services running:**
```bash
podman ps
systemctl --user status traefik.service
```

### Step 9: Verify System Health

**Check all critical systems:**
```bash
# Home directory
ls -la ~/

# BTRFS pool
df -h /mnt/btrfs-pool/

# Containers
podman ps --all

# Services
systemctl --user list-units --type=service --state=running

# Network
ip addr
ping -c 3 8.8.8.8

# DNS
nslookup google.com
```

**Run diagnostics:**
```bash
~/containers/scripts/homelab-intel.sh
```

### Step 10: Restore Backup Automation

**Re-enable backup timers:**
```bash
# Enable backup timers
systemctl --user enable --now btrfs-snapshot-backup@tier1-daily.timer
systemctl --user enable --now btrfs-snapshot-backup@tier1-weekly.timer

# Enable restore test timer
systemctl --user enable --now backup-restore-test.timer

# Verify timers
systemctl --user list-timers
```

## Verification Checklist

- [ ] System boots successfully from new SSD
- [ ] Home directory fully restored and accessible
- [ ] SSH keys working (can authenticate to GitHub)
- [ ] BTRFS pool mounted and accessible
- [ ] All containers running
- [ ] Critical services operational (Traefik, Prometheus, Grafana)
- [ ] Network connectivity working
- [ ] Can access web services (Jellyfin, Grafana, etc.)
- [ ] Backup automation re-enabled and scheduled
- [ ] Git repository cloned and accessible

## Post-Recovery Actions

- [ ] **Immediate:**
  - Run full backup to external drive
  - Verify all services accessible externally
  - Test key workflows (media playback, monitoring, etc.)
  - Document recovery process and time taken

- [ ] **Within 24 hours:**
  - Review what data was lost (7 days of changes)
  - Update this runbook with actual recovery experience
  - Implement improvements to reduce RPO if needed
  - Test restored system under normal load

- [ ] **Within 1 week:**
  - Root cause analysis (why did SSD fail?)
  - Consider preventive measures (SMART monitoring, alerts)
  - Evaluate if more frequent backups needed
  - Update system inventory and documentation

## Rollback Plan

If recovery fails or critical issues found:

1. **Boot back to live USB**
2. **Preserve any recovered data:**
   ```bash
   sudo mount /dev/nvme0n1p3 /mnt/newroot
   sudo tar czf /mnt/external/recovery-attempt-$(date +%Y%m%d).tar.gz /mnt/newroot
   ```
3. **Try alternative approach:**
   - Different snapshot date
   - Manual file-by-file restoration
   - Fresh install with manual config

## Estimated Timeline

- **SSD replacement:** 15-30 minutes
- **Fresh OS install:** 20-30 minutes
- **Home directory restore:** 15-30 minutes (depends on size)
- **System configuration:** 30-60 minutes
- **Container restoration:** 15-30 minutes
- **Service verification:** 15-30 minutes
- **Testing and validation:** 30-60 minutes
- **Total RTO:** **4-6 hours**

## Data Loss Window

**Expected data loss:**
- Home directory: Last 7 days (since last weekly backup)
- System packages: Last 30 days (since last monthly root backup)
- Containers config: Last 7 days (if not on separate BTRFS pool)

**Minimizing data loss:**
- Restore from most recent daily snapshot (if available locally)
- Check if BTRFS pool survived (contains most critical data)
- Review Git commit history for config changes

## Prevention Measures

### SMART Monitoring

**Install smartmontools:**
```bash
sudo dnf install smartmontools
```

**Check SSD health regularly:**
```bash
# Add to cron or systemd timer
sudo smartctl -a /dev/nvme0n1 | grep -E 'Power_On_Hours|Wear_Leveling|Temperature'
```

**Set up alerts for SSD issues:**
```bash
# Monitor SMART attributes
# Alert when wear exceeds 80%
# Alert on temperature spikes
# Alert on reallocated sectors
```

### Increase Backup Frequency

**For critical data, move to daily external backups:**
```bash
# Modify backup script to run daily for Tier 1
# Reduces RPO from 7 days to 1 day
```

### System Package List Backup

**Save installed packages:**
```bash
# Add to backup script
dnf list installed > ~/package-list.txt

# Backup to external drive
cp ~/package-list.txt /mnt/external/package-list-$(date +%Y%m%d).txt
```

### Configuration Snapshot Before Changes

**Before major system changes:**
```bash
# Create manual snapshot
sudo btrfs subvolume snapshot / /.snapshots/pre-update-$(date +%Y%m%d)
```

## Related Runbooks

- **DR-002:** BTRFS Pool Corruption (if BTRFS pool also failed)
- **DR-003:** Accidental Deletion (for recovering specific files)
- **DR-004:** Total Catastrophe (if backup drive also lost)

## Quick Reference Commands

```bash
# Boot from Fedora live USB
# Install OS → Create user → Reboot

# Mount external backup
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# Find latest snapshots
ls -t /mnt/external/.snapshots/htpc-home/ | head -1
ls -t /mnt/external/.snapshots/htpc-root/ | head -1

# Restore home directory
sudo cp -a /mnt/external/.snapshots/htpc-home/LATEST /home/patriark
sudo chown -R patriark:patriark /home/patriark

# Mount BTRFS pool
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Restore containers
git clone https://github.com/vonrobak/fedora-homelab-containers.git ~/containers

# Start services
systemctl --user daemon-reload
systemctl --user start traefik.service

# Verify
podman ps
~/containers/scripts/homelab-intel.sh
```

---

**Last Updated:** 2025-11-30
**Maintainer:** Homelab Operations
**Review Schedule:** Quarterly
**Next Test:** Q1 2026 (simulated recovery on spare hardware)
