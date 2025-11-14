# Health-Driven Operations Guide

**Created:** 2025-11-14
**Purpose:** Use system health metrics to guide operational decisions
**Skill:** homelab-intelligence (homelab-intel.sh)
**Status:** Production ✅

---

## Overview

**Health-driven operations** means using **quantitative health metrics** to inform deployment, maintenance, and troubleshooting decisions rather than relying on intuition or reactive problem-solving.

**The homelab-intel.sh script** provides:
- Health score (0-100) representing overall system state
- Critical issues requiring immediate action
- Warnings about degrading conditions
- Recommendations based on current metrics

**Integration:** Pattern deployment (`check-system-health.sh`) uses intelligence scoring to block deployments when system health is poor.

---

## Quick Reference

### Check System Health

```bash
# Full intelligence report
./scripts/homelab-intel.sh

# Quiet mode (score only)
./scripts/homelab-intel.sh --quiet

# JSON output (for automation)
./scripts/homelab-intel.sh --json

# Latest report location
ls -lt ~/containers/docs/99-reports/intel-*.json | head -1
```

### Health Score Interpretation

| Score | Status | Meaning | Action |
|-------|--------|---------|--------|
| **90-100** | Excellent ✅ | All systems optimal | Deploy anything |
| **75-89** | Good ⚠️ | Minor issues present | Proceed with monitoring |
| **50-74** | Degraded ⚠️ | Multiple warnings | Address warnings first |
| **0-49** | Critical 🚨 | Severe issues | Fix before new deployments |

### Integration with Deployment

```bash
cd .claude/skills/homelab-deployment

# Health check integrated automatically
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# Or run health check manually
./scripts/check-system-health.sh

# Override health check (emergency deployments only)
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --skip-health-check
```

---

## Health Metrics

### Metric Categories

**homelab-intel.sh analyzes:**

1. **System Resources**
   - Disk usage (system SSD + BTRFS pool)
   - Memory usage and pressure
   - CPU load average
   - Swap usage

2. **Critical Services**
   - Traefik (reverse proxy)
   - Prometheus (metrics)
   - Grafana (dashboards)
   - Alertmanager (alerting)
   - Authelia (authentication)
   - CrowdSec (security)

3. **BTRFS Health**
   - Fragmentation levels
   - Filesystem errors
   - Allocation usage
   - Device status

4. **Container Health**
   - Running container count
   - Failed container count
   - Container restart patterns

5. **System Uptime**
   - Days since last reboot
   - Unexpected reboots
   - Kernel updates pending

---

### Score Calculation

**Health score formula:**
```
Base Score: 100 points

Deductions:
- Critical service down: -20 points per service
- Disk >80% full: -15 points
- Disk >70% full: -10 points
- Memory >90%: -15 points
- Memory >80%: -10 points
- BTRFS fragmentation >50%: -10 points
- Failed containers: -5 points per container
- Load average >4: -10 points
- Warnings: -2 points per warning

Final Score: Base - Total Deductions
```

**Example:**
```
Base: 100
- Disk 78% (>70%): -10
- Memory 55%: 0
- All services running: 0
- BTRFS fragmentation 25%: 0
- Load average 1.2: 0
= Final Score: 90 (Excellent)
```

---

## Operational Workflows

### Workflow 1: Pre-Deployment Health Check

**Goal:** Verify system ready for new service deployment

**Steps:**
```bash
# 1. Run intelligence scan
./scripts/homelab-intel.sh

# Example output:
# ════════════════════════════════════════
# System Health: 85/100 (Good)
# ════════════════════════════════════════
#
# ⚠ Warnings:
# - System disk at 72% (target <70%)
# - 1 container restart detected (traefik)
#
# ✅ Recommendations:
# - Clean up old logs: journalctl --vacuum-time=7d
# - Check traefik restart cause
#
# ════════════════════════════════════════

# 2. Interpret score
# 85/100 = Good
# Proceed with deployment but monitor warnings

# 3. Optionally address warnings first
journalctl --user --vacuum-time=7d  # Clean logs
podman logs traefik --tail 50       # Check restart cause

# 4. Deploy service
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name redis \
  --memory 512M
```

**Decision Matrix:**

| Health Score | Action | Rationale |
|--------------|--------|-----------|
| **90-100** | ✅ Deploy | System optimal |
| **75-89** | ⚠️ Deploy + Monitor | Minor issues, acceptable |
| **50-74** | ⚠️ Fix Warnings First | Degraded state, stabilize before adding load |
| **0-49** | 🚨 Block Deployment | Critical issues must be resolved |

---

### Workflow 2: Routine Health Monitoring

**Goal:** Proactive detection of degrading conditions

**Frequency:** Daily or weekly

**Steps:**
```bash
# 1. Run intelligence scan
./scripts/homelab-intel.sh > /tmp/health-$(date +%Y%m%d).txt

# 2. Compare to previous scan
diff /tmp/health-$(date +%Y%m%d --date='1 week ago').txt \
     /tmp/health-$(date +%Y%m%d).txt

# 3. Track score trends
# Health scores over time:
# Week 1: 95
# Week 2: 92
# Week 3: 88  ← Declining trend
# Week 4: 85  ← Investigate

# 4. Investigate declining scores
./scripts/homelab-intel.sh --json | jq .warnings

# 5. Address root causes
# Example: Disk usage increasing
du -sh ~/containers/* | sort -h | tail -10
```

**Trend analysis:**
- **Stable (95 → 94 → 96):** Healthy fluctuation
- **Gradual decline (95 → 90 → 85):** Investigate proactively
- **Sudden drop (95 → 60):** Urgent investigation needed

---

### Workflow 3: Troubleshooting with Health Data

**Goal:** Use health metrics to diagnose issues

**Scenario:** Service deployment failed mysteriously

**Steps:**
```bash
# 1. Check system health
./scripts/homelab-intel.sh

# Output shows:
# Health Score: 55/100 (Degraded)
# 🚨 Critical Issues:
# - System disk: 92% full
# - Prometheus service: down
# ⚠ Warnings:
# - Memory pressure detected

# 2. Identify root cause
# Disk nearly full explains deployment failure
# (likely failed to pull image or write data)

# 3. Fix critical issues
# Clean disk space
podman system prune -af
journalctl --user --vacuum-time=3d
rm -rf ~/containers/data/backup-logs/*.log.old

# Restart Prometheus
systemctl --user restart prometheus.service

# 4. Verify health improved
./scripts/homelab-intel.sh

# Output:
# Health Score: 88/100 (Good)
# ✅ All critical services running
# ⚠ System disk: 68% (acceptable)

# 5. Retry deployment
./scripts/deploy-from-pattern.sh --pattern cache-service --service-name redis
```

---

### Workflow 4: Capacity Planning

**Goal:** Use health trends to predict resource exhaustion

**Method: Track metrics over time**

```bash
# Weekly health tracking
for i in {1..4}; do
  date=$(date +%Y%m%d --date="$i weeks ago")
  echo "=== Week $i ==="
  cat ~/containers/docs/99-reports/intel-${date}*.json | jq '{
    health_score: .health_score,
    disk_system: .metrics.disk_usage_system,
    disk_btrfs: .metrics.disk_usage_btrfs,
    memory: .metrics.memory_used_percent
  }'
done

# Example output:
# === Week 4 ===
# health_score: 95
# disk_system: 55%
# disk_btrfs: 38%
# memory: 48%

# === Week 3 ===
# health_score: 92
# disk_system: 62%
# disk_btrfs: 41%
# memory: 52%

# === Week 2 ===
# health_score: 88
# disk_system: 68%
# disk_btrfs: 45%
# memory: 58%

# === Week 1 ===
# health_score: 85
# disk_system: 72%  ← Trend: +17% in 4 weeks
# disk_btrfs: 48%
# memory: 62%

# Prediction: System disk will reach 80% in ~2 weeks
# Action: Plan cleanup or storage expansion
```

**Capacity thresholds:**
- **Disk >70%:** Plan cleanup within 2 weeks
- **Disk >80%:** Urgent cleanup required
- **Memory >80%:** Consider reducing service count or adding RAM
- **Load avg >4:** CPU bottleneck, optimize or upgrade

---

## Health-Aware Deployment Blocking

### Automatic Blocking

**`check-system-health.sh` blocks deployments when:**

```bash
# Health check runs automatically
./scripts/deploy-from-pattern.sh --pattern media-server-stack --service-name jellyfin

# If health score < 50:
# Output:
# ════════════════════════════════════════
# ⛔ DEPLOYMENT BLOCKED
# ════════════════════════════════════════
# System health: 45/100 (Critical)
#
# Critical issues must be resolved before deployment:
# - System disk: 95% full
# - Prometheus: down
# - Memory: 92% used
#
# Fix these issues, then retry deployment.
# Override with --skip-health-check if emergency.
# ════════════════════════════════════════

# Deployment exits with error code 1
```

**Thresholds:**
- **Health < 50:** BLOCK deployment (critical issues)
- **Health 50-70:** WARN but allow (degraded state)
- **Health > 70:** ALLOW (acceptable state)

---

### Manual Override

**When to override:**
- Emergency fix deployment (service down, need quick replacement)
- Health check false positive (known non-critical warning)
- Testing in controlled environment

**How to override:**
```bash
# Skip health check entirely
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name emergency-redis \
  --skip-health-check

# Or force deployment despite low score
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name emergency-redis \
  --force
```

**Warning:** Overriding health checks increases risk of deployment failure or system instability.

---

## Health Report Interpretation

### Sample Report Analysis

```
════════════════════════════════════════
Homelab Intelligence Report
════════════════════════════════════════
Generated: 2025-11-14 14:30:00
Health Score: 78/100 (Good)
════════════════════════════════════════

📊 System Resources
  System Disk: 68% (128GB SSD)
  BTRFS Pool: 45% (4TB HDD)
  Memory: 58% (16GB total, 9.3GB used)
  Load Average: 1.8 (4 cores)
  Uptime: 12 days

✅ Critical Services (6/6 running)
  ✓ traefik
  ✓ prometheus
  ✓ grafana
  ✓ alertmanager
  ✓ authelia
  ✓ crowdsec

⚠ Warnings (3)
  - System disk approaching 70% threshold
  - Container restart detected: traefik (1 restart)
  - BTRFS fragmentation: 28% (monitor)

💡 Recommendations
  - Clean old journal logs: journalctl --vacuum-time=7d
  - Investigate traefik restart: journalctl -u traefik.service
  - Consider disk cleanup if reaches 75%

════════════════════════════════════════
```

**Interpretation:**

| Metric | Value | Assessment |
|--------|-------|------------|
| **Health Score** | 78/100 | Good - proceed with caution |
| **System Disk** | 68% | Approaching threshold, plan cleanup |
| **BTRFS Pool** | 45% | Healthy |
| **Memory** | 58% | Healthy |
| **Services** | 6/6 running | Excellent |
| **Warnings** | 3 warnings | Minor issues, addressable |

**Action plan:**
1. ✅ Deploy new services (health >70%)
2. ⚠️ Clean journal logs proactively (disk nearing 70%)
3. 🔍 Investigate traefik restart (informational, not blocking)
4. 📊 Monitor BTRFS fragmentation (currently acceptable)

---

## Automation

### Daily Health Check with Notifications

**Systemd timer for automated health monitoring:**

```bash
# Create timer unit
nano ~/.config/systemd/user/health-check.timer

[Unit]
Description=Daily Health Check

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target

# Create service unit
nano ~/.config/systemd/user/health-check.service

[Unit]
Description=Run Homelab Intelligence Scan

[Service]
Type=oneshot
ExecStart=/home/user/containers/scripts/homelab-intel.sh --json --output /home/user/containers/docs/99-reports/intel-%Y%m%d.json

# Enable timer
systemctl --user enable --now health-check.timer
```

---

### Alert on Critical Health

**Discord notification when health drops below threshold:**

```bash
#!/bin/bash
# health-alert.sh

WEBHOOK_URL="https://discord.com/api/webhooks/..."
THRESHOLD=70

# Run health check
HEALTH_SCORE=$(./scripts/homelab-intel.sh --quiet | jq .health_score)

if [[ $HEALTH_SCORE -lt $THRESHOLD ]]; then
  # Get critical issues
  ISSUES=$(./scripts/homelab-intel.sh --json | jq -r '.critical[] | .message' | head -3)

  # Send Discord alert
  curl -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"content\": \"🚨 **Health Alert**\",
      \"embeds\": [{
        \"title\": \"System Health: ${HEALTH_SCORE}/100\",
        \"description\": \"Critical issues detected:\n${ISSUES}\",
        \"color\": 15158332
      }]
    }"
fi
```

---

## Best Practices

### Regular Health Checks

- **Frequency:** Daily automated scan + weekly manual review
- **Retention:** Keep 30 days of health reports
- **Trending:** Track score changes over time
- **Action:** Address warnings before they become critical

### Pre-Deployment Verification

- **Always:** Check health before major deployments
- **Threshold:** Don't deploy if health < 70 unless emergency
- **Document:** Log health score in deployment notes
- **Retry:** If deployment fails, recheck health first

### Health-Aware Maintenance

- **Schedule:** Perform maintenance when health >80
- **Monitor:** Check health after maintenance operations
- **Rollback:** If health drops significantly, investigate immediately
- **Trending:** Declining health indicates need for proactive action

---

## Troubleshooting

### Low Health Score with No Obvious Issues

**Symptom:** Health score <70 but can't identify root cause

**Diagnosis:**
```bash
# Get detailed JSON output
./scripts/homelab-intel.sh --json > /tmp/health.json

# Check all metrics
cat /tmp/health.json | jq .metrics

# Check all warnings
cat /tmp/health.json | jq .warnings

# Check all critical issues
cat /tmp/health.json | jq .critical

# Compare to previous report
diff /tmp/health-previous.json /tmp/health.json
```

**Common hidden issues:**
- Gradual disk filling (many small files)
- Memory leak in long-running container
- BTRFS fragmentation increasing slowly
- Failed containers not showing in ps (exited state)

---

### Health Check Script Hangs

**Symptom:** `homelab-intel.sh` doesn't complete

**Diagnosis:**
```bash
# Run with debug mode
bash -x ./scripts/homelab-intel.sh

# Common hang points:
# - Checking service status (systemctl query timeout)
# - BTRFS status check (filesystem corruption)
# - podman ps (container runtime issue)
```

**Fix:** See `SESSION_3_REMAINING_BUGS.md` for bash arithmetic fixes

---

## Related Documentation

- **Intelligence Skill:** `.claude/skills/homelab-intelligence/SKILL.md`
- **Deployment Integration:** `.claude/skills/homelab-deployment/SKILL.md`
- **Pattern Selection:** `docs/10-services/guides/pattern-selection-guide.md`
- **Skill Integration:** `docs/10-services/guides/skill-integration-guide.md`
- **ADR-007:** `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md`

---

**Maintained by:** patriark + Claude Code
**Review frequency:** Quarterly
**Next review:** 2026-02-14
