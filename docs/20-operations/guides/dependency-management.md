# Service Dependency Management Guide

**Last Updated:** 2025-12-02
**Related:** ADR-006, autonomous-operations.md, drift-detection.md

## Overview

This guide covers the service dependency mapping system that automatically discovers, tracks, and monitors dependencies between containerized services.

## Quick Reference

```bash
# Discover dependencies (runs daily at 06:00 automatically)
~/containers/scripts/discover-dependencies.sh

# Check for drift
~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh --verbose

# Query dependencies
~/containers/scripts/query-homelab.sh "what depends on traefik?"
~/containers/scripts/query-homelab.sh "what does jellyfin depend on?"

# View blast radius
~/containers/scripts/query-homelab.sh "show blast radius"

# Export metrics manually
~/containers/scripts/export-dependency-metrics.sh

# View dashboard
# https://grafana.patriark.org/d/dependency-mapping
```

## Understanding Dependencies

### Dependency Types

**1. Runtime Dependencies** (`type: "runtime"`)
- Service must be running for this service to function
- Example: Jellyfin depends on reverse_proxy network
- Strength: HARD (Requires=) or SOFT (Wants=)

**2. Startup Dependencies** (`type: "startup"`)
- Service must start BEFORE this service
- Example: Authelia after reverse_proxy network
- Strength: SOFT (ordering only, not required)

**3. Routing Dependencies** (`type: "routing"`)
- Traefik routes traffic TO this service
- Example: traefik → jellyfin
- Strength: SOFT (can route without backend)

**4. Optional Dependencies** (`type: "optional"`)
- Service works better with this, but not required
- Strength: SOFT (Wants=)

### Dependency Strength

**HARD** (`"strength": "hard"`)
- Service CANNOT start without dependency
- Uses systemd Requires= directive
- Example: Container requires its networks

**SOFT** (`"strength": "soft"`)
- Service can start, may have degraded functionality
- Uses systemd After= or Wants= directive
- Example: Service after another for ordering

**OBSERVED** (`"strength": "observed"`)
- Detected from runtime TCP connections
- Not declared in quadlets
- Example: Service calling another's API

### Dependency Sources

1. **quadlet** - Declared in `.container` files (After=, Requires=, Wants=)
2. **networks** - Podman network membership
3. **tcp-connections** - Runtime TCP connections (nsenter + ss)
4. **traefik-router** - Traefik routing configuration

## Dependency Discovery

### Automatic Discovery

Dependencies are discovered automatically **daily at 06:00** via systemd timer:

```bash
# Check timer status
systemctl --user status dependency-discovery.timer

# View last run
journalctl --user -u dependency-discovery.service -n 50

# Check next run time
systemctl --user list-timers | grep dependency-discovery
```

### Manual Discovery

Run discovery manually after making changes:

```bash
cd ~/containers
./scripts/discover-dependencies.sh

# Show changes since last discovery
./scripts/discover-dependencies.sh --diff

# Verify dependencies
./scripts/discover-dependencies.sh --verify

# Specific source only
./scripts/discover-dependencies.sh --source quadlets
./scripts/discover-dependencies.sh --source networks
```

### Discovery Output

**Location:** `.claude/context/dependency-graph.json`

**Contents:**
- All services with their dependencies
- Network topology
- Blast radius calculations
- Critical service markings

**Example:**
```json
{
  "services": {
    "traefik": {
      "dependencies": [
        {"target": "reverse_proxy", "type": "runtime", "strength": "hard", "source": "quadlet"},
        {"target": "jellyfin", "type": "routing", "strength": "soft", "source": "traefik-router"}
      ],
      "dependents": ["ocis", "vaultwarden"],
      "blast_radius": 2,
      "critical": true
    }
  }
}
```

## Blast Radius

### What is Blast Radius?

**Definition:** Number of services that would be affected if this service fails.

**Calculation:** Count of direct dependents (services that depend on this one).

**Example:**
- Traefik has blast_radius: 9 (9 services route through it)
- Jellyfin has blast_radius: 0 (nothing depends on it)

### Viewing Blast Radius

**Command Line:**
```bash
# Show all blast radii
~/containers/scripts/query-homelab.sh "show blast radius"

# Specific service
jq '.services.traefik.blast_radius' ~/.claude/context/dependency-graph.json
```

**Dashboard:**
Navigate to https://grafana.patriark.org/d/dependency-mapping

Panels:
- "Top 10 Services by Blast Radius" - Bar chart
- "Blast Radius Heatmap" - Color-coded heatmap

### High Blast Radius Services

**Critical Services (blast_radius > 3):**
- **Traefik** - Reverse proxy for all external services
- **Authelia** - SSO authentication
- **Prometheus** - Metrics collection
- **Networks** - Shared infrastructure

**Handling High Blast Radius:**
- Extra caution when restarting
- Check dependents before changes
- Use cascade restart if safe (dep_safety_score >= 0.8)
- Monitor alerts: `HighBlastRadiusServiceDown`

## Dependency Drift

### What is Drift?

**Declared Dependencies:** What quadlet files say (intended architecture)
**Observed Dependencies:** What the system actually has (runtime + Traefik)

**Drift:** Mismatch between declared and observed.

### Types of Drift

**1. Undeclared Dependencies** (Observed but not declared)
```
⚠ WARNING: Undeclared dependencies detected
  Observed but not in quadlet:  jellyfin grafana prometheus
  These may be runtime connections or Traefik routes
```

**Causes:**
- Traefik routing (expected, informational)
- Runtime TCP connections (service-to-service calls)
- Manual container configuration

**Action:** Usually informational. Review if unexpected.

**2. Missing Dependencies** (Declared but not observed)
```
⚠ WARNING: Declared dependencies not observed
  In quadlet but not in graph:  old-service
  May be startup-only or inactive services
```

**Causes:**
- Service not currently running
- Startup-only dependency (not needed at runtime)
- Stale quadlet configuration

**Action:** Verify service state, update quadlet if needed.

### Checking for Drift

```bash
# Check all services
~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh --verbose

# Check specific service
~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh traefik --verbose

# Generate JSON report
~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh --json --output drift-report.json
```

### Drift Categories

- **✓ MATCH** - Configuration matches perfectly
- **✗ DRIFT** - Actual drift requiring reconciliation (restart service)
- **⚠ WARNING** - Minor differences (informational, dependency drift)

## Autonomous Operations Integration

### Dependency Safety Score

**Formula:**
```
dep_safety_score = 1.0
  - (blast_radius × 0.05)
  - (unhealthy_dependencies × 0.20)
  - (critical_service_down × 0.40)
```

**Range:** 0.0 (unsafe) to 1.0 (perfectly safe)

**Thresholds:**
- **>= 0.8** - Safe for cascade restart
- **0.5 - 0.8** - Moderate safety
- **< 0.5** - Risky, manual intervention recommended

### Confidence Formula Integration

Autonomous operations now use **5-parameter confidence**:
- prediction_confidence: 25% (was 30%)
- historical_success: 25% (was 30%)
- impact_certainty: 15% (was 20%)
- rollback_feasibility: 15% (was 20%)
- **dep_safety_score: 20%** (NEW)

**Impact:** Services with unhealthy dependencies or high blast radius get lower confidence scores, preventing risky automated actions.

### Cascade Restart Logic

**Trigger:** Service restart with dep_safety_score >= 0.8

**Behavior:**
1. Restart primary service
2. Wait 5 seconds for stabilization
3. Recursively restart dependents
4. Prevent infinite loops (cascade=false on recursive calls)

**Example:**
```bash
# Autonomous execute decides to restart jellyfin
# dep_safety_score = 0.95 (>= 0.8)
# Enables cascade restart
# Restarts jellyfin
# No dependents, cascade complete
```

## Metrics & Monitoring

### Prometheus Metrics

**Exported by:** `scripts/export-dependency-metrics.sh`
**Location:** `data/backup-metrics/dependency_metrics.prom`
**Scrape:** Node exporter textfile collector

**Metrics:**
1. `homelab_service_dependency_count{homelab_service, type}` - Deps per service
2. `homelab_service_dependent_count{homelab_service}` - Reverse deps
3. `homelab_service_blast_radius{homelab_service}` - Impact if fails
4. `homelab_dependency_health{homelab_service, dependency}` - Dep health (0/1)
5. `homelab_dependency_graph_staleness_seconds` - Time since last update
6. `homelab_dependency_drift_detected{homelab_service}` - Drift status (0/1)
7. `homelab_network_member_count{network}` - Services per network
8. `homelab_dependency_chain_depth{homelab_service}` - Max chain depth
9. `homelab_critical_service_status{homelab_service}` - Critical service up/down

### Prometheus Alerts

**File:** `config/prometheus/alerts/dependency-alerts.yml`

**Alerts:**
1. **CriticalServiceDependencyUnhealthy** (critical)
   - Trigger: Critical service has unhealthy dependency
   - Action: Investigate dependency immediately

2. **HighBlastRadiusServiceDown** (critical)
   - Trigger: Service with blast_radius > 3 is down
   - Action: Restart service, check dependents

3. **DependencyGraphStale** (warning)
   - Trigger: Graph not updated in 25 hours (>90000s)
   - Action: Check dependency-discovery.timer

4. **MediumBlastRadiusServiceDown** (warning)
   - Trigger: Service with blast_radius 2-3 is down
   - Action: Monitor dependents

### Grafana Dashboard

**URL:** https://grafana.patriark.org/d/dependency-mapping
**Title:** "Service Dependency Mapping"
**Panels:** 7

**Panels:**
1. Total Services (stat)
2. Total Dependencies (stat)
3. Graph Staleness (stat with thresholds)
4. Critical Services Running (stat)
5. Top 10 Services by Blast Radius (bar chart)
6. Blast Radius Heatmap (heatmap)
7. Dependency Health Matrix (table)
8. Network Topology Overview (table)

## Natural Language Queries

**Integration:** `scripts/query-homelab.sh`

**Patterns:**
```bash
# What does X depend on?
query-homelab.sh "what does jellyfin depend on?"

# What depends on X?
query-homelab.sh "what depends on traefik?"

# Show blast radius
query-homelab.sh "show blast radius"

# List critical services
query-homelab.sh "list critical services"

# Dependency health
query-homelab.sh "dependency health for traefik"

# Network members
query-homelab.sh "what services are on monitoring network?"

# Unhealthy dependencies
query-homelab.sh "show unhealthy dependencies"
```

## Troubleshooting

### Graph Not Updating

**Symptom:** Graph staleness > 24 hours

**Check:**
```bash
# Timer status
systemctl --user status dependency-discovery.timer

# Last execution
journalctl --user -u dependency-discovery.service -n 50

# Run manually
~/containers/scripts/discover-dependencies.sh
```

**Fix:**
```bash
# Restart timer
systemctl --user restart dependency-discovery.timer

# Force immediate discovery
~/containers/scripts/discover-dependencies.sh
```

### Metrics Not Appearing in Prometheus

**Check:**
```bash
# Metrics file exists
ls -lh ~/containers/data/backup-metrics/dependency_metrics.prom

# File is valid
head ~/containers/data/backup-metrics/dependency_metrics.prom

# Node exporter can read it
curl http://localhost:9100/metrics | grep homelab_service

# Prometheus scraping
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="node_exporter")'
```

**Fix:**
```bash
# Re-export metrics
~/containers/scripts/export-dependency-metrics.sh

# Check Prometheus logs
podman logs prometheus | grep -i dependency
```

### Drift Warnings for Expected Behavior

**Symptom:** Check-drift.sh shows warnings for Traefik routing

**Example:**
```
⚠ WARNING: Undeclared dependencies detected
  Observed but not in quadlet:  jellyfin grafana
  These may be runtime connections or Traefik routes
```

**Expected:** This is NORMAL. Traefik routing dependencies are discovered dynamically and won't be in quadlets.

**Action:** No action needed. This is informational.

### Missing Runtime Dependencies

**Symptom:** Expected TCP connection not discovered

**Causes:**
- Connection not ESTABLISHED when discovery ran
- Service not running
- Connection is UDP (not TCP)
- Connection is to external host (not container)

**Fix:**
```bash
# Ensure both services are running
podman ps | grep -E "service1|service2"

# Check connections manually
podman exec service1 ss -tn | grep ESTABLISHED

# Run discovery while services are active
~/containers/scripts/discover-dependencies.sh
```

## Best Practices

### When Adding New Services

1. **Declare dependencies in quadlet:**
   ```ini
   [Unit]
   After=reverse_proxy.network
   Requires=reverse_proxy.network
   Wants=authelia.service
   ```

2. **Run discovery after deployment:**
   ```bash
   ~/containers/scripts/discover-dependencies.sh
   ```

3. **Check for drift:**
   ```bash
   ~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh new-service --verbose
   ```

4. **Verify in dashboard:**
   - Navigate to Grafana dependency dashboard
   - Check new service appears
   - Verify blast radius is reasonable

### When Removing Services

1. **Check dependents first:**
   ```bash
   jq '.services."old-service".dependents' ~/.claude/context/dependency-graph.json
   ```

2. **Stop service:**
   ```bash
   systemctl --user stop old-service.service
   ```

3. **Remove quadlet:**
   ```bash
   rm ~/.config/containers/systemd/old-service.container
   systemctl --user daemon-reload
   ```

4. **Rediscover:**
   ```bash
   ~/containers/scripts/discover-dependencies.sh --diff
   ```

### When Troubleshooting Issues

1. **Check dependency health:**
   ```bash
   ~/containers/scripts/query-homelab.sh "dependency health for problematic-service"
   ```

2. **Review blast radius:**
   ```bash
   ~/containers/scripts/query-homelab.sh "show blast radius"
   ```

3. **Check for drift:**
   ```bash
   ~/containers/.claude/skills/homelab-deployment/scripts/check-drift.sh problematic-service --verbose
   ```

4. **Review Prometheus alerts:**
   ```bash
   curl http://localhost:9093/api/v2/alerts | jq '.[] | select(.labels.component=="dependencies")'
   ```

## Advanced Usage

### Custom Discovery Source

To add a new discovery source (e.g., Consul, etcd):

1. Add discovery function to `discover-dependencies.sh`:
   ```bash
   discover_custom_source() {
       # Your logic here
       echo '{"service": [{"target": "dep", "source": "custom"}]}'
   }
   ```

2. Call in `build_dependency_graph()`:
   ```bash
   local custom_deps=$(discover_custom_source)
   ```

3. Merge with existing:
   ```bash
   services=$(merge_custom_deps "$services" "$custom_deps")
   ```

4. Update metadata sources:
   ```json
   "sources": [..., "custom"]
   ```

### Dependency Graph API Queries

The dependency graph is JSON, so you can query it with jq:

```bash
# Find all services depending on a specific service
jq '.services | to_entries[] | select(.value.dependencies[]?.target == "traefik") | .key' ~/.claude/context/dependency-graph.json

# Services with no dependencies
jq '.services | to_entries[] | select(.value.dependencies | length == 0) | .key' ~/.claude/context/dependency-graph.json

# Services with blast radius > 5
jq '.services | to_entries[] | select(.value.blast_radius > 5) | "\(.key): \(.value.blast_radius)"' ~/.claude/context/dependency-graph.json

# Critical services that are down
jq '.services | to_entries[] | select(.value.critical == true) | .key' ~/.claude/context/dependency-graph.json
```

## References

- **ADR-006:** `docs/20-operations/decisions/2025-12-02-decision-006-service-dependency-mapping.md`
- **Discovery Script:** `scripts/discover-dependencies.sh`
- **Metrics Exporter:** `scripts/export-dependency-metrics.sh`
- **Drift Detection:** `.claude/skills/homelab-deployment/scripts/check-drift.sh`
- **Autonomous Integration:** `docs/20-operations/guides/autonomous-operations.md`
- **Grafana Dashboard:** https://grafana.patriark.org/d/dependency-mapping
- **Prometheus Alerts:** http://prometheus.patriark.org/alerts?search=dependency
