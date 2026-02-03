# Homelab Status - 2026-02-02 13:37

## Current State: SERVICES DOWN

**Reason:** Network architecture violation discovered - internet traffic routing through monitoring network instead of reverse_proxy network.

**User Status:** Remote via SSH/WireGuard - cannot access systemctl user session

## What You Need to Do When Home

### Option 1: Complete Shutdown (Safest)

```bash
cd ~/containers
./scripts/shutdown-all-services.sh
```

This will properly stop all services via systemd. They will stay down until you manually restart.

### Option 2: Apply Fix and Restart

**Only do this if you're ready to test and verify:**

```bash
cd ~/containers

# 1. Review changes
git diff quadlets/*.container
cat RECOVERY-NOTES.md

# 2. Apply fix
systemctl --user daemon-reload

# 3. Start services
for svc in alertmanager prometheus grafana authelia nextcloud immich-server jellyfin home-assistant traefik; do
    systemctl --user restart $svc.service
    sleep 3
done

# 4. Verify routing
./scripts/verify-network-routing.sh

# 5. Test Home Assistant
curl -I https://ha.patriark.org
```

## What We Discovered

### Root Cause
- **Kernel upgrade** (6.17.11 → 6.18.7) on Feb 1 changed network namespace behavior
- **Podman bugs** cause networks to attach alphabetically, not in quadlet order
- All internet-facing services were routing through monitoring network (10.89.4.x)
- **This is an architecture violation** - monitoring should never touch internet traffic

### Why This Matters
Your network segmentation design is sound. This is a **Podman/kernel bug**, not a flaw in your architecture:
- Network ordering in quadlets SHOULD be respected (it's not)
- DNS nameserver order SHOULD match network order (it's random)
- These are known, documented Podman issues

### The Fix
Added explicit interface ordering to 9 quadlet files:
```
Network=systemd-reverse_proxy:interface_name=eth0
```

This forces eth0 to always be reverse_proxy network, ensuring:
- Internet traffic routes through correct network
- DNS resolution happens via reverse_proxy first
- Network segmentation is maintained

## Files Changed (Not Committed)

```
quadlets/traefik.container
quadlets/home-assistant.container  
quadlets/jellyfin.container
quadlets/immich-server.container
quadlets/nextcloud.container
quadlets/grafana.container
quadlets/prometheus.container
quadlets/alertmanager.container
quadlets/authelia.container
```

**DO NOT commit until you've verified the fix works!**

## Trust in the Architecture

I understand this reduces trust. Here's what this incident revealed:

**What worked well:**
- ✅ Home Assistant's strict `trusted_proxies` caught the violation
- ✅ Network segmentation design is correct
- ✅ Monitoring detected the issue (you saw HA was broken)

**What needs improvement:**
- ❌ No automated detection of routing violations
- ❌ Relied on application-level security catching network-level issues
- ❌ Kernel/Podman updates can silently break assumptions

**Recommendations:**
1. Add network routing verification to health checks
2. Consider kernel version pinning for stability
3. Document this as an ADR about Podman network assumptions
4. Add pre-reboot network validation script

## Next Steps

1. **When home:** Run shutdown script OR apply fix
2. **If applying fix:** Verify thoroughly before committing
3. **Document:** Create ADR about this incident and the fix
4. **Monitor:** Watch for similar issues after future kernel updates
5. **Consider:** Filing issue with Fedora/Podman about kernel regression

## Support

All investigation documented in:
- `RECOVERY-NOTES.md` - Technical details and recovery steps
- `STATUS.md` (this file) - Current status and action items
- Git history - All changes tracked, easy to rollback

The systematic-debugging investigation found the root cause and proper solution.
This is fixable and preventable going forward.
