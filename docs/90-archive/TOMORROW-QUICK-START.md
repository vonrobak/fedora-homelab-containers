# Quick Start Guide - Tomorrow Morning

## 🌅 **What You Need to Do**

### **ONE TASK: Add Let's Encrypt (10 minutes)**

This will fix ALL remaining issues:
- ✅ Remove certificate warnings
- ✅ Enable iPhone access
- ✅ Professional SSL certificates
- ✅ Auto-renewing (no maintenance)

---

## ⚡ **Step-by-Step Commands**

Copy and paste these in order:

### **Step 1: Create Certificate Directory**
```bash
mkdir -p ~/containers/config/traefik/letsencrypt
chmod 600 ~/containers/config/traefik/letsencrypt
```

### **Step 2: Edit Traefik Main Config**
```bash
nano ~/containers/config/traefik/traefik.yml
```

**Add at the very end:**
```yaml

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-actual-email@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

**Save:** Ctrl+O, Enter, Ctrl+X

### **Step 3: Update Traefik Quadlet**
```bash
nano ~/.config/containers/systemd/traefik.container
```

**Add this line in [Container] section:**
```ini
Volume=%h/containers/config/traefik/letsencrypt:/letsencrypt:Z
```

**Save:** Ctrl+O, Enter, Ctrl+X

### **Step 4: Update All Routers**
```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Replace ENTIRE file with:**
```yaml
http:
  routers:
    root-redirect:
      rule: "Host(`patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
    
    tinyauth-portal:
      rule: "Host(`auth.patriark.lokal`) || Host(`auth.patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
    
    traefik-dashboard:
      rule: "Host(`traefik.patriark.lokal`) || Host(`traefik.patriark.org`)"
      service: "api@internal"
      entryPoints:
        - websecure
      middlewares:
        - tinyauth@file
      tls:
        certResolver: letsencrypt
    
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.lokal`) || Host(`jellyfin.patriark.org`)"
      service: "jellyfin"
      entryPoints:
        - websecure
      middlewares:
        - tinyauth@file
      tls:
        certResolver: letsencrypt
  
  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
    
    tinyauth:
      loadBalancer:
        servers:
          - url: "http://tinyauth:3000"
```

**Save:** Ctrl+O, Enter, Ctrl+X

### **Step 5: Restart Traefik**
```bash
systemctl --user daemon-reload
systemctl --user restart traefik.service
```

### **Step 6: Wait for Certificates (Important!)**
```bash
echo "Waiting for Let's Encrypt certificates..."
sleep 60
echo "Done! Checking..."
ls -la ~/containers/config/traefik/letsencrypt/
```

**Should see:** `acme.json` file

### **Step 7: Check Logs**
```bash
podman logs traefik | grep -i certificate
```

**Should see:** Messages about obtaining certificates successfully

---

## 🧪 **Testing**

### **From Fedora:**
```bash
curl -v https://jellyfin.patriark.org 2>&1 | grep "subject:"
```

**Should show:** Let's Encrypt certificate (not self-signed)

### **From Browser (Fedora):**
1. Go to: https://jellyfin.patriark.org
2. **No certificate warning!** ✅
3. Tinyauth login appears
4. Login works smoothly

### **From iPhone:**
1. Turn on cellular data (not WiFi)
2. Open Safari
3. Go to: https://jellyfin.patriark.org
4. **No certificate warning!** ✅
5. Tinyauth login appears
6. Login and access Jellyfin ✅

---

## ⚠️ **If Something Goes Wrong**

### **Certificate Not Generated:**
```bash
# Check Traefik can reach Let's Encrypt
podman logs traefik | grep -i acme | tail -20

# Common issue: Port 80 not accessible from internet
# Test: curl http://your-public-ip from outside network
```

### **Still Getting Certificate Warnings:**
```bash
# Wait longer (can take up to 5 minutes)
sleep 180

# Check certificate file
cat ~/containers/config/traefik/letsencrypt/acme.json | jq

# If empty, check logs
podman logs traefik | grep -i error
```

### **Traefik Won't Start:**
```bash
# Check for config errors
podman logs traefik --tail 50

# Most common: YAML syntax error
# Re-check routers.yml indentation
```

---

## 🆘 **Emergency Rollback**

If Let's Encrypt breaks something:

```bash
# Restore previous routers.yml
cp ~/containers/backups/phase1-*/traefik-config/dynamic/routers.yml \
   ~/containers/config/traefik/dynamic/routers.yml

# Restart
systemctl --user restart traefik.service

# Everything back to working (with self-signed certs)
```

---

## ✅ **Success Checklist**

After completing all steps:

- [ ] acme.json file exists
- [ ] No certificate warnings in browser (Fedora)
- [ ] No certificate warnings on iPhone
- [ ] Can login to Jellyfin from iPhone
- [ ] Can access Traefik dashboard
- [ ] All services working smoothly

---

## 🎉 **When Complete**

### **You Will Have:**
- Professional SSL certificates
- No certificate warnings anywhere
- iPhone access working perfectly
- Automatic certificate renewal
- Production-ready homelab!

### **Total Time Investment:**
- Today: 3-4 hours (authentication + DNS)
- Tomorrow: 10 minutes (SSL)
- **Total: One evening of work for complete homelab!** 🚀

---

## 📝 **Notes**

### **Current Credentials:**
- **Tinyauth:** patriark / [your password]
- **Access:** https://jellyfin.patriark.org

### **Important Files:**
```
~/containers/config/traefik/traefik.yml
~/containers/config/traefik/dynamic/routers.yml
~/.config/containers/systemd/traefik.container
```

### **Backup Location:**
```
~/containers/backups/phase1-TIMESTAMP/
```

---

## 🌟 **You're Almost There!**

Just one 10-minute task tomorrow and everything will be perfect!

Sleep well! 💤
