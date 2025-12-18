# Standalone Projects Index

**Created:** 2025-11-15
**Purpose:** High-value projects independent of Session 4 (Context Framework)
**Status:** Planning Complete, Ready for Prioritization

---

## Overview

While waiting for CLI credits to execute Session 4 (Context Framework + Auto-Remediation), three **standalone high-value projects** have been identified and planned:

| Project | Priority | Risk Reduction | Time Saving | Effort | Status |
|---------|----------|---------------|-------------|--------|--------|
| **A: Disaster Recovery** | 🔥 CRITICAL | ⭐⭐⭐ | ⭐⭐ | 6-8h | ✅ Detailed Plan |
| **B: Security Hardening** | 🔒 HIGH | ⭐⭐ | ⭐ | 7-9h | ✅ High-Level Plan |
| **C: Auto-Documentation** | 📚 MEDIUM | ⭐ | ⭐⭐⭐ | 6-8h | ✅ High-Level Plan |

---

## Project A: Backup & Disaster Recovery Testing 🔥

**File:** [PROJECT-A-DISASTER-RECOVERY-PLAN.md](PROJECT-A-DISASTER-RECOVERY-PLAN.md)
**Plan Detail:** FULL (850+ lines, execution-ready)

### The Problem

You have comprehensive backups (6 subvolumes, 13TB data, daily/weekly/monthly snapshots) but **zero restore testing**. This means:
- ❌ Don't know if backups actually work
- ❌ No procedures for disaster recovery
- ❌ Unknown RTO (Recovery Time Objective)
- ❌ No monitoring/alerting for backup failures

### What You'll Build

1. **Automated Restore Testing**
   - Monthly tests: Restore random samples, verify integrity
   - Validation: Checksums, permissions, SELinux contexts
   - Reporting: Pass/fail per subvolume, metrics exported

2. **Disaster Recovery Runbooks**
   - DR-001: System SSD Failure (4-6 hour recovery)
   - DR-002: BTRFS Pool Corruption (6-12 hour recovery)
   - DR-003: Accidental Deletion (5-30 minute recovery)
   - DR-004: Total Catastrophe (rebuild procedure)

3. **Backup Health Monitoring**
   - Prometheus metrics: backup age, success rate, restore test results
   - Grafana dashboard: Visual backup health status
   - Alertmanager: Notify when backups fail or restore tests fail

4. **RTO/RPO Measurement**
   - Measure actual restore times
   - Document recovery time for each subvolume
   - Identify improvement opportunities

### Key Deliverables

- `scripts/test-backup-restore.sh` - Automated testing script
- `docs/20-operations/runbooks/DR-*.md` - 4 recovery runbooks
- Systemd timer for monthly automated tests
- Prometheus/Grafana integration
- RTO/RPO documentation

### Why This First?

✅ **Highest Risk Mitigation** - Prevents total data loss
✅ **Prerequisite for Everything** - If homelab is lost, other projects don't matter
✅ **Quick Validation Win** - Uses existing backup infrastructure
✅ **Immediate Peace of Mind** - Know backups actually work

### Implementation Timeline

**Session 1:** Restore testing framework (3-4h)
**Session 2:** Runbooks + monitoring (2-3h)
**Session 3:** Testing & documentation (1-2h)
**Total:** 6-9 hours

---

## Project B: Security Hardening & Compliance 🔒

**File:** [PROJECT-B-SECURITY-HARDENING.md](PROJECT-B-SECURITY-HARDENING.md)
**Plan Detail:** HIGH-LEVEL (380 lines, ready for detailed planning)

### The Problem

Security tools are deployed (CrowdSec, Authelia, Traefik) but recent issues reveal gaps:
- ⚠️ CrowdSec crashed 3900+ times (config validation gap)
- ⚠️ ADR-006 only 75% compliant
- ⚠️ No automated security scanning
- ⚠️ No vulnerability detection for containers
- ⚠️ No audit trail for security events

### What You'll Build

1. **Security Audit Toolkit**
   - Automated port scanning (verify only expected ports open)
   - Configuration review (TLS settings, auth enforcement)
   - Log analysis (failed logins, blocked IPs, privilege escalation)
   - Permission auditing (secrets have 600, configs have 644)

2. **Compliance Checker**
   - ADR-001: Rootless Containers (verify all services rootless)
   - ADR-002: Systemd Quadlets (verify no standalone containers)
   - ADR-003: Monitoring Stack (verify metrics coverage)
   - ADR-005: Authelia SSO (verify YubiKey enforcement)
   - ADR-006: CrowdSec (verify tiered profiles, whitelists, CAPI)

3. **Vulnerability Scanner**
   - Trivy integration (scan container images for CVEs)
   - Weekly automated scans
   - Block deployments with critical CVEs
   - Prometheus metrics for vulnerability counts

4. **Security Baseline Enforcement**
   - Pre-deployment security checks
   - Verify resource limits, health checks
   - Validate Traefik middleware (auth, rate limiting, headers)
   - Ensure secrets not in environment variables

5. **Incident Response Playbooks**
   - IR-001: Brute Force Attack Detected
   - IR-002: Unauthorized Port Exposed
   - IR-003: Critical CVE in Running Container
   - IR-004: Failed Compliance Check

### Key Deliverables

- `scripts/security-audit.sh` - Comprehensive security scanner
- `scripts/compliance-check.sh` - ADR compliance validator
- `scripts/scan-vulnerabilities.sh` - Trivy wrapper for CVE scanning
- `scripts/enforce-security-baseline.sh` - Pre-deployment gate
- `docs/30-security/runbooks/IR-*.md` - Incident response procedures
- Grafana dashboard: "Security Posture"

### Why This Second?

✅ **High Risk Mitigation** - Prevents breaches and data leaks
✅ **Addresses Known Issues** - Fixes CrowdSec config gap, ADR compliance
✅ **Proactive Security** - Detect vulnerabilities before exploitation
✅ **Compliance Visibility** - Know your actual security posture

### Implementation Timeline

**Phase 1:** Foundation + audit toolkit (2h)
**Phase 2:** Compliance checker (2h)
**Phase 3:** Vulnerability scanning (1h)
**Phase 4:** Baseline enforcement (1-2h)
**Phase 5:** Incident response (1h)
**Phase 6:** Monitoring integration (1h)
**Total:** 7-9 hours (includes 2h detailed planning)

---

## Project C: Automated Architecture Documentation 📚

**File:** [PROJECT-C-AUTO-DOCUMENTATION.md](PROJECT-C-AUTO-DOCUMENTATION.md)
**Plan Detail:** HIGH-LEVEL (430 lines, ready for detailed planning)

### The Problem

Excellent manual documentation (160 files) but:
- ⚠️ Scattered across directories (hard to find)
- ⚠️ Manual maintenance burden (docs get stale)
- ⚠️ No visual representations (network topology, dependencies)
- ⚠️ Onboarding after vacation = 30+ minutes re-reading

### What You'll Build

1. **Service Catalog Generator**
   - Auto-generated inventory of all 20 services
   - Details: Image, networks, ports, URLs, health status
   - Categorized by function (gateway, media, auth, monitoring)
   - Updates automatically when services change

2. **Network Topology Visualizer**
   - Mermaid diagrams showing 5 networks
   - Service placement with IP addresses
   - Request flow diagrams (User → Traefik → Service)
   - Auto-updates when network configs change

3. **Dependency Graph Generator**
   - Visualize which services depend on what
   - Critical path identification (gateway services)
   - Startup order recommendations
   - Detect circular dependencies

4. **Documentation Index Aggregator**
   - Single entry point for all 160 docs
   - Categorized by directory (foundation, services, operations, security)
   - Grouped by type (guides, journals, ADRs, reports)
   - Recently updated section (last 7 days)
   - Search by service feature

5. **Architecture Summary Generator**
   - Human-readable "state of the homelab" overview
   - Key metrics from latest reports
   - Recent changes from git log
   - Health summary table
   - Links to detailed docs

### Key Deliverables

- `scripts/generate-service-catalog.sh`
- `scripts/generate-network-topology.sh`
- `scripts/generate-dependency-graph.sh`
- `scripts/generate-doc-index.sh`
- `scripts/generate-architecture-summary.sh`
- `docs/AUTO-SERVICE-CATALOG.md` (auto-generated)
- `docs/AUTO-NETWORK-TOPOLOGY.md` (auto-generated)
- `docs/AUTO-DEPENDENCY-GRAPH.md` (auto-generated)
- `docs/AUTO-DOCUMENTATION-INDEX.md` (auto-generated)
- `docs/AUTO-ARCHITECTURE-SUMMARY.md` (auto-generated)
- Git pre-commit hook for auto-regeneration

### Why This Third?

✅ **Highest Time Savings** - Reduce context-gathering from 30min to 5min
✅ **Efficiency Gain** - Automatic documentation maintenance
✅ **Visual Understanding** - See architecture at a glance
✅ **Onboarding Aid** - Easy to return after time away

### Implementation Timeline

**Phase 1:** Parsers & data collection (1-2h)
**Phase 2:** Service catalog (1h)
**Phase 3:** Visualizations (1-2h)
**Phase 4:** Aggregation (1h)
**Phase 5:** Architecture summary (30min)
**Phase 6:** Automation (1h)
**Total:** 6-8 hours (includes 2h detailed planning)

---

## Decision Matrix

### By Priority (Risk Mitigation)

1. **Project A** - Disaster Recovery 🔥
   - **Risk:** Total data loss
   - **Impact:** Catastrophic
   - **Urgency:** High (untested backups = useless backups)

2. **Project B** - Security Hardening 🔒
   - **Risk:** Breach, data leak, service compromise
   - **Impact:** High
   - **Urgency:** Medium (some security already in place)

3. **Project C** - Auto-Documentation 📚
   - **Risk:** Inefficiency, knowledge loss
   - **Impact:** Medium
   - **Urgency:** Low (nice to have, not critical)

### By Effort vs Value

| Project | Effort | Risk Reduction | Time Savings | ROI |
|---------|--------|---------------|-------------|-----|
| **A: Disaster Recovery** | 6-8h | ⭐⭐⭐ High | ⭐⭐ Medium | ⭐⭐⭐ Excellent |
| **B: Security Hardening** | 7-9h | ⭐⭐ Medium-High | ⭐ Low | ⭐⭐ Good |
| **C: Auto-Documentation** | 6-8h | ⭐ Low | ⭐⭐⭐ High | ⭐⭐ Good |

### By Dependencies

**All three projects are independent:**
- ✅ None depend on Session 4 (Context Framework)
- ✅ Can be executed in any order
- ✅ Can be executed in parallel (different areas)

---

## Recommended Execution Order

### Option 1: Sequential (Risk-First Approach)

**Recommended for:** Maximum risk mitigation

```
Week 1: Project A (Disaster Recovery)
  ↓ Backups proven reliable
Week 2: Project B (Security Hardening)
  ↓ Security posture validated
Week 3: Project C (Auto-Documentation)
  ↓ Documentation automated
Week 4+: Session 4 (Context Framework)
```

**Rationale:** Address highest-risk gaps first, then efficiency improvements

---

### Option 2: Hybrid (Value-First Approach)

**Recommended for:** Quick wins + risk mitigation

```
Week 1: Project A Phase 1-2 (4-5h)
  ↓ Core restore testing + runbooks
Project C Phase 1-2 (2-3h)
  ↓ Service catalog + network diagrams

Week 2: Project A Phase 3 (1-2h) - Complete
  ↓ Testing & documentation
Project B Phase 1-3 (4-5h)
  ↓ Security audit + compliance + scanning

Week 3: Project B Phase 4-6 (3-4h) - Complete
  ↓ Baseline + incident response + monitoring
Project C Phase 3-6 (3-4h) - Complete
  ↓ Visualizations + aggregation + automation

Week 4+: Session 4 (Context Framework)
```

**Rationale:** Balance risk mitigation with quick efficiency gains

---

### Option 3: Parallel (Team Approach)

**Recommended for:** Multiple people or extended time

```
Track A: Disaster Recovery (one focus session)
Track B: Security Hardening (another focus session)
Track C: Auto-Documentation (another focus session)
```

**Rationale:** All independent, can be done in parallel without conflicts

---

## Next Steps

### To Execute Any Project

1. **Choose Project** - A, B, or C based on priorities
2. **Review Plan** - Read the detailed/high-level plan document
3. **Request Detailed Plan** - For B or C if you want Project A level of detail
4. **Gather Resources** - Ensure CLI credits available
5. **Schedule Session** - Block time on fedora-htpc
6. **Execute** - Follow the implementation roadmap

### Before Starting

**Project A (Disaster Recovery):**
- [x] Detailed plan complete ✅
- [ ] Review plan and accept scope
- [ ] Ensure external backup drive available
- [ ] Schedule 6-9 hours across 2-3 sessions

**Project B (Security Hardening):**
- [x] High-level plan complete ✅
- [ ] Request detailed implementation plan (add 2h)
- [ ] Install Trivy vulnerability scanner
- [ ] Schedule 7-9 hours across 3-4 sessions

**Project C (Auto-Documentation):**
- [x] High-level plan complete ✅
- [ ] Request detailed implementation plan (add 2h)
- [ ] Choose diagram tool (Mermaid vs Graphviz)
- [ ] Schedule 6-8 hours across 2-3 sessions

---

## Questions & Answers

### Can I execute multiple projects in parallel?

**Yes!** All three are completely independent. You could:
- Run Project A restore tests while implementing Project C parsers
- Implement Project B security audit while Project A monitoring integrates
- Any combination that makes sense for your workflow

### Should I finish one project before starting another?

**Not necessarily.** Each project has phases that can be paused:
- Project A: After Phase 2 (core testing + runbooks), you have value
- Project B: After Phase 2 (audit + compliance), you have visibility
- Project C: After Phase 2 (catalog + topology), you have quick reference

### Which project should I do first?

**Recommended: Project A (Disaster Recovery)**

**Reasoning:**
1. Highest risk - untested backups are a ticking time bomb
2. Lowest dependencies - works with existing backup scripts
3. Immediate value - know backups work, sleep better
4. Prerequisite mentality - if you lose everything, Projects B & C don't matter

**Alternative: Start with Project C if:**
- You need efficiency gains NOW (context-gathering is painful)
- You have confidence in backups (even without testing)
- You value visual understanding highly

### How long until I can execute Session 4?

Session 4 (Context Framework) is independent of these three projects. You can:
- Execute Session 4 now (if CLI credits available)
- Execute A/B/C first, then Session 4
- Interleave: Project A → Session 4 → Project B → etc.

**Recommendation:** Do Project A first (critical risk), then Session 4 when CLI credits return.

---

## Summary

You now have **three execution-ready standalone projects**:

✅ **Project A:** Full detailed plan (850 lines)
✅ **Project B:** High-level plan (ready for detail)
✅ **Project C:** High-level plan (ready for detail)

All three:
- ✅ Independent of Session 4
- ✅ High value for your homelab
- ✅ Executable on fedora-htpc CLI
- ✅ Clear deliverables and success criteria

**Recommended Next Action:**
1. Review Project A detailed plan
2. Execute Project A when CLI credits available
3. Request detailed plans for B & C if desired
4. Execute Session 4 when appropriate

---

**Plans Created:** 2025-11-15
**Total Planning Effort:** ~4 hours (detailed A + high-level B & C)
**Ready for:** CLI execution (Project A) or detailed planning (B & C)
**Questions?** Review individual project files for more detail
