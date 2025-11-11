#!/usr/bin/env bash

# sanitize-for-public.sh
# Sanitizes homelab repository for public release by replacing sensitive information

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 Homelab Repository Sanitization${NC}"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "CLAUDE.md" ]]; then
    echo -e "${RED}❌ Error: CLAUDE.md not found. Run this script from repository root.${NC}"
    exit 1
fi

# Confirm sanitization
echo -e "${YELLOW}⚠️  WARNING: This will modify files in place!${NC}"
echo "Make sure you're working on a copy or branch, not your main repository."
echo ""
read -p "Continue with sanitization? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting sanitization...${NC}"
echo ""

# Create backup
BACKUP_DIR="sanitization-backup-$(date +%Y%m%d-%H%M%S)"
echo "📦 Creating backup in ${BACKUP_DIR}..."
mkdir -p "$BACKUP_DIR"
cp -r docs/ "$BACKUP_DIR/" 2>/dev/null || true
cp CLAUDE.md README.md "$BACKUP_DIR/" 2>/dev/null || true
echo -e "${GREEN}✓${NC} Backup created"
echo ""

# Function to replace in files
replace_in_files() {
    local pattern="$1"
    local replacement="$2"
    local description="$3"

    echo "🔄 Replacing: $description"

    # Count occurrences before replacement
    local count=$(grep -r "$pattern" \
        --include="*.md" \
        --include="*.yml" \
        --include="*.yaml" \
        --exclude-dir=".git" \
        --exclude-dir="$BACKUP_DIR" \
        . 2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
        # Perform replacement
        find . -type f \
            \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
            ! -path "./.git/*" \
            ! -path "./${BACKUP_DIR}/*" \
            -exec sed -i "s|${pattern}|${replacement}|g" {} +

        echo -e "  ${GREEN}✓${NC} Replaced ${count} occurrences"
    else
        echo -e "  ${YELLOW}○${NC} No occurrences found"
    fi
}

# Domain replacements
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Domain Sanitization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
replace_in_files "patriark\.org" "example.com" "patriark.org → example.com"
replace_in_files "patriark\.lokal" "example.local" "patriark.lokal → example.local (internal DNS)"
echo ""

# Username replacements
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Username Sanitization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
replace_in_files "patriark:" "homelab-admin:" "patriark: → homelab-admin: (in configs)"
replace_in_files "user patriark" "user homelab-admin" "user patriark → user homelab-admin"
replace_in_files "username patriark" "username homelab-admin" "username patriark → username homelab-admin"
# Keep "patriark" in narrative text (e.g., "patriark's homelab") - only replace in technical contexts
echo ""

# Email replacements
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Email Sanitization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
replace_in_files "surfaceideology@proton\.me" "admin@example.com" "Personal email → admin@example.com"
echo ""

# IP Address replacements
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "IP Address Sanitization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
replace_in_files "62\.249\.184\.112" "203.0.113.100" "Public IP → TEST-NET-3 range"
replace_in_files "192\.168\.1\.69" "192.168.1.10" "Specific local IP → generic"
replace_in_files "192\.168\.1\.70" "192.168.1.20" "Specific local IP → generic"
echo ""

# Specific host references
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Hostname Sanitization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
replace_in_files "fedora-htpc" "homelab-server" "fedora-htpc → homelab-server"
echo ""

# Check for any remaining sensitive patterns
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Final Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "🔍 Checking for remaining sensitive information..."
echo ""

# Check for email patterns
email_count=$(grep -rE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" \
    --include="*.md" \
    --exclude-dir=".git" \
    --exclude-dir="$BACKUP_DIR" \
    . 2>/dev/null | grep -v "example.com" | wc -l)

if [[ $email_count -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found ${email_count} potential email addresses (excluding example.com)${NC}"
    grep -rE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" \
        --include="*.md" \
        --exclude-dir=".git" \
        --exclude-dir="$BACKUP_DIR" \
        . 2>/dev/null | grep -v "example.com" | head -5
    echo "  (showing first 5)"
else
    echo -e "${GREEN}✓${NC} No email addresses found (excluding example.com)"
fi

# Check for .org domains (might catch missed domains)
org_domains=$(grep -r "\.org" \
    --include="*.md" \
    --exclude-dir=".git" \
    --exclude-dir="$BACKUP_DIR" \
    . 2>/dev/null | grep -v "example.com" | grep -v "GitHub" | grep -v "organization" | wc -l)

if [[ $org_domains -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found ${org_domains} .org references (excluding example.com)${NC}"
    echo "  Review these manually - may be legitimate (e.g., github.org)"
else
    echo -e "${GREEN}✓${NC} No unexpected .org domains found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Sanitization Complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Backup location: ${BACKUP_DIR}/"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff"
echo "2. Check random files manually"
echo "3. Run: git status"
echo "4. If satisfied, commit sanitized version"
echo ""
echo -e "${YELLOW}⚠️  Important: Review files manually before making repository public!${NC}"
