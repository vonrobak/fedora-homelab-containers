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
# Traefik Routing Generation
##############################################################################

generate_traefik_routing() {
    local traefik_template="${PATTERN_VARS[traefik_template]}"

    echo -e "${BLUE}=== Generating Traefik Routing ===${NC}"
    echo ""

    # Skip if no Traefik routing needed
    if [[ -z "$traefik_template" || "$traefik_template" == "none" ]]; then
        echo -e "${CYAN}ℹ${NC} No Traefik routing (internal service)"
        echo ""
        return 0
    fi

    local template_file="${TEMPLATES_DIR}/traefik/${traefik_template}"
    local output_file="/tmp/${SERVICE_NAME}-traefik.yml"

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}✗${NC} Traefik template not found: ${traefik_template}"
        exit 1
    fi

    # Substitute variables (including PORT with default)
    local port="${PATTERN_VARS[port]:-8080}"

    cp "$template_file" "$output_file"
    sed -i "s/{{SERVICE_NAME}}/${SERVICE_NAME}/g" "$output_file"
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" "$output_file"
    sed -i "s/{{PORT}}/${port}/g" "$output_file"

    local routers_file="${HOME}/containers/config/traefik/dynamic/routers.yml"

    if [[ ! -f "$routers_file" ]]; then
        echo -e "${RED}✗${NC} Traefik routers.yml not found: ${routers_file}"
        exit 1
    fi

    # Backup routers.yml before any modification
    cp "$routers_file" "${routers_file}.backup-$(date +%Y%m%d-%H%M%S)"

    echo -e "${GREEN}✓${NC} Traefik routing generated: $output_file"

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "Preview:"
        cat "$output_file"
    fi

    echo ""
}

append_to_routers() {
    local traefik_template="${PATTERN_VARS[traefik_template]}"

    # Skip if no routing to append
    if [[ -z "$traefik_template" || "$traefik_template" == "none" ]]; then
        return 0
    fi

    local rendered_config="/tmp/${SERVICE_NAME}-traefik.yml"
    local routers_file="${HOME}/containers/config/traefik/dynamic/routers.yml"

    if [[ ! -f "$rendered_config" ]]; then
        echo -e "${YELLOW}⚠${NC} No Traefik config to append"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would append to: $routers_file"
        echo ""
        echo "Router entry:"
        grep -A 20 "SERVICE_NAME\|${SERVICE_NAME}" "$rendered_config" 2>/dev/null | head -25 || true
        return 0
    fi

    echo -e "${BLUE}=== Updating Traefik Configuration ===${NC}"
    echo ""

    # Duplicate detection
    if grep -q "^    ${SERVICE_NAME}-secure:" "$routers_file"; then
        echo -e "${RED}✗${NC} Router '${SERVICE_NAME}-secure' already exists in routers.yml"
        echo "  Remove the existing entry first or use a different service name"
        rm -f "$rendered_config"
        exit 1
    fi

    # Use Python for YAML-aware insertion
    python3 << PYEOF
import yaml
import sys
import re

routers_file = "${routers_file}"
rendered_file = "${rendered_config}"
service_name = "${SERVICE_NAME}"

# Read the rendered template to extract router and service blocks
with open(rendered_file) as f:
    rendered_lines = f.readlines()

# Extract router lines (between first comment and "# Append under http.services:")
router_lines = []
service_lines = []
in_services = False

for line in rendered_lines:
    stripped = line.rstrip()
    # Skip template comment lines at the top
    if stripped.startswith('# Traefik route fragment') or stripped.startswith('# Authenticated') or stripped.startswith('# Public') or stripped.startswith('# Admin') or stripped.startswith('# API') or stripped.startswith('# Native auth') or stripped.startswith('# Use for:'):
        continue
    if stripped.startswith('# Append'):
        continue
    if '# Append under http.services:' in stripped:
        in_services = True
        continue
    if in_services:
        service_lines.append(line.rstrip('\n'))
    else:
        router_lines.append(line.rstrip('\n'))

# Read existing routers.yml
with open(routers_file) as f:
    existing = f.read()

# Validate existing YAML first
try:
    yaml.safe_load(existing)
except yaml.YAMLError as e:
    print(f"ERROR: Existing routers.yml has invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)

# Find insertion points using line-based approach
lines = existing.split('\n')

# Find the services section start
services_line_idx = None
for i, line in enumerate(lines):
    if re.match(r'^  services:', line):
        services_line_idx = i
        break

if services_line_idx is None:
    print("ERROR: Cannot find 'services:' section in routers.yml", file=sys.stderr)
    sys.exit(1)

# Insert router lines before the services section
# Insert service lines after the last service entry (end of file or before middlewares)
# Find middlewares section (if exists)
middlewares_line_idx = None
for i, line in enumerate(lines):
    if re.match(r'^  middlewares:', line):
        middlewares_line_idx = i
        break

# Build output
output_lines = []

# Add everything up to services section, then insert router
for i, line in enumerate(lines):
    if i == services_line_idx:
        # Insert router lines before services section
        for rl in router_lines:
            if rl.strip():  # Skip empty lines
                output_lines.append(rl)
        output_lines.append('')  # blank line separator
    output_lines.append(line)

# Append service lines at the appropriate location
if middlewares_line_idx is not None:
    # Insert before middlewares section
    new_output = []
    output_idx = 0
    # Find middlewares in our output (index shifted by router insertion)
    for i, line in enumerate(output_lines):
        if re.match(r'^  middlewares:', line):
            # Insert service lines here
            new_output.append('')
            for sl in service_lines:
                if sl.strip():
                    new_output.append(sl)
            new_output.append('')
        new_output.append(line)
    output_lines = new_output
else:
    # Append at end of file
    output_lines.append('')
    for sl in service_lines:
        if sl.strip():
            output_lines.append(sl)

# Write output
with open(routers_file, 'w') as f:
    f.write('\n'.join(output_lines))
    if not output_lines[-1] == '':
        f.write('\n')

print("OK")
PYEOF

    local py_exit=$?
    rm -f "$rendered_config"

    if [[ $py_exit -ne 0 ]]; then
        echo -e "${RED}✗${NC} Failed to update routers.yml"
        echo "  Restoring from backup..."
        local latest_backup
        latest_backup=$(ls -t "${routers_file}.backup-"* 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" "$routers_file"
            echo -e "${GREEN}✓${NC} Restored from: $latest_backup"
        fi
        exit 1
    fi

    # Validate the result
    if [[ -x "${SCRIPTS_DIR}/validate-traefik-config.sh" ]]; then
        if ! "${SCRIPTS_DIR}/validate-traefik-config.sh" "$routers_file" > /dev/null 2>&1; then
            echo -e "${RED}✗${NC} Post-insertion validation failed"
            echo "  Restoring from backup..."
            local latest_backup
            latest_backup=$(ls -t "${routers_file}.backup-"* 2>/dev/null | head -1)
            if [[ -n "$latest_backup" ]]; then
                cp "$latest_backup" "$routers_file"
                echo -e "${GREEN}✓${NC} Restored from: $latest_backup"
            fi
            exit 1
        fi
    fi

    echo -e "${GREEN}✓${NC} Routing added to routers.yml (YAML-validated)"
    echo ""
}

reload_traefik() {
    local traefik_template="${PATTERN_VARS[traefik_template]}"

    # Skip if no routing was added
    if [[ -z "$traefik_template" || "$traefik_template" == "none" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would reload Traefik"
        return 0
    fi

    echo -e "${BLUE}=== Reloading Traefik ===${NC}"
    echo ""

    if podman exec traefik kill -SIGHUP 1 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Traefik reloaded (SIGHUP)"
    else
        echo -e "${CYAN}ℹ${NC} Traefik will auto-reload in ~60s"
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
    local traefik_template="${PATTERN_VARS[traefik_template]}"

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

        # Add routing check if Traefik routing was configured
        if [[ -n "$traefik_template" && "$traefik_template" != "none" ]]; then
            echo "  ☐ Verify routing: grep -A 10 '${SERVICE_NAME}-secure' ~/containers/config/traefik/dynamic/routers.yml"
            echo "  ☐ Test external access: curl -I https://${HOSTNAME}"
        fi
    fi

    echo ""
    echo -e "${GREEN}✓ Deployment complete!${NC}"

    # Show service access info
    if [[ -n "$traefik_template" && "$traefik_template" != "none" ]]; then
        echo ""
        echo "  Service: systemctl --user status ${SERVICE_NAME}.service"
        echo "  Access:  https://${HOSTNAME}"
    else
        echo ""
        echo "  Service: systemctl --user status ${SERVICE_NAME}.service"
        echo "  Note:    Internal service (no external routing)"
    fi

    echo ""
}

##############################################################################
# Context Logging
##############################################################################

log_deployment_to_context() {
    local context_script="$HOME/containers/.claude/context/scripts/append-deployment.sh"

    # Skip if context logging not available
    if [[ ! -x "$context_script" ]]; then
        return 0
    fi

    # Extract networks from quadlet
    local networks=""
    if [[ -f "$HOME/.config/containers/systemd/${SERVICE_NAME}.container" ]]; then
        networks=$(grep "^Network=" "$HOME/.config/containers/systemd/${SERVICE_NAME}.container" | \
                  sed 's/^Network=//' | \
                  tr '\n' ',' | \
                  sed 's/,$//')
    fi

    # If no networks found, use pattern default or "unknown"
    if [[ -z "$networks" ]]; then
        networks="${PATTERN_VARS[networks]:-unknown}"
    fi

    # Get current date
    local deploy_date=$(date +%Y-%m-%d)

    # Prepare notes
    local notes="Auto-logged deployment via deploy-from-pattern.sh"
    if [[ -n "$HOSTNAME" ]]; then
        notes="$notes, accessible at https://$HOSTNAME"
    fi

    # Log to context (suppress errors - non-critical)
    "$context_script" \
        "$SERVICE_NAME" \
        "$deploy_date" \
        "$PATTERN" \
        "$MEMORY" \
        "$networks" \
        "$notes" \
        "pattern-based" 2>/dev/null || true
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
    generate_traefik_routing
    run_prerequisites_check
    validate_quadlet
    deploy_service
    append_to_routers
    reload_traefik
    log_deployment_to_context
    show_post_deployment
}

main "$@"
