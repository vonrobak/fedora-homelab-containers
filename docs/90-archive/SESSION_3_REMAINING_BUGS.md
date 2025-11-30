# Session 3: Remaining Bugs & Follow-Up Tasks

**Created:** 2025-11-14
**Updated:** 2025-11-14 (Session 3.5 - BUGS FIXED)
**Status:** ✅ COMPLETE (both bugs fixed)
**Actual Time:** 45 minutes
**Priority:** RESOLVED

---

## ✅ Session 3.5 Resolution Summary

**Both bugs fixed successfully!** Root cause was identical: bash arithmetic post-increment with errexit.

### Bug #1: check-prerequisites.sh ✅ FIXED
- **Root cause:** `((CHECKS_PASSED++))` returns 0, triggers errexit
- **Fix:** Changed to `CHECKS_PASSED=$((CHECKS_PASSED + 1))`
- **Result:** All 7 checks complete successfully
- **Testing:** Validated with single/multiple networks, nonexistent networks

### Bug #2: homelab-intel.sh ✅ FIXED
- **Root cause:** `((running++))` returns 0, triggers errexit
- **Fix:** Changed to `running=$((running + 1))`
- **Result:** Script completes, generates health report (80/100)
- **Testing:** Full intelligence report generated in 2 seconds

**Commits:** 1d7bf12
**Report:** `docs/99-reports/2025-11-14-session-3.5-bug-fixes.md`

---

## Original Overview (Session 3 Validation)

Session 3 delivered 85% working functionality with 4/5 bugs fixed. Two issues remained that prevented full end-to-end deployment workflow but didn't block immediate use of the skill.

**What's Working:**
- ✅ check-drift.sh - Production-ready drift detection
- ✅ Pattern library - 9 comprehensive patterns
- ✅ deploy-from-pattern.sh - Help, pattern listing, quadlet generation

**What Needs Work:**
- ⚠️ check-prerequisites.sh - Stops after image check
- ⚠️ homelab-intel.sh - Hangs at Critical Services (pre-existing)

---

## Bug #1: check-prerequisites.sh Silent Failure

**File:** `.claude/skills/homelab-deployment/scripts/check-prerequisites.sh`
**Priority:** MEDIUM
**Estimated Fix Time:** 30-45 minutes
**Impact:** Blocks full pattern deployment workflow

### Symptom

Script stops execution after the image check (line 62) without displaying subsequent checks:
- ✅ Image check works and displays
- ❌ Network check doesn't display
- ❌ Port check doesn't display
- ❌ No summary shown

### Reproduction

```bash
cd .claude/skills/homelab-deployment

./scripts/check-prerequisites.sh \
  --service-name test-redis \
  --image docker.io/library/redis:7-alpine \
  --networks "systemd-monitoring"

# Output stops after:
# ✓ Image exists or pulled successfully: docker.io/library/redis:7-alpine
```

### Investigation Findings

1. **Script syntax is valid:** `bash -n check-prerequisites.sh` passes
2. **Network check uses IFS/read:** Lines 67-68 use `IFS=',' read -ra NETWORK_ARRAY`
3. **Script has `set -euo pipefail`:** May be exiting on unexpected condition
4. **No obvious error:** Silent failure suggests errexit triggering

### Root Cause Hypothesis

Likely causes (in order of probability):
1. **IFS/read array expansion issue** - The `read -ra` pattern may fail silently with errexit
2. **podman network exists exit code** - May return non-zero even with `2>/dev/null`
3. **Empty NETWORKS variable** - Pattern loading may not populate networks correctly
4. **Bash array handling in loop** - Array expansion `"${NETWORK_ARRAY[@]}"` may fail if empty

### Debugging Steps

**Step 1: Add debug output**
```bash
# Add after line 66 (before IFS read)
echo "DEBUG: NETWORKS variable: '$NETWORKS'"
echo "DEBUG: About to parse networks..."

# Add after line 67 (after IFS read)
echo "DEBUG: Array length: ${#NETWORK_ARRAY[@]}"
echo "DEBUG: Array contents: ${NETWORK_ARRAY[@]}"
```

**Step 2: Test IFS/read in isolation**
```bash
# Test the exact pattern used in script
NETWORKS="systemd-reverse_proxy,systemd-monitoring"
IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS"
echo "Length: ${#NETWORK_ARRAY[@]}"
for net in "${NETWORK_ARRAY[@]}"; do echo "Net: $net"; done
```

**Step 3: Test with errexit**
```bash
# Run script section with errexit
bash -c 'set -euo pipefail; NETWORKS="test"; IFS="," read -ra NETWORK_ARRAY <<< "$NETWORKS"; echo "Success: ${#NETWORK_ARRAY[@]}"'
```

**Step 4: Test empty array handling**
```bash
# Test what happens with empty networks
bash -c 'set -euo pipefail; declare -a NETWORK_ARRAY=(); for net in "${NETWORK_ARRAY[@]}"; do echo "$net"; done; echo "After loop"'
```

### Proposed Fix

**Option A: Safer array handling (Recommended)**
```bash
# Lines 64-75 (replace)
echo ""
echo "Checking networks..."
if [[ -n "$NETWORKS" ]]; then
    IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS" || true
    if [[ ${#NETWORK_ARRAY[@]} -gt 0 ]]; then
        for network in "${NETWORK_ARRAY[@]}"; do
            if podman network exists "$network" 2>/dev/null; then
                check_pass "Network exists: $network"
            else
                check_fail "Network not found: $network"
                echo "  Create with: podman network create $network"
            fi
        done
    else
        check_warn "No networks specified"
    fi
else
    check_warn "No networks specified"
fi
```

**Option B: Disable errexit temporarily**
```bash
# Before IFS read
set +e
IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS"
set -e
```

**Option C: Use simpler pattern**
```bash
# Replace IFS/read with tr + while loop
echo "$NETWORKS" | tr ',' '\n' | while read -r network; do
    if [[ -n "$network" ]]; then
        if podman network exists "$network" 2>/dev/null; then
            check_pass "Network exists: $network"
        else
            check_fail "Network not found: $network"
        fi
    fi
done
```

### Testing Plan

After implementing fix:

```bash
# Test 1: Single network
./scripts/check-prerequisites.sh \
  --service-name test \
  --image docker.io/library/redis:7-alpine \
  --networks "systemd-monitoring"

# Test 2: Multiple networks
./scripts/check-prerequisites.sh \
  --service-name test \
  --image docker.io/library/redis:7-alpine \
  --networks "systemd-reverse_proxy,systemd-monitoring"

# Test 3: Empty networks
./scripts/check-prerequisites.sh \
  --service-name test \
  --image docker.io/library/redis:7-alpine \
  --networks ""

# Test 4: Nonexistent network
./scripts/check-prerequisites.sh \
  --service-name test \
  --image docker.io/library/redis:7-alpine \
  --networks "nonexistent-network"

# Expected: All tests should complete showing all checks
```

### Success Criteria

- [ ] Script completes all 7 checks
- [ ] Summary section displays
- [ ] Exit code correct (0 if pass, 1 if fail)
- [ ] Works with single network
- [ ] Works with multiple comma-separated networks
- [ ] Works with empty networks (warning)
- [ ] Full pattern deployment workflow succeeds

---

## Bug #2: homelab-intel.sh Hanging

**File:** `~/containers/scripts/homelab-intel.sh`
**Priority:** HIGH (but pre-existing, not Session 3)
**Estimated Fix Time:** 30-60 minutes
**Impact:** Blocks check-system-health.sh intelligence integration

### Symptom

Script hangs indefinitely at the "Critical Services" section and never completes:

```bash
./scripts/homelab-intel.sh

# Output stops after:
▶ Critical Services
[hangs here forever]
```

### Investigation Findings

1. **Script reaches Critical Services section:** Uptime, SELinux, Disk usage all work
2. **No output after section header:** Suggests loop or command hang
3. **Not a timeout issue:** Runs indefinitely (tested for several minutes)
4. **Pre-existing issue:** Not introduced by Session 3 changes

### Root Cause Hypothesis

Likely in the `check_services()` function (need to examine):
1. **Infinite loop** - Service checking logic may loop forever
2. **Blocking command** - systemctl or podman command waiting for input
3. **Service query hang** - Querying failed/stuck service causes hang
4. **Race condition** - Service state check creates deadlock

### Debugging Steps

**Step 1: Identify exact hang location**
```bash
# Add set -x to see which command hangs
bash -x ~/containers/scripts/homelab-intel.sh 2>&1 | tee /tmp/intel-debug.log

# In another terminal, after it hangs:
tail -20 /tmp/intel-debug.log
```

**Step 2: Check for stuck systemctl commands**
```bash
# While script is hung, check for processes
ps aux | grep -E 'systemctl|podman|homelab-intel'

# Check for D state (uninterruptible sleep)
ps aux | awk '$8 ~ /D/ {print}'
```

**Step 3: Review check_services function**
```bash
# Find the function
sed -n '/check_services/,/^}/p' ~/containers/scripts/homelab-intel.sh | head -50
```

**Step 4: Test service checks individually**
```bash
# Test the commands that check_services likely uses
systemctl --user list-units --state=running --type=service | grep -E 'traefik|prometheus|grafana'

podman ps --format '{{.Names}}'

# Test with timeout
timeout 5s systemctl --user status traefik.service
```

### Proposed Fix

**Option A: Add timeout to service checks**
```bash
# In check_services function, wrap commands with timeout
timeout 5s systemctl --user is-active "${service}.service" || echo "timeout/failed"
```

**Option B: Skip problematic check**
```bash
# Temporarily comment out check_services call
# In main() function, comment:
# check_services
```

**Option C: Simplify service check**
```bash
# Replace complex check with simple podman ps
RUNNING_SERVICES=$(podman ps --format '{{.Names}}' 2>/dev/null || echo "")
```

### Testing Plan

After implementing fix:

```bash
# Test 1: Full run with timeout
timeout 30s ~/containers/scripts/homelab-intel.sh

# Expected: Should complete or timeout (not hang)

# Test 2: Quiet mode
timeout 30s ~/containers/scripts/homelab-intel.sh --quiet

# Test 3: Check JSON output created
ls -lt ~/containers/docs/99-reports/intel-*.json | head -1

# Test 4: Integration with check-system-health.sh
cd .claude/skills/homelab-deployment
timeout 30s ./scripts/check-system-health.sh
```

### Success Criteria

- [ ] homelab-intel.sh completes without hanging
- [ ] All sections display (System, Disk, Services, Resources, etc.)
- [ ] JSON report generated successfully
- [ ] check-system-health.sh can parse health score
- [ ] Deployment blocking works at low health scores
- [ ] Health score logged to deployment-logs/

---

## Testing Checklist (After Fixes)

### Full Workflow Test

```bash
cd .claude/skills/homelab-deployment

# Step 1: Health check
./scripts/check-system-health.sh
# Expected: Shows health score, proceeds or blocks appropriately

# Step 2: Pattern deployment (dry-run)
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name test-redis-final \
  --memory 256M \
  --dry-run
# Expected: Completes all steps including prerequisites

# Step 3: Pattern deployment (real)
./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name test-redis-final \
  --image docker.io/library/redis:7-alpine \
  --memory 256M
# Expected: Deploys successfully

# Step 4: Drift detection
./scripts/check-drift.sh test-redis-final
# Expected: Shows MATCH status for new service

# Step 5: Cleanup
systemctl --user stop test-redis-final.service
systemctl --user disable test-redis-final.service
podman rm test-redis-final
rm ~/.config/containers/systemd/test-redis-final.container
systemctl --user daemon-reload
```

### Success Criteria

- [ ] All 5 steps complete without errors
- [ ] Health check shows score and risk assessment
- [ ] Dry-run shows all validation steps
- [ ] Real deployment creates and starts service
- [ ] Drift detection confirms MATCH status
- [ ] Cleanup removes all artifacts

---

## Session 3.5 Plan (Optional Follow-Up)

**Goal:** Fix remaining bugs and complete full validation

**Duration:** 1-2 hours

**Tasks:**
1. Fix check-prerequisites.sh (30-45 min)
   - Add debug output
   - Implement safer array handling
   - Test with various inputs

2. Fix homelab-intel.sh (30-60 min)
   - Identify hang location with bash -x
   - Add timeouts to problematic commands
   - Test completion

3. End-to-end testing (15-30 min)
   - Deploy test service via pattern
   - Verify all checks work
   - Confirm drift detection

4. Update validation report (15 min)
   - Document fixes
   - Update success criteria
   - Mark Session 3 as complete

**Expected Outcome:** 100% working Session 3 functionality

---

## Workarounds (Until Fixed)

**For check-prerequisites.sh:**
```bash
# Use deploy-service.sh directly instead of deploy-from-pattern.sh
# Manual prerequisites verification:
podman image exists <image>
podman network exists <network>
ss -tulnp | grep <port>
```

**For homelab-intel.sh:**
```bash
# Use check-system-health.sh with --skip-health-check
./scripts/deploy-from-pattern.sh \
  --pattern <pattern> \
  --service-name <name> \
  --skip-health-check
```

**For full pattern deployment:**
```bash
# Use patterns as reference guides
# Deploy manually following pattern documentation:
cat patterns/<pattern>.yml
# Then use deploy-service.sh for orchestration
```

---

## Priority Assessment

**Fix Now (High Impact):**
- check-prerequisites.sh - Blocks pattern deployment automation

**Fix Soon (Medium Impact):**
- homelab-intel.sh - Blocks intelligence integration but has workaround

**Optional Enhancements:**
- Add more drift detection categories
- Improve error messages
- Add JSON output to more scripts

---

## Notes for Next Session

1. **Start with check-prerequisites.sh** - Quicker fix, higher impact
2. **Use debug logging extensively** - Add echo statements to trace execution
3. **Test incrementally** - Fix one section at a time
4. **Keep workarounds documented** - Pattern library is usable now
5. **Consider timeouts everywhere** - Prevent future hangs

---

**Created:** 2025-11-14
**Last Updated:** 2025-11-14
**Status:** Ready for follow-up session
**Effort:** 1-2 hours estimated
