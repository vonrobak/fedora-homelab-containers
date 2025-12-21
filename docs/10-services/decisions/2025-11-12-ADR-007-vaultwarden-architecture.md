# ADR-006: Vaultwarden Password Manager Architecture

**Date:** 2025-11-12
**Status:** ✅ Accepted (Ready for Deployment)
**Deciders:** patriark, Claude Code
**Context:** Need for self-hosted password management solution

---

## Context and Problem Statement

Password management is critical for personal and homelab security. Commercial cloud-based solutions (LastPass, 1Password, etc.) introduce risks:
- Third-party breach exposure
- Vendor lock-in
- Recurring subscription costs
- Privacy concerns (password vault metadata)

**Requirement:** Self-hosted password manager that:
- Supports hardware 2FA (YubiKey/WebAuthn)
- Works across all devices (desktop, mobile, browser)
- Compatible with existing Bitwarden ecosystem (clients widely available)
- Lightweight enough for homelab scale
- Production-ready with automated backups

---

## Decision Drivers

### Technical Requirements
- Cross-platform client support (Linux, Windows, Mac, Android, iOS)
- Hardware 2FA support (FIDO2/WebAuthn for YubiKey)
- Real-time sync between devices
- File attachment support (for recovery codes, passport scans)
- Export capability (encrypted vault backup)

### Security Requirements
- End-to-end encryption (vault data encrypted with master password)
- Phishing-resistant 2FA (FIDO2/WebAuthn)
- Rate limiting (prevent brute-force attacks)
- Defense-in-depth (CrowdSec + rate limiting + security headers)
- Automated backups with restore capability

### Operational Requirements
- Lightweight (<512MB memory)
- Simple maintenance (single container, SQLite database)
- Integration with existing Traefik/monitoring stack
- Automated backups (BTRFS snapshots)
- Clear disaster recovery process

---

## Considered Options

### Option 1: Bitwarden Official Server
**Pros:**
- Official implementation, guaranteed compatibility
- Full feature parity with cloud version
- Active development by Bitwarden Inc.

**Cons:**
- Resource-heavy (requires MSSQL/PostgreSQL, multiple containers)
- Overkill for single-user / family use
- Complex deployment (docker-compose with ~6 services)

**Verdict:** ❌ Too resource-intensive for homelab

---

### Option 2: Vaultwarden (Bitwarden_RS)
**Pros:**
- Lightweight Rust implementation (~50MB image, <512MB RAM)
- 100% Bitwarden client compatibility
- SQLite support (no separate database container)
- All premium features free (organizations, 2FA, attachments)
- Single container deployment
- Active community, well-maintained

**Cons:**
- Unofficial implementation (not by Bitwarden Inc.)
- Slight delay in supporting new Bitwarden features
- Community-driven (not backed by company)

**Verdict:** ✅ **SELECTED** - Perfect balance for homelab

---

### Option 3: KeePassXC + Sync Service
**Pros:**
- Completely offline (maximum security)
- Open source, desktop-native
- No server required

**Cons:**
- Manual sync between devices (Syncthing/Nextcloud required)
- Poor mobile experience
- No browser extension integration
- Cumbersome for multi-device workflows

**Verdict:** ❌ Too limited for modern multi-device use

---

### Option 4: Pass (password-store)
**Pros:**
- Simple (Git + GPG)
- CLI-first (appeals to power users)
- Fully offline, open source

**Cons:**
- No official mobile/browser clients
- Steep learning curve for non-technical users
- No built-in 2FA support
- Manual sync via Git

**Verdict:** ❌ Too technical, limited ecosystem

---

## Decision: Vaultwarden with Hardened Configuration

**Selected:** **Option 2: Vaultwarden**

**Rationale:**
- Bitwarden-compatible (leverage existing client ecosystem)
- Lightweight (perfect for homelab resource constraints)
- Premium features (organizations, 2FA, file attachments) included free
- Single-container deployment (simpler than official server)
- Active community (1.4k+ GitHub stars, regular updates)

---

## Implementation Details

### Database Backend

**Decision:** SQLite (not PostgreSQL)

**Rationale:**
- Homelab scale (<5 users, <10,000 passwords)
- SQLite handles thousands of requests/second easily at this scale
- Single file database (simpler backups)
- No separate database container required
- Can migrate to PostgreSQL later if needed

**Trade-off:** PostgreSQL scales better for concurrent users, but overkill for personal/family use.

---

### Authentication Strategy

**Decision:** Master Password + YubiKey/WebAuthn (primary) + TOTP (backup)

**Rationale:**
- **Master password:** Strong passphrase (20+ chars, Diceware method)
- **YubiKey/WebAuthn:** Phishing-resistant hardware 2FA (FIDO2)
- **TOTP backup:** Software 2FA for situations without YubiKey

**Why NOT email/SMS 2FA:**
- Email: Vulnerable to email account compromise
- SMS: Vulnerable to SIM-swapping attacks
- Neither is phishing-resistant

**Trade-off:** YubiKey required for most logins (acceptable inconvenience for high security).

---

### User Registration

**Decision:** Registration disabled (admin-created accounts only)

**Rationale:**
- Personal/family use (not public service)
- Prevents unauthorized account creation
- Reduces attack surface

**Process:**
1. Enable admin panel temporarily
2. Create user accounts manually
3. Disable admin panel after setup

**Trade-off:** Can't invite users via email (must use admin panel). Acceptable for homelab.

---

### Admin Panel Access

**Decision:** Enabled for initial setup, then **disabled permanently**

**Rationale:**
- Admin panel only needed during initial setup
- After user account creation and configuration, no admin functions needed
- Disabling reduces attack surface
- Can temporarily re-enable if needed (requires environment file edit + restart)

**Security:** Admin panel uses strong random token (48 bytes, base64-encoded).

---

### Email Configuration

**Decision:** Optional (SMTP recommended but not required)

**Rationale:**
- **With SMTP:** Password reset, new device verification, security alerts
- **Without SMTP:** Manual recovery process, export vault backups as safety net

**Recommended:** Configure Proton Mail SMTP for password recovery capability.

**Trade-off:** Without email, losing master password = permanent lockout. Mitigate with:
- Strong master password (written on paper, stored in safe)
- Regular encrypted vault exports (quarterly)
- TOTP recovery codes (stored offline)

---

### Traefik Integration

**Decision:** Dynamic config files (NOT container labels)

**Rationale:**
- Consistent with project configuration philosophy (centralized config)
- Easier to review and modify (one place for all routing rules)
- No need to recreate container to change routing
- Better for documentation and auditability

**Configuration:**
```yaml
# routers.yml - Routing
vaultwarden-secure:
  rule: "Host(`vault.patriark.org`)"
  service: "vaultwarden"
  middlewares:
    - crowdsec-bouncer@file
    - rate-limit-vaultwarden@file
    - security-headers@file

# middleware.yml - Rate Limiting
rate-limit-vaultwarden-auth:
  rateLimit:
    average: 5     # 5 attempts/min (strictest)
    burst: 2
    period: 1m
```

---

### Authelia Integration

**Decision:** NO Authelia on Vaultwarden web UI

**Rationale:**
- Vaultwarden already has strong authentication (master password + 2FA)
- Adding Authelia creates UX friction without meaningful security gain
- Mobile/desktop clients can't handle SSO redirects (breaks Bitwarden client authentication)
- Defense-in-depth already achieved via CrowdSec + rate limiting + security headers

**Alternative considered:** Authelia on /admin endpoint only
**Verdict:** Admin panel disabled entirely (no need for additional auth layer)

---

### Rate Limiting Strategy

**Decision:** Vaultwarden-specific strict rate limits

**Rationale:**
- Password managers are **highest-value targets** for attackers
- Brute-force attacks must be aggressively blocked
- Master password hashing is intentionally slow (PBKDF2 600k iterations)
- 5 attempts/min is generous for legitimate use, blocks automated attacks

**Rate Limits:**
- **Authentication endpoints:** 5 req/min per IP
- **General endpoints:** 100 req/min per IP

**Comparison with other services:**
- Authelia: 10 req/min
- General services: 100 req/min
- Vaultwarden auth: **5 req/min** (strictest)

**Trade-off:** Users locked out after 5 wrong passwords in 1 minute. Acceptable for security.

---

### Backup Strategy

**Decision:** Daily BTRFS snapshots + quarterly manual exports

**Rationale:**
- **BTRFS snapshots:** Automated, point-in-time recovery (RPO: 24 hours)
- **Manual exports:** Encrypted vault backup, stored offline (disaster recovery)

**What's backed up:**
```
/mnt/btrfs-pool/subvol7-containers/vaultwarden/
├── db.sqlite3           # Encrypted password vault
├── db.sqlite3-shm       # SQLite shared memory
├── db.sqlite3-wal       # Write-ahead log
├── attachments/         # Encrypted file attachments
├── sends/               # Bitwarden Send files
├── rsa_key.pem          # Server encryption key
└── config.json          # Server configuration
```

**Retention:**
- Local BTRFS snapshots: 7 days
- External backups: 4 weeks (weekly)
- Manual exports: Indefinite (until next export)

**Recovery Time Objective (RTO):** <30 minutes (restore from BTRFS snapshot)

---

### Network Placement

**Decision:** `systemd-reverse_proxy` network only

**Rationale:**
- Needs Traefik access (reverse proxy)
- No database dependencies (SQLite embedded)
- No need for dedicated network (single container)

**Security:** Network isolation via Podman user networks (automatic).

---

### Resource Limits

**Decision:**
- Memory: 512MB (normal), 1GB (max)
- CPU: 100% (1 full core)

**Rationale:**
- Vaultwarden is lightweight (~50MB idle, ~200MB active)
- 512MB covers normal operation (login, sync, search)
- 1GB max handles spikes (simultaneous device syncs, attachment uploads)
- CPU quota prevents runaway processes

**Monitoring:** Memory alerts if consistently >80% (480MB) for 10+ minutes.

---

### WebSocket Support

**Decision:** Enabled (real-time sync)

**Rationale:**
- Real-time synchronization between devices
- Better UX (instant password updates)
- Traefik v3 handles WebSocket upgrade automatically (no special config)

**Trade-off:** Slightly more resource usage (~10MB). Acceptable for feature value.

---

### File Attachments

**Decision:** Enabled (1GB max file size)

**Rationale:**
- Useful for storing recovery codes, passport scans, SSH keys
- End-to-end encrypted (same security as passwords)
- Backed up automatically (BTRFS snapshots)

**Storage impact:** Minimal (<100MB typical for personal use)

---

## Consequences

### Positive

✅ **Security:**
- Self-hosted (no third-party breach risk)
- End-to-end encrypted (vault data never leaves your control)
- Hardware 2FA (phishing-resistant YubiKey authentication)
- Defense-in-depth (CrowdSec, rate limiting, security headers)

✅ **Privacy:**
- No telemetry to Bitwarden Inc.
- No password vault metadata sent to cloud
- Full control over access logs

✅ **Cost:**
- Zero recurring costs (vs $36-60/year for Bitwarden Premium or 1Password)
- All premium features free (organizations, 2FA, file attachments)

✅ **Compatibility:**
- Works with all Bitwarden official clients (desktop, mobile, browser extensions)
- Existing Bitwarden users can migrate easily

✅ **Operations:**
- Single container deployment (simple)
- Automated backups (BTRFS daily snapshots)
- Low maintenance (update via `systemctl restart`)

### Negative

⚠️ **Single Point of Failure:**
- If server dies AND backups fail, passwords lost
- **Mitigation:** Regular encrypted vault exports to offline storage

⚠️ **No Official Support:**
- Community-driven project (not backed by Bitwarden Inc.)
- **Mitigation:** Active GitHub community, well-maintained codebase

⚠️ **Internet Dependency:**
- Vault sync requires internet access to homelab
- **Mitigation:** Bitwarden clients cache vault offline (still accessible)

⚠️ **Responsibility:**
- You are responsible for backups, security, uptime
- **Mitigation:** Automated backups, monitoring, documented procedures

### Neutral

⚡ **Learning Opportunity:**
- Deepens understanding of password management architecture
- Hands-on experience with encryption, 2FA, backup strategies

⚡ **Control:**
- Full access to database (can extract passwords if needed)
- Can customize configuration (registration, 2FA requirements)

---

## Validation

### Success Criteria

Deployment considered successful if:

1. **Functionality:**
   - [ ] Web vault accessible at https://vault.patriark.org
   - [ ] Master password authentication working
   - [ ] YubiKey/WebAuthn 2FA working
   - [ ] TOTP backup 2FA working
   - [ ] Desktop client syncs successfully
   - [ ] Browser extension syncs successfully
   - [ ] Mobile app syncs successfully
   - [ ] File attachments upload/download working

2. **Security:**
   - [ ] Admin panel disabled after setup
   - [ ] Rate limiting blocks brute-force (6th attempt blocked)
   - [ ] CrowdSec bouncer active (check Traefik logs)
   - [ ] TLS certificate valid (Let's Encrypt)
   - [ ] Security headers present (check browser dev tools)

3. **Reliability:**
   - [ ] Service auto-starts on boot
   - [ ] Health checks passing
   - [ ] Backups include Vaultwarden database
   - [ ] Restoration tested from snapshot

4. **Monitoring:**
   - [ ] Service status visible in Homepage dashboard
   - [ ] Container metrics in Grafana (cAdvisor)
   - [ ] Request rates visible in Traefik dashboard

### Performance Targets

- **Response Time:** <500ms for vault unlock
- **Sync Time:** <5s for full vault sync (100 items)
- **Memory:** <512MB during normal operation
- **CPU:** <10% average utilization

---

## Compliance

### Security Best Practices

✅ **OWASP Password Storage:**
- Master password hashed with PBKDF2 (600k iterations)
- Vault data encrypted with AES-256-CBC
- Server encryption keys protected by filesystem permissions

✅ **Defense-in-Depth:**
- Layer 1: CrowdSec (IP reputation)
- Layer 2: Rate limiting (brute-force prevention)
- Layer 3: Master password (client-side encryption)
- Layer 4: Hardware 2FA (phishing-resistant)

✅ **Least Privilege:**
- Rootless containers (UID 1000)
- Capabilities dropped (`DropCap=ALL`)
- Only necessary capabilities added (CAP_CHOWN, CAP_SETUID, CAP_SETGID)

---

## Future Considerations

### Short-Term (1-3 months)

1. **Monitoring Dashboard:**
   - Add Grafana panel for Vaultwarden metrics
   - Alert on service downtime
   - Track login attempts, rate limit violations

2. **Family Sharing:**
   - Enable Organizations feature (if family members join)
   - Configure shared password collections
   - Document family member onboarding

3. **External Backup:**
   - Set up automated encrypted exports to external drive
   - Test restoration from external backup

### Long-Term (6-12 months)

4. **PostgreSQL Migration:**
   - Migrate from SQLite to PostgreSQL if user count >5
   - Better concurrent user support
   - More robust for organizational use

5. **High Availability:**
   - Consider Vaultwarden failover instance
   - Load-balanced Traefik instances
   - Database replication

6. **Advanced Authentication:**
   - Duo Security integration (if family grows)
   - Conditional access policies (IP allowlists)
   - Session timeout tuning

---

## Related Decisions

- **ADR-001:** Rootless Containers (security model)
- **ADR-002:** Systemd Quadlets (deployment pattern)
- **ADR-003:** Monitoring Stack (observability)
- **ADR-005:** Authelia SSO (authentication strategy - why Vaultwarden is exempt)

---

## References

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [Bitwarden Security Whitepaper](https://bitwarden.com/images/resources/security-white-paper-download.pdf)
- [FIDO2 WebAuthn Standard](https://www.w3.org/TR/webauthn/)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

---

## Status: Ready for Deployment

All configuration files created, backup automation in place, monitoring ready. Awaiting user deployment following `vaultwarden-deployment.md` guide.
