# Natural Language Query System - User Guide

**Created:** 2025-11-22
**Status:** ✅ Production-Ready
**Safety Audit:** [docs/99-reports/2025-11-22-query-system-safety-audit.md](../../99-reports/2025-11-22-query-system-safety-audit.md)

---

## Overview

The natural language query system lets you ask questions about your homelab in plain English and get instant, cached responses.

**Benefits:**
- ⚡ **Fast**: Responses in <1 second (cache hits)
- 🧠 **Smart**: Pattern-matching translates English to system commands
- 💾 **Cached**: Pre-computed results updated every 5 minutes
- 🔒 **Safe**: Thoroughly tested, no risk of system hangs

---

## Quick Start

### Basic Usage

```bash
~/containers/scripts/query-homelab.sh "What services are using the most memory?"
```

**Output:**
```
Top memory users:
     1  jellyfin: 1128MB
     2  immich-ml: 534MB
     3  immich-server: 516MB
     4  prometheus: 362MB
     5  grafana: 294MB
```

### Get JSON Output

```bash
~/containers/scripts/query-homelab.sh "Show me disk usage" --json
```

---

## Supported Query Patterns

### 1. Resource Usage

**Memory:**
```bash
# Top memory consumers
"What services are using the most memory?"
"Show me memory usage"
"Top memory users"
```

**CPU:**
```bash
# Top CPU consumers
"What's using the most CPU?"
"Show me CPU usage"
"Top CPU users"
```

**Disk:**
```bash
# Filesystem usage
"Show me disk usage"
"What's the disk usage?"
"Filesystem usage"
```

---

### 2. Service Status

**Specific service:**
```bash
# Check if a service is running
"Is jellyfin running?"
"Check status of traefik"
"Is prometheus up?"
```

**Current services:**
```bash
# List current service states (not restart history)
"Show me recent restarts"
"Service status"
```

---

### 3. Network Topology

**Network members:**
```bash
# See what's on a specific network
"What's on the reverse_proxy network?"
"Show me services on monitoring network"
"What services are on media_services?"
```

**Note:** Network names can be specified without the `systemd-` prefix.

---

### 4. Configuration

**Service configuration:**
```bash
# Get key config for a service
"What's jellyfin's configuration?"
"Show me prometheus settings"
"Traefik configuration"
```

**Output includes:**
- Container image
- Memory limit
- Networks
- (Read from quadlet file)

---

## Cache Management

### How Caching Works

The query system caches results with a Time-To-Live (TTL):

| Query Type | TTL | Freshness |
|------------|-----|-----------|
| Memory usage | 5 min | Current state |
| CPU usage | 5 min | Current state |
| Disk usage | 5 min | Rarely changes |
| Service status | Instant | No cache (live check) |
| Network members | 5 min | Rarely changes |
| Configuration | 5 min | Rarely changes |

### Pre-computed Queries

You can optionally set up automatic cache warming:

```bash
# Run manually
~/containers/scripts/precompute-queries.sh

# Or schedule via cron (every 5 minutes)
crontab -e
```

Add this line:
```cron
*/5 * * * * ~/containers/scripts/precompute-queries.sh >> ~/containers/data/query-cache.log 2>&1
```

**What gets pre-computed:**
- Top memory users
- Top CPU users
- Disk usage

**Benefits:**
- Instant responses even on first query
- Reduced load on system
- Cache always fresh

---

## Advanced Usage

### Cache Location

Cache stored at: `~/.claude/context/query-cache.json`

**View cache:**
```bash
cat ~/.claude/context/query-cache.json | jq '.'
```

**Clear cache:**
```bash
rm ~/.claude/context/query-cache.json
# Cache will rebuild on next query
```

### Query Patterns Database

Pattern definitions at: `~/.claude/context/query-patterns.json`

**View patterns:**
```bash
cat ~/.claude/context/query-patterns.json | jq '.patterns[] | {id, match, executor}'
```

This shows all supported question patterns and what commands they map to.

---

## Cache Pre-Computation

### Automated Cache Refresh

**Script:** `~/containers/scripts/precompute-queries.sh`

Common queries are automatically pre-computed every 5 minutes to ensure cache freshness:

**Pre-computed queries:**
- "What services are using the most memory?"
- "What's using the most CPU?"
- "Show me disk usage"
- Service health status (via direct executor)

**Cron setup:**
```bash
# Add to crontab
*/5 * * * * ~/containers/scripts/precompute-queries.sh >> ~/containers/data/query-cache.log 2>&1
```

**Benefits:**
- Queries complete in <1 second (cache hits)
- Reduced system load from fewer concurrent calls
- Autonomous operations can query without performance impact

**Monitoring:**
```bash
# Check cache update logs
tail -f ~/containers/data/query-cache.log

# Expected output:
# [2025-11-30 19:55:27] Pre-computing common queries...
#   - What services are using the most memory?
#     ✓ Cached successfully
#   - What's using the most CPU?
#     ✓ Cached successfully
#   - Show me disk usage
#     ✓ Cached successfully
#   - Direct executor: get_unhealthy_services
#     ✓ Cached successfully (unhealthy_services)
# [2025-11-30 19:55:28] Cache updated successfully
```

**Cache TTL:**
- Memory/CPU queries: 60 seconds
- Disk usage: 600 seconds (10 minutes)
- Service lists: 120 seconds

---

## Integration with Autonomous Operations

The query cache is used by `autonomous-check.sh` during the OBSERVE phase:

**Performance improvement:**
```bash
# Before cache integration
OBSERVE phase: 12-21 system calls, 3-5 seconds

# After cache integration (cache hit)
OBSERVE phase: ~7 system calls, 1-2 seconds
```

**How it works:**
1. autonomous-check.sh attempts to read cache
2. If cache fresh (age < TTL): Use cached data
3. If cache stale or missing: Fall back to direct system calls
4. Results are identical regardless of source

**Graceful degradation:**
- Cache failures don't break autonomous operations
- Direct calls are always available as fallback
- No special configuration required

**See:** `docs/20-operations/guides/autonomous-operations.md` for integration details

**Performance metrics:**
```json
{
  "cache_effectiveness": {
    "hit_rate": "95%",
    "system_call_reduction": "58%",
    "average_observe_time": "1.2s"
  }
}
```

---

## Integration with Skills

### Homelab Intelligence Skill

The query system is integrated with the `homelab-intelligence` skill.

**When to use:**
- **Query system**: Quick, specific questions ("Is jellyfin running?")
- **Full intel script**: Comprehensive health check, troubleshooting

**Example workflow:**
```
User: "What services are using the most memory?"
Claude: Uses query system (1s response)

User: "How is my homelab doing?"
Claude: Runs full intel script (comprehensive analysis)
```

---

## Troubleshooting

### Query Not Recognized

**Symptom:**
```
I don't understand that question.
Try asking:
  - What services are using the most memory?
  - Is jellyfin running?
  ...
```

**Solution:**
Your question doesn't match any pattern. Try:
1. Use one of the suggested phrasings
2. Check `--help` for supported patterns
3. View pattern database (see Advanced Usage)

### Slow Response (>5s)

**Symptom:** Query takes a long time despite caching.

**Possible causes:**
1. Cache expired and query needs to run fresh
2. System under load (heavy transcoding, backup running)

**Solution:**
- Enable pre-computation via cron to keep cache fresh
- Check system load: `uptime`

### Stale Data

**Symptom:** Results don't reflect recent changes.

**Cause:** Cache hasn't expired yet (5min TTL).

**Solution:**
```bash
# Clear cache to force fresh query
rm ~/.claude/context/query-cache.json

# Then re-run query
~/containers/scripts/query-homelab.sh "Your question"
```

---

## Safety Features

### Built-in Protections

1. **Timeout protection**: All queries timeout after 10 seconds
2. **Memory limits**: No dangerous operations (journalctl --grep removed)
3. **Read-only**: Query system never modifies system state
4. **Tested**: 100-iteration stress test passed, no memory leaks

### What Changed from Original Design

**Original (DANGEROUS):**
- Used `journalctl --grep` for restart history
- Could hang for 15+ seconds
- Risk of OOM on large journals

**Current (SAFE):**
- Uses `systemctl list-units` for service state
- Completes in <100ms
- No risk of system freeze

**Trade-off:**
- "Show me recent restarts" now shows **current service states** instead of restart history
- This is an acceptable trade-off for system stability

---

## Examples

### Example 1: Quick Service Check

```bash
$ ~/containers/scripts/query-homelab.sh "Is jellyfin running?"
jellyfin is running
```

### Example 2: Resource Analysis

```bash
$ ~/containers/scripts/query-homelab.sh "What services are using the most memory?"
Top memory users:
     1  jellyfin: 1128MB
     2  immich-ml: 534MB
     3  prometheus: 362MB
     4  grafana: 294MB
     5  loki: 156MB
```

### Example 3: Network Topology

```bash
$ ~/containers/scripts/query-homelab.sh "What's on the reverse_proxy network?"
Network members:
  traefik: 10.89.0.2/16
  jellyfin: 10.89.0.3/16
  authelia: 10.89.0.4/16
  grafana: 10.89.0.5/16
```

### Example 4: Configuration Check

```bash
$ ~/containers/scripts/query-homelab.sh "What's jellyfin's configuration?"
Configuration:
  service: jellyfin
  image: docker.io/jellyfin/jellyfin:latest
  memory_limit: 4G
  networks: systemd-reverse_proxy.network,systemd-media_services.network
```

---

## Performance

**Benchmark results** (from safety audit):

| Metric | Value |
|--------|-------|
| Avg query time | 80ms |
| Cache hit time | <100ms |
| Cache miss time | 1-2s |
| Memory overhead | 54MB temp (returns to baseline) |
| Stress test | 100 queries in 8s |

---

## Future Enhancements

Potential improvements (not yet implemented):

1. **Historical trends**: Track metrics over time
2. **Predictive queries**: "Will disk fill this week?"
3. **Alert integration**: "Show me active alerts"
4. **More patterns**: Support additional question types
5. **Performance metrics**: Response time tracking

---

## See Also

- **Safety Audit**: `docs/99-reports/2025-11-22-query-system-safety-audit.md`
- **Session 5C Plan**: `docs/99-reports/SESSION-5C-NATURAL-LANGUAGE-QUERIES-PLAN.md`
- **Homelab Intelligence Skill**: `.claude/skills/homelab-intelligence/SKILL.md`
- **CLAUDE.md**: Main homelab reference guide

---

**Questions or issues?** Check the safety audit report or review the script source code in `scripts/query-homelab.sh`.
