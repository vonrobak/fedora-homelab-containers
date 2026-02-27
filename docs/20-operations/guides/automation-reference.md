# Automation Reference Guide

**Last Updated:** 2026-02-27
**Maintainer:** patriark

Authoritative reference for all automation scripts, scheduled timers, and skill integrations in the homelab. **56 active scripts**, **26 scheduled timers**, **9 deployment scripts**, **7 remediation playbooks**.

---

## Quick Reference

### Which Script Do I Use?

```
What do you need to do?
│
├─ Check system health?
│   └─ ./scripts/homelab-intel.sh
│
├─ Diagnose a problem?
│   ├─ General diagnostics → ./scripts/homelab-diagnose.sh
│   ├─ Storage issues → ./scripts/collect-storage-info.sh
│   └─ Flapping alerts → ./scripts/catch-flapping-alert.sh
│
├─ Deploy a service?
│   ├─ New service → .claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh
│   ├─ Validate quadlet → .claude/skills/homelab-deployment/scripts/validate-quadlet.sh
│   └─ Check for drift → .claude/skills/homelab-deployment/scripts/check-drift.sh
│
├─ Query the system?
│   ├─ Ask a question → ./scripts/query-homelab.sh "your question"
│   └─ Get skill recommendation → ./scripts/recommend-skill.sh "describe task"
│
├─ Check SLO compliance?
│   ├─ Quick status → ./scripts/slo-status.sh
│   ├─ Full report → ./scripts/monthly-slo-report.sh
│   └─ Trend analysis → ./scripts/analyze-slo-trends.sh
│
├─ Perform maintenance?
│   ├─ Cleanup resources → ./scripts/maintenance-cleanup.sh
│   ├─ Clear swap → ./scripts/clear-swap-memory.sh
│   └─ Rotate logs → ./scripts/rotate-journal-export.sh
│
├─ Update containers / prepare for reboot?
│   └─ ./scripts/update-before-reboot.sh
│       (orchestrates: snapshot → health gate → graceful shutdown → pull → prune)
│
├─ Manage backups?
│   ├─ Daily/weekly snapshots → ./scripts/btrfs-snapshot-backup.sh
│   ├─ Monitor transfer → ./scripts/monitor-btrfs-transfer.sh
│   └─ Test restore → ./scripts/test-backup-restore.sh
│
├─ Regenerate documentation?
│   └─ ./scripts/auto-doc-orchestrator.sh (runs all 4 generators in ~2s)
│
├─ Security audit?
│   ├─ Full audit → ./scripts/security-audit.sh
│   ├─ Vulnerability scan → ./scripts/scan-vulnerabilities.sh
│   ├─ Config compliance → ./scripts/audit-configuration.sh
│   └─ Permission drift → ./scripts/verify-permissions.sh
│
└─ Autonomous operations?
    ├─ Assessment only → ./scripts/autonomous-check.sh --verbose
    └─ Execute actions → ./scripts/autonomous-execute.sh --status
```

---

## Scheduled Timers (26 active)

All custom timers are in `~/.config/systemd/user/`. Timer management:

```bash
systemctl --user list-timers                          # List all
systemctl --user status <name>.timer                  # Check specific
journalctl --user -u <name>.service -n 20             # Last execution
systemctl --user start <name>.service                 # Trigger manually
```

### High-Frequency (minutes)

| Timer | Schedule | Script | Purpose |
|-------|----------|--------|---------|
| `nextcloud-cron` | Every 5 min | `podman exec nextcloud php cron.php` | Nextcloud background jobs |
| `dependency-metrics-export` | Every 15 min | `export-dependency-metrics.sh` | Dependency graph → Prometheus |
| `cloudflare-ddns` | Every 30 min | `cloudflare-ddns.sh` | Update DNS on IP change |
| `journal-logrotate` | Hourly | `rotate-journal-export.sh` | Keep journal logs under control |

### Daily

| Timer | Schedule | Script | Purpose |
|-------|----------|--------|---------|
| `daily-slo-snapshot` | 23:50 | `daily-slo-snapshot.sh` | Capture SLO metrics for trend analysis |
| `btrfs-backup-daily` | 02:00 | `btrfs-snapshot-backup.sh --local-only` | Local BTRFS snapshots |
| `predictive-maintenance-check` | 06:00 | Remediation: `predictive-maintenance` | Forecast resource exhaustion 7-14 days ahead |
| `daily-drift-check` | ~06:00 | `daily-drift-check.sh` | Config drift detection → digest |
| `dependency-discovery` | ~06:00 | `discover-dependencies.sh` | Map service dependencies from quadlets + networks |
| `daily-resource-forecast` | ~06:05 | `daily-resource-forecast.sh` | Predict disk/memory exhaustion → digest |
| `autonomous-operations` | 06:30 | `autonomous-execute.sh --from-check` | OODA loop ACT phase (with pre-check gate) |
| `auto-doc-update` | 07:00 | `auto-doc-orchestrator.sh` | Regenerate AUTO-*.md docs |
| `daily-error-digest` | ~07:00 | `daily-error-digest.sh` | Loki error aggregation → digest |
| `query-cache-refresh` | ~07:05 | `precompute-queries.sh` | Pre-compute query cache |
| `daily-morning-digest` | ~07:30 | `daily-morning-digest.sh` | Consolidated morning Discord notification |

### Weekly

| Timer | Schedule | Script | Purpose |
|-------|----------|--------|---------|
| `btrfs-backup-weekly` | Sat 04:00 | `btrfs-snapshot-backup.sh` | Sync snapshots to external drive |
| `podman-auto-update-weekly` | Sun 03:00 | `podman auto-update` (with pre/post health checks) | Container image updates |
| `database-maintenance` | Sun ~03:00 | Remediation: `database-maintenance` | PostgreSQL VACUUM, Redis analysis |
| `maintenance-cleanup` | Sun ~03:00 | `maintenance-cleanup.sh` | Prune containers, rotate logs |
| `vulnerability-scan` | Sun ~06:00 | `scan-vulnerabilities.sh --all --notify --quiet` | Trivy CVE scanning → Discord |
| `weekly-intelligence` | Fri 07:30 | `weekly-intelligence-report.sh` | End-of-week health summary → Discord |
| `check-image-updates` | Sun 10:00 | `check-image-updates.sh` | Check for available image updates |

### Monthly

| Timer | Schedule | Script | Purpose |
|-------|----------|--------|---------|
| `remediation-monthly-report` | 1st ~08:00 | `analytics/generate-monthly-report.sh` | Remediation effectiveness report |
| `monthly-slo-report` | 1st 10:00 | `monthly-slo-report.sh` | SLO compliance report → Discord |
| `monthly-skill-report` | 1st 10:30 | `analyze-skill-usage.sh --monthly-report` | Skill usage analytics |
| `backup-restore-test` | Last Sun 11:00 | `test-backup-restore.sh --verbose` | Backup integrity verification |

### Daily Execution Order

The daily automation follows a deliberate sequence:

```
23:50  daily-slo-snapshot       (capture yesterday's SLO data)
02:00  btrfs-backup-daily       (local snapshots while system quiet)
06:00  predictive-maintenance   (forecast before OODA loop)
06:00  daily-drift-check        (detect drift → write digest status)
06:00  dependency-discovery     (refresh dependency graph)
06:05  daily-resource-forecast  (resource predictions → write digest status)
06:30  autonomous-operations    (OODA ACT phase — pre-check gate, write digest status)
07:00  auto-doc-update          (regenerate docs with fresh data)
07:00  daily-error-digest       (last 24h error summary → write digest status)
07:05  query-cache-refresh      (pre-compute query cache with fresh data)
07:30  daily-morning-digest     (consolidated Discord notification)
```

---

## Scripts by Category

### System Health & Intelligence

| Script | Purpose | Notes |
|--------|---------|-------|
| `homelab-intel.sh` | Health scoring (0-100) + recommendations | JSON report, known-issues integration |
| `homelab-diagnose.sh` | Comprehensive diagnostics report | Timestamped output |
| `query-homelab.sh` | Natural language queries (cached) | Pre-computed by `precompute-queries.sh` |
| `recommend-skill.sh` | Intelligent skill recommendation | Terminal or JSON output |
| `survey.sh` | System inventory (BTRFS, firewall, versions) | |
| `show-pod-status.sh` | Container status with network/port info | |
| `collect-storage-info.sh` | Storage survey and diagnostics | |

### SLO Monitoring

| Script | Purpose | Notes |
|--------|---------|-------|
| `slo-status.sh` | Quick SLO compliance check | Terminal output |
| `monthly-slo-report.sh` | Full SLO compliance report | Timer: monthly, Discord |
| `daily-slo-snapshot.sh` | Capture daily SLO metrics to CSV | Timer: daily 23:50 |
| `analyze-slo-trends.sh` | Trend analysis and target calibration | Manual, uses snapshot CSV data |

### Autonomous Operations

| Script | Purpose | Notes |
|--------|---------|-------|
| `autonomous-check.sh` | OODA Observe+Orient+Decide (assessment only) | JSON with recommendations |
| `autonomous-execute.sh` | OODA Act phase (execute approved actions) | Timer: daily 06:30, safety controls |
| `analyze-impact.sh` | Blast radius / restart impact analysis | Used by autonomous-check.sh |
| `daily-drift-check.sh` | Config drift detection → digest | Timer: daily 06:00 |
| `daily-resource-forecast.sh` | Predict resource exhaustion → digest | Timer: daily 06:05 |
| `weekly-intelligence-report.sh` | Weekly health summary → Discord | Timer: Friday 07:30 |
| `daily-error-digest.sh` | Loki error aggregation → digest | Timer: daily 07:00 |
| `daily-morning-digest.sh` | Consolidated morning Discord notification | Timer: daily 07:30 |
| `catch-flapping-alert.sh` | Identify flapping alerts in Alertmanager | On-demand diagnostic |

### Update Workflow

Container updates follow a 6-step orchestrated workflow:

```
update-before-reboot.sh (orchestrator)
  ├─ 1. pre-update-snapshot.sh      → Capture system state to JSON
  ├─ 2. pre-update-health-check.sh  → Gate: disk, services, DB, memory
  ├─ 3. graceful-shutdown.sh        → 6-phase dependency-aware shutdown
  ├─ 4. podman pull / prune         → Update images, clean old layers
  └─ (after reboot)
      └─ post-reboot-verify.sh      → Compare against pre-update snapshot
          └─ post-update-health-check.sh → Verify services + NC DB upgrade

podman-auto-update-weekly.timer (Sunday 03:00)
  ├─ pre-update-health-check.sh (ExecStartPre)
  ├─ podman auto-update
  └─ post-update-health-check.sh (ExecStartPost)
```

| Script | Purpose | Notes |
|--------|---------|-------|
| `update-before-reboot.sh` | Orchestrator: snapshot → health → shutdown → pull | `--skip-pull`, `--dry-run` |
| `pre-update-snapshot.sh` | Capture containers/images state to JSON | Output: `data/update-snapshots/` |
| `pre-update-health-check.sh` | Pre-flight health gate (exit 1 = abort) | Checks disk, services, DB, memory |
| `graceful-shutdown.sh` | 6-phase dependency-aware container shutdown | `--dry-run` supported |
| `post-reboot-verify.sh` | Compare post-reboot state against snapshot | `--snapshot PATH` |
| `post-update-health-check.sh` | Post-update service verification + NC DB fix | Sends Discord notification |

### Backup & Storage

| Script | Purpose | Notes |
|--------|---------|-------|
| `btrfs-snapshot-backup.sh` | Create snapshots, sync to external drive | Timer: daily + weekly |
| `test-backup-restore.sh` | Validate backup integrity via restore test | Timer: monthly last Sunday |
| `collect-storage-info.sh` | Storage diagnostics | On-demand |
| `monitor-btrfs-transfer.sh` | Monitor btrfs send/receive progress | On-demand helper |
| `backup-pihole.sh` | Backup Pi-hole config to external drive | Manual |

### Security & Compliance

| Script | Purpose | Notes |
|--------|---------|-------|
| `security-audit.sh` | Comprehensive security audit (40+ checks) | On-demand |
| `scan-vulnerabilities.sh` | Trivy CVE scanning | Timer: weekly Sunday |
| `audit-configuration.sh` | ADR-016 compliance validation | On-demand |
| `verify-permissions.sh` | ADR-019 permission drift detection | Referenced by security-audit.sh |
| `verify-monitoring.sh` | Verify Prometheus targets + dashboards | Used by deployment verification |
| `verify-security-posture.sh` | Verify CrowdSec, TLS, headers, auth | Used by deployment verification |
| `sanitize-for-public.sh` | Prepare repo for public release | On-demand |
| `security/sync-ssh-keys.sh` | Sync authorized_keys to remote hosts | Manual, idempotent |

### Maintenance

| Script | Purpose | Notes |
|--------|---------|-------|
| `maintenance-cleanup.sh` | Prune containers, rotate logs, remediation log rotation | Timer: weekly Sunday |
| `clear-swap-memory.sh` | Clear swap under pressure | On-demand |
| `rotate-journal-export.sh` | Journal log rotation | Timer: hourly |
| `cloudflare-ddns.sh` | Update DNS when public IP changes | Timer: every 30 min |

### Documentation Generation

| Script | Purpose | Notes |
|--------|---------|-------|
| `auto-doc-orchestrator.sh` | Run all 4 generators (~2s) | Timer: daily 07:00 |
| `generate-service-catalog-simple.sh` | → AUTO-SERVICE-CATALOG.md | Called by orchestrator |
| `generate-network-topology.sh` | → AUTO-NETWORK-TOPOLOGY.md | Called by orchestrator |
| `generate-dependency-graph.sh` | → AUTO-DEPENDENCY-GRAPH.md | Called by orchestrator |
| `generate-doc-index.sh` | → AUTO-DOCUMENTATION-INDEX.md | Called by orchestrator |

### Dependency Mapping

| Script | Purpose | Notes |
|--------|---------|-------|
| `discover-dependencies.sh` | Map dependencies from quadlets + networks | Timer: daily 06:00 |
| `export-dependency-metrics.sh` | Export dependency graph → Prometheus | Timer: every 15 min |

### Service-Specific

| Script | Purpose |
|--------|---------|
| `jellyfin-manage.sh` | Jellyfin start/stop/restart/status/logs |
| `jellyfin-status.sh` | Quick Jellyfin status check |
| `traefik-entrypoint.sh` | Traefik container wrapper for secrets |
| `validate-traefik-config.sh` | Validate Traefik YAML syntax |
| `check-image-updates.sh` | Check for available container image updates |

### Analytics & Reporting

| Script | Purpose | Notes |
|--------|---------|-------|
| `analyze-skill-usage.sh` | Skill usage patterns and effectiveness | Timer: monthly 1st |
| `analytics/generate-monthly-report.sh` | Monthly remediation report | Timer: monthly 1st |
| `analytics/remediation-effectiveness.sh` | Playbook effectiveness scoring | Called by monthly report |
| `analytics/remediation-recommendations.sh` | Improvement recommendations | Called by monthly report |
| `analytics/remediation-roi.sh` | ROI calculations | Called by monthly report |
| `analytics/remediation-trends.sh` | Trend analysis over time | Called by monthly report |
| `write-remediation-metrics.sh` | Write remediation metrics → Prometheus | Called by apply-remediation.sh |

### Predictive Analytics

| Script | Purpose |
|--------|---------|
| `predictive-analytics/predict-resource-exhaustion.sh` | Forecast disk/memory exhaustion dates |
| `predictive-analytics/analyze-trends.sh` | Analyze historical resource trends |
| `predictive-analytics/generate-predictions-cache.sh` | Pre-compute predictions for caching |

---

## Deployment & Validation (Skill Scripts)

Located in `.claude/skills/homelab-deployment/scripts/`:

| Script | Purpose |
|--------|---------|
| `deploy-from-pattern.sh` | Deploy using 9 battle-tested patterns |
| `check-prerequisites.sh` | Validate environment before deployment |
| `check-drift.sh` | Compare running vs declared state |
| `check-system-health.sh` | Pre-deployment health gate |
| `validate-quadlet.sh` | Quadlet syntax validation |
| `validate-traefik-config.sh` | Traefik config validation |
| `deploy-service.sh` | Systemd operations orchestrator |
| `deploy-stack.sh` | Multi-service stack deployment |
| `test-deployment.sh` | Post-deployment verification |
| `verify-deployment.sh` | Full 7-level verification framework |
| `generate-docs.sh` | Auto-generate service documentation |
| `resolve-dependencies.sh` | Topological sort for stack ordering |

---

## Remediation Framework

Playbooks in `.claude/remediation/`, executed via `apply-remediation.sh`:

| Playbook | Risk | Purpose | Trigger |
|----------|------|---------|---------|
| `disk-cleanup` | Low | Prune containers, rotate logs, clean caches | Disk >75% |
| `service-restart` | Low | Restart failed/unhealthy services | Service down |
| `self-healing-restart` | Low | Smart restart with root cause detection | Service restart loop |
| `predictive-maintenance` | Low | Proactive cleanup based on forecasts | Timer: daily 06:00 |
| `drift-reconciliation` | Medium | Reconcile config drift, restart service | Drift detected |
| `resource-pressure` | Medium | Clear caches, mitigate memory/swap pressure | Swap >6GB |
| `database-maintenance` | Medium | PostgreSQL VACUUM, Redis analysis | Timer: weekly Sunday |

```bash
cd .claude/remediation/scripts
./apply-remediation.sh --list-playbooks           # List available
./apply-remediation.sh --playbook disk-cleanup --dry-run  # Test first
./apply-remediation.sh --playbook disk-cleanup     # Execute
```

---

## Known Issues Framework

Expected warnings documented in `~/.claude/context/known-issues.yml` to prevent alert fatigue:
- Warnings tagged with `[KNOWN ISSUE]` in `homelab-intel.sh`
- Weekly report escalates warnings persisting 7+ days
- Known issues don't reduce health score

---

## Skill Integration

| Skill | Scripts Used |
|-------|--------------|
| **homelab-intelligence** | `homelab-intel.sh`, `homelab-diagnose.sh`, `query-homelab.sh`, `predictive-analytics/` |
| **homelab-deployment** | All scripts in `.claude/skills/homelab-deployment/scripts/` |
| **systematic-debugging** | Uses diagnostic scripts indirectly via methodology |
| **autonomous-operations** | `autonomous-check.sh`, `autonomous-execute.sh`, `analyze-impact.sh` |
| **git-advanced-workflows** | No direct script integration |

---

## Archived Scripts

Scripts that have served their purpose are in `scripts/archived/`. See `scripts/archived/README.md` for the full inventory and restoration instructions.

**Latest archive (2026-02-27):** 22 scripts archived — one-off fixes, applied migrations, completed tests, and superseded tools.

---

## Adding New Automation

### New Script

Include this header:
```bash
#!/bin/bash
# script-name.sh — One-line description
# Usage: ./script-name.sh [options]
# Timer: timer-name.timer (if scheduled)
# Status: ACTIVE | DEPRECATED | ONE-TIME
```

### New Scheduled Timer

```bash
# ~/.config/systemd/user/my-task.timer
[Unit]
Description=My Scheduled Task Timer

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

```bash
systemctl --user daemon-reload
systemctl --user enable --now my-task.timer
```

---

## See Also

- `docs/20-operations/guides/backup-strategy.md` — Backup automation details
- `docs/20-operations/guides/autonomous-operations.md` — OODA loop framework
- `docs/40-monitoring-and-documentation/guides/slo-framework.md` — SLO monitoring
- `docs/40-monitoring-and-documentation/guides/loki-remediation-queries.md` — LogQL queries
- `.claude/skills/homelab-deployment/SKILL.md` — Deployment skill documentation
- `.claude/remediation/README.md` — Remediation framework documentation
