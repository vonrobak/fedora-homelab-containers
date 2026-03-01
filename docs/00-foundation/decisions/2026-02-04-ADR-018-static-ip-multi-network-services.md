# ADR-018: Static IP Assignment for Multi-Network Services

**Status:** Accepted
**Date:** 2026-02-04
**Context:** Podman's DNS resolution ordering is undefined, causing intermittent routing failures

---

## Context

Podman's aardvark-dns returns container IP addresses in undefined order when containers attach to multiple networks. The order depends on hash functions, memory layout, and kernel timing—not declaration order or network names.

**Impact:** When monitoring network IPs are resolved before reverse_proxy IPs, Traefik routes traffic through the monitoring network, violating trusted_proxies configuration. This caused persistent "400 Bad Request - untrusted proxy" errors in Home Assistant and other services.

**Upstream:** Podman maintainers closed [issue #14262](https://github.com/containers/podman/issues/14262) as WONT_FIX—undefined DNS ordering is considered acceptable behavior.

## Decision

**Use static IP assignments for all multi-network services, combined with Traefik /etc/hosts override.**

### Implementation

**1. Static IPs in quadlets (.69+ range, consistent last octet):**
```ini
# Example: home-assistant.container
Network=systemd-reverse_proxy:ip=10.89.2.76
Network=systemd-home_automation:ip=10.89.6.76
Network=systemd-monitoring:ip=10.89.4.76
```

**2. IPAM lease range in network quadlets (.2-.68 for dynamic allocation):**
```ini
# Example: reverse_proxy.network
[Network]
Subnet=10.89.2.0/24
Gateway=10.89.2.1
IPRange=10.89.2.2-10.89.2.68
```

**3. Traefik hosts file override:**
```yaml
# config/traefik/hosts (mounted as /etc/hosts in Traefik)
10.89.2.76  home-assistant
10.89.2.78  authelia
10.89.2.77  grafana
# ... all backend services
```

**3. Traefik quadlet volume mount:**
```ini
Volume=%h/containers/config/traefik/hosts:/etc/hosts:ro,Z
```

### IP Allocation Convention

**Dynamic range:** `.2-.68` — reserved for Podman's IPAM auto-allocation (containers without static IPs).
Enforced via `IPRange=` / `lease_range` on all 8 networks.

**Static range:** `.69-.254` — assigned explicitly in quadlet files for multi-network containers.
Each service uses a **consistent last octet across all networks** for easy identification.

**Allocation table (reverse_proxy network shown, same last octet on all networks):**

| IP | Service | Networks |
|---|---|---|
| .69 | traefik | reverse_proxy, auth_services, monitoring |
| .70 | crowdsec | reverse_proxy |
| .71 | vaultwarden | reverse_proxy |
| .72 | alertmanager | reverse_proxy, monitoring |
| .73 | homepage | reverse_proxy |
| .74 | audiobookshelf | reverse_proxy |
| .75 | navidrome | reverse_proxy, monitoring |
| .76 | home-assistant | reverse_proxy, home_automation, monitoring |
| .77 | grafana | reverse_proxy, monitoring |
| .78 | authelia | reverse_proxy, auth_services |
| .79 | prometheus | reverse_proxy, monitoring |
| .80 | immich-server | reverse_proxy, photos, monitoring |
| .81 | jellyfin | reverse_proxy, media_services, monitoring |
| .82 | nextcloud | reverse_proxy, nextcloud, monitoring |
| .83 | loki | reverse_proxy, monitoring |
| .84 | gathio | reverse_proxy, gathio, monitoring |
| .85 | qbittorrent | reverse_proxy |
| .86 | alert-discord-relay | reverse_proxy, monitoring |
| .87 | unpoller | reverse_proxy, monitoring |

**Next available:** `.88`

**Why .69+?** The dynamic IPAM range starts at `.2` and allocates sequentially. With a hard
boundary at `.68`, even 67 dynamic containers per network cannot collide with static assignments.
This prevents the IPAM collision failure observed on 2026-03-01 where a dynamically assigned IP
blocked a static IP container from starting (7h outage).

## Consequences

### Positive

**Predictable routing:** Traefik always connects via reverse_proxy network, regardless of DNS query order.

**DNS bypass:** /etc/hosts takes precedence over aardvark-dns (per standard `hosts: files dns` in /etc/nsswitch.conf).

**Network segmentation preserved:** Monitoring network remains isolated from Internet traffic.

**Persistent:** Static IPs and volume mounts survive container restarts and system reboots (verified 2026-02-04).

### Negative

**Manual IP management:** Must allocate IPs when adding services (low overhead, 9 services currently).

**Tight coupling:** Traefik hosts file must stay synchronized with quadlet IPs (mitigated by deployment patterns).

**No auto-discovery:** Can't leverage Podman's dynamic DNS for new services (acceptable trade-off for stability).

### Neutral

**Podman version dependency:** Requires `Network=name:ip=X` syntax (supported since Podman 4.x, currently on 5.7.1).

**IP allocation burden:** Minimal (9 services, infrequent additions).

## Alternatives Considered

**1. Single network per container:** Eliminates multi-network DNS issues but breaks network segmentation design.

**2. Docker migration:** Solves Podman-specific issues but requires complete infrastructure rewrite.

**3. Manual routing in Traefik config:** Possible but more verbose and error-prone than /etc/hosts.

**4. Accept undefined behavior:** Unacceptable—intermittent failures violate reliability requirements.

## Verification

**Tested:** Container restarts, systemd daemon-reload, full system reboot (kernel 6.18.7).
**Result:** Zero "untrusted proxy" errors for 12+ minutes post-reboot (previously ~50 errors/minute).
**Status:** Production-ready, fully persistent.

## Amendments

### 2026-03-01: .69+ Convention and IPAM Lease Range

**Problem:** During overnight update, `redis-immich` (no static IP) was dynamically assigned
`10.89.5.5`—the same IP statically assigned to `immich-server`. This caused a 7h outage because
the static IPs (.8-.16) were in the dynamic IPAM allocation range.

**Changes:**
1. All static IPs migrated to `.69+` with consistent last octet per service
2. `IPRange=` added to all 8 network quadlets restricting dynamic allocation to `.2-.68`
3. Runtime network configs updated with `lease_range` (takes effect without network recreation)

**PR:** #109

## References

- Investigation: `docs/98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md`
- Verification: `docs/98-journals/2026-02-04-reboot-verification-success.md`
- PR #77: Resolve Podman DNS resolution ordering
- PR #78: Complete network IP configuration audit
- PR #109: Static IP .69+ convention and IPAM lease range enforcement
- Podman issue #14262: DNS nameserver order is random (WONT_FIX)
- Podman issue #12850: Network attachment order undefined
