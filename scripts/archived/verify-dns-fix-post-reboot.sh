#!/bin/bash
# Post-Reboot Verification Script for DNS Fix
# Tests static IP assignment and /etc/hosts override solution
# Run after system reboot to verify persistence
#
# See: docs/98-journals/2026-02-02-solution-implemented-pending-reboot-verification.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Post-Reboot DNS Fix Verification"
echo "========================================"
echo ""
echo "Boot ID: $(journalctl --list-boots | head -1 | awk '{print $2}')"
echo "Uptime: $(uptime -p)"
echo "Date: $(date)"
echo ""

# Test 1: Service Status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 1: Service Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SERVICES_OK=0
SERVICES_FAILED=0

for service in traefik authelia home-assistant grafana prometheus; do
  status=$(systemctl --user is-active $service.service 2>/dev/null || echo "inactive")
  if [[ "$status" == "active" ]]; then
    echo -e "  ${GREEN}✓${NC} $service: $status"
    ((SERVICES_OK++))
  else
    echo -e "  ${RED}✗${NC} $service: $status"
    ((SERVICES_FAILED++))
  fi
done
echo ""

if [[ $SERVICES_FAILED -gt 0 ]]; then
  echo -e "${RED}⚠ WARNING: $SERVICES_FAILED service(s) not running${NC}"
  echo ""
fi

# Test 2: Static IP Assignment
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 2: Static IP Assignment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

declare -A EXPECTED_IPS=(
  ["home-assistant"]="10.89.2.8"
  ["authelia"]="10.89.2.10"
  ["grafana"]="10.89.2.9"
  ["prometheus"]="10.89.2.11"
)

IPS_OK=0
IPS_FAILED=0

for service in "${!EXPECTED_IPS[@]}"; do
  expected="${EXPECTED_IPS[$service]}"
  actual=$(podman exec $service ip addr show 2>/dev/null | grep "inet 10.89.2" | awk '{print $2}' | cut -d'/' -f1 || echo "")

  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}✓${NC} $service: $actual (expected $expected)"
    ((IPS_OK++))
  else
    echo -e "  ${RED}✗${NC} $service: $actual (expected $expected)"
    ((IPS_FAILED++))
  fi
done
echo ""

if [[ $IPS_FAILED -gt 0 ]]; then
  echo -e "${RED}⚠ WARNING: $IPS_FAILED IP(s) don't match expected values${NC}"
  echo ""
fi

# Test 3: Traefik Hosts File
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 3: Traefik Hosts File"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if podman exec traefik cat /etc/hosts 2>/dev/null | grep -q "^10.89.2"; then
  echo -e "${GREEN}✓${NC} Hosts file mounted correctly"
  echo ""
  echo "Sample entries:"
  podman exec traefik cat /etc/hosts 2>/dev/null | grep "^10.89.2" | head -5 | sed 's/^/  /'
  HOSTS_OK=1
else
  echo -e "${RED}✗${NC} Hosts file NOT mounted or empty"
  HOSTS_OK=0
fi
echo ""

# Test 4: DNS Resolution from Traefik
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 4: DNS Resolution from Traefik"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DNS_OK=0
DNS_FAILED=0

for service in "${!EXPECTED_IPS[@]}"; do
  expected="${EXPECTED_IPS[$service]}"
  actual=$(podman exec traefik getent hosts $service 2>/dev/null | awk '{print $1}' || echo "")

  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}✓${NC} $service: $actual (expected $expected)"
    ((DNS_OK++))
  else
    echo -e "  ${RED}✗${NC} $service: $actual (expected $expected)"
    ((DNS_FAILED++))
  fi
done
echo ""

if [[ $DNS_FAILED -gt 0 ]]; then
  echo -e "${RED}⚠ WARNING: $DNS_FAILED service(s) not resolving correctly${NC}"
  echo ""
fi

# Test 5: External Access
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 5: External Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ACCESS_OK=0
ACCESS_FAILED=0

# Test Home Assistant
ha_status=$(curl -sI https://ha.patriark.org 2>&1 | grep "^HTTP/" | awk '{print $2}' || echo "FAILED")
if [[ "$ha_status" =~ ^(200|302|405)$ ]]; then
  echo -e "  ${GREEN}✓${NC} Home Assistant: HTTP $ha_status"
  ((ACCESS_OK++))
else
  echo -e "  ${RED}✗${NC} Home Assistant: HTTP $ha_status"
  ((ACCESS_FAILED++))
fi

# Test Grafana (should redirect to SSO)
grafana_status=$(curl -sI https://grafana.patriark.org 2>&1 | grep "^HTTP/" | awk '{print $2}' || echo "FAILED")
if [[ "$grafana_status" == "302" ]]; then
  echo -e "  ${GREEN}✓${NC} Grafana: HTTP $grafana_status (redirect to SSO)"
  ((ACCESS_OK++))
else
  echo -e "  ${RED}✗${NC} Grafana: HTTP $grafana_status (expected 302)"
  ((ACCESS_FAILED++))
fi
echo ""

# Test 6: Check for Proxy Errors
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST 6: Untrusted Proxy Errors"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

errors=$(journalctl --user -u home-assistant.service --since "5 minutes ago" 2>/dev/null | grep -i "untrusted" | wc -l)
if [[ $errors -eq 0 ]]; then
  echo -e "  ${GREEN}✓${NC} No untrusted proxy errors (last 5 minutes)"
  ERRORS_OK=1
else
  echo -e "  ${RED}✗${NC} Found $errors untrusted proxy error(s)"
  echo ""
  echo "Recent errors:"
  journalctl --user -u home-assistant.service --since "5 minutes ago" | grep -i "untrusted" | tail -5 | sed 's/^/  /'
  ERRORS_OK=0
fi
echo ""

# Summary
echo "========================================"
echo "  VERIFICATION SUMMARY"
echo "========================================"
echo ""

TOTAL_TESTS=6
PASSED_TESTS=0

if [[ $SERVICES_FAILED -eq 0 ]]; then ((PASSED_TESTS++)); fi
if [[ $IPS_FAILED -eq 0 ]]; then ((PASSED_TESTS++)); fi
if [[ $HOSTS_OK -eq 1 ]]; then ((PASSED_TESTS++)); fi
if [[ $DNS_FAILED -eq 0 ]]; then ((PASSED_TESTS++)); fi
if [[ $ACCESS_FAILED -eq 0 ]]; then ((PASSED_TESTS++)); fi
if [[ $ERRORS_OK -eq 1 ]]; then ((PASSED_TESTS++)); fi

echo "Tests Passed: $PASSED_TESTS/$TOTAL_TESTS"
echo ""

if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
  echo -e "${GREEN}✓✓✓ ALL TESTS PASSED ✓✓✓${NC}"
  echo ""
  echo "The DNS fix is working correctly after reboot!"
  echo ""
  echo "Next steps:"
  echo "1. Update PR #77 with successful reboot verification"
  echo "2. Merge PR to main branch"
  echo "3. Create ADR documenting this solution"
  echo ""
  exit 0
else
  echo -e "${RED}✗✗✗ SOME TESTS FAILED ✗✗✗${NC}"
  echo ""
  echo "Investigation needed. Check:"
  if [[ $SERVICES_FAILED -gt 0 ]]; then
    echo "  • Service startup: systemctl --user status <service>.service"
  fi
  if [[ $IPS_FAILED -gt 0 ]]; then
    echo "  • Static IPs: podman inspect <service> | jq .NetworkSettings.Networks"
  fi
  if [[ $HOSTS_OK -eq 0 ]]; then
    echo "  • Hosts mount: podman inspect traefik | jq '.Mounts[] | select(.Destination==\"/etc/hosts\")'"
  fi
  if [[ $DNS_FAILED -gt 0 ]]; then
    echo "  • DNS: podman exec traefik getent hosts <service>"
  fi
  if [[ $ACCESS_FAILED -gt 0 ]]; then
    echo "  • External access: curl -v https://ha.patriark.org"
  fi
  if [[ $ERRORS_OK -eq 0 ]]; then
    echo "  • Logs: journalctl --user -u home-assistant.service -n 50"
  fi
  echo ""
  echo "Document findings in:"
  echo "  docs/98-journals/2026-02-03-reboot-verification-failed.md"
  echo ""
  exit 1
fi
