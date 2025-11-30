# Context Framework

**Created:** 2025-11-18 (Session 4A)
**Purpose:** Persistent system knowledge base for Claude Skills

---

## Overview

The Context Framework provides Claude with **persistent memory** of your homelab system, enabling context-aware recommendations based on actual history rather than generic advice.

**Key Components:**
1. **System Profile** - Hardware, networks, services inventory
2. **Issue History** - Past problems and their resolutions
3. **Deployment Log** - Service deployment patterns and configurations
4. **Query Scripts** - Fast context lookups

---

## Files

### Data Files

**Session 4A - Core Context:**
- **`system-profile.json`** - Current system state (20 services, 5 networks, hardware specs)
- **`issue-history.json`** - Historical issues (12 tracked, 7 resolved)
- **`deployment-log.json`** - Deployment history (20 services)

**Session 4B - Preferences:**
- **`preferences.yml`** - User preferences, risk tolerance, deployment defaults

**Session 6 - Autonomous Operations:**
- **`autonomous-state.json`** - Autonomous operations state (circuit breaker, statistics, cooldowns)
- **`decision-log.json`** - Audit trail of autonomous decisions and actions

### Scripts

**Context Generation:**
- **`scripts/generate-system-profile.sh`** - Generate fresh system profile
- **`scripts/populate-issue-history.sh`** - Rebuild issue history
- **`scripts/build-deployment-log.sh`** - Rebuild deployment log

**Context Queries:**
- **`scripts/query-issues.sh`** - Query issues by category/severity/status
- **`scripts/query-deployments.sh`** - Query deployments by service/pattern/method
- **`scripts/query-decisions.sh`** - Query autonomous operations decision history (Session 6)

---

## Usage

### Querying Issues

```bash
cd .claude/context/scripts

# Find disk space issues
./query-issues.sh --category disk-space

# Find critical issues
./query-issues.sh --severity critical

# Find resolved issues
./query-issues.sh --status resolved

# Find ongoing issues
./query-issues.sh --status ongoing
```

**Available categories:** disk-space, deployment, authentication, scripting, monitoring, performance, ssl, media, architecture, operations

**Available severities:** critical, high, medium, low

**Available statuses:** resolved, ongoing, mitigated, investigating

### Querying Deployments

```bash
cd .claude/context/scripts

# Find specific service deployment
./query-deployments.sh --service jellyfin

# Find all monitoring stack deployments
./query-deployments.sh --pattern monitoring-stack

# Find pattern-based deployments
./query-deployments.sh --method pattern-based
```

**Available methods:** pattern-based, manual quadlet, deploy script, multi-container stack, custom script

### Querying Autonomous Decisions

```bash
cd .claude/context/scripts

# View last 10 decisions
./query-decisions.sh

# Last 7 days
./query-decisions.sh --last 7d

# Only failures
./query-decisions.sh --outcome failure

# Only executed actions
./query-decisions.sh --outcome success

# Statistics summary
./query-decisions.sh --stats
```

**Outcome types:** success, failure, skipped, queued

### Updating Context

```bash
cd .claude/context/scripts

# Regenerate system profile (hardware, services, networks)
./generate-system-profile.sh

# Rebuild issue history (run after documenting new issues)
./populate-issue-history.sh

# Rebuild deployment log (run after new deployments)
./build-deployment-log.sh
```

---

## Unified Context Directory (2025-12-01)

**Location:** `~/containers/.claude/context/` (all context files unified here)

All context data is now stored in a single location under version control:

**Session 5C - Natural Language Queries:**
- `query-cache.json` (12KB) - Pre-computed query results (TTL: 60-300s)
- `query-patterns.json` (6.5KB) - Pattern matching database (10 patterns)

**Session 5D - Skill Recommendations:**
- `task-skill-map.json` (7.2KB) - Maps task categories to skills
- `skill-usage.json` (1.7KB) - Tracks skill invocation and success rates

**Session 5B - Predictive Analytics:**
- `~/containers/data/predictions.json` - Resource exhaustion forecasts (separate location)

**Backward Compatibility:**
A symlink exists at `~/.claude/context/` → `~/containers/.claude/context/` for backward compatibility with external scripts.

**All scripts now use unified location:**
- `~/containers/scripts/query-homelab.sh` (Session 5C)
- `~/containers/scripts/recommend-skill.sh` (Session 5D)
- `~/containers/scripts/autonomous-check.sh` (Session 6)
- `~/containers/scripts/analyze-skill-usage.sh` (Session 5D)
- `~/containers/scripts/precompute-queries.sh` (Session 5C)

---

## Integration with Skills

### homelab-intelligence

```bash
# Example: Context-aware disk space warning
# Before: "Disk usage high. Consider cleaning up."
# After: "Disk at 84%. Last time (ISS-001), cleaned journal logs + pruned images = 12GB freed. Run same cleanup?"
```

### homelab-deployment

```bash
# Example: Deployment with memory
# Before: "Deploying Redis with default 2G memory"
# After: "Deploying Redis. Your cache-service pattern uses 256M (see redis-authelia, redis-immich). Using 256M."
```

### drift detection

```bash
# Example: Config drift auto-fix
# Before: "Drift detected in jellyfin. Manual reconciliation required."
# After: "Drift detected. Auto-reconciliation available from deployment-log. Fix? (y/n)"
```

---

## Data Schemas

### System Profile

```json
{
  "generated_at": "ISO8601 timestamp",
  "system": {
    "hostname": "string",
    "uptime_days": "number",
    "os": "string",
    "kernel": "string"
  },
  "hardware": {
    "cpu": { "model": "string", "cores": "number" },
    "memory": { "total_mb": "number", "available_mb": "number" },
    "gpu": { "model": "string", "driver": "string", "dri_devices": ["string"] },
    "storage": { "system_ssd": {}, "btrfs_pool": {} }
  },
  "networks": ["string"],
  "services": ["string"],
  "container_runtime": { "type": "podman", "rootless": true }
}
```

### Issue History

```json
{
  "generated_at": "ISO8601 timestamp",
  "total_issues": "number",
  "issues": [
    {
      "id": "ISS-XXX",
      "title": "string",
      "category": "disk-space|deployment|authentication|scripting|...",
      "severity": "critical|high|medium|low",
      "date_encountered": "YYYY-MM-DD",
      "description": "string",
      "resolution": "string",
      "outcome": "resolved|ongoing|mitigated|investigating"
    }
  ]
}
```

### Deployment Log

```json
{
  "generated_at": "ISO8601 timestamp",
  "total_deployments": "number",
  "deployments": [
    {
      "service": "string",
      "deployed_date": "YYYY-MM-DD",
      "pattern_used": "string",
      "memory_limit": "string",
      "networks": ["string"],
      "notes": "string",
      "deployment_method": "pattern-based|manual quadlet|..."
    }
  ]
}
```

---

## Maintenance

### Adding New Issues

Edit `scripts/populate-issue-history.sh` and add:

```bash
add_issue "ISS-XXX" \
    "Issue title" \
    "category" \
    "severity" \
    "YYYY-MM-DD" \
    "Description of what happened" \
    "How it was resolved" \
    "resolved|ongoing|mitigated|investigating"
```

Then run `./populate-issue-history.sh` to regenerate.

### Adding New Deployments

Edit `scripts/build-deployment-log.sh` and add:

```bash
add_deployment "service-name" \
    "YYYY-MM-DD" \
    "pattern-name" \
    "memory-limit" \
    "network1,network2" \
    "Deployment notes" \
    "deployment-method"
```

Then run `./build-deployment-log.sh` to regenerate.

---

## Statistics (as of 2025-11-30)

**System Profile:**
- Services: ~20 running containers
- Networks: 5 (auth_services, media_services, monitoring, photos, reverse_proxy)
- System SSD: 75% used (improved from 84%)
- BTRFS Pool: 77% used

**Issue History:**
- Total issues: 12 documented
- Resolved: 7
- Ongoing: 1
- Mitigated: 2
- Investigating: 2
- **Note:** Needs update - recent work not reflected

**Deployment Log:**
- Total deployments: 20 services (last updated 2025-11-22)
- Pattern-based: 14 (70%)
- **Note:** Needs update - recent deployments not logged

**Autonomous Operations:**
- Total checks: 11
- Total actions: 0
- Circuit breaker: Not triggered
- Success rate: 100% (no failures yet)

**Global Context (Sessions 5-6):**
- Query patterns: 10 implemented
- Query cache: 12KB (warm)
- Skill recommendations: 6 skills mapped to 8 categories
- Predictions: Active forecasting

---

## Integration Status

**Session 4 (Context Framework):**
- ✅ Core context files created and maintained
- ✅ Query scripts functional
- ⚠️ Manual updates required (not automated)

**Session 5C (Natural Language Queries):**
- ✅ Fully integrated with global context
- ✅ Used by autonomous operations for fast OBSERVE phase

**Session 5D (Skill Recommendations):**
- ✅ Implemented and functional
- ✅ Task-skill mapping active
- ✅ Usage analytics collecting data

**Session 6 (Autonomous Operations):**
- ✅ Uses preferences.yml for risk tolerance
- ✅ Maintains autonomous-state.json and decision-log.json
- ✅ Reads query-cache.json for performance
- ⚠️ Doesn't auto-update issue-history or deployment-log

---

## Known Gaps & Future Work

**Priority 1: Automate Context Updates**
- Deployment hooks to update deployment-log.json
- Autonomous operations should log resolved issues to issue-history.json
- Periodic refresh of system-profile.json (cron job)

**Priority 2: Improve Integration**
- Skills should query context for recommendations
- homelab-intelligence could reference issue-history for suggested fixes
- Drift detection could use deployment-log for auto-reconciliation

**Priority 3: Analytics & Insights**
- Visualize deployment patterns over time
- Track issue resolution effectiveness
- Correlate autonomous decisions with outcomes

---

**Maintainer:** patriark
**Status:** Active - Sessions 4, 5C, 5D, 6 complete
**Last Updated:** 2025-11-30
**Analysis:** See `docs/99-reports/2025-11-30-context-remediation-analysis.md`
