# Week 2 Implementation Plan: Secure Internet Exposure
**Generated:** 2025-10-22  
**Timeline:** 5 days @ 1-2 hours/day  
**Priority:** Security first, then functionality

---

## 🎯 Mission Statement

Transform your local-only homelab into a **securely internet-accessible system** with valid TLS certificates, proper authentication, and defense-in-depth security controls.

---

## ⚠️ Critical Security Fixes (MUST DO BEFORE INTERNET EXPOSURE)

### Issues That Will Be Exploited:
2. Traefik API dashboard exposed without authentication
3. Session cookies failing due to self-signed certs # needs to be resolved!
4. No rate limiting on public entrypoints

---

## 📅 Day-by-Day Implementation

### **Day 1 (1-2 hours): Foundation & Security Hardening**

**Goal:** Fix critical vulnerabilities, register domain, prepare for Let's Encrypt

#### Task 1A: Register Domain & Configure DNS (30 min)
- [ ] Register `patriark.org` at Hostinger
- [ ] Configure basic DNS records: # done at Cloudflare - domain still hosted by hostinger
  ```
  A     @              62.249.184.112
  A     *              62.249.184.112  (wildcard for subdomains)

  ```
- [ ] Obtain Cloudflare API token (for DNS-01 ACME challenges) # Cloudflare API token stored in ~/containers/secrets
- [ ] Test DNS propagation: `dig patriark.org @8.8.8.8`

#### Task 1B: Fix Redis Password Exposure (15 min) # abandoned after ditching Authelia for tinyauth
**Current vulnerability:** Plain text password on line 79 of `configuration.yml`



#### Task 1C: Secure Traefik Dashboard (20 min) # this configuration has likely been replaced after implementing tinyauth instead of Authelia - but should still be investigated!
**Current vulnerability:** API dashboard exposed on port 8080 with `insecure: true`




#### Task 1E: Backup Current Configuration (10 min)
```bash
# Already have BTRFS snapshots, but create explicit backup
cd ~/containers
tar -czf ~/backups/homelab-pre-letsencrypt-$(date +%Y%m%d).tar.gz \
  config/ secrets/ quadlets/ scripts/

# Verify backup
tar -tzf ~/backups/homelab-pre-letsencrypt-*.tar.gz | head -20
```
All these backups has been moved to an encrypted external drive - in addition to BTRFS snapshots

**Day 1 Deliverables:**
- ✅ Domain registered and DNS configured
- ✅ Traefik dashboard authentication enabled
- ✅ Configuration backed up

---

### **Day 2 (1-2 hours): Let's Encrypt Integration (DNS-01)** # user is currently here!

**Goal:** Obtain valid TLS certificates using DNS-01 challenge via Cloudflare


#### Task 2C: Update Service Definitions (30 min)



#### Task 2D: Initialize ACME Storage (10 min)



#### Task 2E: Test Certificate Issuance (30 min)


```

**Troubleshooting:**
- If DNS-01 fails: Check Cloudflare API token permissions - located in ~/containers/secrets
- If timeout occurs: Increase `delayBeforeCheck` to 60s
- If rate limited: Wait 1 hour, use staging server

**Day 2 Deliverables:**
- ✅ Traefik configured for ACME DNS-01
- ✅ Staging certificates obtained and validated # evaluate if stagin certificates really are necessary instead of moving straight to production. Fallback is always possible!
- ✅ Service routers updated for .org domain
- ✅ Certificate auto-renewal configured

---

### **Day 3 (1-2 hours): Production Certificates & tinyauth adjustments**

**Goal:** Switch to production certificates,

#### Task 3A: Switch to Production Certificates (20 min)

**Only proceed if staging certificates work perfectly!**

```bash
# Backup staging acme.json
cp ~/containers/data/traefik/letsencrypt/acme.json{,.staging-backup}

# Restart Traefik
systemctl --user restart traefik.service

# Verify production certificates
curl -vI https://auth.patriark.org 2>&1 | grep -i "issuer"
# Should show: "issuer: CN=R3" (Let's Encrypt production)

# Test in browser - no more warnings!
firefox https://auth.patriark.org
```

#### Task 3B: Update Authelia for Dual-Domain (40 min) # abandoned due to tinyauth but consider if applicable for tinyauth


#### Task 3C: Test Authentication Flow (30 min)


**Day 3 Deliverables:**
- ✅ Production Let's Encrypt certificates active


---

### **Day 4 (1-2 hours): UDM Pro Configuration & Internet Exposure** # port-forwarding finalized and services reachable through patriark.org (with some routing errors, likely due to outdated Traefik configs)

**Goal:** Configure port forwarding, firewall rules, enable external access

#### Task 4A: UDM Pro Port Forwarding (30 min) # finalized except rule 3

**Configure in UDM Pro Web Interface:**
```
Settings → Internet → Port Forwarding

Rule 1: HTTP (temporary, for ACME HTTP-01 fallback)
- Name: Homelab-HTTP
- From: Any
- Port: 80
- Forward IP: 192.168.1.70
- Forward Port: 80
- Protocol: TCP
- Enable: Yes

Rule 2: HTTPS (primary)
- Name: Homelab-HTTPS
- From: Any
- Port: 443
- Forward IP: 192.168.1.70
- Forward Port: 443
- Protocol: TCP
- Enable: Yes

Rule 3: WireGuard (for future VPN access) # NOT IMPLEMENTED - is this even necessary if running wireguard server on UDM pro?
- Name: WireGuard-VPN
- From: Any
- Port: 51820
- Forward IP: 192.168.1.1 (UDM itself)
- Forward Port: 51820
- Protocol: UDP
- Enable: No (enable later)
```

**Security recommendation:** Do NOT forward port 8080 (Traefik dashboard)

#### Task 4B: Configure Dynamic DNS (20 min) # Finalized with local update script running on fedora-htpc - not on UDM Pro

**Since you have dynamic IP, set up DDNS on UDM Pro:**

```
Settings → Internet → Dynamic DNS # implemented with local script instead - running every 30 mins

Service: Custom (Cloudflare API)
Hostname: patriark.org
Username: (your Cloudflare username)
Password: (your Cloudflare API token)
Server: api.hostinger.com

Update: Every 5 minutes
```

**Alternatively:** Use Cloudflare proxy (recommended for DDoS protection) # this was implemented instead
- Sign up for Cloudflare (free plan)
- Transfer DNS management to Cloudflare
- Enable "Proxied" (orange cloud) for A records # please provide some information as another guide advocated for leaving this on "DNS only"/grey cloud
- Your IP stays hidden, Cloudflare handles DDoS

**With Cloudflare proxy:**
- ✅ DDoS protection (priority 4/5)
- ✅ Hide your real IP (privacy priority 5/5)
- ✅ Free SSL/TLS (though you have Let's Encrypt)
- ✅ Web Application Firewall (WAF) rules
- ⚠️ Cloudflare sees all traffic (privacy trade-off)
- ⚠️ Cannot use DNS-01 challenge (need API token) # can this be circumvented by DNS only as was currently setup for A records?

#### Task 4C: Test External Access (30 min) # this works but with certificate errors - see above

```bash
# From your phone (mobile data, NOT wifi):
# 1. Open https://auth.patriark.org
# 2. Should load without certificate errors
# 3. Login with credentials                 # is it possible to add TOTP with tinyauth?
# 4. Should successfully authenticate

# Test Jellyfin:
# 1. Navigate to https://jellyfin.patriark.org
# 2. Should redirect to auth.patriark.org
# 3. Login if needed
# 4. Should redirect back to Jellyfin
# 5. Media should play

# Monitor Traefik access logs
podman logs -f traefik | grep -i auth

# Monitor Authelia logs
podman logs -f authelia | grep -i login
```

#### Task 4D: Configure Firewall Rules on UDM Pro (30 min)

**Create security policies between VLANs:**

```
Settings → Firewall → Rules

Rule 1: Block IoT → Homelab # IoT network should already be segmented away from default network, except dns requests are allowed to reach pihole
- Type: Internet In
- Source: VLAN2 (IoT - 192.168.2.0/24)
- Destination: 192.168.1.70
- Action: Drop
- Logging: Enable

Rule 2: Allow WireGuard → Homelab # Not implemented yet
- Type: Internet In
- Source: 192.168.100.0/24 (WireGuard)
- Destination: 192.168.1.70
- Action: Accept
- Logging: Enable

Rule 3: Block Guest → Homelab # Guest network should already be segmented away from other VLANs but have access to Internet and DNS from pihole
- Type: Internet In
- Source: VLAN4 (Guest - 192.168.99.0/24)
- Destination: 192.168.1.70
- Action: Drop
- Logging: Enable

Rule 4: Rate Limit Port 443 (DDoS protection) # could this be secured through fail2ban or other measures? Also, this seems to let any Internet request to reach 192.168.1.70 - is this the best solution? Where should it be placed in the hierarchy of rules?
- Type: Internet In
- Source: Any
- Destination: 192.168.1.70
- Port: 443
- Rate Limit: 100 connections/minute
- Action: Accept
- Logging: Enable
```

**Day 4 Deliverables:** # see comments above
- ✅ Port forwarding active (80, 443)
- ✅ Dynamic DNS configured
- ✅ External access tested and working
- ✅ UDM Pro firewall rules implemented
- ✅ Rate limiting active

---

### **Day 5 (1-2 hours): Monitoring, Documentation & Security Audit**

**Goal:** Implement basic monitoring, document everything, conduct security review

#### Task 5A: Deploy Basic Monitoring (45 min)

**Simple monitoring with Uptime Kuma (lightweight):**

```bash
# Create uptime-kuma.container quadlet
cat > ~/.config/containers/systemd/uptime-kuma.container << 'EOF'
[Unit]
Description=Uptime Kuma - Monitoring
After=network-online.target

[Container]
Image=docker.io/louislam/uptime-kuma:1
ContainerName=uptime-kuma
Volume=%h/containers/data/uptime-kuma:/app/data:Z
Network=systemd-reverse_proxy
Label=traefik.enable=true
Label=traefik.http.routers.uptime.rule=Host(`status.patriark.org`)
Label=traefik.http.routers.uptime.tls=true
Label=traefik.http.routers.uptime.tls.certresolver=letsencrypt-prod
Label=traefik.http.services.uptime.loadbalancer.server.port=3001

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
EOF

# Create data directory
mkdir -p ~/containers/data/uptime-kuma

# Load and start
systemctl --user daemon-reload
systemctl --user start uptime-kuma.service

# Access: https://status.patriark.org
```

**Configure monitors:**
- https://auth.patriark.org (every 1 min)
- https://jellyfin.patriark.org (every 5 min)
- https://traefik.patriark.org (every 5 min)
- ICMP ping to 192.168.1.70 (every 1 min)

#### Task 5B: Security Audit Checklist (30 min)

**Run security verification script:**

security-audit.sh

Result from script 2025-10-23:
➜  ~ ~/containers/scripts/security-audit.sh     
=== Homelab Security Audit ===

[1] Checking for plain-text secrets...
/home/patriark/containers/config/jellyfin/passwordreset06d300a8-12b9-48df-a026-2813233da049.json:{"Pin":"85-DD-A5-DC","UserName":"patriark","PinFile":"/config/passwordreset06d300a8-12b9-48df-a026-2813233da049.json","ExpirationDate":"2025-10-20T21:35:03.654498Z"}
❌ FAIL: Plain-text passwords found
[2] Checking Traefik dashboard auth...
⚠️  WARN: Dashboard may be exposed
[3] Checking TLS certificates...
❌ FAIL: Invalid certificate
[5] Checking rate limiting...
⚠️  WARN: No rate limiting
[6] Checking open ports...
✅ PASS: Only 80/443 exposed
[7] Checking SELinux...
✅ PASS: SELinux enforcing
[8] Checking rootless containers...
✅ PASS: All containers rootless

=== Audit Complete ===


```markdown
# External Access Guide

## Accessing Your Homelab From Anywhere

### Prerequisites
- Device connected to internet (mobile data, public wifi, etc.)
- Modern web browser (Chrome, Firefox, Safari)

### Step 1: Navigate to Service
Open your browser and go to:
- **Jellyfin (movies/TV):** https://jellyfin.patriark.org
- **Nextcloud (files):** https://nextcloud.patriark.org     # not yet implemented!

### Step 3: Access Service
- You'll be redirected back to the service
- You're now logged in securely!

### Troubleshooting
**"Certificate error":**
- Should not happen anymore (valid Let's Encrypt certs)
- If it does, contact admin

**"Login loop":**
- Clear your browser cookies for patriark.org
- Try in private/incognito mode
- Contact admin if persists

**"Connection timeout":**
- Check if your network blocks ports 80/443
- Try mobile data instead of wifi
- Verify service status at https://status.patriark.org
```

#### Task 5D: Create Emergency Rollback Procedure (15 min)

~/containers/scripts/emergency-rollback.sh # not properly configured

**Day 5 Deliverables:**
- ✅ Basic monitoring operational
- ✅ Security audit passed (or issues documented)
- ✅ Documentation updated and published
- ✅ Emergency rollback procedure tested
- ✅ Week 2 complete!

---

## 📊 Success Metrics

### Definition of "Internet-Ready":
- ✅ Valid Let's Encrypt certificates (no browser warnings)
- ✅ External access tested from mobile network
- ✅ No plain-text secrets in configs # not successful needs investigation
- ✅ Traefik dashboard authenticated # might be remnants of old configs exposing it in a risky way - should be investigated
- ✅ Rate limiting active # script return no - should be investigated
- ✅ Monitoring operational # monitoring not yet operational
- ✅ Emergency rollback tested # BTRFS snapshots of /home ensure that fallback always is available

### Security Scorecard:
**Before Week 2:** 7/13 (54%)  
**Target Week 2:** 12/13 (92%)

Only missing:
- Full intrusion detection (Week 3)
- Advanced monitoring/alerting (Week 3)

---

## ⚠️ Important Security Notes

### What NOT to Do:
1. ❌ Do NOT skip Day 1 security fixes # Finalized but might need a second opinion
2. ❌ Do NOT expose port 8080 (Traefik dashboard) # THIS MUST BE INVESTIGATED
3. ❌ Do NOT use production certs before testing staging # not yet implemented
5. ❌ Do NOT disable rate limiting "for performance" # help me setting up high quality configs across my configurations

### Progressive Exposure Strategy:
**Week 2:** Jellyfin + tinyauth only (entertainment + auth) # Traefik dashboard is exposed and should be investigated
**Week 3:** Add Nextcloud (file sync)
**Week 4:** Add Vaultwarden (password manager)
**Week 5+:** Additional services as needed

### Decision: Cloudflare Proxy vs. Direct? # this needs further investigation as I already have Cloudflare for DNS but without proxy - is not https traffic encrypted?

**Cloudflare Proxy (Recommended):**
- ✅ Hides your home IP address
- ✅ Free DDoS protection (your priority 4/5)
- ✅ Web Application Firewall
- ✅ Automatic failover if your internet goes down
- ⚠️ Cloudflare sees all traffic (privacy trade-off)
- ⚠️ Slightly higher latency (~20-50ms)

**Direct DNS (Your Current Plan):**
- ✅ Lower latency
- ✅ Full control over traffic
- ✅ More learning opportunities
- ❌ Your home IP is public knowledge
- ❌ No DDoS protection beyond UDM Pro
- ❌ Requires dynamic DNS management

**My recommendation:** Start direct (Week 2), evaluate Cloudflare in Week 3 after seeing real traffic patterns.

## 🎯 Week 3 Preview

With internet exposure working, Week 3 focuses on:
1. **Advanced Monitoring** - Prometheus + Grafana + Loki
2. **IDS/IPS** - fail2ban or Crowdsec integration
3. **WireGuard VPN** - Secure remote access to all services
4. **Nextcloud Deployment** - File sync with E2E encryption

**Estimated time:** 7-10 hours over 7 days

---

**Status:** 📋 Ready for implementation  
**Risk Level:** Medium (internet exposure requires careful execution)  
**Support:** Document all issues for troubleshooting

**Good luck! Take your time on Day 1 security fixes - they're the foundation for everything else.**
