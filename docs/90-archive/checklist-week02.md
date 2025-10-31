# Week 2 Implementation Checklist

**Date Started:** ___________  
**Target Completion:** ___________

---

## 🎯 DAY 1: Foundation & Security (1-2 hours)

### Morning: Prerequisites (30 min)
- [ ] Read QUICK-START-GUIDE.md completely
- [ ] Review week02-implementation-plan.md overview
- [ ] Verify BTRFS snapshot exists: `sudo btrfs subvolume list /`
- [ ] Create today's backup: `sudo btrfs subvolume snapshot / /snapshots/before-week2`

### Security Hardening (15 min)
- [ ] Copy scripts to ~/containers/scripts/
- [ ] Make executable: `chmod +x ~/containers/scripts/*.sh`
- [ ] Run: `./critical-security-fixes.sh`
- [ ] Verify: `./verify-security-fixes.sh` shows all PASS
- [ ] Test Traefik dashboard requires auth: https://traefik.patriark.lokal

### Domain Registration (10 min)
- [ ] Register patriark.dev at Hostinger
- [ ] Cost paid: €_____
- [ ] Add DNS A record: @ → 62.249.184.112
- [ ] Add DNS A record: * → 62.249.184.112
- [ ] Add CNAMEs: auth, jellyfin, traefik → @
- [ ] Get API token from Hostinger Dashboard
- [ ] Save token securely: `echo "token" > ~/containers/secrets/hostinger_api_token`
- [ ] Test DNS: `dig patriark.dev +short` (wait 5-10 min if needed)

### SMTP Configuration (5 min)
- [ ] Login to account.microsoft.com/security (or Gmail)
- [ ] Enable 2FA if needed
- [ ] Create app password named "Homelab Authelia"
- [ ] Save password: `echo "password" > ~/containers/secrets/smtp_password`
- [ ] Set permissions: `chmod 600 ~/containers/secrets/smtp_password`

### Dual-Domain Configuration (20 min)
- [ ] Run: `./configure-authelia-dual-domain.sh`
- [ ] Review diff output
- [ ] Type 'yes' to apply
- [ ] Restart: `systemctl --user restart authelia.service`
- [ ] Wait 10 seconds
- [ ] Check: `podman ps | grep authelia` shows "healthy"
- [ ] Test login: https://jellyfin.patriark.lokal
- [ ] Login successful WITHOUT loop? (If no, see troubleshooting below)

### End of Day 1 Verification
- [ ] Can access Jellyfin locally: https://jellyfin.patriark.lokal
- [ ] Login works with username + password + TOTP
- [ ] NO login loop after TOTP
- [ ] Traefik dashboard requires authentication
- [ ] DNS resolves: `dig auth.patriark.dev +short` returns your IP
- [ ] All backups created in ~/containers/backups/

**Day 1 Complete:** Yes ☐  No ☐  
**Time Spent:** _____ hours

---

## 🔒 DAY 2: Let's Encrypt Setup (1-2 hours)

### Traefik ACME Configuration (30 min)
- [ ] Create Hostinger env file with API key
- [ ] Update traefik.yml with certificatesResolvers section
- [ ] Start with letsencrypt-staging (not prod!)
- [ ] Create acme.json: `touch ~/containers/data/traefik/letsencrypt/acme.json`
- [ ] Set permissions: `chmod 600 ~/containers/data/traefik/letsencrypt/acme.json`
- [ ] Update traefik.container quadlet with volume mount
- [ ] Reload: `systemctl --user daemon-reload`

### Certificate Issuance (30 min)
- [ ] Restart Traefik: `systemctl --user restart traefik.service`
- [ ] Monitor logs: `podman logs -f traefik | grep -i acme`
- [ ] Wait for "Certificate obtained for domains [patriark.dev *.patriark.dev]"
- [ ] Verify staging cert: `curl -vI https://auth.patriark.dev 2>&1 | grep issuer`
- [ ] Should show: "(STAGING) Let's Encrypt"

### Service Router Updates (30 min)
- [ ] Create dynamic/certificates.yml with new routes
- [ ] Update all services to use .dev domain
- [ ] Add certResolver: letsencrypt-staging to each router
- [ ] Test access (accept staging cert warning)
- [ ] Verify all services accessible via .dev domain

### Troubleshooting (if needed)
- [ ] Check Traefik logs for ACME errors
- [ ] Verify Hostinger API token has correct permissions
- [ ] Increase delayBeforeCheck to 60s if timeouts occur
- [ ] Check DNS propagation: `dig _acme-challenge.patriark.dev TXT`

**Day 2 Complete:** Yes ☐  No ☐  
**Time Spent:** _____ hours

---

## ✅ DAY 3: Production Certs & WebAuthn (1-2 hours)

### Switch to Production (20 min)
**ONLY proceed if staging certificates worked perfectly!**

- [ ] Backup staging acme.json
- [ ] Update all certResolver to letsencrypt-prod
- [ ] Restart Traefik
- [ ] Verify prod cert: should show "CN=R3" (not STAGING)
- [ ] Test in browser: NO certificate warnings

### Authelia Production Updates (40 min)
- [ ] Verify dual-domain session cookies working
- [ ] Clear Redis if needed: `podman exec authelia-redis redis-cli FLUSHDB`
- [ ] Test login from LAN (.lokal) - should work perfectly
- [ ] Test login from phone/mobile data (.dev) if port forwarding done
- [ ] Verify no login loop on either domain

### WebAuthn Registration (20 min)
- [ ] Navigate to https://auth.patriark.dev
- [ ] Login successfully
- [ ] Click username → Security Keys
- [ ] Register YubiKey #1 (5C NFC - Serial 17735753)
- [ ] Register YubiKey #2 (5 NFC - Serial 16173971)
- [ ] Register YubiKey #3 (5Ci - Serial 11187313)
- [ ] Test WebAuthn login: logout, login, touch key
- [ ] Verify all 3 keys work

### SMTP Testing (10 min)
- [ ] Test password reset flow
- [ ] Verify email notification received
- [ ] Check email arrives within 1 minute
- [ ] Test from different email if needed

**Day 3 Complete:** Yes ☐  No ☐  
**Time Spent:** _____ hours

---

## 🌐 DAY 4: External Access (1-2 hours)

### UDM Pro Port Forwarding (30 min)
- [ ] Login to UDM Pro web interface
- [ ] Settings → Internet → Port Forwarding
- [ ] Add rule: HTTP (80) → 192.168.1.70:80
- [ ] Add rule: HTTPS (443) → 192.168.1.70:443
- [ ] Enable both rules
- [ ] Verify in UDM logs that rules are active

### Dynamic DNS (20 min)
**Choose ONE option:**

Option A: Hostinger DDNS on UDM Pro
- [ ] Settings → Internet → Dynamic DNS
- [ ] Configure with Hostinger API
- [ ] Test update works

Option B: Cloudflare (Recommended)
- [ ] Sign up for Cloudflare (free plan)
- [ ] Add patriark.dev domain
- [ ] Update nameservers at Hostinger
- [ ] Enable "Proxied" (orange cloud) for A records
- [ ] Configure SSL/TLS to "Full (strict)"

### External Access Testing (30 min)
- [ ] Disconnect from wifi, use mobile data
- [ ] Navigate to https://auth.patriark.dev
- [ ] Should load without errors
- [ ] Login with credentials + TOTP or YubiKey
- [ ] Navigate to https://jellyfin.patriark.dev
- [ ] Should redirect to auth, then back to Jellyfin
- [ ] Media plays correctly

### Firewall Hardening (20 min)
- [ ] UDM Pro → Firewall → Rules
- [ ] Block IoT VLAN → 192.168.1.70
- [ ] Block Guest VLAN → 192.168.1.70
- [ ] Allow WireGuard → 192.168.1.70 (when ready)
- [ ] Rate limit port 443: 100 conn/min
- [ ] Enable logging on all rules
- [ ] Test rules don't block legitimate traffic

**Day 4 Complete:** Yes ☐  No ☐  
**Time Spent:** _____ hours

---

## 📊 DAY 5: Monitoring & Documentation (1-2 hours)

### Deploy Uptime Kuma (45 min)
- [ ] Create uptime-kuma.container quadlet
- [ ] Create data directory
- [ ] Start service: `systemctl --user start uptime-kuma.service`
- [ ] Access: https://status.patriark.dev
- [ ] Set admin password
- [ ] Add monitor: auth.patriark.dev (1 min)
- [ ] Add monitor: jellyfin.patriark.dev (5 min)
- [ ] Add monitor: traefik.patriark.dev (5 min)
- [ ] Configure email notifications
- [ ] Test: stop a service, verify alert received

### Security Audit (30 min)
- [ ] Run security audit script
- [ ] All checks show PASS
- [ ] No plain-text secrets: `grep -r "password.*:" ~/containers/config/ | grep -v file://`
- [ ] SELinux enforcing: `getenforce`
- [ ] Only ports 80/443 exposed: `sudo firewall-cmd --list-ports`
- [ ] Traefik dashboard authenticated
- [ ] Rate limiting active
- [ ] Valid certificates on all domains

### Documentation Updates (30 min)
- [ ] Update ~/containers/docs/20-operations/summary-revised.md
- [ ] Update TLS status to "Valid Let's Encrypt"
- [ ] Add .dev domain information
- [ ] Update security score: from 7/13 to 12/13
- [ ] Create external-access-guide.md for family
- [ ] Update quick-reference.md with new URLs
- [ ] Document any issues encountered and solutions

### Emergency Rollback Test (15 min)
- [ ] Create emergency-rollback.sh script
- [ ] Read through script (don't execute yet)
- [ ] Verify you understand each step
- [ ] Document rollback procedure in notes
- [ ] Keep script handy for emergencies

**Day 5 Complete:** Yes ☐  No ☐  
**Time Spent:** _____ hours

---

## 🎉 WEEK 2 COMPLETION

### Final Verification
- [ ] All services accessible externally
- [ ] Valid certificates (no warnings)
- [ ] WebAuthn works with all YubiKeys
- [ ] Email notifications working
- [ ] Monitoring operational
- [ ] Login loop bug fixed
- [ ] Documentation complete
- [ ] Emergency procedures documented

### Security Scorecard
**Before Week 2:** 7/13 (54%)  
**After Week 2:** ___/13 (___%)

Target: 12/13 (92%)

### Metrics
**Total time spent:** _____ hours  
**Issues encountered:** _____  
**Major blocker:** Yes ☐  No ☐  
**Would recommend this approach:** Yes ☐  No ☐

### What Went Well
1. ________________________________
2. ________________________________
3. ________________________________

### What Was Challenging
1. ________________________________
2. ________________________________
3. ________________________________

### Lessons Learned
1. ________________________________
2. ________________________________
3. ________________________________

---

## 🚨 TROUBLESHOOTING LOG

Use this section to document any issues you encounter:

**Issue #1:**  
Date: _____  
Problem: _________________________________  
Solution: _________________________________  
Time to resolve: _____ min

**Issue #2:**  
Date: _____  
Problem: _________________________________  
Solution: _________________________________  
Time to resolve: _____ min

**Issue #3:**  
Date: _____  
Problem: _________________________________  
Solution: _________________________________  
Time to resolve: _____ min

---

## 📋 NOTES

Use this space for additional notes:

_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________

---

**Week 2 Status:** Complete ☐  In Progress ☐  
**Ready for Week 3:** Yes ☐  No ☐  
**Confidence Level:** ___/100

**Signature:** _____________ **Date:** _________
