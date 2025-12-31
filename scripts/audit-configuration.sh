#!/usr/bin/env bash
# Configuration compliance audit
# Validates adherence to ADR-016 (Configuration Design Principles)

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Paths
QUADLETS_DIR="${HOME}/.config/containers/systemd"
ROUTERS_FILE="${HOME}/containers/config/traefik/dynamic/routers.yml"
MIDDLEWARE_FILE="${HOME}/containers/config/traefik/dynamic/middleware.yml"

##############################################################################
# Principle 1: Separation of Concerns
# Quadlets define deployment, Traefik defines routing
##############################################################################

check_no_traefik_labels() {
    echo -e "${BLUE}=== Checking Traefik Label Separation ===${NC}"
    echo ""

    if [[ ! -d "$QUADLETS_DIR" ]]; then
        echo -e "${YELLOW}⚠${NC} Quadlets directory not found: $QUADLETS_DIR"
        ((CHECKS_WARNING++))
        echo ""
        return 0
    fi

    # Count Traefik labels in quadlets
    local label_count=0
    local files_with_labels=()

    while IFS= read -r quadlet; do
        if grep -q "^Label=traefik\." "$quadlet" 2>/dev/null; then
            label_count=$((label_count + 1))
            files_with_labels+=("$(basename "$quadlet")")
        fi
    done < <(find "$QUADLETS_DIR" -name "*.container" -type f)

    if [[ $label_count -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} No Traefik labels in quadlets (compliant with ADR-016)"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} Found Traefik labels in $label_count quadlet(s) (non-compliant)"
        echo ""
        echo "  Files with labels:"
        for file in "${files_with_labels[@]}"; do
            echo "    - $file"
        done
        echo ""
        echo "  Action: Move routing to ~/containers/config/traefik/dynamic/routers.yml"
        ((CHECKS_FAILED++))
    fi

    echo ""
}

##############################################################################
# Principle 2: Centralized Security Enforcement
# All middleware chains follow fail-fast ordering
##############################################################################

check_middleware_ordering() {
    echo -e "${BLUE}=== Checking Middleware Ordering ===${NC}"
    echo ""

    if [[ ! -f "$ROUTERS_FILE" ]]; then
        echo -e "${YELLOW}⚠${NC} Routers file not found: $ROUTERS_FILE"
        ((CHECKS_WARNING++))
        echo ""
        return 0
    fi

    # Check for common ordering violations
    # This is a simplified check - manual review recommended for complex chains
    local violations=0

    # Informational check only - middleware ordering is complex and context-dependent
    echo -e "${CYAN}ℹ${NC} Middleware ordering should follow fail-fast principle:"
    echo "    1. crowdsec-bouncer@file      (cache lookup - fastest)"
    echo "    2. rate-limit-*@file           (memory check - fast)"
    echo "    3. authelia@file               (database + crypto - expensive)"
    echo "    4. security-headers@file       (response headers - last)"
    echo ""
    echo "  Recommendation: Manually review routers.yml for proper ordering"

    # No automatic pass/fail - informational only
    ((CHECKS_PASSED++))

    echo ""
}

##############################################################################
# Principle 3: Secrets via Platform Primitives
# Prefer Podman secrets (type=env), avoid hardcoded secrets
##############################################################################

check_secrets_usage() {
    echo -e "${BLUE}=== Checking Secrets Management ===${NC}"
    echo ""

    # Count secrets patterns
    local env_secrets=0
    local mount_secrets=0
    local env_files=0

    while IFS= read -r quadlet; do
        # Pattern 2: Secret=name,type=env (recommended)
        local env_count=$(grep -c "Secret=.*type=env" "$quadlet" 2>/dev/null || true)
        env_secrets=$((env_secrets + env_count))

        # Pattern 1: Secret=name,type=mount (acceptable for file:// apps)
        local mount_count=$(grep -c "Secret=.*type=mount" "$quadlet" 2>/dev/null || true)
        mount_secrets=$((mount_secrets + mount_count))

        # Legacy: EnvironmentFile (discouraged for new deployments)
        local env_file_count=$(grep -c "^EnvironmentFile=" "$quadlet" 2>/dev/null || true)
        env_files=$((env_files + env_file_count))
    done < <(find "$QUADLETS_DIR" -name "*.container" -type f)

    echo "  Secrets Pattern Usage:"
    echo "    Pattern 2 (type=env):    $env_secrets secrets (recommended)"
    echo "    Pattern 1 (type=mount):  $mount_secrets secrets (acceptable for file:// apps)"
    echo "    Legacy (EnvironmentFile): $env_files files (discouraged)"

    if [[ $env_files -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}ℹ${NC} Consider migrating EnvironmentFile to Podman secrets (Pattern 2)"
        echo "    See: ADR-016, Principle 3 (Secrets via Platform Primitives)"
    fi

    # No hard pass/fail - informational only
    ((CHECKS_PASSED++))

    echo ""
}

##############################################################################
# Principle 4: Configuration as Code
# All configs in Git, secrets excluded
##############################################################################

check_gitignore_coverage() {
    echo -e "${BLUE}=== Checking .gitignore Coverage ===${NC}"
    echo ""

    local gitignore="${HOME}/containers/.gitignore"

    if [[ ! -f "$gitignore" ]]; then
        echo -e "${RED}✗${NC} .gitignore not found"
        ((CHECKS_FAILED++))
        echo ""
        return 1
    fi

    # Check for critical patterns
    local missing_patterns=()

    [[ $(grep -c "^\*\.key$" "$gitignore" 2>/dev/null || echo 0) -eq 0 ]] && missing_patterns+=("*.key")
    [[ $(grep -c "^\*\.pem$" "$gitignore" 2>/dev/null || echo 0) -eq 0 ]] && missing_patterns+=("*.pem")
    [[ $(grep -c "^\*\.env$" "$gitignore" 2>/dev/null || echo 0) -eq 0 ]] && missing_patterns+=("*.env")
    [[ $(grep -c "^\*secret\*$" "$gitignore" 2>/dev/null || echo 0) -eq 0 ]] && missing_patterns+=("*secret*")
    [[ $(grep -c "^acme\.json$" "$gitignore" 2>/dev/null || echo 0) -eq 0 ]] && missing_patterns+=("acme.json")

    if [[ ${#missing_patterns[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} .gitignore covers common secret patterns"
        ((CHECKS_PASSED++))
    else
        echo -e "${YELLOW}⚠${NC} Missing .gitignore patterns:"
        for pattern in "${missing_patterns[@]}"; do
            echo "    - $pattern"
        done
        ((CHECKS_WARNING++))
    fi

    echo ""
}

##############################################################################
# Principle 6: Service Discovery via Naming Convention
# Container names match service hostnames
##############################################################################

check_service_discovery() {
    echo -e "${BLUE}=== Checking Service Discovery Naming ===${NC}"
    echo ""

    if [[ ! -f "$ROUTERS_FILE" ]]; then
        echo -e "${YELLOW}⚠${NC} Routers file not found, skipping"
        ((CHECKS_WARNING++))
        echo ""
        return 0
    fi

    # Extract service names from routers.yml (router names ending in -secure)
    local mismatches=0

    while IFS= read -r router; do
        # Router name format: service-name-secure
        local service_name="${router%-secure}"

        # Check if corresponding container exists
        if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service_name}$"; then
            echo -e "${YELLOW}⚠${NC} Router '$router' has no running container '$service_name'"
            mismatches=$((mismatches + 1))
        fi
    done < <(grep "^    [a-z0-9-]*-secure:" "$ROUTERS_FILE" | sed 's/:$//' | awk '{print $1}')

    if [[ $mismatches -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All routed services have matching containers"
        ((CHECKS_PASSED++))
    else
        echo ""
        echo "  Note: Some routed services may be stopped (not necessarily an error)"
        ((CHECKS_WARNING++))
    fi

    echo ""
}

##############################################################################
# Additional Checks
##############################################################################

check_routers_match_services() {
    echo -e "${BLUE}=== Checking Router/Service Consistency ===${NC}"
    echo ""

    if [[ ! -f "$ROUTERS_FILE" ]]; then
        echo -e "${YELLOW}⚠${NC} Routers file not found"
        ((CHECKS_WARNING++))
        echo ""
        return 0
    fi

    # Extract router section only (between "routers:" and "services:")
    local routers_section=$(sed -n '/^  routers:/,/^  services:/p' "$ROUTERS_FILE" | head -n -1)

    # Count routers
    local router_count=$(echo "$routers_section" | grep -c "^    [a-z0-9-]*:" || echo 0)

    echo -e "${CYAN}ℹ${NC} Found $router_count routers in routers.yml"
    echo ""
    echo "  Recommendation: Manually verify router → service mappings in routers.yml"

    # Simplified check - just informational
    ((CHECKS_PASSED++))

    echo ""
}

##############################################################################
# Summary
##############################################################################

show_summary() {
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Configuration Compliance Audit Summary        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${GREEN}✓ Passed:${NC}  $CHECKS_PASSED"
    echo -e "  ${RED}✗ Failed:${NC}  $CHECKS_FAILED"
    echo -e "  ${YELLOW}⚠ Warnings:${NC} $CHECKS_WARNING"

    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ System is compliant with ADR-016 (Configuration Design Principles)${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Compliance issues detected - review failures above${NC}"
        echo ""
        echo "  Reference: ~/containers/docs/00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md"
        echo ""
        return 1
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Configuration Compliance Audit (ADR-016)      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    check_no_traefik_labels
    check_middleware_ordering
    check_secrets_usage
    check_gitignore_coverage
    check_service_discovery
    check_routers_match_services

    show_summary
}

main "$@"
