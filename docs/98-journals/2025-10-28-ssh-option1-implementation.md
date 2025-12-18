# SSH Hardening - Option 1 Implementation Guide

**Date**: 2025-11-04
**System**: fedora-htpc.lokal (192.168.1.70)
**Objective**: Clean up SSH keys, add IP restrictions, improve security with DNS-aware architecture

---

## Network Architecture Overview

### Static Infrastructure (Pi-hole DNS)
```
raspberrypi.lokal  → 192.168.1.69  (Pi-hole DNS server)
fedora-htpc.lokal  → 192.168.1.70  (This machine - SSH server)
fedora-jern.lokal  → 192.168.1.71  (Workstation - SSH client)
```

### DHCP Devices (UniFi U7 Pro AP)
```
MacBook Air        → 192.168.1.34  (Currently DHCP)
Other Apple devices → DHCP pool
```

### Recommendation: Static DHCP Reservation for MacBook Air
**Why**:
- Prevents IP changes that break SSH restrictions
- Makes security rules predictable
- Allows DNS entry: `macbook.lokal → 192.168.1.34`

**How**: Configure in UniFi Controller or Pi-hole DHCP settings

---

## Current Key Analysis

### Identified Keys (8 total)
```
Line  Fingerprint (last 10 chars)    Source Device           Status
────  ──────────────────────────────  ──────────────────────  ─────────────
1     ...HXwAPjJ++a9qA                patriark-MB.local       ✅ ACTIVE (Nov 4)
2     ...a6VsZQtc5b8                  patriark-MB.local       ❓ Unknown
3     ...3RDuXCWRbOPE                 patriark-MB.local       ❓ Unknown
4     ...iaHjBmbmLm8                  fedorajern              ❓ Unknown
5     ...Wtmi13cJ0mg                  fedorajern              ❓ Unknown
6     ...EZiX0PZnGFU                  fedorajern              ❓ Unknown
7     ...+DnDXdHlU18                  MacBookAir              ❓ Unknown
8     ...h8yjfaCiZ2ODOanxpp4         MacBookAir (yk5cnfc)    ✅ ACTIVE (Nov 4)
```

**Actively used keys** (from sshd logs):
- Key 1: Used multiple times on Nov 3-4 from 192.168.1.34
- Key 8: Used on Nov 4 from 192.168.1.34

### Hypothesis
You have 3 Yubikeys and generated keys from multiple devices:
- **Yubikey #1** (Serial 16173971 - currently inserted): Likely Key 8 (yk5cnfc label)
- **Yubikey #2**: Unknown which keys
- **Yubikey #3**: Unknown which keys

The multiple keys suggest you registered each Yubikey from multiple machines, creating redundancy.

---

## Decision Point: Which Keys to Keep?

### Option A: Keep Only Currently Active Keys (Simplest)
**Pros**: Minimal disruption, known working keys
**Cons**: Loses backup Yubikeys if only 2 keys kept

**Recommended for**: Quick implementation, test other Yubikeys separately

### Option B: Identify All 3 Yubikeys First (Thorough)
**Pros**: Ensures all 3 Yubikeys work, proper backup strategy
**Cons**: Requires testing with all 3 Yubikeys, takes more time

**Recommended for**: Complete security setup

---

## Implementation Plan - Option A (Quick & Safe)

We'll keep the 2 actively working keys plus identify one more from your other Yubikeys.

### Step 1: Backup Everything

```bash
# Create backup directory
mkdir -p ~/.ssh/backups/20251104-option1

# Backup authorized_keys
cp ~/.ssh/authorized_keys ~/.ssh/backups/20251104-option1/authorized_keys.backup
chmod 600 ~/.ssh/backups/20251104-option1/authorized_keys.backup

# Backup any existing SSH config
[ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/backups/20251104-option1/config.backup

# Verify backup
ls -la ~/.ssh/backups/20251104-option1/
cat ~/.ssh/backups/20251104-option1/authorized_keys.backup | wc -l  # Should show 8
```

### Step 2: Identify Your Yubikeys

**Currently inserted**: Yubikey Serial 16173971

Let's test which key this Yubikey uses:

```bash
# Test SSH with current Yubikey to localhost
# This will show which key gets used
ssh -v patriark@localhost 2>&1 | grep "Offering public key" | tail -1

# Or test to MacBook if accessible:
ssh -v patriark@192.168.1.34 2>&1 | grep "Offering public key"
```

**Action needed**: Test with your other 2 Yubikeys:
1. Remove current Yubikey
2. Insert Yubikey #2
3. Try SSH to fedora-htpc: `ssh patriark@192.168.1.70`
4. Note if it works and which key fingerprint is used
5. Repeat with Yubikey #3

### Step 3: Create Clean authorized_keys

Based on actively used keys, here's the new file:

```bash
# Create new authorized_keys with IP restrictions and DNS-aware comments
cat > ~/.ssh/authorized_keys.new << 'EOF'
# ═══════════════════════════════════════════════════════════════
# SSH Authorized Keys - fedora-htpc.lokal
# Last Updated: 2025-11-04
# ═══════════════════════════════════════════════════════════════
#
# Security Policy:
# - Hardware keys only (FIDO2/U2F)
# - IP restrictions enforced
# - Physical touch required for authentication
#
# Trusted Networks:
#   192.168.1.0/24 - Main LAN (UniFi, fedora-htpc, Pi-hole)
#   192.168.1.34   - macbook.lokal (DHCP, needs static reservation)
#   192.168.1.70   - fedora-htpc.lokal (this machine, for local scripts)
#   192.168.1.71   - fedora-jern.lokal (workstation)
# ═══════════════════════════════════════════════════════════════

# Yubikey #1 - Serial 16173971 (Primary - 5 NFC, Blue/Black keychain)
# Generated: 2023-12-17 from MacBook Air
# Last used: 2025-11-04 from 192.168.1.34
from="192.168.1.0/24" sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIFbVTBtfbZqUFxtnDmYNDdCMv5/60w0NikxBzH64GktuAAAABHNzaDo= yubikey-16173971-primary

# Yubikey #2 - Serial UNKNOWN (Backup #1)
# Generated: Unknown from patriark-MB.local
# Last used: 2025-11-04 from 192.168.1.34
from="192.168.1.0/24" sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIIUpnq5DXV+p64yIie+PuDg+I+D+1ypfjsTzbyAX65CiAAAABHNzaDo= yubikey-backup1

# Yubikey #3 - Serial UNKNOWN (Backup #2 - PLACEHOLDER)
# TODO: Test with physical Yubikey and replace with actual working key
# One of the fedorajern keys (lines 4-6 from backup)
from="192.168.1.0/24" sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDoTl+B+l8I92cDxP8ty0evHfTISJW4vood9RDW3yvuWAAAABHNzaDo= yubikey-backup2-placeholder

EOF

# Set correct permissions
chmod 600 ~/.ssh/authorized_keys.new

# Review the new file
cat ~/.ssh/authorized_keys.new
```

**Network restriction explanation**:
- `from="192.168.1.0/24"` - Allows entire LAN subnet
  - Includes: fedora-htpc, fedora-jern, macbook, Pi-hole
  - Rejects: Any connection from outside your LAN
  - More flexible than individual IPs for DHCP devices

**Alternative** (if you want stricter control):
```bash
from="192.168.1.34,192.168.1.70,192.168.1.71"
```
This only allows specific IPs but requires static IP for MacBook Air.

### Step 4: Test BEFORE Activating

**CRITICAL**: Test new config in a safe way

```bash
# Method 1: Test with sshd in debug mode (requires another terminal)
# Terminal 1 (keep your current session open!):
SUDO_ASKPASS=/tmp/askpass.sh sudo -A /usr/sbin/sshd -t -f /etc/ssh/sshd_config \
  -o AuthorizedKeysFile=$HOME/.ssh/authorized_keys.new

# If validation passes, continue to Method 2

# Method 2: Atomic swap with instant rollback capability
# Open a NEW terminal on fedora-htpc (local, not SSH)
# Then from MacBook Air, test:

# On fedora-htpc:
mv ~/.ssh/authorized_keys ~/.ssh/authorized_keys.old
mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys

# IMMEDIATELY test from MacBook Air:
# From MacBook: ssh patriark@fedora-htpc.lokal

# If it works: SUCCESS!
# If it fails: Rollback immediately:
mv ~/.ssh/authorized_keys.old ~/.ssh/authorized_keys
```

**Safety net**: Set up auto-rollback timer (optional)
```bash
# This will automatically restore old keys after 5 minutes if you don't cancel
(sleep 300; mv ~/.ssh/authorized_keys.old ~/.ssh/authorized_keys 2>/dev/null) &
ROLLBACK_PID=$!
echo "Auto-rollback PID: $ROLLBACK_PID"
echo "Cancel with: kill $ROLLBACK_PID"

# After successful test:
kill $ROLLBACK_PID  # Cancel auto-rollback
```

### Step 5: Create SSH Client Configuration

Create `.ssh/config` with DNS names:

```bash
cat > ~/.ssh/config << 'EOF'
# ═══════════════════════════════════════════════════════════════
# SSH Client Configuration - Uses Pi-hole DNS (.lokal domains)
# ═══════════════════════════════════════════════════════════════

# Global defaults for all connections
Host *
    # Security
    IdentitiesOnly yes
    HashKnownHosts yes
    StrictHostKeyChecking ask
    VerifyHostKeyDNS yes

    # Use FIDO2 keys only
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentityFile ~/.ssh/id_ecdsa_sk

    # Performance and reliability
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
    TCPKeepAlive yes

    # Disable vulnerable features by default
    ForwardAgent no
    ForwardX11 no

    # Use Pi-hole DNS for .lokal domains
    CanonicalizeHostname yes
    CanonicalDomains lokal
    CanonicalizeFallbackLocal yes

# ═══════════════════════════════════════════════════════════════
# Homelab Infrastructure
# ═══════════════════════════════════════════════════════════════

# Pi-hole DNS Server
Host pihole raspberrypi
    HostName raspberrypi.lokal
    User pi
    # Enable X11 for admin GUI if needed
    ForwardX11 yes
    ForwardX11Trusted yes

# This machine (fedora-htpc) - for local scripts/testing
Host htpc fedora-htpc localhost
    HostName fedora-htpc.lokal
    User patriark
    # Allow X11 for local GUI apps
    ForwardX11 yes
    ForwardX11Trusted yes

# Workstation
Host jern fedora-jern workstation
    HostName fedora-jern.lokal
    User patriark
    ForwardX11 yes
    ForwardX11Trusted yes

# ═══════════════════════════════════════════════════════════════
# Apple Ecosystem (DHCP devices)
# ═══════════════════════════════════════════════════════════════

# MacBook Air - Primary mobile device
# NOTE: Uses DHCP, consider static reservation at 192.168.1.34
Host macbook mac macbook-air
    HostName 192.168.1.34
    # Or use: HostName macbook.lokal (if DNS entry created)
    User patriark
    ForwardX11 yes

# ═══════════════════════════════════════════════════════════════
# Connection Patterns
# ═══════════════════════════════════════════════════════════════

# Pattern: All .lokal domains (homelab)
Host *.lokal
    User patriark
    # Faster authentication for internal network
    GSSAPIAuthentication no

# Pattern: All 192.168.1.* addresses
Host 192.168.1.*
    User patriark
    GSSAPIAuthentication no

EOF

chmod 600 ~/.ssh/config

# Test DNS resolution
echo "Testing DNS resolution..."
host fedora-htpc.lokal
host fedora-jern.lokal
host raspberrypi.lokal

# Test SSH config
echo "Testing SSH config parsing..."
ssh -G htpc | grep -E "^hostname|^user|^forward"
ssh -G jern | grep -E "^hostname|^user"
ssh -G macbook | grep -E "^hostname|^user"
```

### Step 6: Handle Private Key Files

You have private key files on disk that shouldn't be needed with FIDO2 resident keys:

```bash
# List private keys
ls -la ~/.ssh/htpcpihole-ed25519*

# Compare with one of your authorized keys
echo "=== Private key fingerprint ==="
ssh-keygen -lf ~/.ssh/htpcpihole-ed25519.pub

echo "=== Checking if this key is in authorized_keys ==="
grep -f <(cat ~/.ssh/htpcpihole-ed25519.pub | awk '{print $2}') ~/.ssh/authorized_keys

# If the key IS in authorized_keys, it might be needed
# If NOT, it's safe to archive

# Archive (don't delete yet, just move to backup)
mkdir -p ~/.ssh/archived-keys
mv ~/.ssh/htpcpihole-ed25519* ~/.ssh/archived-keys/

# Test SSH still works
ssh patriark@localhost

# If SSH works, keys were resident on Yubikey (good!)
# If SSH fails, restore from ~/.ssh/archived-keys/
```

### Step 7: Verify and Test

**Test matrix**:

```bash
# Test 1: Local connection
ssh patriark@localhost
# Expected: Should work with Yubikey touch

# Test 2: Using DNS name
ssh htpc
# Expected: Should work (uses fedora-htpc.lokal)

# Test 3: Using short name
ssh jern
# Expected: Should resolve to fedora-jern.lokal (if accessible)

# Test 4: From MacBook Air to fedora-htpc
# On MacBook Air:
ssh htpc
# Expected: Should work with Yubikey touch

# Test 5: IP restriction (simulate unauthorized IP)
# Temporarily add a test key with wrong IP:
echo 'from="10.0.0.1" sk-ssh-ed25519@openssh.com AAAA...(test key)... test' >> ~/.ssh/authorized_keys
# Try to connect - should reject
# Then remove test line

# Test 6: Check logs
journalctl -u sshd -n 20 --no-pager
# Look for "Accepted publickey" messages
```

### Step 8: Create Yubikey Inventory Documentation

```bash
cat > ~/containers/docs/30-security/YUBIKEY-INVENTORY.md << 'EOF'
# Yubikey Inventory - fedora-htpc.lokal

**Last Updated**: 2025-11-04
**Owner**: patriark

---

## Yubikey #1 - PRIMARY

### Hardware Details
- **Serial Number**: 16173971
- **Model**: YubiKey 5 NFC
- **Form Factor**: Keychain (USB-A)
- **Firmware**: 5.4.3
- **Color/Identifier**: [Blue/Black - describe your key]
- **Purchase Date**: [YYYY-MM-DD]

### Location & Usage
- **Primary Location**: Daily keyring
- **Usage**: Primary authentication for all systems
- **Last Tested**: 2025-11-04

### SSH Public Key
```
sk-ssh-ed25519@openssh.com AAAAGnNr...GktuAAAABHNzaDo= yubikey-16173971-primary
Fingerprint: SHA256:ZZQ6vvqOPtQy12Zpg0xtmp74h8yjfaCiZ2ODOanxpp4
```

### Enabled Applications
- ✅ FIDO U2F
- ✅ FIDO2
- ✅ Yubico OTP
- ✅ OATH (TOTP)
- ✅ PIV
- ✅ OpenPGP
- ✅ NFC (all applications)

---

## Yubikey #2 - BACKUP #1

### Hardware Details
- **Serial Number**: [UNKNOWN - insert and run `ykman info`]
- **Model**: YubiKey 5 [?]
- **Form Factor**: [Nano/Keychain/etc]
- **Firmware**: [?.?.?]
- **Color/Identifier**: [Describe to differentiate from #1]
- **Purchase Date**: [YYYY-MM-DD]

### Location & Usage
- **Primary Location**: [Home safe / Backup location]
- **Usage**: Backup authentication
- **Last Tested**: [YYYY-MM-DD - TEST THIS!]

### SSH Public Key
```
sk-ssh-ed25519@openssh.com AAAAGnNr...65CiAAAABHNzaDo= yubikey-backup1
Fingerprint: SHA256:JCw016Q9070cP9f5a1ejo388kwp3t8HXwAPjJ++a9qA
```

### Enabled Applications
- [Run `ykman info` to document]

---

## Yubikey #3 - BACKUP #2 / EMERGENCY

### Hardware Details
- **Serial Number**: [UNKNOWN - insert and run `ykman info`]
- **Model**: YubiKey 5 [?]
- **Form Factor**: [Nano/Keychain/etc]
- **Firmware**: [?.?.?]
- **Color/Identifier**: [Describe to differentiate]
- **Purchase Date**: [YYYY-MM-DD]

### Location & Usage
- **Primary Location**: [Off-site backup / Family member / Safety deposit box]
- **Usage**: Emergency access only
- **Last Tested**: [YYYY-MM-DD - TEST THIS!]

### SSH Public Key
```
[TO BE DETERMINED - Test with this Yubikey]
Fingerprint: [TBD]
```

### Enabled Applications
- [Run `ykman info` to document]

---

## Testing Schedule

### Quarterly Tests (Every 3 months)
- [ ] Q1 2025: Test all 3 Yubikeys can SSH to fedora-htpc
- [ ] Q2 2025: Test all 3 Yubikeys + verify backup locations
- [ ] Q3 2025: Test all 3 Yubikeys + update firmware if needed
- [ ] Q4 2025: Test all 3 Yubikeys + review access logs

### Actions if Yubikey Lost/Stolen
1. Immediately remove corresponding line from `~/.ssh/authorized_keys`
2. Verify no unauthorized access: `journalctl -u sshd --since "7 days ago" | grep "Accepted publickey"`
3. Order replacement Yubikey
4. Generate new key from replacement and add to `authorized_keys`
5. Update this inventory

### Actions if All Yubikeys Lost (Emergency)
1. Physical access to machine required
2. Generate new non-resident SSH key pair temporarily
3. Order 3 new Yubikeys
4. Set up new FIDO2 resident keys
5. Remove temporary keys

---

## SSH Configuration Summary

**Authorized Keys Location**: `~/.ssh/authorized_keys`
**Current Key Count**: 3 (one per Yubikey)
**IP Restrictions**: `from="192.168.1.0/24"`
**Trusted Networks**: Home LAN only (fedora-htpc, fedora-jern, macbook, Pi-hole)

**Authentication Requirements**:
- ✅ Hardware security key (Yubikey)
- ✅ Physical touch required
- ✅ Connection from trusted network IP
- ✅ Valid SSH protocol negotiation

---

## Reference Commands

```bash
# Check which Yubikey is inserted
ykman info

# List Yubikey serial numbers (if multiple readers)
ykman list --serials

# Extract resident keys from Yubikey
ssh-keygen -K

# Test SSH with specific Yubikey
ssh -v patriark@fedora-htpc.lokal 2>&1 | grep "Offering public key"

# View recent SSH authentications
journalctl -u sshd -n 50 | grep "Accepted publickey"

# Check authorized_keys
cat ~/.ssh/authorized_keys

# View SSH config
cat ~/.ssh/config

# Test SSH config for host
ssh -G htpc
```

---

## Related Documentation

- `~/containers/docs/30-security/SSH-HARDENING-ANALYSIS.md` - Full security analysis
- `~/containers/docs/30-security/OPTION1-IMPLEMENTATION-GUIDE.md` - This implementation
- `~/.ssh/backups/20251104-option1/` - Backup of original configuration

EOF

# Open for editing to fill in your Yubikey details
echo "Created Yubikey inventory template. Edit with your details:"
echo "vim ~/containers/docs/30-security/YUBIKEY-INVENTORY.md"
```

---

## Rollback Procedure

If anything goes wrong:

```bash
# Restore original authorized_keys
cp ~/.ssh/backups/20251104-option1/authorized_keys.backup ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Test immediately
ssh patriark@localhost

# Verify
diff ~/.ssh/authorized_keys ~/.ssh/backups/20251104-option1/authorized_keys.backup
# Should show no differences

# Check SSH works
journalctl -u sshd -n 10
```

---

## Post-Implementation Tasks

### Immediate (Today)
- [ ] Backup completed
- [ ] New authorized_keys tested and activated
- [ ] SSH config created
- [ ] Private key files archived
- [ ] Verified SSH works from MacBook Air
- [ ] Verified SSH works locally

### This Week
- [ ] Test with all 3 Yubikeys to identify them
- [ ] Update Yubikey inventory with serial numbers
- [ ] Consider static DHCP reservation for MacBook Air
- [ ] Add DNS entry for macbook.lokal in Pi-hole (optional)

### This Month
- [ ] Test emergency access from fedora-jern
- [ ] Verify IP restrictions work (test from different network)
- [ ] Set up quarterly Yubikey test calendar reminders
- [ ] Consider implementing Option 2 (fail2ban, Match blocks)

---

## Network Improvement Recommendations

### Priority 1: Static DHCP for MacBook Air
**Current**: DHCP lease at 192.168.1.34
**Recommended**: DHCP reservation at 192.168.1.34

**Steps** (in UniFi Controller or Pi-hole):
1. Note MacBook Air MAC address: `arp -a | grep 192.168.1.34`
2. In Pi-hole (if it's your DHCP server):
   - Go to Settings → DHCP
   - Add static lease: MAC → 192.168.1.34
3. Or in UniFi Controller:
   - Devices → MacBook Air → Config → Fixed IP: 192.168.1.34

### Priority 2: DNS Entry for MacBook Air
Add to Pi-hole local DNS:
```
192.168.1.34    macbook.lokal
192.168.1.34    macbook-air.lokal
```

Then update SSH config to use DNS name:
```
Host macbook mac
    HostName macbook.lokal  # Instead of IP
```

### Priority 3: Document Other Apple Devices
If you have iPhone, iPad, etc. accessing SSH, consider:
- Static DHCP reservations
- DNS entries (iphone.lokal, ipad.lokal, etc.)
- Separate authorized_keys entries if they need different access patterns

---

## Success Criteria

✅ **Implementation successful if**:
1. Can SSH from MacBook Air to fedora-htpc with Yubikey touch
2. Can SSH locally with Yubikey touch
3. Authorized keys reduced from 8 to 3
4. IP restrictions prevent access from outside 192.168.1.0/24
5. SSH config provides convenient short names (htpc, jern, etc.)
6. All 3 Yubikeys identified and documented
7. Backup files preserved for emergency rollback

---

## Next Steps After Success

1. **Monitor for a week**: Check `journalctl -u sshd` daily
2. **Test all 3 Yubikeys**: Ensure each one works
3. **Update CLAUDE.md**: Document the new SSH setup
4. **Consider Option 2**: Add fail2ban, Match blocks, enhanced logging
5. **Share with family**: If someone holds backup Yubikey, teach them emergency access

---

**Ready to proceed? Follow steps 1-8 in order. Test at each stage!**
