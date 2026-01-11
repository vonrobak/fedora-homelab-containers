Plan saved to: ~/.claude/plans/floofy-stirring-cocoa.md · /plan to edit
     Homelab Strategic Development Proposals (2026 Q1)

     Date: 2026-01-09
     Status: Awaiting Approval
     Context: 20-day development analysis + system capabilities assessment

     ---
     Executive Summary

     This plan presents strategic development proposals based on comprehensive analysis of the last 20 days of homelab evolution and current system capabilities. The infrastructure has reached operational
     maturity (95-100/100 health score, 24 services deployed), with a strategic pivot from "building more services" to "building better operational capabilities."

     Three Strategic Courses Proposed:
     1. Matter Home Automation Plan v2.0 - Update existing plan, leverage completed Unpoller integration
     2. Operational Excellence & Gap Closure - Achieve 100/100 health score, validate disaster recovery
     3. Observability & SLO Maturation - Data-driven monitoring, predictive alerting

     Additional Work:
     - UniFi Security Dashboard Enhancement (6 panels) - separate from main courses

     ---
     Last 20 Days Development Summary

     Major Achievements (Dec 21, 2025 - Jan 9, 2026)

     Infrastructure Maturity Reached:
     - 24 services deployed, 95-100/100 health score
     - Alert fatigue eliminated: 678,000+ errors/day reduced to zero
     - Workflow optimization: /commit-push-pr slash command (<30s vs 5-10 min manual)
     - Disaster recovery validated: 6-minute RTO proven

     Key ADRs & Frameworks:
     - ADR-016 (Dec 31): Configuration Design Principles - codified 6 core principles from 2+ months production
     - ADR-017 (Jan 4-5): Slash Commands & Subagents - workflow automation framework
       - 3 specialized subagents: infrastructure-architect, service-validator, code-simplifier
       - Verification feedback loops for autonomous operations
       - Tested with Unpoller deployment: 92% confidence, caught 4 syntax errors

     Network Security Monitoring:
     - Unpoller integration completed (Jan 5-8)
     - 544 metrics/poll, 12 recording rules, 7 alert rules, 10 SLO rules
     - Network + application layer threat correlation
     - CRITICAL: Unpoller satisfies Matter plan Phase 2 prerequisite

     Operational Excellence:
     - Monitoring fixes: Certificate alerts, Loki health check, node_exporter (Jan 8)
     - External backup restore capability validated (Jan 3)
     - Auto-documentation system complete (daily regeneration at 07:00)
     - Autonomous OODA loop with circuit breaker protection

     ---
     Current System Capabilities

     Infrastructure Overview

     Core Services (All Healthy):
     - Reverse Proxy: Traefik (4 days uptime) - 23 routes, fail-fast middleware ordering
     - Authentication: Authelia (7+ days) - YubiKey/WebAuthn + TOTP, 99.9% SLO
     - IP Reputation: CrowdSec (11 days) - Real-time threat intel, CAPI integration
     - Monitoring: Prometheus (4 days), Grafana (9 days), Loki (11 days, health check intermittent)
     - Network Monitoring: Unpoller (NEW, Jan 8) - UDM Pro metrics, VPN presence detection

     Application Services:
     - Media: Jellyfin (752MB RAM, 99.5% SLO), Immich (multi-container, 99.9% SLO)
     - Files: Nextcloud (MariaDB + Redis), Vaultwarden (password manager)
     - Monitoring: Alertmanager, Node Exporter, cAdvisor

     Automation & Orchestration:
     - 68+ production scripts across 8 categories
     - Pattern-based deployment (9 battle-tested patterns)
     - Autonomous OODA loop (daily 06:00 + 06:30)
     - Drift detection (daily verification)
     - Natural language queries (homelab-intel.sh)

     Security Posture (95/100):
     - 7-layer defense: Network segmentation, CrowdSec, rate limiting, Authelia, TLS, headers, container isolation
     - 8 runbooks: 4 DR, 4 IR (including new IR-005 for network security)
     - Weekly vulnerability scanning
     - ADR-001 compliance: Rootless containers, SELinux enforcing

     Observability:
     - 9 SLOs across 5 services (established Dec 31, need calibration)
     - 40+ alert rules, 15+ Grafana dashboards
     - Loki log aggregation (Traefik + remediation decisions)
     - Predictive maintenance (7-14 day resource forecasting)

     Documentation (315 files):
     - 17 ADRs (design-guiding decisions documented)
     - Hybrid structure: Topical reference + chronological learning
     - Auto-generated daily: Service catalog, network topology, dependency graph

     Resource Utilization

     - Memory: 13GB / 31GB (43% used, healthy headroom)
     - CPU: 2-5% normal, idle >90%
     - Disk (Root): 61GB / 118GB (53% used)
     - Disk (BTRFS): 11TB / 15TB (72% used, -0.30 GB/day growth)

     Identified Gaps

     - Loki health check intermittent (low impact, service functional)
     - External backup restore untested (local validated: 6-min RTO)
     - SLO targets need calibration (established Dec 31, need Jan-Mar data)
     - Memory limits: Some containers lack explicit limits (current stability good)

     ---
     COURSE 1: Matter Home Automation Plan v2.0 (REQUIRED)

     Strategic Vision

     Transform the existing 590-line Matter home automation plan into an immediately actionable implementation roadmap by resolving identified gaps and leveraging the already-completed Unpoller integration.

     Why Now:
     - Unpoller dependency ALREADY SATISFIED (Phase 2 prerequisite complete)
     - Hardware is cheap ($12 nRF52840 dongle for OTBR)
     - Aligns with operational maturity (monitoring-first deployment)
     - Plan has been awaiting approval since Dec 30, 2025

     Scope

     Critical Updates:

     1. ADR Conflict Resolution
       - Current plan references ADR-016 through ADR-019
       - Actual: ADR-016 (Configuration Design), ADR-017 (Slash Commands)
       - Fix: Renumber Matter ADRs to ADR-018 through ADR-021
       - Update all cross-references
     2. Traefik Routing Examples
       - Plan lacks concrete implementation examples
       - Add: Complete dynamic config snippets for:
           - Home Assistant (authenticated, high-throughput)
         - OTBR web UI (admin-only, optional exposure)
         - Voice gateway (public port 10300, strict rate limiting)
       - Follow ADR-016 principles (routing in routers.yml, not labels)
     3. Phase 1 Implementation Runbook
       - Current: High-level phases
       - Create: Week-by-week checklist with:
           - Prerequisites verification (hardware ordered, UDM Pro accessible)
         - Step-by-step quadlet creation (:Z SELinux labels)
         - Network creation commands with verification
         - Traefik routing deployment sequence
         - Verification checkpoints after each step
     4. Hardware Procurement Checklist
       - Document: Product links, alternatives, flashing instructions
       - nRF52840 dongle: Nordic PCA10059, ~$12 USD
       - Flashing guide: OpenThread.io step-by-step
       - Backup sources if primary vendor out of stock
     5. VPN Presence Detection Quick Win
       - Unpoller already provides homelab:vpn_clients:count recording rule
       - Document: PromQL query, HA integration pattern
       - Proves Unpoller → HA integration before deploying HA
       - Timeline: Week 1 of Phase 1 (early validation)
     6. Risk Assessment Update
       - Original: "Integration complexity" risk
       - Update: Unpoller integration de-risked
       - Add: "Resource usage" risk (plan adds 9.5GB RAM to baseline)
       - Mitigation: Phased deployment allows monitoring resource impact

     Timeline

     Week 1 (8 hours): Plan revision
     - ADR renumbering, conflict resolution (2h)
     - Traefik routing examples (3h)
     - Phase 1 runbook creation (3h)

     Week 2 (4 hours): Validation and documentation
     - Hardware procurement checklist (2h)
     - VPN presence detection guide (1h)
     - Review against ADRs, commit to docs/97-plans/ (1h)

     Total: 12 hours over 2 weeks (sustainable at 1-2 hours/day)

     Critical Files

     To Modify:
     - /home/patriark/containers/docs/97-plans/2025-12-30-matter-home-automation-implementation-plan.md - Plan document

     To Reference:
     - /home/patriark/containers/docs/00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md - Traefik patterns
     - /home/patriark/containers/config/traefik/dynamic/routers.yml - Routing examples
     - /home/patriark/containers/docs/97-plans/2025-01-08-unpoller-with-advanced-networks-monitoring-plan.md - VPN presence integration

     Value Proposition

     Immediate Benefits:
     - Actionable plan ready for hardware procurement
     - No ADR confusion (clean numbering)
     - Concrete examples (copy-paste-adapt)
     - VPN presence detection quick win

     Strategic Benefits:
     - Unlocks major infrastructure expansion (10 new services, home automation platform)
     - Demonstrates mature deployment (monitoring-first, security-first)
     - Template for future multi-service deployments
     - Establishes home automation as production capability

     Risk Assessment

     Low Risk:
     - Documentation-only (no system changes)
     - ADR renumbering follows established patterns
     - Traefik examples based on proven ADR-016 principles

     Mitigations:
     - Review with infrastructure-architect subagent before approval
     - Test Traefik routing examples syntax before committing
     - VPN presence detection as early validation checkpoint

     ---
     COURSE 2: Operational Excellence & Gap Closure

     Strategic Vision

     Close identified operational gaps to achieve 100/100 sustained health score and validate all documented recovery procedures. This transforms the homelab from "highly capable" to "operationally
     bulletproof."

     Why Now:
     - System stable (95/100 health), perfect time to test without pressure
     - Better to find gaps during controlled testing than real incidents
     - Recent monitoring fixes provide patterns to follow

     Scope

     1. Loki Health Check Resolution (2 hours)
     - Issue: Intermittent health check, service actually healthy
     - Root cause: Script checks non-existent localhost port
     - Fix: Align with recent monitoring fixes (node_exporter broken pipe pattern from Jan 8)
     - Verify via Promtail connection logs (proven approach)

     2. Memory Limit Audit & Standardization (4 hours)
     - Current: 24/24 containers have limits, inconsistent patterns
     - Audit: Review all quadlets, identify MemoryMax vs MemoryHigh usage
     - Standardize: Apply pattern from deployment skill (both limits defined)
     - Document: Update pattern templates with best practices

     3. External Backup Restore Testing (6 hours)
     - Current: Local backup validated (6-min RTO), external untested
     - Test: Restore from WD-18TB external backup to temporary directory
     - Measure: Time to restore, data integrity verification
     - Document: Update DR runbooks with actual external restore procedure

     4. SLO Calibration (3 hours)
     - Current: 9 SLOs established Dec 31, based on estimates
     - Collect: Jan 1-31 actual performance data
     - Calibrate: Adjust targets based on 95th percentile observed performance
     - Rationale: Data-driven targets vs. estimates

     5. Configuration Drift Monitoring Enhancement (3 hours)
     - Current: Manual drift detection script
     - Enhance: Automated weekly drift reports
     - Alert: Discord notification if drift detected
     - Integration: Autonomous operations can auto-remediate simple drift

     Timeline

     Week 1 (8 hours): Quick wins
     - Loki health check fix (2h)
     - Memory limit audit (4h)
     - Drift monitoring enhancement (2h)

     Week 2 (8 hours): Validation work
     - External backup restore test (6h)
     - SLO data collection setup (2h)

     Week 3 (2 hours): Calibration
     - Review Jan data, adjust SLO targets (wait until Feb 1)

     Total: 18 hours over 3 weeks

     Critical Files

     To Modify:
     - /home/patriark/containers/scripts/homelab-intel.sh - Loki health check
     - /home/patriark/.config/containers/systemd/*.container - Memory limits (24 files)
     - /home/patriark/containers/config/prometheus/rules/*-slo-rules.yml - SLO targets

     To Reference:
     - /home/patriark/containers/docs/20-operations/runbooks/DR-*.md - DR validation procedures

     Value Proposition

     Immediate Benefits:
     - 100/100 sustained health score
     - Proven disaster recovery (external backup validated)
     - Data-driven SLO targets (vs. estimates)
     - Automated drift detection

     Strategic Benefits:
     - Operational confidence (tested recovery procedures)
     - Reduced MTTR (faster recovery from validated procedures)
     - Compliance readiness (audit trail of DR testing)
     - Foundation for quarterly DR drills

     Measurable Outcomes:
     - Health score: 100/100 for 30+ consecutive days
     - External backup RTO: <X minutes (measured, currently unknown)
     - SLO targets: Adjusted to 95th percentile of observed performance
     - Drift detection: Automated weekly, <5 min to investigate

     Risk Assessment

     Medium Risk:
     - External backup restore could reveal gaps in strategy
     - Memory limit changes could destabilize services
     - SLO targets might be too aggressive (require relaxation)

     Mitigations:
     - Backup restore: Test on non-production directory first
     - Memory limits: Change one service at a time, monitor 24h before next
     - SLO calibration: Start conservative, tighten after more data
     - All changes: BTRFS snapshots before modifications

     ---
     COURSE 3: Observability & SLO Maturation

     Strategic Vision

     Evolve monitoring stack from "comprehensive metrics" to "actionable insights" by calibrating SLO targets with real-world data, expanding Loki log analysis, and creating predictive alerting that warns
     before SLO violations occur.

     Why Now:
     - SLO framework established Dec 31, enough data exists by Feb 1 to calibrate
     - Loki remediation queries proven (autonomous operations), time to expand
     - Recent alert fatigue fixes demonstrate value of predictive alerting

     Scope

     1. SLO Target Calibration (4 hours)
     - Collect: Jan 1-31 performance data (9 SLOs across 5 services)
     - Analyze: 95th percentile, error budget burn rate, actual downtime
     - Calibrate: Adjust targets to realistic levels (avoid alert fatigue)
     - Document: Rationale for each target, burn rate thresholds

     2. SLO Burn Rate Alerting (6 hours)
     - Current: Alerts when SLO violated
     - Enhance: Predict SLO violation based on burn rate
     - Implementation:
       - 1-hour window: >14.4x burn rate → page immediately (exhaust in 2 days)
       - 6-hour window: >6x burn rate → warning (exhaust in 5 days)
       - 24-hour window: >3x burn rate → info (exhaust in 10 days)
     - Integration: Alertmanager routing based on severity

     3. Loki Log Analysis Expansion (8 hours)
     - Current: Remediation audit trail (autonomous operations)
     - Expand: Error pattern detection, anomaly identification
     - Create: LogQL queries for common failure patterns
     - Correlate: Logs with Prometheus metrics
     - Automated: Daily top 10 errors report across all services
     - Integration: Discord daily digest, Grafana dashboard

     4. Trace Collection Exploration (6 hours)
     - Current: Metrics (Prometheus) + Logs (Loki)
     - Explore: Distributed tracing (Tempo or Jaeger) - PoC
     - Scope: Test with 2-3 services (Traefik, Authelia, Nextcloud)
     - Decision: Implement if value justifies complexity

     5. Custom Metrics for Business Logic (4 hours)
     - Current: Infrastructure metrics (CPU, memory, network)
     - Add: Application-level metrics
       - Jellyfin: Concurrent streams, transcode queue depth
       - Immich: Photo upload rate, ML processing backlog
       - Nextcloud: Active users, file sync errors
     - Integration: Prometheus custom exporters or native app integrations

     Timeline

     Week 1 (8 hours): SLO work
     - Data collection and analysis (4h)
     - Burn rate alerting implementation (4h)

     Week 2 (8 hours): Log analysis
     - LogQL query expansion (6h)
     - Daily error digest automation (2h)

     Week 3 (10 hours): Advanced observability
     - Trace collection PoC (6h)
     - Custom metrics implementation (4h)

     Total: 26 hours over 3 weeks

     Critical Files

     To Modify:
     - /home/patriark/containers/config/prometheus/rules/*-slo-rules.yml - SLO targets
     - /home/patriark/containers/config/prometheus/alerts/rules.yml - Burn rate alerts
     - /home/patriark/containers/docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md - Log queries

     To Create:
     - Trace collection configuration (if PoC succeeds)
     - Custom exporter configurations for business metrics

     Value Proposition

     Immediate Benefits:
     - Predictive alerting (warn before SLO violation)
     - Data-driven SLO targets (vs. estimates)
     - Automated error detection (vs. manual log review)
     - Business metrics visibility (app-level insights)

     Strategic Benefits:
     - Proactive operations (predict failures before users notice)
     - Reduced MTTD (faster detection via log correlation)
     - Capacity planning (business metrics guide scaling)
     - Observability maturity (metrics + logs + traces)

     Measurable Outcomes:
     - SLO violations predicted: 80%+ caught by burn rate alerts
     - Error detection: Automated daily report highlights top issues
     - Trace coverage: 3+ critical paths instrumented (if implemented)
     - Business metrics: 5+ new metrics per service

     Risk Assessment

     Low-Medium Risk:
     - Burn rate alerting could be too sensitive (alert fatigue)
     - Trace collection adds complexity (storage, performance overhead)
     - Custom metrics require app-specific knowledge

     Mitigations:
     - Burn rate: Start conservative, tune thresholds based on false positive rate
     - Tracing: PoC first, implement only if clear value
     - Custom metrics: Start with 1-2 services, expand if useful
     - All changes: Monitor resource impact, rollback if overhead too high

     ---
     Alternative Courses (Not Recommended for Q1)

     COURSE 4: Advanced Workflow & Subagent Maturation

     Summary: Mature ADR-017 framework by expanding service-validator profiles, testing code-simplifier, creating oncall-guide subagent, implementing verification feedback loops, and testing /commit-push-pr.

     Timeline: 26 hours over 3 weeks

     Why Not Q1: Workflow automation is already functional. Priority should be operational excellence and observability maturation to ensure solid foundation before expanding workflow tooling.

     COURSE 5: Service Expansion & Pattern Library

     Summary: Deploy 3-5 new services (Uptime Kuma, Miniflux, Linkding, etc.), enhance pattern library with 2-3 new patterns, add automation for Prometheus/Grafana/Loki integration.

     Timeline: 24 hours over 3 weeks

     Why Not Q1: System is stable with 24 services. Better to mature existing services (observability, operational excellence) before expanding portfolio.

     ---
     Recommended Strategy

     Primary Recommendation: OPERATIONAL EXCELLENCE TRACK

     Courses Selected:
     1. Matter Plan v2.0 (12 hours, 2 weeks) - User-requested, unlocks major expansion
     2. Operational Excellence & Gap Closure (18 hours, 3 weeks) - Achieves 100/100 health
     3. Observability & SLO Maturation (26 hours, 3 weeks) - Predictive monitoring

     Rationale:
     - Aligns with strategic pivot to "building better operational capabilities"
     - Matter plan adds new capabilities, Courses 2+3 ensure foundation is rock-solid
     - Data-driven approach (validate external backup, calibrate SLOs with real data)
     - Predictive operations (burn rate alerts, automated error detection)

     Timeline: 12 weeks total
     - Weeks 1-2: Matter plan revision
     - Weeks 3-5: Operational excellence (Course 2)
     - Weeks 6-8: SLO maturation (Course 3)
     - Weeks 9-12: Matter Phase 1 execution (after hardware arrives)

     Outcome by March 2026:
     - Home automation platform deployed
     - 100/100 sustained health score
     - Validated disaster recovery (external backup tested)
     - Predictive alerting preventing SLO violations
     - Data-driven SLO targets

     Alternative Recommendation: WORKFLOW MATURATION TRACK

     Courses Selected:
     1. Matter Plan v2.0 (12 hours, 2 weeks)
     2. Advanced Workflow & Subagent Maturation (Course 4, 26 hours, 3 weeks)
     3. Service Expansion & Pattern Library (Course 5, 24 hours, 3 weeks)

     Rationale:
     - Advances workflow automation and deployment tooling
     - Demonstrates pattern maturity through new service deployments
     - Creates learning system (verification feedback loops)
     - Expands homelab capabilities (3-5 new services)

     Why Not Primary: Workflow automation already functional (ADR-017 validated). Operational excellence provides more value in Q1.

     ---
     Additional Work (Separate from Main Courses)

     UniFi Security Dashboard Enhancement

     Scope: Add 6 panels to Security Overview dashboard
     - Port forwarding traffic to homelab (80/443 → 192.168.1.70)
     - DPI security threats detected
     - Firewall blocks by source (top 10)
     - WireGuard VPN presence detection
     - Bandwidth usage to homelab (24h heatmap)
     - Correlation matrix (unified view)

     Timeline: 1-2 hours (automated, from Unpoller Phase 2 plan)

     Status: Can execute after Unpoller Phase 1 user completion

     Note: This is SEPARATE from the 3 main strategic courses and can run in parallel.

     ---
     Success Metrics

     Matter Plan v2.0

     - ADR conflicts resolved (renumbered to ADR-018 through ADR-021)
     - Traefik routing examples added (3 services)
     - Phase 1 runbook created (week-by-week checklist)
     - Hardware procurement checklist documented
     - VPN presence detection guide created
     - Plan approved and ready for execution

     Operational Excellence

     - 100/100 health score sustained for 30+ days
     - Loki health check fixed (no false positives)
     - Memory limits standardized across all containers
     - External backup RTO measured (<X minutes)
     - SLO targets calibrated with Jan data
     - Automated drift detection implemented

     Observability Maturation

     - SLO burn rate alerts implemented (3 windows: 1h, 6h, 24h)
     - LogQL queries expanded (common failure patterns)
     - Daily error digest automated (Discord integration)
     - Trace collection evaluated (PoC complete)
     - Business metrics implemented (5+ per service)

     ---
     Dependencies & Prerequisites

     Matter Plan v2.0

     - Prerequisites: None (documentation work)
     - Blockers: None
     - Enablers: ADR-016, ADR-017, Unpoller deployment complete

     Operational Excellence

     - Prerequisites: January performance data (wait until Feb 1 for SLO calibration)
     - Blockers: None
     - Enablers: Recent monitoring fixes (Jan 8), external backup infrastructure

     Observability Maturation

     - Prerequisites: January performance data (wait until Feb 1)
     - Blockers: Loki operational (currently intermittent health check, but functional)
     - Enablers: Existing SLO framework, Loki remediation queries

     ---
     Risk Mitigation

     Cross-Cutting Risks


     ┌────────────────────┬────────────────────────────────────┬────────────────────────────────────────────────────────────┐
     │        Risk        │               Impact               │                         Mitigation                         │
     ├────────────────────┼────────────────────────────────────┼────────────────────────────────────────────────────────────┤
     │ Time commitment    │ May take longer than 1-2 hours/day │ Phased approach, can pause between courses                 │
     ├────────────────────┼────────────────────────────────────┼────────────────────────────────────────────────────────────┤
     │ System instability │ Changes could destabilize services │ BTRFS snapshots before all modifications                   │
     ├────────────────────┼────────────────────────────────────┼────────────────────────────────────────────────────────────┤
     │ Alert fatigue      │ New alerts could overwhelm         │ Conservative thresholds, tune based on false positive rate │
     ├────────────────────┼────────────────────────────────────┼────────────────────────────────────────────────────────────┤
     │ Scope creep        │ Additional work discovered         │ Stick to defined scope, document future work separately    │
     └────────────────────┴────────────────────────────────────┴────────────────────────────────────────────────────────────┘
     Course-Specific Risks

     Matter Plan v2.0:
     - Low risk (documentation only)
     - Mitigation: Review with infrastructure-architect before committing

     Operational Excellence:
     - Medium risk (external backup could reveal gaps)
     - Mitigation: Test in non-production environment first

     Observability Maturation:
     - Low-medium risk (burn rate alerts could be too sensitive)
     - Mitigation: Start conservative, tune thresholds incrementally

     ---
     Next Steps

     User Decision Required

     Choose Strategic Track:
     1. Operational Excellence Track (Courses 1, 2, 3) - RECOMMENDED
     2. Workflow Maturation Track (Courses 1, 4, 5)

     Approval Process

     1. Review this plan
     2. Ask clarifying questions if needed
     3. Approve chosen track
     4. Claude begins execution with Course 1 (Matter Plan v2.0 revision)

     Post-Approval

     Week 1-2: Matter plan revision
     - Update ADR references
     - Add Traefik routing examples
     - Create Phase 1 runbook
     - Document hardware procurement
     - VPN presence detection guide

     Weeks 3+: Execute approved secondary courses

     ---
     End of Plan

● Excellent! I've completed a comprehensive strategic analysis and created your Q1 2026 development roadmap.

  Strategic Intelligence Summary

  Last 20 Days Highlights:
  - Infrastructure maturity achieved (24 services, 95-100/100 health)
  - Alert fatigue eliminated (678K errors/day → 0)
  - Workflow automation framework deployed (ADR-017)
  - Unpoller integration complete - satisfies Matter plan Phase 2 prerequisite

  Current Capabilities:
  - 68+ automation scripts, autonomous OODA loop
  - 7-layer security defense, 95/100 security score
  - 9 SLOs across 5 services (need data-driven calibration)
  - 315 documentation files, 17 ADRs

  Three Strategic Courses Proposed

  COURSE 1: Matter Home Automation Plan v2.0 (REQUIRED)

  Timeline: 12 hours over 2 weeks
  Key Updates:
  - Resolve ADR numbering conflicts (renumber to ADR-018 through ADR-021)
  - Add concrete Traefik routing examples
  - Create detailed Phase 1 implementation runbook
  - Document VPN presence detection quick win (leverages existing Unpoller)

  COURSE 2: Operational Excellence & Gap Closure

  Timeline: 18 hours over 3 weeks
  Deliverables:
  - Fix Loki health check, standardize memory limits
  - Test external backup restore (validate disaster recovery)
  - Calibrate SLO targets with real Jan data
  - Automated drift detection

  Outcome: 100/100 sustained health score, proven disaster recovery

  COURSE 3: Observability & SLO Maturation

  Timeline: 26 hours over 3 weeks
  Deliverables:
  - Predictive SLO burn rate alerting (warn before violation)
  - Expanded Loki log analysis with automated error detection
  - Custom business metrics (Jellyfin streams, Immich uploads, etc.)
  - Trace collection evaluation (PoC)

  Outcome: Proactive operations, data-driven monitoring

  Recommendation

  PRIMARY: Operational Excellence Track (Courses 1, 2, 3)
  - Aligns with strategic pivot to "building better operational capabilities"
  - Matter plan unlocks new capabilities
  - Courses 2+3 ensure foundation is rock-solid before expansion
  - By March 2026: Home automation deployed, 100/100 health, validated DR, predictive monitoring

  Alternative: Workflow Maturation Track (Courses 1, 4, 5)
  - Advances subagent framework, deploys 3-5 new services
  - Why not primary: Workflow automation already functional

  Next Steps

  Your Decision: Which track do you prefer?
  1. Operational Excellence Track (recommended)
  2. Workflow Maturation Track

  Once you decide, I'll begin with Course 1 (Matter Plan v2.0 revision) - updating ADRs, adding Traefik examples, and creating the Phase 1 runbook.

  Note: UniFi Security Dashboard Enhancement (6 panels) is separate and can run in parallel with any track.
