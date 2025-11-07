# SSH Server Hardening Deployment Procedure

**Created:** 2025-11-05
**Target Systems:** pihole (Debian 12), fedora-htpc (Fedora 43), fedora-jern (Fedora 43)

## Pre-Deployment Checklist

- [x] YubiKey authentication verified on all systems
- [ ] Backup YubiKeys tested and available
- [ ] Emergency console access available (keyboard/monitor or IPMI/iLO)
- [ ] All systems accessible via SSH
- [ ] Optimized sshd_config template reviewed

## Critical Safety Rules

⚠️ **NEVER close your current SSH session until you verify new config works!**

**Best Practice:**
1. Keep one terminal with SSH session open (Session A)
2. Open second terminal for testing new config (Session B)
3. Only close Session A after Session B successfully reconnects

## Deployment Order

Deploy in this order to maintain access:
1. **pihole** (least critical, can be accessed from jern)
2. **fedora-htpc** (can be accessed from jern)
3. **fedora-jern** (most critical, deploy last)

---

## System-Specific Configurations

### pihole (Debian 12)

**Changes needed from template:**
```bash
# Line to change:
Subsystem sftp /usr/lib/openssh/sftp-server

# Optional: Change to AUTH if AUTHPRIV not available
SyslogFacility AUTH
```

**Service name:** `ssh` (not `sshd`)

---

### fedora-htpc (Fedora 43)

**Use template as-is** with these settings:
```bash
Subsystem sftp /usr/libexec/openssh/sftp-server
SyslogFacility AUTHPRIV
```

**Service name:** `sshd`

---

### fedora-jern (Fedora 43)

**Same as fedora-htpc** - use template as-is.

**Service name:** `sshd`

---

## Deployment Steps (Per System)

### Step 1: Backup Current Configuration

**Run on target system:**
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-$(date +%Y%m%d)
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original
```

### Step 2: View Current Configuration

**Capture current config for reference:**
```bash
sudo cat /etc/ssh/sshd_config | grep -v "^#" | grep -v "^$" > ~/sshd_config_current.txt
cat ~/sshd_config_current.txt
```

### Step 3: Transfer New Configuration

**From MacBook:**
```bash
# Copy template to target (adjust path for each system)
scp ~/fedora-homelab-containers/docs/30-security/sshd_config-optimized-homelab.conf pihole:/tmp/sshd_config.new

# Or use cat + SSH:
cat ~/fedora-homelab-containers/docs/30-security/sshd_config-optimized-homelab.conf | ssh pihole 'cat > /tmp/sshd_config.new'
```

### Step 4: Customize for Target System

**On target system:**
```bash
# Edit the new config if needed
nano /tmp/sshd_config.new

# For pihole, change these lines:
# Subsystem sftp /usr/lib/openssh/sftp-server
# SyslogFacility AUTH
```

### Step 5: Test Configuration Syntax

**CRITICAL - Always test before applying:**
```bash
sudo sshd -t -f /tmp/sshd_config.new
```

**Expected output:** Silence (no output means success)

**If you see errors:**
- Fix the issues in /tmp/sshd_config.new
- Re-run the test
- DO NOT proceed until test passes

### Step 6: Apply New Configuration

**On target system:**
```bash
# Move new config into place
sudo cp /tmp/sshd_config.new /etc/ssh/sshd_config

# Set proper permissions
sudo chmod 600 /etc/ssh/sshd_config
sudo chown root:root /etc/ssh/sshd_config
```

### Step 7: Restart SSH Service

**⚠️ KEEP YOUR CURRENT SSH SESSION OPEN!**

**Fedora systems (htpc, jern):**
```bash
sudo systemctl restart sshd
```

**Debian systems (pihole):**
```bash
sudo systemctl restart ssh
```

### Step 8: Test New Connection

**From MacBook (new terminal window):**
```bash
# Try to connect with YubiKey
ssh -i ~/.ssh/id_ed25519_yk5cnfc <system> hostname

# Example:
ssh -i ~/.ssh/id_ed25519_yk5cnfc pihole hostname
```

**Expected:**
- Prompt for YubiKey passphrase
- Request YubiKey touch
- Successful connection
- Should see: raspberrypi / fedora-htpc / fedora-jern

**If connection fails:**
1. DON'T PANIC - your original session is still open
2. Check logs in original session: `sudo journalctl -u sshd -n 50` (or `-u ssh` on Debian)
3. Revert: `sudo cp /etc/ssh/sshd_config.backup-$(date +%Y%m%d) /etc/ssh/sshd_config`
4. Restart: `sudo systemctl restart sshd` (or `ssh` on Debian)

### Step 9: Verify Hardening

**On target system, check that password auth is disabled:**
```bash
# Try to connect with password (should fail)
# From another machine without keys:
ssh patriark@<target-ip>
# Should see: "Permission denied (publickey)"
```

**Check logs show publickey authentication:**
```bash
sudo journalctl -u sshd -n 20 | grep -i authentication
# or on Debian:
sudo journalctl -u ssh -n 20 | grep -i authentication
```

### Step 10: Document Changes

**On target system:**
```bash
# Add marker to config showing when it was deployed
sudo bash -c 'echo "# Deployed: $(date) by patriark" >> /etc/ssh/sshd_config'
```

---

## Quick Deployment Script

**Use this for faster deployment after manual verification on first system:**

```bash
#!/bin/bash
# deploy-sshd-config.sh - Deploy optimized SSH config to homelab system
# Usage: ./deploy-sshd-config.sh <system>

SYSTEM=$1
CONFIG_SOURCE="$HOME/fedora-homelab-containers/docs/30-security/sshd_config-optimized-homelab.conf"

if [ -z "$SYSTEM" ]; then
    echo "Usage: $0 <system>"
    echo "Example: $0 pihole"
    exit 1
fi

echo "Deploying SSH config to $SYSTEM..."
echo "1. Backing up current config..."
ssh "$SYSTEM" 'sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-$(date +%Y%m%d)'

echo "2. Transferring new config..."
cat "$CONFIG_SOURCE" | ssh "$SYSTEM" 'cat > /tmp/sshd_config.new'

echo "3. Testing new config..."
ssh "$SYSTEM" 'sudo sshd -t -f /tmp/sshd_config.new'
if [ $? -ne 0 ]; then
    echo "ERROR: Config test failed! Not applying."
    exit 1
fi

echo "4. Applying new config..."
ssh "$SYSTEM" 'sudo cp /tmp/sshd_config.new /etc/ssh/sshd_config && sudo chmod 600 /etc/ssh/sshd_config'

echo "5. Restarting SSH service..."
if [[ "$SYSTEM" == "pihole" ]]; then
    ssh "$SYSTEM" 'sudo systemctl restart ssh'
else
    ssh "$SYSTEM" 'sudo systemctl restart sshd'
fi

echo "6. Testing connection..."
sleep 2
ssh "$SYSTEM" hostname
if [ $? -eq 0 ]; then
    echo "✓ Deployment successful on $SYSTEM"
else
    echo "✗ Connection test failed - check manually!"
    exit 1
fi
```

---

## Rollback Procedure

**If something goes wrong:**

```bash
# Connect to system (if possible)
ssh <system>

# Restore backup
sudo cp /etc/ssh/sshd_config.backup-<date> /etc/ssh/sshd_config

# Restart SSH
sudo systemctl restart sshd   # or 'ssh' on Debian

# Test
ssh <system> hostname
```

**If SSH is completely broken:**
1. Connect via local console (keyboard/monitor)
2. Log in as patriark
3. Restore backup: `sudo cp /etc/ssh/sshd_config.backup-<date> /etc/ssh/sshd_config`
4. Restart: `sudo systemctl restart sshd`

---

## Post-Deployment Verification

**After all systems are updated:**

```bash
# From MacBook - test all systems
for system in pihole htpc jern; do
    echo "Testing $system..."
    ssh -i ~/.ssh/id_ed25519_yk5cnfc $system 'echo "✓ $HOSTNAME accessible"'
done

# From fedora-jern - test targets
ssh jern
ssh pihole 'echo "✓ pihole from jern"'
ssh htpc 'echo "✓ htpc from jern"'
```

**Check security settings applied:**
```bash
# On each system
ssh <system> 'sudo sshd -T | grep -E "passwordauth|permitroot|pubkeyauth|allowusers"'

# Expected output:
# passwordauthentication no
# permitrootlogin no
# pubkeyauthentication yes
# allowusers patriark
```

---

## Troubleshooting

### "Permission denied (publickey)"

**Check:**
1. YubiKey is inserted
2. Correct identity file specified
3. Public key is in target's ~/.ssh/authorized_keys
4. File permissions: authorized_keys should be 600

**Debug:**
```bash
ssh -vvv <system> 2>&1 | grep -E "Offering|Authenticating"
```

### "Connection closed by remote host"

**Likely causes:**
- sshd_config syntax error
- MaxStartups limit reached
- AllowUsers doesn't include your username

**Check logs:**
```bash
ssh <system> 'sudo journalctl -u sshd -n 50'
```

### "agent refused operation"

**Not a problem** - just means SSH agent has stale keys. Direct YubiKey auth still works.

**To clean up:**
```bash
ssh-add -D  # Clear all keys from agent
```

---

## Monitoring & Maintenance

**Check SSH logs regularly:**
```bash
# Failed authentication attempts
sudo journalctl -u sshd | grep -i "failed\|invalid"

# Successful logins
sudo journalctl -u sshd | grep -i "Accepted publickey"

# Configuration changes
sudo journalctl -u sshd | grep -i "configuration"
```

**Set up log alerting (future enhancement):**
- Use logwatch or fail2ban
- Alert on repeated failed authentication attempts
- Monitor for configuration errors

---

## Next Steps After Deployment

1. [ ] Test backup YubiKeys on all systems
2. [ ] Set up Fail2Ban for brute-force protection
3. [ ] Configure log aggregation (rsyslog to central server)
4. [ ] Document emergency recovery procedure
5. [ ] Update ssh-infrastructure-state.md with new settings
