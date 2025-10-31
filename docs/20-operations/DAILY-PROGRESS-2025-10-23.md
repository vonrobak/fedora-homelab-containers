# Homelab Progress Documentation - October 22-23, 2025

## 📊 **Today's Achievements**

### ✅ **Phase 1: Authentication System - COMPLETE**
- Removed Authelia (backed up safely)
- Installed and configured Tinyauth
- SSO authentication working on LAN
- All services protected with login

### ✅ **Phase 2: Verification - COMPLETE**
- Documented current state
- Created backup strategies
- Verified all containers running

### ✅ **Phase 3: Dynamic DNS with Cloudflare - 95% COMPLETE**
- Cloudflare account created
- DNS transferred from Hostinger
- Automatic DDNS script working (updates every 30 minutes)
- Wildcard DNS configured (*.patriark.org)
- Services accessible from internet

### 🔄 **Phase 4: SSL Certificates - IN PROGRESS**
- Self-signed certificates working on LAN ✅
- Let's Encrypt setup ready (next step)
- iPhone access blocked by certificate warnings (will be fixed by Let's Encrypt)

---

## 🗂️ **Current System State**

### **Services Running:**
```
tinyauth        - Authentication portal (port 3000)
traefik         - Reverse proxy (ports 80, 443, 8080)
jellyfin        - Media server (port 8096)
```

### **DNS Configuration:**
```
patriark.org        → 62.249.184.112 (public IP)
*.patriark.org      → 62.249.184.112 (wildcard)

Local DNS (Pi-hole also resolves):
jellyfin.patriark.org  → 192.168.1.70
auth.patriark.org      → 192.168.1.70
traefik.patriark.org   → 192.168.1.70
```

### **Network Configuration:**
- **Server IP:** 192.168.1.70
- **UDM Pro IP:** 192.168.1.1
- **Pi-hole IP:** 192.168.1.69
- **Public IP:** 62.249.184.112

### **Port Forwarding (UDM Pro):**
- Port 80 (HTTP) → 192.168.1.70:80
- Port 443 (HTTPS) → 192.168.1.70:443

### **Podman Networks:**
- `systemd-reverse_proxy` - Traefik, Tinyauth, Jellyfin

---

## 📁 **Important File Locations**

### **Configuration Files:**
```
~/containers/config/traefik/traefik.yml           - Main Traefik config
~/containers/config/traefik/dynamic/routers.yml   - Service routing rules
~/containers/config/traefik/dynamic/middleware.yml - Security headers and auth
~/containers/config/traefik/letsencrypt/          - SSL certificates (create this)
```

### **Quadlet Files (Systemd):**
```
~/.config/containers/systemd/tinyauth.container   - Tinyauth service
~/.config/containers/systemd/traefik.container    - Traefik service
~/.config/containers/systemd/jellyfin.container   - Jellyfin service
```

### **Scripts:**
```
~/containers/scripts/cloudflare-ddns.sh           - Auto-update DNS
~/.config/systemd/user/cloudflare-ddns.timer      - Runs script every 30 min
~/.config/systemd/user/cloudflare-ddns.service    - Service definition
```

### **Secrets:**
```
~/containers/secrets/cloudflare_token             - Cloudflare API token
~/containers/secrets/cloudflare_zone_id           - Zone ID for patriark.org
```

### **Backups:** # currently moved away to encrypted external drive
```
~/containers/backups/phase1-TIMESTAMP/            - Authelia removal backup
~/containers/backups/authelia-to-tinyauth-*/      - Migration backups
```

---

## 🔐 **Authentication Credentials**

### **Tinyauth Login:**
- **Username:** patriark
- **Password:** [your password]
- **Portal:** https://auth.patriark.org

### **How to Add More Users:**
```bash
# Generate hash for new user
podman run --rm -i ghcr.io/steveiliop56/tinyauth:v4 user create --interactive

# Edit tinyauth quadlet
nano ~/.config/containers/systemd/tinyauth.container

# Add comma-separated in USERS line:
Environment=USERS=patriark:$$hash1,newuser:$$hash2

# Restart
systemctl --user daemon-reload
systemctl --user restart tinyauth.service
```

---

## 🌐 **Access URLs**

### **Local Access (LAN):**
```
https://jellyfin.patriark.org   - Media server (requires login)
https://traefik.patriark.org    - Dashboard (requires login)
https://auth.patriark.org       - Authentication portal
https://patriark.org            - Redirects to auth
```

### **Internet Access:**
Same URLs work from internet via public IP and port forwarding.

### **Current Status:**
- ✅ LAN access working perfectly (with self-signed cert warnings)
- ⚠️ Internet access working but certificate warnings on iPhone
- 🔜 Let's Encrypt will fix certificate warnings

---

## 🚧 **Known Issues & Solutions**

### **Issue 1: Certificate Warnings**
**Status:** Expected with self-signed certificates  
**Solution:** Set up Let's Encrypt (next step)  
**Workaround:** Click "Show Details" → "Visit this website" on warnings

### **Issue 2: iPhone Can't Access**
**Cause:** iOS strict certificate validation  
**Solution:** Let's Encrypt will fix this completely  
**Timeline:** 10 minutes setup + 60 seconds for cert generation

### **Issue 3: Tinyauth Domain Warning**
**Status:** Minor annoyance, goes away after proper login  
**Solution:** Already using correct APP_URL (auth.patriark.org)  
**Note:** Will disappear with Let's Encrypt

### **Issue 4: Telenor SafeZone Blocking**
**Status:** False positive malware warning  
**Cause:** Your public IP was previously used by someone else  
**Workaround:** Use 1.1.1.1 VPN app on iPhone  
**Long-term:** Request removal from Telenor blocklist

---

## 📝 **Next Steps (After Sleep)**

### **Step 1: Let's Encrypt Setup (10 minutes)**

**A. Create certificate storage:**
```bash
mkdir -p ~/containers/config/traefik/letsencrypt
chmod 600 ~/containers/config/traefik/letsencrypt
```

**B. Edit Traefik main config:**
```bash
nano ~/containers/config/traefik/traefik.yml
```

Add at the end:
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com  # CHANGE THIS
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

**C. Update Traefik quadlet:**
```bash
nano ~/.config/containers/systemd/traefik.container
```

Add in [Container] section:
```ini
Volume=%h/containers/config/traefik/letsencrypt:/letsencrypt:Z
```

**D. Update routers to use Let's Encrypt:**
```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

Change ALL `tls: {}` to:
```yaml
tls:
  certResolver: letsencrypt
```

**E. Restart Traefik:**
```bash
systemctl --user daemon-reload
systemctl --user restart traefik.service
```

**F. Wait for certificates (60 seconds):**
```bash
sleep 60
ls -la ~/containers/config/traefik/letsencrypt/
# Should see acme.json file
```

**G. Test from iPhone:**
- No VPN needed
- No certificate warnings!
- Everything works ✅

---

### **Step 2: Optional - Phase 4 (WireGuard VPN)**

**Purpose:** Secure VPN access instead of exposing services to internet  
**Time:** 45 minutes  
**File:** See `PHASE4-WIREGUARD-VPN.md`

**Benefits:**
- More secure (no public exposure)
- Access homelab from anywhere
- Encrypted tunnel

**Considerations:**
- Requires VPN client on devices
- More setup complexity
- Family members need VPN configured

**Recommendation:** Get Let's Encrypt working first, then decide if you want VPN later.

---

## 🔄 **Maintenance Tasks**

### **Daily:**
- None! Everything runs automatically

### **Weekly:**
```bash
# Check services are running
podman ps

# Check DDNS is updating
systemctl --user status cloudflare-ddns.timer
```

### **Monthly:**
```bash
# Update containers
podman auto-update

# Check disk space
df -h /home

# Review logs for issues
journalctl --user -u traefik.service --since "1 month ago" | grep -i error
```

### **Quarterly:**
```bash
# Backup configuration
tar -czf ~/containers/backups/config-$(date +%Y%m%d).tar.gz \
  ~/containers/config \
  ~/.config/containers/systemd \
  ~/containers/scripts

# Update documentation
# Create new BTRFS snapshot
```

---

## 📊 **BTRFS Snapshots**

### **Current Snapshots:**
```bash
# List snapshots
sudo btrfs subvolume list / | grep home

# Create new snapshot
sudo btrfs subvolume snapshot /home /home-snapshot-$(date +%Y%m%d-%H%M)
```

### **Restore from Snapshot:**
```bash
# If something breaks, restore:
sudo btrfs subvolume snapshot /home-snapshot-TIMESTAMP /home
reboot
```

### **Recommended Snapshot Schedule:**
- Before major changes (like today)
- After successful configuration
- Weekly for safety

---

## 🛠️ **Troubleshooting Commands**

### **Check Service Status:**
```bash
# All services
podman ps -a

# Specific service
systemctl --user status tinyauth.service
systemctl --user status traefik.service
systemctl --user status jellyfin.service
```

### **View Logs:**
```bash
# Container logs
podman logs tinyauth --tail 50
podman logs traefik --tail 50
podman logs jellyfin --tail 50

# Service logs
journalctl --user -u tinyauth.service -n 50
journalctl --user -u traefik.service -n 50
```

### **Test Connectivity:**
```bash
# Test from server
curl -k https://jellyfin.patriark.org

# Test DNS
dig jellyfin.patriark.org +short

# Test ports
ss -tlnp | grep -E ":80 |:443 "

# Test authentication
curl -k https://jellyfin.patriark.org
# Should return 401 or redirect (= auth is working)
```

### **Restart Everything:**
```bash
# Nuclear option if things are weird
systemctl --user restart tinyauth.service
systemctl --user restart traefik.service
systemctl --user restart jellyfin.service

# Wait and check
sleep 10
podman ps
```

---

## 📚 **Documentation Files Created**

### **Guides:**
```
CURRENT-STATE-ANALYSIS.md          - System analysis and decision framework
PHASE1-INSTRUCTIONS.md             - Authelia removal and Tinyauth setup
PHASE3-CLOUDFLARE-DDNS.md          - Complete Cloudflare DDNS guide
PHASE4-WIREGUARD-VPN.md            - WireGuard VPN setup (optional)
TINYAUTH-GUIDE.md                  - Complete Tinyauth documentation
```

### **Scripts:**
```
cloudflare-ddns.sh                 - Automatic DNS updates
document-current-state.sh          - System state documentation
remove-authelia.sh                 - Clean Authelia removal
```

---

## 🎯 **Success Criteria**

### **What's Working:**
- ✅ Tinyauth authentication on LAN
- ✅ All services protected by SSO
- ✅ Dynamic DNS updating automatically
- ✅ Services accessible from internet
- ✅ Port forwarding configured
- ✅ Wildcard DNS working

### **What Needs Completion:**
- 🔜 Let's Encrypt SSL certificates (10 min task)
- 🔜 iPhone internet access (fixed by Let's Encrypt)
- 🔜 Remove certificate warnings (fixed by Let's Encrypt)

### **Optional Future Enhancements:**
- 🔄 WireGuard VPN (more secure access)
- 🔄 More services (Nextcloud, Vaultwarden, etc.)
- 🔄 Monitoring (Uptime Kuma, Grafana)
- 🔄 Automated backups

---

## 💾 **Backup Checklist**

### **Before Making Changes:**
```bash
# 1. BTRFS snapshot
sudo btrfs subvolume snapshot /home /home-before-change-$(date +%Y%m%d)

# 2. Backup configs
cp -r ~/containers/config ~/containers/backups/config-$(date +%Y%m%d)
cp -r ~/.config/containers/systemd ~/.config/containers/systemd-backup-$(date +%Y%m%d)

# 3. Document what you're changing
nano ~/containers/documentation/changes-$(date +%Y%m%d).md
```

### **Current Backup Locations:**
```
/home-before-change-20251023        - BTRFS snapshot from today
~/containers/backups/phase1-*/      - Authelia removal backup
~/containers/backups/config-*/      - Configuration backups
```

---

## 🔐 **Security Notes**

### **What's Secured:**
- ✅ All services behind Tinyauth authentication
- ✅ HTTPS encryption (self-signed for now, Let's Encrypt soon)
- ✅ UDM Pro firewall protecting network
- ✅ Only ports 80/443 exposed to internet
- ✅ Secrets stored in protected files (chmod 600)

### **Security Best Practices:**
- Strong password for Tinyauth
- Regular updates (podman auto-update)
- Monitor logs for suspicious activity
- Keep backups current
- Consider WireGuard VPN for even more security

### **Exposed to Internet:**
- Port 80 (HTTP) - redirects to HTTPS
- Port 443 (HTTPS) - protected by Tinyauth
- All traffic encrypted and authenticated ✅

---

## 📞 **Quick Reference**

### **Restart Service:**
```bash
systemctl --user restart SERVICE.service
```

### **View Logs:**
```bash
podman logs CONTAINER --tail 50
journalctl --user -u SERVICE.service -n 50
```

### **Check Status:**
```bash
podman ps
systemctl --user status SERVICE.service
```

### **Update DNS:**
```bash
~/containers/scripts/cloudflare-ddns.sh
```

### **Test Access:**
```bash
curl -k https://jellyfin.patriark.org
```

---

## 🎓 **Lessons Learned**

### **What Worked Well:**
1. **Tinyauth** - Much simpler than Authelia, works reliably
2. **Cloudflare DDNS** - Free, fast, reliable DNS
3. **Quadlets** - Clean systemd integration for containers
4. **BTRFS snapshots** - Safety net for experiments
5. **Incremental approach** - Phase by phase is manageable

### **What Was Challenging:**
1. **Authelia complexity** - Too many moving parts for our needs
2. **Network troubleshooting** - Multi-network setup was confusing
3. **Certificate warnings** - Self-signed certs cause friction
4. **iPhone strictness** - More strict certificate validation

### **Key Takeaways:**
1. **Simpler is better** - Tinyauth > Authelia for our use case
2. **Good DNS is critical** - Pi-hole + Cloudflare = perfect combo
3. **Document everything** - Easy to forget configuration details
4. **Backup before changes** - BTRFS snapshots saved us multiple times
5. **Test incrementally** - Don't change everything at once

---

## 🚀 **Tomorrow's Plan**

### **Priority 1: Let's Encrypt (Required)**
- 10 minutes to configure
- 60 seconds to generate certificates
- Fixes all certificate warnings
- Makes iPhone access work perfectly

### **Priority 2: Test Everything**
- Access from iPhone (cellular)
- Access from LAN (Fedora)
- Test all services (Jellyfin, Traefik)
- Verify authentication works smoothly

### **Priority 3: Documentation**
- Update this document with Let's Encrypt setup
- Create quick reference card
- Document any issues encountered

### **Optional: Phase 4 (WireGuard)**
- Only if you want VPN access
- Can be done anytime later
- Not required for basic functionality

---

## ✅ **Pre-Sleep Checklist**

- [x] Create BTRFS snapshot
- [x] Document today's progress
- [x] Save all important configurations
- [x] Services running and accessible on LAN
- [x] DDNS updating automatically
- [x] Clear plan for tomorrow
- [x] Backup files saved
- [x] System stable and working

---

## 💤 **Good Night!**

**You've accomplished a LOT today:**
- Removed complex Authelia
- Set up simpler Tinyauth
- Configured Cloudflare DDNS
- Services accessible from internet
- Authentication working on LAN

**Tomorrow is just finishing touches:**
- Add Let's Encrypt (10 minutes)
- Test from iPhone
- Everything will work perfectly! ✅

**Sleep well!** 🌙

---

**Last Updated:** October 23, 2025 01:30 CEST  
**Status:** Stable, 95% complete  
**Next Task:** Let's Encrypt SSL setup
