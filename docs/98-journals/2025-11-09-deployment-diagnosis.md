# Phase 1+ Deployment Diagnosis

**Date:** 2025-11-09
**Status:** Investigating deployment issues after Phase 1+ quadlet optimizations

## Summary

After deploying Phase 1+ improvements (health checks + resource limits + restart policy fixes), we encountered:

1. ✅ **immich-ml "starting"** - Expected behavior (10-minute startup grace period)
2. ⚠️ **alert-discord-relay unhealthy** - Pre-existing issue now detected by new health check
3. ❌ **Snapshot script crashed** - JSON parse error during health check validation

## Diagnostic Steps (Run on fedora-htpc)

### 1. Check Current Service Status

```bash
# Check all service health status
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Check immich-ml specifically (should be healthy by now, >10 min since restart)
podman healthcheck run immich-ml
podman logs immich-ml --tail 50

# Check alert-discord-relay (expected to be unhealthy)
podman healthcheck run alert-discord-relay
podman logs alert-discord-relay --tail 50
```

### 2. Diagnose alert-discord-relay Issue

**Expected Issue:** Service not listening on port 9095

```bash
# Check if the service is running
systemctl --user status alert-discord-relay.service

# Check what ports it's actually listening on
podman exec alert-discord-relay netstat -tlnp 2>/dev/null || \
podman exec alert-discord-relay ss -tlnp 2>/dev/null

# Test the health check manually
podman exec alert-discord-relay wget --no-verbose --tries=1 --spider http://localhost:9095/ || echo "Health check failed"

# Check if the container has the required binary
podman exec alert-discord-relay which wget

# Check environment variables (might be missing DISCORD_WEBHOOK_URL)
podman exec alert-discord-relay env | grep -i discord
```

**Likely Root Cause:** The alert-discord-relay might:
- Not be starting properly due to missing/invalid Discord webhook URL secret
- Be listening on a different port
- Have crashed on startup

### 3. Fix alert-discord-relay

**Option A: Check Podman Secret Exists**

```bash
# List podman secrets
podman secret ls

# Verify discord_webhook_url secret exists
podman secret inspect discord_webhook_url

# If missing, create it:
# echo "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL" | podman secret create discord_webhook_url -
```

**Option B: Check Container Logs for Startup Errors**

```bash
# Full logs since start
podman logs alert-discord-relay

# If there are errors, the service might need to be rebuilt or reconfigured
```

### 4. Apply Missing MemoryMax Fix

The git repository has been updated with MemoryMax=128M for alert-discord-relay. Apply it:

```bash
cd ~/containers

# Pull latest changes
git pull origin claude/improve-homelab-snapshot-script-011CUxXJaHNGcWQyfgK7PK3C

# Copy updated quadlet
cp quadlets/alert-discord-relay.container ~/.config/containers/systemd/

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart alert-discord-relay.service

# Wait 10 seconds then check health
sleep 10
podman healthcheck run alert-discord-relay
```

### 5. Re-run Snapshot Script

Once services are stable:

```bash
cd ~/containers
./scripts/homelab-snapshot.sh

# Verify JSON is valid
jq . docs/99-reports/snapshot-*.json | head -20

# Check health statistics
jq '.health_check_analysis' docs/99-reports/snapshot-*.json | tail -20
```

## Expected Results

After fixes:

- **immich-ml**: `"health": "healthy"` (if >10 min since start)
- **alert-discord-relay**: `"health": "healthy"` (if Discord webhook secret is valid) OR still unhealthy if configuration issue
- **Snapshot script**: Should complete successfully with valid JSON
- **Health check coverage**: 93% (15/16) - tinyauth still has no health check
- **Resource limits coverage**: 87% (14/16) - tinyauth and cadvisor missing limits

## Analysis

### Why alert-discord-relay is Unhealthy

Before Phase 1, alert-discord-relay had NO health check, so we didn't know it had issues. We added:

```ini
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:9095/ || exit 1
```

This health check is now **detecting a pre-existing problem**. The service is either:
1. Not starting properly (missing secret)
2. Crashed on startup
3. Listening on wrong port

This is a **positive outcome** - health checks are doing their job by revealing hidden issues!

### Why immich-ml was "starting"

immich-ml has a 10-minute startup grace period (`HealthStartPeriod=600s`) because it needs to:
1. Download machine learning models on first start
2. Initialize the ML engine
3. Load models into memory

The snapshot was taken only 6 minutes after restart, so "starting" status was expected and correct.

### Why Snapshot Script Crashed

The script uses `podman exec` with timeouts to validate health check binaries exist in containers:

```bash
timeout --kill-after=1s 2s podman exec "$container_name" which "$cmd_binary"
```

If a container is unresponsive or starting up, this could cause issues. The script successfully validated 5 services:
- cadvisor ✅
- grafana ✅
- jellyfin ✅
- postgresql-immich ✅
- redis-immich ✅

Then crashed, likely when trying to validate the next service (possibly immich-ml while it was still starting).

**Recommendation:** Re-run snapshot script after all services are fully healthy (wait 10+ minutes after deployment).

## Next Steps

1. ✅ Add MemoryMax to alert-discord-relay (committed to git)
2. ⏳ Run diagnostics on fedora-htpc (user action required)
3. ⏳ Fix alert-discord-relay if secret is missing
4. ⏳ Re-run snapshot script when services stable
5. ⏳ Commit successful snapshot and create pull request

## Files Modified

- `quadlets/alert-discord-relay.container` - Added MemoryMax=128M
- `docs/99-reports/2025-11-09-deployment-diagnosis.md` - This file

## Reference

- Previous successful snapshot: `docs/99-reports/snapshot-20251109-195148.json`
- Incomplete snapshot: `docs/99-reports/snapshot-20251109-213857.json`
- Phase 1+ changes: Commit `5fe19dd`
