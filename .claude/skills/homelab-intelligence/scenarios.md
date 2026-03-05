# Homelab Intelligence — Scenarios & Examples

Detailed scenarios for the homelab-intelligence skill. See [SKILL.md](SKILL.md) for the main workflow.

## Common Scenarios

### Scenario 1: Critical Service Down

When the intel script shows critical services failed:

1. Identify which service(s) failed from the JSON output
2. Check recent journal: `journalctl --user -u <service>.service -n 50`
3. Look for error patterns: network issues, permissions (`:Z` labels), port conflicts
4. Reference CLAUDE.md "Container Won't Start" troubleshooting
5. Check recent changes: `git log --oneline -10`

**Common root causes:**
- Quadlet syntax error after edit (fix: `systemctl --user daemon-reload`)
- Volume permission / SELinux context (fix: verify `:Z` labels)
- Network doesn't exist (fix: `podman network ls`)
- Port conflict (fix: `ss -tulnp | grep <port>`)

### Scenario 2: High Disk Usage

When system SSD >70%:

1. Identify culprits: `du -sh ~/containers/data/* | sort -h`
2. Check journal size: `journalctl --user --disk-usage`
3. Check container layers: `podman system df`
4. Review backup log retention: `du -sh ~/containers/data/backup-logs/`

**Cleanup commands:**
```bash
journalctl --user --vacuum-time=7d
podman system prune -f
find ~/containers/data/backup-logs/ -name "*.log" -mtime +30 -delete
```

**Escalation:** System may freeze at 100%. Warning at 75%, critical at 85%.

### Scenario 3: Monitoring Stack Issues

When Prometheus/Grafana/Loki health checks fail:

1. Check each service: `systemctl --user status {prometheus,grafana,loki}.service`
2. Verify monitoring network: `podman network inspect systemd-monitoring`
3. Test endpoints:
   - Prometheus: `podman exec prometheus wget -q -O- http://localhost:9090/-/healthy`
   - Grafana: `curl -f http://localhost:3000/api/health`
   - Loki: external monitoring only (distroless image, no shell)
4. Check scrape targets: http://localhost:9090/targets (via Traefik dashboard)

**Note:** Prometheus has no host port — access via container network or `podman exec`.

### Scenario 4: Everything Healthy

When health score >90 and no issues:

1. Acknowledge healthy state with key metrics
2. Highlight positive trends (stable disk, high uptime)
3. Suggest proactive actions:
   - Review Grafana dashboards for anomalies
   - Check SLO burn rates
   - Run `./scripts/check-drift.sh` for configuration drift
4. Mention any planned improvements from user priorities

## Context Framework Examples

### Querying Issue History

```bash
cd ~/containers/.claude/context/scripts

# Find past disk space issues and their resolutions
./query-issues.sh --category disk-space --status resolved

# Check deployment-related problems
./query-issues.sh --category deployment

# Recent issues across all categories
./query-issues.sh --last 30d
```

### Querying Deployment History

```bash
# How was a service originally deployed?
./query-deployments.sh --service jellyfin

# What pattern was used?
./query-deployments.sh --pattern monitoring-stack

# Recent deployments
./query-deployments.sh --last 7d
```

## Health Score Algorithm

- **Starting score:** 100
- **Critical issue:** -20 each (services down, disk >80%, SELinux disabled, no internet)
- **Warning:** -5 each (disk >70%, backup overdue, high memory, high swap)
- **Exit codes:** 0 = healthy (score >= 75), 1 = warning (50-74), 2 = critical (<50)

Score thresholds for response tone:
- **90-100:** "Excellent health" — brief summary, proactive suggestions
- **75-89:** "Good health" — note warnings, suggest preventive actions
- **50-74:** "Degraded" — prioritize fixes, explain escalation risks
- **<50:** "Critical" — immediate action required, step-by-step remediation
