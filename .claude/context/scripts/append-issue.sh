#!/bin/bash
#
# append-issue.sh
# Append a single issue to issue-history.json
#
# Usage: ./append-issue.sh <id> <title> <category> <severity> <date> <description> <resolution> <outcome>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISSUE_LOG="$SCRIPT_DIR/../issue-history.json"
BACKUP_LOG="${ISSUE_LOG}.backup"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Validate arguments
if [ $# -lt 8 ]; then
    echo -e "${RED}Error: Insufficient arguments${NC}"
    echo "Usage: $0 <id> <title> <category> <severity> <date> <description> <resolution> <outcome>"
    echo ""
    echo "Categories: disk-space, deployment, authentication, scripting, monitoring, performance, ssl, media, architecture, operations"
    echo "Severities: critical, high, medium, low"
    echo "Outcomes: resolved, ongoing, mitigated, investigating"
    echo ""
    echo "Example:"
    echo "  $0 'AUTO-20251130' 'High disk usage auto-remediated' 'disk-space' 'medium' '2025-11-30' 'Disk at 82%, auto-cleanup freed 8GB' 'Executed disk-cleanup playbook' 'resolved'"
    exit 1
fi

ID="$1"
TITLE="$2"
CATEGORY="$3"
SEVERITY="$4"
DATE="$5"
DESCRIPTION="$6"
RESOLUTION="$7"
OUTCOME="$8"

# Validate category
VALID_CATEGORIES="disk-space deployment authentication scripting monitoring performance ssl media architecture operations"
if ! echo "$VALID_CATEGORIES" | grep -qw "$CATEGORY"; then
    echo -e "${RED}Error: Invalid category '$CATEGORY'${NC}"
    echo "Valid categories: $VALID_CATEGORIES"
    exit 1
fi

# Validate severity
VALID_SEVERITIES="critical high medium low"
if ! echo "$VALID_SEVERITIES" | grep -qw "$SEVERITY"; then
    echo -e "${RED}Error: Invalid severity '$SEVERITY'${NC}"
    echo "Valid severities: $VALID_SEVERITIES"
    exit 1
fi

# Validate outcome
VALID_OUTCOMES="resolved ongoing mitigated investigating"
if ! echo "$VALID_OUTCOMES" | grep -qw "$OUTCOME"; then
    echo -e "${RED}Error: Invalid outcome '$OUTCOME'${NC}"
    echo "Valid outcomes: $VALID_OUTCOMES"
    exit 1
fi

# Validate issue log exists
if [ ! -f "$ISSUE_LOG" ]; then
    echo -e "${RED}Error: issue-history.json not found at $ISSUE_LOG${NC}"
    exit 1
fi

# Create backup
cp "$ISSUE_LOG" "$BACKUP_LOG"

# Check if issue ID already exists
EXISTING=$(jq -r --arg id "$ID" '.issues[] | select(.id == $id) | .id' "$ISSUE_LOG" | head -1)

if [ -n "$EXISTING" ]; then
    echo -e "${YELLOW}⚠ Issue '$ID' already exists, skipping duplicate${NC}"
    rm "$BACKUP_LOG"
    exit 0
fi

# Append issue entry
jq --arg id "$ID" \
   --arg title "$TITLE" \
   --arg cat "$CATEGORY" \
   --arg sev "$SEVERITY" \
   --arg date "$DATE" \
   --arg desc "$DESCRIPTION" \
   --arg res "$RESOLUTION" \
   --arg out "$OUTCOME" \
   '
   .issues += [{
     "id": $id,
     "title": $title,
     "category": $cat,
     "severity": $sev,
     "date_encountered": $date,
     "description": $desc,
     "resolution": $res,
     "outcome": $out
   }] |
   .total_issues = (.issues | length) |
   .generated_at = (now | todate)
   ' "$ISSUE_LOG" > "${ISSUE_LOG}.tmp"

# Verify the output is valid JSON
if jq empty "${ISSUE_LOG}.tmp" 2>/dev/null; then
    mv "${ISSUE_LOG}.tmp" "$ISSUE_LOG"
    rm "$BACKUP_LOG"
    echo -e "${GREEN}✓ Added issue: $ID - $TITLE${NC}"
    echo -e "  Category: $CATEGORY"
    echo -e "  Severity: $SEVERITY"
    echo -e "  Outcome: $OUTCOME"
else
    echo -e "${RED}Error: Generated invalid JSON, restoring backup${NC}"
    mv "$BACKUP_LOG" "$ISSUE_LOG"
    rm -f "${ISSUE_LOG}.tmp"
    exit 1
fi
