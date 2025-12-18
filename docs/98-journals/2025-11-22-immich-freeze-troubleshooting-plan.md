# Immich Freeze Troubleshooting Plan

**Date:** 2025-11-22
**Issue:** Immich web interface loads but becomes unresponsive
**URL:** https://photos.patriark.org
**Symptoms:**
- Page loads initially
- UI becomes frozen/unresponsive
- Clickable elements don't respond to clicks
- Firefox reports high resource usage for the tab

**Hypothesis:** Frontend JavaScript issue, slow/hanging API responses, or resource exhaustion

---

## Troubleshooting Phases

This plan follows a systematic approach from service health → logs → API connectivity → resource limits → configuration.

### Phase 1: Service Health Check (5 min)

**Objective:** Verify all Immich containers are running and identify obvious issues.

```bash
# 1. Check all Immich-related containers
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep -i immich

# 2. Check systemd service status
systemctl --user status immich*.service

# 3. Quick resource snapshot
podman stats --no-stream | grep -i immich
```

**Expected Output:**
- All containers: `Up` state
- Services: `active (running)`
- Memory usage: <80% of limits

**Red Flags:**
- ❌ Containers in `Restarting` state
- ❌ Services in `failed` or `inactive` state
- ❌ Memory usage >90%

**Next Steps if Issues Found:**
- Container restarts → Check Phase 2 logs immediately
- Service failures → Check `journalctl --user -u <service> -n 50`
- High memory → Proceed to Phase 4

---

### Phase 2: Container Logs Analysis (10 min)

**Objective:** Identify errors in application logs that could cause frontend freeze.

```bash
# 4. Check immich-server logs (backend API)
podman logs --tail 100 immich-server

# 5. Check immich-web logs (frontend)
podman logs --tail 100 immich-web

# 6. Filter for errors in web logs
podman logs immich-web | grep -iE "error|warn|fail|exception"

# 7. Check immich-ml service (machine learning)
podman logs --tail 50 immich-ml

# 8. Check database connectivity
podman logs --tail 50 immich-postgres | grep -iE "error|connection|timeout"

# 9. Check Redis (session/cache)
podman logs --tail 50 immich-redis | grep -iE "error|warn"
```

**What to Look For:**

| Pattern | Meaning | Action |
|---------|---------|--------|
| `ECONNREFUSED` | Can't connect to dependency | Check Phase 7 (interconnectivity) |
| `Timeout` or `ETIMEDOUT` | Slow responses | Check Phase 3 (API) |
| `Out of memory` or `OOM` | Memory exhaustion | Check Phase 4 (limits) |
| `JavaScript error` | Frontend build issue | Check image version/rebuild |
| `500`, `502`, `504` | Backend errors | Check API health (Phase 3) |
| `Database connection failed` | PostgreSQL issue | Check postgres container |

**Common Patterns:**
```
✅ Good: "Server started on port 3001"
✅ Good: "Database connection established"
❌ Bad: "Error: Connection timeout after 30000ms"
❌ Bad: "TypeError: Cannot read property 'map' of undefined"
❌ Bad: "FATAL: remaining connection slots reserved"
```

---

### Phase 3: API Health Check (5 min)

**Objective:** Determine if backend API is responsive or hanging.

```bash
# 10. Find Immich server port (usually 2283 or 3001)
podman ps --format "{{.Names}}\t{{.Ports}}" | grep immich-server

# 11. Test API endpoint directly (bypass Traefik)
# Replace <PORT> with actual port from step 10
curl -v http://localhost:<PORT>/api/server-info/ping

# 12. Measure API response time
time curl -s http://localhost:<PORT>/api/server-info/version

# 13. Test API through Traefik
curl -v https://photos.patriark.org/api/server-info/ping

# 14. Check Traefik routing logs
podman logs traefik | grep immich | tail -30
```

**Response Time Benchmarks:**
- ✅ <2 seconds: Healthy
- ⚠️ 2-10 seconds: Degraded (check database)
- ❌ >10 seconds or timeout: Critical issue

**Traefik Issues:**
```bash
# Look for these in Traefik logs:
❌ "Gateway Timeout" → Backend not responding
❌ "Bad Gateway" → Backend unreachable
❌ "rate limit exceeded" → Too many requests
✅ "200 OK" → Working correctly
```

---

### Phase 4: Resource Limits Check (5 min)

**Objective:** Identify if containers are hitting memory/CPU limits.

```bash
# 15. Check memory limits in quadlet files
cat ~/.config/containers/systemd/immich*.container | grep -iE "memory|cpu"

# 16. Real-time resource monitoring
podman stats immich-server immich-web immich-ml immich-postgres immich-redis
# Let this run for 30 seconds, then refresh photos.patriark.org and observe

# 17. Check for OOM (Out of Memory) kills
journalctl --user --since "24 hours ago" | grep -iE "out of memory|oom|killed" | grep immich

# 18. Check disk I/O (if on BTRFS)
iostat -x 2 5
# Look for high %util on BTRFS devices during page load
```

**Memory Usage Guidelines:**

| Container | Normal | Warning | Critical |
|-----------|--------|---------|----------|
| immich-server | 200-500MB | 800MB | >1GB |
| immich-web | 100-200MB | 400MB | >512MB |
| immich-ml | 500MB-1GB | 1.5GB | >2GB |
| immich-postgres | 100-300MB | 600MB | >1GB |
| immich-redis | 50-100MB | 200MB | >256MB |

**If hitting limits:**
```bash
# Increase memory limit example (adjust values as needed)
# Edit quadlet file:
nano ~/.config/containers/systemd/immich-server.container

# Add or modify:
[Container]
Memory=2G  # Increase from 1G

# Apply changes:
systemctl --user daemon-reload
systemctl --user restart immich-server.service
```

---

### Phase 5: Browser-Side Diagnostics (5 min)

**Objective:** Capture frontend errors and identify hanging requests.

**In Firefox Developer Tools (F12):**

1. **Console Tab** - Look for JavaScript errors:
   ```
   ❌ Uncaught TypeError: ...
   ❌ Failed to fetch
   ❌ Network request failed
   ❌ Maximum call stack size exceeded (infinite loop!)
   ```

2. **Network Tab** - Refresh page and monitor:
   - Click "Persist Logs" checkbox
   - Reload photos.patriark.org
   - Sort by "Duration" column (descending)

   **Red Flags:**
   - Requests stuck in "Pending" for >30 seconds
   - Multiple 500/502/504 errors
   - Failed requests (red icon)
   - Large payload sizes (>10MB) taking forever

3. **Performance Tab** - Check memory:
   - Click "Take snapshot"
   - Look at memory usage graph
   - If >500MB for a web page, something is wrong

**Save Evidence:**
```bash
# Take screenshots of:
1. Console errors (if any)
2. Network tab showing slow/failed requests
3. Performance/memory graph

# Or save HAR file:
Network tab → Right-click → "Save All As HAR"
```

---

### Phase 6: Configuration Drift Check (5 min)

**Objective:** Identify recent changes that may have broken Immich.

```bash
# 19. Check for configuration drift
cd /home/user/fedora-homelab-containers/.claude/skills/homelab-deployment
./scripts/check-drift.sh immich --verbose

# 20. Review recent changes to Immich files
git log --oneline --since="7 days ago" -- "*immich*"

# 21. Check for uncommitted changes
git status

# 22. Compare current config with last known good state
git diff HEAD~5 -- config/immich/
git diff HEAD~5 -- ~/.config/containers/systemd/immich*.container

# 23. Check current branch
git branch --show-current
```

**What Changed Recently?**
- Memory limits adjusted?
- Traefik labels modified?
- Network configuration changed?
- Image version upgraded?

**Quick Rollback (if needed):**
```bash
# Revert to previous commit (CAREFUL!)
git log --oneline -5  # Find last good commit
git checkout <commit-hash> -- config/immich/
git checkout <commit-hash> -- ~/.config/containers/systemd/immich*.container
systemctl --user daemon-reload
systemctl --user restart immich*.service
```

---

### Phase 7: Immich Component Interconnectivity (5 min)

**Objective:** Verify all Immich services can communicate.

```bash
# 24. Check if immich-server can reach postgres
podman exec immich-server ping -c 2 immich-postgres

# 25. Check if immich-server can reach redis
podman exec immich-server ping -c 2 immich-redis

# 26. Check if immich-server can reach ML service
podman exec immich-server ping -c 2 immich-ml

# 27. Verify immich-web can reach immich-server
# Get immich-server internal port (usually 3001)
podman exec immich-web wget -O- --timeout=5 http://immich-server:3001/api/server-info/ping

# 28. Check network attachments
podman inspect immich-server | grep -A 10 "NetworkSettings"
podman inspect immich-web | grep -A 10 "NetworkSettings"

# 29. Verify all services on same network
podman network inspect systemd-photos | grep -E "Container|Name"
```

**Expected:** All services on `systemd-photos` network and able to ping each other.

**If ping fails:**
- Check network exists: `podman network ls | grep photos`
- Verify containers attached: `podman network inspect systemd-photos`
- Check quadlet network config

---

## Decision Tree

Follow this flowchart to determine next actions:

```
Container not running?
├─ YES → Check logs (Phase 2) → Fix startup issue
└─ NO → Continue

High memory/CPU usage (>90%)?
├─ YES → Increase limits (Phase 4) → Restart service
└─ NO → Continue

OOM kills in journal?
├─ YES → IMMEDIATE: Increase memory limits, restart
└─ NO → Continue

API timeout or slow response (>10s)?
├─ YES → Check database performance
│         Check ML service (disable if needed)
│         Increase timeout values
└─ NO → Continue

JavaScript errors in browser console?
├─ YES → Check immich-web logs
│         Verify image version matches documentation
│         Search GitHub issues for error message
└─ NO → Continue

Requests stuck in "Pending" in Network tab?
├─ YES → Backend hanging → Check Phase 3 API health
│         Check Phase 7 interconnectivity
└─ NO → Continue

Recent config changes?
├─ YES → Revert and test
└─ NO → Continue

Configuration drift detected?
├─ YES → Reconcile drift → Restart services
└─ NO → Advanced troubleshooting needed
```

---

## Quick Command Reference

### All-in-One Diagnostics
```bash
# Run comprehensive system diagnostics
./scripts/homelab-diagnose.sh

# Run system intelligence report
./scripts/homelab-intel.sh
```

### Live Monitoring
```bash
# Follow all Immich logs in real-time (multiple terminals)
podman logs -f immich-server
podman logs -f immich-web
podman logs -f immich-ml
podman logs -f immich-postgres

# Or use journalctl for all services
journalctl --user -u "immich*" -f

# Monitor resources while reproducing issue
watch -n 2 'podman stats --no-stream | grep immich'
```

### Quick Health Checks
```bash
# All containers running?
podman ps | grep immich

# All services active?
systemctl --user status immich*.service | grep Active

# Quick log scan for errors
for svc in immich-server immich-web immich-ml immich-postgres immich-redis; do
  echo "=== $svc ==="
  podman logs --tail 10 $svc 2>&1 | grep -iE "error|fail|warn" || echo "No errors"
done
```

---

## Expected Findings & Solutions

### Scenario A: Memory Exhaustion
**Symptoms:** Container using >95% of limit, OOM kills in journal
**Solution:**
```bash
# Increase memory limits
nano ~/.config/containers/systemd/immich-server.container
# Change Memory=1G to Memory=2G

systemctl --user daemon-reload
systemctl --user restart immich-server.service
```

### Scenario B: Slow API Responses
**Symptoms:** API calls taking >10 seconds, requests stuck in "Pending"
**Root Causes:**
- Database slow (postgres needs more memory)
- ML service consuming all resources (pause ML jobs)
- Disk I/O bottleneck (check BTRFS NOCOW for postgres data)

**Solution:**
```bash
# Increase postgres memory
nano ~/.config/containers/systemd/immich-postgres.container
# Add: Memory=1G

# Temporarily disable ML features (if needed)
# Via Immich web UI: Settings → Machine Learning → Pause Jobs
```

### Scenario C: JavaScript Errors
**Symptoms:** Console shows "Uncaught TypeError", infinite rendering loop
**Root Causes:**
- Corrupted frontend build
- Version mismatch between web and server
- Browser extension conflict

**Solution:**
```bash
# Verify versions match
podman exec immich-server cat package.json | grep version
podman exec immich-web cat package.json | grep version

# Pull latest matching versions
podman pull ghcr.io/immich-app/immich-server:latest
podman pull ghcr.io/immich-app/immich-web:latest

# Recreate containers with new images
systemctl --user restart immich-server.service immich-web.service
```

### Scenario D: Network/Connectivity Issues
**Symptoms:** Services can't ping each other, connection refused
**Solution:**
```bash
# Verify network exists
podman network ls | grep photos

# Recreate network if missing
podman network create systemd-photos

# Reconnect containers
podman network connect systemd-photos immich-server
podman network connect systemd-photos immich-web
# etc.

# Or restart all services (they should auto-connect)
systemctl --user restart immich*.service
```

### Scenario E: Traefik Routing Issues
**Symptoms:** 502 Bad Gateway, route not found
**Solution:**
```bash
# Check Traefik sees the route
curl http://localhost:8080/api/http/routers | jq '.[] | select(.name | contains("immich"))'

# Verify container labels
podman inspect immich-web | grep -A 20 "Labels"

# Restart Traefik to reload
systemctl --user restart traefik.service
```

---

## Post-Resolution Actions

Once the issue is resolved:

1. **Document the root cause:**
   ```bash
   # Create incident report
   nano docs/10-services/journal/2025-11-22-immich-freeze-incident.md
   ```

2. **Update monitoring:**
   - Add alert for specific condition that caused the issue
   - Adjust alert thresholds if needed

3. **Commit fixes:**
   ```bash
   git add <changed-files>
   git commit -m "Fix: Immich freeze issue - <root cause>"
   git push origin claude/fix-immich-resource-issue-01NUVfxdRmBJj8VbMvEfc3Aa
   ```

4. **Test thoroughly:**
   - Reload photos.patriark.org multiple times
   - Test on mobile device
   - Upload a photo to verify full functionality
   - Check UI responsiveness

5. **Update documentation if needed:**
   - If configuration changed, update relevant guide
   - Add to troubleshooting section of docs/10-services/guides/immich.md

---

## Emergency Rollback Procedure

If troubleshooting makes things worse:

```bash
# 1. Stop all Immich services
systemctl --user stop immich*.service

# 2. Restore from last known good commit
git log --oneline -10  # Find commit hash before issues started
git checkout <good-commit-hash> -- config/immich/ ~/.config/containers/systemd/immich*.container

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Start services
systemctl --user start immich*.service

# 5. Test
curl http://localhost:<port>/api/server-info/ping
```

---

## Additional Resources

- **Immich Documentation:** https://immich.app/docs
- **Immich GitHub Issues:** https://github.com/immich-app/immich/issues
- **Homelab Diagnostics:** `./scripts/homelab-diagnose.sh`
- **Related Docs:**
  - `docs/10-services/guides/immich.md` (if exists)
  - `docs/20-operations/guides/troubleshooting-workflow.md`
  - `docs/40-monitoring-and-documentation/guides/prometheus-grafana.md`

---

## Notes Section

Use this space to record findings during troubleshooting:

```
Date/Time:
Phase completed:
Finding:
Action taken:
Result:

---

Date/Time:
Phase completed:
Finding:
Action taken:
Result:
```
