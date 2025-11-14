#!/usr/bin/env bash
# Validate quadlet syntax and best practices

set -euo pipefail

QUADLET_FILE="$1"

if [[ ! -f "$QUADLET_FILE" ]]; then
    echo "Error: File not found: $QUADLET_FILE"
    exit 1
fi

echo "Validating quadlet: $QUADLET_FILE"
echo "=========================================="

ERRORS=0
WARNINGS=0

# Check INI syntax
if ! grep -q '^\[Unit\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Container\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Service\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Install\]' "$QUADLET_FILE"; then
    echo "✗ Missing required sections"
    ((ERRORS++))
else
    echo "✓ All required sections present"
fi

# Check network naming
if grep -q '^Network=' "$QUADLET_FILE"; then
    if grep '^Network=' "$QUADLET_FILE" | grep -q 'systemd-'; then
        echo "✓ Network names use systemd- prefix"
    else
        echo "✗ Network names missing systemd- prefix"
        ((ERRORS++))
    fi
fi

# Check SELinux labels
if grep -q '^Volume=' "$QUADLET_FILE"; then
    if grep '^Volume=' "$QUADLET_FILE" | grep -qv ':Z'; then
        echo "⚠ Some volumes missing :Z SELinux label"
        ((WARNINGS++))
    else
        echo "✓ All volumes have SELinux labels"
    fi
fi

# Check health check
if grep -q '^HealthCmd=' "$QUADLET_FILE"; then
    echo "✓ Health check defined"
else
    echo "⚠ No health check defined"
    ((WARNINGS++))
fi

# Check resource limits
if grep -q '^MemoryMax=' "$QUADLET_FILE"; then
    echo "✓ Memory limit set"
else
    echo "⚠ No memory limit"
    ((WARNINGS++))
fi

echo ""
echo "Validation complete:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"

if [[ $ERRORS -eq 0 ]]; then
    echo "✓ Quadlet is valid"
    exit 0
else
    echo "✗ Fix errors before deploying"
    exit 1
fi
