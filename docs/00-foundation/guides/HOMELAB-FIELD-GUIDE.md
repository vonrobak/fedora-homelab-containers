# Homelab Field Guide

**Purpose:** Operational manual for maintaining a healthy, efficient homelab
**Audience:** Homelab operators (you + Claude Code)
**Last Updated:** 2025-11-30
**Philosophy:** Proactive health, systematic deployment, routine maintenance

---

## 🎯 Mission

**Keep the homelab healthy, secure, and reliable** through disciplined operational habits.

**Core Principles:**
1. **Health-first** - Check before acting
2. **Pattern-based** - Use proven templates
3. **Verify always** - Confirm changes applied
4. **Document intent** - Future-you will thank you
5. **Fail gracefully** - Understand before fixing

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
- Remove auth: Edit `traefik.http.routers.*.middlewares` label
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
nano ~/.config/containers/systemd/<service>.container
# Edit: traefik.http.routers.*.middlewares
# Remove: authelia@docker
systemctl --user daemon-reload
systemctl --user restart <service>.service

# NOTE: Service now publicly accessible
# Restore authentication after fixing Authelia
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

## 🌟 Philosophy: Good Operators

**Good operators:**
- Check before acting (health-first)
- Follow patterns (consistency)
- Verify changes (drift detection)
- Document intent (future clarity)
- Learn from incidents (continuous improvement)
- Automate repetition (reduce toil)
- Plan for failure (graceful degradation)

**Bad operators:**
- Deploy without checking health
- Skip verification steps
- Make undocumented changes
- Ignore warnings until critical
- Repeat manual work
- React instead of prevent

**Be the operator you'd want on call.**

---

## 📍 Quick Start for New Operators

**Day 1: Familiarization**
1. Read this field guide
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

**Document Version:** 1.0
**Maintained By:** patriark + Claude Code
**Review Frequency:** Quarterly (or after major incidents)
**Next Review:** 2026-02-14

---

**Remember:** *A healthy homelab is a boring homelab. Boring is good.*
