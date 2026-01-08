# Security Audit Guide

**Purpose:** Comprehensive security checklist for homelab infrastructure
**Frequency:** Monthly manual audit + automated checks (security-audit.sh script)
**Last Updated:** 2026-01-08

---

## Overview

This guide provides a structured approach to auditing the security posture of your homelab infrastructure. It covers multiple layers of defense including authentication, network security, application hardening, monitoring, and operational security.

**Audit Levels:**
- **Level 1 (Critical)**: Must pass - security gaps pose immediate risk
- **Level 2 (Important)**: Should pass - gaps increase risk surface
- **Level 3 (Best Practice)**: Nice to have - defense-in-depth improvements

---

## Authentication & Access Control

### Authelia SSO

**Level 1 (Critical):**
- [ ] Authelia service is running and healthy
- [ ] YubiKey/WebAuthn 2FA enforced for all users
- [ ] Default policy is not `bypass` (should be `two_factor` or `one_factor` minimum)
- [ ] Session secret and encryption key are strong random values (>32 chars)
- [ ] Redis (session storage) is only accessible on internal network

```bash
# Verify Authelia is running
systemctl --user is-active authelia.service

# Check health endpoint
curl -f http://localhost:9091/api/health

# Verify Redis is not exposed externally
podman exec redis-authelia redis-cli ping
ss -tulnp | grep 6379  # Should only bind to internal network
```

**Level 2 (Important):**
- [ ] Session expiration configured (default: 1 hour inactivity, 12 hours max)
- [ ] Failed authentication attempts are logged to Loki
- [ ] Brute force protection is enabled (default: 5 failed attempts → temporary ban)
- [ ] Authelia access logs show no unusual 401/403 patterns

```bash
# Check session configuration
grep -A 5 "session:" ~/containers/config/authelia/configuration.yml

# Check recent authentication failures
podman logs authelia --since 24h 2>&1 | grep -i "unsuccessful\|denied" | wc -l
```

**Level 3 (Best Practice):**
- [ ] TOTP backup configured for YubiKey users
- [ ] Authelia access control rules documented and reviewed
- [ ] User database backed up securely (users_database.yml)

### SSH Hardening

**Level 1 (Critical):**
- [ ] SSH key-based authentication only (PasswordAuthentication no)
- [ ] Root login disabled (PermitRootLogin no)
- [ ] SSH service uses hardened config from `sshd-deployment-procedure.md`

```bash
# Verify SSH config
sudo sshd -T | grep -E "^passwordauthentication|^permitrootlogin"

# Expected output:
# passwordauthentication no
# permitrootlogin no
```

**Level 2 (Important):**
- [ ] Ed25519 SSH keys used (not RSA-2048)
- [ ] SSH listening on non-standard port (if configured)
- [ ] Fail2ban or similar brute force protection enabled

---

## Network-Layer Security

### CrowdSec IP Reputation

**Level 1 (Critical):**
- [ ] CrowdSec service running and healthy
- [ ] Traefik bouncer plugin active and blocking decisions
- [ ] At least 10 active scenarios loaded
- [ ] CrowdSec LAPI reachable by bouncer

```bash
# Verify CrowdSec is running
systemctl --user is-active crowdsec.service

# Check bouncer registration
podman exec crowdsec cscli bouncers list | grep traefik-bouncer

# Verify scenarios loaded
podman exec crowdsec cscli scenarios list | grep -E "enabled.*\btrue\b" | wc -l
# Expected: >=10
```

**Level 2 (Important):**
- [ ] CrowdSec connected to Central API (community threat intel)
- [ ] Bouncer blocklist size reasonable (not empty, not >10k unless under attack)
- [ ] Alert webhooks configured (Discord/Slack)
- [ ] CrowdSec logs show no authentication errors with bouncer

```bash
# Check Central API enrollment
podman exec crowdsec cscli capi status

# Check current block list size
podman exec crowdsec cscli decisions list | wc -l

# Check recent alerts
podman exec crowdsec cscli alerts list --since 24h
```

**Level 3 (Best Practice):**
- [ ] Custom scenarios configured for homelab-specific threats
- [ ] CrowdSec metrics exported to Prometheus
- [ ] Correlation with Traefik rate limiting and Authelia auth failures
- [ ] Monthly review of top blocked IPs and threat patterns

### Network-Layer Security Monitoring (UniFi)

**Level 1 (Critical):**
- [ ] Unpoller service running and authenticated to UDM Pro
- [ ] Prometheus successfully scraping Unpoller metrics (unpoller:9130)
- [ ] UDM Pro availability SLO >99.9% (43 min/month error budget)
- [ ] DPI security threat alerts configured and routed to Discord

```bash
# Verify Unpoller is running
systemctl --user is-active unpoller.service

# Check Prometheus scraping
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="unpoller") | .health'
# Expected: "up"

# Check DPI threat detection is active
curl -s 'http://localhost:9090/api/v1/query?query=homelab:dpi_security_bytes:rate5m' | jq '.data.result[0].value[1]'
# Expected: "0" (no threats currently)

# Verify alert rules loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="unifi_critical") | .rules[] | .name'
# Expected: UDMProDown, ExtremeBandwidthSpike, DPISecurityThreatDetected, etc.
```

**Level 2 (Important):**
- [ ] 7-day bandwidth baseline established for anomaly detection
- [ ] Firewall block correlation with CrowdSec IP bans configured
- [ ] Port forwarding traffic to homelab (80/443 → 192.168.1.70) is monitored
- [ ] VPN client presence detection working (for Home Assistant integration)
- [ ] Recording rules pre-computing expensive queries (12 rules)

```bash
# Check 7-day bandwidth baseline
curl -s 'http://localhost:9090/api/v1/query?query=avg_over_time(homelab:bandwidth_bytes_per_second:rate5m[7d])' | jq '.data.result[0].value[1]'
# Expected: Numeric value (baseline traffic rate)

# Verify recording rules are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="unifi_metrics") | .rules | length'
# Expected: 12

# Check VPN client count
curl -s 'http://localhost:9090/api/v1/query?query=homelab:vpn_clients:count' | jq '.data.result[0].value[1]'

# Verify firewall blocks are tracked
curl -s 'http://localhost:9090/api/v1/query?query=homelab:firewall_blocks_per_minute:rate5m' | jq '.data.result[0].value[1]'
```

**Level 3 (Best Practice):**
- [ ] Security Overview dashboard enhanced with UniFi panels (6 panels planned)
- [ ] SLO burn rate alerts tuned (tiered: 1h, 6h, 24h, 7d windows)
- [ ] Loki log aggregation for Unpoller logs (Phase 2 Matter automation plan)
- [ ] Incident response runbook IR-005 tested and validated
- [ ] Monthly review of DPI classifications and threat patterns

```bash
# Check SLO burn rate
curl -s 'http://localhost:9090/api/v1/query?query=slo:udm_availability:error_budget_burn_rate_1h' | jq '.data.result[0].value[1]'
# Expected: <1.0 (sustainable burn rate)

# Verify 3 UniFi dashboards imported
ls -1 ~/containers/config/grafana/provisioning/dashboards/json/unifi-*.json | wc -l
# Expected: 3 (client-insights, network-sites, usw)
```

---

## Application Security

### Traefik Reverse Proxy

**Level 1 (Critical):**
- [ ] Traefik service running and healthy
- [ ] TLS certificates valid and auto-renewing (Let's Encrypt)
- [ ] CrowdSec bouncer middleware active on all public routes
- [ ] Security headers middleware applied (HSTS, CSP, X-Frame-Options)

```bash
# Verify Traefik is running
systemctl --user is-active traefik.service

# Check Let's Encrypt certificates
podman exec traefik ls -lh /letsencrypt/acme.json
# Expected: File exists, >1KB size

# Test public endpoint has security headers
curl -I https://grafana.patriark.org | grep -E "Strict-Transport-Security|X-Frame-Options|Content-Security-Policy"
```

**Level 2 (Important):**
- [ ] Rate limiting configured (tiered: global 50/min, auth 10/min, API 30/min)
- [ ] Middleware ordering correct: CrowdSec → Rate Limit → Authelia → Headers
- [ ] Dashboard access protected by Authelia
- [ ] Access logs shipped to Loki for analysis

```bash
# Check middleware configuration
grep -A 10 "http.middlewares" ~/containers/config/traefik/dynamic/middleware.yml

# Verify rate limiting is active
curl -I https://traefik.patriark.org/api/overview | grep -i "rate"
```

**Level 3 (Best Practice):**
- [ ] TLS 1.3 preferred, TLS 1.2 minimum
- [ ] HTTP/2 enabled for performance
- [ ] Compression enabled (gzip/brotli)
- [ ] Custom 404/403 error pages configured

### Container Security

**Level 1 (Critical):**
- [ ] All containers run rootless (UID 1000, not root)
- [ ] SELinux enforcing mode enabled
- [ ] No containers running with `--privileged` flag
- [ ] Volume mounts use `:Z` SELinux label for proper context

```bash
# Verify all containers rootless
podman ps --format "{{.Names}}\t{{.Mounts}}" | grep -v ":Z"
# Expected: Empty output (all mounts have :Z)

# Check SELinux mode
getenforce
# Expected: Enforcing
```

**Level 2 (Important):**
- [ ] Container images use specific tags (not `:latest` for databases)
- [ ] Health checks defined in quadlet files
- [ ] No exposed ports outside intended scope (check `ss -tulnp`)
- [ ] Secrets managed via podman secrets (Pattern 2: type=env)

```bash
# Check for containers using :latest inappropriately
podman ps --format "{{.Names}}\t{{.Image}}" | grep -E "postgres|mariadb|redis" | grep ":latest"
# Expected: Empty (databases should be pinned)

# Verify podman secrets exist
podman secret ls
# Expected: Multiple secrets (authelia_*, unpoller_*, etc.)
```

**Level 3 (Best Practice):**
- [ ] Container vulnerability scanning enabled (Trivy/Grype)
- [ ] Regular container updates (weekly check for security patches)
- [ ] Resource limits defined (memory, CPU)
- [ ] Network segmentation enforced (5 networks for trust boundaries)

---

## Monitoring & Observability

### Prometheus Metrics

**Level 1 (Critical):**
- [ ] Prometheus service running and healthy
- [ ] All critical services exporting metrics (Traefik, Authelia, Unpoller, Node Exporter)
- [ ] Recording rules loaded and evaluating
- [ ] Alert rules loaded and routed to Alertmanager

```bash
# Verify Prometheus is running
systemctl --user is-active prometheus.service

# Check health
curl -f http://localhost:9090/-/healthy

# Verify all targets are up
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health=="down") | .labels.job]'
# Expected: [] (empty array, all targets up)

# Check recording rules
curl -s http://localhost:9090/api/v1/rules | jq '[.data.groups[].rules[] | select(.type=="recording")] | length'
# Expected: >12 (UniFi + other recording rules)
```

**Level 2 (Important):**
- [ ] Prometheus retention configured (default: 15 days)
- [ ] TSDB disk usage <80% of available space
- [ ] No gaps in time series data (check for scrape failures)
- [ ] Grafana dashboards loading successfully

```bash
# Check Prometheus storage size
du -sh ~/containers/data/prometheus/

# Check for scrape failures
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.lastError!="")] | length'
# Expected: 0 (no scrape errors)
```

**Level 3 (Best Practice):**
- [ ] Custom recording rules for complex queries
- [ ] Metric cardinality monitoring (prevent explosion)
- [ ] Prometheus remote write configured (optional: long-term storage)

### Alertmanager

**Level 1 (Critical):**
- [ ] Alertmanager service running and healthy
- [ ] Discord webhook configured and tested
- [ ] Alert routing configured (component: network → discord-critical)
- [ ] At least one alert route defined

```bash
# Verify Alertmanager is running
systemctl --user is-active alertmanager.service

# Check health
curl -f http://localhost:9093/-/healthy

# Test alert routing (check recent alerts)
curl -s http://localhost:9093/api/v2/alerts | jq 'length'
```

**Level 2 (Important):**
- [ ] Alert silences configured for maintenance windows
- [ ] Grouping configured to prevent alert storms
- [ ] Repeat interval appropriate (default: 4 hours)
- [ ] Alert history logged to remediation-decision-log.md

**Level 3 (Best Practice):**
- [ ] PagerDuty/Opsgenie integration for critical alerts (optional)
- [ ] Alert escalation policies defined
- [ ] Monthly review of alert noise and false positives

### Grafana Dashboards

**Level 1 (Critical):**
- [ ] Grafana service running and healthy
- [ ] Prometheus datasource configured and working
- [ ] At least one dashboard per category: Security, Monitoring, UniFi, SLO
- [ ] Dashboard provisioning directory readable by Grafana

```bash
# Verify Grafana is running
systemctl --user is-active grafana.service

# Check health
curl -f http://localhost:3000/api/health

# Count provisioned dashboards
ls -1 ~/containers/config/grafana/provisioning/dashboards/json/*.json | wc -l
# Expected: >3 (security-overview, SLO, UniFi dashboards, etc.)
```

**Level 2 (Important):**
- [ ] Loki datasource configured for log queries
- [ ] Dashboard refresh intervals reasonable (not <5s)
- [ ] No dashboards with "No data" panels (indicates broken queries)
- [ ] Dashboard JSON files under version control

**Level 3 (Best Practice):**
- [ ] Dashboard variables used for filtering (IP, service, timerange)
- [ ] Annotations configured for alerts and deployments
- [ ] Public snapshot sharing disabled (security)

---

## Operational Security

### Secrets Management

**Level 1 (Critical):**
- [ ] No plaintext secrets in Git repository
- [ ] `.gitignore` excludes: `*.key`, `*.pem`, `*secret*`, `*.env`, `acme.json`
- [ ] Podman secrets used for sensitive credentials (not EnvironmentFile)
- [ ] GPG signing enabled for Git commits

```bash
# Check for accidentally committed secrets
git log --all --full-history --source -- "**/*secret*" "**/*.env" "**/*.key"
# Expected: Empty output

# Verify podman secrets pattern
grep -r "Secret=" ~/.config/containers/systemd/*.container | wc -l
# Expected: >3 (multiple services using secrets)

# Check GPG signing
git config --get commit.gpgsign
# Expected: true
```

**Level 2 (Important):**
- [ ] Annual secret rotation schedule documented
- [ ] Secrets backup procedure defined and tested
- [ ] Secrets access limited (file permissions 600)
- [ ] No secrets in command history or scripts

```bash
# Check secret file permissions
ls -l ~/.local/share/containers/storage/secrets/
# Expected: Files owned by user, not world-readable
```

**Level 3 (Best Practice):**
- [ ] External secrets manager considered (Vault, Bitwarden Secrets)
- [ ] Secrets version controlled outside main repo (encrypted)
- [ ] Automated secret rotation for long-lived credentials

### Backup & Disaster Recovery

**Level 1 (Critical):**
- [ ] Critical data backed up: Authelia users_database.yml, Prometheus data, Grafana dashboards
- [ ] BTRFS snapshots configured (automatic daily)
- [ ] Backup retention policy defined (7 daily, 4 weekly, 12 monthly)
- [ ] At least one off-site backup location

```bash
# Check BTRFS snapshots exist
sudo btrfs subvolume list /mnt/btrfs-pool | grep snapshot | wc -l
# Expected: >7 (daily snapshots)

# Verify backup script exists
ls -lh ~/containers/scripts/*backup*.sh
```

**Level 2 (Important):**
- [ ] Disaster recovery runbooks exist (DR-001 through DR-004)
- [ ] Recovery procedures tested in last 6 months
- [ ] Backup integrity checks automated (weekly)
- [ ] Backup logs reviewed monthly

**Level 3 (Best Practice):**
- [ ] Encrypted off-site backups (Backblaze B2, rsync.net)
- [ ] Database backups include consistency checks
- [ ] Infrastructure-as-code allows full redeploy from Git

---

## Vulnerability Management

### Scanning & Patching

**Level 1 (Critical):**
- [ ] Automated vulnerability scanning enabled (weekly)
- [ ] CRITICAL and HIGH severity CVEs patched within 7 days
- [ ] Fedora system updates applied monthly
- [ ] Container images updated for security patches

```bash
# Run vulnerability scan
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH

# Check for pending system updates
dnf check-update | grep -i security

# Last system update date
rpm -qa --last | head -1
```

**Level 2 (Important):**
- [ ] CVE notifications configured (email/RSS)
- [ ] Vulnerability scan reports archived
- [ ] Medium severity CVEs reviewed and scheduled
- [ ] Container base images kept up-to-date

**Level 3 (Best Practice):**
- [ ] SBOM (Software Bill of Materials) generated for containers
- [ ] Dependency update automation (Dependabot/Renovate)
- [ ] Zero-day vulnerability response plan documented

---

## Compliance & Audit Trail

### Logging & Audit Trail

**Level 1 (Critical):**
- [ ] Loki service running and ingesting logs
- [ ] Promtail shipping container logs to Loki
- [ ] Remediation decisions logged to decision log
- [ ] Security events logged with timestamps

```bash
# Verify Loki is running
systemctl --user is-active loki.service promtail.service

# Check Loki health
curl -f http://localhost:3100/ready

# Check recent log ingestion
curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}' | jq '.data.result | length'
# Expected: >0 (logs being ingested)
```

**Level 2 (Important):**
- [ ] Log retention policy defined (default: 30 days)
- [ ] Critical security events have Loki labels for filtering
- [ ] Correlation queries documented (Loki Remediation Queries guide)
- [ ] Log volume monitored (prevent disk exhaustion)

**Level 3 (Best Practice):**
- [ ] Log aggregation includes UDM Pro logs (via syslog)
- [ ] Automated log analysis for anomaly detection
- [ ] Compliance reporting (PCI-DSS, SOC2 controls if applicable)

### Configuration Drift Detection

**Level 1 (Critical):**
- [ ] All configuration under version control (Git)
- [ ] Drift detection script runs monthly
- [ ] Critical services have drift alerts configured
- [ ] Configuration changes reviewed before commit

```bash
# Run drift detection
~/containers/scripts/check-drift.sh

# Check for uncommitted changes
git status --short
# Expected: Empty (all changes committed)
```

**Level 2 (Important):**
- [ ] ADRs (Architecture Decision Records) up-to-date
- [ ] Configuration changes include rationale in commit message
- [ ] Breaking changes documented in CHANGELOG
- [ ] Pre-commit hooks enforce standards

**Level 3 (Best Practice):**
- [ ] Automated configuration validation (CI/CD checks)
- [ ] Policy-as-code enforcement (OPA/Sentinel)
- [ ] Infrastructure state reconciliation

---

## Audit Execution

### Manual Monthly Audit

**Process:**
1. Review this checklist section by section
2. Execute verification commands for Level 1 and Level 2 items
3. Document findings in `docs/99-reports/security-audit-YYYY-MM.md`
4. Create remediation tasks for failures
5. Update this guide if new checks are identified

**Automated Checks:**
```bash
# Run comprehensive security audit
~/containers/scripts/security-audit.sh

# Check homelab intelligence report
~/containers/scripts/homelab-intel.sh --detailed

# Review autonomous operations decisions
~/containers/.claude/context/scripts/query-decisions.sh --last 30d --stats
```

### Reporting

**Template:** `docs/99-reports/security-audit-YYYY-MM.md`

```markdown
# Security Audit Report: YYYY-MM

**Date:** YYYY-MM-DD
**Auditor:** [Name]
**Duration:** [X hours]

## Executive Summary
[Overall security posture: Excellent / Good / Needs Improvement / Critical Issues]

## Findings Summary
- Level 1 (Critical): [X/Y passed]
- Level 2 (Important): [X/Y passed]
- Level 3 (Best Practice): [X/Y passed]

## Failed Checks
[List of failed checks with severity]

## Remediation Plan
[Action items with target dates]

## Improvements Since Last Audit
[List of security enhancements completed]

## Next Steps
[Focus areas for next month]
```

---

## Related Documentation

- [CrowdSec Phase 1 Field Manual](./crowdsec-phase1-field-manual.md)
- [Secrets Management Guide](./secrets-management.md)
- [SSH Hardening Guide](./ssh-hardening.md)
- [UniFi Security Monitoring Guide](../../40-monitoring-and-documentation/guides/unifi-security-monitoring.md)
- [SLO Framework](../../40-monitoring-and-documentation/guides/slo-framework.md)
- [Incident Response Runbooks](../runbooks/)

---

**End of Guide**
