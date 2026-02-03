# ADR-017: Static IP Assignment for Multi-Network Services

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

**1. Static IPs in quadlets:**
```ini
# Example: home-assistant.container
Network=systemd-reverse_proxy.network:ip=10.89.2.8
Network=systemd-home_automation.network:ip=10.89.6.3
Network=systemd-monitoring.network:ip=10.89.4.11
```

**2. Traefik hosts file override:**
```yaml
# config/traefik/hosts (mounted as /etc/hosts in Traefik)
10.89.2.8   home-assistant
10.89.2.10  authelia
10.89.2.9   grafana
# ... all backend services
```

**3. Traefik quadlet volume mount:**
```ini
Volume=%h/containers/config/traefik/hosts:/etc/hosts:ro,Z
```

### IP Allocation

**Reverse Proxy Network (10.89.2.0/24):**
- `.8` - home-assistant
- `.9` - grafana
- `.10` - authelia
- `.11` - prometheus
- `.12` - immich-server
- `.13` - jellyfin
- `.14` - nextcloud
- `.15` - loki
- `.16` - gathio

**Rationale:** Reserved `.2-.7` for infrastructure (Traefik, CrowdSec), `.8+` for backend services.

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

## References

- Investigation: `docs/98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md`
- Verification: `docs/98-journals/2026-02-04-reboot-verification-success.md`
- PR #77: Resolve Podman DNS resolution ordering
- PR #78: Complete network IP configuration audit
- Podman issue #14262: DNS nameserver order is random (WONT_FIX)
- Podman issue #12850: Network attachment order undefined
