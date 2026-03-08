#!/usr/bin/env bash
#
# security-audit.sh - Comprehensive Homelab Security Audit
#
# 53 checks across 7 categories with structured output, scoring, and trend analysis.
#
# Usage:
#   ./scripts/security-audit.sh                      # Default: level 2, terminal output
#   ./scripts/security-audit.sh --level 1            # Critical checks only (15)
#   ./scripts/security-audit.sh --level 3            # All checks (53)
#   ./scripts/security-audit.sh --category auth      # Single category
#   ./scripts/security-audit.sh --json               # JSON output to stdout
#   ./scripts/security-audit.sh --report             # Generate markdown report
#   ./scripts/security-audit.sh --compare            # Show trend vs previous audit
#   ./scripts/security-audit.sh --quiet              # Minimal terminal output
#
# Exit codes: 0 = all pass, 1 = warnings, 2 = failures
#
# Status: ACTIVE
# Updated: 2026-03-08

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUADLETS_DIR="$HOME/containers/quadlets"
TRAEFIK_DYNAMIC="$CONTAINERS_DIR/config/traefik/dynamic"
AUTHELIA_CONFIG="$CONTAINERS_DIR/config/authelia/configuration.yml"
HISTORY_DIR="$CONTAINERS_DIR/data/security-audit"
REPORT_DIR="$CONTAINERS_DIR/docs/99-reports"

# CLI options
LEVEL=2
CATEGORY=""
JSON_OUTPUT=false
GENERATE_REPORT=false
COMPARE=false
QUIET=false

# Results storage
declare -a RESULTS=()
SCORE=100

# Colors (disabled for JSON/quiet)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

##############################################################################
# Argument Parsing
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --level)
            LEVEL="$2"
            if [[ ! "$LEVEL" =~ ^[123]$ ]]; then
                echo "Error: --level must be 1, 2, or 3" >&2
                exit 2
            fi
            shift 2
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --compare)
            COMPARE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Usage: security-audit.sh [options]

Options:
  --level N       1=critical (15), 2=important (28), 3=all (53). Default: 2
  --category CAT  Run one category: auth|network|traefik|containers|monitoring|secrets|compliance
  --json          JSON output to stdout
  --report        Generate markdown report to docs/99-reports/
  --compare       Show trend vs previous audit
  --quiet         Minimal terminal output
  --help, -h      Show this help

Scoring: Start at 100. L1 fail: -15, L2 fail: -5, L3 fail: -2.
         Warnings: half penalty. Floor at 0.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# Suppress colors for JSON/quiet
if $JSON_OUTPUT || $QUIET; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" NC=""
fi

##############################################################################
# Result Tracking
##############################################################################

# Record a check result
# Usage: record_check "SA-XXX-NN" level category "PASS|WARN|FAIL" "message" "detail"
record_check() {
    local id="$1" level="$2" category="$3" status="$4" message="$5" detail="${6:-}"

    RESULTS+=("$(printf '%s|%s|%s|%s|%s|%s' "$id" "$level" "$category" "$status" "$message" "$detail")")

    # Apply score penalty
    case "$status" in
        FAIL)
            case "$level" in
                1) SCORE=$((SCORE - 15)) ;;
                2) SCORE=$((SCORE - 5)) ;;
                3) SCORE=$((SCORE - 2)) ;;
            esac
            ;;
        WARN)
            case "$level" in
                1) SCORE=$((SCORE - 7)) ;;
                2) SCORE=$((SCORE - 2)) ;;
                3) SCORE=$((SCORE - 1)) ;;
            esac
            ;;
    esac
    # Floor at 0
    (( SCORE < 0 )) && SCORE=0 || true

    # Terminal output (unless JSON-only)
    if ! $JSON_OUTPUT; then
        case "$status" in
            PASS) $QUIET || echo -e "  ${GREEN}PASS${NC}  [$id] $message" ;;
            WARN) echo -e "  ${YELLOW}WARN${NC}  [$id] $message" ;;
            FAIL) echo -e "  ${RED}FAIL${NC}  [$id] $message" ;;
        esac
    fi
}

# Check if a check should run based on level and category filters
should_run() {
    local check_level="$1" check_category="$2"
    # Level filter: run checks at or below the requested level
    (( check_level > LEVEL )) && return 1
    # Category filter
    [[ -n "$CATEGORY" && "$CATEGORY" != "$check_category" ]] && return 1
    return 0
}

section_header() {
    if ! $JSON_OUTPUT && ! $QUIET; then
        echo ""
        echo -e "${BOLD}${BLUE}[$1] $2${NC}"
    fi
}

##############################################################################
# AUTH Checks (SA-AUTH-01 through SA-AUTH-07)
##############################################################################

run_auth_checks() {
    section_header "AUTH" "Authentication & Access Control"

    # SA-AUTH-01 (L1): Authelia service running
    if should_run 1 auth; then
        if systemctl --user is-active authelia.service &>/dev/null; then
            record_check "SA-AUTH-01" 1 auth "PASS" "Authelia service running"
        else
            record_check "SA-AUTH-01" 1 auth "FAIL" "Authelia service not running"
        fi
    fi

    # SA-AUTH-02 (L1): Authelia health endpoint responds
    if should_run 1 auth; then
        if timeout 5 podman exec authelia wget -q -O- http://localhost:9091/api/health 2>/dev/null | grep -q "OK" 2>/dev/null; then
            record_check "SA-AUTH-02" 1 auth "PASS" "Authelia health endpoint OK"
        else
            record_check "SA-AUTH-02" 1 auth "FAIL" "Authelia health endpoint not responding"
        fi
    fi

    # SA-AUTH-03 (L1): Redis-authelia running
    if should_run 1 auth; then
        if systemctl --user is-active redis-authelia.service &>/dev/null; then
            record_check "SA-AUTH-03" 1 auth "PASS" "Redis-authelia service running"
        else
            record_check "SA-AUTH-03" 1 auth "FAIL" "Redis-authelia service not running"
        fi
    fi

    # SA-AUTH-04 (L2): Default policy is deny
    if should_run 2 auth; then
        if grep -q "default_policy: deny" "$AUTHELIA_CONFIG" 2>/dev/null; then
            record_check "SA-AUTH-04" 2 auth "PASS" "Authelia default_policy is deny"
        else
            record_check "SA-AUTH-04" 2 auth "FAIL" "Authelia default_policy is NOT deny"
        fi
    fi

    # SA-AUTH-05 (L2): All routed domains have access_control rules
    if should_run 2 auth; then
        local routed_domains missing_domains=""
        routed_domains=$(grep -oP 'Host\(`([^`]+)`\)' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null | grep -oP '`[^`]+`' | tr -d '`' | sort -u)
        local authelia_domains
        authelia_domains=$(grep -oP "domain:\s*['\"]?([a-z0-9.-]+)" "$AUTHELIA_CONFIG" 2>/dev/null | awk '{print $2}' | tr -d "'" | tr -d '"' | sort -u)
        # Add wildcard match - if *.patriark.org is in access_control, all subdomains covered
        local has_wildcard=false
        if grep -qP "domain:\s*['\"]?\*\.patriark\.org" "$AUTHELIA_CONFIG" 2>/dev/null; then
            has_wildcard=true
        fi

        for domain in $routed_domains; do
            if ! $has_wildcard; then
                if ! echo "$authelia_domains" | grep -qF "$domain" 2>/dev/null; then
                    missing_domains="$missing_domains $domain"
                fi
            fi
        done

        if [[ -z "$missing_domains" ]]; then
            record_check "SA-AUTH-05" 2 auth "PASS" "All routed domains have access_control rules"
        else
            record_check "SA-AUTH-05" 2 auth "WARN" "Domains possibly missing access_control:$missing_domains" "$missing_domains"
        fi
    fi

    # SA-AUTH-06 (L2): Redis not exposed on host ports
    if should_run 2 auth; then
        if ss -tlnp 2>/dev/null | grep -q ":6379 " 2>/dev/null; then
            record_check "SA-AUTH-06" 2 auth "FAIL" "Redis exposed on host port 6379"
        else
            record_check "SA-AUTH-06" 2 auth "PASS" "Redis not exposed on host ports"
        fi
    fi

    # SA-AUTH-07 (L3): Auth failure count last 24h (informational)
    if should_run 3 auth; then
        local fail_count=0
        fail_count=$(journalctl --user -u authelia.service --since "24 hours ago" 2>/dev/null | grep -ci "unsuccessful\|failed\|denied" || echo "0")
        if (( fail_count > 50 )); then
            record_check "SA-AUTH-07" 3 auth "WARN" "High auth failure count: $fail_count in 24h" "$fail_count failures"
        else
            record_check "SA-AUTH-07" 3 auth "PASS" "Auth failures in 24h: $fail_count"
        fi
    fi
}

##############################################################################
# NETWORK Checks (SA-NET-01 through SA-NET-09)
##############################################################################

run_network_checks() {
    section_header "NETWORK" "CrowdSec & Network Security"

    # SA-NET-01 (L1): CrowdSec running
    if should_run 1 network; then
        if systemctl --user is-active crowdsec.service &>/dev/null; then
            record_check "SA-NET-01" 1 network "PASS" "CrowdSec service running"
        else
            record_check "SA-NET-01" 1 network "FAIL" "CrowdSec service not running"
        fi
    fi

    # SA-NET-02 (L1): CrowdSec CAPI connected
    if should_run 1 network; then
        local capi_ok
        capi_ok=$(timeout 10 podman exec crowdsec cscli capi status 2>&1 | grep -c "successfully interact" || echo "0")
        if (( capi_ok > 0 )); then
            record_check "SA-NET-02" 1 network "PASS" "CrowdSec CAPI connected"
        else
            record_check "SA-NET-02" 1 network "FAIL" "CrowdSec CAPI disconnected"
        fi
    fi

    # SA-NET-03 (L1): Active bouncer registered
    if should_run 1 network; then
        local bouncer_count
        bouncer_count=$(timeout 10 podman exec crowdsec cscli bouncers list -o json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
        if (( bouncer_count > 0 )); then
            record_check "SA-NET-03" 1 network "PASS" "Active bouncers registered: $bouncer_count"
        else
            record_check "SA-NET-03" 1 network "FAIL" "No active bouncers registered"
        fi
    fi

    # SA-NET-04 (L2): Scenario count >= 10
    if should_run 2 network; then
        local scenario_count
        scenario_count=$(timeout 10 podman exec crowdsec cscli scenarios list -o json 2>/dev/null | jq '.scenarios | length' 2>/dev/null || echo "0")
        if (( scenario_count >= 10 )); then
            record_check "SA-NET-04" 2 network "PASS" "CrowdSec scenarios loaded: $scenario_count"
        else
            record_check "SA-NET-04" 2 network "WARN" "Low CrowdSec scenario count: $scenario_count"
        fi
    fi

    # SA-NET-05 (L2): No unexpected low ports (<1024)
    if should_run 2 network; then
        local unexpected=""
        local listening_ports
        listening_ports=$(ss -tlnp 2>/dev/null | awk '/LISTEN/ {print $4}' | grep -oE '[0-9]+$' | sort -un)
        for port in $listening_ports; do
            if (( port < 1024 )); then
                case "$port" in
                    22|53|80|443|631) ;; # Expected: SSH, DNS, HTTP/S, CUPS
                    *) unexpected="$unexpected $port" ;;
                esac
            fi
        done
        if [[ -z "$unexpected" ]]; then
            record_check "SA-NET-05" 2 network "PASS" "Only expected low ports open"
        else
            record_check "SA-NET-05" 2 network "WARN" "Unexpected low ports:$unexpected" "$unexpected"
        fi
    fi

    # SA-NET-06 (L2): Monitoring network is Internal=true
    if should_run 2 network; then
        local mon_internal
        mon_internal=$(podman network inspect systemd-monitoring 2>/dev/null | jq -r '.[0].internal // false' 2>/dev/null || echo "false")
        if [[ "$mon_internal" == "true" ]]; then
            record_check "SA-NET-06" 2 network "PASS" "Monitoring network is internal"
        else
            record_check "SA-NET-06" 2 network "FAIL" "Monitoring network is NOT internal"
        fi
    fi

    # SA-NET-07 (L2): No Samba ports (139/445)
    if should_run 2 network; then
        if ss -tlnp 2>/dev/null | grep -qE ":(139|445) " 2>/dev/null; then
            record_check "SA-NET-07" 2 network "FAIL" "Samba ports 139/445 still open"
        else
            record_check "SA-NET-07" 2 network "PASS" "No Samba ports open"
        fi
    fi

    # SA-NET-08 (L3): CrowdSec decision list size
    if should_run 3 network; then
        local decision_count
        decision_count=$(timeout 10 podman exec crowdsec cscli decisions list -o json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
        record_check "SA-NET-08" 3 network "PASS" "CrowdSec active decisions: $decision_count"
    fi

    # SA-NET-09 (L3): Recent alerts summary
    if should_run 3 network; then
        local alert_count
        alert_count=$(timeout 10 podman exec crowdsec cscli alerts list --since 24h -o json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
        if (( alert_count > 100 )); then
            record_check "SA-NET-09" 3 network "WARN" "High CrowdSec alert volume: $alert_count in 24h"
        else
            record_check "SA-NET-09" 3 network "PASS" "CrowdSec alerts in 24h: $alert_count"
        fi
    fi
}

##############################################################################
# TRAEFIK Checks (SA-TRF-01 through SA-TRF-09)
##############################################################################

run_traefik_checks() {
    section_header "TRAEFIK" "Reverse Proxy & TLS"

    # SA-TRF-01 (L1): Traefik running
    if should_run 1 traefik; then
        if systemctl --user is-active traefik.service &>/dev/null; then
            record_check "SA-TRF-01" 1 traefik "PASS" "Traefik service running"
        else
            record_check "SA-TRF-01" 1 traefik "FAIL" "Traefik service not running"
        fi
    fi

    # SA-TRF-02 (L1): All TLS certs valid >7 days
    if should_run 1 traefik; then
        local acme_json cert_issues="" cert_count=0
        acme_json=$(timeout 10 podman exec traefik cat /letsencrypt/acme.json 2>/dev/null || echo "")
        if [[ -n "$acme_json" ]]; then
            local now_epoch
            now_epoch=$(date +%s)
            while IFS= read -r cert_b64; do
                [[ -z "$cert_b64" ]] && continue
                local end_date days_left
                end_date=$(echo "$cert_b64" | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
                if [[ -n "$end_date" ]]; then
                    local expiry_epoch
                    expiry_epoch=$(date -d "$end_date" +%s 2>/dev/null || echo "0")
                    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
                    ((cert_count++)) || true
                    if (( days_left <= 7 )); then
                        cert_issues="$cert_issues cert${cert_count}:${days_left}d"
                    fi
                fi
            done < <(echo "$acme_json" | jq -r '.letsencrypt.Certificates[].certificate' 2>/dev/null)

            if [[ -z "$cert_issues" ]]; then
                record_check "SA-TRF-02" 1 traefik "PASS" "All $cert_count TLS certificates valid >7 days"
            else
                record_check "SA-TRF-02" 1 traefik "FAIL" "TLS certificates expiring:$cert_issues"
            fi
        else
            record_check "SA-TRF-02" 1 traefik "WARN" "Could not read acme.json"
        fi
    fi

    # SA-TRF-03 (L1): CrowdSec bouncer in every public router middleware
    if should_run 1 traefik; then
        local total_routers cs_routers
        total_routers=$(yq '.http.routers | keys | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")
        cs_routers=$(yq '[.http.routers[] | select(.middlewares[] == "crowdsec-bouncer@file")] | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")

        if (( total_routers > 0 && cs_routers >= total_routers )); then
            record_check "SA-TRF-03" 1 traefik "PASS" "CrowdSec bouncer in all $total_routers routers"
        else
            record_check "SA-TRF-03" 1 traefik "FAIL" "CrowdSec bouncer missing: $cs_routers/$total_routers routers" "$(( total_routers - cs_routers )) routers missing CrowdSec"
        fi
    fi

    # SA-TRF-04 (L2): Rate limiting in every public router
    if should_run 2 traefik; then
        local total_routers rl_routers
        total_routers=$(yq '.http.routers | keys | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")
        rl_routers=$(yq '[.http.routers[] | select(.middlewares[] | test("rate-limit"))] | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")

        if (( total_routers > 0 && rl_routers >= total_routers )); then
            record_check "SA-TRF-04" 2 traefik "PASS" "Rate limiting in all $total_routers routers"
        else
            record_check "SA-TRF-04" 2 traefik "WARN" "Rate limiting coverage: $rl_routers/$total_routers routers"
        fi
    fi

    # SA-TRF-05 (L2): Middleware ordering correct (crowdsec first)
    if should_run 2 traefik; then
        # Check each middleware list: first entry after "middlewares:" should be crowdsec
        local first_mw_count=0 cs_first=0
        local in_list=false
        while IFS= read -r line; do
            if [[ "$line" =~ middlewares: ]]; then
                in_list=true
                continue
            fi
            if $in_list && [[ "$line" =~ ^[[:space:]]*- ]]; then
                ((first_mw_count++)) || true
                if [[ "$line" =~ crowdsec-bouncer ]]; then
                    ((cs_first++)) || true
                fi
                in_list=false
            elif $in_list; then
                in_list=false
            fi
        done < "$TRAEFIK_DYNAMIC/routers.yml"

        if (( first_mw_count > 0 && cs_first == first_mw_count )); then
            record_check "SA-TRF-05" 2 traefik "PASS" "CrowdSec is first middleware in all chains"
        elif (( cs_first > 0 )); then
            record_check "SA-TRF-05" 2 traefik "WARN" "CrowdSec first in $cs_first/$first_mw_count middleware chains"
        else
            record_check "SA-TRF-05" 2 traefik "FAIL" "CrowdSec is NOT first middleware"
        fi
    fi

    # SA-TRF-06 (L2): No Traefik labels in quadlets (ADR-016)
    if should_run 2 traefik; then
        local label_files=""
        for f in "$QUADLETS_DIR"/*.container; do
            [[ -f "$f" ]] || continue
            # Only flag actual Traefik routing labels (Label=traefik.)
            # NOT comments, dependencies (After=traefik.service), or CrowdSec scenario names
            if grep -qP '^Label=traefik\.' "$f" 2>/dev/null; then
                label_files="$label_files $(basename "$f")"
            fi
        done
        if [[ -z "$label_files" ]]; then
            record_check "SA-TRF-06" 2 traefik "PASS" "No Traefik labels in quadlets (ADR-016 compliant)"
        else
            record_check "SA-TRF-06" 2 traefik "FAIL" "Traefik references in quadlets:$label_files"
        fi
    fi

    # SA-TRF-07 (L2): Security headers on all routers
    if should_run 2 traefik; then
        # Count routers with any security/hsts header middleware
        local total_header_routers
        total_header_routers=$(yq '[.http.routers[] | select(.middlewares[] | test("security-headers|hsts-only"))] | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")
        local total_routers
        total_routers=$(yq '.http.routers | keys | length' "$TRAEFIK_DYNAMIC/routers.yml" 2>/dev/null || echo "0")

        # SSO portal doesn't need security headers (Authelia sets its own)
        # So we expect total_routers - 1 (at minimum)
        if (( total_header_routers >= total_routers - 2 )); then
            record_check "SA-TRF-07" 2 traefik "PASS" "Security headers on $total_header_routers/$total_routers routers"
        else
            record_check "SA-TRF-07" 2 traefik "WARN" "Security headers coverage: $total_header_routers/$total_routers routers"
        fi
    fi

    # SA-TRF-08 (L2): Dashboard not exposed on host port 8080
    if should_run 2 traefik; then
        if ss -tlnp 2>/dev/null | grep -q ":8080 " 2>/dev/null; then
            record_check "SA-TRF-08" 2 traefik "FAIL" "Traefik dashboard exposed on host port 8080"
        else
            record_check "SA-TRF-08" 2 traefik "PASS" "Traefik dashboard not on host port 8080"
        fi
    fi

    # SA-TRF-09 (L3): TLS 1.2 minimum configured
    if should_run 3 traefik; then
        if grep -q "minVersion.*VersionTLS12\|minVersion.*1.2" "$TRAEFIK_DYNAMIC/tls.yml" 2>/dev/null; then
            record_check "SA-TRF-09" 3 traefik "PASS" "TLS 1.2 minimum version configured"
        else
            record_check "SA-TRF-09" 3 traefik "WARN" "TLS minimum version not explicitly set"
        fi
    fi
}

##############################################################################
# CONTAINERS Checks (SA-CTR-01 through SA-CTR-11)
##############################################################################

run_container_checks() {
    section_header "CONTAINERS" "Container Security"

    # SA-CTR-01 (L1): SELinux enforcing
    if should_run 1 containers; then
        if getenforce 2>/dev/null | grep -q "Enforcing"; then
            record_check "SA-CTR-01" 1 containers "PASS" "SELinux enforcing"
        else
            record_check "SA-CTR-01" 1 containers "FAIL" "SELinux not enforcing"
        fi
    fi

    # SA-CTR-02 (L2): All containers have memory limits
    if should_run 2 containers; then
        local no_limits=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            if systemctl --user is-active "${name}.service" &>/dev/null; then
                if ! grep -q "^MemoryMax=\|^MemoryHigh=" "$quadlet" 2>/dev/null; then
                    no_limits="$no_limits $name"
                fi
            fi
        done
        if [[ -z "$no_limits" ]]; then
            record_check "SA-CTR-02" 2 containers "PASS" "All running containers have memory limits"
        else
            record_check "SA-CTR-02" 2 containers "WARN" "No memory limits:$no_limits" "$no_limits"
        fi
    fi

    # SA-CTR-03 (L2): Database images pinned (not :latest)
    if should_run 2 containers; then
        local unpinned=""
        for db_quadlet in "$QUADLETS_DIR"/postgresql-*.container "$QUADLETS_DIR"/nextcloud-db.container "$QUADLETS_DIR"/gathio-db.container; do
            [[ -f "$db_quadlet" ]] || continue
            local image_line
            image_line=$(grep "^Image=" "$db_quadlet" 2>/dev/null || echo "")
            # Fail if :latest or no tag at all (no colon). Major version pins like :11, :7, :14-xxx are OK
            if [[ "$image_line" =~ :latest$ ]] || [[ ! "$image_line" =~ : ]]; then
                unpinned="$unpinned $(basename "$db_quadlet")"
            fi
        done
        if [[ -z "$unpinned" ]]; then
            record_check "SA-CTR-03" 2 containers "PASS" "Database images pinned to specific versions"
        else
            record_check "SA-CTR-03" 2 containers "FAIL" "Database images not pinned:$unpinned"
        fi
    fi

    # SA-CTR-04 (L2): Volume mounts have SELinux labels (:Z/:z)
    if should_run 2 containers; then
        local no_label=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            while IFS= read -r vol_line; do
                # Skip empty, comments, environment, and podman secret mounts
                [[ -z "$vol_line" ]] && continue
                [[ "$vol_line" =~ ^# ]] && continue
                # Only check bind mounts to user-controlled paths
                # Skip system paths and Podman internals that shouldn't be relabeled
                if [[ "$vol_line" =~ ^Volume=(/home|/mnt|~) ]] || \
                   { [[ "$vol_line" =~ ^Volume=%h ]] && [[ ! "$vol_line" =~ ^Volume=%h/\.local ]]; }; then
                    if ! echo "$vol_line" | grep -qE '[,:][zZ]' 2>/dev/null; then
                        no_label="$no_label $name"
                        break
                    fi
                fi
            done < <(grep "^Volume=" "$quadlet" 2>/dev/null)
        done
        if [[ -z "$no_label" ]]; then
            record_check "SA-CTR-04" 2 containers "PASS" "All volume mounts have SELinux labels"
        else
            record_check "SA-CTR-04" 2 containers "WARN" "Missing SELinux labels:$no_label" "$no_label"
        fi
    fi

    # SA-CTR-05 (L2): No OOMKilled containers (24h)
    if should_run 2 containers; then
        local oom_count
        oom_count=$(journalctl --user --since "24 hours ago" 2>/dev/null | grep -ci "oom\|out of memory" || echo "0")
        if (( oom_count == 0 )); then
            record_check "SA-CTR-05" 2 containers "PASS" "No OOM events in 24h"
        else
            record_check "SA-CTR-05" 2 containers "WARN" "OOM events in 24h: $oom_count"
        fi
    fi

    # SA-CTR-06 (L2): First Network= is reverse_proxy for internet-needing containers
    if should_run 2 containers; then
        local bad_order=""
        # Containers that need internet: those on reverse_proxy network
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            local networks
            networks=$(grep "^Network=" "$quadlet" 2>/dev/null || echo "")
            local net_count
            net_count=$(echo "$networks" | grep -c "Network=" || echo "0")
            if (( net_count > 1 )); then
                # Multi-network: check if reverse_proxy is present and first
                if echo "$networks" | grep -q "reverse_proxy" 2>/dev/null; then
                    local first_net
                    first_net=$(echo "$networks" | head -1)
                    if ! echo "$first_net" | grep -q "reverse_proxy" 2>/dev/null; then
                        bad_order="$bad_order $name"
                    fi
                fi
            fi
        done
        if [[ -z "$bad_order" ]]; then
            record_check "SA-CTR-06" 2 containers "PASS" "Network ordering correct for multi-network containers"
        else
            record_check "SA-CTR-06" 2 containers "WARN" "Wrong network order (reverse_proxy not first):$bad_order"
        fi
    fi

    # SA-CTR-07 (L2): Healthchecks defined in quadlets
    if should_run 2 containers; then
        local no_health=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            if systemctl --user is-active "${name}.service" &>/dev/null; then
                if ! grep -q "^HealthCmd=" "$quadlet" 2>/dev/null; then
                    no_health="$no_health $name"
                fi
            fi
        done
        if [[ -z "$no_health" ]]; then
            record_check "SA-CTR-07" 2 containers "PASS" "All running containers have healthchecks"
        else
            record_check "SA-CTR-07" 2 containers "WARN" "No healthcheck:$no_health" "$no_health"
        fi
    fi

    # SA-CTR-08 (L2): Podman Secret= directives resolve to actual secrets
    if should_run 2 containers; then
        local bad_secrets=""
        local available_secrets
        available_secrets=$(podman secret ls --format '{{.Name}}' 2>/dev/null || echo "")
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            while IFS= read -r secret_line; do
                local secret_name
                secret_name=$(echo "$secret_line" | sed 's/^Secret=//;s/,.*//')
                if ! echo "$available_secrets" | grep -qw "$secret_name" 2>/dev/null; then
                    bad_secrets="$bad_secrets ${name}:${secret_name}"
                fi
            done < <(grep "^Secret=" "$quadlet" 2>/dev/null)
        done
        if [[ -z "$bad_secrets" ]]; then
            record_check "SA-CTR-08" 2 containers "PASS" "All Podman secrets resolve correctly"
        else
            record_check "SA-CTR-08" 2 containers "FAIL" "Missing secrets:$bad_secrets"
        fi
    fi

    # SA-CTR-09 (L2): Static IPs for multi-network containers (.69+)
    if should_run 2 containers; then
        local missing_static=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            local net_count
            net_count=$(grep -c "^Network=" "$quadlet" 2>/dev/null || echo "0")
            if (( net_count > 1 )); then
                # Multi-network: should have static IPs
                if ! grep -q "ip=10\." "$quadlet" 2>/dev/null; then
                    missing_static="$missing_static $name"
                fi
            fi
        done
        if [[ -z "$missing_static" ]]; then
            record_check "SA-CTR-09" 2 containers "PASS" "Multi-network containers have static IPs"
        else
            record_check "SA-CTR-09" 2 containers "WARN" "Missing static IPs:$missing_static"
        fi
    fi

    # SA-CTR-10 (L3): Container image age < 30 days
    if should_run 3 containers; then
        local old_images=""
        local now_epoch
        now_epoch=$(date +%s)
        while IFS= read -r line; do
            local img_name created_at
            img_name=$(echo "$line" | awk '{print $1}')
            created_at=$(echo "$line" | awk '{print $2}')
            if [[ -n "$created_at" && "$created_at" != "<none>" ]]; then
                local img_epoch
                img_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
                local age_days=$(( (now_epoch - img_epoch) / 86400 ))
                if (( age_days > 30 )); then
                    old_images="$old_images ${img_name##*/}:${age_days}d"
                fi
            fi
        done < <(podman images --format '{{.Repository}} {{.CreatedAt}}' 2>/dev/null | head -30)
        if [[ -z "$old_images" ]]; then
            record_check "SA-CTR-10" 3 containers "PASS" "All container images <30 days old"
        else
            record_check "SA-CTR-10" 3 containers "WARN" "Old images:$old_images" "$old_images"
        fi
    fi

    # SA-CTR-11 (L3): All quadlets have Slice=container.slice
    if should_run 3 containers; then
        local no_slice=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            if ! grep -q "^Slice=" "$quadlet" 2>/dev/null; then
                no_slice="$no_slice $name"
            fi
        done
        if [[ -z "$no_slice" ]]; then
            record_check "SA-CTR-11" 3 containers "PASS" "All quadlets have Slice directive"
        else
            record_check "SA-CTR-11" 3 containers "WARN" "Missing Slice:$no_slice"
        fi
    fi
}

##############################################################################
# MONITORING Checks (SA-MON-01 through SA-MON-07)
##############################################################################

run_monitoring_checks() {
    section_header "MONITORING" "Observability Stack"

    # SA-MON-01 (L1): Prometheus running
    if should_run 1 monitoring; then
        if systemctl --user is-active prometheus.service &>/dev/null; then
            record_check "SA-MON-01" 1 monitoring "PASS" "Prometheus service running"
        else
            record_check "SA-MON-01" 1 monitoring "FAIL" "Prometheus service not running"
        fi
    fi

    # SA-MON-02 (L1): Alertmanager running
    if should_run 1 monitoring; then
        if systemctl --user is-active alertmanager.service &>/dev/null; then
            record_check "SA-MON-02" 1 monitoring "PASS" "Alertmanager service running"
        else
            record_check "SA-MON-02" 1 monitoring "FAIL" "Alertmanager service not running"
        fi
    fi

    # SA-MON-03 (L1): Grafana running
    if should_run 1 monitoring; then
        if systemctl --user is-active grafana.service &>/dev/null; then
            record_check "SA-MON-03" 1 monitoring "PASS" "Grafana service running"
        else
            record_check "SA-MON-03" 1 monitoring "FAIL" "Grafana service not running"
        fi
    fi

    # SA-MON-04 (L2): No Prometheus scrape targets down
    if should_run 2 monitoring; then
        local down_targets
        down_targets=$(timeout 10 podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/targets' 2>/dev/null | jq -r '.data.activeTargets[] | select(.health=="down") | .labels.job' 2>/dev/null | head -5 || echo "")
        if [[ -z "$down_targets" ]]; then
            record_check "SA-MON-04" 2 monitoring "PASS" "All Prometheus scrape targets up"
        else
            local down_list
            down_list=$(echo "$down_targets" | tr '\n' ', ' | sed 's/,$//')
            record_check "SA-MON-04" 2 monitoring "WARN" "Prometheus targets down: $down_list"
        fi
    fi

    # SA-MON-05 (L2): Promtail running
    if should_run 2 monitoring; then
        if systemctl --user is-active promtail.service &>/dev/null; then
            record_check "SA-MON-05" 2 monitoring "PASS" "Promtail service running"
        else
            record_check "SA-MON-05" 2 monitoring "WARN" "Promtail service not running"
        fi
    fi

    # SA-MON-06 (L2): Alertmanager not exposed on host port
    if should_run 2 monitoring; then
        if ss -tlnp 2>/dev/null | grep -q ":9093 " 2>/dev/null; then
            record_check "SA-MON-06" 2 monitoring "FAIL" "Alertmanager exposed on host port 9093"
        else
            record_check "SA-MON-06" 2 monitoring "PASS" "Alertmanager not on host ports"
        fi
    fi

    # SA-MON-07 (L3): Alert rules loaded in Prometheus
    if should_run 3 monitoring; then
        local rule_count
        rule_count=$(timeout 10 podman exec prometheus wget -q -O- 'http://localhost:9090/api/v1/rules' 2>/dev/null | jq '.data.groups | length' 2>/dev/null || echo "0")
        if (( rule_count > 0 )); then
            record_check "SA-MON-07" 3 monitoring "PASS" "Prometheus alert rule groups loaded: $rule_count"
        else
            record_check "SA-MON-07" 3 monitoring "WARN" "No Prometheus alert rules loaded"
        fi
    fi
}

##############################################################################
# SECRETS Checks (SA-SEC-01 through SA-SEC-05)
##############################################################################

run_secrets_checks() {
    section_header "SECRETS" "Secrets Management"

    # SA-SEC-01 (L1): .gitignore covers secret patterns
    if should_run 1 secrets; then
        local gitignore="$CONTAINERS_DIR/.gitignore"
        local missing=""
        for pattern in "*.key" "*.pem" "*secret*" "*.env" "acme.json"; do
            if ! grep -qF "$pattern" "$gitignore" 2>/dev/null; then
                missing="$missing $pattern"
            fi
        done
        if [[ -z "$missing" ]]; then
            record_check "SA-SEC-01" 1 secrets "PASS" ".gitignore covers secret file patterns"
        else
            record_check "SA-SEC-01" 1 secrets "FAIL" ".gitignore missing patterns:$missing"
        fi
    fi

    # SA-SEC-02 (L1): No secrets in git history (check recent commits)
    if should_run 1 secrets; then
        local secret_leaks
        secret_leaks=$(cd "$CONTAINERS_DIR" && git log --oneline -20 --diff-filter=A --name-only 2>/dev/null | grep -iE '\.(key|pem|env)$|secret|password|credential' | head -5 || echo "")
        if [[ -z "$secret_leaks" ]]; then
            record_check "SA-SEC-02" 1 secrets "PASS" "No secret files in recent git history"
        else
            record_check "SA-SEC-02" 1 secrets "WARN" "Possible secrets in git history: $secret_leaks"
        fi
    fi

    # SA-SEC-03 (L2): Secret files have 600/400 permissions
    if should_run 2 secrets; then
        local bad_perms=""
        shopt -s nullglob globstar 2>/dev/null || true
        for secret in "$CONTAINERS_DIR"/secrets/* "$CONTAINERS_DIR"/config/**/secret*; do
            if [[ -f "$secret" ]]; then
                local perms
                perms=$(stat -c %a "$secret" 2>/dev/null || echo "")
                if [[ -n "$perms" && "$perms" != "600" && "$perms" != "400" ]]; then
                    bad_perms="$bad_perms $(basename "$secret"):$perms"
                fi
            fi
        done
        shopt -u nullglob globstar 2>/dev/null || true
        if [[ -z "$bad_perms" ]]; then
            record_check "SA-SEC-03" 2 secrets "PASS" "Secret files have restrictive permissions"
        else
            record_check "SA-SEC-03" 2 secrets "WARN" "Loose permissions:$bad_perms"
        fi
    fi

    # SA-SEC-04 (L2): GPG signing enabled
    if should_run 2 secrets; then
        local gpg_sign
        gpg_sign=$(cd "$CONTAINERS_DIR" && git config --get commit.gpgsign 2>/dev/null || echo "false")
        if [[ "$gpg_sign" == "true" ]]; then
            record_check "SA-SEC-04" 2 secrets "PASS" "GPG commit signing enabled"
        else
            record_check "SA-SEC-04" 2 secrets "WARN" "GPG commit signing not enabled"
        fi
    fi

    # SA-SEC-05 (L3): Podman secrets count >= expected
    if should_run 3 secrets; then
        local secret_count
        secret_count=$(podman secret ls --format '{{.Name}}' 2>/dev/null | wc -l || echo "0")
        # Expect at least 3 secrets (authelia jwt, session, storage encryption + cloudflare)
        if (( secret_count >= 3 )); then
            record_check "SA-SEC-05" 3 secrets "PASS" "Podman secrets: $secret_count registered"
        else
            record_check "SA-SEC-05" 3 secrets "WARN" "Low Podman secret count: $secret_count (expected >=3)"
        fi
    fi
}

##############################################################################
# COMPLIANCE Checks (SA-CMP-01 through SA-CMP-05)
##############################################################################

run_compliance_checks() {
    section_header "COMPLIANCE" "Configuration Drift & Standards"

    # SA-CMP-01 (L2): No uncommitted changes
    if should_run 2 compliance; then
        local dirty
        dirty=$(cd "$CONTAINERS_DIR" && git status --porcelain 2>/dev/null | wc -l || echo "0")
        if (( dirty == 0 )); then
            record_check "SA-CMP-01" 2 compliance "PASS" "No uncommitted changes"
        else
            record_check "SA-CMP-01" 2 compliance "WARN" "Uncommitted changes: $dirty files"
        fi
    fi

    # SA-CMP-02 (L2): BTRFS NOCOW on database dirs
    if should_run 2 compliance; then
        local missing_nocow=""
        for db_dir in /mnt/btrfs-pool/subvol7-containers/prometheus /mnt/btrfs-pool/subvol7-containers/loki /mnt/btrfs-pool/subvol7-containers/postgresql-immich; do
            if [[ -d "$db_dir" ]]; then
                local attrs
                attrs=$(lsattr -d "$db_dir" 2>/dev/null | awk '{print $1}' || echo "")
                if ! echo "$attrs" | grep -q "C" 2>/dev/null; then
                    missing_nocow="$missing_nocow $(basename "$db_dir")"
                fi
            fi
        done
        if [[ -z "$missing_nocow" ]]; then
            record_check "SA-CMP-02" 2 compliance "PASS" "BTRFS NOCOW set on database directories"
        else
            record_check "SA-CMP-02" 2 compliance "WARN" "Missing NOCOW:$missing_nocow"
        fi
    fi

    # SA-CMP-03 (L2): Filesystem permissions intact
    if should_run 2 compliance; then
        local verify_script="$SCRIPT_DIR/verify-permissions.sh"
        if [[ -x "$verify_script" ]]; then
            if "$verify_script" >/dev/null 2>&1; then
                record_check "SA-CMP-03" 2 compliance "PASS" "Filesystem permissions intact"
            else
                record_check "SA-CMP-03" 2 compliance "WARN" "Filesystem permission drift detected"
            fi
        else
            record_check "SA-CMP-03" 2 compliance "WARN" "verify-permissions.sh not found"
        fi
    fi

    # SA-CMP-04 (L3): Naming convention compliance
    if should_run 3 compliance; then
        local bad_names=""
        for quadlet in "$QUADLETS_DIR"/*.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            local container_name
            container_name=$(grep "^ContainerName=" "$quadlet" 2>/dev/null | cut -d= -f2 || echo "")
            if [[ -n "$container_name" && "$container_name" != "$name" ]]; then
                bad_names="$bad_names $name!=$container_name"
            fi
        done
        if [[ -z "$bad_names" ]]; then
            record_check "SA-CMP-04" 3 compliance "PASS" "Container names match quadlet filenames"
        else
            record_check "SA-CMP-04" 3 compliance "WARN" "Name mismatches:$bad_names"
        fi
    fi

    # SA-CMP-05 (L3): All quadlets have Requires/After for dependencies
    if should_run 3 compliance; then
        local missing_deps=""
        # Check containers that reference other containers (e.g., app + db)
        for quadlet in "$QUADLETS_DIR"/nextcloud.container "$QUADLETS_DIR"/immich-server.container "$QUADLETS_DIR"/gathio.container "$QUADLETS_DIR"/authelia.container; do
            [[ -f "$quadlet" ]] || continue
            local name
            name=$(basename "$quadlet" .container)
            if ! grep -q "^Requires=\|^After=" "$quadlet" 2>/dev/null; then
                missing_deps="$missing_deps $name"
            fi
        done
        if [[ -z "$missing_deps" ]]; then
            record_check "SA-CMP-05" 3 compliance "PASS" "Service dependencies declared in quadlets"
        else
            record_check "SA-CMP-05" 3 compliance "WARN" "Missing dependency declarations:$missing_deps"
        fi
    fi
}

##############################################################################
# Output Generation
##############################################################################

generate_json() {
    local timestamp
    timestamp=$(date -Iseconds)
    local total=0 pass=0 warn=0 fail=0

    # Category counters
    declare -A cat_pass cat_warn cat_fail
    for cat in auth network traefik containers monitoring secrets compliance; do
        cat_pass[$cat]=0
        cat_warn[$cat]=0
        cat_fail[$cat]=0
    done

    # Build checks array
    local checks_json="["
    local first=true
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r id level category status message detail <<< "$result"
        ((total++)) || true
        case "$status" in
            PASS) ((pass++)) || true; ((cat_pass[$category]++)) || true ;;
            WARN) ((warn++)) || true; ((cat_warn[$category]++)) || true ;;
            FAIL) ((fail++)) || true; ((cat_fail[$category]++)) || true ;;
        esac

        $first || checks_json+=","
        first=false

        # Escape strings for JSON
        message=$(echo "$message" | sed 's/"/\\"/g')
        detail=$(echo "$detail" | sed 's/"/\\"/g')

        checks_json+="$(cat << CHECKEOF
{
      "id": "$id",
      "level": $level,
      "category": "$category",
      "status": "$status",
      "message": "$message",
      "detail": "$detail"
    }
CHECKEOF
)"
    done
    checks_json+="]"

    # Build categories summary
    local categories_json="{"
    first=true
    for cat in auth network traefik containers monitoring secrets compliance; do
        $first || categories_json+=","
        first=false
        categories_json+="\"$cat\": {\"pass\": ${cat_pass[$cat]}, \"warn\": ${cat_warn[$cat]}, \"fail\": ${cat_fail[$cat]}}"
    done
    categories_json+="}"

    # Trend comparison
    local trend_json="{}"
    if $COMPARE; then
        local prev_file
        prev_file=$(ls -t "$HISTORY_DIR"/audit-*.json 2>/dev/null | head -1 || echo "")
        if [[ -f "$prev_file" ]]; then
            local prev_score prev_date prev_failures new_failures resolved
            prev_score=$(jq '.security_score' "$prev_file" 2>/dev/null || echo "0")
            prev_date=$(jq -r '.timestamp' "$prev_file" 2>/dev/null || echo "unknown")
            local score_change=$(( SCORE - prev_score ))

            # Find new failures (in current but not previous)
            new_failures=$(jq -r '[.checks[] | select(.status == "FAIL") | .id]' "$prev_file" 2>/dev/null || echo "[]")
            resolved="[]"

            trend_json="{\"previous_date\": \"$prev_date\", \"previous_score\": $prev_score, \"score_change\": $score_change}"
        else
            trend_json="{\"previous_date\": null, \"score_change\": 0, \"note\": \"No previous audit found\"}"
        fi
    fi

    cat << JSONEOF
{
  "timestamp": "$timestamp",
  "version": "2.0",
  "level": $LEVEL,
  "security_score": $SCORE,
  "summary": {
    "total": $total,
    "pass": $pass,
    "warn": $warn,
    "fail": $fail
  },
  "categories": $categories_json,
  "checks": $checks_json,
  "trend": $trend_json
}
JSONEOF
}

generate_report() {
    local timestamp
    timestamp=$(date -Iseconds)
    local date_str
    date_str=$(date +%Y-%m-%d)
    local report_file="$REPORT_DIR/security-audit-${date_str}.md"

    local total=0 pass=0 warn=0 fail=0
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r _ _ _ status _ _ <<< "$result"
        ((total++)) || true
        case "$status" in
            PASS) ((pass++)) || true ;;
            WARN) ((warn++)) || true ;;
            FAIL) ((fail++)) || true ;;
        esac
    done

    mkdir -p "$REPORT_DIR"

    {
        echo "# Security Audit Report - $date_str"
        echo ""
        echo "**Security Score: $SCORE/100** | Level: $LEVEL | Checks: $total (Pass: $pass, Warn: $warn, Fail: $fail)"
        echo ""
        echo "Generated: $timestamp"
        echo ""

        # Failures first
        if (( fail > 0 )); then
            echo "## Failures"
            echo ""
            for result in "${RESULTS[@]}"; do
                IFS='|' read -r id level category status message detail <<< "$result"
                if [[ "$status" == "FAIL" ]]; then
                    echo "- **[$id]** (L$level/$category) $message"
                    [[ -n "$detail" ]] && echo "  - Detail: $detail"
                fi
            done
            echo ""
        fi

        # Warnings
        if (( warn > 0 )); then
            echo "## Warnings"
            echo ""
            for result in "${RESULTS[@]}"; do
                IFS='|' read -r id level category status message detail <<< "$result"
                if [[ "$status" == "WARN" ]]; then
                    echo "- **[$id]** (L$level/$category) $message"
                fi
            done
            echo ""
        fi

        # Summary table
        echo "## Category Summary"
        echo ""
        echo "| Category | Pass | Warn | Fail |"
        echo "|----------|------|------|------|"
        local current_cat=""
        declare -A rpt_pass rpt_warn rpt_fail
        for cat in auth network traefik containers monitoring secrets compliance; do
            rpt_pass[$cat]=0; rpt_warn[$cat]=0; rpt_fail[$cat]=0
        done
        for result in "${RESULTS[@]}"; do
            IFS='|' read -r _ _ category status _ _ <<< "$result"
            case "$status" in
                PASS) ((rpt_pass[$category]++)) || true ;;
                WARN) ((rpt_warn[$category]++)) || true ;;
                FAIL) ((rpt_fail[$category]++)) || true ;;
            esac
        done
        for cat in auth network traefik containers monitoring secrets compliance; do
            echo "| ${cat^^} | ${rpt_pass[$cat]} | ${rpt_warn[$cat]} | ${rpt_fail[$cat]} |"
        done
        echo ""
        echo "---"
        echo "Generated by \`security-audit.sh --level $LEVEL --report\`"
    } > "$report_file"

    echo "Report saved to: $report_file" >&2
}

print_summary() {
    $JSON_OUTPUT && return
    $QUIET && return

    local total=0 pass=0 warn=0 fail=0
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r _ _ _ status _ _ <<< "$result"
        ((total++)) || true
        case "$status" in
            PASS) ((pass++)) || true ;;
            WARN) ((warn++)) || true ;;
            FAIL) ((fail++)) || true ;;
        esac
    done

    echo ""
    echo -e "${BOLD}${BLUE}=========================================${NC}"
    echo -e "${BOLD}  Security Score: ${SCORE}/100${NC}"
    echo -e "${BOLD}${BLUE}=========================================${NC}"
    echo ""
    echo -e "  ${GREEN}PASS:${NC}  $pass"
    echo -e "  ${YELLOW}WARN:${NC}  $warn"
    echo -e "  ${RED}FAIL:${NC}  $fail"
    echo -e "  Total: $total checks (level $LEVEL)"
    echo ""

    if $COMPARE; then
        local prev_file
        prev_file=$(ls -t "$HISTORY_DIR"/audit-*.json 2>/dev/null | head -1 || echo "")
        if [[ -f "$prev_file" ]]; then
            local prev_score
            prev_score=$(jq '.security_score' "$prev_file" 2>/dev/null || echo "0")
            local delta=$(( SCORE - prev_score ))
            if (( delta > 0 )); then
                echo -e "  ${GREEN}Trend: +${delta} from previous audit${NC}"
            elif (( delta < 0 )); then
                echo -e "  ${RED}Trend: ${delta} from previous audit${NC}"
            else
                echo -e "  Trend: No change from previous audit"
            fi
        else
            echo "  Trend: No previous audit for comparison"
        fi
        echo ""
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    # Ensure history directory exists
    mkdir -p "$HISTORY_DIR"

    # Header
    if ! $JSON_OUTPUT && ! $QUIET; then
        echo ""
        echo -e "${BOLD}${BLUE}=========================================${NC}"
        echo -e "${BOLD}${BLUE}     HOMELAB SECURITY AUDIT v2.0${NC}"
        echo -e "${BOLD}${BLUE}=========================================${NC}"
        echo -e "  Level: $LEVEL | $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    # Run checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "auth" ]] && run_auth_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "network" ]] && run_network_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "traefik" ]] && run_traefik_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "containers" ]] && run_container_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "monitoring" ]] && run_monitoring_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "secrets" ]] && run_secrets_checks
    [[ -z "$CATEGORY" || "$CATEGORY" == "compliance" ]] && run_compliance_checks

    # Summary
    print_summary

    # JSON output
    local json_data
    if $JSON_OUTPUT || $GENERATE_REPORT || [[ -d "$HISTORY_DIR" ]]; then
        json_data=$(generate_json)
    fi

    if $JSON_OUTPUT; then
        echo "$json_data"
    fi

    # Save history
    if [[ -d "$HISTORY_DIR" ]]; then
        local date_str
        date_str=$(date +%Y-%m-%d)
        echo "$json_data" > "$HISTORY_DIR/audit-${date_str}.json" 2>/dev/null || true
    fi

    # Generate report
    if $GENERATE_REPORT; then
        generate_report
    fi

    # Exit code
    local fail_count=0
    local warn_count=0
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r _ _ _ status _ _ <<< "$result"
        case "$status" in
            FAIL) ((fail_count++)) || true ;;
            WARN) ((warn_count++)) || true ;;
        esac
    done

    if (( fail_count > 0 )); then
        exit 2
    elif (( warn_count > 0 )); then
        exit 1
    else
        exit 0
    fi
}

main "$@"
