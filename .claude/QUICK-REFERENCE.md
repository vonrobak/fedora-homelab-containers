# Quick Reference Card

**Context Framework & Auto-Remediation**

---

## Most Common Commands

### Context Queries
```bash
cd ~/containers/.claude/context/scripts

# Query issues
./query-issues.sh --status ongoing        # Current problems
./query-issues.sh --status resolved       # Past solutions
./query-issues.sh --category disk-space   # Disk issues
./query-issues.sh --severity critical     # Critical issues

# Query deployments
./query-deployments.sh --service jellyfin      # How was X deployed?
./query-deployments.sh --pattern monitoring-stack  # Services using pattern
./query-deployments.sh --method pattern-based      # Pattern vs manual

# Update context
./generate-system-profile.sh    # Refresh system state
./populate-issue-history.sh     # Rebuild issue DB
./build-deployment-log.sh       # Rebuild deployment DB
```

### Auto-Remediation
```bash
cd ~/containers/.claude/remediation/scripts

# Always dry-run first!
./apply-remediation.sh --playbook disk-cleanup --dry-run
./apply-remediation.sh --playbook service-restart --service prometheus --dry-run

# Execute remediation
./apply-remediation.sh --playbook disk-cleanup
./apply-remediation.sh --playbook service-restart --service grafana

# Check logs
ls -lh ../../data/remediation-logs/
tail -50 ../../data/remediation-logs/disk-cleanup-*.log
```

---

## Query Filters Reference

### Issue Categories
- `disk-space` - Storage problems
- `deployment` - Service deployment issues
- `authentication` - Auth/SSO problems
- `scripting` - Script bugs
- `monitoring` - Prometheus/Grafana/Loki issues
- `performance` - CPU/memory/GPU issues
- `ssl` - Certificate problems
- `media` - Jellyfin/media issues
- `architecture` - Design decisions
- `operations` - Backup/maintenance

### Issue Severities
- `critical` - System-breaking
- `high` - Major impact
- `medium` - Moderate impact
- `low` - Minor annoyance

### Issue Statuses
- `resolved` - Fixed
- `ongoing` - Active problem
- `mitigated` - Workaround applied
- `investigating` - Under investigation

### Deployment Methods
- `pattern-based` - From homelab-deployment patterns
- `manual quadlet` - Hand-written .container files
- `deploy script` - Used deployment scripts
- `multi-container stack` - Multiple coordinated services
- `custom script` - One-off automation

---

## File Locations

### Context Framework
```
~/containers/.claude/context/
├── system-profile.json          # Current system state
├── issue-history.json           # Problem database
├── deployment-log.json          # Deployment history
├── preferences.yml              # Your settings
└── scripts/                     # Query/update tools
```

### Remediation Framework
```
~/containers/.claude/remediation/
├── playbooks/*.yml              # Remediation recipes
├── scripts/apply-remediation.sh # Execution engine
└── ../data/remediation-logs/    # Execution logs
```

---

## Workflow Examples

### Troubleshooting a Service
```bash
# 1. Check if you've seen this before
cd ~/containers/.claude/context/scripts
./query-issues.sh --status resolved | grep prometheus

# 2. Check deployment config
./query-deployments.sh --service prometheus

# 3. Try auto-restart
cd ../../remediation/scripts
./apply-remediation.sh --playbook service-restart --service prometheus
```

### Deploying New Service
```bash
# 1. Check similar deployments
cd ~/containers/.claude/context/scripts
./query-deployments.sh --pattern cache-service  # Example: Redis

# 2. Deploy using same pattern
cd ~/containers/.claude/skills/homelab-deployment/scripts
./deploy-from-pattern.sh --pattern cache-service --service-name redis-new

# 3. Record deployment
cd ~/containers/.claude/context/scripts
nano build-deployment-log.sh  # Add entry
./build-deployment-log.sh
git commit -am "Add redis-new deployment"
```

### Disk Space Crisis
```bash
# 1. Check what worked before
cd ~/containers/.claude/context/scripts
./query-issues.sh --category disk-space

# 2. Run auto-cleanup
cd ../../remediation/scripts
./apply-remediation.sh --playbook disk-cleanup --dry-run  # Preview
./apply-remediation.sh --playbook disk-cleanup            # Execute
```

---

## Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Context shortcuts
alias ctx='cd ~/containers/.claude/context/scripts'
alias ctx-issues='cd ~/containers/.claude/context/scripts && ./query-issues.sh'
alias ctx-deploy='cd ~/containers/.claude/context/scripts && ./query-deployments.sh'

# Remediation shortcuts
alias remedy='cd ~/containers/.claude/remediation/scripts'
alias remedy-disk='./apply-remediation.sh --playbook disk-cleanup'
alias remedy-dry='./apply-remediation.sh --playbook disk-cleanup --dry-run'

# System status
alias homelab-status='~/containers/scripts/homelab-intel.sh'
alias homelab-health='~/containers/scripts/homelab-intel.sh | grep -A 20 "System Health"'
```

---

## Emergency Commands

### Disk Full (>95%)
```bash
cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook disk-cleanup  # Auto-cleanup
# If still critical:
sudo journalctl --vacuum-time=3d  # Aggressive journal cleanup
podman system prune -af           # Nuclear option (removes ALL unused images)
```

### Service Won't Start
```bash
# Quick restart
systemctl --user restart SERVICE.service

# Smart restart with logging
cd ~/containers/.claude/remediation/scripts
./apply-remediation.sh --playbook service-restart --service SERVICE

# Check what changed
cd ~/containers/.claude/skills/homelab-deployment/scripts
./check-drift.sh SERVICE
```

### Check System Health
```bash
~/containers/scripts/homelab-intel.sh
~/containers/scripts/homelab-diagnose.sh  # Detailed report
```

---

## Playbook Status

| Playbook | Status | Usage |
|----------|--------|-------|
| disk-cleanup | ✅ Ready | System SSD >75% |
| service-restart | ✅ Ready | Failed services |
| drift-reconciliation | ⚠️ Partial | Engine pending |
| resource-pressure | ⚠️ Partial | Engine pending |

---

## JSON Quick Queries

```bash
cd ~/containers/.claude/context

# System stats
jq '.service_count' system-profile.json
jq '.hardware.storage.system_ssd.used_percent' system-profile.json

# Issue counts
jq '.total_issues' issue-history.json
jq '.issues | group_by(.outcome) | map({status: .[0].outcome, count: length})' issue-history.json

# Deployment patterns
jq '.deployments | group_by(.pattern_used) | map({pattern: .[0].pattern_used, count: length})' deployment-log.json

# Memory allocation
jq -r '.deployments[] | "\(.service): \(.memory_limit)"' deployment-log.json
```

---

## Help Resources

- **Getting Started Guide:** `~/containers/.claude/GETTING-STARTED.md`
- **Context README:** `~/containers/.claude/context/README.md`
- **Remediation README:** `~/containers/.claude/remediation/README.md`
- **Session 4 Plan:** `~/containers/docs/99-reports/2025-11-15-session-4-hybrid-plan.md`

---

**Last Updated:** 2025-11-18
**Framework Version:** 1.0 (Session 4 Complete)
