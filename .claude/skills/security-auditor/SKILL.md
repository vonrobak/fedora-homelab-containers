---
name: security-auditor
description: Comprehensive security auditing with scoring, trend analysis, and remediation guidance. Use for periodic deep audits, security posture assessment, post-change verification, or investigating security events.
---

# Security Auditor

## Overview

Deep security audit skill for 1-2x/month comprehensive posture assessment. Runs 53 checks across 7 domains with scoring, trend analysis, and remediation guidance.

## Workflow

### Phase 1: Gather

```bash
cd ~/containers

# Full audit with JSON output for analysis
./scripts/security-audit.sh --level 3 --json --compare

# Optional: health context (unhealthy system may produce misleading security findings)
./scripts/homelab-intel.sh --quiet
```

**Audit levels:**
- Level 1: Critical only (15 checks) — quick daily sanity
- Level 2: Important (28 checks) — standard assessment
- Level 3: All (53 checks) — comprehensive deep audit

**Single category:**
```bash
./scripts/security-audit.sh --category auth --json
# Categories: auth, network, traefik, containers, monitoring, secrets, compliance
```

### Phase 2: Analyze

Parse the JSON output. Key fields:

```json
{
  "security_score": 92,
  "summary": { "total": 53, "pass": 48, "warn": 3, "fail": 2 },
  "categories": { "auth": { "pass": 5, "warn": 1, "fail": 0 }, ... },
  "checks": [{ "id": "SA-AUTH-01", "level": 1, "status": "FAIL", "message": "..." }],
  "trend": { "previous_score": 89, "score_change": 3 }
}
```

**Correlation analysis:**
- CrowdSec down (SA-NET-01) + rate limiter as only defense = critical exposure
- Authelia down (SA-AUTH-01) + Redis down (SA-AUTH-03) = complete auth failure
- SELinux disabled (SA-CTR-01) + loose permissions (SA-SEC-03) = container escape risk
- No memory limits (SA-CTR-02) + OOM events (SA-CTR-05) = resource exhaustion pattern
- CrowdSec bouncer missing (SA-TRF-03) + middleware ordering wrong (SA-TRF-05) = defense bypass

**Scoring:** Start at 100. L1 fail: -15, L2 fail: -5, L3 fail: -2. Warnings: half penalty.

### Phase 3: Report

Structure the response as:

```
**Security Score: XX/100** [up/down arrow + delta from previous]

**Critical Findings** (Level 1 failures)
- Finding with impact assessment
- Remediation steps with specific commands
- Reference to relevant runbook (IR-001 through IR-005)

**Important Findings** (Level 2 failures/warnings)
- Finding with timeline for remediation
- Prevention strategy

**Domain Summary**
| Category | Pass | Warn | Fail | Notes |
|----------|------|------|------|-------|

**Trend** (vs previous audit)
- Score change and direction
- New failures since last audit
- Resolved issues

**Recommended Actions** (prioritized)
1. [CRITICAL] Immediate action with command
2. [IMPORTANT] Action within 24h
3. [BEST PRACTICE] Improvement opportunity
```

## Check Catalog

| Category | Checks | What it covers |
|----------|--------|---------------|
| AUTH | SA-AUTH-01..07 | Authelia running/health, default policy, access_control coverage, Redis isolation |
| NETWORK | SA-NET-01..09 | CrowdSec running/CAPI/bouncers, port audit, monitoring isolation, Samba |
| TRAEFIK | SA-TRF-01..09 | Traefik running, TLS certs, CrowdSec in routers, middleware ordering, ADR-016 |
| CONTAINERS | SA-CTR-01..11 | SELinux, memory limits, DB pinning, SELinux labels, OOM, network ordering, healthchecks |
| MONITORING | SA-MON-01..07 | Prometheus/Alertmanager/Grafana running, scrape targets, Promtail, alert rules |
| SECRETS | SA-SEC-01..05 | gitignore coverage, git history, file permissions, GPG signing, Podman secrets |
| COMPLIANCE | SA-CMP-01..05 | Uncommitted changes, BTRFS NOCOW, filesystem permissions, naming conventions |

## Runbook References

When findings require remediation, reference these runbooks:

- **IR-001** — Security incident response (CrowdSec/Authelia failures)
- **IR-002** — Compromised credentials
- **IR-003** — Service exploitation
- **IR-004** — Data breach response
- **IR-005** — DDoS/abuse response
- **DR-001** through **DR-004** — Disaster recovery procedures

Location: `docs/30-security/runbooks/` and `docs/20-operations/runbooks/`

## Integration with Other Skills

- **homelab-intelligence** — Run health check first; unhealthy system may produce misleading security findings
- **systematic-debugging** — Use for investigating specific check failures in depth
- **autonomous-operations** — Check decision log for security-relevant automated actions

## History & Trends

Audit history stored as JSON in `~/containers/data/security-audit/audit-YYYY-MM-DD.json`.

```bash
# Compare with previous audit
./scripts/security-audit.sh --level 3 --json --compare

# Generate markdown report
./scripts/security-audit.sh --level 3 --report
# Output: docs/99-reports/security-audit-YYYY-MM-DD.md
```

## Reference

- Check details and scenarios: [scenarios.md](scenarios.md)
- Security guides: `docs/30-security/guides/`
- Manual checklist: `docs/30-security/guides/security-audit.md`
