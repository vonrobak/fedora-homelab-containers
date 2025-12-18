# Vaultwarden Deployment - Focused Implementation Roadmap

**Date:** 2025-11-12
**Status:** 📋 Ready for Implementation
**Based On:** User feedback on comprehensive deployment plan

---

## Quick Answers to Your Questions

### Decision 8: Traefik Labels vs Dynamic Config

**You're absolutely right!** Following your configuration design philosophy:

✅ **Use dynamic config files** (`middleware.yml`, `routers.yml`)
❌ **NOT container labels**

**Why:** Aligns with your design principles:
- Configuration as code (centralized in `/config/traefik/dynamic/`)
- Easier to review and maintain
- Consistent with existing services (Authelia, Grafana, etc.)
- No need to recreate container to change routing

**Implementation:**
```yaml
# config/traefik/dynamic/routers.yml
http:
  routers:
    vaultwarden:
      rule: "Host(`vault.patriark.org`)"
      entryPoints:
        - websecure
      service: vaultwarden
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-vaultwarden-auth@file
        - security-headers@file
      tls:
        certResolver: letsencrypt

  services:
    vaultwarden:
      loadBalancer:
        servers:
          - url: "http://vaultwarden:80"
```

WebSocket support is **automatic** in Traefik v3—no special configuration needed!

---

### Decision 10: Vaultwarden-Specific Rate Limiting

**Yes, these are additional middlewares** for Vaultwarden's unique needs.

**Why separate from existing rate limits:**

| Existing Middleware | Rate | Use Case |
|---------------------|------|----------|
| `rate-limit` | 100/min | General services |
| `rate-limit-strict` | 30/min | Sensitive endpoints |
| `rate-limit-auth` | 10/min | Auth endpoints (Authelia) |
| **`rate-limit-vaultwarden-auth`** | **5/min** | **Password vault login (stricter)** |

**Rationale:**
- Password managers are **highest-value targets** for attackers
- Vaultwarden login is slower (master password hashing is intentionally expensive)
- 5 attempts/min is generous for legitimate users, restrictive for brute-force
- Separate from Authelia's rate limit (different attack surface)

**Consistent with your config philosophy:**
- Defined in `middleware.yml` (not labels) ✅
- Follows fail-fast ordering (CrowdSec → rate limit → headers) ✅
- Reusable middleware (can apply to other high-value services) ✅

---

### Decision 6: Discord for Email Notifications

**Short answer:** Discord **cannot** replace SMTP for Vaultwarden.

**Why:**
- Vaultwarden needs to send emails **to users** (password reset, new device verification)
- Discord webhooks only allow **you** to send messages **to Discord**
- No way for Vaultwarden to send emails through Discord API

**Alternative options:**

| Option | Complexity | Cost | Recommendation |
|--------|------------|------|----------------|
| **Proton Mail SMTP** | Low | Free | ✅ **Best choice** |
| Gmail SMTP | Low | Free | Good (but Google tracks you) |
| Mailgun | Medium | Free tier (100/day) | Overkill for homelab |
| Self-hosted mail server | Very High | Free | ❌ Not worth complexity |
| **No email** | None | Free | ⚠️ Risky (no password recovery) |

**Recommendation:** Configure **Proton Mail SMTP** (10 minutes setup).

**Setup:**
```bash
# Proton Mail Bridge or SMTP credentials
SMTP_HOST=smtp.protonmail.ch
SMTP_FROM=your-email@proton.me
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=your-email@proton.me
SMTP_PASSWORD=<app-password>  # Generate in Proton settings
```

**Fallback:** If you really want no email, I'll add manual backup export instructions to compensate for lack of password recovery.

---

### Decision 5: Backup Script Investigation

**Issue identified:** No systemd timer configured—script exists but doesn't run automatically.

**Current state:**
- ✅ Script exists: `scripts/btrfs-snapshot-backup.sh`
- ❌ No systemd timer file
- ❌ Not scheduled

**Fix required:** Create `btrfs-snapshot-backup.timer` and `.service` files.

---

## Enhancement 1: CrowdSec Update & Scenarios

**Finding:** Scenarios already installed, but CrowdSec is outdated (v1.7.2 → v1.7.3).

**Actions:**
1. Update CrowdSec to v1.7.3
2. Verify all scenarios active
3. Add local whitelists
4. Configure tiered ban profiles

---

## Focused Implementation Roadmap

Based on your feedback, here's the streamlined plan:

---

## Phase 1: Vaultwarden Deployment (This Week)

### Task 1.1: Fix Backup Automation (BLOCKER)
**Priority:** 🔴 Critical (must fix before deploying Vaultwarden)

**Actions:**
- [ ] Create `~/.config/systemd/user/btrfs-snapshot-backup.service`
- [ ] Create `~/.config/systemd/user/btrfs-snapshot-backup.timer`
- [ ] Enable and start timer
- [ ] Verify backup runs automatically
- [ ] Test restoration process

**Time:** 1 hour

---

### Task 1.2: Deploy Vaultwarden
**Priority:** 🔴 High

**Configuration decisions (approved):**
- ✅ SQLite database
- ✅ Admin panel disabled after setup
- ✅ Registration disabled
- ✅ YubiKey/WebAuthn + TOTP 2FA
- ✅ Proton Mail SMTP (or skip if preferred)
- ✅ Attachments enabled
- ✅ WebSocket enabled (automatic in Traefik v3)
- ✅ No Authelia on web UI (vault has own auth)
- ✅ Vaultwarden-specific rate limiting (5 req/min)

**Files to create:**
1. `config/vaultwarden/.env` (environment variables)
2. `config/traefik/dynamic/routers.yml` (add Vaultwarden router)
3. `config/traefik/dynamic/middleware.yml` (add rate-limit-vaultwarden-auth)
4. `~/.config/containers/systemd/vaultwarden.container` (quadlet)
5. `docs/10-services/guides/vaultwarden.md` (service guide)
6. `docs/10-services/decisions/2025-11-12-decision-006-vaultwarden-architecture.md` (ADR)

**Steps:**
1. Generate admin token
2. Create directory structure on BTRFS pool
3. Create Vaultwarden quadlet
4. Add Traefik routing (dynamic config, not labels)
5. Add rate limiting middleware
6. Start service
7. Access admin panel, create user account
8. Configure YubiKey + TOTP 2FA
9. Disable admin panel
10. Test sync across devices
11. Verify backups include Vaultwarden data
12. Document in service guide

**Time:** 2-3 hours

---

## Phase 2: CrowdSec Enhancement (Next Week)

### Task 2.1: Update CrowdSec
**Priority:** 🟡 Medium

**Actions:**
- [ ] Update CrowdSec container to v1.7.3
- [ ] Verify scenarios still active after update
- [ ] Test bouncer still blocking banned IPs

**Time:** 30 minutes

---

### Task 2.2: Configure Local Whitelists
**Priority:** 🟡 Medium

**Actions:**
- [ ] Whitelist 192.168.1.0/24 (LAN)
- [ ] Whitelist 192.168.100.0/24 (WireGuard VPN)
- [ ] Verify whitelists working (can't accidentally ban yourself)

**Time:** 15 minutes

---

### Task 2.3: Tiered Ban Profiles
**Priority:** 🟡 Medium

**Actions:**
- [ ] Create `config/crowdsec/profiles.yaml`
- [ ] Define 3 tiers: standard (4h), aggressive (24h), severe (7d)
- [ ] Apply profiles to scenarios
- [ ] Test with simulated attacks

**Time:** 1 hour

---

## Phase 3: Monitoring & Alerting (Week 3)

### Task 3.1: Security Dashboards (Enhancement 4)
**Priority:** 🟢 High Interest

**Dashboards to create:**

**Dashboard 1: Security Overview**
- CrowdSec ban statistics (by scenario, by country)
- Failed authentication attempts (Authelia, Vaultwarden)
- Rate limit violations (by service)
- Top blocked IPs
- Active bans count

**Dashboard 2: Vaultwarden Security**
- Failed login attempts
- Successful logins (by user, device, location)
- 2FA usage statistics
- Master password change events
- New device authorizations

**Dashboard 3: Traefik Traffic Analysis**
- Requests by service
- Response times
- Error rates (4xx, 5xx)
- TLS version distribution
- Geographic distribution (if GeoIP later)

**Data sources:**
- Prometheus (CrowdSec exporter, Traefik metrics)
- Loki (log aggregation from all services)

**Time:** 3-4 hours

---

### Task 3.2: Alert Tuning (Enhancement 5)
**Priority:** 🟢 High Interest

**Current problem:** All alerts go to Discord (alert fatigue).

**Solution: Tiered alerting**

**Tier 1: Critical (Immediate Discord notification)**
- Service down (Traefik, Prometheus, Vaultwarden)
- System disk >85%
- Memory >90%
- Multiple failed Vaultwarden logins from same IP
- CrowdSec banning your own IP (misconfiguration)

**Tier 2: Warning (Aggregated, hourly summary)**
- Service restarted
- Disk >70%
- High error rate (>5% 5xx responses)
- Moderate failed login attempts

**Tier 3: Info (Log only, no notification)**
- Successful authentications
- Scheduled tasks completed
- Backups succeeded
- Configuration changes applied

**Implementation:**
- [ ] Update `config/alertmanager/alertmanager.yml`
- [ ] Create severity labels in Prometheus rules
- [ ] Add Discord webhook for critical/warning
- [ ] Create "null" receiver for info alerts
- [ ] Test with simulated alerts

**Time:** 2 hours

---

## Phase 4: WireGuard VPN Testing & Integration (Month 2)

**Current state:**
- WireGuard server on UDM-Pro (192.168.100.0/24)
- Not tested, possibly not working

**Goal:** Secure remote access to homelab without exposing services.

### Task 4.1: Test Existing WireGuard Setup
**Priority:** 🟡 Medium

**Actions:**
- [ ] Review UDM-Pro WireGuard configuration
- [ ] Generate client config for your laptop/phone
- [ ] Test connection from external network
- [ ] Verify can access homelab services (Grafana, Jellyfin, etc.)
- [ ] Test DNS resolution through VPN

**Time:** 1-2 hours

---

### Task 4.2: Document WireGuard Access (if working)
**Priority:** 🟢 Low

**Actions:**
- [ ] Create `docs/30-security/guides/wireguard-vpn.md`
- [ ] Document client setup process
- [ ] Add to CLAUDE.md "Remote Access" section
- [ ] Update firewall documentation

**Time:** 1 hour

---

### Task 4.3: Integrate VPN with Monitoring (optional)
**Priority:** 🟢 Low

**Actions:**
- [ ] Add WireGuard metrics to Prometheus (if UDM-Pro supports)
- [ ] Create Grafana dashboard for VPN connections
- [ ] Alert on suspicious VPN activity

**Time:** 2 hours

---

## Phase 5: Secrets Management Review (Week 4)

**Current state:** "Largely implemented already, but implementation could be reviewed."

### Task 5.1: Audit Current Secrets
**Priority:** 🟡 Medium

**Actions:**
- [ ] List all secrets currently in use (API keys, tokens, passwords)
- [ ] Identify where each secret is stored (env files, quadlets, configs)
- [ ] Check Git history for accidentally committed secrets
- [ ] Verify `.gitignore` catches all secret patterns

**Time:** 1 hour

---

### Task 5.2: Migrate to Podman Secrets (if needed)
**Priority:** 🟢 Low

**Actions:**
- [ ] Identify candidates for Podman secrets (database passwords, API tokens)
- [ ] Create secrets with `podman secret create`
- [ ] Update quadlets to use secrets
- [ ] Remove plaintext secrets from env files
- [ ] Document secrets workflow

**Time:** 2-3 hours (if migrating multiple services)

---

## Deferred Enhancements

Based on your feedback, these are **lower priority** due to UDM-Pro coverage:

### Enhancement 2: Geographic IP Blocking
**Status:** ⏸️ Deferred (UDM-Pro handles this)

**Future consideration:** CrowdSec GeoIP still useful for homelab-level blocking (complements UDM-Pro).

---

### Enhancement 3: Intrusion Detection (Suricata)
**Status:** ⏸️ Deferred (UDM-Pro handles this)

**Future consideration:** Suricata on homelab can provide application-layer inspection that UDM-Pro might miss.

---

## Implementation Timeline

### Week 1 (This Week)
- **Monday:** Fix backup automation (Task 1.1)
- **Tuesday-Wednesday:** Deploy Vaultwarden (Task 1.2)
- **Thursday:** Test Vaultwarden thoroughly
- **Friday:** Documentation (ADR-006, service guide)

### Week 2 (Next Week)
- **Monday:** Update CrowdSec (Task 2.1)
- **Tuesday:** Configure whitelists and profiles (Task 2.2-2.3)
- **Wednesday-Friday:** Start security dashboards (Task 3.1)

### Week 3
- **Monday-Tuesday:** Finish security dashboards (Task 3.1)
- **Wednesday-Thursday:** Alert tuning (Task 3.2)
- **Friday:** Test and refine alerting rules

### Week 4
- **Monday-Tuesday:** Test WireGuard VPN (Task 4.1)
- **Wednesday:** Document VPN if working (Task 4.2)
- **Thursday-Friday:** Secrets management audit (Task 5.1)

---

## Success Criteria

### Vaultwarden Deployment Success:
- ✅ Vault accessible at `https://vault.patriark.org`
- ✅ Master password + YubiKey 2FA working
- ✅ Desktop/mobile clients sync successfully
- ✅ Rate limiting blocks brute-force attempts (test with wrong password)
- ✅ Backups include Vaultwarden database
- ✅ Can restore from backup
- ✅ Admin panel disabled
- ✅ Service guide documented
- ✅ ADR-006 created

### Security Enhancements Success:
- ✅ CrowdSec updated to v1.7.3
- ✅ Local networks whitelisted (can't ban yourself)
- ✅ Tiered ban profiles active (4h/24h/7d)
- ✅ 3 Grafana security dashboards created
- ✅ Alert fatigue reduced (critical/warning/info tiers)
- ✅ WireGuard VPN tested and documented (if working)

---

## Next Steps

**Immediate action:** Should I proceed with:

1. **Task 1.1 (Backup Automation)** - Create systemd timer files
2. **Task 1.2 (Vaultwarden Deployment)** - Create deployment script and configs

Or would you like to review anything else first?

**Optional:** If you want to see the exact files before I create them, I can show you:
- The complete `.env` file for Vaultwarden
- The systemd timer/service files for backups
- The Traefik dynamic config additions
- The rate limiting middleware definition

Let me know how you'd like to proceed!
