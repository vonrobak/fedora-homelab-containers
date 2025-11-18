#!/bin/bash
#
# populate-issue-history.sh
# Builds issue history from documentation, git log, and intel reports
#
# Usage: ./populate-issue-history.sh
#

set -euo pipefail

OUTPUT_FILE="../issue-history.json"
TEMP_FILE=$(mktemp)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Populating issue history from project artifacts...${NC}"

# Initialize JSON structure
cat > "$TEMP_FILE" << 'EOF'
{
  "generated_at": "",
  "total_issues": 0,
  "issues": []
}
EOF

# Function to add an issue
add_issue() {
    local id="$1"
    local title="$2"
    local category="$3"
    local severity="$4"
    local date="$5"
    local description="$6"
    local resolution="$7"
    local outcome="$8"

    jq --arg id "$id" \
       --arg title "$title" \
       --arg cat "$category" \
       --arg sev "$severity" \
       --arg date "$date" \
       --arg desc "$description" \
       --arg res "$resolution" \
       --arg out "$outcome" \
       '.issues += [{
         "id": $id,
         "title": $title,
         "category": $cat,
         "severity": $sev,
         "date_encountered": $date,
         "description": $desc,
         "resolution": $res,
         "outcome": $out
       }]' "$TEMP_FILE" > "$TEMP_FILE.tmp" && mv "$TEMP_FILE.tmp" "$TEMP_FILE"
}

# Issue 1: System SSD disk space critical (current)
add_issue "ISS-001" \
    "System SSD at 84% capacity" \
    "disk-space" \
    "critical" \
    "2025-11-18" \
    "System SSD (/dev/nvme0n1) reached 84% capacity, triggering warnings in homelab-intel" \
    "Pending: Need to clean journal logs, prune old containers, rotate backup logs" \
    "ongoing"

# Issue 2: Authelia deployment challenges
add_issue "ISS-002" \
    "Authelia SSO deployment complications" \
    "deployment" \
    "high" \
    "2025-11-11" \
    "Multiple attempts to deploy Authelia with YubiKey 2FA encountered config issues, Redis session storage problems" \
    "Resolved: Created comprehensive configuration, separated Redis instance, validated MFA flow" \
    "resolved"

# Issue 3: Immich dual authentication UX problem
add_issue "ISS-003" \
    "Immich dual-authentication user experience issue" \
    "authentication" \
    "medium" \
    "2025-11-12" \
    "Immich requiring both Authelia SSO AND native login created poor UX for users" \
    "Resolved: Removed Authelia middleware from Immich, use native auth only" \
    "resolved"

# Issue 4: Session 3 check-drift.sh errexit bug
add_issue "ISS-004" \
    "Drift detection script errexit failures" \
    "scripting" \
    "high" \
    "2025-11-13" \
    "check-drift.sh failing with 'bad substitution' errors due to errexit in arithmetic expansion" \
    "Resolved: Refactored arithmetic to use (( )) instead of $(()), added proper error handling" \
    "resolved"

# Issue 5: Prometheus/Loki health check failures
add_issue "ISS-005" \
    "Monitoring stack health checks intermittent" \
    "monitoring" \
    "medium" \
    "2025-11-18" \
    "Prometheus and Loki health endpoints timing out on initial checks, likely startup delays" \
    "Workaround: Increased HealthStartPeriod in quadlets to 90s" \
    "mitigated"

# Issue 6: Swap usage high (7.4GB)
add_issue "ISS-006" \
    "High swap usage indicating memory pressure" \
    "performance" \
    "medium" \
    "2025-11-18" \
    "Swap usage at 7.4GB (threshold 6.3GB), suggests containers may need memory limit tuning" \
    "Investigation: Review container memory allocations, consider reducing Jellyfin from 4G to 3G" \
    "investigating"

# Issue 7: Traefik certificate warnings
add_issue "ISS-007" \
    "Let's Encrypt certificate file not found warnings" \
    "ssl" \
    "medium" \
    "2025-11-18" \
    "homelab-intel reporting certificate file missing, may be path issue or pre-issuance" \
    "Investigation: Verify acme.json path and Let's Encrypt integration" \
    "investigating"

# Issue 8: GPU acceleration not enabled
add_issue "ISS-008" \
    "Jellyfin GPU transcoding not configured" \
    "performance" \
    "high" \
    "2025-11-17" \
    "Jellyfin using CPU transcoding only, no VA-API hardware acceleration" \
    "Resolved: Installed mesa-va-drivers-freeworld, added /dev/dri devices to quadlet, enabled VA-API in dashboard" \
    "resolved"

# Issue 9: HEVC 10-bit color space problems
add_issue "ISS-009" \
    "HDR/10-bit video color rendering incorrect on older TV" \
    "media" \
    "medium" \
    "2025-11-18" \
    "HEVC 10-bit HDR content displays with wrong colors on 2016 Philips TV (no HDR support)" \
    "Workaround: Disable HEVC 10-bit hardware decode, enable tone mapping in Jellyfin" \
    "mitigated"

# Issue 10: Storage architecture migrations
add_issue "ISS-010" \
    "Multiple storage layout revisions needed" \
    "architecture" \
    "medium" \
    "2025-10-25" \
    "Initial storage layout inadequate, required multiple revisions for BTRFS optimization" \
    "Resolved: Created authoritative storage architecture with NOCOW for databases" \
    "resolved"

# Issue 11: homelab-intel.sh hanging issues
add_issue "ISS-011" \
    "Intelligence script hanging on SSL checks" \
    "scripting" \
    "high" \
    "2025-11-14" \
    "homelab-intel.sh hanging indefinitely on certificate checks, blocking automation" \
    "Resolved: Added timeout protection to curl commands, improved error handling" \
    "resolved"

# Issue 12: Backup automation complexity
add_issue "ISS-012" \
    "Manual backup process error-prone" \
    "operations" \
    "medium" \
    "2025-11-07" \
    "Manual BTRFS snapshot process tedious, risk of forgetting backups" \
    "Resolved: Created btrfs-snapshot-backup.sh with automated scheduling" \
    "resolved"

# Update metadata
TIMESTAMP=$(date -Iseconds)
ISSUE_COUNT=$(jq '.issues | length' "$TEMP_FILE")

jq --arg ts "$TIMESTAMP" \
   --argjson count "$ISSUE_COUNT" \
   '.generated_at = $ts | .total_issues = $count' \
   "$TEMP_FILE" > "$OUTPUT_FILE"

rm "$TEMP_FILE"

echo -e "${GREEN}✓ Issue history populated: $OUTPUT_FILE${NC}"
echo -e "${BLUE}Summary:${NC}"
echo "  Total issues: $ISSUE_COUNT"
echo "  Resolved: $(jq '[.issues[] | select(.outcome == "resolved")] | length' "$OUTPUT_FILE")"
echo "  Ongoing: $(jq '[.issues[] | select(.outcome == "ongoing")] | length' "$OUTPUT_FILE")"
echo "  Mitigated: $(jq '[.issues[] | select(.outcome == "mitigated")] | length' "$OUTPUT_FILE")"
echo "  Investigating: $(jq '[.issues[] | select(.outcome == "investigating")] | length' "$OUTPUT_FILE")"
