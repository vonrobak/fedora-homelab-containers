---
name: homelab-intelligence
description: Comprehensive system health analysis with scoring and recommendations. Use when checking system state, diagnosing issues, monitoring resources, or before/after infrastructure changes.
---

# Homelab Intelligence

## Overview

Two-tier system intelligence: quick queries for specific questions, full assessment for comprehensive health analysis.

## Quick Query (Fast Path)

For specific questions, use the natural language query system:

```bash
~/containers/scripts/query-homelab.sh "Your question here"
```

Supports: resource usage, service status, network topology, configuration lookups. Cached responses in <1s.

**Use quick query when:** user asks a specific, narrow question about current state.
**Use full intel when:** user wants overall health, comprehensive diagnostics, or pre/post-change assessment.

## Full Intelligence Workflow

### Step 1: Gather

```bash
cd ~/containers && ./scripts/homelab-intel.sh
```

Checks: services, disk, memory, backups, certificates, monitoring health, network. Outputs JSON report to `docs/99-reports/intel-<timestamp>.json`.

### Step 2: Analyze

Parse the JSON output. Categorize findings:

| Priority | Threshold | Examples |
|----------|-----------|---------|
| Critical | Immediate action | Services down, disk >80%, SELinux disabled |
| Warning | Address soon | Disk >70%, backup overdue, high memory |
| Info | Healthy state | All services running, certs valid |

**Health Score:** 90-100 excellent, 75-89 good, 50-74 degraded, <50 critical.
Algorithm: Start at 100, -20 per critical, -5 per warning. Exit codes: 0=healthy, 1=warning, 2=critical.

### Step 3: Respond

Provide context-aware recommendations:

- **Critical:** Explain impact, step-by-step resolution, reference docs/ADRs
- **Warning:** Explain escalation risk, suggest preventive actions
- **Healthy:** Acknowledge, highlight trends, suggest proactive improvements

For deeper investigation, reference the `systematic-debugging` skill.

## Output Format

Structure every response as:

```
**Overall Health: XX/100** [status emoji]

**Critical Issues** (if any)
- Issue with impact and resolution steps

**Warnings** (if any)
- Warning with timeline and prevention

**Healthy Systems**
- Positive findings summary

**Key Metrics**
- Uptime, resource usage, container count

**Recommended Actions** (prioritized)
1. [HIGH/MEDIUM/LOW] Specific action with command

Would you like help with any of these items?
```

## Context Framework Integration

For historical awareness during troubleshooting:

```bash
# Check if problem has occurred before
~/containers/.claude/context/scripts/query-issues.sh --category disk-space
~/containers/.claude/context/scripts/query-issues.sh --status resolved

# Deployment history
~/containers/.claude/context/scripts/query-deployments.sh --service <name>
```

## Auto-Remediation

For common issues, use remediation playbooks:

```bash
~/containers/.claude/remediation/scripts/apply-remediation.sh --playbook disk-cleanup --dry-run
~/containers/.claude/remediation/scripts/apply-remediation.sh --playbook service-restart --service <name>
```

Available playbooks: `disk-cleanup`, `service-restart`, `drift-reconciliation`, `resource-pressure`

## Related Skills

- **systematic-debugging** — when issues require deeper root cause investigation
- **homelab-deployment** — verify health before/after deployments
- **autonomous-operations** — OODA loop for automated assessment

## Reference

- Detailed scenarios and examples: [scenarios.md](scenarios.md)
- Script catalog: `docs/20-operations/guides/automation-reference.md`
- SLO dashboard: `docs/40-monitoring-and-documentation/guides/slo-framework.md`
