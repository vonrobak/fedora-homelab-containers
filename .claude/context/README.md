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

- **`system-profile.json`** - Current system state (20 services, 5 networks, hardware specs)
- **`issue-history.json`** - Historical issues (12 tracked, 7 resolved)
- **`deployment-log.json`** - Deployment history (20 services)
- **`preferences.yml`** - User preferences and risk tolerance (created in Session 4B)

### Scripts

- **`scripts/generate-system-profile.sh`** - Generate fresh system profile
- **`scripts/populate-issue-history.sh`** - Rebuild issue history
- **`scripts/build-deployment-log.sh`** - Rebuild deployment log
- **`scripts/query-issues.sh`** - Query issues by category/severity/status
- **`scripts/query-deployments.sh`** - Query deployments by service/pattern/method

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

## Statistics (as of 2025-11-18)

**System Profile:**
- Services: 20 running containers
- Networks: 5 (auth_services, media_services, monitoring, photos, reverse_proxy)
- System SSD: 84% used (critical)
- BTRFS Pool: 65% used

**Issue History:**
- Total issues: 12
- Resolved: 7
- Ongoing: 1
- Mitigated: 2
- Investigating: 2

**Deployment Log:**
- Total deployments: 20 services
- Pattern-based: 14 (70%)
- Manual quadlets: 2
- Deploy scripts: 1
- Multi-container: 2
- Custom scripts: 1

---

## Next Steps (Session 4B)

- [ ] Create auto-remediation playbooks
- [ ] Build remediation execution engine
- [ ] Enhance skills to use context
- [ ] Create user preferences file
- [ ] Test context-aware recommendations

---

**Maintainer:** patriark
**Status:** Active (Session 4A complete)
**Documentation:** See main Session 4 plan in `docs/99-reports/2025-11-15-session-4-hybrid-plan.md`
