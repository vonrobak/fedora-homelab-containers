#!/bin/bash
# Service Catalog Generator
# Generates categorized service inventory with health, uptime, URLs, and guide links

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-SERVICE-CATALOG.md"
ROUTERS_FILE="${HOME}/containers/config/traefik/dynamic/routers.yml"
GUIDES_DIR="${HOME}/containers/docs/10-services/guides"
MONITORING_GUIDE="docs/40-monitoring-and-documentation/guides/monitoring-stack.md"

# Service group assignment (matches CLAUDE.md's 13 service groups)
get_group() {
    case "$1" in
        traefik|crowdsec|authelia|redis-authelia)    echo "1:Core Infrastructure" ;;
        nextcloud|nextcloud-db|nextcloud-redis)      echo "2:Nextcloud" ;;
        immich-server|immich-ml|postgresql-immich|redis-immich) echo "3:Immich" ;;
        jellyfin)                                    echo "4:Jellyfin" ;;
        vaultwarden)                                 echo "5:Vaultwarden" ;;
        home-assistant|matter-server)                echo "6:Home Automation" ;;
        gathio|gathio-db)                            echo "7:Gathio" ;;
        homepage)                                    echo "8:Homepage" ;;
        prometheus|grafana|loki|alertmanager|promtail|node_exporter|cadvisor|unpoller|alert-discord-relay)
                                                     echo "9:Monitoring" ;;
        *)                                           echo "10:Other" ;;
    esac
}

# Extract public URL for a service from routers.yml
# Maps container names to Traefik service names and finds the Host rule
get_public_url() {
    local container=$1

    [[ ! -f "$ROUTERS_FILE" ]] && return

    # Map container names to Traefik service names where they differ
    local svc_name="$container"
    case "$container" in
        immich-server) svc_name="immich" ;;
        home-assistant) svc_name="home-assistant" ;;
        # Traefik dashboard uses api@internal, extract directly
        traefik)
            grep -oP 'Host\(`\K[^`]+' "$ROUTERS_FILE" | grep -m1 traefik || true
            return
            ;;
    esac

    # Find Host rule for this service in routers.yml
    # Look for service: "name" then find the corresponding rule: "Host(...)"
    awk -v svc="$svc_name" '
        /^    [a-z][a-z0-9_-]*:/ { in_router=1; rule=""; found=0 }
        in_router && /rule:.*Host\(/ {
            match($0, /Host\(`([^`]+)`\)/, m)
            if (m[1] != "") rule = m[1]
        }
        in_router && /service:/ {
            match($0, /"([^"]+)"/, m)
            if (m[1] == svc) found=1
        }
        in_router && found && rule != "" { print rule; exit }
        /^  [a-z]+:/ && !/^    / { in_router=0 }
    ' "$ROUTERS_FILE" 2>/dev/null || true
}

# Find the guide file for a service
get_guide_link() {
    local container=$1

    # Direct match
    if [[ -f "${GUIDES_DIR}/${container}.md" ]]; then
        echo "10-services/guides/${container}.md"
        return
    fi

    # Monitoring services share a guide
    case "$container" in
        prometheus|grafana|loki|alertmanager|promtail|node_exporter|cadvisor|unpoller)
            echo "40-monitoring-and-documentation/guides/monitoring-stack.md"
            return
            ;;
    esac

    # Try parent service name (e.g., nextcloud-db → nextcloud)
    local parent="${container%%-*}"
    if [[ "$parent" != "$container" && -f "${GUIDES_DIR}/${parent}.md" ]]; then
        echo "10-services/guides/${parent}.md"
        return
    fi
}

# Parse health and uptime from podman ps status string
parse_status() {
    local status="$1"
    local health="—"
    local uptime="—"

    if echo "$status" | grep -q "(healthy)"; then
        health="✅ healthy"
    elif echo "$status" | grep -q "(unhealthy)"; then
        health="⚠️ unhealthy"
    elif echo "$status" | grep -q "Up"; then
        health="— no check"
    fi

    # Extract uptime (e.g., "Up 10 days" → "10d", "Up 6 hours" → "6h")
    uptime=$(echo "$status" | sed -n 's/Up \(.*\) (.*/\1/p')
    if [[ -z "$uptime" ]]; then
        uptime=$(echo "$status" | sed -n 's/Up \(.*\)/\1/p')
    fi
    # Compact format
    uptime=$(echo "$uptime" | sed 's/ seconds\?/s/; s/ minutes\?/m/; s/ hours\?/h/; s/ days\?/d/; s/ weeks\?/w/; s/ months\?/mo/')
    # Trim "About "
    uptime=$(echo "$uptime" | sed 's/About /~/')

    echo "$health|$uptime"
}

# Main generation
{
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    total_running=$(podman ps -q | wc -l)
    total_defined=$(podman ps -aq | wc -l)
    healthy_count=$(podman ps --format "{{.Status}}" | grep -c "(healthy)" || true)
    total_with_healthcheck=$(podman ps --format "{{.Status}}" | grep -c "(healthy)\|(unhealthy)" || true)

    echo "# Service Catalog (Auto-Generated)"
    echo ""
    echo "**Generated:** $timestamp"
    echo "**System:** $(hostname) | **Services:** ${total_running}/${total_defined} running | **Health:** ${healthy_count}/${total_with_healthcheck} healthy ($(( total_running - total_with_healthcheck )) without healthcheck)"
    echo ""
    echo "---"

    # Collect container data and group it
    # Format: group_key|container_name|image|health|uptime|url|guide
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT

    podman ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | while IFS=$'\t' read -r name image status; do
        group=$(get_group "$name")
        short_image=$(echo "$image" | sed 's|docker.io/library/||; s|docker.io/||; s|ghcr.io/||' | cut -c1-45)
        parsed=$(parse_status "$status")
        health="${parsed%%|*}"
        uptime="${parsed##*|}"
        url=$(get_public_url "$name")
        guide=$(get_guide_link "$name")

        # Format URL as link or dash
        if [[ -n "$url" ]]; then
            url_col="[${url}](https://${url})"
        else
            url_col="—"
        fi

        # Format guide as link or dash
        if [[ -n "$guide" ]]; then
            guide_col="[guide](${guide})"
        else
            guide_col="—"
        fi

        echo "${group}|${name}|${short_image}|${health}|${uptime}|${url_col}|${guide_col}" >> "$tmpfile"
    done

    # Output grouped tables
    current_group=""
    sort "$tmpfile" | while IFS='|' read -r group name image health uptime url guide; do
        group_name="${group#*:}"
        if [[ "$group_name" != "$current_group" ]]; then
            # Count services in this group
            group_count=$(grep -c "^${group}|" "$tmpfile")
            echo ""
            echo "## ${group_name} (${group_count})"
            echo ""
            echo "| Service | Image | Health | Uptime | URL | Docs |"
            echo "|---------|-------|--------|--------|-----|------|"
            current_group="$group_name"
        fi
        echo "| ${name} | ${image} | ${health} | ${uptime} | ${url} | ${guide} |"
    done

    echo ""
    echo "---"
    echo ""
    echo "## Statistics"
    echo ""
    echo "- **Total Running:** ${total_running}"
    echo "- **Total Defined:** ${total_defined}"
    echo "- **System Load:**$(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    echo "---"
    echo ""
    echo "## Quick Links"
    echo ""
    echo "- [Network Topology](AUTO-NETWORK-TOPOLOGY.md)"
    echo "- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md)"
    echo "- [Homelab Architecture](20-operations/guides/homelab-architecture.md)"
    echo ""
    echo "---"
    echo ""
    echo "*Auto-generated by \`scripts/generate-service-catalog-simple.sh\`*"
} > "$OUTPUT_FILE"

echo "✓ Service catalog generated: $OUTPUT_FILE"
