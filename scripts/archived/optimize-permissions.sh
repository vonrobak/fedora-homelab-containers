#!/bin/bash
# optimize-permissions.sh
# Homelab Filesystem Permission Optimization
#
# Purpose: Decommission Samba, standardize subvolume ownership,
#          establish POSIX ACL-based permission model
#
# Run: sudo ~/containers/scripts/optimize-permissions.sh
#
# Phases:
#   0: Pre-flight safety (BTRFS snapshots + ACL preservation test)
#   1: Decommission Samba (stop service, close firewall ports)
#   2: Fix Downloads permissions (replace 2777 with ACLs)
#   3: Standardize subvolume ownership (chgrp, remove SGID, set modes)
#
# Rollback: sudo btrfs subvolume delete /mnt/btrfs-pool/.snapshots/subvol*-pre-perms
#
# See: ADR-019 (Filesystem Permission Model)
# Status: ACTIVE
# Created: 2026-02-22

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Paths
POOL="/mnt/btrfs-pool"
SNAP_DIR="$POOL/.snapshots"
DOWNLOADS="$POOL/subvol6-tmp/Downloads"
OWNER="patriark"
OWNER_UID=1000
OWNER_GID=1000
NC_UID=100032  # Nextcloud www-data (container UID 33 + 100000 offset)

# Counters
STEP=0
ERRORS=0

step() {
    ((STEP++)) || true
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Step $STEP: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; ((ERRORS++)) || true; }
info() { echo -e "  ${BLUE}ℹ️  $1${NC}"; }

abort() {
    echo ""
    echo -e "${RED}ABORT: $1${NC}"
    echo -e "${RED}No changes have been made. Fix the issue and re-run.${NC}"
    exit 1
}

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    HOMELAB FILESYSTEM PERMISSION OPTIMIZATION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Host: $(hostname)"
echo ""

# ============================================================================
# Phase 0: Pre-flight Safety
# ============================================================================
step "Pre-flight: BTRFS snapshots"

mkdir -p "$SNAP_DIR"

SUBVOLS=(subvol1-docs subvol2-pics subvol3-opptak subvol6-tmp)
for sv in "${SUBVOLS[@]}"; do
    SNAP_NAME="${sv}-pre-perms"
    if btrfs subvolume show "$SNAP_DIR/$SNAP_NAME" &>/dev/null; then
        warn "Snapshot $SNAP_NAME already exists (from previous run?), skipping"
    else
        btrfs subvolume snapshot -r "$POOL/$sv" "$SNAP_DIR/$SNAP_NAME"
        ok "Snapshot: $SNAP_NAME"
    fi
done

step "Pre-flight: ACL preservation test"

# Create a test file, set an ACL, chgrp it, verify ACL survives
TEST_DIR="$POOL/subvol6-tmp"
TEST_FILE="$TEST_DIR/.acl-test-$$"

touch "$TEST_FILE"
chown "$OWNER:$OWNER" "$TEST_FILE"
setfacl -m u:$NC_UID:rw "$TEST_FILE"

# Capture ACL before chgrp
ACL_BEFORE=$(getfacl -c "$TEST_FILE" 2>/dev/null | grep "user:$NC_UID")

chgrp "$OWNER" "$TEST_FILE"

# Capture ACL after chgrp
ACL_AFTER=$(getfacl -c "$TEST_FILE" 2>/dev/null | grep "user:$NC_UID")

rm -f "$TEST_FILE"

if [[ "$ACL_BEFORE" == "$ACL_AFTER" ]] && [[ -n "$ACL_BEFORE" ]]; then
    ok "ACL preserved after chgrp ($ACL_AFTER)"
else
    abort "chgrp destroyed ACLs! Before: '$ACL_BEFORE', After: '$ACL_AFTER'"
fi

# ============================================================================
# Phase 1: Decommission Samba
# ============================================================================
step "Decommission Samba services"

# Stop and disable SMB/NMB
for svc in smb.service nmb.service; do
    if systemctl is-active "$svc" &>/dev/null; then
        systemctl stop "$svc"
        ok "Stopped $svc"
    else
        info "$svc already stopped"
    fi
    if systemctl is-enabled "$svc" &>/dev/null; then
        systemctl disable "$svc"
        ok "Disabled $svc"
    else
        info "$svc already disabled"
    fi
done

step "Close Samba firewall ports"

CHANGED=false
for fw_svc in samba samba-client; do
    if firewall-cmd --query-service="$fw_svc" --permanent &>/dev/null; then
        firewall-cmd --permanent --remove-service="$fw_svc"
        ok "Removed firewall service: $fw_svc"
        CHANGED=true
    else
        info "Firewall service $fw_svc not present"
    fi
done

if $CHANGED; then
    firewall-cmd --reload
    ok "Firewall reloaded"
else
    info "No firewall changes needed"
fi

step "Remove user from samba group"

if id -nG "$OWNER" | grep -qw samba; then
    gpasswd -d "$OWNER" samba
    ok "Removed $OWNER from samba group"
else
    info "$OWNER not in samba group"
fi

info "Samba package kept installed (zero cost, easy re-enable)"

# ============================================================================
# Phase 2: Fix Downloads Permissions
# ============================================================================
step "Fix Downloads directory permissions"

if [[ ! -d "$DOWNLOADS" ]]; then
    fail "Downloads directory not found: $DOWNLOADS"
else
    FILE_COUNT=$(find "$DOWNLOADS" -maxdepth 0 -printf '%y' 2>/dev/null | wc -c)
    TOTAL_FILES=$(find "$DOWNLOADS" -type f 2>/dev/null | wc -l)
    TOTAL_DIRS=$(find "$DOWNLOADS" -type d 2>/dev/null | wc -l)
    info "Downloads contains $TOTAL_FILES files, $TOTAL_DIRS directories"

    # Set directory permissions: 0755 + ACLs
    info "Setting directory permissions to 0755 + ACL u:$NC_UID:rwx..."
    find "$DOWNLOADS" -type d -exec chmod 0755 {} +
    find "$DOWNLOADS" -type d -exec setfacl -m u:$NC_UID:rwx {} +
    find "$DOWNLOADS" -type d -exec setfacl -d -m u:$NC_UID:rwx {} +
    ok "Directories: 0755 + ACL access+default u:$NC_UID:rwx"

    # Set file permissions: 0644 + ACLs
    info "Setting file permissions to 0644 + ACL u:$NC_UID:rw..."
    find "$DOWNLOADS" -type f -exec chmod 0644 {} +
    find "$DOWNLOADS" -type f -exec setfacl -m u:$NC_UID:rw {} +
    ok "Files: 0644 + ACL u:$NC_UID:rw"

    # Remove any world-writable bits
    find "$DOWNLOADS" -perm -o+w -exec chmod o-w {} +
    ok "Removed all world-writable bits"

    # Verify
    # Note: setfacl -d (default ACL) auto-sets SGID bit, and ACL mask raises
    # apparent group bits. stat -c %a will show 2775 not 755 — this is correct.
    DL_ACL=$(getfacl -c "$DOWNLOADS" 2>/dev/null | grep "user:$NC_UID" | head -1)
    DL_DEFAULT=$(getfacl -c "$DOWNLOADS" 2>/dev/null | grep "default:user:$NC_UID" || true)
    DL_WORLD=$(stat -c %a "$DOWNLOADS" | grep -o '.$')  # last digit = others
    if [[ -n "$DL_ACL" ]] && [[ -n "$DL_DEFAULT" ]] && [[ "$DL_WORLD" != "7" ]] && [[ "$DL_WORLD" != "6" ]]; then
        ok "Verified: Downloads has ACL $DL_ACL + default, others=r-x"
    else
        fail "Downloads verification failed: ACL=$DL_ACL, default=$DL_DEFAULT, others=$DL_WORLD"
    fi
fi

# ============================================================================
# Phase 3: Standardize Subvolume Ownership
# ============================================================================
SUBVOLS_TO_FIX=(subvol1-docs subvol2-pics subvol3-opptak)

for sv in "${SUBVOLS_TO_FIX[@]}"; do
    SV_PATH="$POOL/$sv"
    step "Standardize $sv"

    if [[ ! -d "$SV_PATH" ]]; then
        fail "$sv not found at $SV_PATH"
        continue
    fi

    # Count files for progress
    TOTAL=$(find "$SV_PATH" -mindepth 1 2>/dev/null | wc -l)
    info "$sv: $TOTAL items to process"

    # Change group ownership from samba to patriark
    info "Changing group ownership to $OWNER..."
    chgrp -R "$OWNER" "$SV_PATH"
    ok "Group ownership changed to $OWNER"

    # Remove SGID bits from all directories
    info "Removing SGID bits from directories..."
    find "$SV_PATH" -type d -perm -g+s -exec chmod g-s {} +
    ok "SGID bits removed"

    # Set standard directory permissions
    info "Setting directory permissions to 0755..."
    find "$SV_PATH" -type d -exec chmod 0755 {} +
    ok "Directories set to 0755"

    # Set standard file permissions
    info "Setting file permissions to 0644..."
    find "$SV_PATH" -type f -exec chmod 0644 {} +
    ok "Files set to 0644"

    # Re-apply ACL masks on subvol1 and subvol2
    # chmod resets ACL mask to match traditional group bits (r-x for 0755),
    # which limits named ACL entries. Re-applying ACLs auto-corrects the mask.
    if [[ "$sv" == "subvol1-docs" ]] || [[ "$sv" == "subvol2-pics" ]]; then
        info "Re-applying ACLs after chmod (mask correction)..."
        find "$SV_PATH" -type d -exec setfacl -m u:$NC_UID:rwx {} +
        find "$SV_PATH" -type d -exec setfacl -d -m u:$NC_UID:rwx {} +
        find "$SV_PATH" -type f -exec setfacl -m u:$NC_UID:rw {} +
        ok "ACLs re-applied on $sv (mask corrected to rwx/rw)"
    fi

    # Verify final state
    SV_OWNER=$(stat -c '%U:%G' "$SV_PATH")
    SV_PERMS=$(stat -c '%a' "$SV_PATH")
    SGID_COUNT=$(find "$SV_PATH" -type d -perm -g+s 2>/dev/null | wc -l)
    WORLD_WRITE=$(find "$SV_PATH" -perm -o+w 2>/dev/null | wc -l)

    info "Final state: owner=$SV_OWNER, mode=$SV_PERMS, SGID dirs=$SGID_COUNT, world-writable=$WORLD_WRITE"

    if [[ "$SV_OWNER" == "$OWNER:$OWNER" ]] && [[ "$SGID_COUNT" -eq 0 ]] && [[ "$WORLD_WRITE" -eq 0 ]]; then
        ok "$sv standardized successfully"
    else
        fail "$sv has issues (see above)"
    fi
done

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Steps completed: $STEP"
echo -e "  Errors: $ERRORS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Completed with $ERRORS error(s). Review output above.${NC}"
    echo ""
    echo -e "${YELLOW}Rollback snapshots available:${NC}"
    for sv in "${SUBVOLS[@]}"; do
        echo "  sudo btrfs subvolume delete $SNAP_DIR/${sv}-pre-perms"
    done
    exit 1
else
    echo -e "${GREEN}All phases completed successfully!${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Return to Claude Code for service verification (Phase 4)"
    echo -e "  2. After verification, clean up snapshots:"
    for sv in "${SUBVOLS[@]}"; do
        echo "      sudo btrfs subvolume delete $SNAP_DIR/${sv}-pre-perms"
    done
fi
echo ""
