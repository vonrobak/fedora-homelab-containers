# Demo: Context-Aware Intelligence in Action

**Real examples showing how Context Framework transforms Claude's responses**

---

## Example 1: GPU Transcoding Troubleshooting

### Without Context (Generic Advice)
```
User: "Jellyfin transcoding is slow"

Claude: "Jellyfin transcoding can be slow for several reasons:
1. No hardware acceleration enabled
2. CPU-only transcoding is intensive
3. Check if you have a GPU available
4. Enable VA-API in settings

Try enabling hardware acceleration in Dashboard → Playback"
```

### With Context (Specific Solution)
```
User: "Jellyfin transcoding is slow"

Claude: [Reads issue-history.json]

"I see you already resolved this! ISS-008 shows you fixed GPU transcoding
on 2025-11-17.

[Reads deployment-log.json and quadlets/jellyfin.container]

Your configuration shows:
✅ AMD Cezanne GPU (amdgpu driver loaded)
✅ /dev/dri/card1 and renderD128 mapped to container
✅ Jellyfin deployed with media-server-stack pattern (4G RAM)

Let me verify it's actually working:
1. Check if radeontop shows GPU usage during playback
2. Verify FFmpeg is using -hwaccel vaapi flags
3. Check Jellyfin logs for VA-API initialization

If GPU is idle during transcode, check:
- Dashboard → Playback → Hardware acceleration = VA-API
- Device: /dev/dri/renderD128
- See ISS-008 resolution for exact steps you used before"
```

**Value:** Specific to YOUR system, references YOUR solution history

---

## Example 2: Disk Space Management

### Without Context
```
User: "System disk is almost full"

Claude: "To free disk space:
- Clean old logs: journalctl --vacuum-time=7d
- Prune Docker images: docker system prune
- Remove unused packages
- Check large files: du -sh /*"
```

### With Context
```
User: "System disk is almost full"

Claude: [Reads system-profile.json]

"Your system SSD is at 70% (was 84% earlier today).

[Reads issue-history.json]

ISS-001 shows this happened on 2025-11-18. You manually fixed it
by deleting BTRFS snapshots.

[Checks remediation playbooks]

You have an auto-cleanup playbook ready:

cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook disk-cleanup --dry-run

This will:
- Rotate journal logs (7-day retention) → ~2-5GB
- Prune dangling images → ~0.5-2GB
- Clean backup logs (30+ days) → ~0.1-1GB
- Remove stale Jellyfin transcodes → ~0-5GB

Total expected: 4-12GB freed

Your preferences.yml shows auto_disk_cleanup: true, so this can
run automatically when you hit 75%."
```

**Value:** Knows your threshold (75%), knows what you did before, has automation ready

---

## Example 3: Service Deployment

### Without Context
```
User: "I want to deploy Redis for a new app"

Claude: "To deploy Redis:

podman run -d --name redis \
  -v redis-data:/data \
  redis:alpine

Or create a systemd quadlet for auto-start."
```

### With Context
```
User: "I want to deploy Redis for a new app"

Claude: [Reads deployment-log.json]

"Let me check how you deployed Redis before:

redis-authelia (2025-11-11):
- Pattern: cache-service
- Memory: 256M
- Network: systemd-auth_services
- Method: pattern-based

redis-immich (2025-11-14):
- Pattern: cache-service
- Memory: 512M
- Network: systemd-photos
- Method: pattern-based

Both use the cache-service pattern. For your new app:

cd ~/containers/.claude/skills/homelab-deployment/scripts
./deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name redis-myapp \
  --hostname redis-myapp \
  --memory 256M \
  --network systemd-[your-app-network]

This will:
✅ Create quadlet with correct config
✅ Set up systemd service
✅ Configure health checks
✅ Match your existing Redis deployments

After deployment, record it:
nano ~/containers/.claude/context/scripts/build-deployment-log.sh
# Add entry, regenerate, commit"
```

**Value:** Consistency with your existing patterns, proven configurations

---

## Example 4: Service Failure Investigation

### Without Context
```
User: "Prometheus won't start"

Claude: "Check the logs:
journalctl -u prometheus.service -n 50

Common issues:
- Port already in use
- Config file syntax error
- Permission issues
- Memory limits

Try restarting:
systemctl restart prometheus.service"
```

### With Context
```
User: "Prometheus won't start"

Claude: [Reads deployment-log.json]

"Checking your Prometheus deployment (from 2025-11-06):
- Pattern: monitoring-exporter
- Memory: 2G
- Network: systemd-monitoring
- Notes: '15-day retention, NOCOW database directory'

[Reads issue-history.json]

I don't see previous Prometheus start failures in your history,
so this might be a new issue.

Let me check:
1. Memory pressure? [Reads system-profile.json: 13GB available, OK]
2. Drift from pattern? Run: check-drift.sh prometheus
3. Recent changes? Check: git log --oneline quadlets/prometheus.container

You have auto-restart remediation:
cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook service-restart --service prometheus --dry-run

This will:
1. Capture pre-restart logs
2. Graceful stop
3. Verify stopped
4. Start service
5. Verify healthy
6. Compare before/after logs

Want me to proceed with the smart restart?"
```

**Value:** Knows exact deployment config, checks for patterns, offers tested automation

---

## Example 5: Authelia Configuration

### Without Context
```
User: "How did I configure Authelia?"

Claude: "I don't have access to your Authelia configuration.
Check your config files in:
- /etc/authelia/configuration.yml
- Your container volumes
- Documentation you created"
```

### With Context
```
User: "How did I configure Authelia?"

Claude: [Reads deployment-log.json]

"Authelia deployment (2025-11-11):
- Pattern: authentication-stack
- Memory: 512M
- Networks: systemd-reverse_proxy, systemd-auth_services
- Method: pattern-based
- Notes: 'SSO with YubiKey, Redis session storage, 1h session timeout'

[Reads issue-history.json]

ISS-002 shows you had deployment complications:
'Multiple attempts encountered config issues, Redis session storage problems'

Resolution: 'Created comprehensive configuration, separated Redis
instance, validated MFA flow'

ISS-003 shows you removed Authelia from Immich:
'Dual-authentication created poor UX, now uses native auth only'

So your Authelia setup:
✅ YubiKey 2FA as primary method
✅ Dedicated Redis instance (redis-authelia, 256M)
✅ 1-hour session timeout
✅ Protects: Grafana, Prometheus, Traefik dashboard
✅ Bypassed for: Immich (native auth), Jellyfin (API endpoints)

Config location (from quadlet pattern):
~/containers/config/authelia/configuration.yml
~/containers/config/authelia/users_database.yml"
```

**Value:** Complete deployment history, lessons learned from issues

---

## Example 6: Pattern Selection

### Without Context
```
User: "What pattern should I use for a web app?"

Claude: "For a web application, consider:
- If it needs a database: web-app-with-database
- If it's standalone: reverse-proxy-backend
- Check available patterns in your deployment system"
```

### With Context
```
User: "What pattern should I use for a web app?"

Claude: [Reads deployment-log.json, analyzes patterns used]

"Looking at your deployment history:

Monitoring apps (Grafana, Alertmanager):
- Pattern: monitoring-stack
- Memory: 256-512M
- Network: monitoring + reverse_proxy

Media apps (Jellyfin):
- Pattern: media-server-stack
- Memory: 4G
- Network: media_services + reverse_proxy

Auth apps (Authelia):
- Pattern: authentication-stack
- Memory: 512M
- Network: auth_services + reverse_proxy

Photo apps (Immich):
- Pattern: multi-container (server + DB + ML + Redis)
- Memory: Varies by component

For a NEW web app, you'd likely want:
- If needs database → web-app-with-database pattern
- If admin/internal → reverse-proxy-backend pattern
- Memory: Start with 512M (typical for your non-media apps)
- Network: reverse_proxy (for external access) + app-specific

Your pattern success rate: 70% pattern-based, 30% manual
→ Patterns work well for you, use them when available"
```

**Value:** Recommendations based on YOUR actual usage patterns

---

## Key Benefits Demonstrated

### 1. **Historical Context**
- Knows what you did before
- References specific issue IDs
- Shows resolution patterns

### 2. **System Awareness**
- Knows exact hardware (AMD Cezanne GPU, 31GB RAM)
- Knows all 20 running services
- Knows network topology

### 3. **Pattern Recognition**
- "You always use 256M for Redis"
- "You prefer pattern-based deployments"
- "You bypassed Authelia for Immich due to ISS-003"

### 4. **Proactive Automation**
- "You have a playbook ready for this"
- "Auto-cleanup triggers at 75%"
- "Your preferences allow automatic restart"

### 5. **Learning from Mistakes**
- ISS-003: Learned Immich + Authelia = bad UX
- ISS-008: Learned APU needs card1 + renderD128
- ISS-011: Learned homelab-intel needs timeouts

---

## How to Leverage This in Practice

### When Asking Claude for Help

**Instead of:**
```
"How do I deploy Redis?"
```

**Ask:**
```
"I need to deploy Redis for my new app. Check how I deployed
redis-authelia and redis-immich, and use the same pattern."
```

Claude will:
1. Query deployment-log.json
2. Find both Redis deployments
3. See they both used cache-service pattern
4. Recommend same approach
5. Show exact commands you used before

---

### When Troubleshooting

**Instead of:**
```
"Jellyfin GPU transcoding not working"
```

**Ask:**
```
"Jellyfin GPU transcoding seems slow. Check issue history -
didn't we fix this before?"
```

Claude will:
1. Query issue-history.json
2. Find ISS-008 (resolved)
3. Show exact resolution steps
4. Verify current config matches
5. Suggest verification commands

---

### When Planning Changes

**Instead of:**
```
"Should I add Authelia to Immich?"
```

**Ask:**
```
"Should I add Authelia to Immich? Check if we tried that before."
```

Claude will:
1. Find ISS-003 in issue history
2. Show you already tried this
3. Explain why you removed it (poor UX)
4. Recommend keeping native auth
5. Save you from repeating mistakes

---

## Real Query Examples

These actually work with your current context:

```bash
cd ~/containers/.claude/context/scripts

# How did I fix GPU transcoding?
./query-issues.sh --category performance | grep -A 5 "ISS-008"

# What pattern does Jellyfin use?
./query-deployments.sh --service jellyfin

# Have I seen Authelia issues before?
./query-issues.sh --category authentication

# How much memory do I give Redis instances?
./query-deployments.sh --method pattern-based | grep redis
```

---

## Future Context Growth

As you use the system more, context becomes more valuable:

**After 1 month:**
- 30+ documented issues
- 25+ deployments
- Pattern preferences clear
- Common pitfalls catalogued

**After 6 months:**
- 100+ issues (comprehensive problem database)
- 40+ deployments (full service history)
- Seasonal patterns visible (e.g., "disk fills up monthly")
- Upgrade histories tracked

**After 1 year:**
- Complete operational history
- Trend analysis possible
- Predictive insights
- New homelab users can learn from your experience

---

## Maintenance Reminder

Keep context valuable by:

1. **Document as you go:** Add issues when you solve them
2. **Update after deployments:** Record new services
3. **Weekly profile refresh:** Keep system-profile.json current
4. **Git commit context changes:** Track evolution over time

---

**The more you feed the context, the smarter Claude becomes about YOUR specific homelab.**

---

**Created:** 2025-11-18
**Examples:** Based on actual issue-history.json and deployment-log.json
**Framework Version:** 1.0 (Session 4)
