# Monitoring Stack Deployment Summary

**Date:** 2025-11-06
**Duration:** ~4 hours
**Status:** ✅ Complete and Operational

---

## What Was Deployed

### Core Components
- **Grafana 11.3.1** - Visualization platform (https://grafana.patriark.org)
- **Prometheus 2.55.1** - Metrics database with 15-day retention
- **Loki 3.2.1** - Log aggregation with 7-day retention
- **Promtail 3.2.1** - Log collector
- **Node Exporter 1.8.2** - System metrics exporter

### Supporting Infrastructure
- **journal-export.service** - Bridges systemd journal to Promtail (workaround for SELinux)
- **monitoring.network** - Isolated Podman network (10.89.4.0/24)
- Traefik routing for all services with TinyAuth authentication
- Storage moved to BTRFS pool to preserve system SSD space

---

## Key Metrics

### Current Status
```
Service          Status    Uptime      Storage
─────────────────────────────────────────────────
grafana          healthy   10 hours    120 MB
prometheus       healthy   10 hours     36 MB (BTRFS)
loki             healthy   10 hours    8.7 MB (BTRFS)
promtail         healthy   ~1 hour     minimal
node_exporter    healthy   10 hours    minimal
```

### Data Ingestion
- **Prometheus:** Scraping 3 targets every 15 seconds
- **Loki:** Ingested 39,608 log lines (8.06 MB) in first hour
- **Streams:** 26 unique log streams identified

---

## Technical Challenges Overcome

### 1. Traefik Network Connectivity Issue
**Problem:** Traefik couldn't reach TinyAuth, dashboard returned 404
**Root Cause:** Traefik not on `systemd-auth_services` network
**Solution:** Added second network to traefik.container
**Location:** traefik.container:4

### 2. Grafana Permission Denied
**Problem:** Container couldn't write to `/var/lib/grafana`
**Root Cause:** UID mismatch (Grafana runs as UID 472)
**Solution:** `podman unshare chown -R 472:472 ~/containers/data/grafana`

### 3. System Disk Space Exhaustion Risk
**Problem:** Only 10GB free on 128GB system SSD
**Solution:** Moved Prometheus and Loki data to BTRFS pool with NOCOW attribute
**Commands:**
```bash
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/prometheus
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/loki
```

### 4. Loki Compactor Configuration Error
**Problem:** `compactor.delete-request-store should be configured when retention is enabled`
**Solution:** Added `delete_request_store: filesystem` to loki-config.yml
**Location:** loki-config.yml:57

### 5. Grafana Alloy Journal Access Failure
**Problem:** Rootless containers cannot access `/var/log/journal/` due to SELinux
**Attempted:** GroupAdd=190, volume labels `:z`, various mount paths
**Result:** All failed with `lsetxattr: operation not permitted`
**Root Cause:** SELinux prevents rootless containers from relabeling system directories

### 6. Promtail Configuration Syntax Error
**Problem:** `field json not found in type scrapeconfig.plain`
**Root Cause:** Used invalid `json:` top-level key instead of `static_configs:`
**Solution:** Corrected to Promtail static_configs format with `__path__` label

### 7. Final Solution: Journal Export Bridge
**Architecture:**
```
systemd journal → journalctl --user -f → journal.log → Promtail → Loki
```

**Trade-offs:**
- ✅ Works within rootless/SELinux constraints
- ✅ No privileged containers required
- ⚠️ Only captures user journal (containers), not system journal
- ⚠️ File requires rotation policy (grows unbounded)
- ⚠️ Additional disk I/O overhead

---

## Critical Actions Required

### Immediate (This Week)
1. **Implement log rotation for journal-export file**
   - Current: 26 MB in 10 hours = 62 MB/day
   - 30-day projection: 1.86 GB (18% of remaining system SSD space)
   - See: monitoring-stack-guide.md § "Optimization Opportunities #2"

2. **Backup Grafana configuration to git**
   - Dashboards at: `~/containers/config/grafana/provisioning/dashboards/`
   - Command: `git add ~/containers/config/grafana && git commit`

3. **Add IP whitelisting to Prometheus/Loki APIs**
   - Currently exposed via Traefik with only TinyAuth auth
   - Recommendation: Restrict to LAN only
   - See: monitoring-stack-guide.md § "Security Hardening #1"

### Short-Term (Next 2 Weeks)
1. Deploy cAdvisor for per-container metrics
2. Enable Traefik metrics endpoint
3. Create service health dashboard
4. Implement Grafana audit logging

---

## Documentation

**Comprehensive Guide:** `docs/monitoring-stack-guide.md` (16,000+ words)

**Sections Include:**
- Architecture and data flow diagrams
- Component configuration details
- Getting started with Grafana/Prometheus/Loki
- Effective usage patterns and query examples
- Critical analysis of architectural weaknesses
- Optimization opportunities (performance, resource, functional)
- Security hardening recommendations
- Storage policy review and retention recommendations
- Using monitoring data to improve homelab design

---

## Files Modified/Created

### Quadlet Files Created
```
~/.config/containers/systemd/
├── monitoring.network
├── grafana.container
├── prometheus.container
├── loki.container
├── promtail.container
└── node_exporter.container
```

### User Services Created
```
~/.config/systemd/user/
└── journal-export.service
```

### Configuration Files
```
~/containers/config/
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml
│   │   ├── datasources/loki.yml
│   │   └── dashboards/dashboards.yml
│   └── dashboards/node-exporter-full.json
├── prometheus/
│   └── prometheus.yml
├── loki/
│   └── loki-config.yml
└── promtail/
    └── promtail-config.yml
```

### Traefik Integration
```
~/containers/config/traefik/dynamic/
└── routers.yml (modified - added grafana-secure, prometheus-secure, loki-secure)
```

### Storage Directories
```
~/containers/data/
├── grafana/          (system SSD)
├── promtail/         (system SSD)
└── journal-export/   (system SSD - ⚠️ needs rotation)

/mnt/btrfs-pool/subvol7-containers/
├── prometheus/       (NOCOW enabled)
└── loki/            (NOCOW enabled)
```

---

## Lessons Learned

### What Worked Well
- **BTRFS storage migration** prevented system SSD exhaustion
- **NOCOW attribute** important for database performance on BTRFS
- **Network segmentation** cleanly separates public/internal traffic
- **TinyAuth integration** provides consistent auth across all services
- **Grafana provisioning** enables infrastructure-as-code for datasources

### What Didn't Work
- **Alloy journal source** incompatible with rootless + SELinux
- **Direct journal volume mounts** blocked by SELinux restrictions
- **GroupAdd for systemd-journal** insufficient for container access
- **SELinux relabeling (`:z`)** prohibited on system directories

### Design Decisions Made
1. **User journal only** - Acceptable trade-off for rootless security
2. **File-based log bridge** - Pragmatic workaround, requires maintenance
3. **15d/7d retention** - Conservative starting point, can extend later
4. **No Alertmanager yet** - Prioritize observability first, alerting second
5. **BTRFS pool storage** - Leverage abundant space, isolate from system

---

## Next Steps

### Monitoring Maturity Roadmap

**Phase 1: Foundation (Complete ✅)**
- Deploy core stack (Grafana, Prometheus, Loki)
- Collect basic metrics and logs
- Authenticate and expose via Traefik

**Phase 2: Enrichment (Current)**
- Add per-container metrics (cAdvisor)
- Enable application metrics (Traefik, Jellyfin)
- Create service-specific dashboards
- Implement log rotation

**Phase 3: Intelligence (Future)**
- Deploy Alertmanager with notification channels
- Create alert rules for critical conditions
- Implement anomaly detection queries
- Build capacity planning dashboards

**Phase 4: Optimization (Future)**
- Evaluate system-mode Promtail for full journal access
- Consider remote storage for long-term retention
- Implement mTLS between components
- Add distributed tracing (Tempo)

---

## References

- Full Documentation: `docs/monitoring-stack-guide.md`
- Configuration Reference: `docs/00-foundation/20251025-configuration-design-quick-reference.md`
- Storage Architecture: `docs/99-reports/20251025-storage-architecture-authoritative-rev2.md`
- Grafana Docs: https://grafana.com/docs/grafana/latest/
- Prometheus Docs: https://prometheus.io/docs/
- Loki Docs: https://grafana.com/docs/loki/latest/

---

**Deployment Engineer:** Claude Code
**Project Owner:** patriark
**Sign-off:** Monitoring stack operational and ready for production use with noted action items.
