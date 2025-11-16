# Project B: Security Hardening & Compliance Framework

**Status:** High-Level Plan (Ready for Detailed Planning)
**Priority:** 🔒 HIGH
**Risk Mitigation:** Prevent breaches, ensure compliance with security standards
**Estimated Effort:** 5-7 hours (detailed planning: +2 hours)
**Dependencies:** None (standalone project)

---

## Executive Summary

Your homelab exposes services to the internet with layered security (CrowdSec, Authelia, Traefik), but recent issues (CrowdSec crash-looping 3900+ times, ADR-006 only 75% compliant) reveal gaps in security validation and compliance checking.

This project creates a **comprehensive security framework** that:
1. **Audits** your security posture automatically
2. **Validates** compliance with your ADRs
3. **Scans** for vulnerabilities in containers
4. **Enforces** security baselines pre-deployment
5. **Responds** to security incidents automatically

**The Gap:**
```
Current: ✅ Security tools deployed → ❌ No validation → ❓ Are we secure?
Target:  ✅ Security tools deployed → ✅ Continuous auditing → ✅ Proven compliant
```

---

## Problem Statement

### Security Risks Identified

**From System Intelligence Report (2025-11-12):**
- ⚠️ CrowdSec: Crashed 3900+ times (5 hours downtime) - config validation gap
- ⚠️ Vaultwarden: No resource limits (OOM vulnerability)
- ⚠️ ADR-006 Compliance: Only 75% complete
- ⚠️ TinyAuth: Still running (deprecated, redundant with Authelia)

**Additional Concerns:**
- No automated security scanning of container images
- No validation of Traefik middleware configurations
- No audit log for security-related changes
- No incident response playbook
- No regular security reviews

### Compliance Gaps

**ADR-006 (CrowdSec Security) - 75% Compliant:**
- ✅ Version pinning
- ✅ CAPI enrollment
- ✅ Tiered ban profiles
- ✅ Whitelisting
- ⚠️ Middleware standardization (inconsistent @file suffixes)
- ⚠️ Bouncer cleanup (17 stale registrations)
- ⚠️ Service stability (restart loop)

**No Compliance Framework for Other ADRs:**
- ADR-001 (Rootless Containers) - Compliance unknown
- ADR-002 (Systemd Quadlets) - Compliance unknown
- ADR-003 (Monitoring Stack) - Compliance unknown
- ADR-005 (Authelia SSO) - Compliance unknown

---

## Proposed Architecture

### Security Hardening Framework

```
┌─────────────────────────────────────────────────────────────┐
│          Security Hardening & Compliance Framework          │
└─────────────────────────────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌──────────────────┐
│ Security Audit  │ │ Compliance      │ │ Vulnerability    │
│ Toolkit         │ │ Checker         │ │ Scanner          │
│                 │ │                 │ │                  │
│ - Port scan     │ │ - ADR-001-006   │ │ - CVE scanning   │
│ - Config review │ │ - Validation    │ │ - Image analysis │
│ - Log analysis  │ │ - Remediation   │ │ - SBOM gen       │
└─────────────────┘ └─────────────────┘ └──────────────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                             ▼
         ┌────────────────────────────────────────┐
         │     Security Baseline Enforcement      │
         │  (Pre-deployment checks for services)  │
         └────────────────────────────────────────┘
                             │
                             ▼
         ┌────────────────────────────────────────┐
         │    Incident Response Automation        │
         │   (Playbooks for security events)      │
         └────────────────────────────────────────┘
```

---

## Components Overview

### Component 1: Security Audit Toolkit

**Purpose:** Automated security scanning and assessment

**Tools to Implement:**
1. **Port Scanner** - Verify only intended ports exposed
   - Expected: 80, 443, 8096 (Jellyfin)
   - Alert on unexpected open ports

2. **Configuration Reviewer** - Validate security configs
   - Traefik: Verify TLS 1.2+, modern ciphers, HSTS enabled
   - Authelia: Verify YubiKey enforcement, session limits
   - CrowdSec: Validate profiles, whitelists, bouncer registration

3. **Log Analyzer** - Scan for security incidents
   - Failed auth attempts (Authelia logs)
   - Blocked IPs (CrowdSec decisions)
   - 403/401 responses (Traefik logs)
   - Privilege escalation attempts (system logs)

4. **Permission Auditor** - Check file/directory permissions
   - Secrets files: 600 (owner read/write only)
   - Config files: 644 (owner write, group/world read)
   - Scripts: 755 (executable, not writable by others)

**Deliverable:** `scripts/security-audit.sh` - Comprehensive security scan

---

### Component 2: Compliance Checker

**Purpose:** Validate adherence to ADRs and security standards

**ADR Compliance Checks:**

**ADR-001 (Rootless Containers):**
- [ ] All containers run as non-root user
- [ ] No containers with `--privileged` flag (except whitelisted GPU)
- [ ] All volume mounts have `:Z` SELinux label
- [ ] SELinux enforcing mode enabled

**ADR-002 (Systemd Quadlets):**
- [ ] All services use quadlet files (not standalone podman run)
- [ ] Quadlets follow naming convention
- [ ] Service dependencies properly declared

**ADR-003 (Monitoring Stack):**
- [ ] Prometheus scraping all expected targets
- [ ] Grafana datasource configured correctly
- [ ] Loki receiving logs from all services
- [ ] Alerting rules present and valid

**ADR-005 (Authelia SSO):**
- [ ] Admin services require YubiKey 2FA
- [ ] Session timeout configured (1 hour)
- [ ] Authelia middleware applied to sensitive services
- [ ] TOTP fallback available

**ADR-006 (CrowdSec):**
- [ ] Version pinned (v1.7.3)
- [ ] CAPI enrolled and pulling blocklist
- [ ] Tiered ban profiles configured (3 tiers)
- [ ] Local networks whitelisted
- [ ] Traefik bouncer registered
- [ ] Middleware standardized (@file suffix)

**Deliverable:** `scripts/compliance-check.sh` - ADR compliance validator

---

### Component 3: Vulnerability Scanner

**Purpose:** Scan container images for known CVEs

**Approach:**
- Use **Trivy** (open-source vulnerability scanner)
- Scan all container images before deployment
- Scan running containers weekly
- Generate vulnerability reports (critical/high/medium/low)

**Integration Points:**
1. **Pre-deployment** - Block if critical CVEs found
2. **Weekly scans** - Alert on new vulnerabilities
3. **Prometheus metrics** - Track vulnerability counts
4. **Grafana dashboard** - Visualize security posture

**Example Workflow:**
```bash
# Scan image before deployment
trivy image --severity HIGH,CRITICAL docker.io/jellyfin/jellyfin:latest

# Exit code 1 if vulnerabilities found (block deployment)
# Generate report: ~/containers/data/security-reports/trivy-*.json
```

**Deliverable:** `scripts/scan-vulnerabilities.sh` - Automated CVE scanning

---

### Component 4: Security Baseline Enforcement

**Purpose:** Pre-deployment checks to prevent security misconfigurations

**Baseline Checks:**
1. **Container Configuration:**
   - ✓ No `--privileged` (unless GPU service on whitelist)
   - ✓ Resource limits defined (MemoryMax, CPUQuota)
   - ✓ Health check configured
   - ✓ Read-only root filesystem (where possible)
   - ✓ No unnecessary capabilities

2. **Network Configuration:**
   - ✓ Service on appropriate network (not exposed unnecessarily)
   - ✓ No direct port bindings for internal services
   - ✓ Reverse proxy used for internet-facing services

3. **Traefik Middleware:**
   - ✓ CrowdSec bouncer applied
   - ✓ Rate limiting configured
   - ✓ Authentication required (Authelia or basic auth)
   - ✓ Security headers enabled

4. **Secrets Management:**
   - ✓ No secrets in environment variables (use files)
   - ✓ Secret files excluded from Git (.gitignore)
   - ✓ Secret files have restrictive permissions (600)

**Integration:** Enhance `homelab-deployment` skill with security validation phase

**Deliverable:** `scripts/enforce-security-baseline.sh` - Pre-deployment security gate

---

### Component 5: Incident Response Playbooks

**Purpose:** Automated response to security events

**Playbook Examples:**

**IR-001: Brute Force Attack Detected**
- **Trigger:** >100 failed auth attempts from single IP in 5 minutes
- **Response:**
  1. CrowdSec auto-bans IP (already configured)
  2. Alert via Discord (high priority)
  3. Log incident to security audit trail
  4. Check if attack successful (any valid logins after failures?)

**IR-002: Unauthorized Port Exposed**
- **Trigger:** Security audit finds unexpected open port
- **Response:**
  1. Alert critical severity
  2. Identify service using port (`ss -tulnp`)
  3. Review recent deployments/changes
  4. Suggest remediation (close port or add to whitelist)

**IR-003: Critical CVE in Running Container**
- **Trigger:** Weekly Trivy scan finds CRITICAL vulnerability
- **Response:**
  1. Alert with CVE details
  2. Check if CVE exploitable in our config
  3. Suggest update command
  4. Track remediation status

**IR-004: Failed Compliance Check**
- **Trigger:** ADR compliance check fails
- **Response:**
  1. Identify which ADR violated
  2. List non-compliant items
  3. Suggest auto-remediation (if available)
  4. Create ticket for manual review

**Deliverable:** `docs/30-security/runbooks/IR-*.md` - Incident response procedures

---

## Implementation Roadmap

### Phase 1: Foundation (2 hours)
- [ ] Install Trivy vulnerability scanner
- [ ] Create security audit script framework
- [ ] Define ADR compliance schema (YAML)
- [ ] Set up security reports directory

### Phase 2: Audit & Compliance (2 hours)
- [ ] Implement security-audit.sh
- [ ] Implement compliance-check.sh (ADR-001 through ADR-006)
- [ ] Test on current homelab state
- [ ] Generate initial reports

### Phase 3: Vulnerability Scanning (1 hour)
- [ ] Implement scan-vulnerabilities.sh
- [ ] Configure Trivy for all container images
- [ ] Create vulnerability report template
- [ ] Set up weekly cron job

### Phase 4: Baseline Enforcement (1-2 hours)
- [ ] Implement enforce-security-baseline.sh
- [ ] Integrate with homelab-deployment skill
- [ ] Create security checklist template
- [ ] Test pre-deployment validation

### Phase 5: Incident Response (1 hour)
- [ ] Create IR playbook templates
- [ ] Write IR-001 through IR-004
- [ ] Set up security event logging
- [ ] Test playbook execution

### Phase 6: Monitoring Integration (1 hour)
- [ ] Export security metrics to Prometheus
- [ ] Create Grafana security dashboard
- [ ] Configure security-related alerts
- [ ] Test alerting workflow

---

## Deliverables Summary

### Scripts
- `scripts/security-audit.sh` - Comprehensive security scanner
- `scripts/compliance-check.sh` - ADR compliance validator
- `scripts/scan-vulnerabilities.sh` - CVE scanner (Trivy wrapper)
- `scripts/enforce-security-baseline.sh` - Pre-deployment security gate

### Documentation
- `docs/30-security/guides/security-framework.md` - Framework overview
- `docs/30-security/runbooks/IR-001-brute-force.md`
- `docs/30-security/runbooks/IR-002-unauthorized-port.md`
- `docs/30-security/runbooks/IR-003-critical-cve.md`
- `docs/30-security/runbooks/IR-004-compliance-failure.md`

### Monitoring
- Prometheus metrics for security events
- Grafana dashboard: "Security Posture"
- Alertmanager rules for security incidents

### Reports (Auto-generated)
- `~/containers/data/security-reports/audit-*.json`
- `~/containers/data/security-reports/compliance-*.json`
- `~/containers/data/security-reports/vulnerabilities-*.json`

---

## Example: ADR-006 Compliance Check Output

```bash
$ ./scripts/compliance-check.sh --adr 006

=========================================
ADR-006 Compliance Check: CrowdSec Security
=========================================

✓ Version pinning: crowdsec:v1.7.3 (compliant)
✓ CAPI enrollment: Active, pulling 9,847 IPs
✓ Tiered profiles: 3 tiers configured
  - Tier 1: 7-day bans (5 scenarios)
  - Tier 2: 24-hour bans (8 scenarios)
  - Tier 3: 4-hour bans (12 scenarios)
✓ Whitelisting: 3 networks configured
  - 192.168.1.0/24
  - 192.168.100.0/24
  - 10.89.0.0/16
✗ Middleware standardization: 3 inconsistencies found
  - Line 45: "crowdsec-bouncer" → Should be "crowdsec-bouncer@file"
  - Line 67: "rate-limit" → Should be "rate-limit@file"
  - Line 89: "authelia" is correct (already has @file)
✗ Bouncer cleanup: 17 stale registrations
  - 16 old Traefik IPs
  - 1 test bouncer (should be deleted)
⚠ Service stability: Restart loop detected (45 restarts in 24h)

---
Compliance Score: 75% (6/8 checks passed)
Status: PARTIAL COMPLIANCE
Priority: Address ✗ items within 1 week
```

---

## Success Metrics

### Quantitative
- [ ] Zero critical/high CVEs in running containers
- [ ] 100% ADR compliance (all ADRs 001-006)
- [ ] Security audit pass rate >95%
- [ ] <5 security incidents per month
- [ ] All internet-facing services behind authentication

### Qualitative
- [ ] Security posture visible in Grafana
- [ ] Automated response to common threats
- [ ] Clear documentation of security standards
- [ ] Confidence in compliance state

---

## Future Enhancements (Beyond Scope)

### Advanced Security
- **Intrusion Detection System (IDS)** - Suricata or Snort integration
- **Web Application Firewall (WAF)** - ModSecurity for Traefik
- **Secrets Manager** - Vault or SOPS for secret management
- **Security Information & Event Management (SIEM)** - Centralized logging with Wazuh

### Compliance & Governance
- **CIS Benchmark Compliance** - Fedora hardening checks
- **NIST Cybersecurity Framework** - Map controls to framework
- **Automated Remediation** - Fix compliance issues automatically
- **Regular Penetration Testing** - Automated security testing

---

## Next Steps

**To proceed with Project B:**

1. **Review this high-level plan** - Confirm scope and approach
2. **Request detailed implementation plan** - Similar to Project A level of detail
3. **Adjust priorities** - Which components are most critical?
4. **Schedule CLI sessions** - When CLI credits available

**Questions to answer before detailed planning:**
- Which ADRs are highest priority for compliance checking?
- Should vulnerability scanning block deployments or just alert?
- What severity level for security alerts? (Discord notifications?)
- Do you want automated remediation or manual approval?

---

**Status:** High-level plan complete
**Ready for:** Detailed implementation planning (add 2 hours for full plan)
**Estimated Total:** 5-7 hours implementation + 2 hours planning = 7-9 hours
