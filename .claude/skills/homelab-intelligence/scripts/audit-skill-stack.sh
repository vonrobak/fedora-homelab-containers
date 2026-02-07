#!/usr/bin/env bash
# audit-skill-stack.sh - Detect drift between skill templates and production
# Part of homelab-intelligence skill
set -euo pipefail

CONTAINERS_DIR="${HOME}/containers"
SKILL_DIR="${CONTAINERS_DIR}/.claude/skills/homelab-deployment"
QUADLETS_DIR="${CONTAINERS_DIR}/quadlets"
AGENTS_DIR="${CONTAINERS_DIR}/.claude/agents"
ROUTERS_FILE="${CONTAINERS_DIR}/config/traefik/dynamic/routers.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCORE=100
ISSUES=0
WARNINGS=0

header() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARNINGS=$((WARNINGS+1)); SCORE=$((SCORE-2)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; ISSUES=$((ISSUES+1)); SCORE=$((SCORE-5)); }

##############################################################################
# 1. Template vs Production: Static IPs (ADR-018)
##############################################################################
check_static_ips() {
    header "ADR-018: Static IP compliance in templates"

    local templates_missing_ip=0
    for template in "${SKILL_DIR}/templates/quadlets/"*.container; do
        [[ -f "$template" ]] || continue
        local name
        name=$(basename "$template")
        if grep -q "^Network=" "$template" && ! grep -q ":ip=" "$template"; then
            # Check if template has placeholder for static IP
            if ! grep -q "STATIC_IP" "$template"; then
                fail "Template ${name}: Network= without static IP placeholder"
                templates_missing_ip=$((templates_missing_ip+1))
            fi
        fi
    done

    # Check production quadlets have static IPs on multi-network containers
    local prod_missing=0
    for quadlet in "${QUADLETS_DIR}"/*.container; do
        [[ -f "$quadlet" ]] || continue
        local name
        name=$(basename "$quadlet")
        local network_count
        network_count=$(grep -c "^Network=" "$quadlet" || true)
        if [[ $network_count -gt 1 ]]; then
            local missing
            missing=$(grep "^Network=" "$quadlet" | grep -cv ":ip=" || true)
            if [[ $missing -gt 0 ]]; then
                warn "Production ${name}: ${missing}/${network_count} networks missing static IP"
                prod_missing=$((prod_missing+1))
            fi
        fi
    done

    [[ $templates_missing_ip -eq 0 ]] && pass "All templates have static IP placeholders" || true
    [[ $prod_missing -eq 0 ]] && pass "All multi-network production quadlets have static IPs" || true
}

##############################################################################
# 2. Template vs Production: Quadlet features
##############################################################################
check_quadlet_features() {
    header "Quadlet feature parity (templates vs production)"

    local features=("Slice=container.slice" "Requires=.*-network.service" "MemorySwapMax=")
    local feature_names=("Slice directive" "Requires network services" "MemorySwapMax")

    for i in "${!features[@]}"; do
        local feature="${features[$i]}"
        local fname="${feature_names[$i]}"

        # Count production quadlets using this feature
        local prod_count=0
        local prod_total=0
        for quadlet in "${QUADLETS_DIR}"/*.container; do
            [[ -f "$quadlet" ]] || continue
            prod_total=$((prod_total+1))
            grep -qE "$feature" "$quadlet" && prod_count=$((prod_count+1)) || true
        done

        # Check if templates have this feature
        local tmpl_has=false
        for template in "${SKILL_DIR}/templates/quadlets/"*.container; do
            [[ -f "$template" ]] || continue
            if grep -qE "$feature" "$template"; then
                tmpl_has=true
                break
            fi
        done

        if [[ $prod_count -gt 0 ]] && [[ "$tmpl_has" == "false" ]]; then
            fail "${fname}: used in ${prod_count}/${prod_total} production quadlets but absent from templates"
        elif [[ $prod_count -gt 0 ]] && [[ "$tmpl_has" == "true" ]]; then
            pass "${fname}: present in templates (${prod_count}/${prod_total} production)"
        fi
    done
}

##############################################################################
# 3. Traefik service naming
##############################################################################
check_traefik_naming() {
    header "Traefik service naming consistency"

    for template in "${SKILL_DIR}/templates/traefik/"*.yml; do
        [[ -f "$template" ]] || continue
        local name
        name=$(basename "$template")

        # Check for -service suffix in service references
        if grep -q "SERVICE_NAME}}-service" "$template"; then
            # Check if production uses -service suffix
            local prod_has_suffix
            prod_has_suffix=$(grep -c "\-service:" "$ROUTERS_FILE" || true)
            if [[ $prod_has_suffix -eq 0 ]]; then
                fail "Template ${name}: uses '-service' suffix but production routers.yml does not"
            fi
        else
            pass "Template ${name}: service naming consistent"
        fi
    done
}

##############################################################################
# 4. Traefik template features vs production
##############################################################################
check_traefik_features() {
    header "Traefik template features vs production"

    for template in "${SKILL_DIR}/templates/traefik/"*.yml; do
        [[ -f "$template" ]] || continue
        local name
        name=$(basename "$template")

        # Check for passHostHeader (not in production)
        if grep -q "passHostHeader" "$template"; then
            if ! grep -q "passHostHeader" "$ROUTERS_FILE"; then
                warn "Template ${name}: has passHostHeader but production does not"
            fi
        fi

        # Check for healthCheck (not in production)
        if grep -q "healthCheck" "$template"; then
            if ! grep -q "healthCheck" "$ROUTERS_FILE"; then
                warn "Template ${name}: has healthCheck but production does not"
            fi
        fi
    done

    # Check for native-auth template
    if [[ ! -f "${SKILL_DIR}/templates/traefik/native-auth-service.yml" ]]; then
        local native_auth_count
        native_auth_count=$(grep -c "NO authelia\|NO Authelia\|native auth\|built-in auth" "$ROUTERS_FILE" || true)
        if [[ $native_auth_count -gt 0 ]]; then
            fail "No native-auth template exists but ${native_auth_count} production services use native auth"
        fi
    else
        pass "native-auth-service.yml template exists"
    fi
}

##############################################################################
# 5. Infrastructure-architect network list
##############################################################################
check_agent_networks() {
    header "Infrastructure-architect network knowledge"

    local agent_file="${AGENTS_DIR}/infrastructure-architect.md"
    if [[ ! -f "$agent_file" ]]; then
        fail "infrastructure-architect.md not found"
        return
    fi

    for network_file in "${QUADLETS_DIR}"/*.network; do
        [[ -f "$network_file" ]] || continue
        local net_name
        net_name=$(basename "$network_file" .network)
        local systemd_name="systemd-${net_name}"

        if ! grep -q "$systemd_name" "$agent_file"; then
            fail "Network ${systemd_name} missing from infrastructure-architect"
        fi
    done

    # Count known vs actual
    local actual_count
    actual_count=$(find "${QUADLETS_DIR}" -name "*.network" | wc -l)
    local known_count
    known_count=$(grep -c "systemd-" "${agent_file}" || true)
    pass "Network check complete (${actual_count} networks in production)"
}

##############################################################################
# 6. ADR-016: Traefik labels in stacks
##############################################################################
check_adr016_compliance() {
    header "ADR-016: No Traefik labels in stacks/quadlets"

    # Check stacks
    for stack in "${SKILL_DIR}/stacks/"*.yml; do
        [[ -f "$stack" ]] || continue
        local name
        name=$(basename "$stack")
        if grep -q "traefik.enable\|traefik.http" "$stack"; then
            fail "Stack ${name}: contains Traefik labels (ADR-016 violation)"
        else
            pass "Stack ${name}: no Traefik labels"
        fi
    done

    # Check production quadlets for Traefik LABELS (not mentions in comments/names)
    for quadlet in "${QUADLETS_DIR}"/*.container; do
        [[ -f "$quadlet" ]] || continue
        local name
        name=$(basename "$quadlet")
        # Skip traefik's own quadlet and containers that legitimately reference traefik
        [[ "$name" == "traefik.container" ]] && continue
        if grep -qE "^Label=.*traefik\." "$quadlet"; then
            fail "Production ${name}: contains Traefik labels (ADR-016 violation)"
        fi
    done
}

##############################################################################
# 7. Pattern network names vs actual networks
##############################################################################
check_pattern_networks() {
    header "Pattern network references vs actual networks"

    local actual_networks=()
    for network_file in "${QUADLETS_DIR}"/*.network; do
        [[ -f "$network_file" ]] || continue
        actual_networks+=("systemd-$(basename "$network_file" .network)")
    done

    for pattern in "${SKILL_DIR}/patterns/"*.yml; do
        [[ -f "$pattern" ]] || continue
        local name
        name=$(basename "$pattern" .yml)

        # Extract network references
        local nets
        nets=$(grep -oE "systemd-[a-z_]+" "$pattern" | sort -u || true)
        for net in $nets; do
            local found=false
            for actual in "${actual_networks[@]}"; do
                [[ "$net" == "$actual" ]] && found=true && break
            done
            # Allow template placeholders like systemd-{app}_services and systemd-database
            if [[ "$found" == "false" ]] && [[ "$net" != *"{"* ]] && [[ "$net" != "systemd-database" ]]; then
                warn "Pattern ${name}: references ${net} which doesn't exist"
            fi
        done
    done

    pass "Pattern network audit complete"
}

##############################################################################
# 8. Database pattern secrets compliance
##############################################################################
check_secrets_compliance() {
    header "Database pattern secrets compliance"

    if grep -q "POSTGRES_PASSWORD={" "${SKILL_DIR}/patterns/database-service.yml" 2>/dev/null; then
        if ! grep -q "Secret=" "${SKILL_DIR}/patterns/database-service.yml" 2>/dev/null; then
            fail "database-service.yml: uses plaintext password, not Podman secrets"
        fi
    fi

    # Check database template
    if grep -q "Secret=" "${SKILL_DIR}/templates/quadlets/database.container" 2>/dev/null; then
        pass "database.container template: uses Podman secrets"
    fi
}

##############################################################################
# Summary
##############################################################################
print_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Skill Stack Audit Summary                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $SCORE -lt 0 ]]; then
        SCORE=0
    fi

    local color=$GREEN
    [[ $SCORE -lt 80 ]] && color=$YELLOW
    [[ $SCORE -lt 60 ]] && color=$RED

    echo -e "  Compliance Score: ${color}${SCORE}/100${NC}"
    echo -e "  Issues (FAIL):    ${RED}${ISSUES}${NC}"
    echo -e "  Warnings (WARN):  ${YELLOW}${WARNINGS}${NC}"
    echo ""

    if [[ $ISSUES -gt 0 ]]; then
        echo -e "  ${RED}Action required:${NC} Fix FAILed items to align skills with production"
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}Review warnings:${NC} Some items may need attention"
    else
        echo -e "  ${GREEN}All checks passed!${NC} Skills are aligned with production"
    fi
    echo ""
}

##############################################################################
# Main
##############################################################################
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Skill Stack Audit                            ║${NC}"
    echo -e "${CYAN}║  Template-to-Production Drift Detection       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"

    check_static_ips
    check_quadlet_features
    check_traefik_naming
    check_traefik_features
    check_agent_networks
    check_adr016_compliance
    check_pattern_networks
    check_secrets_compliance

    print_summary
}

main "$@"
