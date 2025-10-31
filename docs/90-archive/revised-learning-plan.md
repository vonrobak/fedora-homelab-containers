cat > ~/containers/docs/REVISED-LEARNING-PLAN.md << 'EOF'
# Revised Homelab Learning Plan (Post Day 7)

**Date:** $(date +%Y-%m-%d)
**Status:** Week 1 Complete, Adjusting for Reality

---

## Completed: Week 1 (Days 1-7)

### Achievements ✅
- Rootless Podman mastery
- Container networking & DNS integration
- Systemd service management
- Quadlet infrastructure-as-code
- Traefik reverse proxy
- Authelia SSO with TOTP 2FA
- Production-grade secret management
- Forward authentication pattern

### Time Investment
- **Planned:** 7 days × 2-3 hours = 14-21 hours
- **Actual:** ~25 hours (extra troubleshooting on Days 6-7)
- **Lesson:** Complex integrations take longer than expected

### Key Insights
1. **Troubleshooting is learning** - The Redis/WebAuthn struggles taught more than smooth deployments
2. **Documentation debt compounds** - Authelia v4.39 quirks not well documented
3. **Perfect is enemy of done** - TOTP works, WebAuthn can wait
4. **Production pragmatism** - Sometimes "good enough" IS good enough

---

## Adjusted Goals Based on Reality

### Original Goal
> "Master self-hosting with production-grade security, automation, and monitoring"

### Reality Check
- ✅ Security: Strong foundation (2FA, secrets, isolation)
- ⚠️ Automation: Partial (Quadlets good, but manual configs)
- ❌ Monitoring: Not started yet
- ⚠️ Production-ready: Close, but needs TLS + email

### Revised Goal
> "Build a **secure, maintainable** homelab that can be **safely exposed to internet** with **proper monitoring**, while **learning deeply** rather than rushing"

**Key Changes:**
- Emphasize understanding over speed
- Accept imperfect solutions if documented
- Prioritize safety for internet exposure
- Build monitoring before going public

---

## Week 2: TLS, Email & Domain Setup (Days 8-14)

**Goal:** Get valid TLS certificates and email working

### Day 8: Let's Encrypt with Traefik
**Duration:** 3-4 hours

**Objectives:**
- Understand ACME protocol
- Configure Traefik with Let's Encrypt
- Set up DNS challenge (Cloudflare or Hostinger)
- Get wildcard certificate for `*.patriark.lokal`

**Deliverables:**
- Valid TLS certificates
- Automatic renewal configured
- No more browser warnings!

**Why This First:**
- Unblocks WebAuthn testing
- Required before internet exposure
- Foundation for all Week 2 work

---

### Day 9: Public Domain Setup (patriark.xyz)
**Duration:** 2-3 hours

**Objectives:**
- Register domain at Hostinger
- Configure DNS records
- Point to home public IP
- Test external access (from phone off WiFi)

**Deliverables:**
- `auth.patriark.xyz` → Home IP
- `jellyfin.patriark.xyz` → Home IP
- DNS propagated globally

**Security Note:** Don't expose services yet, just set up DNS

---

### Day 10: Email Notifications (SMTP)
**Duration:** 2-3 hours

**Objectives:**
- Configure Hostinger SMTP
- Update Authelia for email notifications
- Test password reset flow
- Set up security alerts

**Deliverables:**
- Email notifications working
- Password reset functional
- Failed login alerts configured

**Why Important:**
- Required for WebAuthn registration verification
- Security incident notifications
- Password recovery

---

### Day 11: WebAuthn Revisited
**Duration:** 2-3 hours

**Prerequisites:** Valid TLS + Email working

**Objectives:**
- Test WebAuthn with valid certificates
- Register all 3 YubiKeys via FIDO2
- Compare TOTP vs WebAuthn UX
- Document which to use when

**Deliverables:**
- All YubiKeys registered via WebAuthn
- Comparison doc: TOTP vs WebAuthn
- Decision: Keep TOTP as backup or primary?

---

### Day 12: Cloudflare Integration (Optional but Recommended)
**Duration:** 3-4 hours

**Objectives:**
- Set up Cloudflare proxy
- Enable DDoS protection
- Configure rate limiting rules
- Hide home IP address

**Deliverables:**
- Traffic routed through Cloudflare
- Home IP hidden
- DDoS protection active
- Rate limiting configured

**Why Cloudflare:**
- Free tier is excellent
- Hides home IP
- DDoS protection
- Built-in analytics

---

### Day 13-14: Security Hardening
**Duration:** 4-5 hours total

**Day 13: Firewall & Fail2ban**
- Configure firewall rules (only 80/443)
- Set up Fail2ban for Authelia
- Test from external network
- Document security posture

**Day 14: Backup Strategy**
- Automated daily backups
- Test restore procedure
- Off-site backup (encrypted USB or cloud)
- Disaster recovery doc

**Deliverables:**
- Comprehensive security documentation
- Tested backup/restore procedures
- Ready for internet exposure

---

## Week 3: Monitoring & Additional Services (Days 15-21)

**Goal:** Visibility into system health + expand service portfolio

### Day 15-16: Prometheus + Grafana
**Duration:** 6-8 hours total

**Objectives:**
- Deploy Prometheus for metrics
- Deploy Grafana for visualization
- Configure exporters (node, cadvisor, Authelia)
- Build dashboards

**Deliverables:**
- Real-time metrics for all containers
- Resource usage dashboards
- Authentication metrics
- Alert rules configured

---

### Day 17: Alerting (Alertmanager + Notifications)
**Duration:** 3-4 hours

**Objectives:**
- Deploy Alertmanager
- Configure Discord/Telegram/Email webhooks
- Set up alert rules:
  - Service down
  - High CPU/memory
  - Failed login attempts
  - Certificate expiry

**Deliverables:**
- Automated alerts to phone
- Escalation policies
- Alert fatigue prevention

---

### Day 18-19: Vaultwarden (Password Manager)
**Duration:** 5-6 hours total

**Objectives:**
- Deploy Vaultwarden (Bitwarden)
- Integrate with Authelia SSO
- Migrate passwords from current manager
- Set up browser extensions
- Configure backups

**Deliverables:**
- Self-hosted password manager
- All passwords migrated
- Automatic backup to encrypted storage
- Mobile app configured

**Why This Matters:**
- Central component of security strategy
- Tests Authelia OAuth2/OIDC integration
- Reduces reliance on external services

---

### Day 20-21: Nextcloud (File Sync)
**Duration:** 5-6 hours total

**Objectives:**
- Deploy Nextcloud
- Integrate with Authelia
- Configure external storage (BTRFS subvolumes)
- Set up desktop/mobile sync
- Enable collabora for document editing

**Deliverables:**
- Self-hosted Dropbox replacement
- Files syncing across devices
- Document editing in browser
- Photo upload from phone

---

## Week 4: Internet Exposure & Advanced Topics (Days 22-28)

**Goal:** Safely expose services to internet + optimize

### Day 22: Pre-Exposure Security Audit
**Duration:** 3-4 hours

**Checklist:**
- [ ] Valid TLS certificates ✓
- [ ] 2FA on all services ✓
- [ ] Monitoring + alerting ✓
- [ ] Backups tested ✓
- [ ] Firewall configured ✓
- [ ] Fail2ban active ✓
- [ ] Rate limiting enabled ✓
- [ ] Cloudflare proxy active ✓
- [ ] All services behind Authelia ✓
- [ ] Emergency shutdown procedure documented ✓

**Deliverable:** Security audit report + go/no-go decision

---

### Day 23: Controlled Internet Exposure
**Duration:** 2-3 hours

**Process:**
1. Enable one service (Jellyfin)
2. Test from external network (phone off WiFi)
3. Monitor logs for 24 hours
4. Enable next service if safe
5. Repeat

**Deliverables:**
- One service public
- Monitoring confirms no issues
- Performance acceptable

---

### Day 24-25: Performance Optimization
**Duration:** 5-6 hours total

**Objectives:**
- Redis tuning
- Authelia performance optimization
- Traefik caching configuration
- Database optimization (if slow)
- Resource limits tuning

**Deliverables:**
- Response times < 200ms
- Resource usage optimized
- Caching strategy documented

---

### Day 26: Advanced Authelia (OAuth2/OIDC)
**Duration:** 3-4 hours

**Objectives:**
- Configure Authelia as OIDC provider
- Integrate services as OIDC clients
- Single sign-on across all services
- Test SSO flow

**Deliverables:**
- True SSO (login once, access all)
- Services using OIDC
- Understanding of OAuth2 flow

---

### Day 27: Documentation & Knowledge Base
**Duration:** 4-5 hours

**Create:**
1. **User guide** - How to access services
2. **Admin guide** - How to manage/troubleshoot
3. **Disaster recovery** - Step-by-step restoration
4. **Architecture diagram** - Visual system overview
5. **Decision log** - Why choices were made

**Deliverables:**
- Comprehensive documentation
- Can hand off to someone else
- Future self can understand

---

### Day 28: Week 4 Review & Future Planning
**Duration:** 2-3 hours

**Activities:**
- Review all 4 weeks
- Test disaster recovery
- Measure against original goals
- Plan next 4 weeks (if continuing)

**Deliverables:**
- Week 4 retrospective
- Lessons learned document
- Next quarter plan (optional)

---

## Adjusted Expectations

### Time Investment
- **Original Plan:** 28 days × 2-3 hours = 56-84 hours
- **Revised Estimate:** 28 days × 3-4 hours = 84-112 hours
- **Reason:** Troubleshooting, documentation, testing takes longer

### Complexity Acknowledgment
**Underestimated:**
- Secret management integration (4 hours vs 30 min planned)
- WebAuthn certificate requirements (deferred entirely)
- Authelia quirks and bugs
- Testing and validation time

**Correctly Estimated:**
- Basic container deployment
- Traefik configuration
- TOTP setup

### Success Metrics Revision

**Original:**
- ✅ All services deployed
- ⚠️ Production-ready Day 7 (actually Day 14)
- ❌ Monitoring by Day 10 (actually Day 15-16)

**Revised:**
- Services deployed incrementally
- Production-ready by Day 14 (realistic)
- Monitoring by Day 16 (allows for TLS first)
- Quality over speed

---

## Lessons Applied to Future Weeks

### 1. Buffer Time
**Each day now includes:**
- Core objective (2-3 hours)
- Buffer for troubleshooting (1 hour)
- Documentation (30 min)

### 2. Dependencies First
**Order adjusted:**
- TLS before WebAuthn
- Monitoring before internet exposure
- Backups before adding services

### 3. Test Before Moving On
**Each day ends with:**
- Verification that objective met
- Documentation updated
- Clean shutdown/restart tested

### 4. Accept Imperfection
**It's okay to:**
- Defer features to later (WebAuthn)
- Use workarounds if documented (Redis password)
- Take longer than planned (learning > speed)

---

## Beyond Week 4 (Future Quarters)

### Quarter 2 (Months 2-3): Media Automation
- Sonarr, Radarr, Prowlarr
- Transmission/qBittorrent
- Jellyseerr (request management)
- Media organization automation

### Quarter 3 (Months 4-6): Home Automation
- Home Assistant integration
- IoT device management
- Automation workflows
- Energy monitoring

### Quarter 4 (Months 7-9): Advanced Topics
- Kubernetes migration (maybe)
- GitOps with FluxCD/ArgoCD
- Advanced networking (WireGuard VPN)
- Multi-node cluster

---

## Guiding Principles (Reinforced)

### 1. Security First
- Never expose without 2FA
- Always encrypt sensitive data
- Monitor everything
- Plan for breaches

### 2. Document Everything
- Write docs while building
- Capture why, not just how
- Future self is your audience
- Screenshots help

### 3. Test Thoroughly
- Nothing goes to production untested
- Test failure modes
- Verify backups work
- Practice disaster recovery

### 4. Iterate Deliberately
- One change at a time
- Understand before optimizing
- Fix > perfectionize
- Learn > rush

### 5. Accept Reality
- Things take longer than planned
- Software has bugs
- Workarounds are okay
- Progress > perfection

---

## Success Indicators

**After Week 2:**
- [ ] All services use valid TLS
- [ ] Email notifications working
- [ ] WebAuthn registered (all keys)
- [ ] Safe to access from internet

**After Week 3:**
- [ ] Monitoring shows all green
- [ ] Vaultwarden managing passwords
- [ ] Nextcloud syncing files
- [ ] Alerts working

**After Week 4:**
- [ ] Services public and stable
- [ ] No major security incidents
- [ ] Backup/restore tested
- [ ] Comprehensive documentation

**Overall Success:**
- Learned deeply
Risk Management
High Priority Risks
Risk 1: Security Breach

Mitigation: 2FA on everything, rate limiting, monitoring
Detection: Failed login alerts, anomaly detection
Response: Documented incident response plan (Week 2, Day 14)

Risk 2: Data Loss

Mitigation: Automated daily backups, off-site storage
Detection: Backup verification checks
Response: Tested restore procedures

Risk 3: Service Outage

Mitigation: Systemd auto-restart, health checks
Detection: Uptime monitoring, alerting
Response: Documented troubleshooting playbook

Risk 4: Certificate Expiry

Mitigation: Auto-renewal with Let's Encrypt
Detection: 30-day expiry alerts
Response: Manual renewal procedure documented

Medium Priority Risks
Risk 5: Resource Exhaustion

Mitigation: Resource limits, monitoring
Detection: CPU/memory alerts
Response: Scaling or optimization

Risk 6: Dependency Failures

Mitigation: Container auto-updates, security scanning
Detection: Container health checks
Response: Rollback procedures


Metrics to Track
Week 2 Metrics

Certificate validity days remaining
Email delivery success rate
WebAuthn registration success rate
External access latency

Week 3 Metrics

Service uptime percentage
Alert false positive rate
Backup success rate
Failed authentication attempts

Week 4 Metrics

Response time (p50, p95, p99)
Resource utilization (CPU, memory, disk)
User satisfaction (family feedback)
Security scan results


Learning Outcomes (Revised)
By End of Week 2
Technical Skills:

ACME protocol & certificate management
DNS management & propagation
SMTP configuration & email delivery
External network testing methodology

Concepts:

Certificate authority trust chain
DNS challenge vs HTTP challenge
Email authentication (SPF, DKIM, DMARC)
Public vs private network security

By End of Week 3
Technical Skills:

Prometheus query language (PromQL)
Grafana dashboard creation
Alert rule configuration
OAuth2/OIDC implementation

Concepts:

Observability (metrics, logs, traces)
Single Sign-On architecture
Data retention policies
Alert fatigue prevention

By End of Week 4
Technical Skills:

Performance optimization
Security auditing
Incident response
Technical writing

Concepts:

Defense in depth
Performance vs security trade-offs
Operational excellence
System thinking


Tools & Technologies Roadmap
Week 1 (Complete) ✅

Podman
Systemd
Quadlets
Traefik
Authelia
Redis

Week 2 (Planned)

Let's Encrypt / Certbot
Cloudflare (DNS + Proxy)
SMTP (Hostinger)
YubiKey PIV (maybe)

Week 3 (Planned)

Prometheus
Grafana
Alertmanager
Vaultwarden
Nextcloud
Collabora Online

Week 4 (Planned)

Apache Bench / wrk (performance testing)
OpenVAS / Nessus (security scanning)
Ansible (automation - maybe)
Git (version control for configs)

Future Quarters

Sonarr/Radarr/Prowlarr
Home Assistant
WireGuard VPN
Maybe Kubernetes


Family/User Considerations
Current State

Services work locally with self-signed certs
Requires accepting security warnings
Login loop workaround needed

Week 2 Improvements

No more certificate warnings
Smoother authentication flow
Access from anywhere (with 2FA)

Week 3 Value-Add

Password manager accessible anywhere
File sync like Dropbox
Media streaming from anywhere

Week 4 Polish

Fast, responsive services
Reliable uptime
Professional feel

Key Insight: Family doesn't care about the tech - they care about:

Does it work? (reliability)
Is it easy? (UX)
Is it safe? (security)

Your job: Make it invisible infrastructure that "just works"

When to Call It "Done"
Minimum Viable Product (End of Week 2)

✅ Valid TLS certificates
✅ Email notifications working
✅ 2FA on all services
✅ Can access from internet safely
✅ Basic monitoring

Production Ready (End of Week 3)

✅ Monitoring + alerting comprehensive
✅ Backups automated and tested
✅ Documentation complete
✅ Family/friends can use it
✅ You're confident leaving it running

Excellent (End of Week 4)

✅ Performance optimized
✅ Security audited
✅ Disaster recovery tested
✅ Can hand off to someone else
✅ Proud to show it off

Don't chase: Perfect - it doesn't exist
Do chase: Good enough to run safely and maintain easily
