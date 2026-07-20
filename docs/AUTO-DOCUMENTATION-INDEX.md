# Documentation Index (Auto-Generated)

**Generated:** 2026-07-20 22:11:55 UTC
**Total Documents:** 66

---

## Quick Navigation

### Auto-Generated Documentation
- [Service Catalog](AUTO-SERVICE-CATALOG.md) - Current service inventory
- [Network Topology](AUTO-NETWORK-TOPOLOGY.md) - Network architecture diagrams
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) - Service dependencies and critical paths
- [This Index](AUTO-DOCUMENTATION-INDEX.md) - Complete documentation catalog

### Key Entry Points
- [CLAUDE.md](../CLAUDE.md) - Project instructions for Claude Code (START HERE)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Complete architecture overview
- [Autonomous Operations](20-operations/guides/autonomous-operations.md) - OODA loop automation

---

## Documentation by Category

### 00-foundation/ (26 documents)

**Fundamentals and core concepts**

**Guides:**
- [middleware-configuration.md](00-foundation/guides/middleware-configuration.md)
- [podman-fundamentals.md](00-foundation/guides/podman-fundamentals.md)
- [quadlets-vs-generated-units-comparison.md](00-foundation/guides/quadlets-vs-generated-units-comparison.md)

**Decisions (ADRs):**
- : [2025-10-20-decision-001-rootless-containers](00-foundation/decisions/2025-10-20-decision-001-rootless-containers.md)
- : [2025-10-25-decision-002-systemd-quadlets-over-compose](00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md)
- ADR-009: [2025-11-13-ADR-009-config-data-directory-strategy](00-foundation/decisions/2025-11-13-ADR-009-config-data-directory-strategy.md)
- ADR-016: [2025-12-31-ADR-016-configuration-design-principles](00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md)
- ADR-018: [2026-02-04-ADR-018-static-ip-multi-network-services](00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md)
- ADR-019: [2026-02-22-ADR-019-filesystem-permission-model](00-foundation/decisions/2026-02-22-ADR-019-filesystem-permission-model.md)
- ADR-020: [2026-03-21-ADR-020-daily-external-backups](00-foundation/decisions/2026-03-21-ADR-020-daily-external-backups.md)
- ADR-021: [2026-03-28-ADR-021-urd-backup-tool](00-foundation/decisions/2026-03-28-ADR-021-urd-backup-tool.md)
- ADR-022: [2026-04-16-ADR-022-traefik-socket-activation](00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md)
- ADR-023: [2026-04-21-ADR-023-monitoring-bind-propagation](00-foundation/decisions/2026-04-21-ADR-023-monitoring-bind-propagation.md)
- ADR-026: [2026-04-21-ADR-026-nextcloud-pinned-major-version](00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md)
- ADR-028: [2026-04-27-ADR-028-podman-secret-store-path-split](00-foundation/decisions/2026-04-27-ADR-028-podman-secret-store-path-split.md)
- ADR-029: [2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup](00-foundation/decisions/2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup.md)
- ADR-030: [2026-05-23-ADR-030-container-supply-chain-trust-model](00-foundation/decisions/2026-05-23-ADR-030-container-supply-chain-trust-model.md)
- ADR-031: [2026-05-25-ADR-031-dns-resolver-first-class-and-ha](00-foundation/decisions/2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md)
- ADR-032: [2026-06-05-ADR-032-forgejo-git-over-ssh-loopback](00-foundation/decisions/2026-06-05-ADR-032-forgejo-git-over-ssh-loopback.md)
- ADR-034: [2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh](00-foundation/decisions/2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh.md)
- ADR-036: [2026-06-10-ADR-036-bake-policy-and-exception-lane](00-foundation/decisions/2026-06-10-ADR-036-bake-policy-and-exception-lane.md)
- ADR-038: [2026-06-12-ADR-038-merge-commit-only-strategy](00-foundation/decisions/2026-06-12-ADR-038-merge-commit-only-strategy.md)
- ADR-039: [2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping](00-foundation/decisions/2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping.md)
- ADR-042: [2026-07-01-ADR-042-vpn-egress-sidecar-qbittorrent](00-foundation/decisions/2026-07-01-ADR-042-vpn-egress-sidecar-qbittorrent.md)
- : [README](00-foundation/decisions/fixtures/README.md)
- ADR-023: [2026-04-18-ADR-023-btrfs-storage-architecture-databases](00-foundation/decisions/withdrawn/2026-04-18-ADR-023-btrfs-storage-architecture-databases.md)

---

### 10-services/ (8 documents)

**Service-specific documentation and deployment guides**

**Service Guides:**
- [authelia.md](10-services/guides/authelia.md)
- [jellyfin-gpu-acceleration-troubleshooting.md](10-services/guides/jellyfin-gpu-acceleration-troubleshooting.md)
- [pattern-selection-guide.md](10-services/guides/pattern-selection-guide.md)
- [traefik.md](10-services/guides/traefik.md)

**Service Decisions (ADRs):**
- ADR-004: [2025-11-08-ADR-004-immich-deployment-architecture](10-services/decisions/2025-11-08-ADR-004-immich-deployment-architecture.md)
- ADR-007: [2025-11-12-ADR-007-vaultwarden-architecture](10-services/decisions/2025-11-12-ADR-007-vaultwarden-architecture.md)
- ADR-013: [2025-12-20-ADR-013-nextcloud-native-authentication](10-services/decisions/2025-12-20-ADR-013-nextcloud-native-authentication.md)
- ADR-014: [2025-12-20-ADR-014-nextcloud-passwordless-authentication](10-services/decisions/2025-12-20-ADR-014-nextcloud-passwordless-authentication.md)

---

### 20-operations/ (9 documents)

**Operational procedures, runbooks, and architecture**

**Guides:**
- [homelab-architecture.md](20-operations/guides/homelab-architecture.md)
- [storage-layout.md](20-operations/guides/storage-layout.md)

**Runbooks:**
- [DR-001-system-ssd-failure](20-operations/runbooks/DR-001-system-ssd-failure.md)
- [DR-002-btrfs-pool-corruption](20-operations/runbooks/DR-002-btrfs-pool-corruption.md)
- [DR-003-accidental-deletion](20-operations/runbooks/DR-003-accidental-deletion.md)
- [DR-004-total-catastrophe](20-operations/runbooks/DR-004-total-catastrophe.md)
- [nextcloud-operations](20-operations/runbooks/nextcloud-operations.md)

---

### 30-security/ (12 documents)

**Security architecture, configurations, and incident response**

**Guides:**

**Security ADRs:**
- ADR-005: [2025-11-10-ADR-005-authelia-sso-mfa-architecture](30-security/decisions/2025-11-10-ADR-005-authelia-sso-mfa-architecture.md)
- ADR-006: [2025-11-11-ADR-006-authelia-sso-yubikey-deployment](30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md)
- ADR-008: [2025-11-12-ADR-008-crowdsec-security-architecture](30-security/decisions/2025-11-12-ADR-008-crowdsec-security-architecture.md)
- ADR-041: [2026-06-14-ADR-041-secrets-openbao-substrate-boundary](30-security/decisions/2026-06-14-ADR-041-secrets-openbao-substrate-boundary.md)
- ADR-045: [2026-07-17-ADR-045-restricted-egress-tier](30-security/decisions/2026-07-17-ADR-045-restricted-egress-tier.md)
- ADR-046: [2026-07-17-ADR-046-retire-etc-hosts-dns-override](30-security/decisions/2026-07-17-ADR-046-retire-etc-hosts-dns-override.md)
- ADR-047: [2026-07-17-ADR-047-cross-bridge-lateral-movement-containment](30-security/decisions/2026-07-17-ADR-047-cross-bridge-lateral-movement-containment.md)

**Runbooks:**
- [IR-001-brute-force-attack](30-security/runbooks/IR-001-brute-force-attack.md)
- [IR-002-unauthorized-port](30-security/runbooks/IR-002-unauthorized-port.md)
- [IR-003-critical-cve](30-security/runbooks/IR-003-critical-cve.md)
- [IR-004-compliance-failure](30-security/runbooks/IR-004-compliance-failure.md)
- [IR-005-network-security-event](30-security/runbooks/IR-005-network-security-event.md)

---

### 40-monitoring-and-documentation/ (3 documents)

**Monitoring stack, SLOs, and documentation practices**

**Guides:**
- [log-to-metric-implementation.md](40-monitoring-and-documentation/guides/log-to-metric-implementation.md)
- [slo-based-alerting.md](40-monitoring-and-documentation/guides/slo-based-alerting.md)

---

## Recently Updated (Last 7 Days)

- 2026-07-14: [2025-10-20-decision-001-rootless-containers.md](00-foundation/decisions/2025-10-20-decision-001-rootless-containers.md)
- 2026-07-14: [2025-10-25-decision-002-systemd-quadlets-over-compose.md](00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md)
- 2026-07-14: [2025-11-13-ADR-009-config-data-directory-strategy.md](00-foundation/decisions/2025-11-13-ADR-009-config-data-directory-strategy.md)
- 2026-07-14: [2025-12-31-ADR-016-configuration-design-principles.md](00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md)
- 2026-07-14: [2026-02-04-ADR-018-static-ip-multi-network-services.md](00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md)
- 2026-07-14: [2026-02-22-ADR-019-filesystem-permission-model.md](00-foundation/decisions/2026-02-22-ADR-019-filesystem-permission-model.md)
- 2026-07-14: [2026-03-21-ADR-020-daily-external-backups.md](00-foundation/decisions/2026-03-21-ADR-020-daily-external-backups.md)
- 2026-07-14: [2026-03-28-ADR-021-urd-backup-tool.md](00-foundation/decisions/2026-03-28-ADR-021-urd-backup-tool.md)
- 2026-07-14: [2026-04-16-ADR-022-traefik-socket-activation.md](00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md)
- 2026-07-14: [2026-04-21-ADR-023-monitoring-bind-propagation.md](00-foundation/decisions/2026-04-21-ADR-023-monitoring-bind-propagation.md)
- 2026-07-14: [2026-04-21-ADR-026-nextcloud-pinned-major-version.md](00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md)
- 2026-07-14: [2026-04-27-ADR-028-podman-secret-store-path-split.md](00-foundation/decisions/2026-04-27-ADR-028-podman-secret-store-path-split.md)
- 2026-07-14: [2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup.md](00-foundation/decisions/2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup.md)
- 2026-07-14: [2026-05-23-ADR-030-container-supply-chain-trust-model.md](00-foundation/decisions/2026-05-23-ADR-030-container-supply-chain-trust-model.md)
- 2026-07-14: [2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md](00-foundation/decisions/2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md)
- 2026-07-14: [2026-06-05-ADR-032-forgejo-git-over-ssh-loopback.md](00-foundation/decisions/2026-06-05-ADR-032-forgejo-git-over-ssh-loopback.md)
- 2026-07-14: [2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh.md](00-foundation/decisions/2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh.md)
- 2026-07-14: [2026-06-10-ADR-036-bake-policy-and-exception-lane.md](00-foundation/decisions/2026-06-10-ADR-036-bake-policy-and-exception-lane.md)
- 2026-07-14: [2026-06-12-ADR-038-merge-commit-only-strategy.md](00-foundation/decisions/2026-06-12-ADR-038-merge-commit-only-strategy.md)
- 2026-07-14: [2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping.md](00-foundation/decisions/2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping.md)

---

## Quick Search by Service

**Traefik:**
- Guide: [traefik.md](10-services/guides/traefik.md)
- ADR: [ADR-022](00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md)
- Config: `~/containers/config/traefik/`
- Quadlet: `~/.config/containers/systemd/traefik.container`

**Authelia:**
- Guide: [authelia.md](10-services/guides/authelia.md)
- ADR: [ADR-005](30-security/decisions/2025-11-10-ADR-005-authelia-sso-mfa-architecture.md)
- ADR: [ADR-006](30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md)
- Config: `~/containers/config/authelia/`
- Quadlet: `~/.config/containers/systemd/authelia.container`

**Crowdsec:**
- ADR: [ADR-039](00-foundation/decisions/2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping.md)
- ADR: [ADR-008](30-security/decisions/2025-11-12-ADR-008-crowdsec-security-architecture.md)
- Quadlet: `~/.config/containers/systemd/crowdsec.container`

**Jellyfin:**
- Related: [jellyfin-gpu-acceleration-troubleshooting.md](10-services/guides/jellyfin-gpu-acceleration-troubleshooting.md)
- Quadlet: `~/.config/containers/systemd/jellyfin.container`

**Immich Server:**
- Quadlet: `~/.config/containers/systemd/immich-server.container`

**Nextcloud:**
- ADR: [ADR-026](00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md)
- ADR: [ADR-013](10-services/decisions/2025-12-20-ADR-013-nextcloud-native-authentication.md)
- ADR: [ADR-014](10-services/decisions/2025-12-20-ADR-014-nextcloud-passwordless-authentication.md)
- Quadlet: `~/.config/containers/systemd/nextcloud.container`

**Vaultwarden:**
- ADR: [ADR-007](10-services/decisions/2025-11-12-ADR-007-vaultwarden-architecture.md)
- Config: `~/containers/config/vaultwarden/`
- Quadlet: `~/.config/containers/systemd/vaultwarden.container`

**Home Assistant:**
- Config: `~/containers/config/home-assistant/`
- Quadlet: `~/.config/containers/systemd/home-assistant.container`

**Gathio:**
- Config: `~/containers/config/gathio/`
- Quadlet: `~/.config/containers/systemd/gathio.container`

**Prometheus:**
- Config: `~/containers/config/prometheus/`
- Quadlet: `~/.config/containers/systemd/prometheus.container`
- Stack Guide: [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)
- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)

**Grafana:**
- Config: `~/containers/config/grafana/`
- Quadlet: `~/.config/containers/systemd/grafana.container`
- Stack Guide: [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)
- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)

**Loki:**
- Config: `~/containers/config/loki/`
- Quadlet: `~/.config/containers/systemd/loki.container`
- Stack Guide: [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)
- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)

**Alertmanager:**
- Config: `~/containers/config/alertmanager/`
- Quadlet: `~/.config/containers/systemd/alertmanager.container`
- Stack Guide: [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)
- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)

---

## Documentation Practices

### Directory Structure

- **guides/** - Living reference documentation (updated in place)
- **decisions/** - Architecture Decision Records (immutable, dated)
- **runbooks/** - Operational procedures (DR, incident response)
- **journal/** - Chronological entries (append-only, never edited)

### File Naming Conventions

- **Guides:** Descriptive names (e.g., `slo-framework.md`)
- **ADRs:** `YYYY-MM-DD-ADR-NNN-description.md`
- **Journals:** `YYYY-MM-DD-description.md`
- **Reports:** `TYPE-YYYYMMDD-HHMMSS.json` or `.md`

See [CONTRIBUTING.md](CONTRIBUTING.md) for full documentation guidelines.

---

*Auto-generated by `scripts/generate-doc-index.sh`*
*Updates daily to reflect documentation changes*
