# SSH Security Hardening Analysis - fedora-htpc

**Date**: 2025-11-04
**System**: Fedora Linux 42 (Workstation Edition)
**OpenSSH Version**: 9.9p1
**Current User**: patriark (member of wheel group)

---

## Current Security Posture - FINDINGS

### ✅ **STRONG FOUNDATIONS (Already Implemented)**

1. **Password Authentication DISABLED**
   - `/etc/ssh/sshd_config`: `PasswordAuthentication no`
   - Cannot be bypassed - only key-based auth works

2. **Root Login Restricted**
   - `PermitRootLogin prohibit-password`
   - Root cannot use passwords, only keys (if any were configured)

3. **Hardware Security Keys ACTIVELY USED**
   - All 8 keys in `authorized_keys` are `sk-ssh-ed25519@openssh.com` (FIDO2)
   - Successfully authenticating from MacBook Air (192.168.1.34)
   - Logs show proper "Postponed → Accepted" flow (physical touch required)

4. **Modern Crypto Standards**
   - Crypto policy: DEFAULT (Fedora system-wide)
   - Supports: `sk-ssh-ed25519@openssh.com`, `sk-ecdsa-sha2-nistp256@openssh.com`
   - Strong ciphers: aes256-gcm, chacha20-poly1305
   - No weak algorithms enabled

5. **PAM Integration Active**
   - `UsePAM yes` - Additional security layer
   - GSSAPIAuthentication enabled (Kerberos support if needed)

6. **Firewall Configured**
   - firewalld active on interface enp3s0
   - SSH service explicitly allowed
   - Also open: 80/tcp, 443/tcp, 8096/tcp, 7359/udp (homelab services)

7. **No Failed Intrusion Attempts**
   - Zero failed/invalid/break-in attempts in last 7 days
   - System is not under active attack
   - No need for emergency fail2ban deployment

### ⚠️ **IDENTIFIED WEAKNESSES**

1. **NO IP-BASED ACCESS RESTRICTIONS**
   - Problem: All 8 keys work from ANY IP address globally
   - Risk: If MacBook Air compromised on untrusted network, key still works
   - Impact: No geographic or network-based defense layer

2. **NO MATCH BLOCKS OR CONDITIONAL ACCESS**
   - `/etc/ssh/sshd_config.d/` contains only crypto policies and RedHat defaults
   - No custom hardening rules present
   - No AllowUsers/DenyUsers directives
   - No per-IP or per-network rules

3. **REDUNDANT KEYS (8 keys for 2-3 devices)**
   - 3 keys from patriark@patriark-MB.local (MacBook Air - old hostname?)
   - 3 keys from patriark@fedorajern
   - 1 key from patriark@MacBookAir
   - 1 key from MacBookAir-Sun with odd timestamp suffix
   - Analysis: Likely multiple keys per Yubikey OR keys from removed Yubikeys

4. **PRIVATE KEY FILES ON DISK**
   - `~/.ssh/htpcpihole-ed25519` (private key file present)
   - `~/.ssh/htpcpihole-ed25519-5cNFC` (private key file present)
   - Issue: FIDO2 resident keys should NOT need private key files stored
   - Risk: If disk compromised, attacker gets key material (still needs Yubikey touch, but...)

5. **NO SSH CLIENT CONFIGURATION**
   - `~/.ssh/config` does not exist
   - Users must type full connection strings
   - No enforcement of security best practices client-side

6. **NO INTRUSION DETECTION**
   - fail2ban NOT installed
   - No automated banning of suspicious activity
   - Relying only on strong authentication (which is good, but...)

7. **X11 FORWARDING ENABLED**
   - `/etc/ssh/sshd_config.d/50-redhat.conf`: `X11Forwarding yes`
   - Potential security risk if not needed
   - Attack surface: X11 protocol vulnerabilities

### 📊 **AUTHORIZATION KEY ANALYSIS**

**Current state**: 8 keys from 2-3 devices
```
Device                      Keys    Notes
──────────────────────────  ──────  ─────────────────────────────
patriark-MB.local           3       MacBook Air (old hostname)
patriark@MacBookAir         1       MacBook Air (new hostname)
MacBookAir-Sun Dec...       1       MacBook Air (dated key)
patriark@fedorajern         3       fedora-jern workstation
```

**Hypothesis**: You have 3 Yubikeys and registered multiple keys per device:
- Likely scenario: Each time you generated a key, you added it without removing old ones
- Possible: Some keys are from replaced/lost Yubikeys that should be revoked

**Risk**: If ANY of these 8 keys' Yubikeys are lost/stolen, attacker has access

---

## SUDO ACCESS METHOD (SOLVED)

### Problem Encountered
- Standard `sudo` requires terminal for password input
- Claude Code cannot provide interactive password input

### Solution Implemented
Created askpass helper using Zenity (GUI password prompt):

```bash
# Created /tmp/askpass.sh:
#!/bin/bash
zenity --password --title="sudo password"

# Usage:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A <command>
```

**Permanent solution** (recommended for documentation):
```bash
# Add to ~/.bashrc or create ~/containers/scripts/sudo-gui.sh:
export SUDO_ASKPASS=/usr/bin/zenity-password-wrapper
alias csudo='sudo -A'  # GUI sudo

# Create wrapper:
cat > ~/containers/scripts/zenity-password.sh << 'EOF'
#!/bin/bash
zenity --password --title="Authentication Required"
EOF
chmod +x ~/containers/scripts/zenity-password.sh
```

---

## REVISED SECURITY HARDENING OPTIONS

Based on actual evidence, here are three approaches:

---

## **OPTION 1: Minimal Hardening - Quick Wins** ⭐ RECOMMENDED FOR START
**Complexity**: Low | **Time**: 15 minutes | **Risk**: Very Low

### What It Does
- Clean up redundant keys (8 → 3, one per Yubikey)
- Add IP restrictions to authorized_keys
- Remove unnecessary private key files
- Create SSH client configuration
- Disable X11 forwarding (if not needed)
- Document which key belongs to which Yubikey

### Why This Option
- **Zero risk of lockout** - Changes are in user space only
- **Immediate security improvement** - IP restrictions active immediately
- **Reversible in seconds** - Just restore backup file
- **No service restart required** - SSH daemon unchanged
- **Your current config is already strong** - This just perfects it

### Implementation

#### Step 1: Identify Your Keys
```bash
# First, test with each Yubikey which key it is
cd ~/.ssh

# Insert Yubikey #1 and test:
ssh-keygen -K  # Extract resident keys from Yubikey
# This will show which public key this Yubikey holds

# Label them as you test:
# Key 1: Line X in authorized_keys = Yubikey serial XXXXX
# Key 2: Line Y in authorized_keys = Yubikey serial YYYYY
# Key 3: Line Z in authorized_keys = Yubikey serial ZZZZZ
```

#### Step 2: Create Clean authorized_keys
```bash
# Backup current file
cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup-$(date +%Y%m%d)

# Create new file with IP restrictions
# Replace KEYDATA with actual key strings from your backup
cat > ~/.ssh/authorized_keys << 'EOF'
# Yubikey #1 (Serial: XXXXX) - Primary
from="192.168.1.34,192.168.2.71,192.168.1.70" sk-ssh-ed25519@openssh.com KEYDATA1 yubikey-1-primary

# Yubikey #2 (Serial: YYYYY) - Backup
from="192.168.1.34,192.168.2.71,192.168.1.70" sk-ssh-ed25519@openssh.com KEYDATA2 yubikey-2-backup

# Yubikey #3 (Serial: ZZZZZ) - Backup
from="192.168.1.34,192.168.2.71,192.168.1.70" sk-ssh-ed25519@openssh.com KEYDATA3 yubikey-3-backup
EOF

chmod 600 ~/.ssh/authorized_keys
```

**IP Address meanings**:
- `192.168.1.34` - MacBook Air (DHCP, consider static in router)
- `192.168.2.71` - fedora-jern (appears to be static)
- `192.168.1.70` - fedora-htpc itself (localhost trust)

#### Step 3: Test BEFORE Logout
```bash
# Open NEW terminal and test SSH:
ssh patriark@192.168.1.70

# If it works, you're good!
# If not, restore backup:
cp ~/.ssh/authorized_keys.backup-YYYYMMDD ~/.ssh/authorized_keys
```

#### Step 4: Clean Up Private Keys
```bash
# These shouldn't be needed with resident keys:
ls -la ~/.ssh/htpcpihole-ed25519*

# IF you're confident these are resident keys on Yubikeys:
mkdir -p ~/.ssh/archived-keys
mv ~/.ssh/htpcpihole-ed25519* ~/.ssh/archived-keys/

# Test SSH again - if it still works, keys are truly resident
```

#### Step 5: Create SSH Client Config
```bash
cat > ~/.ssh/config << 'EOF'
# Default for all hosts
Host *
    # Only try Yubikey resident keys
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentityFile ~/.ssh/id_ecdsa_sk
    IdentitiesOnly yes

    # Security
    HashKnownHosts yes
    StrictHostKeyChecking ask
    VerifyHostKeyDNS yes

    # Performance
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes

    # Disable vulnerable features
    ForwardAgent no
    ForwardX11 no

# Localhost (this machine)
Host fedora-htpc localhost
    HostName 192.168.1.70
    User patriark
    ForwardX11 yes  # Allow for local use

# fedora-jern workstation
Host fedora-jern jern
    HostName 192.168.2.71
    User patriark

# MacBook Air
Host macbook mac
    HostName 192.168.1.34
    User patriark
EOF

chmod 600 ~/.ssh/config

# Test:
ssh fedora-htpc  # Should work without specifying user@host
```

#### Step 6: Optional - Disable X11 Forwarding (if not needed)
```bash
# Only if you DON'T need X11 forwarding for GUI apps over SSH
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/ssh/sshd_config.d/60-x11-disable.conf << 'EOF'
# Disable X11 forwarding for security
X11Forwarding no
EOF

SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl restart sshd
```

### Verification
```bash
# Check effective SSH config:
ssh -G fedora-htpc | grep -i "identityfile\|forward"

# Verify authorized_keys permissions:
ls -la ~/.ssh/authorized_keys  # Should be -rw------- (600)

# Test from MacBook Air:
# ssh patriark@192.168.1.70
# (Should work with Yubikey touch)

# Test from unauthorized IP (simulation):
# Edit authorized_keys temporarily, remove your current IP, try SSH - should fail
```

### Rollback Plan
```bash
# If anything goes wrong:
cp ~/.ssh/authorized_keys.backup-YYYYMMDD ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# Done - you're back to original state
```

---

## **OPTION 2: Moderate Hardening - Defense in Depth**
**Complexity**: Medium | **Time**: 45 minutes | **Risk**: Low (with testing)

### What It Does
- Everything from Option 1
- Add sshd Match blocks for IP-based conditional access
- Configure static DHCP reservations in router
- Install and configure fail2ban
- Add SSH rate limiting via firewalld
- Set up audit logging for SSH events
- Create monitoring script for SSH security

### Why This Option
- **Multiple security layers** - If one fails, others protect
- **Automated defense** - fail2ban blocks brute force automatically
- **Better logging** - Audit trail for compliance/forensics
- **Professional setup** - Similar to enterprise SSH hardening
- **Still conservative** - No exotic features, well-tested approach

### Implementation

#### Phase 1: Complete Option 1 First
(Follow all steps from Option 1 above)

#### Phase 2: Configure Static IPs in Router
```bash
# This step is done in your router's DHCP settings
# Pi-hole at 192.168.1.69 might be your DHCP server?

# Get MAC addresses:
ip link show enp3s0  # fedora-htpc MAC
ssh 192.168.1.34 "ip link show en0"  # MacBook Air MAC (if accessible)

# In router/Pi-hole DHCP settings:
# - MacBook Air MAC → 192.168.1.34 (static)
# - fedora-jern MAC → 192.168.2.71 (already static?)
# - fedora-htpc MAC → 192.168.1.70 (already static?)
```

#### Phase 3: Create sshd Match Block Configuration
```bash
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/ssh/sshd_config.d/80-ip-restrictions.conf << 'EOF'
# IP-based access control
# Default deny is handled by authorized_keys restrictions
# This adds defense-in-depth

# Trusted local network access
Match Address 192.168.1.0/24,192.168.2.0/24
    # Allow passwordless sudo users only
    AllowGroups wheel
    MaxAuthTries 3
    LoginGraceTime 30

# Reject everything else (belt and suspenders)
Match Address *,!192.168.1.0/24,!192.168.2.0/24
    DenyUsers *
    PermitRootLogin no
EOF

# Validate configuration
SUDO_ASKPASS=/tmp/askpass.sh sudo -A sshd -t

# If validation passes, restart
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl restart sshd
```

#### Phase 4: Install and Configure fail2ban
```bash
# Install
SUDO_ASKPASS=/tmp/askpass.sh sudo -A dnf install -y fail2ban

# Configure
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban for 1 hour
bantime = 3600
# Check for 3 failures in 10 minutes
findtime = 600
maxretry = 3
# Send to firewalld
banaction = firewallcmd-rich-rules
# Log level
loglevel = INFO

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd

# Additional protection against port scanning
[sshd-ddos]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 6
findtime = 60
bantime = 600
EOF

# Enable and start
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl enable --now fail2ban

# Check status
SUDO_ASKPASS=/tmp/askpass.sh sudo -A fail2ban-client status
SUDO_ASKPASS=/tmp/askpass.sh sudo -A fail2ban-client status sshd
```

#### Phase 5: Add SSH Rate Limiting (firewalld)
```bash
# Limit SSH connections per IP
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --permanent \
  --add-rich-rule='rule service name="ssh" limit value="10/m" accept'

# Reload
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --reload

# Verify
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --list-rich-rules
```

#### Phase 6: Enhanced Audit Logging
```bash
# Create audit rule for SSH key authentication
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/audit/rules.d/ssh-monitoring.rules << 'EOF'
# Monitor SSH key file access
-w /home/patriark/.ssh/authorized_keys -p wa -k ssh_key_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config_changes

# Monitor SSH daemon
-w /usr/sbin/sshd -p x -k sshd_execution
EOF

# Reload audit rules
SUDO_ASKPASS=/tmp/askpass.sh sudo -A augenrules --load

# Test audit
ausearch -k ssh_key_changes -ts recent
```

#### Phase 7: Create Monitoring Script
```bash
cat > ~/containers/scripts/ssh-security-monitor.sh << 'EOF'
#!/bin/bash
# SSH Security Monitoring Script

echo "=== SSH Security Status Report ==="
echo "Generated: $(date)"
echo ""

echo "--- Active SSH Sessions ---"
who | grep pts

echo ""
echo "--- Recent SSH Logins (last 10) ---"
last -n 10 | grep pts

echo ""
echo "--- fail2ban Status ---"
sudo fail2ban-client status sshd 2>/dev/null || echo "fail2ban not configured"

echo ""
echo "--- Recent Auth Failures (last 24h) ---"
journalctl -u sshd --since "24 hours ago" | grep -i "failed\|invalid" | wc -l

echo ""
echo "--- Authorized Keys Count ---"
wc -l ~/.ssh/authorized_keys

echo ""
echo "--- SSH Service Status ---"
systemctl status sshd --no-pager -l | head -10

echo ""
echo "--- Firewall SSH Rules ---"
sudo firewall-cmd --list-rich-rules | grep ssh || echo "No rich rules for SSH"
EOF

chmod +x ~/containers/scripts/ssh-security-monitor.sh

# Run it:
~/containers/scripts/ssh-security-monitor.sh
```

### Testing Procedure
```bash
# 1. Test from authorized IP (MacBook Air)
ssh patriark@192.168.1.70  # Should work

# 2. Test fail2ban (simulate attack from MacBook)
for i in {1..4}; do
    ssh -o PreferredAuthentications=password wronguser@192.168.1.70
done
# Check if banned:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A fail2ban-client status sshd

# 3. Unban yourself if needed:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A fail2ban-client set sshd unbanip 192.168.1.34

# 4. Monitor logs:
journalctl -u sshd -f
```

### Rollback Plan
```bash
# Remove Match blocks:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A rm /etc/ssh/sshd_config.d/80-ip-restrictions.conf
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl restart sshd

# Disable fail2ban:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl stop fail2ban
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl disable fail2ban

# Remove firewall rule:
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --permanent \
  --remove-rich-rule='rule service name="ssh" limit value="10/m" accept'
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --reload
```

---

## **OPTION 3: Advanced Hardening - Zero Trust Architecture**
**Complexity**: High | **Time**: 2-3 hours | **Risk**: Medium (requires careful testing)

### What It Does
- Everything from Options 1 & 2
- SSH Certificate Authority for centralized key management
- FIDO2 resident keys with verification policies
- Port knocking to hide SSH port from scanners
- Separate SSH ports per network segment
- Two-factor authentication (FIDO2 + certificate)
- Session recording and audit logging
- Automatic key rotation policy
- Geofencing via GeoIP

### Why This Option
- **Maximum security** - Bank/government level hardening
- **Centralized control** - Revoke access instantly via CA
- **Compliance ready** - Meets strict security frameworks (PCI-DSS, NIST)
- **Invisible to attackers** - Port knocking hides SSH completely
- **Future-proof** - Scales to multiple users/systems

### ⚠️ WARNING
This option is complex and can lock you out if misconfigured. Only proceed if:
- You have physical access to the machine
- You have console/KVM access
- You understand SSH certificates and PKI
- You're comfortable with advanced troubleshooting

### Implementation

#### Phase 1: Complete Options 1 & 2
(Follow all steps above first)

#### Phase 2: Set Up SSH Certificate Authority
```bash
# Create CA structure
mkdir -p ~/.ssh/ca/{private,public,certs}
chmod 700 ~/.ssh/ca
chmod 700 ~/.ssh/ca/private

# Generate CA key (KEEP THIS SECURE!)
ssh-keygen -t ed25519 -f ~/.ssh/ca/private/user_ca \
  -C "SSH User CA for fedora-htpc homelab"
chmod 600 ~/.ssh/ca/private/user_ca

# Generate each Yubikey's certificate
# Do this with each Yubikey inserted:

# Yubikey #1:
ssh-keygen -s ~/.ssh/ca/private/user_ca \
  -I "patriark-yubikey1-$(date +%Y%m%d)" \
  -n patriark \
  -V +52w \
  -O source-address=192.168.1.0/24,192.168.2.0/24 \
  -O verify-required \
  ~/.ssh/id_yk1.pub

# Yubikey #2:
ssh-keygen -s ~/.ssh/ca/private/user_ca \
  -I "patriark-yubikey2-$(date +%Y%m%d)" \
  -n patriark \
  -V +52w \
  -O source-address=192.168.1.0/24,192.168.2.0/24 \
  -O verify-required \
  ~/.ssh/id_yk2.pub

# Yubikey #3:
ssh-keygen -s ~/.ssh/ca/private/user_ca \
  -I "patriark-yubikey3-$(date +%Y%m%d)" \
  -n patriark \
  -V +52w \
  -O source-address=192.168.1.0/24,192.168.2.0/24 \
  -O verify-required \
  ~/.ssh/id_yk3.pub

# Copy CA public key to sshd location
SUDO_ASKPASS=/tmp/askpass.sh sudo -A cp ~/.ssh/ca/private/user_ca.pub \
  /etc/ssh/trusted_user_ca.pub
SUDO_ASKPASS=/tmp/askpass.sh sudo -A chmod 644 /etc/ssh/trusted_user_ca.pub
```

#### Phase 3: Configure sshd for Certificate Authentication
```bash
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/ssh/sshd_config.d/90-certificate-auth.conf << 'EOF'
# Certificate-based authentication
TrustedUserCAKeys /etc/ssh/trusted_user_ca.pub

# Require certificate + key
AuthenticationMethods publickey
PubkeyAuthentication yes

# Enhanced security
PermitRootLogin no
MaxAuthTries 2
LoginGraceTime 20

# Log certificate details
LogLevel VERBOSE

# Disable weaker methods
PasswordAuthentication no
KbdInteractiveAuthentication no
GSSAPIAuthentication no
EOF

SUDO_ASKPASS=/tmp/askpass.sh sudo -A sshd -t && \
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl restart sshd
```

#### Phase 4: Implement Port Knocking
```bash
# Install knockd
SUDO_ASKPASS=/tmp/askpass.sh sudo -A dnf install -y knock-server

# Configure knock sequence
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/knockd.conf << 'EOF'
[options]
    UseSyslog
    Interface = enp3s0

[openSSH]
    sequence    = 7142,8256,9374
    seq_timeout = 15
    start_command = firewall-cmd --add-port=22/tcp
    tcpflags    = syn
    cmd_timeout = 30
    stop_command = firewall-cmd --remove-port=22/tcp

[closeSSH]
    sequence    = 9374,8256,7142
    seq_timeout = 15
    command     = firewall-cmd --remove-port=22/tcp
    tcpflags    = syn
EOF

# Enable knockd
SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl enable --now knockd

# Close SSH port by default
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --remove-service=ssh --permanent
SUDO_ASKPASS=/tmp/askpass.sh sudo -A firewall-cmd --reload

# Test from client:
# knock 192.168.1.70 7142 8256 9374
# ssh patriark@192.168.1.70
# knock 192.168.1.70 9374 8256 7142  # Close port
```

#### Phase 5: Install knock Client on MacBook/fedora-jern
```bash
# On MacBook Air:
brew install knock

# On fedora-jern:
sudo dnf install -y knock

# Create knock wrapper:
cat > ~/.ssh/ssh-knock.sh << 'EOF'
#!/bin/bash
HOST=$1
shift
knock $HOST 7142 8256 9374 -d 500
sleep 1
ssh "$HOST" "$@"
knock $HOST 9374 8256 7142 -d 500
EOF
chmod +x ~/.ssh/ssh-knock.sh

# Usage:
# ~/.ssh/ssh-knock.sh fedora-htpc
```

#### Phase 6: Set Up Session Recording
```bash
# Install tlog for session recording
SUDO_ASKPASS=/tmp/askpass.sh sudo -A dnf install -y tlog

# Configure PAM to record SSH sessions
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee -a /etc/pam.d/sshd << 'EOF'
# Record SSH sessions
session optional pam_exec.so /usr/bin/tlog-rec-session
EOF

# Logs stored in journal, view with:
# tlog-play -r journal -M TLOG_REC=<session_id>
```

#### Phase 7: Create Key Rotation Policy
```bash
cat > ~/containers/scripts/ssh-cert-rotate.sh << 'EOF'
#!/bin/bash
# SSH Certificate Rotation Script
# Run this every 52 weeks or on-demand for revocation

CA_KEY=~/.ssh/ca/private/user_ca
VALIDITY="+52w"

echo "=== SSH Certificate Rotation ==="
echo "This will re-issue certificates for all Yubikeys"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

# Revoke old certificates (optional - implement revocation list)
# For now, old certs will expire naturally

# Re-issue for each Yubikey
for key in ~/.ssh/id_yk*.pub; do
    basename=$(basename "$key" .pub)
    echo "Issuing certificate for $basename"

    ssh-keygen -s "$CA_KEY" \
        -I "patriark-$basename-$(date +%Y%m%d)" \
        -n patriark \
        -V "$VALIDITY" \
        -O source-address=192.168.1.0/24,192.168.2.0/24 \
        -O verify-required \
        "$key"

    echo "Certificate created: ${basename}-cert.pub"
done

echo "=== Rotation Complete ==="
echo "Copy new certificates to client machines"
EOF

chmod +x ~/containers/scripts/ssh-cert-rotate.sh
```

#### Phase 8: GeoIP Blocking (Optional)
```bash
# Install GeoIP
SUDO_ASKPASS=/tmp/askpass.sh sudo -A dnf install -y geoipupdate

# Configure to only allow Norway/local
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee /etc/ssh/sshd_config.d/95-geoip.conf << 'EOF'
# Use TCP wrappers for GeoIP filtering
UseDNS yes
EOF

# Configure hosts.deny
SUDO_ASKPASS=/tmp/askpass.sh sudo -A tee -a /etc/hosts.deny << 'EOF'
sshd: ALL EXCEPT LOCAL
EOF

SUDO_ASKPASS=/tmp/askpass.sh sudo -A systemctl restart sshd
```

### Testing Procedure (CRITICAL!)
```bash
# BEFORE CLOSING YOUR CURRENT SESSION!

# Terminal 1: Keep your current SSH session open
# Terminal 2: Test new connection

# Test 1: Port knock + connect
knock 192.168.1.70 7142 8256 9374 -d 500
sleep 1
ssh -vvv -i ~/.ssh/id_yk1 -o CertificateFile=~/.ssh/id_yk1-cert.pub patriark@192.168.1.70

# If successful, test disconnect knock:
knock 192.168.1.70 9374 8256 7142 -d 500

# Test 2: Verify certificate
ssh-keygen -L -f ~/.ssh/id_yk1-cert.pub | grep -A 5 "Critical Options"

# Test 3: Try without certificate (should fail)
ssh -i ~/.ssh/id_yk1 patriark@192.168.1.70

# IF ANYTHING FAILS, ROLLBACK FROM TERMINAL 1!
```

### Emergency Rollback
```bash
# If locked out, use console/physical access:

# Remove certificate auth:
sudo rm /etc/ssh/sshd_config.d/90-certificate-auth.conf

# Re-enable SSH in firewall:
sudo firewall-cmd --add-service=ssh --permanent
sudo firewall-cmd --reload

# Disable knockd:
sudo systemctl stop knockd
sudo systemctl disable knockd

# Restart sshd:
sudo systemctl restart sshd

# Restore original authorized_keys:
cp ~/.ssh/authorized_keys.backup-YYYYMMDD ~/.ssh/authorized_keys
```

### Maintenance
```bash
# Weekly checks:
~/containers/scripts/ssh-security-monitor.sh

# Monthly certificate inspection:
for cert in ~/.ssh/*-cert.pub; do
    echo "=== $cert ==="
    ssh-keygen -L -f "$cert" | grep -E "Valid:|Critical Options:"
done

# Yearly certificate rotation:
~/containers/scripts/ssh-cert-rotate.sh
```

---

## COMPARISON MATRIX

| Feature | Option 1 | Option 2 | Option 3 |
|---------|----------|----------|----------|
| **Complexity** | Low | Medium | High |
| **Implementation Time** | 15 min | 45 min | 2-3 hrs |
| **Lockout Risk** | Very Low | Low | Medium |
| **Maintenance** | Minimal | Low | Moderate |
| **IP Restrictions** | ✅ User space | ✅ System + User | ✅ CA-enforced |
| **Key Cleanup** | ✅ | ✅ | ✅ |
| **fail2ban** | ❌ | ✅ | ✅ |
| **Firewall Rate Limit** | ❌ | ✅ | ✅ |
| **Match Blocks** | ❌ | ✅ | ✅ |
| **SSH Certificates** | ❌ | ❌ | ✅ |
| **Port Knocking** | ❌ | ❌ | ✅ |
| **Session Recording** | ❌ | ❌ | ✅ |
| **GeoIP Blocking** | ❌ | ❌ | ✅ Optional |
| **Key Rotation** | Manual | Manual | Automated |
| **Centralized Revocation** | ❌ | ❌ | ✅ |
| **Compliance Level** | Basic | Good | Excellent |

---

## RECOMMENDATIONS

### For Your Homelab: **START WITH OPTION 1** ⭐

**Reasoning:**
1. **Your current security is already strong**
   - Password auth disabled ✅
   - Hardware keys only ✅
   - No failed intrusion attempts ✅
   - Modern crypto standards ✅

2. **Option 1 gives 80% of security for 20% of effort**
   - IP restrictions prevent remote attacks
   - Key cleanup reduces attack surface
   - Zero risk implementation
   - Instantly reversible

3. **Option 2 is good for "defense in depth" philosophy**
   - Add if you want automated protection
   - fail2ban is valuable if system is internet-facing
   - Match blocks provide system-level enforcement

4. **Option 3 is overkill for a homelab**
   - Unless you're practicing for enterprise deployment
   - Or you have compliance requirements
   - Or you manage multiple users/systems

### Implementation Path

**Week 1**: Implement Option 1
- Clean up keys
- Add IP restrictions
- Create SSH config
- Monitor for any issues

**Week 2-3**: Add Option 2 components if desired
- Set up static IPs in router first
- Add Match blocks
- Install fail2ban
- Test thoroughly

**Future**: Consider Option 3 elements piecemeal
- SSH CA when you add more systems
- Port knocking if exposing to internet
- Session recording if needed for audit trail

---

## SECURITY BEST PRACTICES (Regardless of Option)

1. **Keep separate Yubikeys in separate locations**
   - Primary: Daily keyring
   - Backup 1: Home safe
   - Backup 2: Off-site (family member, safety deposit box)

2. **Document which key is which**
   ```bash
   # Create key inventory
   cat > ~/containers/docs/30-security/YUBIKEY-INVENTORY.md << 'EOF'
   # Yubikey Inventory

   ## Yubikey #1 (Primary)
   - Serial: XXXXX
   - Color: Blue
   - Location: Daily keyring
   - SSH Key: Line 1 in authorized_keys
   - Purchase Date: YYYY-MM-DD

   ## Yubikey #2 (Backup)
   - Serial: YYYYY
   - Color: Black
   - Location: Home safe
   - SSH Key: Line 2 in authorized_keys
   - Purchase Date: YYYY-MM-DD

   ## Yubikey #3 (Emergency)
   - Serial: ZZZZZ
   - Color: Black
   - Location: Off-site backup
   - SSH Key: Line 3 in authorized_keys
   - Purchase Date: YYYY-MM-DD
   EOF
   ```

3. **Test emergency access regularly**
   - Once per quarter, test SSH with backup Yubikey
   - Ensure you can access without primary key

4. **Monitor SSH logs**
   ```bash
   # Add to cron or systemd timer:
   journalctl -u sshd --since "24 hours ago" | \
     grep -i "failed\|invalid" | \
     mail -s "SSH Security Alert" your@email.com
   ```

5. **Keep firmware updated**
   ```bash
   # Check Yubikey firmware:
   ykman info

   # Update if available (irreversible!):
   # Visit: https://www.yubico.com/support/download/yubikey-manager/
   ```

---

## CONCLUSION

Your SSH setup is already in good shape. Option 1 will make it excellent with minimal effort and zero risk. The main security improvements you need are:

1. ✅ **Clean up redundant keys** (8 → 3)
2. ✅ **Add IP restrictions** (prevent remote access)
3. ✅ **Remove private key files** (not needed with resident keys)
4. ✅ **Create SSH config** (convenience + security enforcement)
5. ✅ **Document your setup** (future you will thank you)

Choose Option 2 if you want enterprise-grade protection. Choose Option 3 if you're building skills for professional security work or managing a multi-user environment.

**Next Steps**: Review this document, choose your option, and let me know when you're ready to proceed with implementation!
