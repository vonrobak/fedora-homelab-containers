#!/usr/bin/env bash
# validate-traefik-config.sh - Validate Traefik routers.yml
# Checks: YAML syntax, middleware ordering, service references, duplicate detection
set -euo pipefail

ROUTERS_FILE="${1:-${HOME}/containers/config/traefik/dynamic/routers.yml}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

check() {
    if "$@"; then
        return 0
    else
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

echo "Validating: $ROUTERS_FILE"
echo ""

# 1. YAML syntax validation
echo -n "  YAML syntax: "
if python3 -c "
import yaml, sys
try:
    with open('${ROUTERS_FILE}') as f:
        data = yaml.safe_load(f)
    if data is None:
        print('Empty file', file=sys.stderr)
        sys.exit(1)
    if 'http' not in data:
        print('Missing http: key', file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'YAML error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} - invalid YAML"
    ERRORS=$((ERRORS+1))
    exit 1  # Can't continue with invalid YAML
fi

# 2. Service references match definitions
echo -n "  Service references: "
MISSING_SERVICES=$(python3 -c "
import yaml
with open('${ROUTERS_FILE}') as f:
    data = yaml.safe_load(f)

routers = data.get('http', {}).get('routers', {})
services = data.get('http', {}).get('services', {})
service_names = set(services.keys()) if services else set()
# Add internal services
service_names.add('api@internal')

missing = []
for rname, rconfig in routers.items():
    svc = rconfig.get('service', '')
    if svc and svc not in service_names:
        missing.append(f'{rname} -> {svc}')

if missing:
    print('\n'.join(missing))
" 2>/dev/null || true)

if [[ -z "$MISSING_SERVICES" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "$MISSING_SERVICES" | while read -r line; do
        echo -e "    ${RED}Missing:${NC} $line"
    done
    ERRORS=$((ERRORS+1))
fi

# 3. CrowdSec first in middleware chains
echo -n "  Middleware ordering: "
BAD_ORDER=$(python3 -c "
import yaml
with open('${ROUTERS_FILE}') as f:
    data = yaml.safe_load(f)

routers = data.get('http', {}).get('routers', {})
bad = []
for rname, rconfig in routers.items():
    mw = rconfig.get('middlewares', [])
    if mw and len(mw) > 1:
        # CrowdSec should be first
        if not any('crowdsec' in str(m) for m in mw[:1]):
            bad.append(f'{rname}: first middleware is {mw[0]} (should be crowdsec)')
if bad:
    print('\n'.join(bad))
" 2>/dev/null || true)

if [[ -z "$BAD_ORDER" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${YELLOW}WARN${NC}"
    echo "$BAD_ORDER" | while read -r line; do
        echo -e "    ${YELLOW}Warning:${NC} $line"
    done
fi

# 4. No duplicate routers
echo -n "  Duplicate detection: "
DUPES=$(python3 -c "
import yaml
# Use a custom loader to detect duplicate keys
from collections import Counter
with open('${ROUTERS_FILE}') as f:
    content = f.read()

# Simple approach: count router name occurrences
import re
router_names = re.findall(r'^    (\S+):$', content, re.MULTILINE)
counts = Counter(router_names)
dupes = [f'{name} ({count}x)' for name, count in counts.items() if count > 1]
if dupes:
    print('\n'.join(dupes))
" 2>/dev/null || true)

if [[ -z "$DUPES" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "$DUPES" | while read -r line; do
        echo -e "    ${RED}Duplicate:${NC} $line"
    done
    ERRORS=$((ERRORS+1))
fi

# 5. TLS configured on all routers
echo -n "  TLS configuration: "
NO_TLS=$(python3 -c "
import yaml
with open('${ROUTERS_FILE}') as f:
    data = yaml.safe_load(f)

routers = data.get('http', {}).get('routers', {})
no_tls = []
for rname, rconfig in routers.items():
    if 'tls' not in rconfig:
        no_tls.append(rname)
if no_tls:
    print('\n'.join(no_tls))
" 2>/dev/null || true)

if [[ -z "$NO_TLS" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${YELLOW}WARN${NC}"
    echo "$NO_TLS" | while read -r line; do
        echo -e "    ${YELLOW}No TLS:${NC} $line"
    done
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Validation FAILED${NC} ($ERRORS errors)"
    exit 1
else
    echo -e "${GREEN}Validation PASSED${NC}"
    exit 0
fi
