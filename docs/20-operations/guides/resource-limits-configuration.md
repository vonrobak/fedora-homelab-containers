# Resource Limits Configuration Guide

**Date:** 2025-11-09
**Status:** Ready to implement
**Priority:** HIGH - Prevents resource exhaustion

---

## Overview

Current resource limit coverage: **5% (1/17 services)**
Target coverage: **41% (7/17 services)** - Critical services protected

This guide provides ready-to-use configurations to add resource limits to the 6 most critical services.

---

## Why Resource Limits Matter

**Without limits:**
- Any service can consume all system memory → OOM killer → system instability
- Database queries can balloon memory usage
- ML model loading can exhaust RAM
- DDoS attacks can overwhelm Traefik

**With limits:**
- Systemd enforces hard caps
- Services get killed if they exceed limits (not the whole system)
- Predictable behavior under load

---

## Implementation Instructions

For each service below, add the `MemoryMax=` line to the `[Service]` section of the quadlet file.

### File Locations

All quadlet files are in: `~/.config/containers/systemd/`

### Steps to Apply

1. Edit the `.container` file
2. Add `MemoryMax=` line under the `[Service]` section
3. Reload systemd: `systemctl --user daemon-reload`
4. Restart the service: `systemctl --user restart <service>.service`

---

## Critical Service Configurations

### 1. Prometheus (Time-Series Database)

**File:** `~/.config/containers/systemd/prometheus.container`

**Rationale:** Prometheus memory grows with metrics cardinality. 2G allows for 15-day retention with current scrape config.

**Add to [Service] section:**
```ini
MemoryMax=2G
```

**Why 2G:**
- Current estimated usage: ~80-150MB
- Growth allowance for 15-day retention
- Prevents runaway queries from exhausting system

---

### 2. Grafana (Visualization)

**File:** `~/.config/containers/systemd/grafana.container`

**Rationale:** Grafana can spike when rendering complex dashboards with lots of data points.

**Add to [Service] section:**
```ini
MemoryMax=1G
```

**Why 1G:**
- Base usage: ~120MB
- Dashboard rendering spikes: up to 500MB
- Headroom for multiple concurrent users

---

### 3. Loki (Log Aggregation)

**File:** `~/.config/containers/systemd/loki.container`

**Rationale:** Loki memory grows with ingestion rate and retention. 7-day retention with current log volume.

**Add to [Service] section:**
```ini
MemoryMax=1G
```

**Why 1G:**
- Base usage: ~60MB
- Index caching and chunk buffering
- 7-day retention safety margin

---

### 4. PostgreSQL (Immich Database)

**File:** `~/.config/containers/systemd/postgresql-immich.container`

**Rationale:** PostgreSQL buffers data in shared_buffers. Photo metadata can grow significantly.

**Add to [Service] section:**
```ini
MemoryMax=2G
```

**Why 2G:**
- Recommended: 25% of available RAM for dedicated DB
- Immich photo metadata growth (thumbnails, ML embeddings)
- Query execution buffers

**Optional PostgreSQL tuning** (add to config file):
```
shared_buffers = 512MB
effective_cache_size = 1536MB
work_mem = 16MB
```

---

### 5. Immich Server (Photo Application)

**File:** `~/.config/containers/systemd/immich-server.container`

**Rationale:** Photo uploads, thumbnail generation, and metadata extraction are memory-intensive.

**Add to [Service] section:**
```ini
MemoryMax=3G
```

**Why 3G:**
- Photo upload buffering
- Thumbnail generation (multiple sizes)
- Video transcoding spikes
- ML inference requests

---

### 6. Immich ML (Machine Learning)

**File:** `~/.config/containers/systemd/immich-ml.container`

**Rationale:** ML models (CLIP, face recognition) require significant memory. Currently unhealthy - may be hitting memory limits.

**Add to [Service] section:**
```ini
MemoryMax=4G
```

**Why 4G:**
- CLIP model: ~1.5GB
- Face recognition model: ~800MB
- Inference working memory
- Model cache

**Note:** This may help resolve the current unhealthy status!

---

## Jellyfin (Already Configured) ✅

**File:** `~/.config/containers/systemd/jellyfin.container`

**Current config:**
```ini
MemoryMax=4G
Nice=-5
```

**Status:** Good! Jellyfin already has proper limits.

---

## Application Workflow

### Quick Apply Script

Save this as `~/containers/scripts/apply-resource-limits.sh`:

```bash
#!/bin/bash

# Apply resource limits to critical services
# Usage: ./apply-resource-limits.sh

QUADLET_DIR="${HOME}/.config/containers/systemd"

services=(
    "prometheus:2G"
    "grafana:1G"
    "loki:1G"
    "postgresql-immich:2G"
    "immich-server:3G"
    "immich-ml:4G"
)

for entry in "${services[@]}"; do
    service="${entry%:*}"
    limit="${entry#*:}"
    quadlet="${QUADLET_DIR}/${service}.container"

    if [ ! -f "$quadlet" ]; then
        echo "⚠ Skipping $service - quadlet not found"
        continue
    fi

    # Check if MemoryMax already exists
    if grep -q '^MemoryMax=' "$quadlet"; then
        echo "✓ $service already has MemoryMax configured"
        continue
    fi

    # Add MemoryMax to [Service] section
    echo "▶ Adding MemoryMax=$limit to $service"
    sed -i '/^\[Service\]/a MemoryMax='"$limit" "$quadlet"
done

echo ""
echo "✓ Resource limits applied!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff ~/.config/containers/systemd/"
echo "  2. Reload systemd: systemctl --user daemon-reload"
echo "  3. Restart services: systemctl --user restart <service>.service"
echo ""
echo "Or restart all at once:"
echo "  systemctl --user restart prometheus grafana loki postgresql-immich immich-server immich-ml"
```

### Manual Application

If you prefer manual edits:

1. **Edit each quadlet file:**
   ```bash
   nano ~/.config/containers/systemd/prometheus.container
   ```

2. **Find the [Service] section:**
   ```ini
   [Container]
   Image=quay.io/prometheus/prometheus:latest
   ...

   [Service]
   Restart=always
   ```

3. **Add MemoryMax line:**
   ```ini
   [Service]
   MemoryMax=2G
   Restart=always
   ```

4. **Save and repeat** for the other 5 services.

5. **Apply changes:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart prometheus.service
   # Repeat for other services
   ```

---

## Verification

After applying limits, verify they're active:

```bash
# Check individual service
systemctl --user show prometheus.service | grep MemoryMax

# Check all services
for svc in prometheus grafana loki postgresql-immich immich-server immich-ml; do
    echo "=== $svc ==="
    systemctl --user show ${svc}.service | grep MemoryMax
done
```

Expected output:
```
=== prometheus ===
MemoryMax=2147483648

=== grafana ===
MemoryMax=1073741824
...
```

---

## Monitoring Resource Usage

After applying limits, monitor usage to ensure limits are appropriate:

```bash
# Real-time resource usage
podman stats

# Memory usage for specific service
podman stats prometheus --no-stream

# Check if service hit limit (OOMKill)
systemctl --user status prometheus.service | grep -i oom
```

### Adjust Limits If Needed

If a service is frequently hitting its limit (getting OOMKilled):

1. Check logs: `journalctl --user -u <service>.service | grep -i oom`
2. Review actual usage: `podman stats <service> --no-stream`
3. Increase limit by 50-100%
4. Re-run snapshot script to update resource_limits_analysis

---

## Expected Impact

**Before:**
- Coverage: 5% (1/17 services)
- Risk: HIGH - any service can exhaust system memory

**After:**
- Coverage: 41% (7/17 services)
- Risk: MEDIUM-LOW - critical services protected
- System stability: Greatly improved

**Next snapshot will show:**
```json
"resource_limits_analysis": {
  "total_services": 17,
  "with_limits": 7,
  "without_limits": 10,
  "coverage_percent": 41
}
```

---

## Future Enhancements

### Phase 2 (Optional):

Add limits to remaining services:
- `traefik`: MemoryMax=512M
- `crowdsec`: MemoryMax=256M
- `tinyauth`: MemoryMax=256M
- `cadvisor`: MemoryMax=512M
- `alertmanager`: MemoryMax=512M
- Others: MemoryMax=256M (conservative)

### Phase 3 (Advanced):

Add CPU limits:
```ini
CPUQuota=200%  # Limit to 2 CPU cores max
```

---

## Troubleshooting

### Service Won't Start After Adding Limit

**Symptom:** `systemctl --user start <service>.service` fails

**Check:**
```bash
journalctl --user -u <service>.service -n 50
```

**Possible causes:**
- Limit too low for service requirements
- Syntax error in quadlet file

**Solution:** Increase limit or fix syntax error

### Service Gets OOMKilled Frequently

**Symptom:** Service restarts often, `journalctl` shows OOM

**Solution:**
1. Increase MemoryMax by 50-100%
2. Investigate why service is using so much memory
3. Consider optimizing service configuration

### How to Remove Limits

If you need to remove a limit:

```bash
# Edit quadlet file
nano ~/.config/containers/systemd/prometheus.container

# Remove or comment out MemoryMax line
# MemoryMax=2G

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart prometheus.service
```

---

## References

- [systemd.resource-control(5)](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- Project ADR: ADR-002 (Systemd Quadlets)

---

**Created by:** Claude Code (homelab-snapshot.sh intelligence analysis)
**Based on:** snapshot-20251109-172016.json analysis
