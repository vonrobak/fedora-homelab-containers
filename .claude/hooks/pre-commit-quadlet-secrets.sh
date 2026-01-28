#!/bin/bash
# Pre-commit hook: Detect hardcoded secrets in quadlet files
# Prevents accidental commit of passwords, tokens, API keys in Environment variables
# Created: 2026-01-28
# Part of quadlet migration from sanitized copy to direct tracking

set -e

# Get list of staged quadlet files
QUADLET_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E "\.container$|\.network$" || true)

if [[ -z "$QUADLET_FILES" ]]; then
  # No quadlet files staged, skip check
  exit 0
fi

echo "🔍 Pre-commit: Checking quadlet files for hardcoded secrets..."

# Patterns that indicate hardcoded secrets in Environment variables
# These should use Podman secrets instead: Secret=name,type=env,target=VAR
SECRET_PATTERNS=(
  'Environment=[^=]*PASSWORD=[^$]'   # PASSWORD=value (not $VAR or ${VAR})
  'Environment=[^=]*SECRET=[^$]'     # SECRET=value
  'Environment=[^=]*TOKEN=[^$]'      # TOKEN=value
  'Environment=[^=]*API_KEY=[^$]'    # API_KEY=value
  'Environment=[^=]*APIKEY=[^$]'     # APIKEY=value
  'Environment=[^=]*KEY=[^$]'        # KEY=value (but allow PUBKEY, etc)
)

# Exceptions: Config values that happen to contain these words but aren't secrets
SAFE_PATTERNS=(
  'PASSWORD_ITERATIONS='             # Vaultwarden security config
  'PASSWORD_HINTS_ALLOWED='          # Vaultwarden feature flag
  'SECRET_KEY_BASE=\${'               # Variable reference (allowed)
  'TOKEN_EXPIRY='                    # Config value, not secret
)

FOUND_SECRETS=0

for file in $QUADLET_FILES; do
  # Skip if file doesn't exist (deleted file)
  if [[ ! -f "$file" ]]; then
    continue
  fi

  for pattern in "${SECRET_PATTERNS[@]}"; do
    # Search for pattern
    MATCHES=$(git diff --cached "$file" | grep -E "^\+" | grep -E "$pattern" || true)

    if [[ -n "$MATCHES" ]]; then
      # Check if it's a safe pattern (exception)
      IS_SAFE=0
      for safe in "${SAFE_PATTERNS[@]}"; do
        if echo "$MATCHES" | grep -qE "$safe"; then
          IS_SAFE=1
          break
        fi
      done

      if [[ $IS_SAFE -eq 0 ]]; then
        echo ""
        echo "❌ ERROR: Hardcoded secret detected in $file"
        echo "   Pattern matched: $pattern"
        echo "   Line(s):"
        echo "$MATCHES" | sed 's/^/     /'
        echo ""
        echo "   ⚠️  Use Podman secrets instead:"
        echo "   1. Create secret: echo 'value' | podman secret create myservice_password -"
        echo "   2. Reference in quadlet:"
        echo "      Secret=myservice_password,type=env,target=PASSWORD"
        echo ""
        FOUND_SECRETS=1
      fi
    fi
  done
done

if [[ $FOUND_SECRETS -eq 1 ]]; then
  echo "🚫 Commit blocked: Remove hardcoded secrets and use Podman secrets"
  echo "   See: docs/30-security/guides/secrets-management.md"
  exit 1
fi

echo "✓ No hardcoded secrets found in quadlet files"
exit 0
