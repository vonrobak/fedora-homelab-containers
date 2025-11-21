# Homelab Infrastructure Portfolio

**Project:** Production-Ready Self-Hosted Infrastructure
**Platform:** Fedora Workstation 42 | Podman Rootless Containers | systemd Quadlets
**Timeline:** October 2025 - Present
**Status:** Production (95/100 Health Score)

---

## Executive Summary

Designed and deployed a production-grade, self-hosted infrastructure platform running 16+ containerized services with enterprise-level reliability, security, and observability. Achieved 100% health check coverage, implemented phishing-resistant authentication (YubiKey/WebAuthn), and built AI-driven monitoring with trend analysis.

**Key Differentiators:**
- Enterprise-grade architecture on consumer hardware
- Rootless containers with SELinux enforcing mode (security-first)
- Configuration-as-code with comprehensive documentation (5 ADRs, 90+ docs)
- Proactive monitoring with AI-driven intelligence system

---

## Problem Statement

**Challenge:** Build a learning platform that demonstrates production-ready infrastructure skills while providing practical services (media streaming, photo management, monitoring).

**Constraints:**
- Consumer hardware (32GB RAM, 128GB SSD + 12TB HDD pool)
- Single-user initially, multi-user capable
- Zero budget for cloud services
- Security-first approach (public internet exposure)

**Goals:**
1. Demonstrate enterprise infrastructure patterns (SSO, monitoring, layered security)
2. Achieve production-level reliability (100% coverage, auto-recovery)
3. Implement modern authentication (phishing-resistant hardware 2FA)
4. Build comprehensive observability (metrics, logs, alerts, intelligence)
5. Create portfolio-quality documentation

---

## Technology Stack

### Core Infrastructure

**Container Runtime:**
- Podman 5.x (rootless, daemonless, OCI-compliant)
- systemd quadlets (native orchestration)
- SELinux enforcing mode (mandatory access control)

**Reverse Proxy & Security:**
- Traefik v3.3 (dynamic routing, Let's Encrypt ACME)
- CrowdSec (IP reputation, community-driven threat intelligence)
- Authelia 4.38 (SSO + WebAuthn/FIDO2)

**Monitoring & Observability:**
- Prometheus (metrics collection, 15-day retention)
- Grafana (visualization, dashboards)
- Loki (log aggregation, 7-day retention)
- Alertmanager (alert routing, Discord integration)

**Services:**
- Jellyfin (media streaming)
- Immich (photo management, ML processing)
- Homepage (service dashboard)

**Storage:**
- BTRFS (Copy-on-Write filesystem, snapshots)
- Automated backup strategy (7 daily, 4 weekly, 6 monthly)

### Development & Operations

**Configuration Management:**
- Git (version control, 400+ commits)
- Configuration-as-code (templates, no hardcoded secrets)
- Podman secrets (secure credential management)

**Documentation:**
- Architecture Decision Records (ADR methodology)
- Deployment journals (1,000+ lines of troubleshooting)
- Living service guides (kept current)

---

## Architecture

### High-Level Overview

```
                          Internet
                             |
                    Port Forward (80/443)
                             |
                    +--------v--------+
                    |    Traefik      |  ← Let's Encrypt (TLS)
                    | Reverse Proxy   |
                    +--------+--------+
                             |
        +--------------------+--------------------+
        |                    |                    |
   +----v-----+         +----v-----+        +----v-----+
   | CrowdSec |         |Authelia  |        | Services |
   |   IP     | ------> |   SSO    | -----> | (16 svc) |
   |Reputation|         | YubiKey  |        |          |
   +----------+         +----+-----+        +----------+
                             |
                        +----v-----+
                        |  Redis   |
                        | Sessions |
                        +----------+
```

### Security Layers (Fail-Fast Principle)

Requests flow through ordered middleware layers:

```
1. CrowdSec IP Reputation    (cache lookup - fastest)
   ↓ Reject known attackers
2. Rate Limiting             (memory check - fast)
   ↓ Throttle excessive requests
3. Authelia SSO              (YubiKey + password - expensive)
   ↓ Hardware 2FA verification
4. Security Headers          (response modification)
   ↓ HSTS, CSP, X-Frame-Options
5. Backend Service           (authenticated request)
```

**Why this order matters:** Each layer is computationally more expensive than the previous. Reject malicious traffic immediately (CrowdSec) before wasting resources on authentication checks (Authelia).

### Network Segmentation

Services isolated into trust-based networks:

- `systemd-reverse_proxy` - Traefik + externally accessible services
- `systemd-auth_services` - Authelia, Redis (session storage)
- `systemd-media_services` - Jellyfin, media processing
- `systemd-photos` - Immich, PostgreSQL, Redis
- `systemd-monitoring` - Prometheus, Grafana, Loki, exporters

**Design principle:** Services join multiple networks only when inter-network communication required. First network determines default route.

---

## Key Achievements

### 1. Enterprise-Grade Authentication (ADR-005)

**Implementation:** Authelia SSO with YubiKey/WebAuthn

**Features:**
- Phishing-resistant hardware 2FA (FIDO2/WebAuthn)
- Single sign-on across 5+ admin services
- Redis-backed session management (1h expiration, 15m inactivity)
- Granular per-service access policies
- Mobile app compatibility (API bypass pattern)

**Technical Decisions:**
- **Dual authentication anti-pattern:** Discovered that layering SSO on top of native service authentication creates confusing UX and breaks mobile apps. Decision: Immich uses native auth only.
- **Rate limiting for SPAs:** Modern single-page applications load 15-20 assets on initial page load. Increased limit from 10 req/min to 100 req/min for SSO portal.
- **IP whitelisting deprecation:** YubiKey provides stronger security than IP-based access control. Removed redundant IP whitelist middleware.

**Result:** All admin services protected by phishing-resistant authentication, zero successful phishing attempts possible.

### 2. 100% Health Check & Resource Limit Coverage

**Achievement:** All 16 services have health checks and resource limits

**Coverage Metrics:**
- Health checks: 16/16 (100%)
- Resource limits: 16/16 (100%)
- Auto-recovery: `Restart=on-failure` on all services

**Technical Implementation:**
- `HealthCmd` in every quadlet (10-30s intervals)
- `MemoryMax` limits prevent OOM cascading failures
- systemd monitors health, auto-restarts unhealthy containers

**Business Value:**
- Prevents resource exhaustion (one service consuming all RAM)
- Automatic recovery from transient failures (network issues, etc.)
- Production-ready reliability (portfolio-worthy metric)

**Challenges Overcome:**
- **TinyAuth health check:** Initial endpoint `/api/auth/traefik` required Traefik headers. Solution: Changed to root endpoint `/` (login page).
- **cAdvisor port conflict:** Unnecessary port publishing caused race conditions. Solution: Removed port binding, use internal network access only.

### 3. AI-Driven Intelligence System

**Implementation:** Custom bash-based trend analysis tools

**Capabilities:**
- Analyzes system snapshots over time (memory, disk, service health)
- Statistical analysis (slope, mean, standard deviation)
- Automatic invalid data filtering (corrupted JSON)
- Predictive capacity planning (planned enhancement)

**Key Insight Discovered:**
- Memory optimization validation: Detected -1,152MB improvement (14,477MB → 13,325MB)
- Proactive rather than reactive monitoring
- Historical analysis: "What happened last Tuesday?"

**Technical Details:**
- `scripts/intelligence/lib/snapshot-parser.sh` - 250 lines of reusable functions
- `scripts/intelligence/simple-trend-report.sh` - Production-ready analyzer
- Processes 10+ snapshots spanning hours/days

### 4. Configuration-as-Code & Documentation Excellence

**Approach:** Architecture Decision Records (ADR methodology)

**Documentation Structure:**
- 5 ADRs documenting major architectural decisions
- 90+ markdown files (guides, journals, reports)
- 1,000+ lines of troubleshooting documentation
- Hybrid structure (living guides + immutable journals)

**Key ADRs:**
1. **ADR-001:** Rootless containers (security through least privilege)
2. **ADR-002:** systemd quadlets over docker-compose (native orchestration)
3. **ADR-003:** Monitoring stack architecture (Prometheus + Grafana + Loki)
4. **ADR-005:** Authelia SSO with YubiKey deployment

**Value:**
- Rationale preserved for future reference
- "Why not X?" questions answered
- Alternatives considered documented
- Immutable decisions (superseded, never edited)

---

## Technical Challenges & Solutions

### Challenge 1: Authelia Rate Limiting for Modern SPAs

**Problem:** SSO portal showed "There was an issue retrieving the current user state" error.

**Investigation:**
- Checked Authelia logs: No errors
- Checked Redis: PONG response (healthy)
- Checked Traefik logs: HTTP 429 (Too Many Requests) on multiple assets

**Root Cause:** Initial rate limit (10 req/min) insufficient for modern single-page applications. Authelia portal loads ~15-20 assets on initial page load (HTML, CSS, JS bundles, API calls).

**Solution:** Changed middleware from `rate-limit-auth` (10 req/min) to `rate-limit` (100 req/min).

**Lesson Learned:** Standard API rate limits don't account for asset-heavy modern web applications.

### Challenge 2: Immich Dual Authentication Anti-Pattern

**Problem:** Immich browser showed infinite spinning logo, mobile app reported "Server not reachable."

**Initial Approach:** Protect web UI with Authelia, bypass API endpoints for mobile apps (Jellyfin pattern).

**Investigation:**
- Browser console: `Failed to fetch dynamically imported module` (HTTP 500)
- JavaScript assets not matching bypass rules
- Mobile app broke after logout

**Root Cause:** Immich has THREE authentication surfaces (web UI, mobile app, API keys). Layering Authelia creates dual authentication:
1. User authenticates to Authelia (YubiKey)
2. Then authenticates to Immich (native login)

**Solution:** Removed Authelia protection entirely from Immich. Let service handle its own authentication consistently (web + mobile).

**Lesson Learned:** Not all services need SSO. Dual authentication creates UX problems. Choose one authentication system.

### Challenge 3: Database Encryption Key Mismatch

**Problem:** Authelia wouldn't start after changing secret mounting from environment variables to files.

**Error:** "the configured encryption key does not appear to be valid for this database"

**Root Cause:**
1. Initial deployment: Secrets as environment variables
2. Configuration change: Secrets as file mounts (default Podman behavior)
3. Database created with env var secrets, now using file-based secrets

**Solution:**
1. Stop Authelia
2. Backup database: `mv db.sqlite3 db.sqlite3.old`
3. Start Authelia (creates new database with current key)
4. Re-enroll YubiKeys and TOTP devices

**Lesson Learned:** Secret delivery method changes require database recreation. Podman secrets default to file mounts, not environment variables.

### Challenge 4: Browser WebAuthn Caching

**Problem:** YubiKey touches not registering in Firefox after configuration changes.

**Symptoms:**
- Vivaldi: YubiKey working ✅
- Firefox: Touch indicator lights up, browser doesn't register ❌
- LibreWolf: Same as Firefox ❌

**Root Cause:** Browser cached old WebAuthn configuration (when attestation was `none`/`discouraged`). Security-related settings cached aggressively.

**Solution:** Firefox → History → Right-click `sso.patriark.org` → "Forget About This Site"

**Result:** All three browsers working after clearing site data.

**Lesson Learned:** WebAuthn configuration changes may require clearing browser cache.

---

## Metrics & Results

### Reliability Metrics

**Health Check Coverage:** 100% (16/16 services)
- All services monitored via health checks
- Automatic restart on failure
- 30-second health check intervals

**Resource Limit Coverage:** 100% (16/16 services)
- All services have MemoryMax defined
- OOM protection prevents cascading failures

**Uptime:** 99%+ (production services)
- Downtime limited to planned maintenance
- Auto-recovery from transient failures

### Security Metrics

**Authentication:**
- 2x YubiKeys enrolled (WebAuthn/FIDO2)
- 100% phishing-resistant (hardware-bound)
- 5 admin services protected
- 0 successful phishing attempts possible

**Attack Surface:**
- 2 ports exposed (80/443) via Traefik
- All other ports blocked (firewall)
- CrowdSec IP reputation active
- 4-hour ban duration for detected threats

**TLS:**
- 7 domains with Let's Encrypt certificates
- Auto-renewal (zero manual intervention)
- TLS 1.2+ with modern ciphers only

### Performance Metrics

**Resource Usage:**
- Memory: 13.5GB / 32GB (42% utilization)
- CPU: <5% average (idle), spikes to 50-80% during ML processing
- System SSD: 65% utilized (83GB/128GB)

**Authentication Latency:**
- Session validation: <10ms (Redis lookup)
- Initial authentication: ~2-3 seconds (includes human YubiKey touch)
- Response time: <50ms (negligible overhead)

**Memory Optimization:**
- Baseline: 14,477MB
- Optimized: 13,325MB
- Improvement: -1,152MB (-8%)
- Validated via intelligence system trend analysis

### Monitoring & Observability

**Metrics Collection:**
- 7 Prometheus targets (node, containers, Traefik, Authelia)
- 15-second scrape interval
- 15-day retention

**Log Aggregation:**
- All container logs → Loki
- systemd journal → Loki
- 7-day retention

**Alerting:**
- 5 alert rules (CPU, memory, disk, service health, backups)
- Discord webhook notifications
- 4-hour repeat interval

---

## Skills Demonstrated

### Infrastructure & Operations

✅ **Container Orchestration**
- Podman rootless containers (security-first approach)
- systemd quadlets (native Linux orchestration)
- Multi-network architecture (network segmentation)

✅ **Service Reliability**
- 100% health check coverage
- 100% resource limit coverage
- Auto-recovery strategies
- High availability patterns

✅ **Monitoring & Observability**
- Prometheus metrics (pull-based monitoring)
- Grafana dashboards (visualization)
- Loki log aggregation (centralized logging)
- Alertmanager (alert routing, Discord integration)
- AI-driven trend analysis (proactive monitoring)

### Security

✅ **Authentication & Authorization**
- SSO implementation (Authelia)
- Hardware 2FA (YubiKey/WebAuthn/FIDO2)
- Session management (Redis-backed)
- Access control policies (per-service, group-based)

✅ **Defense in Depth**
- Layered security (CrowdSec → rate limiting → authentication)
- Network segmentation (trust-based isolation)
- Fail-fast architecture (computational efficiency)

✅ **Secrets Management**
- Podman secrets (secure credential storage)
- Configuration-as-code (templates in Git)
- .gitignore strategy (no secrets in repository)

### Software Engineering

✅ **Configuration Management**
- Infrastructure-as-code (quadlets, Traefik YAML)
- Git version control (400+ commits)
- Configuration templates (reusable patterns)

✅ **Documentation**
- Architecture Decision Records (ADR methodology)
- Technical writing (90+ markdown files)
- Troubleshooting documentation (1,000+ lines)
- Living guides vs immutable journals

✅ **Problem Solving**
- Root cause analysis (systematic debugging)
- Trade-off evaluation (alternatives considered)
- Iterative improvement (test → fail → fix → validate)

### DevOps & Automation

✅ **CI/CD Concepts**
- Automated deployments (health-aware scripts)
- Validation before success declaration
- Rollback procedures documented

✅ **Scripting & Automation**
- Bash scripting (intelligence system, deployment automation)
- systemd service management
- Automated backups (BTRFS snapshots)

---

## Project Evolution & Learning Journey

### Phase 1: Foundation (October 2025)

**Focus:** Core infrastructure and container orchestration

**Milestones:**
- Deployed Traefik reverse proxy with Let's Encrypt
- Configured rootless Podman with SELinux enforcing
- Established systemd quadlets pattern
- Network segmentation architecture

**Key Learning:** Rootless containers require `:Z` SELinux labels on all volume mounts.

### Phase 2: Security Hardening (October-November 2025)

**Focus:** Authentication, access control, threat detection

**Milestones:**
- Deployed CrowdSec (IP reputation)
- Implemented YubiKey SSH authentication
- Initial authentication with TinyAuth (basic password auth)
- Layered middleware architecture

**Key Learning:** Order middleware by computational cost (fail-fast principle).

### Phase 3: Observability (November 2025)

**Focus:** Monitoring, logging, alerting

**Milestones:**
- Deployed Prometheus + Grafana + Loki stack
- Configured Alertmanager with Discord notifications
- Built AI intelligence system (trend analysis)
- Achieved 100% health check coverage

**Key Learning:** Proactive monitoring (trend analysis) > reactive monitoring (alerts only).

### Phase 4: Enterprise Authentication (November 2025)

**Focus:** SSO, phishing-resistant authentication

**Milestones:**
- Replaced TinyAuth with Authelia SSO
- Enrolled 2x YubiKeys (WebAuthn/FIDO2)
- Migrated 5 admin services to YubiKey protection
- Documented dual-auth anti-pattern

**Key Learning:** Not all services need SSO. Consider UX implications, especially mobile apps.

---

## Transferable Skills to Enterprise Environments

### 1. Production-Ready Mindset

**Homelab Demonstration:**
- 100% health check coverage (all services monitored)
- Auto-recovery strategies (restart on failure)
- Resource limits (prevent cascading failures)

**Enterprise Application:**
- Kubernetes liveness/readiness probes
- Pod disruption budgets
- Resource quotas and limits

### 2. Security-First Architecture

**Homelab Demonstration:**
- Hardware 2FA (phishing-resistant)
- Layered security (defense in depth)
- Network segmentation (trust boundaries)

**Enterprise Application:**
- Zero-trust networking (BeyondCorp, etc.)
- Identity and Access Management (Okta, Azure AD)
- Service mesh security (Istio, Linkerd)

### 3. Infrastructure-as-Code

**Homelab Demonstration:**
- Configuration templates in Git
- Declarative service definitions (quadlets)
- Version-controlled changes

**Enterprise Application:**
- Terraform (infrastructure provisioning)
- Kubernetes manifests (application deployment)
- GitOps workflows (Flux, ArgoCD)

### 4. Observability & SRE Practices

**Homelab Demonstration:**
- Metrics, logs, alerts (three pillars)
- Proactive monitoring (trend analysis)
- Runbook documentation (troubleshooting guides)

**Enterprise Application:**
- SLIs, SLOs, SLAs (service-level objectives)
- Error budgets (balance velocity vs reliability)
- Incident response (on-call, post-mortems)

### 5. Documentation & Knowledge Sharing

**Homelab Demonstration:**
- ADRs (architectural decisions)
- Deployment journals (troubleshooting)
- Living guides (operational procedures)

**Enterprise Application:**
- Technical design documents (RFCs)
- Post-mortems (incident analysis)
- Runbooks (on-call procedures)

---

## Future Enhancements

### Planned Improvements

**Short-Term (1-2 months):**
- Security event monitoring (failed login alerts)
- Authentication analytics dashboard (Grafana)
- TinyAuth decommissioning (after confidence period)

**Medium-Term (3-6 months):**
- GPU acceleration (AMD ROCm for Immich ML - pending hardware validation)
- Additional services (Vaultwarden, Uptime Kuma)
- Off-site backups (encrypted remote storage)

**Long-Term (6-12 months):**
- Multi-user deployment (family/friends)
- Advanced access policies (time-based, geographic)
- High availability patterns (service redundancy)

### Lessons to Apply

1. **Start simple, add complexity when needed** - TinyAuth → Authelia migration happened when SSO became valuable, not prematurely.

2. **Fail fast, fail cheap** - Order operations by cost. Reject bad traffic before expensive operations.

3. **Document decisions AND rationale** - ADRs capture "why not X?" for future reference.

4. **Not all services need the same pattern** - Immich uses native auth, Jellyfin uses conditional auth, admin services use strict auth.

5. **Hardware 2FA > IP whitelisting** - YubiKey provides stronger security than geographic restrictions.

---

## Conclusion

This homelab project demonstrates production-ready infrastructure skills through practical implementation. From enterprise-grade authentication (phishing-resistant YubiKey 2FA) to comprehensive observability (metrics, logs, alerts, intelligence), the architecture reflects modern DevOps and SRE best practices.

**Key Takeaways:**
- 16 services running with 100% reliability coverage
- Phishing-resistant authentication protecting all admin interfaces
- AI-driven proactive monitoring (trend analysis)
- 90+ documentation files following ADR methodology
- Real-world problem-solving with documented trade-offs

**Portfolio Value:**
- Demonstrates depth (troubleshooting 1,000+ line deployment journals)
- Demonstrates breadth (security, monitoring, automation, documentation)
- Shows learning ability (iterative improvement, failed experiments documented)
- Proves judgment (when to add complexity, when to keep it simple)

---

## Repository & Contact

**Public Repository:** (To be created - sanitized version)

**Documentation:** 90+ markdown files
- Architecture Decision Records
- Service guides (living documentation)
- Deployment journals (troubleshooting records)
- System state reports (point-in-time snapshots)

**Project Status:** Production (Active Development)

---

**This portfolio piece demonstrates enterprise-grade infrastructure implementation, security-first architecture, and comprehensive documentation practices suitable for DevOps, SRE, or Platform Engineering roles.**
