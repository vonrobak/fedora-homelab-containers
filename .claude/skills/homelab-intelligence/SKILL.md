# Homelab Intelligence Skill

**Purpose:** Gather comprehensive system intelligence, analyze health, and provide actionable recommendations for the homelab infrastructure.

**When to use:** When you need to understand current system state, diagnose issues, or provide recommendations for maintenance/improvements.

**Triggers:**
- User asks "how is the system?"
- User requests health check or diagnostics
- User mentions issues or performance concerns
- User asks specific questions about services, resources, or configuration
- Before making significant changes to the infrastructure
- Periodically for proactive monitoring

---

## Quick Query System (NEW: 2025-11-22)

**For specific questions, use the natural language query system first:**

```bash
~/containers/scripts/query-homelab.sh "Your question here"
```

**Supported query types:**
- **Resource usage**: "What services are using the most memory?", "Show me disk usage"
- **Service status**: "Is jellyfin running?", "Show me recent restarts"
- **Network topology**: "What's on the reverse_proxy network?"
- **Configuration**: "What's jellyfin's configuration?"

**Benefits:**
- ✅ Instant responses (<1s) from cache
- ✅ No need to run full intel script for simple questions
- ✅ Production-ready and safety-tested

**When to use query system vs full intel:**
- **Query system**: Specific, quick questions about current state
- **Full intel**: Comprehensive health assessment, troubleshooting, recommendations

---

## Instructions

When this skill is invoked, follow this workflow:

### Step 1: Run Intelligence Gathering

Execute the homelab intelligence script to collect current system state:

```bash
cd ~/containers
./scripts/homelab-intel.sh
```

**Note:** Script always generates JSON report in `docs/99-reports/intel-<timestamp>.json`

This will:
- Check system basics (uptime, SELinux, kernel updates)
- Analyze disk usage (system SSD and BTRFS pool)
- Verify all critical services are running
- Measure resource usage (memory, swap, load average)
- Check backup status (local logs, external drive, BTRFS snapshots)
- Verify SSL certificate validity (Let's Encrypt)
- Test monitoring stack health (Prometheus, Grafana, Loki via container exec)
- Assess network connectivity (internet reachability)

### Step 2: Analyze the Output

Read and parse the JSON output from the script. Pay special attention to:

**Critical Issues (Priority 1):**
- These require immediate action
- May indicate system instability or security concerns
- Examples: Services down, disk >80%, SELinux disabled, no internet

**Warnings (Priority 2):**
- Should be addressed soon
- May become critical if ignored
- Examples: Disk >70%, no recent backup, high memory usage

**Info Items:**
- Informational status updates
- Positive confirmations of healthy state
- Examples: All services running, monitoring healthy

**Health Score:**
- 90-100: Excellent health
- 75-89: Good health, minor issues
- 50-74: Degraded, needs attention
- 0-49: Critical state, immediate action required

### Step 3: Provide Context-Aware Recommendations

Based on the analysis, provide specific, actionable recommendations:

**For Critical Issues:**
1. Explain the impact of the issue
2. Provide step-by-step resolution
3. Reference relevant documentation in `docs/` if applicable
4. Mention related ADRs if architectural decisions are involved

**For Warnings:**
1. Explain when this might become critical
2. Suggest preventive actions
3. Provide commands to investigate further

**For General Health:**
1. Summarize overall system state
2. Highlight any trends (improving/degrading)
3. Suggest proactive improvements

### Step 4: Check for Patterns

Look for common patterns that might indicate deeper issues:

**Disk Space Issues:**
- Check if journal logs are growing (suggest rotation)
- Look for container layer accumulation (suggest pruning)
- Review backup log retention

**Service Issues:**
- Check if services failed after recent changes (review git log)
- Verify quadlet syntax if services won't start
- Check network connectivity for monitoring stack

**Resource Pressure:**
- High memory + swap = need to review container limits
- High CPU + Jellyfin = likely transcoding (normal)
- High disk I/O = check if backup is running

### Step 5: Reference Documentation

When providing recommendations, link to relevant documentation:

**Troubleshooting:**
- Service issues: Reference `CLAUDE.md` Troubleshooting Workflow section
- Disk issues: Reference `docs/20-operations/guides/storage-layout.md`
- Backup issues: Reference `docs/20-operations/guides/backup-strategy.md`

**Architecture Decisions:**
- If suggesting changes, check ADRs in `docs/*/decisions/`
- Reference `CLAUDE.md` ADR section for key decisions

**Service-Specific Issues:**
- Traefik: `docs/10-services/guides/traefik.md`
- Jellyfin: `docs/10-services/guides/jellyfin.md`
- Monitoring: `docs/40-monitoring-and-documentation/guides/monitoring-stack.md`

### Step 6: Suggest Follow-Up Actions

Based on findings, suggest next steps:

**If Health Score < 75:**
1. Run detailed diagnostics: `./scripts/homelab-diagnose.sh`
2. Review service logs: `journalctl --user -u <service>.service -n 100`
3. Check recent changes: `git log --oneline -10`

**If Backup Overdue:**
1. Check external drive: `df -h | grep WD-18TB`
2. Run manual backup: `./scripts/btrfs-snapshot-backup.sh`
3. Review backup logs

**If Disk Usage High:**
1. Identify large files: `du -sh ~/containers/data/* | sort -h`
2. Check journal size: `journalctl --user --disk-usage`
3. Review cleanup options from CLAUDE.md

---

## Example Workflow

**User:** "How is my homelab doing?"

**Claude Response:**

1. *(Runs intelligence script)*
2. *(Reads JSON output)*
3. *(Analyzes results)*

"I've run a comprehensive health check of your homelab. Here's the summary:

**Overall Health: 87/100** ✅ Healthy

**Good News:**
- All 12 services running normally
- SSL certificates valid (62 days until renewal)
- Monitoring stack (Prometheus, Grafana, Loki) fully operational
- Memory usage normal at 24%

**Warnings Found (2):**

1. **System SSD at 58% capacity** (W001)
   - Current: 75GB / 128GB used
   - Trend: +2% since last week
   - Recommendation: Review `journalctl --user --disk-usage` and consider rotating old logs
   - Reference: See CLAUDE.md "High Disk Usage" troubleshooting

2. **Backup slightly overdue** (I002)
   - Last backup: 9 days ago
   - Expected: Weekly (Sunday)
   - Recommendation: Verify external drive mounted and run `./scripts/btrfs-snapshot-backup.sh`
   - Reference: docs/20-operations/guides/backup-strategy.md

**Recommended Actions:**
1. [MEDIUM] Review disk usage and clean up old logs
2. [LOW] Run weekly backup when external drive is available

Would you like me to help with any of these items?"

---

## Common Scenarios

### Scenario 1: Critical Service Down

If intelligence script shows critical services failed:

1. Identify which service(s) failed
2. Check recent systemd journal: `journalctl --user -u <service>.service -n 50`
3. Look for error patterns (common: network, permissions, port conflicts)
4. Reference CLAUDE.md "Container Won't Start" troubleshooting
5. Suggest specific fix based on error

### Scenario 2: High Disk Usage

If system SSD >70%:

1. Run `du -sh ~/containers/data/* | sort -h` to identify culprits
2. Check journal size: `journalctl --user --disk-usage`
3. Suggest cleanup commands from CLAUDE.md "High Disk Usage"
4. Explain consequences if ignored (system may freeze at 100%)

### Scenario 3: Monitoring Stack Issues

If Prometheus/Grafana/Loki health checks fail:

1. Check each service individually: `systemctl --user status <service>.service`
2. Verify network connectivity (services must be on monitoring network)
3. Check datasource UIDs in Grafana provisioning
4. Reference docs/40-monitoring-and-documentation/guides/monitoring-stack.md

### Scenario 4: Everything Healthy

If health score >90 and no issues:

1. Acknowledge healthy state
2. Highlight any positive trends (e.g., disk usage stable, uptime high)
3. Suggest proactive actions (review Grafana dashboards, test backup restore)
4. Ask if user wants to work on planned improvements from docs/40-monitoring-and-documentation/journal/

---

## Integration with Other Skills

This skill works well with:

- **session-start-hook**: Run intelligence check at start of sessions for context
- **Documentation skills**: Reference findings when updating guides
- **Deployment skills**: Verify system health before/after deployments

---

## Output Format

Always structure your response as:

1. **Health Score & Status** (with emoji for visual clarity)
2. **Critical Issues** (if any - these are urgent)
3. **Warnings** (if any - these need attention)
4. **Positive Findings** (what's working well)
5. **Key Metrics** (uptime, resource usage, service count)
6. **Recommended Actions** (prioritized list)
7. **Offer to Help** (ask if user wants assistance with any item)

Keep responses concise but actionable. Always provide specific commands or file references.

---

## Notes

- **v2.0 improvements:** Always generates JSON output, improved monitoring health checks via `podman exec`, better backup detection (3 locations), smarter swap threshold
- JSON reports automatically saved to `~/containers/docs/99-reports/intel-<timestamp>.json`
- Script is safe to run frequently (no side effects, read-only operations)
- Health scoring algorithm: Start at 100, -20 for critical issues, -5 for warnings
- Exit codes: 0=healthy, 1=warning, 2=critical (useful for automation)
