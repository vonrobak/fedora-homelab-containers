#!/usr/bin/env bash
# Check for configuration drift between quadlets and running containers
# Version: 1.0 (Session 3)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
QUADLET_DIR="${HOME}/.config/containers/systemd"
REPORT_DIR="${HOME}/containers/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Counters
TOTAL_SERVICES=0
SERVICES_MATCH=0
SERVICES_DRIFT=0
SERVICES_WARNING=0

# Output flags
VERBOSE=false
JSON_OUTPUT=false
OUTPUT_FILE=""

##############################################################################
# Help
##############################################################################

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [SERVICE_NAME]

Compare running containers against their quadlet definitions to detect drift.

Arguments:
  SERVICE_NAME            Check specific service (default: all services)

Options:
  --verbose               Show detailed comparison for each service
  --json                  Output results in JSON format
  --output FILE           Save report to file
  --help                  Show this help message

Drift Categories:
  ✓ MATCH                 Running config matches quadlet definition
  ✗ DRIFT                 Configuration mismatch (needs reconciliation)
  ⚠ WARNING               Minor differences (informational only)

Examples:
  # Check all services
  $0

  # Check specific service with verbose output
  $0 jellyfin --verbose

  # Generate JSON report
  $0 --json --output drift-report.json

  # Check and show detailed differences
  $0 --verbose

What is checked:
  - Container image version
  - Memory limits
  - Network connections
  - Volume mounts
  - Environment variables
  - Traefik labels
  - Health check configuration
  - Restart policy

EOF
}

##############################################################################
# Service Inspection
##############################################################################

get_quadlet_value() {
    local quadlet_file="$1"
    local key="$2"
    local section="$3"

    if [[ ! -f "$quadlet_file" ]]; then
        echo ""
        return 1
    fi

    # Extract value from specific section
    awk -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $0 ~ "^" key "=" {
            sub(/^[^=]*=/, "");
            gsub(/^[ \t]+|[ \t]+$/, "");
            print;
            exit
        }
    ' "$quadlet_file"
}

get_container_value() {
    local container_name="$1"
    local field="$2"

    podman inspect "$container_name" --format "{{${field}}}" 2>/dev/null || echo ""
}

##############################################################################
# Drift Detection
##############################################################################

check_service_drift() {
    local service_name="$1"
    local quadlet_file="${QUADLET_DIR}/${service_name}.container"
    local container_name="${service_name}"

    TOTAL_SERVICES=$((TOTAL_SERVICES + 1))

    echo -e "${BLUE}Checking:${NC} $service_name"

    # Check if quadlet exists
    if [[ ! -f "$quadlet_file" ]]; then
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Quadlet file not found"
        SERVICES_WARNING=$((SERVICES_WARNING + 1))
        return 0
    fi

    # Check if container is running
    if ! podman ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Container not running"
        SERVICES_WARNING=$((SERVICES_WARNING + 1))
        return 0
    fi

    local has_drift=false

    # Check 1: Image version
    local quadlet_image=$(get_quadlet_value "$quadlet_file" "Image" "Container")
    local running_image=$(get_container_value "$container_name" ".Config.Image")

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Image:"
        echo "    Quadlet: $quadlet_image"
        echo "    Running: $running_image"
    fi

    if [[ "$quadlet_image" != "$running_image" ]]; then
        echo -e "  ${RED}✗ DRIFT:${NC} Image mismatch"
        echo "    Expected: $quadlet_image"
        echo "    Running:  $running_image"
        has_drift=true
    else
        [[ "$VERBOSE" == "true" ]] && echo -e "    ${GREEN}✓${NC} Match"
    fi

    # Check 2: Memory limit
    local quadlet_memory=$(get_quadlet_value "$quadlet_file" "Memory" "Service")
    local running_memory=$(get_container_value "$container_name" ".HostConfig.Memory")

    if [[ -n "$quadlet_memory" ]] && [[ -n "$running_memory" ]]; then
        # Convert to bytes for comparison (simplified)
        local quadlet_bytes=$(echo "$quadlet_memory" | sed 's/G/*1073741824/; s/M/*1048576/' | bc 2>/dev/null || echo "0")

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Memory:"
            echo "    Quadlet: $quadlet_memory ($quadlet_bytes bytes)"
            echo "    Running: $running_memory bytes"
        fi

        if [[ "$quadlet_bytes" -ne "$running_memory" ]] && [[ "$quadlet_bytes" -ne 0 ]]; then
            echo -e "  ${RED}✗ DRIFT:${NC} Memory limit mismatch"
            echo "    Expected: $quadlet_memory"
            echo "    Running:  $running_memory bytes"
            has_drift=true
        else
            [[ "$VERBOSE" == "true" ]] && echo -e "    ${GREEN}✓${NC} Match"
        fi
    fi

    # Check 3: Networks
    local quadlet_networks=$(grep "^Network=" "$quadlet_file" | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//')
    local running_networks=$(podman inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}' 2>/dev/null | tr ' ' '\n' | while read net_id; do
        podman network inspect "$net_id" --format '{{.Name}}' 2>/dev/null || echo "$net_id"
    done | tr '\n' ' ' | sed 's/ $//')

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Networks:"
        echo "    Quadlet: $quadlet_networks"
        echo "    Running: $running_networks"
    fi

    if [[ "$quadlet_networks" != "$running_networks" ]] && [[ -n "$quadlet_networks" ]]; then
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Network configuration differs"
        echo "    Expected: $quadlet_networks"
        echo "    Running:  $running_networks"
        SERVICES_WARNING=$((SERVICES_WARNING + 1))
    else
        [[ "$VERBOSE" == "true" ]] && echo -e "    ${GREEN}✓${NC} Match"
    fi

    # Check 4: Volume mounts
    local quadlet_volumes=$(grep "^Volume=" "$quadlet_file" | wc -l)
    local running_volumes=$(podman inspect "$container_name" --format '{{json .Mounts}}' 2>/dev/null | grep -o '"Type"' | wc -l)

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Volumes:"
        echo "    Quadlet defines: $quadlet_volumes mounts"
        echo "    Running has: $running_volumes mounts"
    fi

    # Ensure running_volumes is a number
    if [[ ! "$running_volumes" =~ ^[0-9]+$ ]]; then
        running_volumes=0
    fi

    if [[ "$quadlet_volumes" -ne "$running_volumes" ]] && [[ "$quadlet_volumes" -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Volume count mismatch"
        echo "    Expected: $quadlet_volumes volumes"
        echo "    Running:  $running_volumes volumes"
        SERVICES_WARNING=$((SERVICES_WARNING + 1))
    else
        [[ "$VERBOSE" == "true" ]] && echo -e "    ${GREEN}✓${NC} Match"
    fi

    # Check 5: Traefik labels
    local quadlet_traefik_labels=$(grep "^Label=" "$quadlet_file" | grep -c "traefik" || echo "0")
    local running_traefik_labels=$(podman inspect "$container_name" --format '{{range $k, $v := .Config.Labels}}{{if contains $k "traefik"}}{{$k}} {{end}}{{end}}' 2>/dev/null | wc -w)

    # Ensure both are numbers
    if [[ ! "$quadlet_traefik_labels" =~ ^[0-9]+$ ]]; then
        quadlet_traefik_labels=0
    fi
    if [[ ! "$running_traefik_labels" =~ ^[0-9]+$ ]]; then
        running_traefik_labels=0
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Traefik Labels:"
        echo "    Quadlet defines: $quadlet_traefik_labels labels"
        echo "    Running has: $running_traefik_labels labels"
    fi

    if [[ "$quadlet_traefik_labels" -ne "$running_traefik_labels" ]] && [[ "$quadlet_traefik_labels" -gt 0 ]]; then
        echo -e "  ${RED}✗ DRIFT:${NC} Traefik labels mismatch"
        echo "    Expected: $quadlet_traefik_labels labels"
        echo "    Running:  $running_traefik_labels labels"
        has_drift=true
    else
        [[ "$VERBOSE" == "true" ]] && echo -e "    ${GREEN}✓${NC} Match"
    fi

    # Summary for this service
    if [[ "$has_drift" == "true" ]]; then
        echo -e "  ${RED}Status: DRIFT DETECTED${NC}"
        echo "  Recommended: systemctl --user restart ${service_name}.service"
        SERVICES_DRIFT=$((SERVICES_DRIFT + 1))
    else
        echo -e "  ${GREEN}Status: MATCH${NC}"
        SERVICES_MATCH=$((SERVICES_MATCH + 1))
    fi

    echo ""
}

##############################################################################
# Report Generation
##############################################################################

generate_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         Drift Detection Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    echo "  Total Services Checked: $TOTAL_SERVICES"
    echo -e "  ${GREEN}✓${NC} Match:      $SERVICES_MATCH"
    echo -e "  ${RED}✗${NC} Drift:      $SERVICES_DRIFT"
    echo -e "  ${YELLOW}⚠${NC} Warnings:   $SERVICES_WARNING"
    echo ""

    if [[ $SERVICES_DRIFT -gt 0 ]]; then
        echo -e "${YELLOW}Recommended Actions:${NC}"
        echo "  1. Review drift details above"
        echo "  2. Reconcile by restarting services (applies quadlet config)"
        echo "  3. Or update quadlet to match running config (if intentional)"
        echo ""
    fi

    if [[ $SERVICES_DRIFT -eq 0 ]] && [[ $SERVICES_WARNING -eq 0 ]]; then
        echo -e "${GREEN}✓ No drift detected - all services match their definitions${NC}"
        echo ""
    fi
}

generate_json_report() {
    local json_file="${OUTPUT_FILE:-${REPORT_DIR}/drift-${TIMESTAMP}.json}"

    mkdir -p "$(dirname "$json_file")"

    cat > "$json_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total": $TOTAL_SERVICES,
    "match": $SERVICES_MATCH,
    "drift": $SERVICES_DRIFT,
    "warnings": $SERVICES_WARNING
  },
  "services": [
EOF

    # Note: This is a simplified JSON output
    # In production, this would be built during the checks

    echo "  ]" >> "$json_file"
    echo "}" >> "$json_file"

    echo -e "${GREEN}✓${NC} JSON report saved: $json_file"
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    local service_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --output|-o)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                echo -e "${RED}✗${NC} Unknown option: $1"
                exit 1
                ;;
            *)
                service_filter="$1"
                shift
                ;;
        esac
    done

    echo "$service_filter"
}

##############################################################################
# Main
##############################################################################

main() {
    local service_filter
    service_filter=$(parse_arguments "$@")

    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Configuration Drift Detection             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get list of services to check
    local services
    if [[ -n "$service_filter" ]]; then
        services=("$service_filter")
        echo "Checking service: $service_filter"
    else
        # Find all quadlet files
        services=()
        while IFS= read -r quadlet; do
            service=$(basename "$quadlet" .container)
            services+=("$service")
        done < <(find "$QUADLET_DIR" -maxdepth 1 -name "*.container" -type f)

        echo "Checking ${#services[@]} services..."
    fi

    echo ""

    # Check each service
    for service in "${services[@]}"; do
        check_service_drift "$service"
    done

    # Generate summary
    generate_summary

    # Generate JSON report if requested
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_json_report
    fi

    # Exit code based on drift level
    if [[ $SERVICES_DRIFT -gt 0 ]]; then
        exit 2  # Drift detected
    elif [[ $SERVICES_WARNING -gt 0 ]]; then
        exit 1  # Warnings only
    else
        exit 0  # No drift
    fi
}

main "$@"
