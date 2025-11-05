# SSH Infrastructure State - Homelab Network

**Last Updated:** 2025-11-05
**Status:** Operational with YubiKey FIDO2 authentication across all systems

## Current Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────┐
│              MacBook Air (macOS 25.0.0)                 │
│  Primary: yk5cnfc | Backup: yk5clgtn, yk5nfc            │
│  SSH Keys: id_ed25519_yk5cnfc, id_ed25519_yk5clgtn,     │
│            id_ed25519_sk (yk5nfc)                       │
├─────────────────────────────────────────────────────────┤
│  SSH Access:                                            │
│    → pihole (192.168.1.69)       [3 YubiKey keys]      │
│    → fedora-htpc (192.168.1.70)  [3 YubiKey keys]      │
│    → fedora-jern (192.168.1.71)  [3 YubiKey keys]      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│          fedora-jern (Fedora 43 - Control Center)       │
│  Primary: yk5nfc | Backup: yk5cnfc, yk5clgtn            │
│  SSH Keys: fedora-jern-yk5nfc, fedora-jern-yk5cnfc,     │
│            fedora-jern-yk5clgtn                         │
│  Features: Encrypted storage, hardware-backed auth      │
├─────────────────────────────────────────────────────────┤
│  SSH Access:                                            │
│    → pihole (192.168.1.69)       [3 YubiKey keys]      │
│    → fedora-htpc (192.168.1.70)  [3 YubiKey keys]      │
└─────────────────────────────────────────────────────────┘
        ↓                              ↓
┌─────────────────┐          ┌────────────────────┐
│ pihole          │          │ fedora-htpc        │
│ 192.168.1.69    │          │ 192.168.1.70       │
│ (Raspberry Pi)  │          │ (Fedora 43)        │
│                 │          │                    │
│ Authorized:     │          │ Authorized:        │
│ - 3 MacBook keys│          │ - 3 MacBook keys   │
│ - 3 jern keys   │          │ - 3 jern keys      │
└─────────────────┘          └────────────────────┘
```

### YubiKey Distribution Strategy

**MacBook Air (Mobile/Interactive):**
- Primary: yk5cnfc (always with MacBook)
- Backups: yk5clgtn, yk5nfc (secure storage)

**fedora-jern (Control Center/Stationary):**
- Primary: yk5nfc (always connected to fedora-jern)
- Backups: yk5cnfc, yk5clgtn (available for failover)

**Design Rationale:** Each machine has a different primary YubiKey to minimize single-point-of-failure risk while maintaining triple redundancy.

## Authentication Methods

### FIDO2 Hardware Keys

All SSH authentication uses **FIDO2 resident keys** (ed25519-sk):
- Private keys stored on YubiKey hardware (never exposed)
- Touch confirmation required for each connection
- PIN protection on YubiKeys
- Optional passphrase on private key handles

### Key Inventory

**MacBook Air Keys:**
```
~/.ssh/id_ed25519_yk5cnfc      (yk5cnfc - primary)
~/.ssh/id_ed25519_yk5clgtn     (yk5clgtn - backup 1)
~/.ssh/id_ed25519_sk           (yk5nfc - backup 2)
```

**fedora-jern Keys:**
```
~/.ssh/fedora-jern-yk5nfc      (yk5nfc - primary)
~/.ssh/fedora-jern-yk5cnfc     (yk5cnfc - backup 1)
~/.ssh/fedora-jern-yk5clgtn    (yk5clgtn - backup 2)
```

**Additional Keys (Legacy/Specific):**
- MacBook: `github-id-ed25519-sk` (GitHub authentication)
- MacBook: Various host-specific keys (pihole-*, htpc-*)
- MacBook: `id_rsa` (legacy RSA key)

## SSH Configuration Files

### MacBook Air (`~/.ssh/config`)

```ssh-config
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-id-ed25519-sk
    IdentitiesOnly yes
    AddKeysToAgent yes

Host pihole raspberrypi.lokal
    HostName 192.168.1.69
    User patriark
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
    IdentityFile ~/.ssh/id_ed25519_yk5clgtn
    IdentityFile ~/.ssh/pihole-ed25519-yb5cnfc
    IdentityFile ~/.ssh/pihole-ed25519-yk5clghtn
    IdentityFile ~/.ssh/pihole-ed25519-yk5nfc
    IdentitiesOnly yes
    AddKeysToAgent yes

Host fedora-htpc fedora-htpc.lokal htpc
    HostName 192.168.1.70
    User patriark
    IdentityFile ~/.ssh/htpc-ed25519-yk5nfc
    IdentityFile ~/.ssh/htpc-ed25519-yk5CNFC
    IdentityFile ~/.ssh/htpc-ed25519-ykclghtn
    IdentitiesOnly yes
    IdentityAgent none

Host fedora-jern fedora-jern.lokal jern
    HostName 192.168.1.71
    User patriark
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
    IdentityFile ~/.ssh/id_ed25519_yk5clgtn
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentitiesOnly yes
    AddKeysToAgent yes
```

**Note:** `IdentityAgent none` on fedora-htpc prevents SSH agent conflicts.

### fedora-jern (`~/.ssh/config`)

```ssh-config
# Default settings
Host *
    IdentitiesOnly yes

# Pi-hole DNS Server
Host pihole pihole.lokal raspberrypi.lokal
    HostName 192.168.1.69
    User patriark
    IdentityFile ~/.ssh/fedora-jern-yk5nfc
    IdentityFile ~/.ssh/fedora-jern-yk5cnfc
    IdentityFile ~/.ssh/fedora-jern-yk5clgtn
    IdentityAgent none

# Fedora HTPC
Host fedora-htpc htpc htpc.lokal
    HostName 192.168.1.70
    User patriark
    IdentityFile ~/.ssh/fedora-jern-yk5nfc
    IdentityFile ~/.ssh/fedora-jern-yk5cnfc
    IdentityFile ~/.ssh/fedora-jern-yk5clgtn
    IdentityAgent none
```

**Critical:** `IdentityAgent none` required for FIDO2 keys to work properly with fallback.

## Investigation & Verification Commands

### Check Authorized Keys on Targets

```bash
# From MacBook - check pihole
ssh pihole 'cat ~/.ssh/authorized_keys | grep -E "fedora-jern|yk5" | wc -l'

# From MacBook - check htpc
ssh htpc 'cat ~/.ssh/authorized_keys | grep -E "fedora-jern|yk5" | wc -l'

# From MacBook - check jern
ssh jern 'cat ~/.ssh/authorized_keys | wc -l'
```

**Expected counts:**
- pihole: 5 keys (3 MacBook + 2-3 fedora-jern, has duplicates)
- htpc: 4 keys (1 MacBook + 3 fedora-jern)
- jern: 3 keys (3 MacBook)

### Verify YubiKey Detection

**On MacBook:**
```bash
# List YubiKey (if connected)
ioreg -p IOUSB -w0 -l | grep -i yubikey
```

**On fedora-jern:**
```bash
# List FIDO2 devices
fido2-token -L

# Check USB devices
lsusb | grep -i yubi
```

### Test SSH Key Authentication

**From MacBook:**
```bash
# Test specific YubiKey to pihole
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole hostname

# Test jern connection
ssh jern hostname
```

**From fedora-jern:**
```bash
# Test specific YubiKey to pihole
ssh -i ~/.ssh/fedora-jern-yk5nfc pihole hostname

# Test with config alias
ssh pihole hostname
ssh htpc hostname
```

### View SSH Connection Details

```bash
# Verbose SSH connection (see which keys are tried)
ssh -v pihole hostname 2>&1 | grep -E "Offering|Authenticating"

# Check SSH agent keys
ssh-add -L

# List resident keys on YubiKey
ssh-keygen -K
```

### Verify OpenSSH and FIDO2 Support

**On any Fedora system:**
```bash
# Check OpenSSH version (needs 8.2+ for FIDO2)
ssh -V

# Check libfido2 installation
rpm -q libfido2 fido2-tools
```

## Current Issues & Known Quirks

### 1. Duplicate Keys on pihole and htpc

**Issue:** Some authorized_keys files have duplicate entries due to deployment errors.

**Impact:** Harmless but adds clutter.

**Location:**
- pihole: 5 keys (should be 6: 3 MacBook + 3 jern)
- htpc: 4 keys (should be 6: 3 MacBook + 3 jern)

### 2. Legacy Keys on MacBook

**Issue:** MacBook has host-specific legacy keys (pihole-*, htpc-*) that may overlap with newer universal keys.

**Impact:** Confusion in key management, potential fallback to wrong keys.

### 3. SSH Agent Conflicts

**Issue:** SSH agent caching FIDO2 key handles causes "agent refused operation" errors.

**Workaround:** `IdentityAgent none` in SSH config forces direct YubiKey interaction.

### 4. Password Authentication Status Unknown

**Issue:** Unknown if password authentication is still enabled on pihole/htpc/jern.

**Security Risk:** If enabled, bypasses YubiKey requirement.

### 5. Post-Quantum Warning on htpc

**Issue:** OpenSSH warns about lack of post-quantum key exchange on htpc.

**Impact:** Future vulnerability to quantum decryption attacks ("store now, decrypt later").

## Cleanup Tasks

### Priority 1: Remove Duplicate Authorized Keys

**On pihole:**
```bash
# Backup current file
ssh pihole 'cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup'

# View current keys with line numbers
ssh pihole 'cat -n ~/.ssh/authorized_keys'

# Manually remove duplicates or rebuild file with unique entries:
ssh pihole 'sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.new && mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys'
```

**On htpc:**
```bash
ssh htpc 'cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup'
ssh htpc 'sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.new && mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys'
```

### Priority 2: Consolidate MacBook SSH Config

**Current issue:** MacBook config references legacy host-specific keys (pihole-*, htpc-*) alongside new universal keys (id_ed25519_*).

**Recommendation:**
1. Test new universal keys work for all hosts
2. Remove legacy key references from config
3. Archive legacy key files to `~/.ssh/archive/`

**Updated MacBook config (proposed):**
```ssh-config
# Default for all hosts
Host *
    IdentitiesOnly yes

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-id-ed25519-sk
    AddKeysToAgent yes

Host pihole raspberrypi.lokal
    HostName 192.168.1.69
    User patriark
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
    IdentityFile ~/.ssh/id_ed25519_yk5clgtn
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentityAgent none

Host fedora-htpc fedora-htpc.lokal htpc
    HostName 192.168.1.70
    User patriark
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
    IdentityFile ~/.ssh/id_ed25519_yk5clgtn
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentityAgent none

Host fedora-jern fedora-jern.lokal jern
    HostName 192.168.1.71
    User patriark
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
    IdentityFile ~/.ssh/id_ed25519_yk5clgtn
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentityAgent none
```

### Priority 3: Archive Legacy Keys

```bash
# On MacBook
mkdir -p ~/.ssh/archive
mv ~/.ssh/pihole-ed25519-* ~/.ssh/archive/
mv ~/.ssh/htpc-ed25519-* ~/.ssh/archive/
mv ~/.ssh/id_rsa* ~/.ssh/archive/  # Archive RSA key if not needed
```

## Security Hardening

### Priority 1: Disable Password Authentication

**On each target system (pihole, htpc, jern):**

```bash
# Check current setting
grep -E "^PasswordAuthentication|^ChallengeResponseAuthentication" /etc/ssh/sshd_config

# Edit sshd_config
sudo nano /etc/ssh/sshd_config

# Set these values:
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

# Restart SSH
sudo systemctl restart sshd
```

**⚠️ WARNING:** Test YubiKey authentication works FIRST before disabling password auth, or you'll be locked out!

### Priority 2: Restrict SSH to Specific Users

**On each target system:**

```bash
sudo nano /etc/ssh/sshd_config

# Add line:
AllowUsers patriark

# Restart SSH
sudo systemctl restart sshd
```

### Priority 3: Enable Post-Quantum Key Exchange (Future-Proofing)

**On all Fedora systems:**

Check if OpenSSH supports PQ algorithms:
```bash
ssh -Q kex | grep mlkem
```

If supported, configure in `/etc/ssh/sshd_config`:
```
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
```

**Note:** Requires OpenSSH 9.0+ with mlkem support. May need OS upgrade.

### Priority 4: Implement Fail2Ban or SSHGuard

**On exposed systems (especially if SSH is port-forwarded):**

```bash
# Install fail2ban
sudo dnf install -y fail2ban

# Enable and configure
sudo systemctl enable --now fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Edit jail.local to customize SSH jail
sudo nano /etc/fail2ban/jail.local
```

### Priority 5: Key Rotation Schedule

**Recommendation:** Rotate YubiKey SSH keys annually.

**Process:**
1. Generate new resident keys on all YubiKeys
2. Deploy new public keys to all targets
3. Test new keys work
4. Remove old keys from authorized_keys
5. Delete old key handles from client systems

## Development & Future Enhancements

### Centralized Key Management

**Option 1: Ansible Playbook**
- Automate authorized_keys deployment
- Ensure consistency across all systems
- Version control for SSH configurations

**Option 2: LDAP/FreeIPA Integration**
- Centralized user/key management
- Single source of truth for authorized keys
- Better for scaling beyond 3-4 systems

### SSH Certificate Authority

**Instead of managing individual authorized_keys:**
1. Set up SSH CA on fedora-jern
2. Sign user keys with CA
3. Configure targets to trust CA
4. Simplifies key rotation and revocation

**Resources:**
- https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/securing_networks/using-secure-communications-between-two-systems-with-openssh_securing-networks#signing-ssh-certificates-using-an-ssh-ca_using-secure-communications-between-two-systems-with-openssh

### Monitoring & Alerting

**Track SSH access:**
```bash
# On each system, monitor auth logs
sudo journalctl -u sshd -f

# Set up log aggregation (rsyslog to central server)
# Alert on failed authentication attempts
```

### Bastion/Jump Host Configuration

**Make fedora-jern a bastion for htpc:**
```ssh-config
# On MacBook
Host htpc-via-jern
    HostName 192.168.1.70
    User patriark
    ProxyJump fedora-jern
    IdentityFile ~/.ssh/id_ed25519_yk5cnfc
```

Benefits:
- Single entry point to homelab from external networks
- Better access control and logging
- Reduces attack surface

### Hardware Token PIN Policy

**Recommendations:**
1. Set different PINs on each YubiKey for better security
2. Document PIN recovery process
3. Set PIN retry limits (already default on YubiKey)
4. Consider PIN + biometric on supported devices

### Backup & Recovery Plan

**Current gaps:**
- No documented recovery procedure if all YubiKeys fail
- No emergency access method

**Recommendations:**
1. Generate recovery SSH key pair (non-FIDO2)
2. Store private key in encrypted vault (1Password, Bitwarden)
3. Deploy public key to all systems with `from="trusted.ip.address"` restriction
4. Document emergency recovery process

## Quick Reference

### Common Operations

**Test all connections from fedora-jern:**
```bash
ssh pihole hostname && ssh htpc hostname
```

**Add new public key to a target:**
```bash
cat new-key.pub | ssh target 'cat >> ~/.ssh/authorized_keys'
```

**Remove a specific key from target:**
```bash
ssh target 'grep -v "key-identifier" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys'
```

**Generate new FIDO2 resident key:**
```bash
ssh-keygen -t ed25519-sk -O resident -C "description" -f ~/.ssh/new-key-name
```

**Check which YubiKey is being used:**
```bash
ssh -v target 2>&1 | grep "ED25519-SK"
```

### Troubleshooting

**"agent refused operation" error:**
- Add `IdentityAgent none` to SSH config for that host
- OR: Clear SSH agent with `ssh-add -D`

**"Permission denied (publickey)" error:**
1. Check YubiKey is inserted
2. Verify correct IdentityFile in config
3. Check public key is in target's authorized_keys
4. Try verbose mode: `ssh -v target`

**YubiKey not detected:**
- Check USB connection
- Run `fido2-token -L` (should show /dev/hidraw*)
- Check permissions on /dev/hidraw* devices
- Reinstall libfido2: `sudo dnf reinstall libfido2`

## Maintenance Schedule

**Weekly:**
- Test SSH access from MacBook to all systems
- Test SSH access from fedora-jern to pihole/htpc

**Monthly:**
- Review SSH logs for failed authentication attempts
- Test backup YubiKeys still work

**Quarterly:**
- Review and update this documentation
- Test emergency recovery procedures
- Update OpenSSH and libfido2 packages

**Annually:**
- Rotate YubiKey SSH keys
- Review and update authorized_keys on all systems
- Audit SSH configurations for security best practices

## Related Documentation

- `yubikey-ssh-setup-guide.md` - Original setup guide (in home directory)
- `.ssh/config` - SSH client configurations
- `/etc/ssh/sshd_config` - SSH server configurations on each system

## Changelog

**2025-11-05:**
- Initial documentation created
- Documented YubiKey FIDO2 setup across MacBook and fedora-jern
- Identified cleanup tasks and security hardening opportunities
- Documented known issues (duplicate keys, legacy keys)
