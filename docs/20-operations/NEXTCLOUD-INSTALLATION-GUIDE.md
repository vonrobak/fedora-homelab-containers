# Nextcloud Installation Guide

**Service:** Nextcloud (Personal Cloud Storage)  
**Purpose:** File sync, collaboration, calendar, contacts  
**Estimated Time:** 20 minutes  
**Difficulty:** Medium

---

## 📋 What You'll Get

- **File Storage** - Personal cloud like Dropbox/Google Drive
- **File Sync** - Desktop and mobile apps
- **Calendar & Contacts** - CalDAV/CardDAV support
- **Document Editing** - Collaborative documents
- **Photo Gallery** - Auto-upload photos
- **Secure** - Encrypted, self-hosted, private
- **Access:** https://nextcloud.patriark.org

---

## 🏗️ Architecture

```
Browser
    ↓
[Traefik] → Authentication & SSL
    ↓
[Nextcloud] → Web interface
    ↓
[MariaDB] → Database (optional, we'll use SQLite first)
```

---

## 🚀 Installation Steps

### Step 1: Create Directories

```bash
# Create config and data directories
mkdir -p ~/containers/config/nextcloud
mkdir -p ~/containers/data/nextcloud

# Set permissions
chmod 755 ~/containers/config/nextcloud
chmod 755 ~/containers/data/nextcloud
```

---

### Step 2: Create Nextcloud Quadlet

```bash
nano ~/.config/containers/systemd/nextcloud.container
```

**Paste this:**

```ini
[Unit]
Description=Nextcloud Personal Cloud
After=network-online.target traefik.service
Wants=network-online.target
Requires=reverse_proxy-network.service

[Container]
Image=docker.io/library/nextcloud:latest
ContainerName=nextcloud
AutoUpdate=registry
Network=systemd-reverse_proxy

# Volumes
Volume=%h/containers/config/nextcloud:/var/www/html:Z
Volume=%h/containers/data/nextcloud:/var/www/html/data:Z

# Environment - Trusted Domains
Environment=NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.patriark.org localhost
Environment=TRUSTED_PROXIES=10.89.2.0/24
Environment=OVERWRITEPROTOCOL=https
Environment=OVERWRITEHOST=nextcloud.patriark.org
Environment=OVERWRITECLIURL=https://nextcloud.patriark.org

# SQLite for simplicity (can upgrade to MariaDB later)
Environment=SQLITE_DATABASE=nextcloud

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
```

**Save:** Ctrl+O, Enter, Ctrl+X

---

### Step 3: Add Traefik Routes

```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Add this router (after existing ones):**

```yaml
    # Nextcloud
    nextcloud:
      rule: "Host(`nextcloud.patriark.org`)"
      service: "nextcloud"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - tinyauth@file
      tls:
        certResolver: letsencrypt
```

**And add this service (in services section):**

```yaml
    nextcloud:
      loadBalancer:
        servers:
          - url: "http://nextcloud:80"
```

**Complete routers.yml should look like:**

```yaml
http:
  routers:
    root-redirect:
      rule: "Host(`patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
      tls:
        certResolver: letsencrypt

    tinyauth-portal:
      rule: "Host(`auth.patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
      tls:
        certResolver: letsencrypt

    traefik-dashboard:
      rule: "Host(`traefik.patriark.org`)"
      service: "api@internal"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - tinyauth@file
      tls:
        certResolver: letsencrypt

    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.org`)"
      service: "jellyfin"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - tinyauth@file
      tls:
        certResolver: letsencrypt

    nextcloud:
      rule: "Host(`nextcloud.patriark.org`)"
      service: "nextcloud"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
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

    nextcloud:
      loadBalancer:
        servers:
          - url: "http://nextcloud:80"
```

**Save:** Ctrl+O, Enter, Ctrl+X

---

### Step 4: Start Nextcloud

```bash
# Reload systemd
systemctl --user daemon-reload

# Start Nextcloud (takes ~30 seconds first time)
systemctl --user start nextcloud.service

# Wait for initialization
echo "Waiting for Nextcloud to initialize..."
sleep 30

# Check status
systemctl --user status nextcloud.service

# Check it's running
podman ps | grep nextcloud

# Check logs
podman logs nextcloud --tail 30
```

---

### Step 5: Restart Traefik

```bash
# Restart Traefik to pick up new routes
systemctl --user restart traefik.service

# Wait
sleep 5

# Verify no errors
podman logs traefik --tail 20 | grep -i error
```

---

### Step 6: Initial Setup via Web

**Open browser and go to:**
```
https://nextcloud.patriark.org
```

**You'll see:**
1. Tinyauth login (use your patriark credentials)
2. Nextcloud setup page

**On Nextcloud setup page:**

1. **Create Admin Account:**
   - Username: `admin` (or your preference)
   - Password: (strong password)

2. **Data Folder:**
   - Leave default: `/var/www/html/data`

3. **Database:**
   - Select: **SQLite** (simplest, good for personal use)
   - (Can upgrade to MariaDB later if needed)

4. **Click:** "Install"

**Wait 1-2 minutes for installation to complete.**

---

### Step 7: Post-Installation Configuration

After installation completes, you'll see warnings about configuration. Let's fix them:

```bash
# Enter Nextcloud container
podman exec -it -u www-data nextcloud bash

# Run maintenance commands
php occ maintenance:update:htaccess
php occ db:add-missing-indices
php occ db:convert-filecache-bigint

# Exit container
exit
```

**Restart Nextcloud:**
```bash
systemctl --user restart nextcloud.service
sleep 10
```

**Reload page** - warnings should be gone or reduced.

---

## 🔧 Configuration Tweaks

### Enable Cron (Background Jobs)

**Option A: System Cron (Recommended)**

```bash
# Create systemd timer for Nextcloud cron
nano ~/.config/systemd/user/nextcloud-cron.service
```

**Paste:**
```ini
[Unit]
Description=Nextcloud Cron Job

[Service]
Type=oneshot
ExecStart=/usr/bin/podman exec -u www-data nextcloud php cron.php
```

**Create timer:**
```bash
nano ~/.config/systemd/user/nextcloud-cron.timer
```

**Paste:**
```ini
[Unit]
Description=Run Nextcloud Cron every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

**Enable:**
```bash
systemctl --user daemon-reload
systemctl --user enable nextcloud-cron.timer
systemctl --user start nextcloud-cron.timer

# Verify
systemctl --user list-timers | grep nextcloud
```

**In Nextcloud web interface:**
1. Go to **Settings** → **Administration** → **Basic settings**
2. Under **Background jobs**, select **Cron**

---

### Increase Upload Size (Optional)

```bash
# Create custom PHP config
mkdir -p ~/containers/config/nextcloud/custom

cat > ~/containers/config/nextcloud/custom/upload.ini << 'EOF'
upload_max_filesize = 10G
post_max_size = 10G
memory_limit = 512M
EOF

# Update quadlet to mount it
nano ~/.config/containers/systemd/nextcloud.container
```

**Add this volume line:**
```ini
Volume=%h/containers/config/nextcloud/custom/upload.ini:/usr/local/etc/php/conf.d/upload.ini:ro,Z
```

**Restart:**
```bash
systemctl --user daemon-reload
systemctl --user restart nextcloud.service
```

---

### Enable Pretty URLs

```bash
# Enter container
podman exec -it -u www-data nextcloud bash

# Enable pretty URLs
php occ config:system:set htaccess.RewriteBase --value='/'
php occ maintenance:update:htaccess

# Exit
exit

# Restart
systemctl --user restart nextcloud.service
```

---

## 📱 Client Apps

### Desktop Sync

**Download:**
- Windows: https://nextcloud.com/install/#install-clients
- macOS: https://nextcloud.com/install/#install-clients
- Linux: `sudo dnf install nextcloud-client`

**Setup:**
1. Install app
2. Enter server: `https://nextcloud.patriark.org`
3. Login via browser (Tinyauth + Nextcloud)
4. Choose sync folders

### Mobile Apps

**Download:**
- iOS: App Store → "Nextcloud"
- Android: Play Store → "Nextcloud"

**Setup:**
1. Open app
2. Enter: `https://nextcloud.patriark.org`
3. Login (will redirect to Tinyauth, then Nextcloud)
4. Enable auto-upload for photos (optional)

---

## 🔐 Security Considerations

### Nextcloud Has Two Login Layers

```
User Request
    ↓
[Tinyauth] ← First authentication (SSO)
    ↓
[Nextcloud] ← Second authentication (Nextcloud user)
```

**This is actually good security!**
- Tinyauth protects against unauthorized access
- Nextcloud provides granular user permissions

### Optional: Bypass Tinyauth for Nextcloud

If you want Nextcloud to handle auth entirely:

```bash
nano ~/containers/config/traefik/dynamic/routers.yml
```

**Change Nextcloud router to:**
```yaml
    nextcloud:
      rule: "Host(`nextcloud.patriark.org`)"
      service: "nextcloud"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        # Removed: tinyauth@file
      tls:
        certResolver: letsencrypt
```

**Then restart Traefik:**
```bash
systemctl --user restart traefik.service
```

**Now:** Only Nextcloud login required (still protected by CrowdSec and rate limiting)

---

## 🎨 Customization

### Install Apps

1. Login to Nextcloud
2. Click your profile → **Apps**
3. Browse and install:
   - **Calendar** - CalDAV calendar
   - **Contacts** - CardDAV contacts
   - **Talk** - Video calls
   - **Deck** - Kanban boards
   - **Tasks** - Todo lists
   - **Notes** - Simple notes
   - **Photos** - Photo gallery

### Change Theme

1. **Settings** → **Administration** → **Theming**
2. Upload logo
3. Change colors
4. Set background

---

## 📊 Monitoring

### Check Status

```bash
# Service status
systemctl --user status nextcloud.service

# Container logs
podman logs nextcloud --tail 50

# Nextcloud status
podman exec -u www-data nextcloud php occ status
```

### Check Disk Usage

```bash
# Data directory size
du -sh ~/containers/data/nextcloud

# Per-user storage
podman exec -u www-data nextcloud php occ user:report
```

---

## 🔧 Maintenance

### Update Nextcloud

```bash
# Pull new image
podman pull docker.io/library/nextcloud:latest

# Restart (auto-updates container)
systemctl --user restart nextcloud.service

# Wait for update
sleep 30

# Check logs
podman logs nextcloud --tail 50

# Run upgrade if prompted in web UI
# Or via command:
podman exec -u www-data nextcloud php occ upgrade
```

### Backup

```bash
# Stop Nextcloud
systemctl --user stop nextcloud.service

# Backup data and config
tar -czf ~/backups/nextcloud-$(date +%Y%m%d).tar.gz \
    ~/containers/config/nextcloud \
    ~/containers/data/nextcloud

# Or use BTRFS snapshot
sudo btrfs subvolume snapshot /home /home-nextcloud-$(date +%Y%m%d)

# Restart
systemctl --user start nextcloud.service
```

---

## 🚀 Advanced: Add MariaDB (Optional)

For better performance with multiple users:

### Create MariaDB Container

```bash
nano ~/.config/containers/systemd/nextcloud-db.container
```

```ini
[Unit]
Description=MariaDB for Nextcloud
After=network-online.target

[Container]
Image=docker.io/library/mariadb:latest
ContainerName=nextcloud-db
AutoUpdate=registry
Network=systemd-reverse_proxy

Volume=%h/containers/data/nextcloud-db:/var/lib/mysql:Z

Environment=MYSQL_ROOT_PASSWORD=CHANGE_THIS_PASSWORD
Environment=MYSQL_DATABASE=nextcloud
Environment=MYSQL_USER=nextcloud
Environment=MYSQL_PASSWORD=CHANGE_THIS_PASSWORD

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Start it:**
```bash
systemctl --user daemon-reload
systemctl --user start nextcloud-db.service
```

**Migrate to MariaDB:**
```bash
# Use Nextcloud's database converter
podman exec -u www-data nextcloud php occ db:convert-type \
    mysql nextcloud nextcloud-db nextcloud
```

---

## 📋 Troubleshooting

### Can't Access Nextcloud

```bash
# Check container is running
podman ps | grep nextcloud

# Check logs for errors
podman logs nextcloud --tail 50

# Check Traefik routing
curl -I https://nextcloud.patriark.org

# Restart everything
systemctl --user restart nextcloud.service
systemctl --user restart traefik.service
```

### "Trusted Domain" Error

```bash
# Add your domain to trusted domains
podman exec -u www-data nextcloud php occ config:system:set \
    trusted_domains 1 --value=nextcloud.patriark.org
```

### Slow Performance

```bash
# Enable PHP opcache (already enabled in official image)

# Add Redis for caching (advanced)
# Install redis container and configure Nextcloud to use it

# Enable file locking
podman exec -u www-data nextcloud php occ config:system:set \
    filelocking.enabled --value=true
```

### Upload Fails

```bash
# Check disk space
df -h ~/containers/data/nextcloud

# Increase PHP limits (see "Increase Upload Size" above)

# Check Nextcloud logs
podman exec nextcloud cat /var/www/html/data/nextcloud.log | tail -50
```

---

## ✅ Success Checklist

After installation:

- [ ] Can access https://nextcloud.patriark.org
- [ ] Can login (Tinyauth → Nextcloud)
- [ ] Can upload files
- [ ] Can create folders
- [ ] Apps installed (Calendar, Contacts, etc.)
- [ ] Desktop client syncing
- [ ] Mobile app connected
- [ ] Cron job running
- [ ] No warnings in admin panel

---

## 🎊 You Now Have

- ✅ **Personal cloud storage**
- ✅ **File sync across devices**
- ✅ **Calendar and contacts**
- ✅ **Secure, self-hosted**
- ✅ **Protected by Tinyauth + CrowdSec**
- ✅ **Valid SSL certificates**
- ✅ **Automatic backups possible**

---

## 🚀 Next Steps

- Upload files and test sync
- Install mobile apps
- Set up calendar/contacts sync on phone
- Configure automatic photo backup
- Share files with others (create additional users)
- Explore apps (Talk, Deck, Notes)

---

**Congratulations! You've added Nextcloud to your homelab!** 🎉

Your homelab now includes:
1. Traefik (reverse proxy)
2. CrowdSec (security)
3. Tinyauth (authentication)
4. Jellyfin (media)
5. Nextcloud (cloud storage) ← NEW!

**Want to add more services? The pattern is established - you're unstoppable now!** 🚀
