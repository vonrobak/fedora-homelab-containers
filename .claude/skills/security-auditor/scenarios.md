# Security Auditor - Scenarios & Examples

Detailed scenarios for the security-auditor skill. See [SKILL.md](SKILL.md) for the main workflow.

## Scenario 1: Post-Change Security Verification

After deploying a new service or modifying configuration:

1. Run `./scripts/security-audit.sh --level 2 --json --compare`
2. Focus on:
   - SA-TRF-03: CrowdSec bouncer in new router
   - SA-TRF-04: Rate limiting on new router
   - SA-TRF-06: No Traefik labels in new quadlet (ADR-016)
   - SA-CTR-04: SELinux labels on volume mounts
   - SA-CTR-07: Healthcheck defined
   - SA-AUTH-05: New domain has access_control rule
3. Compare score with pre-change baseline

**Expected outcome:** Score should not decrease after changes. New check IDs should all pass.

## Scenario 2: Monthly Comprehensive Audit

For the biweekly deep audit (1st and 15th of month):

1. Run `./scripts/security-audit.sh --level 3 --json --report --compare`
2. Review all 53 checks
3. Check trend vs previous audit
4. Generate markdown report for audit trail
5. Address any new failures or degradations

**Focus areas:**
- L3 checks that are informational (SA-AUTH-07 auth failures, SA-NET-08 CrowdSec decisions)
- Container image age (SA-CTR-10) — images >30 days should be updated
- Compliance drift (SA-CMP-01..05) — configuration should match git

## Scenario 3: Security Incident Investigation

When investigating a potential security event:

1. Run `./scripts/security-audit.sh --category network --json` for CrowdSec status
2. Run `./scripts/security-audit.sh --category auth --json` for auth status
3. Cross-reference with:
   - CrowdSec alerts: `podman exec crowdsec cscli alerts list --since 24h`
   - Authelia logs: `journalctl --user -u authelia.service --since "1 hour ago"`
   - Traefik access logs: Loki queries in Grafana
4. Reference IR runbooks based on findings

## Scenario 4: Score Dropped Significantly

When the security score drops >10 points from previous:

1. Identify which checks changed status (compare JSON outputs)
2. Categorize: infrastructure issue vs configuration drift vs external factor
3. Priority order:
   - L1 failures: Fix immediately (service down, cert expiring, SELinux disabled)
   - L2 failures: Fix within 24h (missing middleware, memory limits)
   - L3 warnings: Track and address in next maintenance window

**Common causes of score drops:**
- Service restart/reboot left something not running (L1 failures)
- Configuration change didn't include all required middleware (L2)
- System update changed SELinux or firewall state (L1)

## Scenario 5: Category-Specific Deep Dive

When a specific domain needs attention:

```bash
# Authentication issues
./scripts/security-audit.sh --category auth --level 3 --json

# Network/CrowdSec issues
./scripts/security-audit.sh --category network --level 3 --json

# Container security
./scripts/security-audit.sh --category containers --level 3 --json
```

## Check ID Quick Reference

**Critical (L1) - Fix immediately:**
- SA-AUTH-01..03: Authelia + Redis running and healthy
- SA-NET-01..03: CrowdSec running, CAPI connected, bouncers active
- SA-TRF-01..03: Traefik running, TLS valid, CrowdSec in routers
- SA-CTR-01: SELinux enforcing
- SA-MON-01..03: Prometheus, Alertmanager, Grafana running
- SA-SEC-01..02: gitignore and git history clean

**Important (L2) - Fix within 24h:**
- SA-AUTH-04..06: Deny policy, access_control rules, Redis isolation
- SA-NET-04..07: Scenarios loaded, port audit, monitoring internal, no Samba
- SA-TRF-04..08: Rate limits, middleware order, ADR-016, headers, port 8080
- SA-CTR-02..09: Memory limits, DB pinning, SELinux labels, OOM, healthchecks
- SA-MON-04..06: Scrape targets, Promtail, Alertmanager port
- SA-SEC-03..04: File permissions, GPG signing
- SA-CMP-01..03: Git status, NOCOW, filesystem permissions

**Best Practice (L3) - Track:**
- SA-AUTH-07: Auth failure volume
- SA-NET-08..09: CrowdSec decisions and alerts
- SA-TRF-09: TLS minimum version
- SA-CTR-10..11: Image age, Slice directive
- SA-MON-07: Alert rules loaded
- SA-SEC-05: Podman secrets count
- SA-CMP-04..05: Naming conventions, dependency declarations
