#!/usr/bin/env bash
# Deploy service from battle-tested pattern
# Version: 1.0 (Session 3)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PATTERNS_DIR="${SKILL_DIR}/patterns"
TEMPLATES_DIR="${SKILL_DIR}/templates"
SCRIPTS_DIR="${SKILL_DIR}/scripts"

# Variables
PATTERN=""
SERVICE_NAME=""
IMAGE=""
HOSTNAME=""
MEMORY="1G"
SKIP_HEALTH_CHECK=false
DRY_RUN=false
VERBOSE=false

# Pattern variables
declare -A PATTERN_VARS

##############################################################################
# Help
##############################################################################

show_help() {
    cat << EOF
Usage: $0 --pattern PATTERN --service-name NAME [OPTIONS]

Deploy a service using a battle-tested pattern.

Required Arguments:
  --pattern NAME          Pattern to use (see available patterns below)
  --service-name NAME     Name for the service

Optional Arguments:
  --image IMAGE           Container image (overrides pattern default)
  --hostname FQDN         Hostname for Traefik routing
  --memory SIZE           Memory limit (e.g., 1G, 512M)
  --var KEY=VALUE         Override pattern variable
  --skip-health-check     Skip system health check
  --dry-run               Show what would be deployed without deploying
  --verbose               Show detailed output
  --help                  Show this help message

Available Patterns:
EOF

    if [[ -d "$PATTERNS_DIR" ]]; then
        echo ""
        for pattern in "$PATTERNS_DIR"/*.yml; do
            if [[ -f "$pattern" ]]; then
                pattern_name=$(basename "$pattern" .yml)
                pattern_desc=$(grep "description:" "$pattern" | head -1 | cut -d'"' -f2)
                printf "  %-25s %s\n" "$pattern_name" "$pattern_desc"
            fi
        done
    fi

    cat << EOF

Examples:
  # Deploy Jellyfin using media-server pattern
  $0 --pattern media-server-stack \\
     --service-name jellyfin \\
     --hostname jellyfin.patriark.org \\
     --memory 4G

  # Deploy PostgreSQL database
  $0 --pattern database-service \\
     --service-name nextcloud-db \\
     --var db_type=postgres \\
     --var db_user=nextcloud \\
     --var db_password=\$POSTGRES_PASSWORD \\
     --memory 2G

  # Deploy Redis cache with dry-run
  $0 --pattern cache-service \\
     --service-name redis-authelia \\
     --memory 256M \\
     --dry-run

Workflow:
  1. Load pattern YAML
  2. Check system health (unless --skip-health-check)
  3. Generate quadlet from pattern + variables
  4. Generate Traefik route (if applicable)
  5. Run prerequisites check
  6. Validate quadlet
  7. Deploy service
  8. Verify deployment
  9. Generate documentation
  10. Display post-deployment checklist

EOF
}

##############################################################################
# Pattern Loading
##############################################################################

load_pattern() {
    local pattern_file="${PATTERNS_DIR}/${PATTERN}.yml"

    if [[ ! -f "$pattern_file" ]]; then
        echo -e "${RED}✗${NC} Pattern not found: ${PATTERN}"
        echo ""
        echo "Available patterns:"
        ls -1 "$PATTERNS_DIR"/*.yml 2>/dev/null | xargs -n1 basename | sed 's/.yml$//' || echo "  None"
        exit 1
    fi

    [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}Loading pattern:${NC} $pattern_file"

    # Parse YAML (basic parsing - extract key values)
    # This is a simplified parser; for production, consider using yq or python

    PATTERN_VARS[image]=$(grep "^  image:" "$pattern_file" | head -1 | cut -d'"' -f2)
    PATTERN_VARS[memory_limit]=$(grep "^  memory_limit:" "$pattern_file" | head -1 | cut -d'"' -f2)
    PATTERN_VARS[quadlet_template]=$(grep "^  quadlet_template:" "$pattern_file" | head -1 | awk '{print $2}')
    PATTERN_VARS[traefik_template]=$(grep "^  traefik_template:" "$pattern_file" | head -1 | awk '{print $2}')

    # Extract networks (comma-separated)
    PATTERN_VARS[networks]=$(grep -A 10 "^  networks:" "$pattern_file" | grep "^    -" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

    [[ "$VERBOSE" == "true" ]] && echo -e "${GREEN}✓${NC} Pattern loaded successfully"
}

##############################################################################
# Variable Substitution
##############################################################################

substitute_variables() {
    local template_file="$1"
    local output_file="$2"

    [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}Substituting variables...${NC}"

    # Copy template
    cp "$template_file" "$output_file"

    # Substitute variables
    sed -i "s/{{SERVICE_NAME}}/${SERVICE_NAME}/g" "$output_file"
    sed -i "s|{{IMAGE}}|${IMAGE}|g" "$output_file"
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" "$output_file"
    sed -i "s/{{MEMORY}}/${MEMORY}/g" "$output_file"

    # Substitute pattern-specific variables
    for key in "${!PATTERN_VARS[@]}"; do
        if [[ -n "${PATTERN_VARS[$key]}" ]]; then
            sed -i "s|{{${key}}}|${PATTERN_VARS[$key]}|g" "$output_file"
        fi
    done

    [[ "$VERBOSE" == "true" ]] && echo -e "${GREEN}✓${NC} Variables substituted"
}

##############################################################################
# Health Check
##############################################################################

run_health_check() {
    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        echo -e "${YELLOW}⚠${NC} Skipping health check (--skip-health-check)"
        return 0
    fi

    echo -e "${BLUE}=== System Health Check ===${NC}"
    echo ""

    if [[ -x "${SCRIPTS_DIR}/check-system-health.sh" ]]; then
        "${SCRIPTS_DIR}/check-system-health.sh"
        local health_exit=$?

        if [[ $health_exit -eq 2 ]]; then
            echo -e "${RED}✗${NC} Deployment blocked due to low health score"
            echo "  Run with --skip-health-check to override (not recommended)"
            exit 2
        elif [[ $health_exit -eq 1 ]]; then
            echo -e "${YELLOW}⚠${NC} Health warnings detected, but proceeding"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Health check script not found, skipping"
    fi

    echo ""
}

##############################################################################
# Quadlet Generation
##############################################################################

generate_quadlet() {
    local quadlet_template="${PATTERN_VARS[quadlet_template]}"
    local template_file="${TEMPLATES_DIR}/quadlets/${quadlet_template}"
    local output_file="/tmp/${SERVICE_NAME}.container"

    echo -e "${BLUE}=== Generating Quadlet ===${NC}"
    echo ""

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}✗${NC} Quadlet template not found: ${quadlet_template}"
        exit 1
    fi

    substitute_variables "$template_file" "$output_file"

    echo -e "${GREEN}✓${NC} Quadlet generated: $output_file"

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "Preview:"
        head -20 "$output_file"
    fi

    echo ""
}

##############################################################################
# Prerequisites Check
##############################################################################

run_prerequisites_check() {
    echo -e "${BLUE}=== Prerequisites Check ===${NC}"
    echo ""

    if [[ -x "${SCRIPTS_DIR}/check-prerequisites.sh" ]]; then
        local networks="${PATTERN_VARS[networks]}"

        "${SCRIPTS_DIR}/check-prerequisites.sh" \
            --service-name "$SERVICE_NAME" \
            --image "$IMAGE" \
            --networks "$networks" \
            || {
                echo -e "${RED}✗${NC} Prerequisites check failed"
                exit 1
            }
    else
        echo -e "${YELLOW}⚠${NC} Prerequisites script not found, skipping"
    fi

    echo ""
}

##############################################################################
# Quadlet Validation
##############################################################################

validate_quadlet() {
    local quadlet_file="/tmp/${SERVICE_NAME}.container"

    echo -e "${BLUE}=== Quadlet Validation ===${NC}"
    echo ""

    if [[ -x "${SCRIPTS_DIR}/validate-quadlet.sh" ]]; then
        "${SCRIPTS_DIR}/validate-quadlet.sh" "$quadlet_file" || {
            echo -e "${RED}✗${NC} Quadlet validation failed"
            exit 1
        }
    else
        echo -e "${YELLOW}⚠${NC} Validation script not found, skipping"
    fi

    echo ""
}

##############################################################################
# Deployment
##############################################################################

deploy_service() {
    local quadlet_file="/tmp/${SERVICE_NAME}.container"
    local target_quadlet="${HOME}/.config/containers/systemd/${SERVICE_NAME}.container"

    echo -e "${BLUE}=== Deploying Service ===${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would deploy: $SERVICE_NAME"
        echo "  Quadlet: $target_quadlet"
        echo "  Pattern: $PATTERN"
        echo "  Image: $IMAGE"
        echo "  Hostname: $HOSTNAME"
        echo "  Memory: $MEMORY"
        echo ""
        return 0
    fi

    # Copy quadlet to systemd directory
    mkdir -p "$(dirname "$target_quadlet")"
    cp "$quadlet_file" "$target_quadlet"
    echo -e "${GREEN}✓${NC} Quadlet installed: $target_quadlet"

    # Deploy using deploy-service.sh if available
    if [[ -x "${SCRIPTS_DIR}/deploy-service.sh" ]]; then
        "${SCRIPTS_DIR}/deploy-service.sh" \
            --service-name "$SERVICE_NAME" \
            --wait-healthy 180 \
            || {
                echo -e "${RED}✗${NC} Deployment failed"
                exit 1
            }
    else
        # Fallback: manual deployment
        systemctl --user daemon-reload
        systemctl --user enable --now "${SERVICE_NAME}.service"
    fi

    echo ""
}

##############################################################################
# Post-Deployment
##############################################################################

show_post_deployment() {
    local pattern_file="${PATTERNS_DIR}/${PATTERN}.yml"

    echo -e "${BLUE}=== Post-Deployment Checklist ===${NC}"
    echo ""

    # Extract post_deployment section from pattern
    if grep -q "^post_deployment:" "$pattern_file"; then
        sed -n '/^post_deployment:/,/^[a-z_]*:/p' "$pattern_file" | \
            grep "^  -" | \
            sed 's/^  - /  ☐ /'
    else
        echo "  ☐ Verify service is running: systemctl --user status ${SERVICE_NAME}.service"
        echo "  ☐ Check logs: journalctl --user -u ${SERVICE_NAME}.service -f"
        echo "  ☐ Test access: https://${HOSTNAME}"
    fi

    echo ""
    echo -e "${GREEN}✓ Deployment complete!${NC}"
    echo ""
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --pattern)
                PATTERN="$2"
                shift 2
                ;;
            --service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            --image)
                IMAGE="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --var)
                # Parse KEY=VALUE
                local key="${2%%=*}"
                local value="${2#*=}"
                PATTERN_VARS["$key"]="$value"
                shift 2
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}✗${NC} Unknown argument: $1"
                echo "  Run with --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$PATTERN" ]]; then
        echo -e "${RED}✗${NC} --pattern is required"
        exit 1
    fi

    if [[ -z "$SERVICE_NAME" ]]; then
        echo -e "${RED}✗${NC} --service-name is required"
        exit 1
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    parse_arguments "$@"

    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Pattern-Based Service Deployment             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Pattern: ${PATTERN}"
    echo "  Service: ${SERVICE_NAME}"
    echo ""

    # Load pattern
    load_pattern

    # Set defaults from pattern if not overridden
    [[ -z "$IMAGE" ]] && IMAGE="${PATTERN_VARS[image]}"
    [[ -z "$HOSTNAME" ]] && HOSTNAME="${SERVICE_NAME}.patriark.org"

    # Workflow
    run_health_check
    generate_quadlet
    run_prerequisites_check
    validate_quadlet
    deploy_service
    show_post_deployment
}

main "$@"
