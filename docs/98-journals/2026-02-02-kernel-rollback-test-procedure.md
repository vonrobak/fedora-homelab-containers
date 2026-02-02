# Kernel Rollback Test Procedure

**Date:** 2026-02-02
**Purpose:** Test if kernel 6.17.12 restores working network behavior
**Related:** [Forum post](https://archlinuxarm.org/forum/viewtopic.php?f=65&t=17368) describing similar issue

---

## Context

After catastrophic network failure on Feb 2 following kernel upgrade 6.17.12 → 6.18.7, testing if the old kernel restores working behavior. This will confirm whether kernel 6.18.7 is truly the root cause.

**Installed kernels:**
- kernel-6.17.12-300.fc43.x86_64 (working as of Feb 1)
- kernel-6.18.5-200.fc43.x86_64
- kernel-6.18.7-200.fc43.x86_64 (current, broken)

---

## Pre-Reboot: Disable Auto-Start

Quadlet services have `WantedBy=default.target` and will auto-start on boot. Must disable them first.

```bash
# Move quadlets out of systemd's path
mkdir -p ~/containers/quadlets-disabled
mv ~/.config/containers/systemd/*.container ~/containers/quadlets-disabled/

# Reload systemd
systemctl --user daemon-reload

# Verify services are gone
systemctl --user list-units --type=service | grep -E "traefik|home-assistant|jellyfin"
# Should show nothing

# Verify no containers running
podman ps
# Should show: CONTAINER ID  IMAGE  COMMAND  CREATED  STATUS  PORTS  NAMES

# Now safe to reboot
sudo reboot
```

---

## Boot into Kernel 6.17.12

**Method 1: One-time boot (recommended for testing)**

1. During boot, press **ESC** or hold **Shift** to show GRUB menu
2. Select: **Fedora Linux (6.17.12-300.fc43.x86_64)**
3. Press **Enter**

**Method 2: Set as default (if test succeeds)**

```bash
# Set 6.17.12 as default kernel
sudo grubby --set-default /boot/vmlinuz-6.17.12-300.fc43.x86_64

# Verify
sudo grubby --default-kernel
# Should show: /boot/vmlinuz-6.17.12-300.fc43.x86_64

# Reboot
sudo reboot
```

---

## Post-Boot: Restore Quadlets and Test

**After system boots into 6.17.12:**

```bash
# Verify kernel version
uname -r
# Should show: 6.17.12-300.fc43.x86_64

# Restore quadlets
mv ~/containers/quadlets-disabled/*.container ~/.config/containers/systemd/

# Reload systemd
systemctl --user daemon-reload

# Start services in dependency order
systemctl --user start traefik.service
sleep 5
systemctl --user start authelia.service
sleep 3
systemctl --user start home-assistant.service
sleep 5
systemctl --user start jellyfin.service
systemctl --user start nextcloud.service
systemctl --user start immich-server.service
systemctl --user start grafana.service
systemctl --user start prometheus.service
systemctl --user start alertmanager.service
```

---

## Verification Tests

**Wait 2-3 minutes for services to stabilize, then:**

### Test 1: Check for "untrusted proxy" errors

```bash
journalctl --user -u home-assistant.service --since "5 minutes ago" | grep "untrusted proxy"
```

**Expected if working:** No output
**Expected if broken:** Lines like `Received X-Forwarded-For header from an untrusted proxy 10.89.4.x`

### Test 2: Check network routing

```bash
podman exec home-assistant ip route | grep default
```

**Expected if working:** `default via 10.89.2.1 dev eth0 metric 100` (reverse_proxy first)
**Expected if broken:** Routes in random order, monitoring network first

### Test 3: Check DNS resolution from Traefik

```bash
podman exec traefik nslookup home-assistant | grep -A1 "Non-authoritative" | grep Address | head -1
```

**Expected if working:** Returns 10.89.2.x (reverse_proxy network)
**Expected if broken:** Returns 10.89.4.x or 10.89.6.x (wrong network)

### Test 4: Test external access

```bash
curl -I https://ha.patriark.org
```

**Expected if working:** `HTTP/2 200` or `HTTP/2 302`
**Expected if broken:** `HTTP/2 400`

### Test 5: Check Traefik can reach backend

```bash
podman exec traefik wget -qO- --timeout=2 http://home-assistant:8123/manifest.json | jq -r .name
```

**Expected if working:** `Home Assistant`
**Expected if broken:** Timeout or error

---

## Decision Tree

### ✅ If All Tests Pass (Kernel 6.17.12 Works)

**Root cause CONFIRMED:** Kernel 6.18.7 broke Podman multi-network behavior

**Actions:**
1. Set 6.17.12 as default kernel (see Method 2 above)
2. Exclude 6.18.x from updates:
   ```bash
   sudo nano /etc/dnf/dnf.conf
   # Add line: exclude=kernel-6.18*
   ```
3. Re-enable services to auto-start:
   ```bash
   # Services already restored, just verify
   systemctl --user list-unit-files | grep traefik
   # Should show: generated -
   ```
4. Report bug to Fedora/kernel bugzilla
5. Update journal with findings
6. Monitor for kernel 6.19 release and test before upgrading

### ❌ If Tests Still Fail (Kernel 6.17.12 Also Broken)

**Root cause NOT the kernel** - something else changed

**Actions:**
1. Stop all services:
   ```bash
   for svc in traefik authelia home-assistant jellyfin nextcloud immich-server grafana prometheus alertmanager; do
       systemctl --user stop ${svc}.service
   done
   ```
2. Move quadlets back to disabled:
   ```bash
   mv ~/.config/containers/systemd/*.container ~/containers/quadlets-disabled/
   systemctl --user daemon-reload
   ```
3. Return to investigation - check for:
   - Podman state corruption
   - Network configuration issues
   - Container volumes/config changes
   - Other system changes in Feb 1 update

---

## Emergency Stop (If System Broken After Boot)

If services auto-started and are exposing internal networks:

```bash
# Immediate stop
podman stop $(podman ps -q)

# Disable quadlets
mv ~/.config/containers/systemd/*.container ~/containers/quadlets-disabled/
systemctl --user daemon-reload

# Verify stopped
podman ps
ss -tlnp | grep -E ":80|:443"
```

---

## Rollback This Test

To return to kernel 6.18.7 (e.g., if 6.17.12 also doesn't work):

```bash
# Set 6.18.7 as default
sudo grubby --set-default /boot/vmlinuz-6.18.7-200.fc43.x86_64

# Reboot
sudo reboot
```

---

## Notes

- Kernel 6.17.12 was last known-good state (Feb 1, 2026)
- Zero "untrusted proxy" errors Jan 28-Feb 1 with identical config
- This test is non-destructive - can easily switch back
- Keep quadlets disabled by default until issue resolved
- Manual service start gives control over testing order

---

## Success Criteria

Test is successful if:
1. No "untrusted proxy" errors after 5+ minutes
2. External HTTPS access returns 200/302 (not 400)
3. Network routing shows reverse_proxy first
4. DNS resolves to reverse_proxy IPs
5. Traefik can reach all backends via DNS

If all criteria met, kernel 6.18.7 is confirmed as root cause.
