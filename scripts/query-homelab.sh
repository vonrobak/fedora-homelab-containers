#!/bin/bash
# query-homelab.sh
# Natural language query engine for homelab
#
# Purpose:
#   - Parse natural language questions about the homelab
#   - Translate to system commands via pattern matching
#   - Cache results for instant responses
#   - Integrate with homelab-intelligence skill
#
# Usage:
#   ./query-homelab.sh "What services are using the most memory?"
#   ./query-homelab.sh "Is jellyfin running?"
#   ./query-homelab.sh "Show me disk usage"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$HOME/.claude/context"
PATTERNS_FILE="$CONTEXT_DIR/query-patterns.json"
CACHE_FILE="$CONTEXT_DIR/query-cache.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

# Initialize cache if not exists
init_cache() {
    mkdir -p "$CONTEXT_DIR"

    if [[ ! -f "$CACHE_FILE" ]]; then
        echo '{}' > "$CACHE_FILE"
    fi
}

# Tokenize query (lowercase, extract keywords)
tokenize_query() {
    local query="$1"

    # Convert to lowercase, split on whitespace, remove punctuation
    echo "$query" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | grep -v '^$'
}

# Match query against patterns
match_pattern() {
    local query="$1"
    local tokens=$(tokenize_query "$query")

    # Check if patterns file exists
    if [[ ! -f "$PATTERNS_FILE" ]]; then
        return 1
    fi

    # Load patterns
    local patterns=$(jq -c '.patterns[]' "$PATTERNS_FILE" 2>/dev/null || echo "")

    if [[ -z "$patterns" ]]; then
        return 1
    fi

    # For each pattern, check if keywords match
    while IFS= read -r pattern_json; do
        local pattern_id=$(echo "$pattern_json" | jq -r '.id')
        local match_keywords=$(echo "$pattern_json" | jq -r '.match[]' 2>/dev/null || echo "")

        if [[ -z "$match_keywords" ]]; then
            continue
        fi

        local match_count=0
        local total_keywords=0

        # Check if all required keywords present in query
        while IFS= read -r keyword; do
            ((total_keywords++)) || true

            # Handle parameter placeholders {service}, {network}
            if [[ "$keyword" =~ ^\{.*\}$ ]]; then
                # Skip parameter placeholders in matching
                ((match_count++)) || true
                continue
            fi

            if echo "$tokens" | grep -qw "$keyword"; then
                ((match_count++)) || true
            fi
        done <<< "$match_keywords"

        # If all keywords matched, return pattern
        if (( match_count == total_keywords )); then
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
    local params=$(echo "$pattern" | jq -r '.parameters[]? // empty' 2>/dev/null)

    if [[ -z "$params" ]]; then
        echo '{}'
        return
    fi

    local result="{}"

    # Extract service name
    if echo "$params" | grep -q "service"; then
        local services=$(podman ps --format "{{.Names}}" 2>/dev/null || echo "")
        local matched_service=""

        if [[ -n "$services" ]]; then
            while IFS= read -r service; do
                if echo "$query" | grep -iq "$service"; then
                    matched_service="$service"
                    break
                fi
            done <<< "$services"
        fi

        if [[ -n "$matched_service" ]]; then
            result=$(echo "$result" | jq --arg service "$matched_service" '. + {service: $service}')
        fi
    fi

    # Extract network name
    if echo "$params" | grep -q "network"; then
        local networks=$(podman network ls --format "{{.Name}}" 2>/dev/null | grep "^systemd-" | sed 's/^systemd-//' || echo "")
        local matched_network=""

        if [[ -n "$networks" ]]; then
            while IFS= read -r network; do
                if echo "$query" | grep -iq "$network"; then
                    matched_network="$network"
                    break
                fi
            done <<< "$networks"
        fi

        if [[ -n "$matched_network" ]]; then
            result=$(echo "$result" | jq --arg network "$matched_network" '. + {network: $network}')
        fi
    fi

    echo "$result"
}

# Check cache for result
check_cache() {
    local cache_key="$1"

    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    local cached=$(jq -r ".\"${cache_key}\" // null" "$CACHE_FILE" 2>/dev/null)

    if [[ "$cached" == "null" ]] || [[ -z "$cached" ]]; then
        return 1
    fi

    # Check TTL
    local timestamp=$(echo "$cached" | jq -r '.timestamp' 2>/dev/null)
    local ttl=$(echo "$cached" | jq -r '.ttl' 2>/dev/null)

    if [[ "$timestamp" == "null" ]] || [[ "$ttl" == "null" ]]; then
        return 1
    fi

    local current_time=$(date +%s)
    local cached_time=$(date -d "$timestamp" +%s 2>/dev/null || echo "0")

    if (( current_time - cached_time > ttl )); then
        # Cache expired
        return 1
    fi

    # Return cached result
    echo "$cached" | jq -c '.result'
    return 0
}

# Update cache
update_cache() {
    local cache_key="$1"
    local result="$2"
    local ttl="${3:-300}"  # Default 5 minutes

    # Create cached entry
    local timestamp=$(date -Iseconds)
    local cached_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --argjson ttl "$ttl" \
        --argjson result "$result" \
        '{timestamp: $timestamp, ttl: $ttl, result: $result}')

    # Update cache file
    local updated_cache=$(jq --arg key "$cache_key" --argjson entry "$cached_entry" \
        '.[$key] = $entry' "$CACHE_FILE" 2>/dev/null || echo "{\"$cache_key\": $cached_entry}")

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
            local service=$(echo "$parameters" | jq -r '.service // empty')
            if [[ -z "$service" ]]; then
                echo '{"error": "No service specified"}'
                return 1
            fi
            check_service_status "$service"
            ;;
        get_network_members)
            local network=$(echo "$parameters" | jq -r '.network // empty')
            if [[ -z "$network" ]]; then
                echo '{"error": "No network specified"}'
                return 1
            fi
            get_network_members "$network"
            ;;
        get_disk_usage)
            get_disk_usage
            ;;
        get_recent_restarts)
            get_recent_restarts
            ;;
        get_service_config)
            local service=$(echo "$parameters" | jq -r '.service // empty')
            if [[ -z "$service" ]]; then
                echo '{"error": "No service specified"}'
                return 1
            fi
            get_service_config "$service"
            ;;
        list_all_services)
            list_all_services
            ;;
        *)
            echo "{\"error\": \"Unknown executor: $executor\"}"
            return 1
            ;;
    esac
}

# ==================== QUERY EXECUTORS ====================

# Get top 5 memory users
get_top_memory_users() {
    # Use format string since JSON format is unreliable
    podman stats --no-stream --format "{{.Name}}|{{.MemUsage}}" 2>/dev/null | \
    awk -F'|' '{
        split($2, mem, " ");
        usage = mem[1];

        # Convert to MB
        if (usage ~ /GB$/) {
            gsub(/GB/, "", usage);
            mb = usage * 1024;
        } else if (usage ~ /MB$/) {
            gsub(/MB/, "", usage);
            mb = usage;
        } else if (usage ~ /KB$/) {
            gsub(/KB/, "", usage);
            mb = usage / 1024;
        } else {
            mb = usage;
        }

        printf "{\"name\": \"%s\", \"memory_mb\": %.0f}\n", $1, mb;
    }' | jq -s 'sort_by(.memory_mb) | reverse | .[0:5]'
}

# Get top 5 CPU users
get_top_cpu_users() {
    podman stats --no-stream --format "{{.Name}}|{{.CPUPerc}}" 2>/dev/null | \
    awk -F'|' '{
        cpu = $2;
        gsub(/%/, "", cpu);
        printf "{\"name\": \"%s\", \"cpu_pct\": %.2f}\n", $1, cpu;
    }' | jq -s 'sort_by(.cpu_pct) | reverse | .[0:5]'
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

    # Try with systemd- prefix
    local network_name="systemd-${network}"

    podman network inspect "$network_name" 2>/dev/null | jq -c '
        if length > 0 then
            .[0].containers // {} | to_entries | map({
                service: .value.name,
                ip: (.value.ipv4_address // .value.ipv6_address // "N/A")
            })
        else
            []
        end
    ' || echo '[]'
}

# Get disk usage summary
get_disk_usage() {
    local root_usage=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}')
    local btrfs_usage=$(df -h /mnt/btrfs-pool 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")

    jq -n \
        --arg root "$root_usage" \
        --arg btrfs "$btrfs_usage" \
        '{filesystems: [
            {mount: "/", usage_pct: $root},
            {mount: "/mnt/btrfs-pool", usage_pct: $btrfs}
        ]}'
}

# Get recent service restarts (last 24h only - SAFETY LIMITED)
get_recent_restarts() {
    # CRITICAL SAFETY: journalctl --grep on large time windows causes system hangs
    # SOLUTION: Use systemctl to check current service states instead of journal history

    # Get all user services and their states
    systemctl --user list-units --type=service --all --no-pager --output json 2>/dev/null | \
    jq -c '[.[] | select(.unit | endswith(".service")) | {
        service: (.unit | rtrimstr(".service")),
        status: .active,
        state: .sub,
        load: .load
    }] | .[0:20]' || echo '[]'

    # NOTE: This returns current state, not restart history
    # Restart history requires journalctl which is too slow/dangerous for large time windows
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
    local memory_limit=$(grep "^Memory=" "$quadlet" 2>/dev/null | cut -d= -f2 || echo "unlimited")
    local networks=$(grep "^Network=" "$quadlet" 2>/dev/null | cut -d= -f2 | tr '\n' ',' | sed 's/,$//' || echo "none")
    local image=$(grep "^Image=" "$quadlet" 2>/dev/null | cut -d= -f2 || echo "unknown")

    jq -n \
        --arg service "$service" \
        --arg image "$image" \
        --arg memory "$memory_limit" \
        --arg networks "$networks" \
        '{service: $service, image: $image, memory_limit: $memory, networks: $networks}'
}

# List all services
list_all_services() {
    systemctl --user list-units --type=service --all --no-pager --output json 2>/dev/null | \
    jq -c '[.[] | select(.unit | endswith(".service")) | {
        name: (.unit | rtrimstr(".service")),
        status: .active,
        state: .sub
    }] | .[0:20]'
}

# ==================== RESPONSE FORMATTERS ====================

# Format result as human-readable text
format_response() {
    local executor="$1"
    local result="$2"
    local from_cache="${3:-false}"

    local cache_note=""
    if [[ "$from_cache" == "true" ]]; then
        cache_note="${GRAY} (cached)${NC}"
    fi

    case "$executor" in
        get_top_memory_users)
            echo -e "${BLUE}Top memory users${cache_note}:${NC}"
            echo "$result" | jq -r '.[] | "\(.name): \(.memory_mb | floor)MB"' | nl
            ;;
        get_top_cpu_users)
            echo -e "${BLUE}Top CPU users${cache_note}:${NC}"
            echo "$result" | jq -r '.[] | "\(.name): \(.cpu_pct)%"' | nl
            ;;
        check_service_status)
            local service=$(echo "$result" | jq -r '.service')
            local status=$(echo "$result" | jq -r '.status')

            if [[ "$status" == "running" ]]; then
                echo -e "${service} is ${GREEN}${status}${NC}"
            else
                echo -e "${service} is ${RED}${status}${NC}"
            fi
            ;;
        get_network_members)
            echo -e "${BLUE}Network members${cache_note}:${NC}"
            local count=$(echo "$result" | jq 'length')
            if (( count == 0 )); then
                echo "  No services found on this network"
            else
                echo "$result" | jq -r '.[] | "  \(.service): \(.ip)"'
            fi
            ;;
        get_disk_usage)
            echo -e "${BLUE}Disk usage${cache_note}:${NC}"
            echo "$result" | jq -r '.filesystems[] | "  \(.mount): \(.usage_pct)"'
            ;;
        get_recent_restarts)
            echo -e "${BLUE}Recent service events (last 7 days)${cache_note}:${NC}"
            echo "$result" | jq -r '.[] | "  [\(.timestamp)] \(.service)"' | head -10
            ;;
        get_service_config)
            echo -e "${BLUE}Configuration${cache_note}:${NC}"
            echo "$result" | jq -r 'to_entries | .[] | "  \(.key): \(.value)"'
            ;;
        list_all_services)
            echo -e "${BLUE}Services${cache_note}:${NC}"
            echo "$result" | jq -r '.[] | "  \(.name): \(.status) (\(.state))"'
            ;;
        *)
            # Check for error
            local error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
            if [[ -n "$error" ]]; then
                echo -e "${RED}Error: $error${NC}"
            else
                echo "$result" | jq -r '.' 2>/dev/null || echo "$result"
            fi
            ;;
    esac
}

# ==================== MAIN LOGIC ====================

show_help() {
    cat <<EOF
${BLUE}Query Homelab - Natural Language Query Engine${NC}

Usage: $0 "Your question here"

Supported query patterns:
  ${GREEN}Resource Usage:${NC}
    - What services are using the most memory?
    - Show me top CPU users

  ${GREEN}Service Status:${NC}
    - Is jellyfin running?
    - Check status of traefik

  ${GREEN}Network Topology:${NC}
    - What's on the reverse_proxy network?
    - Show me services on monitoring network

  ${GREEN}Disk Usage:${NC}
    - Show me disk usage
    - What's the filesystem usage?

  ${GREEN}Historical Events:${NC}
    - Show me recent restarts
    - What happened recently?

  ${GREEN}Configuration:${NC}
    - What's jellyfin's configuration?
    - Show me prometheus settings

Examples:
  $0 "What services are using the most memory?"
  $0 "Is jellyfin running?"
  $0 "Show me disk usage"

Options:
  --help     Show this help message
  --json     Output raw JSON result
EOF
}

main() {
    local query="$*"
    local output_json=false

    # Parse options
    if [[ "$query" == "--help" ]] || [[ -z "$query" ]]; then
        show_help
        exit 0
    fi

    if [[ "$query" == *"--json"* ]]; then
        output_json=true
        query="${query/--json/}"
    fi

    init_cache

    # Match query pattern
    local pattern=$(match_pattern "$query")

    if [[ -z "$pattern" ]]; then
        echo -e "${YELLOW}I don't understand that question.${NC}\n"
        echo "Try asking:"
        echo "  - What services are using the most memory?"
        echo "  - Is jellyfin running?"
        echo "  - What's on the reverse_proxy network?"
        echo "  - Show me disk usage"
        echo ""
        echo "Or run: $0 --help"
        return 1
    fi

    # Extract pattern details
    local executor=$(echo "$pattern" | jq -r '.executor')
    local cache_key=$(echo "$pattern" | jq -r '.cache_key // empty')
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

        # Update cache if successful and cache_key exists
        if [[ $? -eq 0 ]] && [[ -n "$cache_key" ]]; then
            update_cache "$cache_key" "$result" "$cache_ttl"
        fi
    fi

    # Output
    if [[ "$output_json" == "true" ]]; then
        echo "$result" | jq '.'
    else
        format_response "$executor" "$result" "$from_cache"
    fi
}

# Run
main "$@"
