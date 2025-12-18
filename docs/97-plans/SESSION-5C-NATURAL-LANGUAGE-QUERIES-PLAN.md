# Session 5C: Natural Language Context Queries

**Status**: Ready for Implementation
**Priority**: MEDIUM-HIGH
**Estimated Effort**: 6-8 hours across 2-3 CLI sessions
**Dependencies**: Session 4 (Context Framework)
**Branch**: TBD (create `feature/natural-language-queries` during implementation)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Architecture Overview](#architecture-overview)
4. [Core Components](#core-components)
5. [Query Patterns](#query-patterns)
6. [Implementation Phases](#implementation-phases)
7. [Integration Points](#integration-points)
8. [Testing Strategy](#testing-strategy)
9. [Success Metrics](#success-metrics)
10. [Future Enhancements](#future-enhancements)

---

## Executive Summary

**What**: Natural language query engine that lets Claude skills answer conversational questions about your homelab using cached context and intelligent query translation.

**Why**:
- Current skills require exact commands (`podman ps`, `systemctl status`)
- Conversational queries are slow (Claude must figure out commands to run)
- Repeated questions waste time (no caching)
- Complex queries require multiple commands (memory-intensive)

**How**:
- Build query parser that understands question patterns
- Translate natural language to system commands
- Cache frequently asked questions in context framework
- Pre-compute common queries (service status, network topology, resource usage)

**Key Deliverables**:
- `scripts/query-homelab.sh` - Natural language query executor (500 lines)
- `.claude/context/query-cache.json` - Pre-computed query results
- `.claude/context/query-patterns.json` - Pattern matching database
- Updated homelab-intelligence skill with query integration
- `docs/40-monitoring-and-documentation/guides/natural-language-queries.md` - Usage guide

---

## Problem Statement

### Current State: Command-Based Interrogation

To answer questions about the homelab, Claude must:

1. **Determine what commands to run** (slow, token-intensive)
2. **Execute commands** (fast)
3. **Parse output** (sometimes error-prone)
4. **Synthesize answer** (more tokens)

**Example Interaction** (Current):
```
User: "What services are using the most memory?"

Claude thinks:
- Need to list all services: podman ps --format "{{.Names}}"
- For each service, get memory: podman stats --no-stream
- Parse output, sort by memory
- Format as human-readable response

[Executes 1 + N commands, uses 2000+ tokens]

Response: "Jellyfin (1.2GB), Prometheus (850MB), Grafana (320MB)..."
```

**Problems**:
- Slow (multiple tool calls)
- Token-heavy (thinking + execution + parsing)
- Not cacheable (commands run fresh each time)
- Doesn't scale (10 questions = 10 full command sequences)

---

### Desired State: Context-Aware Query Engine

**Example Interaction** (Desired):
```
User: "What services are using the most memory?"

Claude thinks:
- This matches query pattern: "resource_usage_top_n"
- Check query cache: Last updated 15 minutes ago (fresh)
- Return cached result

[0 commands executed, 100 tokens used]

Response: "Jellyfin (1.2GB), Prometheus (850MB), Grafana (320MB)...
(cached 15m ago)"
```

**Benefits**:
- Fast (cache hit = instant response)
- Token-efficient (no command execution overhead)
- Scalable (10 questions use same cache)
- Proactive (pre-compute common queries)

---

### Query Categories

We'll support 5 categories of queries:

1. **Service Status** - "Is Jellyfin running?", "What services are stopped?"
2. **Resource Usage** - "What's using the most memory?", "Disk usage?"
3. **Network Topology** - "What services are on reverse_proxy network?"
4. **Historical Events** - "When was Authelia last restarted?", "Recent errors?"
5. **Configuration** - "What's Jellyfin's memory limit?", "Where is config stored?"

---

## Architecture Overview

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER QUERY (Natural Language)                     │
│  "What services are using the most memory?"                          │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│            QUERY PARSER (scripts/query-homelab.sh)                   │
│                                                                      │
│  1. Tokenize query (extract keywords)                               │
│  2. Match against query patterns                                    │
│  3. Extract parameters (service name, resource type, etc.)          │
│  4. Generate query plan                                             │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│          QUERY PATTERNS (.claude/context/query-patterns.json)        │
│                                                                      │
│  {                                                                   │
│    "patterns": [                                                     │
│      {                                                               │
│        "id": "resource_usage_top_n",                                │
│        "match": ["memory", "using", "most"],                        │
│        "intent": "resource_usage",                                  │
│        "executor": "get_top_memory_users",                          │
│        "cache_key": "top_memory_users",                             │
│        "cache_ttl": 300                                             │
│      },                                                              │
│      {                                                               │
│        "id": "service_status_specific",                             │
│        "match": ["is", "{service}", "running"],                     │
│        "intent": "service_status",                                  │
│        "executor": "check_service_status",                          │
│        "parameters": ["service"]                                    │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│           CACHE CHECK (.claude/context/query-cache.json)             │
│                                                                      │
│  {                                                                   │
│    "top_memory_users": {                                            │
│      "timestamp": "2025-11-16T10:15:00Z",                           │
│      "ttl": 300,                                                     │
│      "result": {                                                     │
│        "services": [                                                 │
│          {"name": "jellyfin", "memory_mb": 1234},                   │
│          {"name": "prometheus", "memory_mb": 850},                  │
│          {"name": "grafana", "memory_mb": 320}                      │
│        ]                                                             │
│      }                                                               │
│    }                                                                 │
│  }                                                                   │
│                                                                      │
│  ┌──────────────────────────────────────┐                           │
│  │ Cache Hit?                           │                           │
│  │  YES → Return cached result          │                           │
│  │  NO  → Execute query, cache result   │                           │
│  └──────────────────────────────────────┘                           │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼ (Cache Miss)
┌─────────────────────────────────────────────────────────────────────┐
│              QUERY EXECUTOR (Bash Functions)                         │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ get_top_memory_users()                                       │  │
│  │   podman stats --no-stream --format json                     │  │
│  │   | jq 'sort_by(.MemUsage) | reverse | .[0:5]'              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ check_service_status(service_name)                           │  │
│  │   systemctl --user is-active "$service_name.service"         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ get_network_members(network_name)                            │  │
│  │   podman network inspect "$network_name"                     │  │
│  │   | jq -r '.plugins[0].ipam.ranges[0][] | .container_id'    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              RESPONSE FORMATTER                                      │
│                                                                      │
│  Convert JSON to human-readable format:                             │
│  "Top memory users:                                                 │
│   1. Jellyfin: 1.2GB                                                │
│   2. Prometheus: 850MB                                              │
│   3. Grafana: 320MB                                                 │
│   (cached 15m ago)"                                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    RETURN TO CLAUDE SKILL                            │
│  homelab-intelligence skill receives formatted response             │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

1. **Query Parser** - Pattern matching engine (keyword-based NLP)
2. **Query Patterns Database** - JSON mapping questions → executors
3. **Query Cache** - Pre-computed results with TTL
4. **Query Executors** - Bash functions that run actual commands
5. **Response Formatter** - Human-readable output generator

---

## Core Components

### Component 1: Query Parser

**File**: `scripts/query-homelab.sh`

**Purpose**: Parse natural language queries and route to executors.

**Usage**:
```bash
# Direct CLI usage
./scripts/query-homelab.sh "What services are using the most memory?"

# Integration with homelab-intelligence skill
# (Skill calls this script with user's question)
```

**Implementation** (500 lines):
```bash
#!/bin/bash
# scripts/query-homelab.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/.claude/context"
PATTERNS_FILE="$CONTEXT_DIR/query-patterns.json"
CACHE_FILE="$CONTEXT_DIR/query-cache.json"

# Initialize cache if not exists
init_cache() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        echo '{}' > "$CACHE_FILE"
    fi
}

# Tokenize query (lowercase, extract keywords)
tokenize_query() {
    local query="$1"

    # Convert to lowercase, split on whitespace
    echo "$query" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n'
}

# Match query against patterns
match_pattern() {
    local query="$1"
    local tokens=$(tokenize_query "$query")

    # Load patterns
    local patterns=$(jq -r '.patterns[] | @json' "$PATTERNS_FILE")

    # For each pattern, check if all keywords match
    while IFS= read -r pattern_json; do
        local pattern_id=$(echo "$pattern_json" | jq -r '.id')
        local keywords=$(echo "$pattern_json" | jq -r '.match[]')

        local match_count=0
        local keyword_count=$(echo "$keywords" | wc -l)

        # Check if all keywords present in query
        while IFS= read -r keyword; do
            if echo "$tokens" | grep -q "^${keyword}$"; then
                ((match_count++)) || true
            fi
        done <<< "$keywords"

        # If all keywords matched, return pattern
        if (( match_count == keyword_count )); then
            echo "$pattern_json"
            return 0
        fi
    done <<< "$patterns"

    # No match found
    return 1
}

# Extract parameters from query (e.g., service name)
extract_parameters() {
    local query="$1"
    local pattern="$2"

    # Get parameter names from pattern
    local params=$(echo "$pattern" | jq -r '.parameters[]? // empty')

    if [[ -z "$params" ]]; then
        echo '{}'
        return
    fi

    # Extract service name (simplistic - match against known services)
    if echo "$params" | grep -q "service"; then
        local services=$(podman ps --format "{{.Names}}")
        local matched_service=""

        while IFS= read -r service; do
            if echo "$query" | grep -iq "$service"; then
                matched_service="$service"
                break
            fi
        done <<< "$services"

        if [[ -n "$matched_service" ]]; then
            echo "{\"service\": \"$matched_service\"}"
        else
            echo '{}'
        fi
    else
        echo '{}'
    fi
}

# Check cache for result
check_cache() {
    local cache_key="$1"

    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    local cached=$(jq -r ".\"${cache_key}\" // null" "$CACHE_FILE")

    if [[ "$cached" == "null" ]]; then
        return 1
    fi

    # Check TTL
    local timestamp=$(echo "$cached" | jq -r '.timestamp')
    local ttl=$(echo "$cached" | jq -r '.ttl')
    local current_time=$(date +%s)
    local cached_time=$(date -d "$timestamp" +%s)

    if (( current_time - cached_time > ttl )); then
        # Cache expired
        return 1
    fi

    # Return cached result
    echo "$cached" | jq -r '.result'
    return 0
}

# Update cache
update_cache() {
    local cache_key="$1"
    local result="$2"
    local ttl="${3:-300}"  # Default 5 minutes

    local cached_entry=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "ttl": $ttl,
  "result": $result
}
EOF
)

    # Update cache file
    local updated_cache=$(jq ".\"${cache_key}\" = $cached_entry" "$CACHE_FILE")
    echo "$updated_cache" > "$CACHE_FILE"
}

# Execute query
execute_query() {
    local executor="$1"
    local parameters="$2"

    case "$executor" in
        get_top_memory_users)
            get_top_memory_users
            ;;
        get_top_cpu_users)
            get_top_cpu_users
            ;;
        check_service_status)
            local service=$(echo "$parameters" | jq -r '.service')
            check_service_status "$service"
            ;;
        get_network_members)
            local network=$(echo "$parameters" | jq -r '.network')
            get_network_members "$network"
            ;;
        get_disk_usage)
            get_disk_usage
            ;;
        get_recent_restarts)
            get_recent_restarts
            ;;
        get_service_config)
            local service=$(echo "$parameters" | jq -r '.service')
            get_service_config "$service"
            ;;
        *)
            echo "Unknown executor: $executor" >&2
            return 1
            ;;
    esac
}

# ==================== QUERY EXECUTORS ====================

# Get top 5 memory users
get_top_memory_users() {
    podman stats --no-stream --format json 2>/dev/null \
        | jq -r 'sort_by(.mem_usage | rtrimstr("MiB") | tonumber) | reverse | .[0:5] | map({name: .name, memory_mb: (.mem_usage | rtrimstr("MiB") | tonumber)}) | @json'
}

# Get top 5 CPU users
get_top_cpu_users() {
    podman stats --no-stream --format json 2>/dev/null \
        | jq -r 'sort_by(.cpu_percent | rtrimstr("%") | tonumber) | reverse | .[0:5] | map({name: .name, cpu_pct: (.cpu_percent | rtrimstr("%") | tonumber)}) | @json'
}

# Check if service is running
check_service_status() {
    local service="$1"

    if systemctl --user is-active "$service.service" >/dev/null 2>&1; then
        echo "{\"service\": \"$service\", \"status\": \"running\"}"
    else
        echo "{\"service\": \"$service\", \"status\": \"stopped\"}"
    fi
}

# Get members of a network
get_network_members() {
    local network="$1"

    podman network inspect "systemd-${network}" 2>/dev/null \
        | jq -r '.[0].containers | to_entries | map({service: .value.name, ip: .value.ipv4_address}) | @json'
}

# Get disk usage summary
get_disk_usage() {
    local root_usage=$(df -h / | tail -1 | awk '{print $5}')
    local btrfs_usage=$(df -h /mnt/btrfs-pool | tail -1 | awk '{print $5}')

    cat <<EOF
{
  "filesystems": [
    {"mount": "/", "usage_pct": "${root_usage}"},
    {"mount": "/mnt/btrfs-pool", "usage_pct": "${btrfs_usage}"}
  ]
}
EOF
}

# Get recent service restarts (last 7 days)
get_recent_restarts() {
    journalctl --user --since "7 days ago" --output json \
        | jq -r 'select(.MESSAGE | contains("Started")) | {service: .UNIT, timestamp: .SYSTEMD_UNIT}' \
        | jq -s 'unique_by(.service) | sort_by(.timestamp) | reverse | .[0:10] | @json'
}

# Get service configuration
get_service_config() {
    local service="$1"

    # Get quadlet file path
    local quadlet="$HOME/.config/containers/systemd/${service}.container"

    if [[ ! -f "$quadlet" ]]; then
        echo "{\"error\": \"Quadlet not found for service: $service\"}"
        return 1
    fi

    # Extract key config
    local memory_limit=$(grep "^Memory=" "$quadlet" | cut -d= -f2)
    local networks=$(grep "^Network=" "$quadlet" | cut -d= -f2 | tr '\n' ',' | sed 's/,$//')
    local image=$(grep "^Image=" "$quadlet" | cut -d= -f2)

    cat <<EOF
{
  "service": "$service",
  "image": "$image",
  "memory_limit": "${memory_limit:-unlimited}",
  "networks": "${networks}"
}
EOF
}

# ==================== RESPONSE FORMATTERS ====================

# Format result as human-readable text
format_response() {
    local executor="$1"
    local result="$2"
    local from_cache="${3:-false}"

    local cache_note=""
    if [[ "$from_cache" == "true" ]]; then
        cache_note=" (cached)"
    fi

    case "$executor" in
        get_top_memory_users)
            echo "Top memory users${cache_note}:"
            echo "$result" | jq -r '.[] | "\(.name): \(.memory_mb)MB"' | nl
            ;;
        get_top_cpu_users)
            echo "Top CPU users${cache_note}:"
            echo "$result" | jq -r '.[] | "\(.name): \(.cpu_pct)%"' | nl
            ;;
        check_service_status)
            local service=$(echo "$result" | jq -r '.service')
            local status=$(echo "$result" | jq -r '.status')
            echo "${service} is ${status}"
            ;;
        get_network_members)
            echo "Network members${cache_note}:"
            echo "$result" | jq -r '.[] | "\(.service): \(.ip)"' | nl
            ;;
        get_disk_usage)
            echo "Disk usage${cache_note}:"
            echo "$result" | jq -r '.filesystems[] | "\(.mount): \(.usage_pct)"'
            ;;
        get_recent_restarts)
            echo "Recent restarts (last 7 days)${cache_note}:"
            echo "$result" | jq -r '.[] | "\(.service) - \(.timestamp)"' | nl
            ;;
        get_service_config)
            echo "Configuration${cache_note}:"
            echo "$result" | jq -r 'to_entries | .[] | "\(.key): \(.value)"'
            ;;
        *)
            echo "$result"
            ;;
    esac
}

# ==================== MAIN LOGIC ====================

main() {
    local query="$1"

    init_cache

    # Match query pattern
    local pattern=$(match_pattern "$query")

    if [[ -z "$pattern" ]]; then
        echo "I don't understand that question. Try:"
        echo "  - What services are using the most memory?"
        echo "  - Is jellyfin running?"
        echo "  - What's on the reverse_proxy network?"
        echo "  - Show me disk usage"
        return 1
    fi

    # Extract pattern details
    local executor=$(echo "$pattern" | jq -r '.executor')
    local cache_key=$(echo "$pattern" | jq -r '.cache_key // ""')
    local cache_ttl=$(echo "$pattern" | jq -r '.cache_ttl // 300')

    # Extract parameters
    local parameters=$(extract_parameters "$query" "$pattern")

    # Check cache
    local result=""
    local from_cache=false

    if [[ -n "$cache_key" ]]; then
        if result=$(check_cache "$cache_key"); then
            from_cache=true
        fi
    fi

    # Execute if cache miss
    if [[ "$from_cache" == "false" ]]; then
        result=$(execute_query "$executor" "$parameters")

        # Update cache
        if [[ -n "$cache_key" ]]; then
            update_cache "$cache_key" "$result" "$cache_ttl"
        fi
    fi

    # Format and output
    format_response "$executor" "$result" "$from_cache"
}

# Run
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 \"Your question here\""
    exit 1
fi

main "$*"
```

---

### Component 2: Query Patterns Database

**File**: `.claude/context/query-patterns.json`

**Purpose**: Map natural language patterns to query executors.

**Structure**:
```json
{
  "patterns": [
    {
      "id": "resource_usage_memory_top",
      "description": "Find services using most memory",
      "match": ["memory", "using", "most"],
      "match_any": ["service", "container", "process"],
      "intent": "resource_usage",
      "executor": "get_top_memory_users",
      "cache_key": "top_memory_users",
      "cache_ttl": 300,
      "examples": [
        "What services are using the most memory?",
        "Show me top memory users",
        "Which containers use the most RAM?"
      ]
    },
    {
      "id": "resource_usage_cpu_top",
      "description": "Find services using most CPU",
      "match": ["cpu", "using", "most"],
      "intent": "resource_usage",
      "executor": "get_top_cpu_users",
      "cache_key": "top_cpu_users",
      "cache_ttl": 60,
      "examples": [
        "What's using the most CPU?",
        "Show me top CPU users"
      ]
    },
    {
      "id": "service_status_specific",
      "description": "Check if specific service is running",
      "match": ["is", "{service}", "running"],
      "match_any": ["status", "up", "active"],
      "intent": "service_status",
      "executor": "check_service_status",
      "parameters": ["service"],
      "cache_ttl": 60,
      "examples": [
        "Is jellyfin running?",
        "Is traefik up?",
        "Check status of authelia"
      ]
    },
    {
      "id": "network_topology_members",
      "description": "List services on a network",
      "match": ["network", "{network}"],
      "match_any": ["on", "in", "members"],
      "intent": "network_topology",
      "executor": "get_network_members",
      "parameters": ["network"],
      "cache_key": "network_{network}",
      "cache_ttl": 600,
      "examples": [
        "What's on the reverse_proxy network?",
        "Show me services on monitoring network",
        "List members of auth_services network"
      ]
    },
    {
      "id": "disk_usage_summary",
      "description": "Show disk usage for all filesystems",
      "match": ["disk", "usage"],
      "match_any": ["space", "storage", "filesystem"],
      "intent": "resource_usage",
      "executor": "get_disk_usage",
      "cache_key": "disk_usage",
      "cache_ttl": 600,
      "examples": [
        "Show me disk usage",
        "How much disk space is left?",
        "What's the filesystem usage?"
      ]
    },
    {
      "id": "historical_restarts",
      "description": "Show recent service restarts",
      "match": ["restart", "recent"],
      "match_any": ["when", "last", "history"],
      "intent": "historical_events",
      "executor": "get_recent_restarts",
      "cache_key": "recent_restarts",
      "cache_ttl": 300,
      "examples": [
        "When was jellyfin last restarted?",
        "Show me recent restarts",
        "Which services restarted recently?"
      ]
    },
    {
      "id": "service_config_details",
      "description": "Get configuration for a service",
      "match": ["config", "{service}"],
      "match_any": ["configuration", "settings", "limits"],
      "intent": "configuration",
      "executor": "get_service_config",
      "parameters": ["service"],
      "cache_ttl": 3600,
      "examples": [
        "What's jellyfin's configuration?",
        "Show me prometheus settings",
        "What's the memory limit for grafana?"
      ]
    }
  ]
}
```

**Pattern Matching Algorithm**:
1. Tokenize query (lowercase, split on whitespace)
2. For each pattern:
   - Check if all required keywords (match[]) are present
   - Check if at least one optional keyword (match_any[]) is present
   - Extract parameters ({service}, {network})
3. Return first matching pattern (order matters - specific before general)

---

### Component 3: Query Cache

**File**: `.claude/context/query-cache.json`

**Purpose**: Store pre-computed query results with TTL.

**Structure**:
```json
{
  "top_memory_users": {
    "timestamp": "2025-11-16T10:15:00Z",
    "ttl": 300,
    "result": [
      {"name": "jellyfin", "memory_mb": 1234},
      {"name": "prometheus", "memory_mb": 850},
      {"name": "grafana", "memory_mb": 320}
    ]
  },
  "disk_usage": {
    "timestamp": "2025-11-16T10:10:00Z",
    "ttl": 600,
    "result": {
      "filesystems": [
        {"mount": "/", "usage_pct": "67%"},
        {"mount": "/mnt/btrfs-pool", "usage_pct": "45%"}
      ]
    }
  }
}
```

**Cache Invalidation**:
- TTL-based (each entry has expiration time)
- Manual invalidation: `rm ~/.claude/context/query-cache.json`
- Automatic refresh via cron (pre-compute common queries)

---

### Component 4: Pre-Compute Script

**File**: `scripts/precompute-queries.sh`

**Purpose**: Proactively execute common queries and cache results.

**Usage**:
```bash
# Manually refresh cache
./scripts/precompute-queries.sh

# Add to crontab (every 5 minutes)
*/5 * * * * ~/fedora-homelab-containers/scripts/precompute-queries.sh
```

**Implementation** (100 lines):
```bash
#!/bin/bash
# scripts/precompute-queries.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pre-compute common queries
queries=(
    "What services are using the most memory?"
    "What's using the most CPU?"
    "Show me disk usage"
    "Show me recent restarts"
)

echo "Pre-computing common queries..."

for query in "${queries[@]}"; do
    echo "  - $query"
    "$SCRIPT_DIR/query-homelab.sh" "$query" > /dev/null 2>&1 || true
done

echo "Cache updated: $(date)"
```

---

## Query Patterns

### Pattern 1: Resource Usage Queries

**Examples**:
- "What services are using the most memory?"
- "Show me top CPU users"
- "Which containers use the most disk?"

**Executor**: `get_top_memory_users`, `get_top_cpu_users`

**Cache**: 5 minutes (frequent changes)

---

### Pattern 2: Service Status Queries

**Examples**:
- "Is jellyfin running?"
- "Check status of traefik"
- "What services are stopped?"

**Executor**: `check_service_status`, `list_stopped_services`

**Cache**: 1 minute (status changes quickly)

---

### Pattern 3: Network Topology Queries

**Examples**:
- "What's on the reverse_proxy network?"
- "Show me all services on monitoring network"
- "List members of auth_services"

**Executor**: `get_network_members`

**Cache**: 10 minutes (network topology stable)

---

### Pattern 4: Historical Event Queries

**Examples**:
- "When was jellyfin last restarted?"
- "Show me recent errors for authelia"
- "What happened yesterday?"

**Executor**: `get_recent_restarts`, `get_recent_errors`

**Cache**: 5 minutes (history doesn't change, but queries are expensive)

---

### Pattern 5: Configuration Queries

**Examples**:
- "What's jellyfin's memory limit?"
- "Show me prometheus configuration"
- "Where is authelia config stored?"

**Executor**: `get_service_config`

**Cache**: 1 hour (config rarely changes)

---

## Implementation Phases

### Phase 1: Query Parser & Basic Patterns (3-4 hours)

**Session 5C-1: Core Query Engine**

**Tasks**:
1. Create `scripts/query-homelab.sh` (500 lines)
   - Tokenization logic
   - Pattern matching algorithm
   - Cache management
   - Response formatting

2. Create `.claude/context/query-patterns.json`
   - Define 7-10 initial patterns
   - Cover all 5 query categories
   - Include examples for testing

3. Create `.claude/context/query-cache.json` (empty initially)

4. Test pattern matching:
   ```bash
   # Test all example queries
   ./scripts/query-homelab.sh "What services are using the most memory?"
   ./scripts/query-homelab.sh "Is jellyfin running?"
   ./scripts/query-homelab.sh "Show me disk usage"
   ```

**Success Criteria**:
- ✅ All example queries match correct pattern
- ✅ Executors run without errors
- ✅ Output is human-readable
- ✅ Cache populates correctly

**Deliverables**:
- `scripts/query-homelab.sh` (executable)
- `.claude/context/query-patterns.json`
- Test results document

---

### Phase 2: Query Executors (2-3 hours)

**Session 5C-2: Implement All Executors**

**Tasks**:
1. Implement remaining executors:
   - `get_top_memory_users` ✅
   - `get_top_cpu_users` ✅
   - `check_service_status` ✅
   - `get_network_members` ✅
   - `get_disk_usage` ✅
   - `get_recent_restarts` ✅
   - `get_service_config` ✅
   - `list_all_services`
   - `get_service_logs`
   - `get_prometheus_metrics`

2. Add error handling:
   - Service doesn't exist
   - Network not found
   - No data available

3. Optimize performance:
   - Cache expensive queries (journalctl searches)
   - Use `--no-stream` for podman stats
   - Limit result sets (top 10, not all)

**Success Criteria**:
- ✅ All executors return valid JSON
- ✅ Error cases handled gracefully
- ✅ Queries complete in <2 seconds
- ✅ Results are accurate

**Deliverables**:
- Updated `scripts/query-homelab.sh` with all executors
- Performance benchmark results

---

### Phase 3: Integration & Pre-Compute (1-2 hours)

**Session 5C-3: Skill Integration**

**Tasks**:
1. Update `homelab-intelligence` skill:
   ```markdown
   <!-- In .claude/skills/homelab-intelligence/skill.md -->

   ## Natural Language Queries

   When the user asks a question about the homelab, ALWAYS try the query engine first:

   1. Run: `scripts/query-homelab.sh "$USER_QUESTION"`
   2. If successful, return the formatted response
   3. If query not understood, fall back to manual tool use

   This approach is:
   - ✅ Faster (cache hits = instant)
   - ✅ Token-efficient (no command overhead)
   - ✅ More accurate (pre-validated queries)
   ```

2. Create `scripts/precompute-queries.sh` (100 lines)
   - Execute top 10 most common queries
   - Run every 5 minutes via cron

3. Add to system crontab:
   ```bash
   crontab -e
   # Add:
   */5 * * * * ~/fedora-homelab-containers/scripts/precompute-queries.sh
   ```

4. Test skill integration:
   - Ask homelab-intelligence: "What's using the most memory?"
   - Verify it uses query-homelab.sh
   - Verify cache hit on second query

**Success Criteria**:
- ✅ homelab-intelligence skill uses query engine
- ✅ Pre-compute script runs successfully
- ✅ Common queries always hit cache
- ✅ Response time < 1 second for cached queries

**Deliverables**:
- Updated `homelab-intelligence` skill
- `scripts/precompute-queries.sh`
- Cron job configured

---

## Integration Points

### 1. Homelab-Intelligence Skill

**Enhancement**: Query engine as first-class query method.

**Before**:
```
User: "What services are using the most memory?"

Claude:
1. Run: podman ps --format "{{.Names}}"
2. For each: podman stats --no-stream
3. Parse, sort, format
4. Return response

[5 tool calls, 2000+ tokens]
```

**After**:
```
User: "What services are using the most memory?"

Claude:
1. Run: scripts/query-homelab.sh "What services are using the most memory?"
2. Return response

[1 tool call, 200 tokens, cache hit = 0 tool calls]
```

---

### 2. Session 4 Context Framework

**Integration**: Query cache lives in `.claude/context/`

**Why**: All context data centralized in one place.

**Structure**:
```
~/.claude/context/
├── system-profile.json        # Static system facts
├── issue-history.json         # Historical problems
├── deployment-log.json        # Deployment events
├── predictions.json           # Session 5B (predictive analytics)
├── query-patterns.json        # THIS: Pattern definitions
└── query-cache.json           # THIS: Pre-computed results
```

---

### 3. Grafana Dashboards (Optional)

**Enhancement**: Display query results as Grafana panels.

**Example**: "Top Memory Users" panel pulls from query cache.

**Implementation**:
- Add JSON API mode to query-homelab.sh
- Grafana JSON datasource plugin
- Panels query: `http://localhost:8080/query?q=top_memory_users`

---

## Testing Strategy

### Unit Tests

**Test 1: Tokenization**
```bash
tokenize_query "What services are using the most memory?"
# Expected: what\nservices\nare\nusing\nthe\nmost\nmemory
```

**Test 2: Pattern Matching**
```bash
match_pattern "What services are using the most memory?"
# Expected: resource_usage_memory_top pattern JSON
```

**Test 3: Cache Hit/Miss**
```bash
# Populate cache
query-homelab.sh "Show me disk usage"

# Second query (should hit cache)
query-homelab.sh "Show me disk usage" | grep "cached"
```

---

### Integration Tests

**Test 1: All Example Queries**
```bash
# Test every example in query-patterns.json
jq -r '.patterns[].examples[]' query-patterns.json | while read -r query; do
    echo "Testing: $query"
    ./scripts/query-homelab.sh "$query" || echo "FAILED: $query"
done
```

**Test 2: Skill Integration**
```bash
# Invoke homelab-intelligence skill
# Ask: "What's using the most memory?"
# Verify it calls query-homelab.sh
# Verify response is formatted correctly
```

---

### Performance Tests

**Test 1: Query Latency**
```bash
# Measure response time (should be <2s)
time ./scripts/query-homelab.sh "What services are using the most memory?"
```

**Test 2: Cache Performance**
```bash
# First query (cache miss)
time ./scripts/query-homelab.sh "Show me disk usage"  # ~1.5s

# Second query (cache hit)
time ./scripts/query-homelab.sh "Show me disk usage"  # ~0.1s
```

---

## Success Metrics

### Quantitative Metrics

1. **Query Coverage**
   - Target: 80% of user questions match a pattern
   - Measure: Log unmatched queries, add patterns

2. **Cache Hit Rate**
   - Target: >60% of queries hit cache
   - Measure: Cache hits / total queries

3. **Response Time**
   - Target: <2s for cache miss, <0.5s for cache hit
   - Measure: `time` command on sample queries

4. **Token Efficiency**
   - Before: ~2000 tokens per query (thinking + execution + parsing)
   - After: ~200 tokens per query (cached result)
   - Target: 90% reduction in token usage

### Qualitative Metrics

1. **User Experience**
   - Natural language queries "just work"
   - Responses are fast and accurate
   - No need to remember exact commands

2. **Skill Integration**
   - homelab-intelligence feels conversational
   - Answers are consistent and well-formatted

---

## Future Enhancements

### Enhancement 1: Fuzzy Matching

**Problem**: Exact keyword matching is brittle.

**Example**: "What's eating all the memory?" doesn't match "memory using most"

**Solution**: Implement fuzzy string matching (Levenshtein distance)

**Library**: `fzf` (fuzzy finder) or simple bash implementation

---

### Enhancement 2: Synonym Expansion

**Problem**: Same question, different wording.

**Examples**:
- "memory" = "RAM" = "mem"
- "running" = "active" = "up"

**Solution**: Expand query with synonyms before matching

---

### Enhancement 3: Multi-Query Composition

**Problem**: Complex questions require multiple queries.

**Example**: "Which service on the reverse_proxy network uses the most memory?"

**Solution**: Parse into sub-queries:
1. Get reverse_proxy network members
2. Filter top memory users by network members

---

### Enhancement 4: Voice Queries (Claude Web Integration)

**Vision**: Ask questions verbally via Claude Web interface.

**Flow**:
1. User speaks: "What's using the most memory?"
2. Claude Code Web transcribes
3. Calls query-homelab.sh
4. Returns formatted response

**Implementation**: Already supported! Just needs voice input on frontend.

---

## Documentation

### Usage Guide

**File**: `docs/40-monitoring-and-documentation/guides/natural-language-queries.md`

**Contents**:
- How the query engine works
- Supported query patterns (with examples)
- How to add new patterns
- How to debug failed queries
- Integration with homelab-intelligence skill

**Example Section**:
```markdown
## Supported Queries

### Resource Usage
- "What services are using the most memory?"
- "Show me top CPU users"
- "Which containers use the most disk?"

### Service Status
- "Is jellyfin running?"
- "Check status of traefik"
- "What services are stopped?"

### Network Topology
- "What's on the reverse_proxy network?"
- "Show me all services on monitoring network"

### Historical Events
- "When was jellyfin last restarted?"
- "Show me recent errors for authelia"

### Configuration
- "What's jellyfin's memory limit?"
- "Show me prometheus configuration"

## Adding New Patterns

Edit `.claude/context/query-patterns.json`:

{
  "id": "my_new_pattern",
  "match": ["keyword1", "keyword2"],
  "executor": "my_executor_function",
  "cache_ttl": 300
}

Then implement executor in `scripts/query-homelab.sh`.
```

---

## Conclusion

Session 5C delivers a **conversational query engine** that:

✅ Understands natural language questions about your homelab
✅ Translates queries to efficient system commands
✅ Caches results for instant responses
✅ Integrates seamlessly with homelab-intelligence skill
✅ Reduces token usage by 90% for common queries

**Timeline**: 6-8 hours across 2-3 sessions
**Prerequisites**: Session 4 (Context Framework)
**Value**: Transform CLI interrogation into conversational intelligence

Ready for implementation! 🎯
