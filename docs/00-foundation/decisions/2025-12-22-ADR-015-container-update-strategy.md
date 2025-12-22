# ADR-015: Container Update Strategy for State-of-the-Art Homelab

**Status:** Accepted
**Date:** 2025-12-22
**Context:** Single-user homelab on Fedora Workstation with robust backup infrastructure

---

## Context

This homelab runs on Fedora Workstation 42 as a desktop media center, requiring frequent system updates and reboots. Key characteristics:

- **Single-user environment** - Impact radius limited to one user
- **Physical access** - Direct console access for damage control
- **Remote access** - WireGuard VPN + SSH for remote troubleshooting
- **Robust backups** - Automated BTRFS snapshots + 3-2-1 backup strategy
- **Learning-focused** - Values state-of-the-art software over conservative stability
- **Desktop workstation** - Already requires frequent updates (kernel, graphics drivers, etc.)

**The Question:** Should we pin container versions for predictability, or use `:latest` tags for automatic security updates?

## Decision

**Use `:latest` tags for most services, with strategic pinning only for databases and services with known breaking changes.**

### Services Using `:latest` Tags

**Infrastructure:**
- Traefik (reverse proxy)
- Authelia (SSO/MFA)
- CrowdSec (security)
- Redis (cache/session storage)
- Valkey (cache)

**Monitoring:**
- Prometheus
- Grafana
- Loki
- Promtail
- Alertmanager
- Node Exporter
- cAdvisor

**Applications:**
- Jellyfin (media server)
- Vaultwarden (password manager)
- Homepage (dashboard)
- Collabora (office suite)

### Services Using Pinned Versions

**Databases** (require manual migration between major versions):
- PostgreSQL: `14-vectorchord0.4.3-pgvectors0.2.0` (Immich vector extensions)
- MariaDB: `11` (major version only, gets minor updates)

**Complex Multi-Container Apps** (tight version coupling):
- Immich server: `v2.3.1` (must match ML + postgres versions)
- Immich ML: `v2.3.1` (model compatibility)

**Optional** (if stability issues arise):
- Nextcloud: `30` (major version only, app compatibility)

## Operational Workflow

### Before System Updates (DNF + Reboot)

```bash
# Run update script
~/containers/scripts/update-before-reboot.sh

# Update Fedora system
sudo dnf update -y

# Reboot
sudo reboot
```

### After Reboot

```bash
# Check system health
~/containers/scripts/homelab-intel.sh

# If issues detected, rollback via BTRFS snapshot
# (snapshots are automated daily, manual snapshots available)
```

### Monthly: Review Pinned Versions

```bash
# Check for updates to pinned services
podman images | grep -E "immich|postgres|mariadb|nextcloud"

# Review release notes
# Update quadlet files if ready to upgrade
# Test in isolation before deploying
```

## Consequences

### Positive

✅ **Security-first:** Automatic security patches via latest tags
✅ **State-of-the-art:** Always running current software
✅ **Operational fit:** Aligns with Fedora rolling update model
✅ **Simple workflow:** Update containers + system together
✅ **Safe experimentation:** BTRFS snapshots enable instant rollback
✅ **Reduced maintenance:** No manual version tracking for 15+ services

### Negative

⚠️ **Potential breaking changes:** Updates may introduce bugs or incompatibilities
⚠️ **Troubleshooting complexity:** "What changed?" requires checking container logs
⚠️ **Database coupling:** Must carefully manage Immich + Postgres versions

### Mitigations

1. **Pre-update snapshots:** BTRFS snapshots before every update (automated)
2. **Health monitoring:** SLO dashboards detect issues immediately
3. **Quick rollback:** Single command to restore snapshot
4. **Quadlet definitions:** Infrastructure-as-code enables rapid rebuild
5. **Physical access:** Console available for worst-case recovery
6. **Remote access:** WireGuard + SSH for remote troubleshooting

## Rationale

**Why this differs from enterprise best practices:**

| Enterprise Production | Single-User Homelab |
|----------------------|---------------------|
| Delayed updates for stability | Immediate updates for security |
| Change control processes | Rapid experimentation |
| Multi-tenant impact | Single-user impact |
| 99.99% uptime SLOs | Learning > uptime |
| Conservative approach | State-of-the-art approach |

**Core principle:** In a homelab with robust backups and single-user impact, the security risk of running outdated software outweighs the stability risk of automatic updates.

## Alternatives Considered

### Alternative 1: Pin All Versions (Rejected)

**Pros:** Predictable behavior, controlled updates
**Cons:** Delayed security patches, high maintenance overhead
**Why rejected:** Security risk > stability risk for single-user homelab

### Alternative 2: All Latest (Rejected)

**Pros:** Maximum automation
**Cons:** Database version mismatches, Immich breaking changes
**Why rejected:** Databases need manual migration; Immich has tight version coupling

### Alternative 3: Automated Testing Before Update (Rejected)

**Pros:** Catch issues before production
**Cons:** Requires duplicate infrastructure, complex CI/CD
**Why rejected:** Over-engineering for single-user environment with instant rollback

## Review Schedule

- **Weekly:** Automated updates via update-before-reboot.sh (before DNF updates)
- **Monthly:** Review pinned versions for available updates
- **Quarterly:** Review this ADR for continued applicability

## References

- Fedora Workstation update philosophy: Rolling updates with stability
- BTRFS snapshot strategy: docs/20-operations/guides/backup-strategy.md
- SLO monitoring: docs/40-monitoring-and-documentation/guides/slo-framework.md
- BoltDB → SQLite migration discussion (2025-12-22): Deferred to Podman 5.8

---

**Decision made by:** User (patriark) + Claude Code discussion
**Supersedes:** Previous conservative approach in CLAUDE.md
