# Homelab Infrastructure Documentation

**Last Updated:** $(date +"%Y-%m-%d")

---

## Quick Access

### Services
- **Jellyfin Media Server:** http://jellyfin.lokal:8096
  - Status: ✓ Running
  - Manage: `~/containers/scripts/jellyfin-manage.sh`

### Documentation
- [Week 1 Overview](#week-1-foundation)
- [Management Scripts](#management-scripts-reference)
- [Troubleshooting Guide](#troubleshooting)

---

## Week 1: Foundation (Complete ✓)

### Day 1: Rootless Containers & DNS
**Documentation:** [day01-learnings.md](day01-learnings.md)

**What was built:**
- Rootless Podman environment
- First test container (whoami)
- Firewall configuration (homelab-containers service)
- DNS resolution via Pi-hole

**Key concepts:** User namespaces, rootless security, firewall rules

---

### Day 2: Networking & Pi-hole Integration
**Documentation:** [day02-networking.md](day02-networking.md)

**What was built:**
- Custom networks (web_services, media_services)
- Container-to-container DNS resolution
- Pi-hole local DNS integration (.lokal domain)
- Network topology scripts

**Key concepts:** Bridge networks, DNS hierarchy (aardvark → host → Pi-hole), service discovery

---

### Day 3: Pods & Multi-Container Applications
**Documentation:** [day03-pods.md](day03-pods.md)

**What was built:**
- Pod architecture (webapp demo)
- Multi-tier application (demo-stack: Flask + PostgreSQL + Redis)
- Shared network namespace
- Pod vs containers decision framework

**Key concepts:** Localhost communication, shared namespaces, sidecar pattern, service coupling

---

### Day 4: Jellyfin Production Deployment
**Documentation:** [day04-jellyfin-final.md](day04-jellyfin-final.md) ⭐

**What was built:**
- Production Jellyfin media server
- Hardware transcoding (AMD GPU)
- Tiered storage architecture
- Systemd service integration
- Management and monitoring scripts
- Zero-downtime service migration

**Key concepts:** Stateful services, hardware passthrough, storage tiering, service reliability, process supervision

**Status:** ✓ Complete and running in production

---

## Management Scripts Reference

### Location
All scripts: `~/containers/scripts/`

### Jellyfin Management

#### Status Check
```bash
~/containers/scripts/jellyfin-status.sh
```
Shows: Service status, resource usage, storage, health check, GPU status

#### Service Management
```bash
~/containers/scripts/jellyfin-manage.sh {command}

Commands:
  status    - Detailed status report
  start     - Start service
  stop      - Stop service
  restart   - Restart service
  logs      - Show recent logs
  follow    - Follow logs live
  clean-cache - Clean cache directory
  clean-transcodes - Clean transcodes
  url       - Show access URLs
```

### Network Utilities

#### Network Topology
```bash
~/containers/scripts/show-network-topology.sh
```
Shows: All networks, containers per network, DNS health

#### Pod Status
```bash
~/containers/scripts/show-pod-status.sh
```
Shows: All pods, containers in pods, published ports

---

## Infrastructure Components

### Networks
| Network | Subnet | Purpose | DNS |
|---------|--------|---------|-----|
| podman | 10.88.0.0/16 | Default | ✓ |
| web_services | 10.89.0.0/24 | Web apps | ✓ |
| media_services | 10.89.1.0/24 | Media services | ✓ |

### Services (Production)
| Service | Status | Network | Ports | Auto-Start |
|---------|--------|---------|-------|------------|
| Jellyfin | ✓ Running | media_services | 8096, 7359 | ✓ Enabled |

### DNS Records (Pi-hole @ 192.168.1.69)
**Homelab Services (.lokal domain):**
- jellyfin.lokal → 192.168.1.70
- media.lokal → 192.168.1.70
- fedora-htpc.lokal → 192.168.1.70
- homelab.lokal → 192.168.1.70
- patriark.lokal → 192.168.1.70
- *(+ 20+ other entries for network devices)*

---

## Storage Architecture

### System Drive (NVMe SSD - 128GB)
```
/home/patriark/containers/
├── config/          # Service configurations (fast access needed)
│   └── jellyfin/   # 200-500 MB
├── docs/           # This documentation
└── scripts/        # Management automation
```

### Data Pool (BTRFS - 10TB)
```
/mnt/btrfs-pool/
├── subvol1-docs/
├── subvol2-pics/
├── subvol3-opptak/
├── subvol4-multimedia/     # Jellyfin media (mounted read-only)
├── subvol5-music/          # Jellyfin music (mounted read-only)
└── subvol6-tmp/
    ├── jellyfin-cache/     # 1-5 GB
    └── jellyfin-transcodes/ # 0-20 GB (varies)
```

**Backup Strategy:**
- Config directories → Restic (encrypted, cloud)
- Media files → BTRFS snapshots (external drive)
- Cache/temp → Not backed up (regenerates)

---

## Systems Design Concepts Mastered

### Week 1
- ✅ Rootless container security
- ✅ Network namespaces and isolation
- ✅ Service discovery via DNS
- ✅ Pod architecture (shared namespaces)
- ✅ Stateful service management
- ✅ Hardware passthrough (GPU)
- ✅ Storage tiering strategies
- ✅ Process supervision with systemd
- ✅ Service reliability and fault tolerance
- ✅ Observability (logs, metrics, health checks)

### Coming in Week 2
- Reverse proxy (Caddy with automatic SSL)
- Centralized authentication (Authelia + YubiKey)
- HTTPS everywhere
- Network segmentation (VLANs)

---

## Troubleshooting

### Quick Diagnostics

**Is Jellyfin running?**
```bash
~/containers/scripts/jellyfin-manage.sh status
```

**Can't access from network?**
```bash
# Check DNS
nslookup jellyfin.lokal

# Check firewall
sudo firewall-cmd --list-ports | grep 8096

# Check service
systemctl --user status jellyfin.service
```

**High CPU usage?**
```bash
# Check what Jellyfin is doing
podman logs jellyfin --tail 50

# Check if GPU transcoding is enabled
# Dashboard → Playback → Hardware Acceleration
```

**Need to restart something?**
```bash
~/containers/scripts/jellyfin-manage.sh restart
```

### Common Issues

See detailed troubleshooting in:
- [day04-jellyfin-final.md](day04-jellyfin-final.md#troubleshooting)

---

## Next Steps: Week 2 Preview

### Day 5 (Next): Systemd Deep Dive
- Timers for scheduled tasks
- Advanced service dependencies
- Resource limits and cgroups
- Creating custom services
- Systemd best practices

### Week 2: Secure Access & Monitoring
- Caddy reverse proxy with automatic SSL
- Authelia SSO with YubiKey 2FA
- Prometheus + Grafana monitoring
- Loki log aggregation
- Network segmentation with VLANs

---

## Resources

### External Documentation
- [Podman Documentation](https://docs.podman.io/)
- [Jellyfin Documentation](https://jellyfin.org/docs/)
- [systemd Documentation](https://www.freedesktop.org/wiki/Software/systemd/)
- [Pi-hole Documentation](https://docs.pi-hole.net/)

### Community
- r/selfhosted
- r/homelab
- r/jellyfin
- Podman GitHub Discussions

---

**Infrastructure Status:** ✓ Operational
**Documentation Status:** ✓ Up to date
**Next Session:** Day 5 - Systemd Deep Dive

### Day 6: Traefik Reverse Proxy & Quadlets ✓
**Documentation:** [day06-complete.md](day06-complete.md)

**What was built:**
- Traefik v3.2 reverse proxy (Quadlet-based)
- Systemd-managed container networks
- HTTP → HTTPS automatic redirect
- Self-signed TLS certificates for *.lokal
- Jellyfin integration with Traefik
- Complete infrastructure as code migration

**Key concepts:** Reverse proxy, TLS termination, Quadlets, infrastructure as code, service dependencies, declarative configuration, debugging methodology

**Issues resolved:** Privileged port binding, network dependencies, Traefik v3 syntax, middleware dependencies

**Status:** ✓ Production ready, fully documented

---


### Day 7: Authelia SSO with TOTP (YubiKeys) ✓
**Documentation:** [day07-authelia-final.md](day07-authelia-final.md)

**What was built:**
- Authelia v4.39 SSO server with forward authentication
- Redis session storage with authentication
- TOTP 2FA with 3 YubiKeys + mobile app
- Podman secrets for production-grade secret management
- Traefik forward auth middleware integration
- Complete authentication infrastructure

**Key challenges resolved:**
- Redis password authentication (4+ hours troubleshooting)
- Podman secrets configuration
- WebAuthn blocked by self-signed certificates (deferred to Week 2)
- Identity verification without email
- Authelia UI login loop bug (documented workaround)

**Key learnings:**
- Forward authentication architecture
- TOTP vs WebAuthn trade-offs
- When to accept pragmatic compromises
- Production-ready ≠ perfect
- Systematic troubleshooting methodology

**Status:** ✅ Production ready with TOTP, WebAuthn deferred until valid TLS

**Known issues:**
- UI login loop requiring browser restart
- WebAuthn requires Let's Encrypt certificates
- Redis password hardcoded in config file

---

