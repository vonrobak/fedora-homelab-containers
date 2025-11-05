# Pi-hole Backup and Restore Procedure

**Last Updated:** 2025-11-05
**Purpose:** Complete backup of Pi-hole/Raspberrypi configuration for disaster recovery

## Overview

**Backup Flow:**
1. SSH to pihole → Create local backup archive
2. Transfer backup from pihole → MacBook (intermediate storage)
3. Copy backup from MacBook → Encrypted BTRFS external drive

**Why this approach:**
- Avoids complex remote sudo authentication
- Simpler and more reliable
- Easy to verify each step

---

## Prerequisites

- [ ] MacBook can SSH to pihole with YubiKey
- [ ] Sufficient disk space on pihole (~100MB for backup)
- [ ] Sufficient disk space on MacBook Downloads folder
- [ ] External BTRFS drive available (for final storage)

---

## Step-by-Step Backup Procedure

### Step 1: SSH to pihole

**On MacBook, run:**
```bash
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole
```

Touch your YubiKey when prompted.

---

### Step 2: Create Backup Script on pihole

**On pihole, run:**

```bash
cat > /tmp/backup-local.sh << 'EOF'
#!/bin/bash
# Local backup script - runs on pihole
# Creates backup archive in /tmp

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="pihole-backup-${BACKUP_DATE}"
BACKUP_DIR="/tmp/${BACKUP_NAME}"
BACKUP_ARCHIVE="/tmp/${BACKUP_NAME}.tar.gz"

echo "Creating backup directory..."
mkdir -p "${BACKUP_DIR}"

echo "Backing up Pi-hole configuration..."
sudo cp -r /etc/pihole "${BACKUP_DIR}/"
sudo chown -R $USER:$USER "${BACKUP_DIR}/pihole"

echo "Backing up dnsmasq configuration..."
sudo cp -r /etc/dnsmasq.d "${BACKUP_DIR}/"
sudo chown -R $USER:$USER "${BACKUP_DIR}/dnsmasq.d"

echo "Backing up SSH configuration..."
mkdir -p "${BACKUP_DIR}/ssh"
sudo cp /etc/ssh/sshd_config* "${BACKUP_DIR}/ssh/" 2>/dev/null || true
sudo chown -R $USER:$USER "${BACKUP_DIR}/ssh"

echo "Backing up SSH authorized_keys..."
cp ~/.ssh/authorized_keys "${BACKUP_DIR}/authorized_keys"

echo "Backing up /etc/hosts..."
sudo cp /etc/hosts "${BACKUP_DIR}/hosts"
sudo chown $USER:$USER "${BACKUP_DIR}/hosts"

echo "Backing up network configuration..."
mkdir -p "${BACKUP_DIR}/network"
sudo cp -r /etc/network "${BACKUP_DIR}/network/" 2>/dev/null || true
sudo cp /etc/dhcpcd.conf "${BACKUP_DIR}/network/" 2>/dev/null || true
sudo chown -R $USER:$USER "${BACKUP_DIR}/network"

echo "Saving installed packages list..."
dpkg --get-selections > "${BACKUP_DIR}/installed-packages.txt"

echo "Saving Pi-hole version..."
pihole -v > "${BACKUP_DIR}/pihole-version.txt"

echo "Saving system information..."
cat /etc/os-release > "${BACKUP_DIR}/system-info.txt"
uname -a >> "${BACKUP_DIR}/system-info.txt"

echo "Creating backup manifest..."
cat > "${BACKUP_DIR}/BACKUP_MANIFEST.txt" << MANIFEST
Pi-hole Backup Manifest
========================
Backup Date: ${BACKUP_DATE}
Hostname: $(hostname)
IP Address: $(hostname -I)

Contents:
- pihole/              Pi-hole configuration directory (/etc/pihole)
- dnsmasq.d/          dnsmasq configuration
- ssh/                SSH server configuration
- authorized_keys     SSH public keys
- hosts               /etc/hosts file
- network/            Network configuration files
- installed-packages.txt  List of installed packages
- pihole-version.txt  Pi-hole version information
- system-info.txt     OS and system information
MANIFEST

echo "Compressing backup..."
cd /tmp
tar czf "${BACKUP_ARCHIVE}" "${BACKUP_NAME}"

echo ""
echo "=== Backup Complete ==="
echo "Archive: ${BACKUP_ARCHIVE}"
echo "Size: $(du -sh ${BACKUP_ARCHIVE} | cut -f1)"
echo ""
echo "To transfer to MacBook, run on MacBook:"
echo "  scp -i ~/.ssh/id_ed25519_yk5cnfc pihole:${BACKUP_ARCHIVE} ~/Downloads/"
EOF

chmod +x /tmp/backup-local.sh
```

---

### Step 3: Run the Backup Script

**Still on pihole, run:**
```bash
/tmp/backup-local.sh
```

**Expected output:**
- Progress messages for each backup step
- Final message showing backup location and size
- Command to transfer to MacBook

**Example output:**
```
Creating backup directory...
Backing up Pi-hole configuration...
Backing up dnsmasq configuration...
...
=== Backup Complete ===
Archive: /tmp/pihole-backup-20251105-120000.tar.gz
Size: 6.2M

To transfer to MacBook, run on MacBook:
  scp -i ~/.ssh/id_ed25519_yk5cnfc pihole:/tmp/pihole-backup-20251105-120000.tar.gz ~/Downloads/
```

**Copy the archive filename** from the output (you'll need it in the next step).

---

### Step 4: Transfer Backup to MacBook

**On MacBook (new terminal or after exiting pihole SSH), run:**

```bash
# Replace YYYYMMDD-HHMMSS with actual timestamp from Step 3
scp -i ~/.ssh/id_ed25519_yk5cnfc pihole:/tmp/pihole-backup-YYYYMMDD-HHMMSS.tar.gz ~/Downloads/
```

**Touch YubiKey when prompted.**

**Verify transfer:**
```bash
ls -lh ~/Downloads/pihole-backup-*.tar.gz
```

You should see the backup file with its size.

---

### Step 5: Extract and Verify Backup (Optional but Recommended)

**On MacBook, run:**

```bash
# Create verification directory
mkdir -p ~/Downloads/pihole-backups
cd ~/Downloads/pihole-backups

# Extract backup
tar xzf ~/Downloads/pihole-backup-YYYYMMDD-HHMMSS.tar.gz

# Verify contents
ls -la pihole-backup-YYYYMMDD-HHMMSS/

# View manifest
cat pihole-backup-YYYYMMDD-HHMMSS/BACKUP_MANIFEST.txt
```

**Check that you see:**
- `pihole/` directory
- `dnsmasq.d/` directory
- `ssh/` directory
- `authorized_keys` file
- `hosts` file
- `network/` directory
- `BACKUP_MANIFEST.txt`

---

### Step 6: Copy to External BTRFS Drive

**Mount your external BTRFS backup drive, then on MacBook:**

```bash
# Create backup directory on external drive
mkdir -p /Volumes/YourDriveName/homelab-backups/pihole

# Copy compressed archive
cp ~/Downloads/pihole-backup-YYYYMMDD-HHMMSS.tar.gz \
   /Volumes/YourDriveName/homelab-backups/pihole/

# Also copy extracted backup for easy access
cp -r ~/Downloads/pihole-backups/pihole-backup-YYYYMMDD-HHMMSS \
      /Volumes/YourDriveName/homelab-backups/pihole/

# Create 'latest' symlink
cd /Volumes/YourDriveName/homelab-backups/pihole
rm -f latest
ln -s pihole-backup-YYYYMMDD-HHMMSS latest

# Verify
ls -la /Volumes/YourDriveName/homelab-backups/pihole/
```

---

### Step 7: Cleanup (Optional)

**Clean up temporary files:**

**On pihole (via SSH):**
```bash
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole
rm -rf /tmp/pihole-backup-*
rm /tmp/backup-local.sh
exit
```

**On MacBook (if you want to save space):**
```bash
# Keep only on external drive, remove from MacBook
rm ~/Downloads/pihole-backup-*.tar.gz
rm -rf ~/Downloads/pihole-backups/pihole-backup-*
```

**Or keep on MacBook for redundancy (recommended):**
```bash
# Move to organized location
mkdir -p ~/Documents/Homelab-Backups/pihole
mv ~/Downloads/pihole-backup-*.tar.gz ~/Documents/Homelab-Backups/pihole/
mv ~/Downloads/pihole-backups/pihole-backup-* ~/Documents/Homelab-Backups/pihole/
```

---

## Restoration Procedure

### Prerequisites for Restoration

1. **Fresh Raspberry Pi OS (Debian 12) installed**
2. **Network configured:**
   - Static IP: 192.168.1.69
   - Gateway: Your router
   - DNS: Temporary (use 8.8.8.8 or router)
3. **SSH enabled:**
   - `sudo systemctl enable ssh`
   - `sudo systemctl start ssh`
4. **User 'patriark' created with sudo access**
5. **Basic connectivity verified from MacBook**

---

### Restoration Steps

#### Step 1: Install Pi-hole

**On fresh Raspberrypi, run:**
```bash
curl -sSL https://install.pi-hole.net | bash
```

Follow the interactive installer. Note the web interface password (will be changed later).

---

#### Step 2: Transfer Backup to Pi-hole

**On MacBook, run:**

```bash
# Option A: Transfer from external drive
scp /Volumes/YourDriveName/homelab-backups/pihole/latest/pihole-backup-*.tar.gz \
    patriark@192.168.1.69:/tmp/

# Option B: Transfer from MacBook Documents
scp ~/Documents/Homelab-Backups/pihole/pihole-backup-*.tar.gz \
    patriark@192.168.1.69:/tmp/
```

---

#### Step 3: Extract and Restore

**On Pi-hole (via SSH), run:**

```bash
# Extract backup
cd /tmp
tar xzf pihole-backup-*.tar.gz
cd pihole-backup-*/

# Stop Pi-hole service
sudo systemctl stop pihole-FTL

# Restore Pi-hole configuration
sudo cp -r pihole/* /etc/pihole/
sudo chown -R pihole:pihole /etc/pihole
sudo chmod 664 /etc/pihole/*.list
sudo chmod 664 /etc/pihole/*.db

# Restore dnsmasq configuration
sudo cp -r dnsmasq.d/* /etc/dnsmasq.d/
sudo chown root:root /etc/dnsmasq.d/*

# Restore /etc/hosts
sudo cp hosts /etc/hosts

# Restore SSH configuration
sudo cp ssh/sshd_config /etc/ssh/sshd_config
sudo chmod 600 /etc/ssh/sshd_config

# Restore SSH authorized_keys
mkdir -p ~/.ssh
cp authorized_keys ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# Restore network configuration (if needed)
# sudo cp -r network/network/* /etc/network/
# sudo cp network/dhcpcd.conf /etc/dhcpcd.conf

# Update gravity database
pihole -g

# Start Pi-hole
sudo systemctl start pihole-FTL

# Restart SSH
sudo systemctl restart ssh
```

---

#### Step 4: Verify Restoration

**Check Pi-hole status:**
```bash
pihole status
```

**Test DNS resolution:**
```bash
dig @127.0.0.1 google.com
```

**Access web interface from MacBook browser:**
```
http://192.168.1.69/admin
```

**Test SSH with YubiKey from MacBook:**
```bash
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole hostname
```

Should return `raspberrypi` and require YubiKey touch.

---

#### Step 5: Verify Security Settings

**On pihole, check SSH hardening:**
```bash
sudo sshd -T | grep -E "passwordauthentication|permitrootlogin|pubkeyauthentication|allowusers"
```

**Expected:**
- `passwordauthentication no`
- `permitrootlogin no`
- `pubkeyauthentication yes`
- `allowusers patriark`

---

## Quick Reference

### Create Backup
```bash
# 1. SSH to pihole
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole

# 2. Run one-line backup command
sudo bash -c 'BACKUP_DIR="/tmp/pihole-backup-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP_DIR"; cp -r /etc/pihole "$BACKUP_DIR/"; cp -r /etc/dnsmasq.d "$BACKUP_DIR/"; cp /etc/ssh/sshd_config* "$BACKUP_DIR/" 2>/dev/null; cp ~/.ssh/authorized_keys "$BACKUP_DIR/" 2>/dev/null; cp /etc/hosts "$BACKUP_DIR/"; cd /tmp; tar czf "$BACKUP_DIR.tar.gz" "$(basename $BACKUP_DIR)"; echo "Backup: $BACKUP_DIR.tar.gz"'

# 3. Exit and transfer to MacBook
exit
scp -i ~/.ssh/id_ed25519_yk5cnfc pihole:/tmp/pihole-backup-*.tar.gz ~/Downloads/
```

### Verify Backup
```bash
# Extract and check
tar tzf ~/Downloads/pihole-backup-*.tar.gz | head -20
```

### Automation (Optional)
Add to cron on MacBook to run monthly:
```bash
# Edit crontab
crontab -e

# Add line (runs 1st of each month at 2am)
0 2 1 * * /Users/patriark/fedora-homelab-containers/scripts/backup-pihole.sh /Volumes/BackupDrive
```

---

## Backup Schedule Recommendation

**Frequency:**
- **Weekly**: Quick backup to MacBook
- **Monthly**: Full backup to external BTRFS drive
- **Before major changes**: Always backup first!

**What triggers a backup:**
- Before Pi-hole updates
- After changing DNS settings
- After modifying blocklists
- Before OS updates
- Monthly maintenance window

---

## Troubleshooting

### "Permission denied" during backup
- Run commands with `sudo` where needed
- Check file ownership with `ls -la`

### SCP transfer fails
- Verify YubiKey is inserted
- Check SSH config on MacBook
- Test basic SSH: `ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole hostname`

### Backup file too large
- Gravity database can be large (5-10MB)
- Normal for complete backup: 5-20MB compressed

### Cannot restore SSH access after restore
- Connect via local console (keyboard/monitor)
- Check `/etc/ssh/sshd_config` syntax: `sudo sshd -t`
- Restart SSH: `sudo systemctl restart ssh`
- Check firewall allows port 22

---

## Files Backed Up

### Critical Files
- `/etc/pihole/` - All Pi-hole config and databases
- `/etc/dnsmasq.d/` - DNS server configuration
- `/etc/ssh/sshd_config*` - Hardened SSH configuration
- `~/.ssh/authorized_keys` - YubiKey public keys
- `/etc/hosts` - Local DNS entries

### Important Files
- `/etc/network/` - Network interface config
- `/etc/dhcpcd.conf` - DHCP client config
- Installed packages list
- System information

### Not Backed Up
- Operating system files
- Installed package binaries
- Log files (can be large)
- Pi-hole logs (regenerate automatically)
- Temporary files

---

## Related Documentation

- `ssh-infrastructure-state.md` - SSH configuration details
- `sshd-deployment-procedure.md` - SSH hardening procedure
- Pi-hole official docs: https://docs.pi-hole.net/

---

## Changelog

**2025-11-05:**
- Initial creation
- Step-by-step procedure for backup via SSH session
- Restoration procedure documented
- Quick reference added
