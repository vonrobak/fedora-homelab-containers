# Immich ML Troubleshooting Guide

**Date:** 2025-11-09
**Status:** Active Investigation
**Service:** immich-ml (Machine Learning)
**Current State:** Running but UNHEALTHY

---

## Current Status

From snapshot-20251109-172016.json:

```json
"immich-ml": {
  "status": "running",
  "health": "unhealthy",
  "started": "2025-11-08 15:59:41",
  "networks": ["systemd-photos"],
  "volumes": ["/mnt/btrfs-pool/subvol7-containers/immich-ml-cache:/cache"]
}
```

**Uptime:** ~1 day (started Nov 8, 15:59)
**Health Status:** UNHEALTHY ⚠️
**Impact:** Photo ML features may not work (face recognition, object detection, smart search)

---

## Investigation Steps

### Step 1: Check Service Logs

```bash
# Recent logs
podman logs immich-ml --tail 100

# Follow live logs
podman logs immich-ml -f

# Systemd service logs
journalctl --user -u immich-ml.service -n 100

# Look for errors
podman logs immich-ml 2>&1 | grep -i error
podman logs immich-ml 2>&1 | grep -i warn
```

**Look for:**
- ML model download failures
- GPU detection issues
- Memory errors
- Network connectivity issues
- Python exceptions

---

### Step 2: Check Health Check Details

```bash
# Detailed health status
podman inspect immich-ml --format '{{json .State.Health}}' | jq .

# Last health check log
podman inspect immich-ml --format '{{range .State.Health.Log}}{{.Output}}{{end}}'
```

**Health check configuration:**
```bash
# View health check command
podman inspect immich-ml --format '{{.Config.Healthcheck}}'
```

---

### Step 3: Check Resource Usage

```bash
# Current memory and CPU usage
podman stats immich-ml --no-stream

# Check if OOMKilled
systemctl --user status immich-ml.service | grep -i oom
journalctl --user -u immich-ml.service | grep -i oom
```

**Expected:** ML service should use 1-2GB under normal load (models in memory)

**If using >3GB:** May need memory limit increase or model optimization

---

### Step 4: Verify ML Cache Volume

```bash
# Check cache directory
ls -lh /mnt/btrfs-pool/subvol7-containers/immich-ml-cache/

# Check cache size
du -sh /mnt/btrfs-pool/subvol7-containers/immich-ml-cache/

# Check disk space
df -h /mnt/btrfs-pool/
```

**Expected cache contents:**
- Model files (~2-3GB total)
- `clip/` directory (CLIP model)
- `facial-recognition/` directory (face detection)

**If empty or incomplete:** Models may still be downloading

---

### Step 5: Test ML Endpoint Directly

```bash
# Check if ML service is responding
# (From another container or host on systemd-photos network)

# Get the ML service IP from snapshot
# immich-ml:10.89.5.6

# Test health endpoint
curl -v http://10.89.5.6:3003/ping

# Or from immich-server
podman exec immich-server curl -v http://immich-ml:3003/ping
```

**Expected:** `200 OK` or similar success response

---

## Common Issues & Solutions

### Issue 1: ML Models Still Downloading

**Symptom:** Health check fails, logs show "Downloading models..."

**Solution:** Wait for model downloads to complete (20GB, 30-60 min)

**Verify:**
```bash
# Watch cache directory grow
watch du -sh /mnt/btrfs-pool/subvol7-containers/immich-ml-cache/

# Check logs for download progress
podman logs immich-ml -f | grep -i download
```

**Resolution:** Patience. Models are large.

---

### Issue 2: Insufficient Memory

**Symptom:** Service crashes or gets OOMKilled, logs show memory errors

**Solution:** Add memory limit (currently no limit set!)

**Recommended limit:** MemoryMax=4G

**Apply:**
```bash
# Edit quadlet
nano ~/.config/containers/systemd/immich-ml.container

# Add to [Service] section
MemoryMax=4G

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart immich-ml.service
```

**Note:** See `docs/20-operations/guides/resource-limits-configuration.md` for details

---

### Issue 3: GPU Detection Failure

**Symptom:** Logs show "No GPU detected, using CPU"

**Context:** Your system has AMD GPU, Immich can use ROCm for acceleration

**Check:**
```bash
# Verify GPU visible to system
lspci | grep -i vga
lspci | grep -i amd

# Check if /dev/dri accessible
ls -l /dev/dri/

# Verify quadlet has device passthrough
grep -i device ~/.config/containers/systemd/immich-ml.container
```

**Expected in quadlet:**
```ini
Device=/dev/dri:/dev/dri
```

**If missing:** Add GPU device passthrough (see Immich deployment docs)

---

### Issue 4: Network Connectivity to immich-server

**Symptom:** ML service can't reach immich-server

**Check:**
```bash
# Verify both on systemd-photos network
podman network inspect systemd-photos | grep -A 5 immich

# Test connectivity from ML to server
podman exec immich-ml ping -c 3 immich-server
podman exec immich-ml curl -v http://immich-server:2283/api/server-info/ping
```

**Solution:** Ensure both services on same network (snapshot confirms they are)

---

### Issue 5: Health Check Misconfigured

**Symptom:** Service works but health check always fails

**Check quadlet health check:**
```bash
cat ~/.config/containers/systemd/immich-ml.container | grep -i health
```

**Proper health check format:**
```ini
HealthCmd=/bin/sh -c "wget --no-verbose --tries=1 --spider http://localhost:3003/ping || exit 1"
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
```

**Fix if misconfigured:** Update quadlet and restart

---

## Quick Diagnostic Commands

Run all these to gather comprehensive data:

```bash
#!/bin/bash
echo "=== Service Status ==="
systemctl --user status immich-ml.service

echo -e "\n=== Container State ==="
podman inspect immich-ml --format '{{.State.Status}} - {{.State.Health.Status}}'

echo -e "\n=== Last 20 Log Lines ==="
podman logs immich-ml --tail 20

echo -e "\n=== Resource Usage ==="
podman stats immich-ml --no-stream

echo -e "\n=== Cache Size ==="
du -sh /mnt/btrfs-pool/subvol7-containers/immich-ml-cache/

echo -e "\n=== Health Check Details ==="
podman inspect immich-ml --format '{{json .State.Health}}' | jq .

echo -e "\n=== Network Connectivity ==="
podman exec immich-ml ping -c 2 immich-server 2>&1 || echo "Ping failed"

echo -e "\n=== Disk Space ==="
df -h /mnt/btrfs-pool/
```

Save as `~/containers/scripts/diagnose-immich-ml.sh` and run.

---

## Resolution Checklist

Work through this checklist:

- [ ] Checked logs for errors
- [ ] Verified health check configuration
- [ ] Checked resource usage (memory/CPU)
- [ ] Verified ML cache directory exists and has space
- [ ] Confirmed models downloaded (cache size ~2-3GB)
- [ ] Tested network connectivity to immich-server
- [ ] Checked for OOMKill events
- [ ] Verified GPU device passthrough (if using)
- [ ] Added memory limit (MemoryMax=4G)
- [ ] Restarted service after configuration changes

---

## Most Likely Cause

Based on snapshot data and common Immich ML issues:

**Theory #1: Memory Limit Issue** ⭐⭐⭐
- immich-ml has **no memory limit** configured
- ML models require 1-2GB just to load
- May be hitting system OOM killer
- **Fix:** Add MemoryMax=4G to quadlet

**Theory #2: Models Still Downloading** ⭐⭐
- Service started ~1 day ago (Nov 8, 15:59)
- May still be downloading 20GB of ML models
- **Check:** Cache directory size and logs

**Theory #3: Health Check Timing** ⭐
- ML models take time to load on startup
- Health check may be timing out
- **Fix:** Increase HealthTimeout or HealthRetries

---

## Recommended Action Plan

1. **Check logs** for obvious errors:
   ```bash
   podman logs immich-ml --tail 50
   ```

2. **Add memory limit** (prevents OOMKill):
   ```bash
   # Edit quadlet
   nano ~/.config/containers/systemd/immich-ml.container

   # Add under [Service]
   MemoryMax=4G

   # Apply
   systemctl --user daemon-reload
   systemctl --user restart immich-ml.service
   ```

3. **Wait 5 minutes** for service to stabilize

4. **Check health status again**:
   ```bash
   podman inspect immich-ml --format '{{.State.Health.Status}}'
   ```

5. **If still unhealthy**, run full diagnostic script above

---

## Expected Behavior

**Healthy immich-ml:**
- Health status: "healthy"
- Memory usage: 1-2GB (models loaded)
- Cache directory: 2-3GB (models downloaded)
- Logs: "Model loaded successfully" or similar
- HTTP ping responds: `200 OK`

**Unhealthy but recoverable:**
- Status: "starting" or "unhealthy"
- Logs: "Downloading models..." or "Loading models..."
- Action: Wait for completion

**Genuinely broken:**
- Logs: Python exceptions, OOM errors, network failures
- Action: Investigate root cause from logs

---

## Impact Assessment

**If immich-ml is unhealthy:**
- ✅ **Photo uploads still work** - handled by immich-server
- ✅ **Photo browsing works** - gallery, albums, sharing
- ❌ **Face recognition disabled** - can't detect/group faces
- ❌ **Object detection disabled** - no automatic tagging
- ❌ **Smart search broken** - CLIP-based semantic search unavailable
- ❌ **Duplicate detection limited** - perceptual hashing only

**Priority:** Medium-High - Core features work, but "smart" features are offline

---

## References

- [Immich ML Documentation](https://immich.app/docs/features/ml-face-detection)
- [Immich GitHub Issues - ML troubleshooting](https://github.com/immich-app/immich/issues?q=is%3Aissue+ml)
- Project: `docs/10-services/decisions/2025-11-08-immich-deployment-architecture.md`
- Snapshot: `docs/99-reports/snapshot-20251109-172016.json`

---

**Next Steps:**
1. Apply resource limit (MemoryMax=4G)
2. Check logs for specific errors
3. Verify models downloaded completely
4. Report findings and update this doc

**Status after resolution:** Update this doc with root cause and solution
