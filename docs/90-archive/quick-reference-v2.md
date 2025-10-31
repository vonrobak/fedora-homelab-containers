# Homelab Quick Reference (v2 - Post Day 6)

**Updated:** $(date +%Y-%m-%d)

---

## Emergency Commands

### Restart Services
```bash
systemctl --user restart traefik.service
systemctl --user restart jellyfin.service
```

### Check Status
```bash
# All services
podman ps

# Specific service
systemctl --user status jellyfin.service

# Traefik routes
curl -s localhost:8080/api/http/routers | jq
```

### View Logs
```bash
# Live logs
journalctl --user -u traefik.service -f
journalctl --user -u jellyfin.service -f

# Recent logs
journalctl --user -u traefik.service -n 50
```

---

## Access URLs

| Service | URL | Notes |
|---------|-----|-------|
| Jellyfin | https://jellyfin.lokal | Secure access |
| Jellyfin (direct) | http://jellyfin.lokal:8096 | Bypass Traefik |
| Traefik Dashboard | http://traefik.lokal:8080/dashboard/ | Monitoring |
| Pi-hole | http://192.168.1.69/admin | DNS admin |

---

## Quadlet Management
```bash
# Edit configuration
nano ~/.config/containers/systemd/jellyfin.container

# Apply changes
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# Check generated service
systemctl --user cat jellyfin.service
```

---

## Network Commands
```bash
# List networks
podman network ls

# Inspect network
podman network inspect systemd-reverse_proxy

# Check container networks
podman inspect jellyfin | jq '.[0].NetworkSettings.Networks'
```

---

## Common Fixes

### Service won't start
```bash
systemctl --user status SERVICE.service
journalctl --user -u SERVICE.service -n 50
```

### Network issues
```bash
# Restart network services
systemctl --user restart media_services-network.service
systemctl --user restart reverse_proxy-network.service
```

### Traefik not seeing containers
```bash
# Check Traefik logs
journalctl --user -u traefik.service -n 50

# Verify container labels
podman inspect jellyfin | jq '.[0].Config.Labels'

# Check network
podman inspect traefik | jq '.[0].NetworkSettings.Networks'
```

### Permission denied on port 80/443
```bash
# Check setting
sysctl net.ipv4.ip_unprivileged_port_start

# Should be 80, if not:
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## File Locations

### Quadlets
```
~/.config/containers/systemd/
├── jellyfin.container
├── traefik.container
├── media_services.network
└── reverse_proxy.network
```

### Configuration
```
~/containers/config/
├── traefik/
│   ├── traefik.yml (static)
│   ├── dynamic/ (routes, middleware)
│   └── certs/ (SSL certificates)
└── jellyfin/
    └── (Jellyfin config)
```

### Generated Services
```
/run/user/$(id -u)/systemd/generator/
├── jellyfin.service
├── traefik.service
├── media_services-network.service
└── reverse_proxy-network.service
```

---

## Backup Commands
```bash
# Quick backup
BACKUP_DIR=~/containers/backups/manual-$(date +%Y%m%d)
mkdir -p $BACKUP_DIR
cp -r ~/.config/containers/systemd $BACKUP_DIR/
cp -r ~/containers/config/traefik $BACKUP_DIR/
cp -r ~/containers/config/jellyfin $BACKUP_DIR/
```

---

## Monitoring
```bash
# Resource usage
podman stats

# Traefik metrics
curl -s localhost:8080/api/http/routers | jq

# Service health
systemctl --user is-active jellyfin.service
```

---

**Last Updated:** $(date +%Y-%m-%d)
**Infrastructure:** Quadlet-based, production ready
**Next:** Day 7 - Authelia + YubiKey
