# ADR-001: Rootless Podman Containers

**Date:** 2025-10-20
**Status:** Accepted
**Decided by:** System architect

---

## Context

When building a homelab with containerized services, there are two primary approaches:
1. **Rootful containers:** Run containers as root user (traditional Docker approach)
2. **Rootless containers:** Run containers as unprivileged user (Podman's security-focused approach)

### The Security Question

Running containers as root means:
- Processes inside containers run as root on the host
- Container escape vulnerabilities could lead to full system compromise
- No isolation between container processes and host system
- Single point of failure for security

### The Trade-off

Rootless containers provide better security but introduce complexity:
- Port binding below 1024 requires workarounds
- Some volume mounts require special handling (`:Z` SELinux labels)
- Filesystem permissions can be tricky (UID mapping)
- Not all container images work out-of-the-box

---

## Decision

**We will use rootless Podman containers for all services in this homelab.**

All container processes will run as user `patriark` (UID 1000), not as root.

---

## Rationale

### Security Benefits
1. **Principle of Least Privilege:** Containers run with minimal necessary permissions
2. **Isolation:** Container processes cannot access host resources without explicit permission
3. **Defense in Depth:** Even if container is compromised, attacker gains unprivileged user access only
4. **SELinux Enforcement:** Works seamlessly with Fedora's SELinux mandatory access control

### Learning Value
- Understanding Linux user namespaces and UID mapping
- Working with SELinux in enforcing mode
- Proper security architecture from the start

### Practical Benefits
- No sudo required for container operations
- User-level systemd services (`systemctl --user`)
- Clear separation between system and user services
- Better multi-user homelab possibility in future

---

## Consequences

### What Becomes Easier
✅ **Security auditing:** All containers run as single unprivileged user
✅ **Permission management:** Clear UID/GID ownership model
✅ **System stability:** Container issues can't affect root-level services
✅ **Compliance:** Aligns with security best practices

### What Becomes More Complex
⚠️ **Port binding:** Ports below 1024 require reverse proxy (led to ADR-003: Traefik)
⚠️ **Volume permissions:** Must use `:Z` SELinux labels on volumes
⚠️ **UID mapping:** Some images expect root, need configuration adjustment
⚠️ **Debugging:** Need to understand user namespaces for troubleshooting

### Accepted Trade-offs
- **Slightly more complex setup** for **significantly better security**
- **Learning curve for newcomers** for **production-grade architecture**
- **Occasional permission debugging** for **peace of mind**

---

## Alternatives Considered

### Alternative 1: Rootful Containers
**Pros:**
- Simpler initial setup
- Bind to any port directly
- More container images work without modification

**Cons:**
- Significant security risk (containers run as root)
- Single point of failure
- Harder to apply principle of least privilege

**Verdict:** ❌ Rejected - Security risk too high for production homelab

### Alternative 2: Hybrid (Some Rootful, Some Rootless)
**Pros:**
- Flexibility for problematic containers

**Cons:**
- Inconsistent security model
- Confusion about which approach to use when
- Two separate Podman instances to manage

**Verdict:** ❌ Rejected - Consistency and simplicity more valuable

### Alternative 3: Virtual Machines Instead of Containers
**Pros:**
- Strong isolation
- No container security concerns

**Cons:**
- Much higher resource usage
- Slower deployment
- Less flexible than containers

**Verdict:** ❌ Rejected - Overkill for homelab, containers provide good enough isolation

---

## Implementation Notes

### Port Binding Solution
- Use Traefik reverse proxy on ports 80/443 with `NET_BIND_SERVICE` capability
- All services bind to high ports (>1024)
- External access through Traefik only

### Volume Permissions
- Always use `:Z` SELinux label on bind mounts: `-v /path:/container/path:Z`
- Use `podman unshare chown` to set correct ownership from host perspective
- Create volumes with correct permissions before first container start

### systemd Integration
- User services in `~/.config/systemd/user/`
- Enable linger: `loginctl enable-linger patriark`
- Use `systemctl --user` for all operations

---

## Validation

### Success Criteria
- [x] All services run as unprivileged user
- [x] No sudo required for day-to-day operations
- [x] SELinux remains in enforcing mode
- [x] Services survive system reboot

### Metrics
- Security: ✅ All processes run as UID 1000
- Functionality: ✅ All services operational (Traefik, Jellyfin, Monitoring stack)
- Performance: ✅ No measurable overhead vs rootful
- Maintainability: ✅ systemd --user integration working perfectly

---

## References

- [Podman Rootless Documentation](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Red Hat: Why rootless containers matter](https://www.redhat.com/en/blog/why-rootless-containers-matter-security)
- Related ADRs: ADR-002 (Systemd Quadlets), ADR-003 (Traefik Reverse Proxy)

---

## Retrospective (2025-11-07)

**Assessment after 3 weeks of operation:**

✅ **Correct Decision** - Zero security incidents, smooth operations
- No regrets about the complexity trade-off
- UID mapping issues were minimal after initial learning
- SELinux integration works flawlessly
- System feels more professional and secure

**Unexpected Benefits:**
- User-level systemd made service management cleaner than expected
- No conflicts with system-level services
- Easy to back up entire container infrastructure (it's all in ~/.local/share/containers)

**Lessons Learned:**
- Document the `:Z` label requirement prominently (caused initial confusion)
- `podman unshare` is your friend for permission debugging
- Most "rootful-only" images actually work rootless with minor config tweaks

**Would we make the same decision again?** 💯 **Absolutely yes.**
