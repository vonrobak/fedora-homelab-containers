# Symlink Hypothesis Test - Network Ordering Investigation

**Date:** 2026-02-02 20:40 CET
**Status:** Awaiting reboot test
**Related:** [Catastrophic Network Failure](2026-02-02-catastrophic-network-failure-investigation.md), [Kernel Rollback](2026-02-02-kernel-rollback-test-procedure.md)

---

## Hypothesis

**Symlinks are causing systemd to process network quadlets in alphabetical order, affecting Podman container network attachment order.**

### Evidence Supporting Hypothesis

1. **Timeline correlation:**
   - Jan 28: Symlink migration (quadlets/README.md)
   - Feb 2 00:45: First reboot after migration
   - Feb 2 01:35: First "untrusted proxy" error (55 min after boot)

2. **Network service startup order (both boots after symlink migration):**
   ```
   Boot -1 (Feb 2 00:46, kernel 6.18.7): ALPHABETICAL
   Boot  0 (Feb 2 19:56, kernel 6.17.12): ALPHABETICAL

   Order: auth_services, gathio, home_automation, media_services,
          monitoring, nextcloud, photos, reverse_proxy (LAST)
   ```

3. **Kernel rollback failed:** Same issue on kernel 6.17.12, ruling out kernel as root cause

4. **Symlink inode order:** All symlinks created simultaneously (Jan 28 13:13) resulted in sequential alphabetical inodes (107479983-107479990)

---

## Test Performed (20:36 CET)

### Actions Taken

1. **Stopped all services** (27 containers)
2. **Removed all symlinks** from `~/.config/containers/systemd/`
3. **Copied real files** from `~/containers/quadlets/` to `~/.config/containers/systemd/`
4. **Reloaded systemd** and started core services

### Backup Created

```bash
~/containers/quadlets.backup-20260202-203644/
```

---

## Initial Observations (Without Reboot)

### ✅ Improvement: DNS Nameserver Order

**Before (with symlinks):**
```
Traefik /etc/resolv.conf:
nameserver 10.89.4.1  # monitoring - FIRST (wrong)
nameserver 10.89.3.1  # auth_services
nameserver 10.89.2.1  # reverse_proxy - LAST
```

**After (real files, no symlinks):**
```
Traefik /etc/resolv.conf:
nameserver 10.89.2.1  # reverse_proxy - FIRST ✅
nameserver 10.89.4.1  # monitoring
nameserver 10.89.3.1  # auth_services
```

### ❌ Still Broken: DNS Resolution & Routing

- DNS still returns monitoring IP first: `10.89.4.127` before `10.89.2.123`
- Traefik still connects via monitoring network: `10.89.4.126`
- Home Assistant still rejects: "Received X-Forwarded-For header from an untrusted proxy 10.89.4.126"
- External access: HTTP/2 400

**Note:** This test was WITHOUT a full system reboot. The original problem only manifested after a complete reboot.

---

## Next Steps: Reboot Test

### Expected Outcomes

**If symlink hypothesis is correct:**
- ✅ Network services start in non-alphabetical order (reverse_proxy early)
- ✅ DNS nameservers ordered correctly (10.89.2.1 first)
- ✅ DNS returns reverse_proxy IPs first
- ✅ No "untrusted proxy" errors
- ✅ External HTTPS access returns 200/302

**If symlink hypothesis is incorrect:**
- ❌ Same alphabetical network startup order
- ❌ Still broken after reboot
- ⚠️ Need to investigate deeper Podman/aardvark-dns issues

### Verification Commands

```bash
# 1. Check network service startup order
journalctl --user -b | grep -E "network.service" | grep "Starting"

# 2. Check DNS nameserver order
podman exec traefik cat /etc/resolv.conf
podman exec home-assistant cat /etc/resolv.conf

# 3. Test DNS resolution
podman exec traefik nslookup home-assistant | grep -A1 "^Name:"

# 4. Check for untrusted proxy errors
journalctl --user -u home-assistant.service --since "5 minutes ago" | grep "untrusted"

# 5. Test external access
curl -I https://ha.patriark.org
```

---

## Current System State

**Kernel:** 6.17.12-300.fc43.x86_64 (rollback kernel)
**Podman:** 5.7.1
**Quadlets:** Real files in `~/.config/containers/systemd/`, NO symlinks
**Services:** Core services running (traefik, authelia, home-assistant, crowdsec)
**Status:** Partially broken (DNS improved but still routing via wrong network)

---

## Important Context

1. **System worked reliably for months** across many reboots before symlink migration
2. **Statistically implausible** it was "random luck" for months
3. **Symlink approach was for git tracking** - quadlets moved from `~/.config/containers/systemd/` to `~/containers/quadlets/` with symlinks back
4. **If this works:** Manual copy workflow acceptable (copy files to `~/containers/quadlets/` for git tracking)

---

## Files Changed

- Removed: All symlinks in `~/.config/containers/systemd/*.{container,network}`
- Added: 36 real files copied from `~/containers/quadlets/`
- Backup: `~/containers/quadlets.backup-20260202-203644/`

---

## References

- Symlink migration commit: https://github.com/vonrobak/fedora-homelab-containers/commit/6721219384a8ce58616cb14f464dd4588f72d8de
- Podman Issue #12850: Networks attach in undefined order
- Podman Issue #14262: DNS nameserver order is random (WONT_FIX)
