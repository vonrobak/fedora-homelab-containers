# Automation Reference Guide

**Last Updated:** 2025-11-30
**Maintainer:** patriark

This guide catalogs all automation scripts in the homelab, their purposes, schedules, and integration with Claude Code skills. Use this as the authoritative reference for understanding and extending the automation ecosystem.

---

## Quick Reference

### Decision Tree: Which Script Do I Use?

```
What do you need to do?
│
├─ Check system health?
│   └─ ./scripts/homelab-intel.sh
│
├─ Diagnose a problem?
│   ├─ General diagnostics → ./scripts/homelab-diagnose.sh
│   ├─ Storage issues → ./scripts/collect-storage-info.sh
│   └─ Memory issues → ./scripts/investigate-memory-leak.sh
│
├─ Deploy a service?
│   ├─ New service → .claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh
│   ├─ Validate before deploy → .claude/skills/homelab-deployment/scripts/check-prerequisites.sh
│   └─ Check for drift → .claude/skills/homelab-deployment/scripts/check-drift.sh
│
├─ Query the system?
│   ├─ Ask a question → ./scripts/query-homelab.sh "your question"
│   └─ Get skill recommendation → ./scripts/recommend-skill.sh "describe task"
│
├─ Check SLO compliance?
│   ├─ Quick status → ./scripts/slo-status.sh
│   └─ Full report → ./scripts/monthly-slo-report.sh
│
├─ Perform maintenance?
│   ├─ Cleanup resources → ./scripts/maintenance-cleanup.sh
│   ├─ Clear swap → ./scripts/clear-swap-memory.sh
│   └─ Rotate logs → ./scripts/rotate-journal-export.sh
│
├─ Manage backups?
│   └─ ./scripts/btrfs-snapshot-backup.sh
│
└─ Security audit?
    └─ ./scripts/security-audit.sh
```

---

## Automation Tiers

Scripts are organized into tiers based on their purpose and automation level.

### Tier 1: Scheduled Automations

These scripts run automatically via systemd timers. **Do not run manually unless testing.**

| Script | Timer | Schedule | Purpose |
|--------|-------|----------|---------|
| `cloudflare-ddns.sh` | `cloudflare-ddns.timer` | Every 30 min | Update DNS when public IP changes |
| `btrfs-snapshot-backup.sh` | `btrfs-backup-daily.timer` | Daily 02:00 | Create local BTRFS snapshots |
| `btrfs-snapshot-backup.sh` | `btrfs-backup-weekly.timer` | Weekly Sun 03:00 | Sync to external drive |
| `maintenance-cleanup.sh` | `maintenance-cleanup.timer` | Weekly Sun 03:00 | Prune containers, rotate logs |
| `daily-drift-check.sh` | `daily-drift-check.timer` | Daily 06:00 | Detect config drift → Discord alert |
| `daily-resource-forecast.sh` | `daily-resource-forecast.timer` | Daily 06:05 | Predict exhaustion → Discord alert |
| `weekly-intelligence-report.sh` | `weekly-intelligence.timer` | Friday 07:30 | End-of-week health summary → Discord |
| `monthly-slo-report.sh` | `monthly-slo-report.timer` | 1st of month 10:00 | SLO compliance report → Discord |
| `rotate-journal-export.sh` | `journal-logrotate.timer` | Hourly | Keep journal logs under control |
| `precompute-queries.sh` | *(cron)* | Every 5 min | Pre-compute query cache for autonomous ops |

**Timer management commands:**
```bash
# List all active timers
systemctl --user list-timers

# Check specific timer
systemctl --user status weekly-intelligence.timer

# View last execution
journalctl --user -u weekly-intelligence.service -n 20

# Trigger manually (for testing)
systemctl --user start weekly-intelligence.service
```

### Tier 2: On-Demand Intelligence

Run these scripts interactively to assess system state.

| Script | Purpose | Output |
|--------|---------|--------|
| `homelab-intel.sh` | System health scoring (0-100) | Terminal + JSON report |
| `homelab-diagnose.sh` | Comprehensive diagnostics | Terminal + timestamped report |
| `homelab-snapshot.sh` | Full infrastructure state capture | JSON snapshot for analysis |
| `query-homelab.sh` | Natural language queries (cached) | Formatted terminal output |
| `recommend-skill.sh` | Intelligent skill recommendation | Terminal or JSON |
| `autonomous-check.sh` | OODA loop assessment (observe, orient, decide) | JSON with skill recommendations |
| `slo-status.sh` | Quick SLO compliance check | Terminal |
| `survey.sh` | System inventory (BTRFS, firewall, versions) | Terminal |
| `show-pod-status.sh` | Container status with network/port info | Terminal |

**Examples:**
```bash
# Quick health check
./scripts/homelab-intel.sh

# Natural language query
./scripts/query-homelab.sh "What services use the most memory?"

# Generate snapshot for documentation
./scripts/homelab-snapshot.sh
```

### Tier 3: Deployment & Validation

Scripts for deploying and validating services. Located in both `/scripts/` and `.claude/skills/`.

| Script | Location | Purpose |
|--------|----------|---------|
| `deploy-from-pattern.sh` | skills/homelab-deployment | Deploy using battle-tested patterns |
| `check-prerequisites.sh` | skills/homelab-deployment | Validate before deployment |
| `check-drift.sh` | skills/homelab-deployment | Compare running vs declared state |
| `check-system-health.sh` | skills/homelab-deployment | Pre-deployment health gate |
| `validate-quadlet.sh` | skills/homelab-deployment | Quadlet syntax validation |
| `deploy-service.sh` | skills/homelab-deployment | Systemd operations orchestrator |
| `deploy-stack.sh` | skills/homelab-deployment | Multi-service stack deployment |
| `test-deployment.sh` | skills/homelab-deployment | Post-deployment verification |
| `generate-docs.sh` | skills/homelab-deployment | Auto-generate documentation |
| `resolve-dependencies.sh` | skills/homelab-deployment | Topological sort for stacks |
| `validate-traefik-config.sh` | scripts/ | Validate Traefik YAML before apply |
| `deploy-jellyfin-with-traefik.sh` | scripts/ | Legacy: Jellyfin-specific deploy |

**Deployment workflow:**
```bash
# Pattern-based deployment (recommended)
cd .claude/skills/homelab-deployment
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --hostname jellyfin.patriark.org

# Check for configuration drift
./scripts/check-drift.sh            # All services
./scripts/check-drift.sh jellyfin   # Specific service
```

### Tier 4: Maintenance & Fixes

Scripts for maintenance tasks and specific fixes.

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `maintenance-cleanup.sh` | Prune containers, rotate logs | Automated; manual if urgent |
| `clear-swap-memory.sh` | Clear swap when under pressure | High swap usage |
| `apply-resource-limits.sh` | Apply memory limits to services | After quadlet changes |
| `migrate-to-container-slice.sh` | Add container.slice to quadlets | One-time migration |

### Tier 5: Predictive Analytics

Located in `/scripts/predictive-analytics/`. Forecast resource exhaustion before it happens.

| Script | Purpose |
|--------|---------|
| `predict-resource-exhaustion.sh` | Forecast disk/memory exhaustion dates |
| `analyze-trends.sh` | Analyze historical trends |
| `generate-predictions-cache.sh` | Pre-compute predictions for caching |

**Example:**
```bash
./scripts/predictive-analytics/predict-resource-exhaustion.sh
# Output: "Disk will hit 90% in ~14 days based on current trend"
```

### Tier 6: Storage & Backup

| Script | Purpose |
|--------|---------|
| `btrfs-snapshot-backup.sh` | Create snapshots, sync to external |
| `collect-storage-info.sh` | Storage survey and diagnostics |
| `relocate-btrfs-snapshots.sh` | Organize snapshots in .snapshots/ |

### Tier 7: Security

| Script | Purpose |
|--------|---------|
| `security-audit.sh` | Check for exposed secrets, auth issues |
| `sanitize-for-public.sh` | Prepare repo for public release |

### Tier 8: Service-Specific

Scripts for managing individual services.

| Script | Service | Purpose |
|--------|---------|---------|
| `jellyfin-manage.sh` | Jellyfin | Start/stop/restart/status |
| `jellyfin-status.sh` | Jellyfin | Quick status check |
| `backup-pihole.sh` | Pi-hole | Backup to external drive |
| `homepage-add-api-key.sh` | Homepage | Configure widget API keys |

### Tier 9: One-Off / Legacy

Scripts created for specific fixes. Consider archiving or removing if obsolete.

| Script | Purpose | Status |
|--------|---------|--------|
| `fix-podman-secrets.sh` | Convert file secrets to Podman secrets | May be obsolete |
| `fix-immich-ml-healthcheck.sh` | Fix ML container health check | Applied |
| `fix-immich-ml-healthcheck-v2.sh` | Simplified ML health check fix | Applied |
| `diagnose-redis-immich.sh` | Debug Redis health validation | Diagnostic |
| `deploy-immich-gpu-acceleration.sh` | Enable ROCm for Immich ML | Feature |
| `detect-gpu-capabilities.sh` | Check AMD GPU prerequisites | Helper |
| `complete-day3-deployment.sh` | Day 3 deployment completion | Historical |
| `compare-quadlets.sh` | Compare deployed vs tracked quadlets | May replace with drift check |
| `organize-docs.sh` | Reorganize documentation structure | One-time |
| `test-yubikey-ssh.sh` | Test YubiKey SSH auth | Testing |
| `monitor-ssh-tests.sh` | Monitor SSH tests from another host | Testing |
| `traefik-entrypoint.sh` | Traefik wrapper for secrets | Container entrypoint |
| `precompute-queries.sh` | Pre-populate query cache | Could be scheduled |
| `investigate-memory-leak.sh` | Identify memory leak sources | Diagnostic |

### Tier 10: Archived Scripts

Scripts moved to `scripts/archived/` - superseded or no longer maintained.

| Script | Archived | Reason |
|--------|----------|--------|
| `intelligence-2025-11/` | 2025-11-28 | Superseded by `homelab-intel.sh` + `predictive-analytics/` |
| `homelab-snapshot.sh` | 2025-11-28 | Not scheduled, overlaps with `homelab-intel.sh` |

See `scripts/archived/README.md` for restoration instructions if needed.

---

## Scheduled Automation Details

### Timer Configurations

All timers are in `~/.config/systemd/user/`:

```
cloudflare-ddns.timer         → Every 30 min, 5 min after boot
btrfs-backup-daily.timer      → Daily at 02:00
btrfs-backup-weekly.timer     → Sunday at 03:00 (external sync)
maintenance-cleanup.timer     → Sunday at 03:00 (±30 min random)
daily-drift-check.timer       → Daily at 06:00 (±10 min random)
daily-resource-forecast.timer → Daily at 06:05 (±10 min random)
weekly-intelligence.timer     → Friday at 07:30 (end-of-week summary)
monthly-slo-report.timer      → 1st of month at 10:00 (SLO compliance)
journal-logrotate.timer       → Hourly
```

### Adding New Scheduled Automation

1. Create the script in `/scripts/`
2. Create timer and service units:

```bash
# ~/.config/systemd/user/my-task.timer
[Unit]
Description=My Scheduled Task Timer
Documentation=file:///home/patriark/containers/scripts/my-task.sh

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
```

```bash
# ~/.config/systemd/user/my-task.service
[Unit]
Description=My Scheduled Task

[Service]
Type=oneshot
ExecStart=/home/patriark/containers/scripts/my-task.sh
```

3. Enable and start:
```bash
systemctl --user daemon-reload
systemctl --user enable --now my-task.timer
```

---

## Skill Integration

### Skill → Script Mapping

| Skill | Scripts Used |
|-------|--------------|
| **homelab-intelligence** | `homelab-intel.sh`, `homelab-diagnose.sh`, `query-homelab.sh`, `predictive-analytics/` |
| **homelab-deployment** | All scripts in `.claude/skills/homelab-deployment/scripts/` |
| **systematic-debugging** | Uses diagnostic scripts indirectly via methodology |
| **git-advanced-workflows** | No direct script integration |
| **claude-code-analyzer** | Own scripts in `.claude/skills/claude-code-analyzer/scripts/` |

### Future Consolidation (Trajectory 3)

Intelligence-related scripts could potentially be consolidated under the homelab-intelligence skill:

```
.claude/skills/homelab-intelligence/
├── SKILL.md
└── scripts/
    ├── homelab-intel.sh          ← Move from /scripts/
    ├── homelab-diagnose.sh       ← Move from /scripts/
    ├── query-homelab.sh          ← Move from /scripts/
    ├── slo-status.sh             ← Move from /scripts/
    └── predictive-analytics/     ← Move from /scripts/
```

**Note:** This would require updating:
- CLAUDE.md command references
- Systemd timer ExecStart paths
- Any scripts that call these scripts

**Current status:** Not prioritized. Scripts work fine in `/scripts/` and are well-documented here.

---

## Automation Candidates (Trajectory 2)

**Implemented (2025-11-28):**
- ~~`check-drift.sh`~~ → `daily-drift-check.timer` (Daily 06:00)
- ~~`predict-resource-exhaustion.sh`~~ → `daily-resource-forecast.timer` (Daily 06:05)

**Remaining candidates:**

| Script | Suggested Schedule | Rationale | Blocker |
|--------|-------------------|-----------|---------|
| `security-audit.sh` | Weekly | Regular security posture check | Uses `sudo firewall-cmd` |
| `precompute-queries.sh` | Every 5 min | Keep query cache fresh | Low value vs complexity |

---

## Script Documentation Standards

When adding new scripts, include this header:

```bash
#!/bin/bash
# script-name.sh
# Purpose: One-line description
#
# Usage:
#   ./script-name.sh [options]
#
# Options:
#   --option1    Description
#   --help       Show this help
#
# Dependencies:
#   - tool1
#   - tool2
#
# Automation:
#   Timer: timer-name.timer (if scheduled)
#   Schedule: description of schedule
#
# Integration:
#   Skill: skill-name (if part of a skill)
#   Called by: other-script.sh (if invoked by another script)
#
# Status: ACTIVE | DEPRECATED | ONE-TIME
# Created: YYYY-MM-DD
```

---

## Troubleshooting

### Timer Not Running

```bash
# Check timer status
systemctl --user status my-task.timer

# Check for errors
journalctl --user -u my-task.timer -n 20
journalctl --user -u my-task.service -n 20

# Verify timer is enabled
systemctl --user is-enabled my-task.timer
```

### Script Fails in Timer but Works Manually

Common causes:
1. **PATH issues** - Use absolute paths in scripts
2. **Environment variables** - Timers don't inherit shell environment
3. **Working directory** - Use `cd` or absolute paths

Solution: Add to service unit:
```ini
[Service]
Environment=PATH=/usr/bin:/bin
WorkingDirectory=/home/patriark/containers
```

### Finding Which Script Does X

```bash
# Search script headers
grep -l "Purpose.*backup" scripts/*.sh

# Search script content
grep -r "podman stats" scripts/

# Check this guide's decision tree above
```

---

## See Also

- `docs/20-operations/guides/backup-strategy.md` - Backup automation details
- `docs/40-monitoring-and-documentation/guides/slo-framework.md` - SLO monitoring
- `.claude/skills/homelab-deployment/SKILL.md` - Deployment skill documentation
- `.claude/skills/README.md` - Skills overview
