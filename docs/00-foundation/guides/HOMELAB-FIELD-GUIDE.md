# Homelab Field Guide

**Purpose:** Operational manual for maintaining a healthy, efficient homelab
**Audience:** Homelab operators (you + Claude Code)
**Last Updated:** 2026-01-07
**Size:** 2,500+ lines | **Coverage:** 90%+ operational scenarios
**Philosophy:** Proactive health, systematic deployment, routine maintenance

---

## Table of Contents

### 🎯 Getting Started
- [Mission & Philosophy](#-mission--philosophy)
- [Quick Start for New Operators](#-quick-start-for-new-operators)
- [Quick Jump to Common Scenarios](#-quick-jump-to-common-scenarios)

### 📅 Daily & Weekly Operations
- [Daily Operations](#-daily-operations) - Health checks, monitoring
- [Deployment Workflow](#-deployment-workflow) - Pattern-based deployment
- [Weekly Maintenance](#-weekly-maintenance) - Drift detection, cleanup

### 🔧 Troubleshooting & Response
- [Troubleshooting Decision Tree](#-troubleshooting-decision-tree)
- [Emergency Procedures](#-emergency-procedures) - Service outages, disk full
- [Disaster Recovery Procedures](#-disaster-recovery-procedures) - Data restoration (6 min to 2 weeks RTO)
- [Security Operations](#-security-operations) - Incident response, audits, CVEs

### 🖥️ System Management
- [Fedora System Management](#-fedora-system-management) - DNF, systemd, SELinux, BTRFS
- [Essential Commands Reference](#-essential-commands-reference) - Quick command lookup

### 🎓 Best Practices & Growth
- [Best Practices and Habits](#-best-practices-and-habits)
- [Success Metrics](#-success-metrics)
- [Continuous Improvement](#-continuous-improvement)
- [Operational Maturity Levels](#-operational-maturity-levels)

---

## 🚀 Quick Jump to Common Scenarios

**Use this for fast navigation to the most common tasks:**

| I need to... | Go to Section | Time |
|--------------|---------------|------|
| **Check system health** | [Daily Operations → Health Check](#morning-health-check-5-minutes) | 5 min |
| **Deploy a new service** | [Deployment Workflow](#deployment-workflow) | 10-20 min |
| **Restore a deleted file** | [DR → Scenario 1: Accidental Deletion](#scenario-1-accidental-deletion-most-common) | 6 min |
| **Respond to brute force attack** | [Security → IR: Brute Force](#incident-response-brute-force-attack) | 10 min |
| **Fix a critical CVE** | [Security → IR: Critical CVE](#incident-response-critical-cve) | Hours-24h |
| **Service won't start** | [Troubleshooting Decision Tree → Step 2](#step-2-service-specific-troubleshooting) | 15-30 min |
| **Disk is >90% full** | [Emergency → Disk Full](#disk-full-emergency) | 5 min |
| **System won't boot** | [DR → Scenario 2: System SSD Failure](#scenario-2-system-ssd-failure) | 4-6 hours |
| **Update Fedora packages** | [Fedora → DNF Management](#dnf-package-management) | 30 min |
| **High swap usage (71%)** | [Fedora → Swap Management](#swap-management) | 15 min |
| **Run security audit** | [Security → Monthly Audit](#monthly-security-audit) | 20-30 min |
| **Rotate secrets** | [Security → Secrets Management](#secrets-management) | 15 min |
| **Find a command** | [Essential Commands Reference](#-essential-commands-reference) | 2 min |

---

## 🎯 Mission & Philosophy

**Keep the homelab healthy, secure, and reliable** through disciplined operational habits.

**Core Principles:**
1. **Health-first** - Check before acting
2. **Pattern-based** - Use proven templates
3. **Verify always** - Confirm changes applied
4. **Document intent** - Future-you will thank you
5. **Fail gracefully** - Understand before fixing

**Good operators:**
- Check before acting (health-first)
- Follow patterns (consistency)
- Verify changes (drift detection)
- Document intent (future clarity)
- Learn from incidents (continuous improvement)
- Automate repetition (reduce toil)
- Plan for failure (graceful degradation)

**Remember:** *A healthy homelab is a boring homelab. Boring is good.*

---

## 📍 Quick Start for New Operators

**Day 1: Familiarization**
1. Read this field guide (focus on Mission, Daily Operations, Troubleshooting)
2. Run `./scripts/homelab-intel.sh` and understand output
3. Review architecture: `docs/20-operations/guides/homelab-architecture.md`
4. Browse patterns: `.claude/skills/homelab-deployment/patterns/`

**Week 1: Observation**
1. Daily health checks (morning routine)
2. No changes - just observe
3. Understand baseline behavior
4. Review Grafana dashboards

**Week 2: First Deployment**
1. Deploy test service using pattern
2. Follow deployment workflow exactly
3. Document what was unclear
4. Ask questions

**Month 1: Build Habits**
1. Daily health check routine
2. Weekly drift audit
3. Monthly cleanup
4. First incident response

**Month 2+: Mastery**
1. Pattern customization
2. Troubleshooting independence
3. Contributing improvements
4. Mentoring new operators

---

## 📋 Daily Operations

### Morning Health Check (5 minutes)

**When:** Start of day, before any work
**Goal:** Situational awareness of system state

```bash
# Run intelligence scan
./scripts/homelab-intel.sh

# Expected output:
# ════════════════════════════════════════
# Health Score: 92/100 (Excellent)
# ════════════════════════════════════════
# ✅ All critical services running
# 📊 System disk: 65%
# 📊 Memory: 52%
#
# ⚠ Warnings (1):
# - Consider log cleanup (7 days old)
# ════════════════════════════════════════
```

**Decision Matrix:**

| Health Score | Status | Action |
|--------------|--------|--------|
| **90-100** | ✅ Excellent | Normal operations, proceed with any work |
| **75-89** | ⚠️ Good | Address warnings when convenient |
| **50-74** | ⚠️ Degraded | Fix warnings before new deployments |
| **0-49** | 🚨 Critical | Stop everything, fix critical issues |

**Quick Checks:**
```bash
# All services running?
systemctl --user is-active traefik prometheus grafana authelia

# Any failed containers?
podman ps -a --filter "status=exited" --filter "status=dead"

# Disk space OK?
df -h / /mnt/btrfs-pool | grep -v tmpfs

# Any unusual activity?
podman stats --no-stream | head -10

# Quick natural language queries (fast, cached):
./scripts/query-homelab.sh "What services are using the most memory?"
./scripts/query-homelab.sh "Show me disk usage"
./scripts/query-homelab.sh "What's using the most CPU?"
```

**Time Budget:** 5 minutes
**Frequency:** Daily (morning)
**Skip if:** Health score >90 for 3+ consecutive days

---

## 🚀 Deployment Workflow

### Pre-Deployment Checklist

**Before deploying ANY service:**

```bash
# 1. Health check (required)
cd .claude/skills/homelab-deployment
./scripts/check-system-health.sh

# Expected: Health score >70
# If <70, address issues first or document override reason

# 2. Choose pattern (required)
# See: docs/10-services/guides/pattern-selection-guide.md
# Decision tree:
# - Media streaming? → media-server-stack
# - Web app? → web-app-with-database
# - Database? → database-service
# - Cache? → cache-service
# - Password manager? → password-manager
# - Auth service? → authentication-stack
# - Admin panel? → reverse-proxy-backend
# - Metrics? → monitoring-exporter

# 3. Verify prerequisites
# - Image exists? podman pull <image>
# - Networks exist? podman network ls | grep systemd-
# - Ports available? ss -tulnp | grep <port>
# - Data directory ready? ls -ld /path/to/data
```

---

### Deployment Execution

**Standard deployment process:**

```bash
cd .claude/skills/homelab-deployment

# Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern <pattern-name> \
  --service-name <name> \
  --hostname <hostname.patriark.org> \
  --memory <size>

# Example:
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org \
  --memory 4G
```

**Expected output:**
```
✓ Health check passed (Score: 92/100)
✓ Pattern loaded: media-server-stack
✓ Prerequisites verified
✓ Generating quadlet...
✓ Quadlet created: ~/.config/containers/systemd/jellyfin.container
✓ Systemd reloaded
✓ Service started: jellyfin.service
✓ Health check passed
✓ Deployment complete
```

---

### Post-Deployment Verification

**Always verify after deployment:**

```bash
# 1. Service running?
systemctl --user status jellyfin.service
# Expected: active (running)

# 2. No configuration drift?
./scripts/check-drift.sh jellyfin
# Expected: MATCH (or intentional DRIFT with comments)

# 3. Health check passing?
curl -f http://localhost:8096/health
# Expected: HTTP 200 OK

# 4. Traefik routing working?
curl -I https://jellyfin.patriark.org
# Expected: HTTP 200 (or 302 to auth)

# 5. Logs clean?
podman logs jellyfin --tail 20
# Expected: No errors, normal startup messages
```

**If any check fails:**
1. Don't proceed with customizations
2. Review deployment logs: `journalctl --user -u jellyfin.service -n 50`
3. Check pattern matches service requirements
4. Consider manual deployment if pattern unsuitable

---

### Post-Deployment Customization (Optional)

**If pattern doesn't fully match needs:**

```bash
# 1. Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# 2. Add customizations (GPU, volumes, env vars, etc.)
# See: docs/10-services/guides/pattern-customization-guide.md

# 3. Apply changes
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 4. Verify customizations applied
./scripts/check-drift.sh jellyfin --verbose
podman inspect jellyfin | grep -A 5 <customization>

# 5. Document customizations in quadlet comments
# Example:
# # CUSTOMIZATION 2025-11-14: GPU transcoding
# AddDevice=/dev/dri/renderD128
```

**Common customizations:**
- GPU passthrough: `AddDevice=/dev/dri/renderD128`
- Volume mounts: `Volume=/path:/container:Z,ro`
- Remove auth: Edit `~/containers/config/traefik/dynamic/routers.yml` (remove authelia middleware)
- Environment vars: `Environment=KEY=value`
- Resource limits: Adjust `Memory=` and `CPUWeight=`

**See:** `docs/10-services/guides/pattern-customization-guide.md`

---

## 🔧 Weekly Maintenance

### Sunday Routine (20 minutes)

**When:** Sunday 10:00 AM (or convenient weekly time)
**Goal:** Proactive health maintenance, prevent issues

```bash
# 1. Full health report
./scripts/homelab-intel.sh > ~/weekly-health-$(date +%Y%m%d).txt
cat ~/weekly-health-*.txt

# 2. Drift detection across all services
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh > ~/drift-report-$(date +%Y%m%d).txt

# 3. Review drift report
cat ~/drift-report-*.txt | grep -E "(DRIFT|WARNING)"

# 4. Reconcile any drift found
for service in $(grep "DRIFT" ~/drift-report-*.txt | awk '{print $2}'); do
  echo "Reconciling: $service"
  systemctl --user restart $service.service
  sleep 5
done

# 5. Verify reconciliation
./scripts/check-drift.sh

# 6. Check for container restarts (unexpected)
podman ps -a --filter "status=restarting" --filter "restart-policy=on-failure"

# 7. Review logs for errors
journalctl --user --since "1 week ago" --priority=err -n 50

# 8. Update health trend tracking
echo "$(date +%Y%m%d): $(./scripts/homelab-intel.sh --quiet | jq .health_score)" \
  >> ~/health-trend.log
```

**Expected time:** 20 minutes
**Expected outcome:** All services showing MATCH, health score >85

---

### Monthly Cleanup (30 minutes)

**When:** First Sunday of month
**Goal:** Prevent disk exhaustion, optimize performance

```bash
# 1. Check disk usage trends
du -sh /home/user/containers/* | sort -h | tail -10
du -sh /mnt/btrfs-pool/subvol*/* | sort -h | tail -10

# 2. Clean old journal logs
journalctl --user --vacuum-time=30d
journalctl --system --vacuum-time=30d

# 3. Prune unused container images/volumes
podman system prune --volumes -f
# WARNING: Only run if no containers are intentionally stopped

# 4. Clean old backup logs
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete

# 5. Clean old health/drift reports
find ~ -name "health-*.txt" -mtime +90 -delete
find ~ -name "drift-report-*.txt" -mtime +90 -delete

# 6. Review BTRFS fragmentation
sudo btrfs filesystem usage /mnt/btrfs-pool/

# 7. Check for updates
# Fedora system updates (manual review)
sudo dnf check-update

# 8. Review Grafana dashboards for anomalies
# Open: https://grafana.patriark.org
# Check: CPU spikes, memory trends, disk usage
```

**Expected outcome:** System disk <65%, BTRFS pool <50%, no fragmentation issues

---

## 🔍 Troubleshooting Decision Tree

### When Something Goes Wrong

**Step 0: Get Skill Recommendation**
```bash
# Let the system suggest which skill to use
./scripts/recommend-skill.sh "describe the problem"

# Examples:
./scripts/recommend-skill.sh "Jellyfin won't start with permission errors"
# → Recommends: systematic-debugging (63% confidence)

./scripts/recommend-skill.sh "Need to reconfigure Immich service"
# → Recommends: homelab-deployment (58% confidence)
```

**Step 1: Check System Health**
```bash
./scripts/homelab-intel.sh
```

**Health score >70?**
- ✅ YES → Issue is service-specific, proceed to Step 2
- ❌ NO → System-wide problem, proceed to Step 3

---

**Step 2: Service-Specific Troubleshooting**

```bash
# A. Check service status
systemctl --user status <service>.service

# B. Check recent logs
journalctl --user -u <service>.service -n 100

# C. Check container logs
podman logs <service> --tail 100

# D. Check configuration drift
cd .claude/skills/homelab-deployment
./scripts/check-drift.sh <service>

# E. Check Traefik routing (if web service)
curl http://localhost:8080/api/http/routers/<service>@docker

# F. Test service health endpoint
curl http://localhost:<port>/health
```

**Common issues:**
- **Service won't start** → Check quadlet syntax, network exists, volume paths
- **Service restarting** → Check logs for errors, resource limits
- **Not accessible via web** → Check Traefik labels, DNS, firewall
- **Slow performance** → Check resource usage (`podman stats`)

**See:** Service-specific guides in `docs/10-services/guides/`

---

**Step 3: System-Wide Troubleshooting**

```bash
# A. Check critical services
systemctl --user is-active traefik prometheus grafana authelia
# If any down: systemctl --user restart <service>.service

# B. Check disk space
df -h / /mnt/btrfs-pool
# If >85%: Run monthly cleanup immediately

# C. Check memory pressure
free -h
podman stats --no-stream | head -15
# If >90%: Identify memory hogs, consider restart

# D. Check for failed containers
podman ps -a --filter "status=exited"
# Investigate why containers exited

# E. Check system load
uptime
top -bn1 | head -20
# If load >4: Identify CPU-intensive processes

# F. Review recent system changes
git log --oneline -10
journalctl --system --since "1 day ago" -p warning -n 50
```

**Emergency actions:**
- **Disk >95%:** Run `podman system prune -af` and `journalctl --vacuum-time=3d`
- **Memory >95%:** Restart memory-intensive services (Jellyfin, Grafana)
- **All services down:** Check Traefik, then cascade restart
- **Can't access any service:** Check UDM Pro port forwarding, DNS

---

## 🚨 Emergency Procedures

### Critical Service Down

**Traefik down (nothing accessible):**
```bash
# 1. Check status
systemctl --user status traefik.service

# 2. Review logs
journalctl --user -u traefik.service -n 50

# 3. Restart
systemctl --user restart traefik.service

# 4. Verify
curl http://localhost:8080/api/overview
curl -I https://jellyfin.patriark.org

# 5. If still failing, check configuration
cat ~/containers/config/traefik/traefik.yml
ls -la ~/containers/config/traefik/dynamic/
```

---

### Disk Full Emergency

**System disk >95%:**
```bash
# IMMEDIATE (5 minutes)
# 1. Clean journal
journalctl --user --vacuum-time=1d
journalctl --system --vacuum-time=1d

# 2. Prune containers
podman system prune -af --volumes

# 3. Remove old logs
find ~/containers/data/*/logs/ -name "*.log" -mtime +7 -delete

# 4. Check space
df -h /

# FOLLOW-UP (30 minutes)
# 5. Identify space consumers
du -sh /home/user/* | sort -h | tail -20
du -sh /var/* | sort -h | tail -20

# 6. Move data to BTRFS pool
# Identify large directories on system disk
# Move to: /mnt/btrfs-pool/subvol7-containers/

# 7. Prevent recurrence
# Review services writing to system disk
# Update quadlets to use BTRFS paths
```

---

### Authentication System Down

**Authelia not responding:**
```bash
# 1. Check Authelia + Redis
systemctl --user status authelia.service redis-authelia.service

# 2. Restart both
systemctl --user restart redis-authelia.service
sleep 5
systemctl --user restart authelia.service

# 3. Verify
curl http://localhost:9091/api/health
curl https://sso.patriark.org

# 4. Check session storage
podman exec redis-authelia redis-cli ping
# Expected: PONG

# 5. Review Authelia logs
podman logs authelia --tail 100 | grep -i error
```

**Emergency bypass (temporary):**
```bash
# Remove authelia middleware from critical service
nano ~/containers/config/traefik/dynamic/routers.yml

# Find router for <service>-secure:
# Remove authelia@file from middlewares list
# Keep: crowdsec-bouncer@file, rate-limit@file, security-headers@file

# Traefik will auto-reload in ~60s, or force reload:
podman exec traefik kill -SIGHUP 1

# NOTE: Service now publicly accessible
# Restore authentication after fixing Authelia
```

---

## 💾 Disaster Recovery Procedures

### Quick Reference

**Backup Coverage:** All critical data protected with automated weekly external backups + off-site mirror.

**Protection Levels Achieved:**
- ✅ **Level 2:** Verified external backup restore (tested 2026-01-03, 81,716 files recovered)
- ✅ **Level 3:** Off-site mirror exists at separate location (manual sync process)

**What's protected:**
- Home directory (~40GB): 7-day RPO, 6-hour RTO
- Container configs (~100GB): 7-day RPO, 6-hour RTO
- Media library (~2TB): 7-day RPO, 4-12 hour RTO
- Documents (~20GB): 7-30 day RPO, 6-hour RTO
- Photos (~500GB): 30-day RPO, 1-3 hour RTO

**Key principle:** Backups are tested monthly - we know they work!

---

### Recovery Decision Matrix

**Use this table to choose the right recovery procedure:**

| Scenario | Data Loss | RTO Target | Runbook | Common? |
|----------|-----------|------------|---------|---------|
| **Accidental file/folder deletion** | None (if <7 days old) | **6 minutes** | DR-003 | ✅ Most common |
| **Service config corruption** | None | **10-20 minutes** | DR-003 | ✅ Common |
| **System SSD failure** | Last 7 days | **4-6 hours** | DR-001 | ⚠️ Rare |
| **BTRFS pool corruption** | Last 7-30 days | **6-12 hours** | DR-002 | ⚠️ Very rare |
| **Total catastrophe (fire/flood/theft)** | Depends on last off-site sync | **1-2 weeks** | DR-004 | ❌ Extremely rare |

**Quick decision tree:**
1. **Lost a file?** → DR-003 (fastest - 6 minutes)
2. **System won't boot?** → DR-001 (fresh OS install + restore)
3. **BTRFS errors?** → DR-002 (reformat pool + restore)
4. **Everything destroyed?** → DR-004 (requires off-site backup)

---

### Scenario 1: Accidental Deletion (MOST COMMON)

**RTO:** 5-30 minutes | **RPO:** 1 day | **Last Verified:** 2026-01-03

**When to use:**
- Deleted important file or folder
- Corrupted configuration file
- Need previous version of file
- Rolled back change too far

**Quick recovery (local snapshots):**

```bash
# 1. Find file in local snapshot (last 7 days)
ls -lh ~/.snapshots/htpc-home/
# Shows: 20260106-htpc-home, 20260105-htpc-home, etc.

# 2. Browse snapshot to find file
find ~/.snapshots/htpc-home/20260105-htpc-home -name "traefik.yml"
# Example output: /home/patriark/.snapshots/htpc-home/20260105-htpc-home/containers/config/traefik/traefik.yml

# 3. Preview file to verify it's correct
less ~/.snapshots/htpc-home/20260105-htpc-home/containers/config/traefik/traefik.yml

# 4. Restore file with timestamp preservation
cp -a ~/.snapshots/htpc-home/20260105-htpc-home/containers/config/traefik/traefik.yml \
      ~/containers/config/traefik/traefik.yml

# 5. Verify restoration
ls -lh ~/containers/config/traefik/traefik.yml
diff ~/containers/config/traefik/traefik.yml \
     ~/.snapshots/htpc-home/20260105-htpc-home/containers/config/traefik/traefik.yml
```

**Recovery from external backup (older than 7 days):**

```bash
# 1. Mount external drive (usually auto-mounted)
ls /run/media/patriark/WD-18TB/.snapshots/
# If not mounted:
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# 2. List available external snapshots
ls -lh /mnt/external/.snapshots/htpc-home/
# Shows: Weekly snapshots (Saturdays) + monthly snapshots

# 3. Find file in external snapshot
SNAPSHOT_DATE="20251228"  # Adjust to desired date
find /mnt/external/.snapshots/htpc-home/$SNAPSHOT_DATE-htpc-home -name "important-file.txt"

# 4. Restore from external
cp -a /mnt/external/.snapshots/htpc-home/$SNAPSHOT_DATE-htpc-home/path/to/file \
      ~/restored-file
```

**Restore entire directory:**

```bash
# Example: Restore entire Traefik config from 2 days ago
cp -av ~/.snapshots/htpc-home/20260104-htpc-home/containers/config/traefik/ \
       ~/containers/config/traefik.restored

# Compare with current
diff -r ~/containers/config/traefik/ ~/containers/config/traefik.restored/

# If looks good, replace
mv ~/containers/config/traefik/ ~/containers/config/traefik.backup
mv ~/containers/config/traefik.restored/ ~/containers/config/traefik/

# Restart affected service
systemctl --user restart traefik.service
```

**See full details:** `docs/20-operations/runbooks/DR-003-accidental-deletion.md`

---

### Scenario 2: System SSD Failure

**RTO:** 4-6 hours | **RPO:** 7 days | **Last Tested:** Not yet tested

**When to use:**
- NVMe SSD failed (won't boot)
- System disk corrupted beyond repair
- Need to rebuild OS on new hardware

**High-level procedure:**

**Phase 1: Install fresh Fedora (1 hour)**
```bash
# Boot from Fedora 42 USB
# Install Fedora Workstation
# Create user: patriark
# Complete initial setup
```

**Phase 2: Restore home directory (30-60 minutes)**
```bash
# 1. Mount external backup drive
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# 2. Find latest home directory snapshot
LATEST_HOME=$(ls -t /mnt/external/.snapshots/htpc-home/ | head -1)
echo "Restoring from: $LATEST_HOME"

# 3. Restore home directory
sudo cp -av /mnt/external/.snapshots/htpc-home/$LATEST_HOME/* /home/patriark/
sudo chown -R patriark:patriark /home/patriark

# 4. Fix SSH permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*

# 5. Verify critical files present
ls -la ~/.config/containers/systemd/
ls -la ~/containers/config/
```

**Phase 3: Restore container data from BTRFS pool (30 minutes)**
```bash
# BTRFS pool is on separate drives - should be intact
# Just mount it
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# Verify data intact
ls -lh /mnt/btrfs-pool/subvol7-containers/
ls -lh ~/containers/config/  # From restored home directory

# If BTRFS pool also corrupted, follow DR-002 instead
```

**Phase 4: Restart services (30-60 minutes)**
```bash
# Reload systemd to pick up restored quadlets
systemctl --user daemon-reload

# Start critical services
systemctl --user start traefik.service
systemctl --user start prometheus.service
systemctl --user start grafana.service
systemctl --user start authelia.service

# Verify services running
podman ps
systemctl --user status traefik.service

# Test web access
curl -I https://grafana.patriark.org
```

**See full details:** `docs/20-operations/runbooks/DR-001-system-ssd-failure.md`

---

### Scenario 3: BTRFS Pool Corruption

**RTO:** 6-12 hours | **RPO:** 7-30 days | **Last Tested:** Not yet tested

**When to use:**
- Cannot mount `/mnt/btrfs-pool`
- BTRFS errors in dmesg
- Services fail with "no such file or directory" for `/mnt/btrfs-pool` paths

**Quick assessment:**

```bash
# 1. Check if BTRFS pool is mountable
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool
# If fails → corruption detected

# 2. Check BTRFS status (READ-ONLY check - safe)
sudo btrfs check --readonly /dev/mapper/btrfs-pool 2>&1 | tee ~/btrfs-check.log

# 3. Review errors
less ~/btrfs-check.log
# Look for: corruption_errs, parent transid verify failed, checksum errors

# 4. Decision:
# - Few errors → Try repair (risky but worth attempting)
# - Many errors → Reformat and restore from backup
```

**If attempting repair (DESTRUCTIVE - only if you have backups!):**

```bash
# Ensure unmounted
sudo umount /mnt/btrfs-pool 2>/dev/null || true

# Attempt repair (modifies filesystem!)
sudo btrfs check --repair /dev/mapper/btrfs-pool 2>&1 | tee ~/btrfs-repair.log

# If successful, mount and verify
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool
ls -lh /mnt/btrfs-pool/
sudo btrfs scrub start /mnt/btrfs-pool
sudo btrfs scrub status /mnt/btrfs-pool
```

**If repair fails or corruption severe - reformat and restore (6-12 hours):**

```bash
# 1. Reformat BTRFS pool (DESTROYS ALL DATA!)
sudo umount /mnt/btrfs-pool 2>/dev/null || true
sudo mkfs.btrfs -f -L btrfs-pool /dev/mapper/btrfs-pool

# 2. Mount new filesystem
sudo mount /dev/mapper/btrfs-pool /mnt/btrfs-pool

# 3. Recreate subvolume structure
cd /mnt/btrfs-pool
sudo btrfs subvolume create subvol1-docs
sudo btrfs subvolume create subvol2-pics
sudo btrfs subvolume create subvol3-opptak
sudo btrfs subvolume create subvol7-containers

# 4. Restore from external backup (prioritize by tier)
# Tier 1: Containers (critical, ~100GB, ~1 hour)
LATEST_CONTAINERS=$(ls -t /mnt/external/.snapshots/subvol7-containers/ | head -1)
sudo cp -av /mnt/external/.snapshots/subvol7-containers/$LATEST_CONTAINERS/* \
            /mnt/btrfs-pool/subvol7-containers/

# Apply NOCOW to database directories (performance)
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/prometheus
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/grafana
sudo chattr +C /mnt/btrfs-pool/subvol7-containers/data/loki

# Tier 1: Media library (~2TB, ~4-8 hours - run in tmux)
tmux new -s restore-media
LATEST_OPPTAK=$(ls -t /mnt/external/.snapshots/subvol3-opptak/ | head -1)
sudo rsync -av --progress \
     /mnt/external/.snapshots/subvol3-opptak/$LATEST_OPPTAK/ \
     /mnt/btrfs-pool/subvol3-opptak/
# Detach: Ctrl+B, D | Reattach: tmux attach -t restore-media

# Tier 2: Documents (~20GB, ~20 minutes)
LATEST_DOCS=$(ls -t /mnt/external/.snapshots/subvol1-docs/ | head -1)
sudo cp -av /mnt/external/.snapshots/subvol1-docs/$LATEST_DOCS/* \
            /mnt/btrfs-pool/subvol1-docs/

# Tier 3: Photos (~500GB, ~1-3 hours - run in tmux)
tmux new -s restore-photos
LATEST_PICS=$(ls -t /mnt/external/.snapshots/subvol2-pics/ | head -1)
sudo rsync -av --progress \
     /mnt/external/.snapshots/subvol2-pics/$LATEST_PICS/ \
     /mnt/btrfs-pool/subvol2-pics/

# 5. Fix ownership
sudo chown -R patriark:patriark /mnt/btrfs-pool/

# 6. Restart services
systemctl --user daemon-reload
systemctl --user start traefik.service prometheus.service grafana.service

# 7. Verify
podman ps
sudo btrfs scrub start /mnt/btrfs-pool
```

**See full details:** `docs/20-operations/runbooks/DR-002-btrfs-pool-corruption.md`

---

### Scenario 4: Total Catastrophe (Fire/Flood/Theft)

**RTO:** 1-2 weeks | **RPO:** Depends on last off-site sync | **Protection:** ✅ Level 3 (off-site mirror exists)

**When to use:**
- Home/office destroyed
- All local equipment lost (server + external backup drive)
- Need to rebuild from off-site backup

**Current status:** Off-site mirror exists via manual Icy Box sync process. Mirror stored at separate physical location.

**What can be recovered (if off-site mirror accessible):**
- ✅ All family photos (~500GB) - irreplaceable data protected
- ✅ All documents (~20GB) - irreplaceable data protected
- ✅ All media library (~2TB) - saves months of organization work
- ✅ All container configs (~100GB) - saves weeks of reconfiguration

**Recovery process (high-level):**

```bash
# 1. Acquire replacement hardware
# - New server/workstation
# - Replacement drives (NVMe SSD + BTRFS pool drives)
# - New external backup drive (18TB+)

# 2. Install fresh Fedora 42
# - Same as DR-001 system installation

# 3. Access off-site mirror drive
# - Retrieve from off-site location
# - Connect to new system
sudo cryptsetup open /dev/sdX WD-18TB-MIRROR
sudo mount /dev/mapper/WD-18TB-MIRROR /mnt/offsite

# 4. Restore by priority
# Priority 1: Irreplaceable data (photos, documents)
mkdir -p ~/restore/
cp -av /mnt/offsite/.snapshots/subvol2-pics/LATEST/* ~/restore/photos/
cp -av /mnt/offsite/.snapshots/subvol1-docs/LATEST/* ~/restore/docs/

# Priority 2: System configs
cp -av /mnt/offsite/.snapshots/htpc-home/LATEST/* ~/

# Priority 3: Container data
# (Follows same procedure as DR-002 BTRFS restore)

# 5. Rebuild services
# (Follows same procedure as DR-001 service restart)

# 6. IMMEDIATELY implement new off-site backup
# - Don't repeat the mistake of losing off-site backup
```

**Time to recovery (with off-site backup):**
- **Week 1:** Hardware acquisition, insurance claim, basic system restore
- **Week 2:** Full data restore, service rebuild, testing
- **Partial functionality:** 3-5 days (critical data + basic services)

**See full details:** `docs/20-operations/runbooks/DR-004-total-catastrophe.md`

**⚠️ Remaining gaps:**
- Off-site mirror restore not yet tested (assumes mirror reliability)
- Manual sync process (no automation, no metrics)
- Need to document sync frequency and last sync date

---

### Monthly Restore Testing

**Purpose:** Verify backups work BEFORE you need them in an emergency.

**Schedule:** First Sunday of each month (already automated via `test-backup-restore.sh`)

**What gets tested:**
1. External backup drive is accessible
2. BTRFS send/receive works correctly
3. File restoration preserves permissions and timestamps
4. Critical configs can be restored

**Test procedure (automated):**

```bash
# Run automated restore test
~/containers/scripts/test-backup-restore.sh

# Expected output:
# ✓ External drive mounted
# ✓ Latest snapshot found
# ✓ Test directory created
# ✓ Snapshot sent to test location
# ✓ Files verified (permissions, timestamps)
# ✓ Test cleanup completed
# Test PASSED - backups are verified working
```

**Manual spot check:**

```bash
# 1. Pick a random important file
FILE="containers/config/traefik/traefik.yml"

# 2. Find it in latest external snapshot
LATEST=$(ls -t /run/media/patriark/WD-18TB/.snapshots/htpc-home/ | head -1)
ls -lh /run/media/patriark/WD-18TB/.snapshots/htpc-home/$LATEST/$FILE

# 3. Compare with current version
diff ~/`$FILE /run/media/patriark/WD-18TB/.snapshots/htpc-home/$LATEST/$FILE
# Some differences expected (file changes since backup)

# 4. Verify permissions match
stat ~/`$FILE
stat /run/media/patriark/WD-18TB/.snapshots/htpc-home/$LATEST/$FILE
# Ownership and permissions should match
```

**Test results documentation:**

```bash
# Log test results
echo "$(date +%Y-%m-%d): Monthly backup restore test: PASSED" >> ~/backup-test-log.txt

# Review test history
tail -12 ~/backup-test-log.txt  # Last year of tests
```

**If test fails:**
1. **STOP** - Don't trust backups until fixed
2. Review test error logs
3. Verify external drive health: `sudo smartctl -H /dev/sdX`
4. Check BTRFS pool health: `sudo btrfs scrub start /mnt/btrfs-pool`
5. Run backup manually to create fresh snapshots
6. Re-test restoration
7. Document root cause and fix

---

### Snapshot Management

**Local snapshots (on system NVMe):**

```bash
# Home directory snapshots
ls -lh ~/.snapshots/htpc-home/
# Expected: 7 daily snapshots (last week)

# BTRFS pool snapshots
ls -lh /mnt/btrfs-pool/.snapshots/subvol7-containers/
ls -lh /mnt/btrfs-pool/.snapshots/subvol3-opptak/
ls -lh /mnt/btrfs-pool/.snapshots/subvol1-docs/
ls -lh /mnt/btrfs-pool/.snapshots/subvol2-pics/
```

**External snapshots (on WD-18TB):**

```bash
# Mount external drive (usually auto-mounted)
ls /run/media/patriark/WD-18TB/.snapshots/

# Home directory (8 weekly + 12 monthly)
ls -lh /run/media/patriark/WD-18TB/.snapshots/htpc-home/

# Containers (4 weekly + 6 monthly)
ls -lh /run/media/patriark/WD-18TB/.snapshots/subvol7-containers/

# Media library (8 weekly + 12 monthly)
ls -lh /run/media/patriark/WD-18TB/.snapshots/subvol3-opptak/

# Documents (8 weekly + 6 monthly)
ls -lh /run/media/patriark/WD-18TB/.snapshots/subvol1-docs/

# Photos (12 monthly)
ls -lh /run/media/patriark/WD-18TB/.snapshots/subvol2-pics/
```

**Check snapshot space usage:**

```bash
# Local NVMe snapshot usage
du -sh ~/.snapshots/
du -sh /mnt/btrfs-pool/.snapshots/

# External drive snapshot usage
du -sh /run/media/patriark/WD-18TB/.snapshots/
```

**Manual snapshot creation (before risky changes):**

```bash
# Create manual snapshot with descriptive name
sudo btrfs subvolume snapshot -r /home \
     ~/.snapshots/htpc-home/$(date +%Y%m%d-%H%M)-pre-upgrade

# Create manual snapshot of containers config
sudo btrfs subvolume snapshot -r /mnt/btrfs-pool/subvol7-containers \
     /mnt/btrfs-pool/.snapshots/subvol7-containers/$(date +%Y%m%d-%H%M)-pre-service-change

# Verify snapshot created
ls -lh ~/.snapshots/htpc-home/ | grep pre-upgrade
```

**Delete old manual snapshots:**

```bash
# List manual snapshots
ls -lh ~/.snapshots/htpc-home/ | grep -E "pre-|manual"

# Delete specific snapshot
sudo btrfs subvolume delete ~/.snapshots/htpc-home/20251115-1430-pre-upgrade
```

---

### Backup Automation Status

**Automated backups (via systemd timers):**

```bash
# Check backup timer status
systemctl --user list-timers | grep backup
# Expected:
# btrfs-backup-daily.timer    - Next run: Tomorrow 02:00
# btrfs-backup-weekly.timer   - Next run: Sat 04:00

# Check last backup run
journalctl --user -u btrfs-backup-daily.service --since "1 week ago" | grep "Completed"
journalctl --user -u btrfs-backup-weekly.service --since "1 month ago" | grep "Completed"

# View latest backup log
tail -100 ~/containers/data/backup-logs/backup-$(date +%Y%m).log

# Check for backup errors
grep ERROR ~/containers/data/backup-logs/backup-$(date +%Y%m).log
```

**Manual backup execution:**

```bash
# Run local snapshots only (fast, ~2 minutes)
~/containers/scripts/btrfs-snapshot-backup.sh --local-only

# Run full backup including external (slow, ~30-60 minutes)
# Ensure external drive connected first!
~/containers/scripts/btrfs-snapshot-backup.sh --verbose

# Test backup without executing
~/containers/scripts/btrfs-snapshot-backup.sh --dry-run
```

**Backup schedule reference:**

| Tier | Data | Local | External | Why |
|------|------|-------|----------|-----|
| 1 | Home, containers, media | Daily 02:00 | Weekly Sat 04:00 | Critical for operations |
| 2 | Documents, root | Daily/Monthly | Weekly/Monthly | Important but less changing |
| 3 | Photos | Weekly Sat 02:00 | Monthly 1st Sat | Large, infrequently changing |

---

### Emergency Contacts and Documentation

**Before disaster strikes:**

```bash
# 1. Document equipment inventory
nano ~/equipment-inventory.md
# Include: model numbers, serial numbers, purchase dates, costs

# 2. Store critical info off-site
# - Equipment inventory
# - Insurance policy numbers
# - External drive encryption passwords
# - GitHub SSH keys (for config restoration)
# - This runbook (printed copy)

# 3. Update emergency contact list
# - Insurance company phone number
# - Hardware vendor contacts
# - Family/friends for off-site backup exchange
```

**Insurance documentation:**

```bash
# Take photos of equipment
ls -lh ~/Documents/insurance/equipment-photos/

# Save receipts
ls -lh ~/Documents/insurance/receipts/

# Document total replacement cost
# Current estimate: ~$2,000-3,000 (server + drives + peripherals)
```

---

### Key Commands Reference

**Quick recovery commands:**

```bash
# Find file in local snapshot
find ~/.snapshots/htpc-home/YYYYMMDD-htpc-home -name "filename"

# Restore file from snapshot
cp -a ~/.snapshots/htpc-home/YYYYMMDD-htpc-home/path/to/file ~/path/to/file

# Mount external backup drive
sudo cryptsetup open /dev/sdX WD-18TB
sudo mount /dev/mapper/WD-18TB /mnt/external

# List external snapshots
ls -lh /mnt/external/.snapshots/htpc-home/

# Create manual snapshot before risky change
sudo btrfs subvolume snapshot -r /home ~/.snapshots/htpc-home/$(date +%Y%m%d-%H%M)-pre-change

# Test backups monthly
~/containers/scripts/test-backup-restore.sh

# Run manual backup
~/containers/scripts/btrfs-snapshot-backup.sh
```

---

### For More Details

**Comprehensive runbooks:**
- **Accidental deletion:** `docs/20-operations/runbooks/DR-003-accidental-deletion.md` (386 lines, verified 2026-01-03)
- **System SSD failure:** `docs/20-operations/runbooks/DR-001-system-ssd-failure.md` (508 lines, step-by-step OS reinstall)
- **BTRFS corruption:** `docs/20-operations/runbooks/DR-002-btrfs-pool-corruption.md` (536 lines, repair vs reformat decision tree)
- **Total catastrophe:** `docs/20-operations/runbooks/DR-004-total-catastrophe.md` (590 lines, off-site recovery procedures)

**Supporting guides:**
- **Backup strategy:** `docs/20-operations/guides/backup-strategy.md` (750 lines, automation details)
- **Disaster recovery:** `docs/20-operations/guides/disaster-recovery.md` (monthly testing procedures)

**Automation:**
- **Backup script:** `~/containers/scripts/btrfs-snapshot-backup.sh`
- **Restore test:** `~/containers/scripts/test-backup-restore.sh`
- **Systemd timers:** `~/.config/systemd/user/btrfs-backup-*.timer`

---

## 🛡️ Security Operations

### Quick Reference

**Security Posture:** Defense in depth with multiple security layers.

**Active Security Components:**
- ✅ **CrowdSec:** IP reputation + automatic banning (Layer 1)
- ✅ **Rate Limiting:** Tiered limits (50-200 req/min) (Layer 2)
- ✅ **Authelia SSO:** YubiKey WebAuthn + TOTP MFA (Layer 3)
- ✅ **Security Headers:** HSTS, CSP, X-Frame-Options (Layer 4)
- ✅ **Network Segmentation:** 5 networks, trust boundaries
- ✅ **Rootless Containers:** All services run as unprivileged user

**Automation:**
- Weekly vulnerability scans (Trivy, automated)
- Monthly security audits (40+ checks, manual)
- Automated compliance validation (ADR alignment)

**Key Principle:** Layered defense - fail fast at cheapest layer (IP reputation first, auth last).

---

### Security Operations Matrix

**Use this table to respond to security events:**

| Event | Severity | Response Time | Procedure | Automation |
|-------|----------|---------------|-----------|------------|
| **Brute force attack detected** | HIGH | **10 minutes** | IR-001 | ✅ CrowdSec auto-bans |
| **Critical CVE in running container** | CRITICAL | **Hours** | IR-003 | ⚠️ Weekly scan detects |
| **High CVE in running container** | HIGH | **24 hours** | IR-003 | ⚠️ Weekly scan detects |
| **Unauthorized port open** | MEDIUM | **1 hour** | IR-002 | ❌ Manual detection |
| **Compliance failure** | MEDIUM | **1 week** | IR-004 | ✅ Weekly automated |
| **Secret rotation needed** | LOW | **90 days** | Secrets guide | ❌ Manual schedule |

**Quick decision tree:**
1. **Under attack?** → Check CrowdSec decisions (IR-001)
2. **CVE disclosed?** → Risk assessment → update or mitigate (IR-003)
3. **Monthly audit failed?** → Review failures → remediate
4. **Need to rotate secrets?** → Follow secrets management guide

---

### Monthly Security Audit

**Schedule:** First Sunday of each month (20-30 minutes)
**Purpose:** Comprehensive security baseline validation (40+ checks)

**Run audit:**

```bash
# Execute comprehensive security audit
~/containers/scripts/security-audit.sh

# Expected output (if all passes):
# ═══════════════════════════════════════════════
#          HOMELAB SECURITY AUDIT
# ═══════════════════════════════════════════════
#
# [1] Checking SELinux... ✓ PASS
# [2] Checking rootless containers... ✓ PASS
# [3] Checking CrowdSec security... ✓ PASS
# [4] Checking Authelia configuration... ✓ PASS
# [5] Checking secrets management... ✓ PASS
# ... (40+ total checks)
#
# ═══════════════════════════════════════════════
# AUDIT SUMMARY
# ═══════════════════════════════════════════════
# ✓ Passed: 40
# ⚠ Warnings: 0
# ✗ Failed: 0
#
# Overall Status: PASS
```

**What gets checked:**
1. **SELinux:** Enforcing mode enabled
2. **Rootless containers:** No containers running as root
3. **CrowdSec:** Active, bouncer functional, recent decisions
4. **Authelia:** SSO + Redis healthy, WebAuthn enabled
5. **Secrets:** No secrets in Git, proper permissions (600)
6. **Network:** Service isolation, no direct host exposure
7. **TLS:** Valid certificates, modern ciphers only
8. **Security headers:** HSTS, CSP, X-Frame-Options present
9. **Rate limiting:** Traefik middleware active
10. **Firewall:** Only ports 80/443 exposed
11. **Service accounts:** No default passwords, MFA enabled
12. **Backups:** Encryption enabled, tested monthly
13. **Monitoring:** Prometheus scraping security metrics
14. **Compliance:** ADR-aligned configurations
15. **... and 25+ more checks**

**If audit fails:**

```bash
# Review failures
~/containers/scripts/security-audit.sh | grep -E "FAIL|WARN"

# Check specific failure details
# Example: CrowdSec not running
podman ps | grep crowdsec
systemctl --user status crowdsec.service

# Fix issues and re-run
~/containers/scripts/security-audit.sh

# Document findings
echo "$(date +%Y-%m-%d): Security audit - <issue> - <fix applied>" \
  >> ~/security-audit-log.txt
```

**Audit log review:**

```bash
# View audit history
tail -12 ~/security-audit-log.txt  # Last year

# Check for recurring failures
grep FAIL ~/security-audit-log.txt | sort | uniq -c
```

---

### Weekly Vulnerability Scanning

**Schedule:** Every Sunday 06:00 (automated via systemd timer)
**Purpose:** Detect CVEs in container images (CRITICAL/HIGH priority)

**Automated scanning (already running):**

```bash
# Check scanner status
systemctl --user list-timers | grep vulnerability
# Expected: vulnerability-scan.timer - Next run: Sun 06:00

# Check last scan results
ls -lt ~/containers/data/security-reports/trivy-*.json | head -5

# View summary of latest scan
cat ~/containers/data/security-reports/trivy-summary-*.txt
```

**Manual scan (on-demand):**

```bash
# Scan all running containers
~/containers/scripts/scan-vulnerabilities.sh --all

# Scan specific image
~/containers/scripts/scan-vulnerabilities.sh --image jellyfin/jellyfin:latest

# Scan with severity filter
~/containers/scripts/scan-vulnerabilities.sh --severity CRITICAL,HIGH

# Scan and send Discord notification
~/containers/scripts/scan-vulnerabilities.sh --all --notify
```

**Review scan results:**

```bash
# Count vulnerabilities by severity
cat ~/containers/data/security-reports/trivy-*.json | \
  jq -r '.Results[].Vulnerabilities[]? | .Severity' | \
  sort | uniq -c

# List CRITICAL vulnerabilities
cat ~/containers/data/security-reports/trivy-*.json | \
  jq '.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL") |
      {CVE: .VulnerabilityID, Package: .PkgName, Fixed: .FixedVersion}'

# Check if specific CVE affects your images
cat ~/containers/data/security-reports/trivy-*.json | \
  jq '.Results[].Vulnerabilities[]? | select(.VulnerabilityID=="CVE-2024-XXXXX")'
```

**See full procedure:** `docs/30-security/runbooks/IR-003-critical-cve.md`

---

### Incident Response: Brute Force Attack

**RTO:** 10 minutes | **Severity:** HIGH | **Automation:** CrowdSec auto-bans

**When this happens:**
- CrowdSec Discord alert: "New ban decision"
- Many failed auth attempts in Authelia logs
- Repeated 401/403 in Traefik logs

**Immediate response (0-5 minutes):**

```bash
# 1. Check CrowdSec active bans
podman exec crowdsec cscli decisions list
# Shows: IP, reason, duration, expiry

# 2. Check recent alerts
podman exec crowdsec cscli alerts list --since 1h

# 3. Check Authelia logs for breach attempts
podman logs authelia --since 1h 2>&1 | grep -i "failed\|unsuccessful" | tail -30

# 4. Verify no successful breaches
podman logs authelia --since 24h 2>&1 | grep "<ATTACKER_IP>" | grep -i "success"
# Should be empty - if not, CRITICAL incident (escalate to IR-005)
```

**Extend ban if needed:**

```bash
# Extend ban duration (default may be too short)
podman exec crowdsec cscli decisions add \
  --ip <ATTACKER_IP> \
  --duration 168h \
  --reason "Extended ban: persistent brute force"

# Permanent ban for severe attacks
podman exec crowdsec cscli decisions add \
  --ip <ATTACKER_IP> \
  --duration 8760h \
  --reason "Permanent ban: severe attack"
```

**Force logout all sessions (if breach suspected):**

```bash
# Nuclear option: expire all Authelia sessions
systemctl --user restart redis-authelia.service
```

**See full procedure:** `docs/30-security/runbooks/IR-001-brute-force-attack.md`

---

### Incident Response: Critical CVE

**RTO:** Hours to 24 hours | **Severity:** CRITICAL/HIGH

**When this happens:**
- Weekly Trivy scan finds CRITICAL or HIGH CVE
- Security advisory from image maintainer
- External disclosure (NVD, GitHub Advisory, etc.)

**Risk assessment (15-30 minutes):**

```bash
# 1. Get CVE details
cat ~/containers/data/security-reports/trivy-*.json | \
  jq '.Results[].Vulnerabilities[]? |
      select(.VulnerabilityID=="<CVE-ID>") |
      {CVE, Severity, Package: .PkgName, Fixed: .FixedVersion, Title}'

# 2. Check which services affected
podman ps --format "{{.Names}}\t{{.Image}}" | grep "<image_name>"

# 3. Determine exposure (internet-facing?)
grep -l "<service>" ~/.config/containers/systemd/*.container
cat ~/containers/config/traefik/dynamic/routers.yml | grep -A 5 "<service>"

# 4. Research CVE
# - NVD: https://nvd.nist.gov/vuln/detail/<CVE-ID>
# - Exploit-DB: https://www.exploit-db.com/search?cve=<CVE-ID>
```

**Remediation options:**

**Option A: Update image (preferred):**

```bash
# Pull latest image
podman pull <image>:<tag>

# Update quadlet (if tag pinned, update it)
nano ~/.config/containers/systemd/<service>.container

# Restart service
systemctl --user daemon-reload
systemctl --user restart <service>.service

# Verify CVE fixed
~/containers/scripts/scan-vulnerabilities.sh --image <new_image>
```

**Option B: Temporary mitigation (no patch available):**

```bash
# Add Authelia protection if not already protected
nano ~/containers/config/traefik/dynamic/routers.yml
# Add authelia@file to middlewares list

# OR move to internal-only network
nano ~/.config/containers/systemd/<service>.container
# Change Network= to systemd-internal

systemctl --user daemon-reload
systemctl --user restart <service>.service
```

**Option C: Disable service (last resort for CRITICAL + internet-facing):**

```bash
systemctl --user stop <service>.service
echo "$(date): <service> disabled due to <CVE-ID>" >> ~/disabled-services.log
```

**See full procedure:** `docs/30-security/runbooks/IR-003-critical-cve.md`

---

### Secrets Management

**When to rotate:**
- **Scheduled:** Every 90 days (quarterly)
- **Triggered:** After suspected exposure
- **Compliance:** As required by policy

**Podman secrets (preferred for containers):**

```bash
# List current secrets
podman secret ls

# Create new secret
echo -n "new-secret-value" | podman secret create service_password -

# Rotate existing secret
podman secret rm old_secret
echo -n "new-value" | podman secret create old_secret -
systemctl --user restart <service>.service

# Verify service uses secret
podman inspect <container> | grep -i secret
```

**EnvironmentFile secrets (for systemd services):**

```bash
# Rotate webhook token example
# 1. Generate new token
NEW_TOKEN=$(openssl rand -base64 32)

# 2. Update secrets file
sed -i "s/WEBHOOK_AUTH_TOKEN=.*/WEBHOOK_AUTH_TOKEN=$NEW_TOKEN/" \
  ~/.config/remediation-webhook.env

# 3. Update Alertmanager config
sed -i "s|token=[^']*|token=$NEW_TOKEN|" \
  ~/containers/config/alertmanager/alertmanager.yml

# 4. Restart services
systemctl --user restart remediation-webhook.service
systemctl --user restart alertmanager.service

# 5. Test
curl -X POST "http://localhost:9096/webhook?token=$NEW_TOKEN" -d '{"alerts": []}'
# Expected: HTTP 200
```

**Pre-commit verification (prevent secrets in Git):**

```bash
# Before committing, check for leaked secrets
git -C ~/containers grep -E "token=|password=|secret=" *.yml *.env 2>&1

# Check .gitignore is protecting secrets
git -C ~/containers status --ignored | grep -E "\.env|secrets"
# Should show: .env files ignored

# Verify no secrets in staged changes
git diff --cached | grep -iE "password|token|secret|key"
# Review carefully before committing
```

**See full guide:** `docs/30-security/guides/secrets-management.md` (694 lines)

---

### CrowdSec Management

**Check CrowdSec status:**

```bash
# CrowdSec service healthy?
systemctl --user status crowdsec.service
podman ps | grep crowdsec

# Bouncer connected?
podman exec crowdsec cscli bouncers list
# Expected: traefik-bouncer (active)

# Recent decisions (bans)?
podman exec crowdsec cscli decisions list
# Shows active IP bans

# Recent alerts (attacks detected)?
podman exec crowdsec cscli alerts list --since 24h
```

**Manual IP management:**

```bash
# Ban specific IP
podman exec crowdsec cscli decisions add \
  --ip 192.0.2.100 \
  --duration 24h \
  --reason "Manual ban: suspicious activity"

# Ban IP range
podman exec crowdsec cscli decisions add \
  --range 192.0.2.0/24 \
  --duration 168h \
  --reason "Manual ban: malicious ASN"

# Unban IP (false positive)
podman exec crowdsec cscli decisions delete --ip 192.0.2.100

# Check why IP was banned
podman exec crowdsec cscli alerts inspect <ALERT_ID>
```

**CrowdSec scenarios (attack patterns):**

```bash
# List active scenarios
podman exec crowdsec cscli scenarios list

# Check which scenarios are triggering
podman exec crowdsec cscli metrics
podman logs crowdsec --since 24h | grep scenario

# Common scenarios:
# - crowdsecurity/http-probing (port scanning)
# - crowdsecurity/http-bad-user-agent (malicious bots)
# - crowdsecurity/http-backdoors-attempts (exploit attempts)
# - crowdsecurity/ssh-bf (SSH brute force)
```

**Update CrowdSec:**

```bash
# Pull latest CrowdSec image
podman pull ghcr.io/crowdsecurity/crowdsec:latest

# Restart service
systemctl --user restart crowdsec.service

# Verify bouncer reconnected
podman exec crowdsec cscli bouncers list
```

---

### Essential Security Commands

**Daily security checks:**

```bash
# Check for active attacks
podman exec crowdsec cscli decisions list

# Check critical service status
systemctl --user is-active traefik authelia crowdsec

# Check failed auth attempts
podman logs authelia --since 1h 2>&1 | grep -ic failed

# Check Traefik access patterns
podman logs traefik --since 1h 2>&1 | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
```

**Weekly security tasks:**

```bash
# Run vulnerability scan
~/containers/scripts/scan-vulnerabilities.sh --all --notify

# Review CrowdSec metrics
podman exec crowdsec cscli metrics

# Check for exposed secrets
git -C ~/containers grep -iE "password|token|secret|key" *.yml 2>&1 | grep -v Binary
```

**Monthly security tasks:**

```bash
# Full security audit
~/containers/scripts/security-audit.sh

# Review firewall rules
sudo firewall-cmd --list-all

# Check certificate expiry
curl -vI https://grafana.patriark.org 2>&1 | grep -i "expire\|valid"

# Review Authelia user activity
podman logs authelia --since 30d 2>&1 | grep "successful" | awk '{print $NF}' | sort | uniq -c
```

**Quarterly security tasks:**

```bash
# Rotate secrets (every 90 days)
# - Webhook tokens
# - API keys
# - Service passwords

# Review and update security documentation
# - Incident response runbooks
# - Security audit checklist
# - Secrets management guide

# Test disaster recovery including security restoration
# - Verify secrets restore from backup
# - Test YubiKey recovery procedures
```

---

### For More Details

**Incident response runbooks:**
- **Brute force attack:** `docs/30-security/runbooks/IR-001-brute-force-attack.md` (231 lines, 10-min response)
- **Unauthorized port:** `docs/30-security/runbooks/IR-002-unauthorized-port.md` (1-hour response)
- **Critical CVE:** `docs/30-security/runbooks/IR-003-critical-cve.md` (293 lines, hours to 24-hour response)
- **Compliance failure:** `docs/30-security/runbooks/IR-004-compliance-failure.md` (weekly validation)

**Security guides:**
- **Secrets management:** `docs/30-security/guides/secrets-management.md` (694 lines, Podman secrets + EnvironmentFile)
- **CrowdSec phases:** `docs/30-security/guides/crowdsec-phases.md` (4-phase security implementation)
- **SSH hardening:** `docs/30-security/guides/ssh-hardening.md` (YubiKey + key-only auth)
- **Security architecture:** `docs/30-security/guides/security-architecture.md` (layered defense design)

**Automation:**
- **Security audit:** `~/containers/scripts/security-audit.sh` (40+ checks, monthly)
- **Vulnerability scan:** `~/containers/scripts/scan-vulnerabilities.sh` (Trivy, weekly automated)
- **Compliance validation:** Automated ADR alignment checks

---

## 🖥️ Fedora System Management

### Quick Reference

**System:** Fedora Workstation 43 (Gnome edition)
**Kernel:** Linux 6.17.12-300.fc43.x86_64
**Hardware:** AMD Ryzen 5 5600G, 30GB RAM, 128GB NVMe SSD + BTRFS pool

**Current state:**
- ⚠️ **Tuned profile:** "balanced" (should be "throughput-performance" for server workload)
- ⚠️ **Swap usage:** 71% (5.7GB/8GB) - needs investigation
- ⚠️ **Failed units:** 10 systemd services failed
- ✅ **SELinux:** Enforcing (secure)
- ✅ **Cockpit:** Available but not enabled

**Key principle:** Optimize Fedora for server workloads, not desktop usage.

---

### Tuned Performance Profiles

**Current status:**

```bash
# Check active tuned profile
tuned-adm active
# Current: balanced (optimized for desktop, not ideal for server)

# List available profiles
tuned-adm list
# Available:
# - balanced (current - desktop optimization)
# - throughput-performance (RECOMMENDED for homelab server)
# - latency-performance (low latency optimization)
# - powersave (battery optimization - not applicable)
```

**Recommended change: Switch to throughput-performance**

```bash
# Switch to throughput-performance profile
sudo tuned-adm profile throughput-performance

# Verify change applied
tuned-adm active
# Expected: Current active profile: throughput-performance

# Check what changed
tuned-adm profile_info throughput-performance
# Shows: CPU governor, I/O scheduler, transparent huge pages, etc.
```

**What throughput-performance optimizes:**
- **CPU governor:** Performance mode (max frequency, lower latency)
- **I/O scheduler:** Deadline/mq-deadline (better for server workloads)
- **Transparent huge pages:** Always enabled (better memory performance)
- **VM dirty ratios:** Adjusted for throughput
- **Energy savings:** Disabled (consistent performance)

**Revert if needed:**

```bash
# Go back to balanced profile
sudo tuned-adm profile balanced
```

---

### DNF Package Management

**Update strategy:**
- **System updates:** Monthly (first Sunday after security audit)
- **Security updates:** Within 7 days of release
- **Kernel updates:** Test then reboot within 14 days

**Monthly update procedure:**

```bash
# 1. Check for updates
sudo dnf check-update | wc -l
# Shows number of available updates

# 2. Review what will be updated
sudo dnf check-update

# 3. Run pre-update script (updates containers first)
~/containers/scripts/update-before-reboot.sh

# 4. Apply system updates
sudo dnf upgrade --refresh

# 5. Check if kernel was updated
sudo dnf list --installed kernel | tail -5
# If new kernel present, reboot required

# 6. Review changelog for major changes
sudo dnf updateinfo list --available
```

**Reboot decision:**

```bash
# Check if reboot required
sudo dnf needs-restarting -r
# Exit code 1 = reboot required
# Exit code 0 = no reboot needed

# Check which services need restart (no reboot)
sudo dnf needs-restarting -s
# Lists services that need restart after update

# Restart services without reboot
systemctl restart <service>
```

**DNF optimization:**

```bash
# Enable fastest mirror
sudo dnf config-manager --setopt=fastestmirror=True --save

# Keep package cache for rollback
sudo dnf config-manager --setopt=keepcache=True --save

# Limit parallel downloads (reduce load)
sudo dnf config-manager --setopt=max_parallel_downloads=3 --save

# Clean old packages (monthly cleanup)
sudo dnf clean packages
sudo dnf autoremove
```

**Kernel management:**

```bash
# List installed kernels
sudo dnf list --installed kernel

# Remove old kernels (keep 2 most recent)
sudo dnf remove $(dnf repoquery --installonly --latest-limit=-2 -q)

# Set kernel retention policy
sudo dnf config-manager --setopt=installonly_limit=2 --save
```

---

### Systemd Service Management

**Check failed services:**

```bash
# List all failed units
systemctl --failed
systemctl --user --failed

# Count failures
systemctl --failed --no-pager | wc -l
# Current system: 10 failed units

# Get details on specific failure
systemctl status <failed-service>.service
journalctl -u <failed-service>.service -n 100
```

**Common failed unit recovery:**

```bash
# Reset failed state
systemctl reset-failed <service>.service

# Restart failed service
systemctl restart <service>.service

# Disable problematic service (if not needed)
systemctl disable <service>.service
systemctl mask <service>.service  # Prevent accidental start

# Re-enable masked service
systemctl unmask <service>.service
```

**User service management (containers):**

```bash
# Enable linger (user services persist after logout)
loginctl enable-linger $USER

# Check linger status
loginctl show-user $USER | grep Linger
# Expected: Linger=yes

# List all user units
systemctl --user list-units --all

# Check for failed user services
systemctl --user --failed

# Reload systemd after quadlet changes
systemctl --user daemon-reload
```

**Systemd timer management:**

```bash
# List all timers (system + user)
systemctl list-timers --all
systemctl --user list-timers --all

# Check timer next run
systemctl --user list-timers | grep backup
# Shows: NEXT (when timer runs), LEFT (time until), LAST (last run)

# Manually trigger timer
systemctl --user start <timer>.service

# Enable/disable timer
systemctl --user enable <timer>.timer
systemctl --user disable <timer>.timer
```

---

### SELinux Management

**Status check:**

```bash
# Check SELinux mode
getenforce
# Expected: Enforcing (secure)
# Also: Permissive (logs violations but allows)
#       Disabled (not recommended)

# Detailed status
sestatus
```

**Troubleshooting permission denials:**

```bash
# Check recent SELinux denials
sudo ausearch -m avc -ts recent

# View denials in human-readable format
sudo ausearch -m avc -ts recent | audit2why

# If legitimate denial, create policy module
sudo ausearch -m avc -ts recent | audit2allow -M my_policy
sudo semodule -i my_policy.pp

# CAUTION: Only allow legitimate denials, not security violations!
```

**Container SELinux labels:**

```bash
# Verify volume has correct label
ls -lZ ~/containers/config/jellyfin
# Should show: container_file_t label

# Fix incorrect label
chcon -R -t container_file_t ~/containers/config/jellyfin

# OR use :Z in podman volume mount (automatic relabeling)
Volume=/path/to/config:/container/path:Z
```

**Temporary permissive mode (troubleshooting only):**

```bash
# Set SELinux to permissive (TEMPORARILY)
sudo setenforce 0

# Test if issue resolves
# ... run your test ...

# Re-enable enforcing mode
sudo setenforce 1

# Make permanent (NOT RECOMMENDED)
# Edit /etc/selinux/config, set SELINUX=permissive
```

---

### BTRFS Maintenance

**Monthly BTRFS maintenance:**

```bash
# Check BTRFS filesystem usage
sudo btrfs filesystem usage /
sudo btrfs filesystem usage /mnt/btrfs-pool

# Run scrub (verify checksums, detect corruption)
sudo btrfs scrub start /
sudo btrfs scrub start /mnt/btrfs-pool

# Check scrub status
sudo btrfs scrub status /mnt/btrfs-pool
# Expected: no errors found

# Run balance (rebalance data across devices)
sudo btrfs balance start -dusage=10 /
sudo btrfs balance start -musage=10 /mnt/btrfs-pool

# Check balance status
sudo btrfs balance status /mnt/btrfs-pool
```

**Defragment files (careful with snapshots!):**

```bash
# Defragment specific directory
sudo btrfs filesystem defragment -r ~/containers/data/prometheus

# CAUTION: Defragmentation breaks snapshot sharing
# Only defragment files that are NOT in snapshots
# Databases (with NOCOW) don't benefit from defragmentation
```

**BTRFS disk usage analysis:**

```bash
# Show space usage by subvolume
sudo btrfs subvolume list /mnt/btrfs-pool
sudo btrfs quota enable /mnt/btrfs-pool
sudo btrfs qgroup show /mnt/btrfs-pool

# Detailed breakdown
sudo btrfs filesystem du -s /mnt/btrfs-pool/*
```

---

### Cockpit Web Console (Optional)

**Setup Cockpit for web-based management:**

```bash
# Install Cockpit
sudo dnf install cockpit cockpit-podman

# Enable and start Cockpit
sudo systemctl enable --now cockpit.socket

# Check status
sudo systemctl status cockpit.socket

# Access Cockpit
# Open browser: https://localhost:9090
# Login with your system user (patriark)
```

**Cockpit features useful for homelab:**
- ✅ System overview (CPU, memory, disk, network graphs)
- ✅ Service management (start/stop/restart systemd units)
- ✅ Container management (via cockpit-podman plugin)
- ✅ Storage management (BTRFS filesystem, RAID)
- ✅ Terminal access (web-based SSH)
- ✅ Log viewer (journalctl integration)

**Firewall for Cockpit (if needed):**

```bash
# Allow Cockpit port (9090) on firewall
sudo firewall-cmd --add-service=cockpit --permanent
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services | grep cockpit
```

**Disable Cockpit (if not using):**

```bash
sudo systemctl disable --now cockpit.socket
sudo dnf remove cockpit cockpit-podman
```

---

### Swap Management

**Current issue: 71% swap usage (5.7GB/8GB)**

**Investigate swap usage:**

```bash
# Check swap usage
free -h
# Current: 5.7GB/8GB swap used (71%)

# Identify processes using swap
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  awk '/^Swap:/{swap=$2} END{if(swap>0) print swap" KB swapped for PID '$pid'"}' /proc/$pid/smaps 2>/dev/null
done | sort -n | tail -20

# Or use smem (if installed)
sudo dnf install smem
sudo smem -s swap -r | head -20
```

**Clear swap (if safe):**

```bash
# ONLY do this if system has free memory available
free -h  # Check available memory first

# Disable swap temporarily
sudo swapoff -a

# Re-enable swap (clears it)
sudo swapon -a

# Verify swap cleared
free -h
# Swap used should be near 0
```

**Adjust swappiness (reduce swap usage preference):**

```bash
# Check current swappiness
cat /proc/sys/vm/swappiness
# Default: 60 (balanced)
# Server recommended: 10-20 (prefer RAM over swap)

# Set swappiness temporarily
sudo sysctl vm.swappiness=10

# Make permanent
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.d/99-swap.conf
sudo sysctl -p /etc/sysctl.d/99-swap.conf
```

**Increase swap file (if RAM exhaustion is common):**

```bash
# Create larger swap file (16GB)
sudo dd if=/dev/zero of=/swapfile bs=1M count=16384
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Add to fstab
echo "/swapfile none swap defaults 0 0" | sudo tee -a /etc/fstab

# Verify
free -h
swapon --show
```

---

### Essential Fedora Commands

**System information:**

```bash
# Fedora version
cat /etc/fedora-release

# Kernel version
uname -r

# CPU info
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"

# Memory info
free -h

# Disk info
lsblk
df -h

# Hardware summary
sudo dmidecode -t system
sudo dmidecode -t memory
```

**Service health:**

```bash
# Critical system services
systemctl is-active systemd-journald systemd-logind NetworkManager firewalld

# User services (containers)
systemctl --user is-active traefik prometheus grafana authelia

# Check for core dumps
coredumpctl list
```

**Log management:**

```bash
# Check journal disk usage
journalctl --disk-usage

# Vacuum old logs (keep last 30 days)
sudo journalctl --vacuum-time=30d

# Rotate logs immediately
sudo journalctl --rotate

# View system boot logs
journalctl -b
journalctl -b -1  # Previous boot
```

**Firewall management:**

```bash
# Check firewall status
sudo firewall-cmd --state

# List active rules
sudo firewall-cmd --list-all

# Check which ports are open
sudo firewall-cmd --list-ports

# Add port (example)
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload

# Rich rules (advanced)
sudo firewall-cmd --list-rich-rules
```

---

### For More Details

**Fedora documentation:**
- **Fedora docs:** https://docs.fedoraproject.org/
- **Systemd manual:** `man systemd`
- **DNF guide:** `man dnf`
- **SELinux:** `man selinux`
- **BTRFS:** `man btrfs`

**Homelab-specific:**
- **Memory management:** `docs/20-operations/guides/memory-management.md`
- **Resource limits:** `docs/20-operations/guides/resource-limits-configuration.md`
- **Automation reference:** `docs/20-operations/guides/automation-reference.md`

**Useful scripts:**
- **Clear swap:** `~/containers/scripts/clear-swap-memory.sh`
- **System health:** `~/containers/scripts/homelab-intel.sh`

---

## 📚 Essential Commands Reference

### Daily Use
```bash
# System health
./scripts/homelab-intel.sh

# Deploy service
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh --pattern <pattern> --service-name <name>

# Check drift
./scripts/check-drift.sh <service>

# Service management
systemctl --user status <service>
systemctl --user restart <service>
podman logs <service> --tail 50
```

### Weekly Maintenance
```bash
# Drift audit
./scripts/check-drift.sh > ~/drift-$(date +%Y%m%d).txt

# Health trend
echo "$(date): $(./scripts/homelab-intel.sh --quiet | jq .health_score)" >> ~/health-trend.log

# Resource check
df -h / /mnt/btrfs-pool
free -h
podman stats --no-stream | head -10
```

### Monthly Cleanup
```bash
# Logs
journalctl --user --vacuum-time=30d

# Containers
podman system prune --volumes -f

# Backups
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
```

---

## 🎯 Best Practices and Habits

### Golden Rules

**1. Health Before Action**
- Always check `homelab-intel.sh` before deployments
- Address degraded health proactively
- Don't deploy when health <70 unless emergency

**2. Pattern-First Deployment**
- Use patterns for 80% of deployments
- Customize after deployment, not during
- Document customizations in quadlet comments

**3. Verify Everything**
- Post-deployment drift check (`check-drift.sh`)
- Service status check (`systemctl --user status`)
- Web access test (`curl https://service.patriark.org`)

**4. Document Intent**
- Commit messages explain WHY, not just WHAT
- Quadlet comments explain customizations
- Git history is your operational log

**5. Routine Discipline**
- Daily health check (5 min)
- Weekly drift audit (20 min)
- Monthly cleanup (30 min)

---

### Operational Hygiene

**Before making changes:**
```bash
# 1. Check current state
./scripts/homelab-intel.sh
git status

# 2. Backup if significant change
cp ~/.config/containers/systemd/<service>.container \
   ~/containers/backups/<service>.container.$(date +%Y%m%d-%H%M%S)

# 3. Commit baseline state
git add ~/.config/containers/systemd/<service>.container
git commit -m "<service>: baseline before <change>"
```

**After making changes:**
```bash
# 1. Verify applied
systemctl --user status <service>.service
./scripts/check-drift.sh <service>

# 2. Test functionality
curl https://<service>.patriark.org
# or service-specific tests

# 3. Commit changes
git add <changed files>
git commit -m "<service>: <description of change>"

# 4. Document in journal (if significant)
echo "$(date +%Y-%m-%d): <service> - <change>" >> ~/operational-journal.md
```

---

### Knowledge Management

**Where to find answers:**

| Question | Reference |
|----------|-----------|
| How to deploy service X? | `docs/10-services/guides/pattern-selection-guide.md` |
| How to customize deployment? | `docs/10-services/guides/pattern-customization-guide.md` |
| What does drift mean? | `docs/20-operations/guides/drift-detection-workflow.md` |
| How to interpret health score? | `docs/20-operations/guides/health-driven-operations.md` |
| What are the patterns? | `.claude/skills/homelab-deployment/patterns/` |
| Quick deployment recipe? | `.claude/skills/homelab-deployment/COOKBOOK.md` |
| Why pattern-based? | `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md` |
| Architecture overview? | `docs/20-operations/guides/homelab-architecture.md` |
| Service-specific help? | `docs/10-services/guides/<service>.md` |
| Natural language queries? | `docs/40-monitoring-and-documentation/guides/natural-language-queries.md` |
| Skill recommendations? | `docs/10-services/guides/skill-recommendation.md` |
| Autonomous operations? | `docs/20-operations/guides/autonomous-operations.md` |
| All automation scripts? | `docs/20-operations/guides/automation-reference.md` |

**When Claude Code should help:**
- **Let the system decide:** `./scripts/recommend-skill.sh "describe the task"`
- Deploying new services → Invoke `homelab-deployment` skill
- System health check → Invoke `homelab-intelligence` skill
- Bug investigation → Invoke `systematic-debugging` skill
- Complex git operations → Invoke `git-advanced-workflows` skill
- Quick system queries → Use `./scripts/query-homelab.sh "your question"`

**See:** `docs/10-services/guides/skill-recommendation.md`

---

## 📊 Success Metrics

**Healthy homelab indicators:**

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| **Health Score** | >85 | 70-85 | <70 |
| **System Disk** | <65% | 65-80% | >80% |
| **BTRFS Pool** | <50% | 50-70% | >70% |
| **Memory** | <70% | 70-85% | >85% |
| **Service Uptime** | >99% | 95-99% | <95% |
| **Drift Services** | 0 | 1-2 | >2 |
| **Container Restarts** | 0/week | 1-3/week | >3/week |

**Operational health indicators:**

| Practice | Target | Actual | Status |
|----------|--------|--------|--------|
| Daily health check | 7/week | ____ | ⬜ |
| Weekly drift audit | 4/month | ____ | ⬜ |
| Monthly cleanup | 1/month | ____ | ⬜ |
| Pre-deployment health | 100% | ____ | ⬜ |
| Post-deployment verify | 100% | ____ | ⬜ |
| Git commits documented | 100% | ____ | ⬜ |

**Track in:** `~/operational-metrics.md`

---

## 🔄 Continuous Improvement

### Monthly Review Questions

**Last Sunday of month, review:**

1. **Health Trend:** Is average health score improving or declining?
2. **Incidents:** What caused any service outages this month?
3. **Drift:** Are certain services consistently drifting?
4. **Resources:** Are we approaching any resource limits?
5. **Patterns:** Do we need new patterns based on deployment patterns?
6. **Documentation:** Are guides still accurate and helpful?
7. **Automation:** What manual tasks could be automated?

**Document findings in:** `docs/40-monitoring-and-documentation/journal/YYYY-MM-DD-monthly-review.md`

---

### Learning from Incidents

**After any significant issue:**

```bash
# 1. Document incident
nano docs/30-security/journal/$(date +%Y-%m-%d)-incident-<description>.md

# Include:
# - What happened?
# - What was the impact?
# - How was it detected?
# - How was it resolved?
# - What prevented faster detection/resolution?
# - What changes prevent recurrence?

# 2. Update runbooks if new procedure
# Add to relevant guide in docs/*/guides/

# 3. Consider automation
# Could this be prevented with monitoring/alerts?
# Could detection be automated?
```

---

## 🎓 Operational Maturity Levels

**Level 1: Reactive** (Starting point)
- Fix things when they break
- No health monitoring
- Manual ad-hoc deployments
- No drift detection

**Level 2: Aware** (First month)
- Daily health checks started
- Using patterns for deployments
- Weekly drift detection
- Basic troubleshooting

**Level 3: Disciplined** (Current goal)
- Automated health monitoring
- Pattern-first deployment habit
- Proactive drift reconciliation
- Systematic troubleshooting

**Level 4: Optimized** (Future)
- Predictive capacity planning
- Automated remediation
- Custom patterns for all services
- Continuous optimization

---

**Document Version:** 2.0 (Enhanced 2026-01-07)
**Maintained By:** patriark + Claude Code
**Review Frequency:** Quarterly (or after major incidents)
**Next Review:** 2026-04-07

---

*"A healthy homelab is a boring homelab. Boring is good."*
