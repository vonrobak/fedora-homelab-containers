# Homelab Quick Reference Card

**Print this and keep it handy!**

---

## Emergency Commands

### Restart Everything
```bash
systemctl --user restart jellyfin.service
```

### Check What's Running
```bash
podman ps
~/containers/scripts/jellyfin-status.sh
```

### View Logs
```bash
~/containers/scripts/jellyfin-manage.sh logs
~/containers/scripts/jellyfin-manage.sh follow  # Live
```

---

## Access URLs

| Service | URL |
|---------|-----|
| Jellyfin | http://jellyfin.lokal:8096 |
| Pi-hole | http://192.168.1.69/admin |

---

## Management Scripts
```bash
# Jellyfin
~/containers/scripts/jellyfin-manage.sh status
~/containers/scripts/jellyfin-manage.sh restart
~/containers/scripts/jellyfin-manage.sh logs

# Network
~/containers/scripts/show-network-topology.sh

# Pods
~/containers/scripts/show-pod-status.sh
```

---

## Service Names

| Old Name | New Name |
|----------|----------|
| container-jellyfin.service | jellyfin.service ✓ |

---

## Storage Locations
```
Config:  ~/containers/config/jellyfin
Cache:   /mnt/btrfs-pool/subvol6-tmp/jellyfin-cache
Media:   /mnt/btrfs-pool/subvol4-multimedia
Music:   /mnt/btrfs-pool/subvol5-music
```

---

## Common Fixes

**Service won't start:**
```bash
systemctl --user restart jellyfin.service
journalctl --user -u jellyfin.service -n 50
```

**Can't access from network:**
```bash
sudo firewall-cmd --list-ports | grep 8096
nslookup jellyfin.lokal
```

**Clean up space:**
```bash
~/containers/scripts/jellyfin-manage.sh clean-cache
~/containers/scripts/jellyfin-manage.sh clean-transcodes
```

---

**Last Updated:** $(date +"%Y-%m-%d")

<!-- AUTO-SECTION:AUTO-QUICK:BEGIN -->
## Quick Services
  - traefik (docker.io/library/traefik:v3.2) → Ports: 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:8080->8080/tcp
  - jellyfin (docker.io/jellyfin/jellyfin:latest) → Ports: 0.0.0.0:8096->8096/tcp, 0.0.0.0:7359->7359/udp
  - authelia-redis (docker.io/library/redis:7-alpine) → Ports: 6379/tcp
  - authelia (docker.io/authelia/authelia:latest) → Ports: 9091/tcp

## URLs
  - Traefik:  http://traefik.patriark.lokal
  - Authelia: https://auth.patriark.lokal (after TLS)
  - Jellyfin: https://jellyfin.patriark.lokal (after TLS)
  - Nextcloud: https://nextcloud.patriark.lokal (planned)

## Useful commands
  - Traefik logs: podman logs traefik --tail=100
  - Authelia logs: podman logs authelia --tail=100
  - Check ports: ss -tulnp | grep -E ":80 |:443 |:8096 |:9091 |:8080 "
<!-- AUTO-SECTION:AUTO-QUICK:END -->
