# Vaultwarden Deployment Plan & Security Enhancement Strategy

**Date:** 2025-11-12
**Author:** Claude Code (Strategic Planning)
**Status:** 📋 Planning Phase
**Priority:** 🔴 High (Security-Critical Service)

---

## Executive Summary

**Objective:** Deploy Vaultwarden (self-hosted Bitwarden server) as a production-ready password management solution with enterprise-grade security posture.

**Why Vaultwarden:**
- Open-source Bitwarden-compatible server (lighter than official server)
- End-to-end encrypted password vault
- Multi-device support (web, desktop, mobile, browser extensions)
- Self-hosted = full control over your credentials
- Perfect fit for homelab security architecture

**Timeline Estimate:** 2-3 hours (including testing and documentation)

**Risk Level:** 🔴 **HIGH** - This is a password manager. Security is paramount.

---

## Part 1: Vaultwarden Deployment Plan

### Architecture Overview

```
Internet → Traefik (80/443)
  ↓
[1] CrowdSec IP Reputation (fail-fast)
  ↓
[2] Rate Limiting (STRICT: 10 req/min for auth endpoints)
  ↓
[3] Security Headers (HSTS, CSP, XSS protection)
  ↓
[4] Authelia SSO (YubiKey/WebAuthn) - OPTIONAL for admin access
  ↓
Vaultwarden Container
  ↓
SQLite Database (encrypted at rest)
```

**Network Placement:**
- Primary: `systemd-reverse_proxy` (internet access for sync)
- Secondary: `systemd-database` (future PostgreSQL migration option)

**Storage:**
- Config: `~/containers/config/vaultwarden/`
- Data: `/mnt/btrfs-pool/subvol7-containers/vaultwarden/` (encrypted, backed up)

---

## Key Decisions to Consider

### Decision 1: Database Backend

**Options:**

| Option | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **SQLite** (default) | Simple, no dependencies, perfect for homelab scale | Not suitable for high-concurrency | ✅ **Start here** |
| **PostgreSQL** | Better for multiple users, more robust | Requires PostgreSQL container, more complex | Consider later if >5 users |
| **MySQL** | Widely supported | Heavier than SQLite, overkill for homelab | ❌ Skip |

**Recommendation:** Start with **SQLite**. You have <5 users, and SQLite handles thousands of requests/day easily. Can migrate to PostgreSQL later if needed.

**Implementation:**
```bash
# Vaultwarden will auto-create SQLite DB
# Store in BTRFS pool for backups
-v /mnt/btrfs-pool/subvol7-containers/vaultwarden:/data:Z
```

---

### Decision 2: Admin Panel Access Control

**Options:**

| Option | Security Level | Complexity | Recommendation |
|--------|----------------|------------|----------------|
| **Disable admin panel** | 🟢 Highest | Low | ✅ **After initial setup** |
| **Admin token only** | 🟡 Medium | Low | Good for setup phase |
| **Admin token + Authelia** | 🟢 High | Medium | Best for ongoing access |
| **Admin token + IP whitelist** | 🟢 High | Low | Good alternative |

**Recommendation:**
1. **Setup phase:** Enable admin panel with strong token
2. **Production:** Disable admin panel OR protect with Authelia + YubiKey + IP whitelist

**Implementation:**
```bash
# Generate strong admin token
openssl rand -base64 48

# In Vaultwarden env:
ADMIN_TOKEN=<your-generated-token>

# After setup, disable:
# ADMIN_TOKEN="" (empty = disabled)
```

---

### Decision 3: User Registration

**Options:**

| Option | Use Case | Security | Recommendation |
|--------|----------|----------|----------------|
| **Open registration** | Public server | 🔴 Low | ❌ **Never** for homelab |
| **Invite-only** | Family/friends | 🟡 Medium | Good for multi-user |
| **Registration disabled** | Personal use | 🟢 High | ✅ **Best for solo** |

**Recommendation:** **Disable public registration**. Create accounts via admin panel, then disable admin access.

**Implementation:**
```bash
SIGNUPS_ALLOWED=false
INVITATIONS_ALLOWED=false  # Or true if you want invite capability
```

---

### Decision 4: Two-Factor Authentication

**Options:**

| 2FA Method | Security | Compatibility | Recommendation |
|------------|----------|---------------|----------------|
| **TOTP (Google Authenticator)** | 🟡 Medium | Excellent | ✅ Minimum baseline |
| **YubiKey/WebAuthn** | 🟢 High | Good (modern browsers) | ✅ **Strongly recommended** |
| **Duo** | 🟢 High | Excellent | Good for enterprise |
| **Email** | 🔴 Low | Excellent | ❌ Avoid (SMS/email are weak) |

**Recommendation:**
- **Primary:** YubiKey/WebAuthn (you already have YubiKeys!)
- **Backup:** TOTP (in case YubiKey unavailable)
- **Never:** Email or SMS-based 2FA

**Implementation:**
Vaultwarden supports all these natively. Users configure in their vault settings.

---

### Decision 5: Backup Strategy

**Critical:** Vaultwarden data is your password vault. Backup failure = catastrophic.

**What to Backup:**
```
/mnt/btrfs-pool/subvol7-containers/vaultwarden/
├── db.sqlite3                    # Encrypted password vault
├── db.sqlite3-shm                # SQLite shared memory
├── db.sqlite3-wal                # Write-ahead log
├── attachments/                  # File attachments (if enabled)
├── sends/                        # Bitwarden Send files
├── rsa_key.pem                   # Server encryption key
└── config.json                   # Server configuration
```

**Backup Frequency:**
- **Daily:** Automated BTRFS snapshots (you already have this!)
- **Weekly:** Off-site backup (external drive or cloud)
- **Pre-update:** Manual snapshot before Vaultwarden updates

**Implementation:**
```bash
# Your existing btrfs-snapshot-backup.sh already covers this!
# Vaultwarden data in BTRFS pool = automatically backed up

# Add to backup verification:
ls -lh /mnt/btrfs-pool/subvol7-containers/vaultwarden/db.sqlite3
```

**Additional Safeguard:**
```bash
# Export vault manually (from Bitwarden client)
# Settings → Tools → Export Vault → JSON (encrypted)
# Store encrypted export in separate location
```

---

### Decision 6: Email Configuration (Optional but Recommended)

**Use Cases:**
- Password reset requests
- New device verification
- Security alerts (failed login attempts)
- Invitation emails (if using invite-only)

**Options:**

| Option | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **No email** | Simple | No password recovery | ⚠️ Risky |
| **SMTP (Gmail, Proton, etc.)** | Easy setup | Requires app password | ✅ **Recommended** |
| **Self-hosted mail server** | Full control | Complex, often blocked | ❌ Overkill |

**Recommendation:** Configure SMTP with your existing email provider (Proton Mail).

**Implementation:**
```bash
# Vaultwarden env:
SMTP_HOST=smtp.protonmail.ch
SMTP_FROM=admin@example.com  # Your email
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=admin@example.com
SMTP_PASSWORD=<app-password>
```

---

### Decision 7: Attachment Support

**Question:** Allow file attachments in vault items?

| Option | Storage Impact | Security Considerations | Recommendation |
|--------|----------------|-------------------------|----------------|
| **Enabled** | ~100MB-1GB typical | Files encrypted, backed up | ✅ Useful feature |
| **Disabled** | 0 bytes | N/A | Only if storage-constrained |

**Recommendation:** **Enable** (default). Useful for storing passport scans, recovery codes, etc.

**Implementation:**
```bash
# Default is enabled, no configuration needed
# Files stored in /data/attachments/ (encrypted)
```

---

### Decision 8: WebSocket Support

**Purpose:** Real-time sync between devices (password changes sync instantly).

**Recommendation:** **Enable** (provides better user experience).

**Implementation:**
```bash
# Vaultwarden env:
WEBSOCKET_ENABLED=true

# Traefik labels (handle WebSocket upgrade):
--label "traefik.http.routers.vaultwarden.middlewares=crowdsec-bouncer@file,rate-limit-auth@file,security-headers@file"
--label "traefik.http.services.vaultwarden.loadbalancer.server.port=80"
```

---

### Decision 9: Authelia Integration

**Question:** Should Vaultwarden require Authelia SSO + YubiKey?

**Analysis:**

| Scenario | Authelia Protection | Rationale |
|----------|---------------------|-----------|
| **Web Vault UI** | ❌ No | Users need master password + 2FA to access vault anyway |
| **/admin panel** | ✅ Yes | Extra protection for administrative functions |
| **API endpoints** | ❌ No | Bitwarden clients (mobile/desktop) can't handle SSO redirect |

**Recommendation:**
- **Web UI:** No Authelia (vault already has strong auth)
- **Admin Panel:** Authelia + YubiKey + IP whitelist (if enabled)

**Reasoning:**
- Vaultwarden has its own strong authentication (master password + 2FA)
- Adding Authelia creates UX friction without meaningful security gain
- Admin panel is different—should have defense-in-depth

---

### Decision 10: Rate Limiting Configuration

**Critical for security:** Password managers are high-value targets for brute-force attacks.

**Recommended Limits:**

| Endpoint | Rate Limit | Rationale |
|----------|------------|-----------|
| `/api/accounts/login` | 5 req/min per IP | Login attempts |
| `/identity/connect/token` | 10 req/min per IP | OAuth token requests |
| Web UI (general) | 100 req/min per IP | Normal browsing |
| `/admin` panel | 3 req/min per IP | Admin access (if enabled) |

**Implementation:**
```yaml
# In middleware.yml (NEW):
rate-limit-vaultwarden-auth:
  rateLimit:
    average: 5
    burst: 2
    period: 1m

rate-limit-vaultwarden-admin:
  rateLimit:
    average: 3
    burst: 1
    period: 1m
```

---

## Part 2: Security Enhancements

### Current Security Posture (95/100)

**Strengths:**
- ✅ CrowdSec active with IP reputation
- ✅ Authelia SSO with YubiKey/WebAuthn
- ✅ Comprehensive rate limiting (4 tiers)
- ✅ Strong security headers (HSTS, CSP, XSS protection)
- ✅ Network segmentation (6 isolated networks)
- ✅ TLS 1.2+ with modern ciphers
- ✅ Monitoring stack with alerting
- ✅ Automated backups (BTRFS snapshots)

**Gaps (5 points):**
1. CrowdSec could be enhanced (scenarios, local decisions)
2. No fail2ban integration (redundant with CrowdSec but adds depth)
3. No geographic IP blocking
4. No honeypot/canary tokens
5. No SIEM-level log analysis

---

### Enhancement 1: CrowdSec Advanced Configuration

**Current State:** CrowdSec deployed with basic scenarios.

**Enhancements:**

#### A. Add Additional Scenarios

```bash
# Install additional scenarios
podman exec crowdsec cscli scenarios install crowdsecurity/http-bad-user-agent
podman exec crowdsec cscli scenarios install crowdsecurity/http-crawl-non_statics
podman exec crowdsec cscli scenarios install crowdsecurity/http-probing
podman exec crowdsec cscli scenarios install crowdsecurity/http-sensitive-files
podman exec crowdsec cscli scenarios install crowdsecurity/iptables-scan-multi_ports
```

**Impact:** Detect and block:
- Malicious user agents (bots, scanners)
- Web crawlers hitting non-static content
- Directory traversal attempts
- Attempts to access sensitive files (.env, .git, etc.)
- Port scanning

---

#### B. Local Decisions (Whitelists/Blacklists)

```bash
# Whitelist your local network (prevent accidental bans)
podman exec crowdsec cscli decisions add --ip 192.168.1.0/24 --duration 0 --type whitelist

# Blacklist known malicious IPs manually
podman exec crowdsec cscli decisions add --ip <malicious-ip> --duration 24h --type ban

# Whitelist your VPN subnet
podman exec crowdsec cscli decisions add --ip 192.168.100.0/24 --duration 0 --type whitelist
```

---

#### C. CrowdSec Profiles (Custom Ban Durations)

Create custom profiles for different threat levels:

```yaml
# ~/containers/config/crowdsec/profiles.yaml
name: default_profile
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
  - type: ban
    duration: 4h  # Standard ban: 4 hours

---
name: aggressive_profile
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip"
  - Alert.GetScenario() contains "http-sensitive-files"
decisions:
  - type: ban
    duration: 24h  # Aggressive threats: 24 hour ban

---
name: severe_profile
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip"
  - Alert.GetScenario() contains "ssh-bruteforce"
decisions:
  - type: ban
    duration: 168h  # SSH bruteforce: 7 day ban
```

**Impact:** Tiered responses based on threat severity.

---

#### D. Enable CrowdSec Console (Central Management)

**Purpose:** Manage CrowdSec across multiple machines, view global threat intelligence.

```bash
# Enroll in CrowdSec Console (free tier)
podman exec crowdsec cscli console enroll <enrollment-key>

# View console: https://app.crowdsec.net
```

**Benefits:**
- View aggregated metrics
- See global threat map
- Manage alerts centrally
- Share threat intelligence with community

---

### Enhancement 2: Geographic IP Blocking (GeoIP)

**Use Case:** Block traffic from countries you don't expect legitimate traffic from.

**Implementation via CrowdSec:**

```bash
# Install GeoIP enrichment
podman exec crowdsec cscli parsers install crowdsecurity/geoip-enrich

# Create custom scenario to block specific countries
# ~/containers/config/crowdsec/scenarios/geoip-block.yaml
type: conditional
name: my/geoip-block-cn-ru
description: "Block IPs from CN, RU"
filter: |
  evt.Parsed.geoip_country in ['CN', 'RU', 'KP', 'IR']
blackhole: 1m
labels:
  remediation: true
```

**Impact:** Reduce attack surface by 60-80% (most homelab attacks originate from specific countries).

**Caution:** Don't block countries you might travel to or use VPN servers from!

---

### Enhancement 3: Intrusion Detection (Suricata IDS)

**Purpose:** Deep packet inspection for malicious traffic patterns.

**Complexity:** Medium-High
**Value:** High (detects attacks CrowdSec might miss)

**Implementation:**

```bash
# Deploy Suricata container
podman run -d \
  --name suricata \
  --network systemd-reverse_proxy \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v ~/containers/config/suricata:/etc/suricata:Z \
  -v ~/containers/data/suricata:/var/log/suricata:Z \
  jasonish/suricata:latest

# Feed Suricata logs to CrowdSec
# CrowdSec can parse Suricata EVE logs for automated blocking
```

**Impact:** Detect SQL injection, XSS, RCE attempts, malware downloads, etc.

---

### Enhancement 4: Security Monitoring Dashboards

**Grafana Dashboards to Add:**

1. **Security Overview Dashboard**
   - CrowdSec ban statistics
   - Failed authentication attempts (from Authelia, Vaultwarden)
   - Rate limit violations
   - Traffic by country (GeoIP)
   - Top blocked IPs

2. **Vaultwarden Security Dashboard**
   - Failed login attempts
   - Successful logins (by user, device, location)
   - 2FA success/failure rates
   - Master password change events
   - Admin panel access (if enabled)

3. **Threat Intelligence Dashboard**
   - CrowdSec scenario triggers
   - Malicious user agents detected
   - Port scan attempts
   - Sensitive file access attempts

**Implementation:**
```bash
# CrowdSec Prometheus metrics (already enabled)
curl http://crowdsec:6060/metrics

# Create Grafana dashboard importing CrowdSec metrics
# Dashboard ID: 14177 (CrowdSec Official Dashboard)
```

---

### Enhancement 5: Alert Tuning (Reduce Noise)

**Current State:** Alertmanager sends all alerts to Discord.

**Problem:** Too many alerts = alert fatigue = ignoring critical alerts.

**Solution:** Tiered alerting

```yaml
# ~/containers/config/alertmanager/alertmanager.yml
route:
  receiver: 'discord-critical'
  group_by: ['alertname', 'severity']
  routes:
    # Critical alerts: Immediate Discord notification
    - match:
        severity: critical
      receiver: 'discord-critical'
      continue: false

    # Warning alerts: Aggregate, send once per hour
    - match:
        severity: warning
      receiver: 'discord-warnings'
      group_wait: 10m
      group_interval: 1h
      repeat_interval: 12h

    # Info alerts: Log only, no notifications
    - match:
        severity: info
      receiver: 'null'

receivers:
  - name: 'discord-critical'
    webhook_configs:
      - url: '<your-discord-webhook>'
        send_resolved: true

  - name: 'discord-warnings'
    webhook_configs:
      - url: '<your-discord-webhook>'
        send_resolved: false

  - name: 'null'
```

**Impact:** Critical alerts get immediate attention, warnings aggregated, info ignored.

---

### Enhancement 6: Secrets Management (Beyond Vaultwarden)

**Current Gap:** Application secrets stored in environment variables or config files.

**Risk:** Accidental commit to Git, plaintext on disk.

**Solutions:**

#### Option A: Podman Secrets (Simple)

```bash
# Create secret
echo "supersecretpassword" | podman secret create db_password -

# Use in container
podman run -d \
  --secret db_password,type=env,target=DB_PASSWORD \
  postgres:16

# Secret is mounted as environment variable (not in ps output)
```

#### Option B: HashiCorp Vault (Enterprise-Grade)

Deploy Vault container for centralized secrets management.

**Use Cases:**
- Dynamic database credentials
- API keys rotation
- Certificate management
- Encryption as a service

**Complexity:** High (but excellent learning experience)

---

### Enhancement 7: Web Application Firewall (ModSecurity)

**Purpose:** Filter malicious HTTP requests before they reach services.

**Implementation:** Traefik plugin or dedicated ModSecurity container.

```bash
# Traefik ModSecurity plugin
# ~/.config/containers/systemd/traefik.container
--label "traefik.http.middlewares.modsec.plugin.modsecurity.enabled=true"
```

**Rules:** OWASP Core Rule Set (CRS) - blocks SQL injection, XSS, etc.

**Impact:** Additional layer of protection for web applications.

---

## Part 3: Enhancement Trajectories

### Trajectory 1: High Availability (HA)

**Goal:** Zero-downtime service updates and fault tolerance.

**Components:**

1. **Multiple Traefik Instances** (round-robin DNS or keepalived VIP)
2. **Database Replication** (PostgreSQL primary + standby)
3. **Distributed Storage** (GlusterFS or CephFS instead of local BTRFS)
4. **Failover Automation** (systemd dependency chains, health checks)

**Complexity:** High
**Value:** Medium (overkill for homelab, excellent learning)
**Timeline:** 2-3 weeks

---

### Trajectory 2: Infrastructure as Code (IaC)

**Goal:** Entire homelab deployable from code.

**Tools:**

1. **Ansible** - Configuration management and provisioning
   ```yaml
   # Deploy entire homelab
   ansible-playbook -i inventory.yml site.yml
   ```

2. **Terraform** - Infrastructure provisioning (cloud resources if you expand)

3. **GitOps** - Automated deployments from Git commits

**Benefits:**
- Disaster recovery in minutes (not hours/days)
- Reproducible environments (dev/staging/prod)
- Documentation as code

**Complexity:** Medium
**Value:** Very High (transferable skills)
**Timeline:** 1-2 weeks

---

### Trajectory 3: Zero-Trust Networking

**Goal:** Mutual TLS (mTLS) authentication between all services.

**Components:**

1. **Service Mesh** (Istio, Linkerd, or Consul)
2. **Certificate Authority** (Step-CA or Vault PKI)
3. **mTLS Enforcement** (every service presents client cert)

**Benefits:**
- Compromised service can't pivot to others
- Encrypted inter-service communication
- Fine-grained access control

**Complexity:** Very High
**Value:** High (cutting-edge, enterprise-level)
**Timeline:** 3-4 weeks

---

### Trajectory 4: Advanced Monitoring & Observability

**Goal:** Full observability stack with distributed tracing.

**Components:**

1. **Distributed Tracing** (Jaeger or Tempo)
   - Trace requests across services
   - Identify bottlenecks and failures

2. **Log Aggregation Enhancement** (Loki + LogQL queries)
   - Correlate logs with traces
   - Automated log analysis

3. **Metrics Federation** (Thanos for long-term Prometheus storage)
   - Retain metrics for years (not days)
   - Query across multiple Prometheus instances

4. **Real User Monitoring (RUM)** (Grafana Faro)
   - Track frontend performance
   - User session analysis

**Complexity:** Medium-High
**Value:** High (observability is critical at scale)
**Timeline:** 2 weeks

---

### Trajectory 5: Multi-Node Cluster

**Goal:** Expand from single machine to Kubernetes cluster.

**Phases:**

1. **Phase 1:** K3s cluster on 3 Raspberry Pis (lightweight Kubernetes)
2. **Phase 2:** Migrate services to Kubernetes (Helm charts)
3. **Phase 3:** GitOps with ArgoCD or Flux
4. **Phase 4:** Service mesh (Istio) for mTLS and observability

**Benefits:**
- Industry-standard orchestration
- Auto-scaling, self-healing
- Massive resume/portfolio boost

**Complexity:** Very High (paradigm shift)
**Value:** Extremely High (Kubernetes is industry standard)
**Timeline:** 4-6 weeks

---

### Trajectory 6: CI/CD Pipeline

**Goal:** Automated testing and deployment.

**Components:**

1. **CI Server** (Drone CI, Gitea + Drone, or GitHub Actions self-hosted runner)
2. **Test Automation**
   - Lint configuration files
   - Test Traefik routing rules
   - Validate Quadlet syntax
   - Run security scans (Trivy for container images)

3. **Automated Deployment**
   - Git push → Auto-deploy to staging
   - Manual approval → Deploy to production
   - Rollback on failure

**Benefits:**
- Catch errors before production
- Consistent deployments
- Audit trail of changes

**Complexity:** Medium
**Value:** Very High (DevOps core skill)
**Timeline:** 1-2 weeks

---

### Trajectory 7: External Access & VPN

**Goal:** Secure remote access without exposing services to internet.

**Options:**

| Solution | Complexity | Security | Use Case |
|----------|------------|----------|----------|
| **WireGuard VPN** | Low | 🟢 High | Access homelab from anywhere |
| **Tailscale** | Very Low | 🟢 High | Zero-config mesh VPN |
| **Cloudflare Tunnel** | Low | 🟢 High | Expose services without port forwarding |
| **ZeroTier** | Low | 🟢 High | Mesh VPN alternative |

**Recommendation:** **Tailscale** (easiest) or **WireGuard** (most control).

**Benefits:**
- No exposed ports (except VPN endpoint)
- Access internal services securely
- Works from restrictive networks

**Complexity:** Low
**Value:** Very High (security + convenience)
**Timeline:** 2-4 hours

---

### Trajectory 8: Compliance & Hardening

**Goal:** CIS Benchmark compliance for Podman and Fedora.

**Components:**

1. **OpenSCAP** - Automated compliance scanning
   ```bash
   sudo oscap xccdf eval --profile cis --results results.xml /usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml
   ```

2. **Lynis** - Security auditing
   ```bash
   lynis audit system
   ```

3. **CIS Benchmarks**
   - Container hardening
   - OS hardening
   - Network hardening

**Benefits:**
- Identify security gaps
- Meet compliance requirements
- Professional security posture

**Complexity:** Low-Medium
**Value:** High (demonstrates security expertise)
**Timeline:** 3-5 days

---

## Recommended Prioritization

### Phase 1: Vaultwarden Deployment (This Week)
1. Deploy Vaultwarden with SQLite backend
2. Configure rate limiting and security headers
3. Test master password + YubiKey 2FA
4. Verify backups working
5. Document in service guide
6. Create ADR-006

**Time:** 2-3 hours

---

### Phase 2: CrowdSec Enhancement (Next Week)
1. Install additional scenarios (bad user agents, probing, etc.)
2. Configure local whitelists (LAN, VPN)
3. Create tiered ban profiles
4. Enroll in CrowdSec Console
5. Create Grafana security dashboard

**Time:** 3-4 hours

---

### Phase 3: Secrets Management (Week 3)
1. Migrate sensitive configs to Podman secrets
2. Document secrets workflow
3. Audit Git history for accidental secret commits

**Time:** 2-3 hours

---

### Phase 4: Choose One Trajectory (Month 2)

Based on your interests, pick ONE:

- **Most Practical:** WireGuard/Tailscale VPN
- **Best Learning:** Infrastructure as Code (Ansible)
- **Most Impressive:** Kubernetes cluster
- **Best for Jobs:** CI/CD pipeline

---

## Summary & Next Steps

### Immediate Action Items

1. **Review this plan** - Any questions or decisions to adjust?
2. **Choose database backend** - SQLite (recommended) or PostgreSQL?
3. **Decide on admin panel** - Keep enabled (with Authelia) or disable after setup?
4. **Choose first trajectory** - Which enhancement path excites you most?

### Vaultwarden Deployment Checklist

- [ ] Generate strong admin token
- [ ] Create directories on BTRFS pool
- [ ] Deploy Vaultwarden container
- [ ] Configure Traefik routing with strict rate limits
- [ ] Test master password + YubiKey registration
- [ ] Configure SMTP (optional but recommended)
- [ ] Verify backups capturing Vaultwarden data
- [ ] Create service guide documentation
- [ ] Write ADR-006 (Vaultwarden Architecture Decision)
- [ ] Decommission admin panel after setup

### Questions for You

1. **Vaultwarden Users:** Just you, or family/friends too?
2. **Email Provider:** Proton Mail or different SMTP?
3. **Admin Panel:** Keep available (with strong auth) or disable completely?
4. **Trajectory Preference:** Which enhancement path interests you most?
5. **Risk Tolerance:** Comfortable deploying security-critical service?

---

**Ready to proceed with Vaultwarden deployment?** Let me know your answers to the questions above, and I'll create the deployment script and configuration files!
