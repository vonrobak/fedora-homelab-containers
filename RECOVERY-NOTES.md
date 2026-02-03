# Network Ordering Issue - Recovery Notes
**Date:** 2026-02-02  
**Status:** All services stopped pending local investigation

## What Happened

**Root Cause:**
- Kernel upgrade (6.17.11 → 6.18.7) on Feb 1, 2026 changed network namespace behavior
- Podman has known bugs with multi-network containers:
  - [Issue #12850](https://github.com/containers/podman/issues/12850): Networks attach alphabetically, not in declaration order
  - [Issue #14262](https://github.com/containers/podman/issues/14262): DNS nameserver order is random
- Result: All internet-facing services routing through monitoring network (10.89.4.x) instead of reverse_proxy (10.89.2.x)
- **ARCHITECTURE VIOLATION:** Monitoring network should never handle internet traffic

**Symptoms:**
- Home Assistant: 400 Bad Request (strict trusted_proxies enforcement caught it)
- Other services: Silently violated network segmentation (no errors but wrong routing)

## Fix Applied (Ready for Testing)

**Changed 9 quadlet files** with explicit interface ordering:
```diff
-Network=systemd-reverse_proxy
+Network=systemd-reverse_proxy:interface_name=eth0
```

**Files modified:**
- traefik.container
- home-assistant.container
- jellyfin.container
- immich-server.container
- nextcloud.container
- grafana.container
- prometheus.container
- alertmanager.container
- authelia.container

## Recovery Steps (When Home)

1. **Verify quadlet changes:**
   ```bash
   cd ~/containers
   git diff quadlets/*.container
   ```

2. **Reload systemd and restart services:**
   ```bash
   systemctl --user daemon-reload
   
   # Start in order (least critical first)
   for svc in alertmanager prometheus grafana authelia nextcloud immich-server jellyfin home-assistant traefik; do
       systemctl --user restart $svc.service
       sleep 3
   done
   ```

3. **Verify network routing:**
   ```bash
   ~/containers/scripts/verify-network-routing.sh
   ```

4. **Test services:**
   ```bash
   curl -I https://ha.patriark.org        # Should return 200 or 302, not 400
   curl -I https://jellyfin.patriark.org  # Should work
   curl -I https://immich.patriark.org    # Should work
   ```

5. **Verify interface order in containers:**
   ```bash
   for svc in traefik home-assistant; do
       echo "=== $svc ==="
       podman exec $svc ip addr show | grep "inet 10.89"
       podman exec $svc ip route | grep default
       podman exec $svc cat /etc/resolv.conf | grep nameserver
   done
   ```

   **Expected results:**
   - eth0 should be 10.89.2.x (reverse_proxy)
   - Default route: 10.89.2.1
   - First nameserver: 10.89.2.1

## Alternative: Rollback

If the fix doesn't work:

```bash
cd ~/containers/quadlets
git restore *.container
systemctl --user daemon-reload
# Restart services
```

**Note:** This will restore the broken behavior (routing through monitoring network).

## Long-Term Considerations

1. **This is a Podman bug**, not a design flaw in your homelab
2. **The fix (interface_name) is the correct workaround** per Podman documentation
3. **Consider:** File issue with Fedora/Podman about kernel 6.18.7 regression
4. **Monitor:** Future Podman/kernel updates may need similar fixes
5. **Document:** Add this to ADR about network architecture assumptions

## Questions to Answer

- [ ] Why did this work before kernel 6.18.7?
- [ ] Is this a kernel regression or new Podman behavior?
- [ ] Should we pin kernel version to avoid future surprises?
- [ ] Do we need additional monitoring for network routing violations?

## Git Status

Modified files (not committed):
```
quadlets/alertmanager.container
quadlets/authelia.container
quadlets/grafana.container
quadlets/home-assistant.container
quadlets/immich-server.container
quadlets/jellyfin.container
quadlets/nextcloud.container
quadlets/prometheus.container
quadlets/traefik.container
```

**Commit these AFTER verifying the fix works.**
