#!/bin/bash
# verify-permissions.sh
# Filesystem Permission Drift Detection
#
# Purpose: Verify the POSIX ACL-based permission model is intact
# Run: ./scripts/verify-permissions.sh
#
# Exit codes: 0 = all pass, 1 = warnings, 2 = failures
#
# See: ADR-019 (Filesystem Permission Model)
# Status: ACTIVE
# Created: 2026-02-22

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
WARN=0
FAIL=0

pass() { echo -e "${GREEN}✅ PASS:${NC} $1"; ((PASS++)) || true; }
warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; ((WARN++)) || true; }
fail() { echo -e "${RED}❌ FAIL:${NC} $1"; ((FAIL++)) || true; }
info() { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }

POOL="/mnt/btrfs-pool"
NC_UID=100032  # Nextcloud www-data (container UID 33 + 100000 offset)
DOWNLOADS="$POOL/subvol6-tmp/Downloads"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}     FILESYSTEM PERMISSION DRIFT DETECTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Check 1: Subvolume root ownership and mode
# ============================================================================
echo "[1] Checking subvolume ownership..."

SUBVOLS=(subvol1-docs subvol2-pics subvol3-opptak subvol4-multimedia subvol5-music subvol6-tmp subvol7-containers)
for sv in "${SUBVOLS[@]}"; do
    SV_PATH="$POOL/$sv"
    if [[ ! -d "$SV_PATH" ]]; then
        warn "$sv not found"
        continue
    fi
    OWNER=$(stat -c '%U:%G' "$SV_PATH")
    PERMS=$(stat -c '%a' "$SV_PATH")
    HAS_ACL=$(getfacl -c "$SV_PATH" 2>/dev/null | grep -c "^user:[0-9]" || true)
    # ACL mask raises apparent group bits: stat reports 775 instead of 755.
    # Accept 775 when named user ACL entries are present.
    if [[ "$OWNER" != "patriark:patriark" ]]; then
        fail "$sv: owner is $OWNER (expected patriark:patriark)"
    elif [[ "$PERMS" == "755" ]]; then
        pass "$sv: $OWNER mode $PERMS"
    elif [[ "$PERMS" == "775" ]] && [[ "$HAS_ACL" -gt 0 ]]; then
        pass "$sv: $OWNER mode $PERMS (775 expected — ACL mask raises group bits)"
    else
        warn "$sv: mode is $PERMS (expected 755)"
    fi
done

# ============================================================================
# Check 2: POSIX ACLs on writable mounts
# ============================================================================
echo ""
echo "[2] Checking POSIX ACLs for Nextcloud (user:$NC_UID)..."

ACL_PATHS=(
    "$POOL/subvol1-docs:subvol1-docs"
    "$POOL/subvol2-pics:subvol2-pics"
    "$DOWNLOADS:Downloads"
)

for entry in "${ACL_PATHS[@]}"; do
    IFS=':' read -r path name <<< "$entry"
    if [[ ! -d "$path" ]]; then
        warn "$name not found"
        continue
    fi

    # Check access ACL
    ACCESS_ACL=$(getfacl -c "$path" 2>/dev/null | grep "^user:$NC_UID:" || true)
    # Check default ACL
    DEFAULT_ACL=$(getfacl -c "$path" 2>/dev/null | grep "^default:user:$NC_UID:" || true)

    if [[ -n "$ACCESS_ACL" ]] && [[ -n "$DEFAULT_ACL" ]]; then
        pass "$name: ACL access($ACCESS_ACL) + default($DEFAULT_ACL)"
    elif [[ -n "$ACCESS_ACL" ]]; then
        warn "$name: has access ACL but missing default ACL"
    else
        fail "$name: missing ACL for user:$NC_UID"
    fi
done

# ============================================================================
# Check 3: No world-writable directories
# ============================================================================
echo ""
echo "[3] Checking for world-writable directories..."

WORLD_WRITE=0
for sv in subvol1-docs subvol2-pics subvol3-opptak subvol6-tmp; do
    SV_PATH="$POOL/$sv"
    [[ -d "$SV_PATH" ]] || continue
    COUNT=$(find "$SV_PATH" -maxdepth 3 -type d -perm -o+w 2>/dev/null | wc -l)
    if [[ "$COUNT" -gt 0 ]]; then
        WORLD_WRITE=$((WORLD_WRITE + COUNT))
        EXAMPLES=$(find "$SV_PATH" -maxdepth 3 -type d -perm -o+w 2>/dev/null | head -3 | tr '\n' ' ')
        fail "$sv: $COUNT world-writable dirs (e.g. $EXAMPLES)"
    fi
done
if [[ "$WORLD_WRITE" -eq 0 ]]; then
    pass "No world-writable directories found"
fi

# ============================================================================
# Check 4: No SGID directories on standardized subvolumes
# ============================================================================
echo ""
echo "[4] Checking for SGID directories..."

SGID_TOTAL=0
for sv in subvol1-docs subvol2-pics subvol3-opptak; do
    SV_PATH="$POOL/$sv"
    [[ -d "$SV_PATH" ]] || continue
    COUNT=$(find "$SV_PATH" -maxdepth 3 -type d -perm -g+s 2>/dev/null | wc -l)
    if [[ "$COUNT" -gt 0 ]]; then
        SGID_TOTAL=$((SGID_TOTAL + COUNT))
        fail "$sv: $COUNT SGID directories found"
    fi
done
if [[ "$SGID_TOTAL" -eq 0 ]]; then
    pass "No SGID directories on subvol1/2/3"
fi

# ============================================================================
# Check 5: Samba decommissioned
# ============================================================================
echo ""
echo "[5] Checking Samba decommission state..."

# Service state
if systemctl is-active smb.service &>/dev/null; then
    fail "Samba (smb.service) is running"
elif systemctl is-enabled smb.service &>/dev/null; then
    warn "Samba (smb.service) is stopped but still enabled"
else
    pass "Samba service stopped and disabled"
fi

# Firewall ports (use ss to check listening ports — no sudo needed)
SMB_FW=false
if ss -tlnp 2>/dev/null | grep -qE ':139\b|:445\b'; then
    SMB_FW=true
fi
if $SMB_FW; then
    fail "Samba firewall ports still open"
else
    pass "Samba firewall ports closed"
fi

# ============================================================================
# Check 6: Nextcloud www-data write test
# ============================================================================
echo ""
echo "[6] Checking Nextcloud write access..."

if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -q '^nextcloud$'; then
    warn "Nextcloud container not running, skipping write tests"
else
    MOUNTS=(
        "/external/user-documents:Documents"
        "/external/user-photos:Photos"
        "/external/downloads:Downloads"
    )
    for entry in "${MOUNTS[@]}"; do
        IFS=':' read -r mount_path name <<< "$entry"
        TEST_FILE="$mount_path/.perm-test-$$"
        if podman exec -u www-data nextcloud touch "$TEST_FILE" 2>/dev/null && \
           podman exec -u www-data nextcloud rm -f "$TEST_FILE" 2>/dev/null; then
            pass "Nextcloud www-data can write to $name ($mount_path)"
        else
            fail "Nextcloud www-data cannot write to $name ($mount_path)"
            # Clean up just in case touch succeeded but rm failed
            podman exec nextcloud rm -f "$TEST_FILE" 2>/dev/null || true
        fi
    done
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✅ Passed:${NC}  $PASS"
echo -e "  ${YELLOW}⚠️  Warnings:${NC} $WARN"
echo -e "  ${RED}❌ Failed:${NC}  $FAIL"
echo ""

# Exit code
if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}Permission check: FAILED${NC}"
    exit 2
elif [[ "$WARN" -gt 0 ]]; then
    echo -e "${YELLOW}Permission check: WARNINGS${NC}"
    exit 1
else
    echo -e "${GREEN}Permission check: PASSED${NC}"
    exit 0
fi
