# Catastrophic Network Failure - Investigation and Analysis

**Date:** 2026-02-02
**Status:** CRITICAL FAILURE - Services disabled
**Severity:** P0 - Security issue (internal networks exposed to Internet)

---

## Executive Summary

After kernel upgrade from 6.17.12 → 6.18.7 and system reboot on Feb 2 00:45, multi-network Podman containers began routing traffic through incorrect networks, exposing internal monitoring network to Internet traffic via Traefik. All services have been stopped and disabled to prevent security exposure.

**Impact:**
- All homelab services offline since 17:30 CET
- Security boundary violation (monitoring network exposed)
- SSH remote management inadequate for systemd user service control

---

## Timeline

### Feb 1, 2026
- **23:39:** DNF update executed (395 packages including kernel 6.18.7)
- **23:59:** No issues reported, system running normally on kernel 6.17.12

### Feb 2, 2026
- **00:45:** System rebooted into kernel 6.18.7-200.fc43.x86_64
- **00:46:** All services started automatically
- **01:35:** **FIRST ERROR:** Home Assistant logs "untrusted proxy 10.89.4.10"
- **Throughout day:** Intermittent 400 errors on ha.patriark.org
- **13:40:** User discovers issue remotely via SSH
- **13:40-17:30:** Multiple failed fix attempts (see Investigation section)
- **17:30:** All services stopped and disabled

---

## Root Cause Analysis

### The Problem

**Symptom:** Traefik connecting to backend services (home-assistant, jellyfin, nextcloud, etc.) via monitoring network (10.89.4.x) instead of reverse_proxy network (10.89.2.x).

**Result:** Home Assistant's `trusted_proxies` check rejects connections from 10.89.4.x, returning HTTP 400.

**Security Impact:** Internal monitoring network handling Internet traffic - violates network segmentation architecture.

### Technical Root Cause

**Podman/netavark DNS behavior in multi-network containers:**

1. **Network attachment order is undefined** (Podman Issue #12850)
   - Quadlet declares: `Network=systemd-reverse_proxy`, then `systemd-auth_services`, then `systemd-monitoring`
   - Actual interface creation order: eth2 (monitoring), eth0 (reverse_proxy), eth1 (auth)
   - Order is NOT alphabetical, NOT declaration order, appears random/kernel-dependent

2. **DNS nameserver order is random** (Podman Issue #14262 - WONT_FIX)
   - Each network has its own aardvark-dns server (10.89.2.1, 10.89.3.1, 10.89.4.1)
   - Container's `/etc/resolv.conf` lists all three in undefined order
   - Nameserver order varies between container starts

3. **DNS servers return all IPs in undefined order**
   - Query: `nslookup home-assistant`
   - Each DNS server returns ALL IPs: 10.89.2.x, 10.89.4.x, 10.89.6.x
   - Order of returned IPs is random/undefined
   - Client uses FIRST IP returned

4. **Kernel 6.18.7 changed network namespace initialization timing**
   - This changed the "random" order
   - What was working by luck on 6.17.12 broke on 6.18.7

### Why It Worked Before

**Pure luck.** The random DNS ordering happened to return reverse_proxy IPs first under kernel 6.17.12. Kernel 6.18.7 changed timing, causing monitoring IPs to be returned first.

**Evidence:**
- Zero "untrusted proxy" errors Jan 28-31, Feb 1 (before reboot)
- First error at Feb 2 01:35 (55 minutes after reboot into 6.18.7)
- Identical quadlet configuration both days

---

## Investigation Attempts (All Failed)

### Attempt 1: Add `interface_name` parameter (14:00-15:30)
```ini
Network=systemd-reverse_proxy:interface_name=eth0
Network=systemd-auth_services:interface_name=eth1
Network=systemd-monitoring:interface_name=eth2
```

**Result:** FAILED
- ✅ Fixed interface naming (eth0, eth1, eth2 now predictable)
- ❌ Did NOT fix DNS nameserver order (still random)
- ❌ Did NOT fix default route metrics (all metric 100)
- ❌ Did NOT fix which IP DNS returns first

**Conclusion:** `interface_name` only controls interface names, not DNS or routing behavior.

### Attempt 2: Remove services from monitoring network (15:30-16:00)
**Rejected by user** - Violates architecture. Services NEED to be on monitoring network for Prometheus scraping. This was not a problem yesterday; removing networks is not the solution.

### Attempt 3: Explicit DNS configuration (16:00-17:00)
```ini
DNS=10.89.2.1  # Force reverse_proxy DNS first
DNS=192.168.1.69
```

**Result:** FAILED
- Podman/netavark IGNORED explicit DNS directive
- Still generated /etc/resolv.conf with network DNS servers
- Still random order

### Attempt 4: Query specific DNS server (17:00-17:30)
Attempted to configure Traefik to query 10.89.2.1 specifically.

**Result:** FAILED - No mechanism in Traefik or Podman to force specific DNS server for service discovery.

---

## What Was Learned

### Confirmed Facts

1. **Podman Issue #12850 is REAL and UNFIXED**
   - Network attachment order is undefined
   - Not alphabetical, not declaration order
   - Likely hash-map or kernel-dependent ordering

2. **Podman Issue #14262 is WONT_FIX by design**
   - DNS nameserver order in multi-network containers is random
   - Stored in maps (unordered data structure)
   - Maintainers closed as "working as designed"

3. **Kernel version affects network namespace behavior**
   - Kernel 6.17.12: Worked (by luck)
   - Kernel 6.18.7: Broken (random order changed)
   - No kernel regression - Podman behavior was always undefined

4. **`interface_name` parameter is NOT the solution**
   - Only controls interface naming
   - Does not control DNS order
   - Does not control route metrics
   - Does not solve the architectural problem

### Architecture Validation

**User's architecture is CORRECT:**
- Services SHOULD be on multiple networks
- Monitoring network IS needed for Prometheus scraping
- Reverse_proxy network IS needed for Traefik routing
- Network segmentation design is sound

**Problem is NOT the architecture - it's Podman's undefined behavior.**

---

## Actual Solutions (Not Yet Implemented)

### Option 1: Explicit IPs in Traefik Backend Config (Recommended)

**Approach:** Configure Traefik service backends with explicit reverse_proxy IPs instead of DNS names.

```yaml
# config/traefik/dynamic/routers.yml
http:
  services:
    home-assistant:
      loadBalancer:
        servers:
          - url: "http://10.89.2.67:8123"  # Explicit reverse_proxy IP
```

**Pros:**
- ✅ Guarantees correct network path
- ✅ No DNS ambiguity
- ✅ Maintains security boundaries
- ✅ Simple to implement

**Cons:**
- ❌ Breaks DNS-based service discovery
- ❌ IPs change if containers restart
- ❌ Manual updates needed for IP changes
- ❌ Violates ADR-016 principle of DNS-based discovery

### Option 2: Network Aliases with Priority

**Approach:** Use network-specific aliases like `home-assistant.reverse_proxy` to force DNS resolution to specific network.

**Status:** UNKNOWN if Podman supports this. Needs research.

### Option 3: Pin to Kernel 6.17.12

**Approach:** Revert to kernel 6.17.12 and pin it to prevent upgrades.

**Pros:**
- ✅ Restores working state immediately

**Cons:**
- ❌ Misses security updates
- ❌ Band-aid solution (problem remains)
- ❌ Not sustainable long-term

### Option 4: Wait for Podman Fix

**Approach:** Monitor Podman Issues #12850 and #14262, wait for upstream fix.

**Status:** #14262 closed as WONT_FIX (by design). #12850 open since 2022, low priority.

**Timeline:** Unknown, likely 6+ months if ever.

---

## SSH/SystemD Remote Access Issue

**Secondary failure:** Could not manage systemd user services via SSH + WireGuard.

**Status:** Needs separate investigation. Current session DOES have XDG_RUNTIME_DIR and systemctl --user works locally. Need to understand why remote SSH session couldn't access user services.

**Impact:** Unable to restart services or apply fixes remotely. Required physical access.

---

## Current System State

**Services:** All stopped and disabled
```bash
systemctl --user list-unit-files | grep enabled | grep -E "traefik|home-assistant|jellyfin"
# Returns: (none)
```

**Quadlets:** Reverted to 2026-02-01 working configuration (without interface_name)

**Git status:** Modified files NOT committed (system is broken, should not be committed)

**Ports:** 80/443 not listening (verified)

**Security:** Internal networks NOT exposed (services offline)

---

## Next Steps (When Ready to Fix)

1. **Research Podman network aliases** - Check if we can use `.reverse_proxy` FQDN suffix
2. **Test explicit IP solution** - Update routers.yml with static IPs, test thoroughly
3. **Consider IP reservation** - Explore Podman static IP assignment per network
4. **Investigate systemd RemainAfterExit** - May help with SSH service management
5. **Document proper fix in ADR** - Once solution proven, document architectural decision
6. **Add network validation to CI** - Automated testing of network routing paths
7. **Create monitoring alert** - Detect when services route via wrong networks

---

## Lessons Learned

### What Went Wrong

1. **Assumed kernel upgrade was safe** - Kernel changes CAN affect container networking
2. **Relied on undefined behavior** - Network order was always random, we got lucky
3. **No validation of network routing** - Should have detected wrong-network routing immediately
4. **Insufficient remote management** - SSH couldn't handle systemd user services
5. **Thrashing on fixes** - Tried multiple solutions without understanding root cause first

### What Went Right

1. **Home Assistant security worked** - `trusted_proxies` caught the violation
2. **Snapshots available** - Could compare working vs broken configs
3. **Git tracking** - Easy to revert changes
4. **Fail-safe shutdown** - Could disable all services to prevent exposure

### Process Improvements Needed

1. **Pre-reboot validation** - Test network routing after kernel updates, before reboot
2. **Automated routing checks** - Script to verify services route via correct networks
3. **Remote management testing** - Ensure SSH can manage all services before relying on it
4. **Staging environment** - Test kernel upgrades in VM before production
5. **Monitoring for this specific issue** - Alert if trusted_proxies violations occur

---

## References

- **Podman Issue #12850:** Networks attach alphabetically, not in declaration order
  https://github.com/containers/podman/issues/12850

- **Podman Issue #14262:** DNS nameserver order is random (WONT_FIX)
  https://github.com/containers/podman/issues/14262

- **Snapshot:** `/home/patriark/.snapshots/htpc-home/20260201-htpc-home/`

- **Kernel changelog:** `rpm -q --changelog kernel-6.18.7-200.fc43.x86_64`

---

## Conclusion

This was a **catastrophic failure** caused by relying on undefined Podman behavior that happened to work under kernel 6.17.12 but broke under 6.18.7. The architecture is sound; the tooling (Podman/netavark) has fundamental limitations in multi-network scenarios.

**The homelab is currently OFFLINE and SAFE.** Services will remain disabled until a proper, tested solution is implemented.

This incident has severely damaged confidence in:
- Podman's multi-network reliability
- Kernel upgrade safety
- Remote management capabilities
- My (Claude's) debugging approach (too much thrashing, not enough systematic thinking)

**Recovery time:** Unknown. Will require careful testing of any solution before re-enabling Internet exposure.

---

## Addendum: Further Investigation (18:00-19:00)

### Additional Hypotheses Investigated

**Network creation order theory:**
- Investigated whether network creation timestamps (reverse_proxy: Oct 2025, monitoring: Nov 2025, auth_services: Jan 2026) affected attachment order
- Theory: Kernel 6.17.12 might have used creation-time ordering, 6.18.7 changed to different mechanism
- **Rejected:** Highly speculative, no evidence to support this mechanism

**Symlink/directory mismatch theory:**
- Investigated potential conflicts between old `.service` files in `~/.config/containers/systemd/` (from before Jan 28 symlink migration) and current `.container` files
- Found 29 old `.service` files dated Jan 9, but systemd correctly loads from generated files in `/run/user/1000/systemd/generator/`
- **Rejected:** Symlinks working correctly, old files are just leftover cruft

**Configuration drift theory:**
- Compared quadlet configurations across snapshots from Jan 28-Feb 1
- Network order has been identical: `Network=systemd-reverse_proxy` first, consistently
- **Rejected:** No configuration changes between working (Feb 1) and broken (Feb 2) states

### What We Confirmed

1. **Podman version unchanged:** 5.7.1 since Dec 21 (NOT updated on Feb 1)
2. **Configuration identical:** Exact same quadlets from Jan 28-Feb 1 (working period)
3. **Only kernel changed:** 6.17.12 → 6.18.7 is the ONLY system change
4. **Consistent behavior pre-upgrade:** No "untrusted proxy" errors Jan 28-Feb 1
5. **Immediate failure post-upgrade:** First error 55 minutes after reboot into 6.18.7

### Current Status

**The root cause remains unknown.** While kernel 6.18.7 is the only changed component and correlates perfectly with the failure, we have not identified the specific kernel change that broke network ordering in Podman containers.

The homelab remains **offline and disabled** until a reliable fix can be identified and tested.

### Lessons Learned (Updated)

- Correlation (kernel upgrade) does not equal causation without mechanism
- "Working consistently" ≠ "working correctly" - the behavior may have always been fragile
- Need better diagnostic tools to understand Podman network attachment order
- Container networking debugging requires kernel-level visibility we don't currently have

**Next actions:** None planned. System will remain offline indefinitely.
