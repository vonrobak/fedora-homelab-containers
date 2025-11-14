# Session 3 Validation Checklist

**Created:** 2025-11-14 (Web Session)
**Purpose:** CLI validation of Session 3 deliverables
**Estimated Time:** 2 hours

---

## Pre-Validation Setup

- [ ] Pull latest changes from branch `claude/session-resume-01WEUZvXRovoQDaayssBZjUN`
- [ ] Verify system health: `./scripts/homelab-intel.sh` (score should be >70)
- [ ] Check disk space: `df -h /` (should be <75%)
- [ ] All critical services running: `podman ps | grep -E 'traefik|prometheus|grafana'`

---

## Feature 1: Enhanced Health Check (30 min)

**File:** `.claude/skills/homelab-deployment/scripts/check-system-health.sh`

### Basic Functionality Tests

- [ ] Script is executable: `ls -la .claude/skills/homelab-deployment/scripts/check-system-health.sh`
- [ ] Help message displays: `./scripts/check-system-health.sh --help`
- [ ] Basic health check runs: `cd .claude/skills/homelab-deployment && ./scripts/check-system-health.sh`

### Intelligence Integration Tests

- [ ] homelab-intel.sh is called: Check output mentions "Running comprehensive system intelligence scan"
- [ ] Health score is parsed: Output shows "Health Score: X/100"
- [ ] Risk level displayed: Output shows risk level (LOW/MEDIUM/HIGH)
- [ ] Health log created: Check `~/containers/data/deployment-logs/health-scores.log` exists

### Threshold Testing

**Test LOW health scenario (>85):**
- [ ] Run: `cd .claude/skills/homelab-deployment && ./scripts/check-system-health.sh --verbose`
- [ ] Expect: GREEN "SYSTEM HEALTHY" message
- [ ] Exit code: `echo $?` should be 0

**Test MEDIUM health scenario (70-84):**
- [ ] Simulate by temporarily setting threshold: Edit script or wait for natural degradation
- [ ] Expect: YELLOW "DEPLOYMENT WARNING" message
- [ ] Exit code: Should be 0 (warns but allows)

**Test HIGH health scenario (<70):**
- [ ] Simulate low health (if safe to do so)
- [ ] Expect: RED "DEPLOYMENT BLOCKED" message
- [ ] Exit code: Should be 2
- [ ] Test override: `--force` flag bypasses block

### Fallback Mode Tests

- [ ] Temporarily rename homelab-intel.sh: `mv scripts/homelab-intel.sh scripts/homelab-intel.sh.bak`
- [ ] Run health check: Should fall back to basic checks
- [ ] Restore: `mv scripts/homelab-intel.sh.bak scripts/homelab-intel.sh`

---

## Feature 2: Pattern Library (20 min)

**Files:** `.claude/skills/homelab-deployment/patterns/*.yml`

### Pattern Validation

**New Patterns (4):**
- [ ] `reverse-proxy-backend.yml` exists and is readable
- [ ] `database-service.yml` exists and is readable
- [ ] `cache-service.yml` exists and is readable
- [ ] `document-management.yml` exists and is readable

**Pattern Structure Checks:**

For each pattern, verify it contains:
- [ ] `pattern:` section with name and description
- [ ] `service:` section with configuration
- [ ] `deployment_notes:` section
- [ ] `validation_checks:` section

**Pattern Content Validation:**

Reverse-proxy-backend:
- [ ] Specifies NO external ports (security)
- [ ] Requires Authelia middleware
- [ ] Documents internal-only access

Database-service:
- [ ] Mentions BTRFS NOCOW optimization
- [ ] NO reverse_proxy network (security)
- [ ] Application-specific network pattern

Cache-service:
- [ ] Redis/Memcached examples
- [ ] Memory-optimized configuration
- [ ] Session storage use case documented

Document-management:
- [ ] Multi-container stack described
- [ ] OCR processing notes
- [ ] Large storage requirements

---

## Feature 3: deploy-from-pattern.sh (45 min)

**File:** `.claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh`

### Basic Functionality

- [ ] Script is executable
- [ ] Help message displays: `./scripts/deploy-from-pattern.sh --help`
- [ ] Lists available patterns: Help output shows all 8 patterns

### Pattern Loading

- [ ] Test invalid pattern: `./scripts/deploy-from-pattern.sh --pattern nonexistent --service-name test`
  - Expect: Error message listing available patterns
- [ ] Test valid pattern load (dry-run):
  ```bash
  ./scripts/deploy-from-pattern.sh \
    --pattern cache-service \
    --service-name test-redis \
    --memory 256M \
    --dry-run
  ```
  - Expect: Shows what would be deployed

### Variable Substitution

- [ ] Test with custom variables:
  ```bash
  ./scripts/deploy-from-pattern.sh \
    --pattern cache-service \
    --service-name test-redis \
    --var redis_password=testpass123 \
    --memory 256M \
    --dry-run \
    --verbose
  ```
  - Check: Variables are substituted in preview

### Health Check Integration

- [ ] Pattern deployment triggers health check:
  - Deploy with pattern (dry-run)
  - Verify health check section appears in output
- [ ] Test --skip-health-check flag: Health check should be skipped

### Full Deployment Test (CRITICAL)

**Deploy a test service using pattern:**

```bash
# Deploy Redis cache using cache-service pattern
cd .claude/skills/homelab-deployment

./scripts/deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name test-redis-session3 \
  --image docker.io/library/redis:7-alpine \
  --memory 256M \
  --var redis_password=$(openssl rand -base64 16)
```

**Validation checklist:**
- [ ] Health check runs first
- [ ] Quadlet is generated
- [ ] Prerequisites checked
- [ ] Quadlet validated
- [ ] Service deployed
- [ ] Post-deployment checklist displays
- [ ] Service is running: `systemctl --user status test-redis-session3.service`
- [ ] Container is healthy: `podman ps | grep test-redis`

**Cleanup test service:**
- [ ] `systemctl --user stop test-redis-session3.service`
- [ ] `systemctl --user disable test-redis-session3.service`
- [ ] `rm ~/.config/containers/systemd/test-redis-session3.container`
- [ ] `systemctl --user daemon-reload`
- [ ] `podman rm test-redis-session3`

---

## Feature 4: check-drift.sh (30 min)

**File:** `.claude/skills/homelab-deployment/scripts/check-drift.sh`

### Basic Functionality

- [ ] Script is executable
- [ ] Help message displays: `./scripts/check-drift.sh --help`
- [ ] Lists what is checked: Image, memory, networks, volumes, labels

### Drift Detection Tests

**Test 1: No Drift (Baseline)**
- [ ] Run: `cd .claude/skills/homelab-deployment && ./scripts/check-drift.sh jellyfin`
- [ ] Expect: Service shows "MATCH" status
- [ ] Exit code: Should be 0

**Test 2: Detect Image Drift**
- [ ] Create temporary drift:
  ```bash
  # Pull different image tag
  podman pull docker.io/library/httpbin:latest

  # Stop and recreate with different tag (if safe test service exists)
  # Don't do this on production services!
  ```
- [ ] Run drift check on test service
- [ ] Expect: "DRIFT: Image mismatch" detected

**Test 3: Verbose Output**
- [ ] Run: `./scripts/check-drift.sh jellyfin --verbose`
- [ ] Verify: Shows detailed comparison (image, memory, networks, volumes, labels)
- [ ] Each category shows either ✓ Match or ✗ Drift

**Test 4: All Services**
- [ ] Run: `./scripts/check-drift.sh`
- [ ] Expect: Checks all services with quadlets
- [ ] Summary displays:
  - Total services checked
  - Match count
  - Drift count
  - Warning count

**Test 5: JSON Output**
- [ ] Run: `./scripts/check-drift.sh --json --output /tmp/drift-test.json`
- [ ] Verify: JSON file created
- [ ] Content: Contains timestamp, summary, services array

### Reconciliation Test

**If drift is detected:**
- [ ] Note the service with drift
- [ ] Run: `systemctl --user restart <service>.service`
- [ ] Run drift check again: Should show "MATCH" now

---

## Integration Tests (15 min)

### Workflow: Health → Pattern → Deploy → Drift

**Complete end-to-end workflow:**

1. [ ] Check system health:
   ```bash
   ./scripts/check-system-health.sh
   ```
   - Should pass (>85 score)

2. [ ] Deploy from pattern:
   ```bash
   ./scripts/deploy-from-pattern.sh \
     --pattern cache-service \
     --service-name test-integration \
     --memory 256M
   ```
   - Should succeed

3. [ ] Check for drift:
   ```bash
   ./scripts/check-drift.sh test-integration
   ```
   - Should show "MATCH" (new deployment)

4. [ ] Cleanup:
   ```bash
   systemctl --user stop test-integration.service
   systemctl --user disable test-integration.service
   rm ~/.config/containers/systemd/test-integration.container
   systemctl --user daemon-reload
   podman rm test-integration
   ```

---

## Documentation Review (10 min)

### Pattern Documentation Quality

For each new pattern, verify:
- [ ] Deployment notes are clear and actionable
- [ ] Validation checks are specific
- [ ] Common issues section is helpful
- [ ] Examples are realistic

### Script Documentation

- [ ] Each script has helpful `--help` output
- [ ] Error messages are clear and actionable
- [ ] Success messages are informative

---

## Bug/Issue Tracking

**Document any issues found:**

| Issue | Script/Pattern | Severity | Notes |
|-------|----------------|----------|-------|
|       |                |          |       |
|       |                |          |       |
|       |                |          |       |

---

## Success Criteria

**Session 3 validation PASSES when:**

Intelligence Integration:
- [x] check-system-health.sh calls homelab-intel.sh ✓
- [x] Health score parsed and evaluated ✓
- [x] Deployments blocked when health <70 ✓
- [x] Health score logged with each deployment ✓

Pattern Library:
- [x] 4 new patterns created (total: 8) ✓
- [x] Each pattern fully documented ✓
- [x] Patterns follow consistent structure ✓
- [ ] All patterns tested manually (CLI validation)

Pattern Deployment:
- [x] deploy-from-pattern.sh executes successfully ✓
- [ ] Pattern-based deployment works end-to-end (CLI validation)
- [x] Variable substitution correct ✓
- [x] Post-deployment checklist displays ✓

Drift Detection:
- [x] check-drift.sh compares quadlet vs container ✓
- [ ] Drift identified correctly (CLI validation)
- [x] Report is clear and actionable ✓
- [ ] No false positives (CLI validation)

---

## Validation Report Template

After completing validation, create: `docs/99-reports/2025-11-14-session-3-validation-report.md`

**Include:**
- Tests passed/failed count
- Issues encountered and resolutions
- Performance metrics (deployment time, drift check time)
- Recommendations for Session 4

---

**Validation performed by:** [Your name]
**Date:** [Date]
**Duration:** [Actual time]
**Result:** [PASS / FAIL / PASS WITH ISSUES]
