# Documentation Index (Auto-Generated)

**Generated:** 2026-02-21 06:02:55 UTC
**Total Documents:** 392

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

### 00-foundation/ (12 documents)

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

---

### 10-services/ (28 documents)

**Service-specific documentation and deployment guides**

**Service Guides:**
- [alert-discord-relay.md](10-services/guides/alert-discord-relay.md)
- [apple-ecosystem-quick-reference.md](10-services/guides/apple-ecosystem-quick-reference.md)
- [authelia.md](10-services/guides/authelia.md)
- [crowdsec.md](10-services/guides/crowdsec.md)
- [esp32-plejd-quick-start.md](10-services/guides/esp32-plejd-quick-start.md)
- [gathio-email-setup.md](10-services/guides/gathio-email-setup.md)
- [home-assistant.md](10-services/guides/home-assistant.md)
- [homepage-widget-configuration.md](10-services/guides/homepage-widget-configuration.md)
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

### 20-operations/ (26 documents)

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

### 30-security/ (17 documents)

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

**Runbooks:**
- [IR-001-brute-force-attack](30-security/runbooks/IR-001-brute-force-attack.md)
- [IR-002-unauthorized-port](30-security/runbooks/IR-002-unauthorized-port.md)
- [IR-003-critical-cve](30-security/runbooks/IR-003-critical-cve.md)
- [IR-004-compliance-failure](30-security/runbooks/IR-004-compliance-failure.md)
- [IR-005-network-security-event](30-security/runbooks/IR-005-network-security-event.md)

---

### 40-monitoring-and-documentation/ (14 documents)

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

### 97-plans/ (27 documents)

**Strategic plans and forward-looking projects**
- 📋 [2025-01-08-unpoller-with-advanced-networks-monitoring-plan.md](97-plans/2025-01-08-unpoller-with-advanced-networks-monitoring-plan.md)
- 📋 [2025-01-09-strategic-development-trajectories-plan.md](97-plans/2025-01-09-strategic-development-trajectories-plan.md)
- 📋 [2025-11-10-authelia-implementation-plan.md](97-plans/2025-11-10-authelia-implementation-plan.md)
- 📋 [2025-11-10-authelia-implementation-plan-revised.md](97-plans/2025-11-10-authelia-implementation-plan-revised.md)
- 📋 [2025-12-23-remediation-phase-3-roadmap.md](97-plans/2025-12-23-remediation-phase-3-roadmap.md)
- 📋 [2025-12-30-matter-home-automation-implementation-plan.md](97-plans/2025-12-30-matter-home-automation-implementation-plan.md)
- 📋 [2025-12-30-nextcloud-security-performance-observability-plan.md](97-plans/2025-12-30-nextcloud-security-performance-observability-plan.md)
- 📋 [2026-01-04-workflow-improvements-plan.md](97-plans/2026-01-04-workflow-improvements-plan.md)
- ✅ [2026-01-22-monthly-review-matter-hybrid-approach.md](97-plans/2026-01-22-monthly-review-matter-hybrid-approach.md)
- 📋 [ADR-REORGANIZATION-PLAN.md](97-plans/ADR-REORGANIZATION-PLAN.md)
- 📋 [MIGRATION-PLAN-FINAL.md](97-plans/MIGRATION-PLAN-FINAL.md)
- ✅ [PLAN-1-AUTO-UPDATE-SAFETY-NET.md](97-plans/PLAN-1-AUTO-UPDATE-SAFETY-NET.md)
- ✅ [PLAN-2-PROACTIVE-AUTO-REMEDIATION.md](97-plans/PLAN-2-PROACTIVE-AUTO-REMEDIATION.md)
- 📝 [PLAN-GUIDE-ORGANIZATION.md](97-plans/PLAN-GUIDE-ORGANIZATION.md)
- ✅ [PROJECT-A-DISASTER-RECOVERY-PLAN.md](97-plans/PROJECT-A-DISASTER-RECOVERY-PLAN.md)
- 📋 [PROJECT-A-IMPLEMENTATION-ROADMAP.md](97-plans/PROJECT-A-IMPLEMENTATION-ROADMAP.md)
- 📝 [PROJECT-AUTONOMOUS-ORCHESTRATION.md](97-plans/PROJECT-AUTONOMOUS-ORCHESTRATION.md)
- 📋 [PROJECT-B-SECURITY-HARDENING.md](97-plans/PROJECT-B-SECURITY-HARDENING.md)
- 📋 [PROJECT-C-AUTO-DOCUMENTATION.md](97-plans/PROJECT-C-AUTO-DOCUMENTATION.md)
- 📋 [PROJECT-C-AUTO-DOCUMENTATION-REVISED.md](97-plans/PROJECT-C-AUTO-DOCUMENTATION-REVISED.md)
- 📋 [SESSION-5B-PREDICTIVE-ANALYTICS-PLAN.md](97-plans/SESSION-5B-PREDICTIVE-ANALYTICS-PLAN.md)
- 📋 [SESSION-5C-NATURAL-LANGUAGE-QUERIES-PLAN.md](97-plans/SESSION-5C-NATURAL-LANGUAGE-QUERIES-PLAN.md)
- 📋 [SESSION-5D-SKILL-RECOMMENDATION-ENGINE-PLAN.md](97-plans/SESSION-5D-SKILL-RECOMMENDATION-ENGINE-PLAN.md)
- 📋 [SESSION-5E-BACKUP-INTEGRATION-PLAN.md](97-plans/SESSION-5E-BACKUP-INTEGRATION-PLAN.md)
- ✅ [SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md](97-plans/SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md)
- 📋 [SESSION-6-AUTONOMOUS-OPERATIONS-PLAN.md](97-plans/SESSION-6-AUTONOMOUS-OPERATIONS-PLAN.md)
- ✅ [STANDALONE-PROJECTS-INDEX.md](97-plans/STANDALONE-PROJECTS-INDEX.md)

---

### 98-journals/ (171 documents)

**Chronological project history (append-only log)**

Complete dated entries documenting the homelab journey. See directory for full chronological listing.

---

### 99-reports/ (28 documents)

**Automated system reports and point-in-time snapshots**

Recent intelligence reports and resource forecasts. Updated automatically by autonomous operations.

---

## Recently Updated (Last 7 Days)

- 2026-02-14: [HOMELAB-FIELD-GUIDE.md](00-foundation/guides/HOMELAB-FIELD-GUIDE.md)
- 2026-02-15: [2026-02-15-community-tool-sharing-platform-architecture.md](98-journals/2026-02-15-community-tool-sharing-platform-architecture.md)
- 2026-02-16: [2026-02-16-gnome-freeze-system-update.md](98-journals/2026-02-16-gnome-freeze-system-update.md)
- 2026-02-16: [2026-02-16-post-reboot-handoff.md](98-journals/2026-02-16-post-reboot-handoff.md)
- 2026-02-20: [2026-02-18-loose-ends-audit.md](98-journals/2026-02-18-loose-ends-audit.md)
- 2026-02-16: [remediation-monthly-202601.md](99-reports/remediation-monthly-202601.md)
- 2026-02-21: [AUTO-DEPENDENCY-GRAPH.md](AUTO-DEPENDENCY-GRAPH.md)
- 2026-02-21: [AUTO-DOCUMENTATION-INDEX.md](AUTO-DOCUMENTATION-INDEX.md)
- 2026-02-21: [AUTO-NETWORK-TOPOLOGY.md](AUTO-NETWORK-TOPOLOGY.md)
- 2026-02-21: [AUTO-SERVICE-CATALOG.md](AUTO-SERVICE-CATALOG.md)

---

## Quick Search by Service

**Traefik:**
- Guide: [traefik.md](10-services/guides/traefik.md)
- Config: `~/containers/config/traefik/`
- Quadlet: `~/.config/containers/systemd/traefik.container`

**Authelia:**
- Guide: [authelia.md](10-services/guides/authelia.md)
- ADR: [ADR-005](30-security/decisions/2025-11-10-ADR-005-authelia-sso-mfa-architecture.md)
- ADR: [ADR-006](30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md)
- Config: `~/containers/config/authelia/`
- Quadlet: `~/.config/containers/systemd/authelia.container`

**Crowdsec:**
- Guide: [crowdsec.md](10-services/guides/crowdsec.md)
- ADR: [ADR-008](30-security/decisions/2025-11-12-ADR-008-crowdsec-security-architecture.md)
- Quadlet: `~/.config/containers/systemd/crowdsec.container`

**Jellyfin:**
- Guide: [jellyfin.md](10-services/guides/jellyfin.md)
- Related: [jellyfin-gpu-acceleration-troubleshooting.md](10-services/guides/jellyfin-gpu-acceleration-troubleshooting.md)
- Quadlet: `~/.config/containers/systemd/jellyfin.container`

**Immich Server:**
- Guide: [immich.md](10-services/guides/immich.md)
- Related: [immich-configuration-review.md](10-services/guides/immich-configuration-review.md)
- Related: [immich-deployment-checklist.md](10-services/guides/immich-deployment-checklist.md)
- Related: [immich-ml-troubleshooting.md](10-services/guides/immich-ml-troubleshooting.md)
- Quadlet: `~/.config/containers/systemd/immich-server.container`

**Nextcloud:**
- Guide: [nextcloud.md](10-services/guides/nextcloud.md)
- ADR: [ADR-013](10-services/decisions/2025-12-20-ADR-013-nextcloud-native-authentication.md)
- ADR: [ADR-014](10-services/decisions/2025-12-20-ADR-014-nextcloud-passwordless-authentication.md)
- Config: `~/containers/config/nextcloud/`
- Quadlet: `~/.config/containers/systemd/nextcloud.container`

**Vaultwarden:**
- Related: [vaultwarden-deployment.md](10-services/guides/vaultwarden-deployment.md)
- ADR: [ADR-007](10-services/decisions/2025-11-12-ADR-007-vaultwarden-architecture.md)
- Config: `~/containers/config/vaultwarden/`
- Quadlet: `~/.config/containers/systemd/vaultwarden.container`

**Home Assistant:**
- Guide: [home-assistant.md](10-services/guides/home-assistant.md)
- Related: [home-assistant.md](10-services/guides/home-assistant.md)
- Config: `~/containers/config/home-assistant/`
- Quadlet: `~/.config/containers/systemd/home-assistant.container`

**Homepage:**
- Related: [homepage-widget-configuration.md](10-services/guides/homepage-widget-configuration.md)
- Config: `~/containers/config/homepage/`
- Quadlet: `~/.config/containers/systemd/homepage.container`

**Gathio:**
- Related: [gathio-email-setup.md](10-services/guides/gathio-email-setup.md)
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
