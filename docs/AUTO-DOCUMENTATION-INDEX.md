# Documentation Index (Auto-Generated)

**Generated:** 2026-07-17 10:43:31 UTC
**Total Documents:** 133

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

### 00-foundation/ (34 documents)

**Fundamentals and core concepts**

**Guides:**
- [configuration-design-quick-reference.md](00-foundation/guides/configuration-design-quick-reference.md)
- [HOMELAB-FIELD-GUIDE.md](00-foundation/guides/HOMELAB-FIELD-GUIDE.md)
- [middleware-configuration.md](00-foundation/guides/middleware-configuration.md)
- [podman-fundamentals.md](00-foundation/guides/podman-fundamentals.md)
- [quadlets-vs-generated-units-comparison.md](00-foundation/guides/quadlets-vs-generated-units-comparison.md)

**Decisions (ADRs):**
- : [2025-10-20-decision-001-rootless-containers](00-foundation/decisions/2025-10-20-decision-001-rootless-containers.md)
- : [2025-10-25-decision-002-systemd-quadlets-over-compose](00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md)
- ADR-009: [2025-11-13-ADR-009-config-data-directory-strategy](00-foundation/decisions/2025-11-13-ADR-009-config-data-directory-strategy.md)
- ADR-015: [2025-12-22-ADR-015-container-update-strategy](00-foundation/decisions/2025-12-22-ADR-015-container-update-strategy.md)
- ADR-016: [2025-12-31-ADR-016-configuration-design-principles](00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md)
- ADR-017: [2026-01-05-ADR-017-slash-commands-and-subagents](00-foundation/decisions/2026-01-05-ADR-017-slash-commands-and-subagents.md)
- ADR-018: [2026-02-04-ADR-018-static-ip-multi-network-services](00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md)
- ADR-019: [2026-02-22-ADR-019-filesystem-permission-model](00-foundation/decisions/2026-02-22-ADR-019-filesystem-permission-model.md)
- ADR-020: [2026-03-21-ADR-020-daily-external-backups](00-foundation/decisions/2026-03-21-ADR-020-daily-external-backups.md)
- ADR-021: [2026-03-28-ADR-021-urd-backup-tool](00-foundation/decisions/2026-03-28-ADR-021-urd-backup-tool.md)
- ADR-022: [2026-04-16-ADR-022-traefik-socket-activation](00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md)
- ADR-024: [2026-04-18-ADR-024-database-dump-backup](00-foundation/decisions/2026-04-18-ADR-024-database-dump-backup.md)
- ADR-025: [2026-04-18-ADR-025-db-storage-migration-deferred](00-foundation/decisions/2026-04-18-ADR-025-db-storage-migration-deferred.md)
- ADR-023: [2026-04-21-ADR-023-monitoring-bind-propagation](00-foundation/decisions/2026-04-21-ADR-023-monitoring-bind-propagation.md)
- ADR-026: [2026-04-21-ADR-026-nextcloud-pinned-major-version](00-foundation/decisions/2026-04-21-ADR-026-nextcloud-pinned-major-version.md)
- ADR-027: [2026-04-22-ADR-027-forward-nocow-workloads-subvol8-db](00-foundation/decisions/2026-04-22-ADR-027-forward-nocow-workloads-subvol8-db.md)
- ADR-028: [2026-04-27-ADR-028-podman-secret-store-path-split](00-foundation/decisions/2026-04-27-ADR-028-podman-secret-store-path-split.md)
- ADR-029: [2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup](00-foundation/decisions/2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup.md)
- ADR-030: [2026-05-23-ADR-030-container-supply-chain-trust-model](00-foundation/decisions/2026-05-23-ADR-030-container-supply-chain-trust-model.md)
- ADR-031: [2026-05-25-ADR-031-dns-resolver-first-class-and-ha](00-foundation/decisions/2026-05-25-ADR-031-dns-resolver-first-class-and-ha.md)
- ADR-032: [2026-06-05-ADR-032-forgejo-git-over-ssh-loopback](00-foundation/decisions/2026-06-05-ADR-032-forgejo-git-over-ssh-loopback.md)
- ADR-034: [2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh](00-foundation/decisions/2026-06-06-ADR-034-forgejo-instance-commit-signing-ssh.md)
- ADR-036: [2026-06-10-ADR-036-bake-policy-and-exception-lane](00-foundation/decisions/2026-06-10-ADR-036-bake-policy-and-exception-lane.md)
- ADR-038: [2026-06-12-ADR-038-merge-commit-only-strategy](00-foundation/decisions/2026-06-12-ADR-038-merge-commit-only-strategy.md)
- ADR-037: [2026-06-13-ADR-037-forge-center-of-gravity-per-repo](00-foundation/decisions/2026-06-13-ADR-037-forge-center-of-gravity-per-repo.md)
- ADR-039: [2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping](00-foundation/decisions/2026-06-14-ADR-039-crowdsec-cloud-api-egress-scoping.md)
- ADR-042: [2026-07-01-ADR-042-vpn-egress-sidecar-qbittorrent](00-foundation/decisions/2026-07-01-ADR-042-vpn-egress-sidecar-qbittorrent.md)
- : [README](00-foundation/decisions/fixtures/README.md)
- ADR-023: [2026-04-18-ADR-023-btrfs-storage-architecture-databases](00-foundation/decisions/withdrawn/2026-04-18-ADR-023-btrfs-storage-architecture-databases.md)

---

### 10-services/ (27 documents)

**Service-specific documentation and deployment guides**

**Service Guides:**
- [alert-discord-relay.md](10-services/guides/alert-discord-relay.md)
- [apple-ecosystem-quick-reference.md](10-services/guides/apple-ecosystem-quick-reference.md)
- [authelia.md](10-services/guides/authelia.md)
- [crowdsec.md](10-services/guides/crowdsec.md)
- [esp32-plejd-quick-start.md](10-services/guides/esp32-plejd-quick-start.md)
- [gathio-email-setup.md](10-services/guides/gathio-email-setup.md)
- [home-assistant.md](10-services/guides/home-assistant.md)
- [immich-configuration-review.md](10-services/guides/immich-configuration-review.md)
- [immich-deployment-checklist.md](10-services/guides/immich-deployment-checklist.md)
- [immich.md](10-services/guides/immich.md)
- [immich-ml-troubleshooting.md](10-services/guides/immich-ml-troubleshooting.md)
- [ios-shortcuts-quick-reference.md](10-services/guides/ios-shortcuts-quick-reference.md)
- [jellyfin-gpu-acceleration-troubleshooting.md](10-services/guides/jellyfin-gpu-acceleration-troubleshooting.md)
- [jellyfin.md](10-services/guides/jellyfin.md)
- [matter-server.md](10-services/guides/matter-server.md)
- [nextcloud.md](10-services/guides/nextcloud.md)
- [pattern-customization-guide.md](10-services/guides/pattern-customization-guide.md)
- [pattern-selection-guide.md](10-services/guides/pattern-selection-guide.md)
- [roborock-room-cleaning-setup.md](10-services/guides/roborock-room-cleaning-setup.md)
- [skill-integration-guide.md](10-services/guides/skill-integration-guide.md)
- [skill-recommendation.md](10-services/guides/skill-recommendation.md)
- [traefik.md](10-services/guides/traefik.md)
- [vaultwarden-deployment.md](10-services/guides/vaultwarden-deployment.md)

**Service Decisions (ADRs):**
- ADR-004: [2025-11-08-ADR-004-immich-deployment-architecture](10-services/decisions/2025-11-08-ADR-004-immich-deployment-architecture.md)
- ADR-007: [2025-11-12-ADR-007-vaultwarden-architecture](10-services/decisions/2025-11-12-ADR-007-vaultwarden-architecture.md)
- ADR-013: [2025-12-20-ADR-013-nextcloud-native-authentication](10-services/decisions/2025-12-20-ADR-013-nextcloud-native-authentication.md)
- ADR-014: [2025-12-20-ADR-014-nextcloud-passwordless-authentication](10-services/decisions/2025-12-20-ADR-014-nextcloud-passwordless-authentication.md)

---

### 20-operations/ (28 documents)

**Operational procedures, runbooks, and architecture**

**Guides:**
- [architecture-diagrams.md](20-operations/guides/architecture-diagrams.md)
- [automation-reference.md](20-operations/guides/automation-reference.md)
- [autonomous-operations.md](20-operations/guides/autonomous-operations.md)
- [backup-automation-setup.md](20-operations/guides/backup-automation-setup.md)
- [backup-strategy.md](20-operations/guides/backup-strategy.md)
- [dependency-management.md](20-operations/guides/dependency-management.md)
- [disaster-recovery.md](20-operations/guides/disaster-recovery.md)
- [drift-detection-workflow.md](20-operations/guides/drift-detection-workflow.md)
- [pihole-backup.md](20-operations/guides/external-systems/pihole-backup.md)
- [health-driven-operations.md](20-operations/guides/health-driven-operations.md)
- [homelab-architecture.md](20-operations/guides/homelab-architecture.md)
- [memory-management.md](20-operations/guides/memory-management.md)
- [permission-optimization-nextcloud.md](20-operations/guides/permission-optimization-nextcloud.md)
- [remediation-chains.md](20-operations/guides/remediation-chains.md)
- [resource-limits-configuration.md](20-operations/guides/resource-limits-configuration.md)
- [storage-health-monitoring.md](20-operations/guides/storage-health-monitoring.md)
- [storage-layout.md](20-operations/guides/storage-layout.md)
- [tier3-initial-backup.md](20-operations/guides/tier3-initial-backup.md)
- [unpoller-metrics-guide.md](20-operations/guides/unpoller-metrics-guide.md)

**Runbooks:**
- [DR-001-system-ssd-failure](20-operations/runbooks/DR-001-system-ssd-failure.md)
- [DR-002-btrfs-pool-corruption](20-operations/runbooks/DR-002-btrfs-pool-corruption.md)
- [DR-003-accidental-deletion](20-operations/runbooks/DR-003-accidental-deletion.md)
- [DR-004-total-catastrophe](20-operations/runbooks/DR-004-total-catastrophe.md)
- [nextcloud-operations](20-operations/runbooks/nextcloud-operations.md)

---

### 30-security/ (20 documents)

**Security architecture, configurations, and incident response**

**Guides:**
- [crowdsec-phase1-field-manual.md](30-security/guides/crowdsec-phase1-field-manual.md)
- [crowdsec-phase2-and-5-advanced-features.md](30-security/guides/crowdsec-phase2-and-5-advanced-features.md)
- [crowdsec-phase3-threat-intelligence.md](30-security/guides/crowdsec-phase3-threat-intelligence.md)
- [crowdsec-phase4-configuration-management.md](30-security/guides/crowdsec-phase4-configuration-management.md)
- [esp32-vlan2-firewall-rule.md](30-security/guides/esp32-vlan2-firewall-rule.md)
- [secrets-management.md](30-security/guides/secrets-management.md)
- [security-audit.md](30-security/guides/security-audit.md)
- [sshd-deployment-procedure.md](30-security/guides/sshd-deployment-procedure.md)
- [ssh-hardening.md](30-security/guides/ssh-hardening.md)

**Security ADRs:**
- ADR-005: [2025-11-10-ADR-005-authelia-sso-mfa-architecture](30-security/decisions/2025-11-10-ADR-005-authelia-sso-mfa-architecture.md)
- ADR-006: [2025-11-11-ADR-006-authelia-sso-yubikey-deployment](30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md)
- ADR-008: [2025-11-12-ADR-008-crowdsec-security-architecture](30-security/decisions/2025-11-12-ADR-008-crowdsec-security-architecture.md)
- ADR-040: [2026-06-14-ADR-040-secrets-substrate-operator-boundary](30-security/decisions/2026-06-14-ADR-040-secrets-substrate-operator-boundary.md)
- ADR-041: [2026-06-14-ADR-041-secrets-openbao-substrate-boundary](30-security/decisions/2026-06-14-ADR-041-secrets-openbao-substrate-boundary.md)
- ADR-045: [2026-07-17-ADR-045-restricted-egress-tier](30-security/decisions/2026-07-17-ADR-045-restricted-egress-tier.md)

**Runbooks:**
- [IR-001-brute-force-attack](30-security/runbooks/IR-001-brute-force-attack.md)
- [IR-002-unauthorized-port](30-security/runbooks/IR-002-unauthorized-port.md)
- [IR-003-critical-cve](30-security/runbooks/IR-003-critical-cve.md)
- [IR-004-compliance-failure](30-security/runbooks/IR-004-compliance-failure.md)
- [IR-005-network-security-event](30-security/runbooks/IR-005-network-security-event.md)

---

### 40-monitoring-and-documentation/ (16 documents)

**Monitoring stack, SLOs, and documentation practices**

**Guides:**
- [daily-error-digest.md](40-monitoring-and-documentation/guides/daily-error-digest.md)
- [git-workflow.md](40-monitoring-and-documentation/guides/git-workflow.md)
- [homelab-snapshot-development.md](40-monitoring-and-documentation/guides/homelab-snapshot-development.md)
- [log-to-metric-dashboard-panels.md](40-monitoring-and-documentation/guides/log-to-metric-dashboard-panels.md)
- [log-to-metric-implementation.md](40-monitoring-and-documentation/guides/log-to-metric-implementation.md)
- [loki-remediation-queries.md](40-monitoring-and-documentation/guides/loki-remediation-queries.md)
- [maximizing-workflow-impact.md](40-monitoring-and-documentation/guides/maximizing-workflow-impact.md)
- [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)
- [natural-language-queries.md](40-monitoring-and-documentation/guides/natural-language-queries.md)
- [slo-based-alerting.md](40-monitoring-and-documentation/guides/slo-based-alerting.md)
- [slo-calibration-process.md](40-monitoring-and-documentation/guides/slo-calibration-process.md)
- [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)
- [unifi-security-monitoring.md](40-monitoring-and-documentation/guides/unifi-security-monitoring.md)

---

### 97-plans/ (0 documents)

**Strategic plans and forward-looking projects**

---

### 98-journals/ (0 documents)

**Chronological project history (append-only log)**

Complete dated entries documenting the homelab journey. See directory for full chronological listing.

---

### 99-reports/ (0 documents)

**Automated system reports and point-in-time snapshots**

Recent intelligence reports and resource forecasts. Updated automatically by autonomous operations.

---

## Recently Updated (Last 7 Days)

