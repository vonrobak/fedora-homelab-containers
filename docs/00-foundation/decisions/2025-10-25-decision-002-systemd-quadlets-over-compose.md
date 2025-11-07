# ADR-002: Systemd Quadlets Over Docker Compose

**Date:** 2025-10-25
**Status:** Accepted
**Decided by:** System architect

---

## Context

After successfully deploying Traefik using `podman generate systemd`, the question arose: **What's the best way to manage container orchestration in this homelab?**

### Available Options

1. **Docker Compose / Podman Compose**
   - Industry standard for multi-container applications
   - YAML-based service definitions
   - Single command deployment (`docker-compose up`)

2. **Systemd Quadlets**
   - Native Podman integration with systemd
   - `.container`, `.network`, `.volume` files
   - First-class systemd citizen

3. **Kubernetes / K3s**
   - Production-grade orchestration
   - Powerful but complex
   - Overkill for homelab scale

4. **Shell Scripts + `podman run`**
   - Maximum flexibility
   - No abstraction layer
   - Manual dependency management

---

## Decision

**We will use systemd quadlets for all service orchestration.**

Container definitions will be written as `.container` files in `~/.config/containers/systemd/`, managed through native systemd commands.

---

## Rationale

### Native Integration

**Systemd is already managing the system** - why add another orchestration layer?

- Quadlets integrate with systemd's dependency management (`After=`, `Requires=`)
- Health checks map to systemd service status
- Logging through journald (unified with system logs)
- Resource limits via systemd directives
- Socket activation support

### Learning Value

This is a **learning-focused homelab**. Systemd is:
- Used in every enterprise Linux environment
- Fundamental to understanding modern Linux
- Directly applicable to production systems
- More valuable skill than docker-compose

### Operational Benefits

**Discoverability:**
```bash
systemctl --user status                  # See all services
journalctl --user -u traefik.service     # Unified logging
```

**Dependency management:**
```ini
[Unit]
After=network-online.target traefik.service
Requires=monitoring-network.service
```

**Automatic restart policies:**
```ini
[Service]
Restart=on-failure
TimeoutStartSec=300
```

### Infrastructure as Code

Quadlet files are:
- Plain text configuration
- Version controlled in git
- Self-documenting (human-readable)
- Portable across Fedora systems

---

## Consequences

### What Becomes Easier

✅ **Service dependencies:** Native systemd dependency graph
✅ **Log aggregation:** All logs in journald, queryable with journalctl
✅ **Resource limits:** CPU/memory limits via systemd directives
✅ **Auto-start on boot:** Standard systemd enable/disable
✅ **Health monitoring:** systemd service status reflects container health
✅ **Debugging:** familiar systemd tools (`systemctl`, `journalctl`)

### What Becomes More Complex

⚠️ **Multi-container apps:** Each container is separate service (vs single docker-compose.yml)
⚠️ **Initial learning curve:** Need to learn quadlet syntax
⚠️ **No visual UI:** CLI-only management (vs Portainer, etc.)

### Accepted Trade-offs

- **Slightly more files** (one per container) for **better modularity**
- **Learning systemd specifics** for **transferable skills**
- **Fedora/RHEL specific** for **production-grade approach**

---

## Alternatives Considered

### Alternative 1: Docker Compose / Podman Compose

**Pros:**
- Industry standard, widely documented
- Single file per application stack
- Easier to share configurations
- GUI tools available (Portainer)

**Cons:**
- Another layer of abstraction on top of systemd
- Compose daemon must be running
- Logs not in journald by default
- Doesn't leverage systemd's capabilities
- Less transferable to enterprise environments

**Verdict:** ❌ Rejected - Adds unnecessary abstraction layer

### Alternative 2: Kubernetes (K3s, MicroK8s)

**Pros:**
- Production-grade orchestration
- Powerful features (rolling updates, service mesh, etc.)
- Industry-relevant skill

**Cons:**
- Massive overkill for <20 containers
- Resource overhead (control plane, etcd)
- Complex debugging
- Hides underlying container mechanics

**Verdict:** ❌ Rejected - Too complex for current scale, can revisit at 50+ containers

### Alternative 3: Shell Scripts

**Pros:**
- Maximum flexibility
- No framework to learn
- Easy to understand

**Cons:**
- No automatic restart on failure
- Manual dependency management
- Reinventing orchestration primitives
- Error-prone
- Not infrastructure as code

**Verdict:** ❌ Rejected - Loses all benefits of orchestration

### Alternative 4: Generated systemd units (`podman generate systemd`)

**Pros:**
- Works with existing containers
- No new syntax to learn

**Cons:**
- Two-step process (create container, then generate)
- Generated files are verbose and ugly
- Loses some systemd integration benefits
- Not as maintainable as hand-crafted quadlets

**Verdict:** ⚠️ Used initially, then **evolved to quadlets** - This is the stepping stone to quadlets

---

## Implementation Guidelines

### File Organization

```
~/.config/containers/systemd/
├── traefik.container
├── jellyfin.container
├── prometheus.container
├── monitoring.network
└── reverse_proxy.network
```

### Naming Convention

- **Containers:** `<service-name>.container`
- **Networks:** `<network-name>.network`
- **Volumes:** `<volume-name>.volume`

### Standard Quadlet Template

```ini
[Unit]
Description=<Service Name>
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/<image>:<tag>
ContainerName=<service-name>
Network=systemd-<network>.network
Volume=%h/containers/config/<service>:/config:Z
Environment=KEY=value

HealthCmd=<health check command>
HealthInterval=30s

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### Deployment Workflow

```bash
# 1. Create quadlet file
nano ~/.config/containers/systemd/newservice.container

# 2. Reload systemd to recognize new quadlet
systemctl --user daemon-reload

# 3. Start and enable service
systemctl --user enable --now newservice.service

# 4. Verify
systemctl --user status newservice.service
```

---

## Migration Path

### Phase 1: Foundation (Complete ✅)
- Started with `podman run` + `generate systemd`
- Learned container basics without framework complexity

### Phase 2: Quadlet Adoption (Complete ✅)
- Converted Traefik to quadlet (day 6)
- Learned quadlet syntax and benefits
- Established patterns and templates

### Phase 3: Standardization (Current)
- All new services deployed as quadlets
- Migrating remaining generated units to quadlets
- Documenting best practices

### Phase 4: Optimization (Future)
- Advanced systemd features (socket activation, etc.)
- Automated quadlet generation tools
- Multi-host deployment (if needed)

---

## Validation

### Success Criteria

- [x] All services managed through systemd --user
- [x] Services auto-start on boot
- [x] Health checks integrated with systemd status
- [x] Dependency management working (networks before containers)
- [x] Logs available through journalctl

### Current Status (2025-11-07)

**12 services running as quadlets:**
- traefik, jellyfin, tinyauth, crowdsec
- prometheus, grafana, loki, promtail, node_exporter, cadvisor
- alertmanager, alert-discord-relay

**All services:**
- ✅ Auto-start on boot (enabled)
- ✅ Auto-restart on failure
- ✅ Health checks working
- ✅ Proper dependency ordering
- ✅ Clean journald integration

---

## Known Issues and Solutions

### Issue 1: Network Dependencies

**Problem:** Containers may start before their networks exist

**Solution:**
```ini
[Unit]
After=network-online.target monitoring-network.service
Requires=monitoring-network.service
```

### Issue 2: First Network is Default Route

**Problem:** Multiple networks = ambiguous default route

**Solution:** First `Network=` directive sets default route
```ini
Network=systemd-reverse_proxy.network  # Gets default route
Network=systemd-monitoring.network      # Additional network
```

### Issue 3: Quadlet Syntax Errors Are Silent

**Problem:** Typos in quadlet files silently fail

**Solution:** Always check after daemon-reload:
```bash
systemctl --user daemon-reload
systemctl --user status service.service  # Check for errors
```

---

## References

- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Systemd Unit File Documentation](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- Repository: `docs/10-services/decisions/2025-10-25-decision-001-quadlets-vs-generated-units.md`

---

## Retrospective (2025-11-07)

**Assessment after 2 weeks of operation:**

✅ **Excellent Decision** - Quadlets are the right abstraction level

**What Worked Well:**
- Service management feels natural (`systemctl --user`)
- Dependency management is bulletproof
- journalctl integration is invaluable for debugging
- Git-tracked configuration is clean and maintainable

**Unexpected Benefits:**
- systemd's timer units for scheduled tasks (backup automation)
- Resource limiting is straightforward
- Multi-network support cleaner than expected
- Service restarts are instant (systemd optimizations)

**Challenges Overcome:**
- Initial syntax learning curve (1-2 days)
- Network ordering gotcha (documented in ADR)
- Took time to build good templates

**Compared to docker-compose experience:**
- **Better:** Logging, dependencies, system integration
- **Same:** Configuration as code, deployment simplicity
- **Different:** One file per service vs stack files (preference)

**Would we make the same decision again?** 💯 **Yes.**

In fact, I would recommend quadlets as the **default choice** for Fedora-based homelabs. The systemd integration is just too good to pass up.
