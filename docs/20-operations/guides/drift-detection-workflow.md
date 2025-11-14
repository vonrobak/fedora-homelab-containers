# Configuration Drift Detection Workflow

**Created:** 2025-11-14
**Purpose:** Systematic approach to detecting and reconciling configuration drift
**Skill:** homelab-deployment (check-drift.sh)
**Status:** Production ✅

---

## Overview

**Configuration drift** occurs when a running container's configuration diverges from its systemd quadlet definition. This happens when:

- Quadlet file is edited but service not restarted
- Container manually modified via `podman` commands
- Image updated without quadlet update
- Networks or volumes changed outside quadlet

**Drift detection** compares running containers against their quadlet definitions and identifies mismatches that require reconciliation.

---

## Quick Reference

### Check Single Service

```bash
cd .claude/skills/homelab-deployment

# Basic check
./scripts/check-drift.sh jellyfin

# Verbose (shows detailed comparison)
./scripts/check-drift.sh jellyfin --verbose

# JSON output
./scripts/check-drift.sh jellyfin --json
```

### Check All Services

```bash
# Check all services (scans systemd quadlets)
./scripts/check-drift.sh

# Save results to file
./scripts/check-drift.sh > drift-report-$(date +%Y%m%d).txt

# JSON report for automation
./scripts/check-drift.sh --json --output drift-$(date +%Y%m%d).json
```

### Common Results

**✓ MATCH** - Configuration correct (no action needed)
```
Service: jellyfin
  ✓ Image: matches
  ✓ Memory: matches
  ✓ Networks: matches
  ✓ Volumes: matches
  ✓ Labels: matches
Status: MATCH
```

**✗ DRIFT** - Mismatch detected (restart required)
```
Service: jellyfin
  ✓ Image: matches
  ✗ Memory: DRIFT
    Quadlet: 4G
    Running: 2G
  ✓ Networks: matches
Status: DRIFT (restart required)
```

**⚠ WARNING** - Minor difference (informational only)
```
Service: jellyfin
  ✓ Image: matches
  ✓ Memory: matches
  ⚠ Networks: order differs (warning)
  ✓ Volumes: matches
Status: WARNING (informational)
```

---

## Drift Categories

### What is Checked

**1. Image Version**
- Compares running container image:tag vs quadlet Image= line
- Detects: Outdated images, manual image changes
- Fix: Update quadlet Image= and restart

**2. Memory Limits**
- Compares running memory limits vs quadlet Memory=/MemoryHigh=
- Detects: Resource limit changes
- Fix: Update quadlet limits and restart

**3. Networks**
- Compares running networks vs quadlet Network= lines
- Detects: Network additions/removals, order changes
- Fix: Update quadlet networks and restart

**4. Volumes**
- Compares running volume mounts vs quadlet Volume= lines
- Detects: Mount path changes, SELinux label changes
- Fix: Update quadlet volumes and restart

**5. Traefik Labels**
- Compares running labels vs quadlet Label= lines
- Detects: Routing changes, middleware changes, port changes
- Fix: Update quadlet labels and restart

### Status Interpretation

**MATCH:**
- All categories match
- No action needed
- Configuration is correct

**DRIFT:**
- One or more categories mismatch
- Restart required to reconcile
- Running container doesn't reflect quadlet

**WARNING:**
- Minor differences that don't affect functionality
- Examples: Network order (but correct networks), label formatting
- Informational only, may be intentional

---

## Workflows

### Workflow 1: Routine Audit (Weekly)

**Goal:** Proactively detect drift across all services

**Steps:**
```bash
cd .claude/skills/homelab-deployment

# 1. Check all services
./scripts/check-drift.sh > drift-report-$(date +%Y%m%d).txt

# 2. Review results
cat drift-report-*.txt | grep -E "(DRIFT|WARNING)"

# 3. Reconcile drifted services
for service in $(cat drift-report-*.txt | grep "DRIFT" | awk '{print $2}'); do
  echo "Reconciling: $service"
  systemctl --user restart $service.service
done

# 4. Verify reconciliation
./scripts/check-drift.sh
```

**Expected outcome:** All services showing MATCH

---

### Workflow 2: Post-Deployment Verification

**Goal:** Confirm deployment matches pattern

**Steps:**
```bash
# 1. Deploy service
./scripts/deploy-from-pattern.sh \
  --pattern media-server-stack \
  --service-name jellyfin \
  --memory 4G

# 2. Wait for service to start
systemctl --user status jellyfin.service

# 3. Check for drift
./scripts/check-drift.sh jellyfin

# 4. Investigate if drift detected
if [[ $? -ne 0 ]]; then
  ./scripts/check-drift.sh jellyfin --verbose
fi
```

**Expected outcome:** MATCH (no drift immediately after deployment)

**If drift detected:** Pattern may have bugs or customization required

---

### Workflow 3: Pre-Change Validation

**Goal:** Ensure clean state before making configuration changes

**Steps:**
```bash
# 1. Check current drift state
./scripts/check-drift.sh jellyfin

# 2. If drift exists, decide:
#    Option A: Reconcile first (restart service)
#    Option B: Accept drift, make additional changes

# 3. Make configuration changes
nano ~/.config/containers/systemd/jellyfin.container

# 4. Reload and restart
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 5. Verify changes applied
./scripts/check-drift.sh jellyfin
```

**Expected outcome:** MATCH after restart confirms changes applied

---

### Workflow 4: Investigating Drift

**Goal:** Understand why drift occurred

**Steps:**
```bash
# 1. Detect drift
./scripts/check-drift.sh jellyfin
# Output: DRIFT (memory mismatch)

# 2. Get detailed comparison
./scripts/check-drift.sh jellyfin --verbose

# Output shows:
#   Memory:
#     Quadlet: 4G (Memory=4G)
#     Running: 2G
#   Last modified: jellyfin.container (2025-11-14 10:30:00)

# 3. Check recent changes
git log --oneline -- ~/.config/containers/systemd/jellyfin.container

# 4. Determine cause
#    - Recent quadlet edit not followed by restart
#    - Manual podman update (podman update jellyfin --memory=2G)
#    - Quadlet modified but systemd not reloaded

# 5. Reconcile
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# 6. Verify fix
./scripts/check-drift.sh jellyfin
```

---

## Reconciliation Strategies

### Strategy 1: Restart Service (Standard)

**When to use:** Most drift scenarios

**How:**
```bash
# Restart to apply quadlet configuration
systemctl --user restart jellyfin.service

# Verify drift resolved
./scripts/check-drift.sh jellyfin
```

**Downtime:** Brief (5-30 seconds depending on service)

**Risk:** Low (systemd restarts service automatically)

---

### Strategy 2: Manual Container Update (Temporary Fix)

**When to use:** Urgent fix needed, can't restart service

**How:**
```bash
# Example: Update memory without restart
podman update jellyfin --memory 4G --memory-reservation 3G

# Note: Drift will reappear after next restart
# Update quadlet to match for permanent fix
```

**Downtime:** None

**Risk:** Medium (drift will persist until quadlet updated)

---

### Strategy 3: Batch Reconciliation (Multiple Services)

**When to use:** Weekly maintenance, after system changes

**How:**
```bash
# Check all services
./scripts/check-drift.sh > drift-report.txt

# Extract drifted services
DRIFTED=$(cat drift-report.txt | grep "DRIFT" | awk '{print $2}')

# Reconcile all at once
for service in $DRIFTED; do
  echo "Restarting: $service"
  systemctl --user restart $service.service
  sleep 5  # Allow time for restart
done

# Verify all reconciled
./scripts/check-drift.sh
```

**Downtime:** Sequential restarts (manageable)

**Risk:** Low (automated, systematic)

---

## Common Drift Scenarios

### Scenario 1: Image Update Without Quadlet Change

**Detection:**
```
Service: jellyfin
  ✗ Image: DRIFT
    Quadlet: jellyfin/jellyfin:latest
    Running: jellyfin/jellyfin:10.8.13
```

**Cause:** Image was pulled manually or auto-updated without updating quadlet

**Fix:**
```bash
# Option A: Update quadlet to match running
nano ~/.config/containers/systemd/jellyfin.container
# Change: Image=jellyfin/jellyfin:10.8.13

# Option B: Restart to pull latest
systemctl --user restart jellyfin.service
```

---

### Scenario 2: Memory Limit Changed in Quadlet

**Detection:**
```
Service: jellyfin
  ✗ Memory: DRIFT
    Quadlet: Memory=4G, MemoryHigh=3G
    Running: Memory=2G, MemoryHigh=1.5G
```

**Cause:** Quadlet edited but service not restarted

**Fix:**
```bash
# Restart to apply new limits
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# Verify new limits applied
podman inspect jellyfin | grep -i memory
```

---

### Scenario 3: Network Added to Quadlet

**Detection:**
```
Service: jellyfin
  ✗ Networks: DRIFT
    Quadlet: systemd-reverse_proxy, systemd-monitoring
    Running: systemd-reverse_proxy
```

**Cause:** Network line added to quadlet but not applied

**Fix:**
```bash
# Restart to join new network
systemctl --user restart jellyfin.service

# Verify network connection
podman inspect jellyfin | grep -i network
```

---

### Scenario 4: Traefik Labels Updated

**Detection:**
```
Service: jellyfin
  ✗ Labels: DRIFT
    Quadlet: traefik.http.routers.jellyfin.middlewares=crowdsec,auth
    Running: traefik.http.routers.jellyfin.middlewares=crowdsec
```

**Cause:** Middleware added to quadlet (e.g., enabling authentication)

**Fix:**
```bash
# Restart to apply new labels
systemctl --user daemon-reload
systemctl --user restart jellyfin.service

# Verify Traefik picked up changes
curl http://localhost:8080/api/http/routers/jellyfin@docker
```

---

## Automation

### Automated Weekly Drift Check

**Systemd timer for automatic drift detection:**

```bash
# Create timer unit
nano ~/.config/systemd/user/drift-check.timer

[Unit]
Description=Weekly Configuration Drift Check

[Timer]
OnCalendar=Sun 02:00
Persistent=true

[Install]
WantedBy=timers.target

# Create service unit
nano ~/.config/systemd/user/drift-check.service

[Unit]
Description=Check Configuration Drift

[Service]
Type=oneshot
ExecStart=/home/user/fedora-homelab-containers/.claude/skills/homelab-deployment/scripts/check-drift.sh --json --output /home/user/containers/data/reports/drift-%Y%m%d.json

# Enable timer
systemctl --user enable --now drift-check.timer
```

---

### Discord Notification on Drift

**Send alerts when drift detected:**

```bash
#!/bin/bash
# drift-notify.sh

WEBHOOK_URL="https://discord.com/api/webhooks/..."

# Run drift check
DRIFT_OUTPUT=$(./scripts/check-drift.sh)

# Check if any drift detected
if echo "$DRIFT_OUTPUT" | grep -q "DRIFT"; then
  # Extract drifted services
  SERVICES=$(echo "$DRIFT_OUTPUT" | grep "DRIFT" | awk '{print $2}' | tr '\n' ', ')

  # Send notification
  curl -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"⚠️ Configuration drift detected: $SERVICES\"}"
fi
```

---

## Troubleshooting

### Drift Persists After Restart

**Problem:** Service still shows drift after restarting

**Diagnosis:**
```bash
# 1. Verify systemd reloaded
systemctl --user daemon-reload

# 2. Check quadlet file syntax
systemctl --user cat jellyfin.service

# 3. Check for systemd errors
journalctl --user -u jellyfin.service -n 50

# 4. Verify quadlet parsed correctly
podman generate systemd --name jellyfin --files
diff ~/.config/containers/systemd/jellyfin.container /tmp/generated.container
```

**Common causes:**
- Syntax error in quadlet (systemd ignores line)
- SELinux label issue (`:Z` missing or incorrect)
- Network doesn't exist (quadlet specifies nonexistent network)

---

### False Positive Drift

**Problem:** Drift detected but configurations actually match

**Diagnosis:**
```bash
# Check verbose output for exact difference
./scripts/check-drift.sh jellyfin --verbose

# Common false positives:
# - Network order (different but both present)
# - Label formatting (whitespace differences)
# - Volume options order (same volumes, different sequence)
```

**Fix:** These are typically WARNING status, not DRIFT. Can ignore if functionality unaffected.

---

### Drift Check Script Fails

**Problem:** check-drift.sh exits with error

**Diagnosis:**
```bash
# Run with bash debug mode
bash -x ./scripts/check-drift.sh jellyfin

# Check for:
# - Service not found (quadlet doesn't exist)
# - Container not running (can't inspect)
# - Permission issues (can't read quadlet file)
```

**Fix:** Ensure service exists and is running before drift check

---

## Best Practices

### Weekly Routine Checks

- **Frequency:** Every Sunday at 2 AM (automated timer)
- **Review:** Monday morning review of drift report
- **Action:** Reconcile any drift found before new deployments

### Post-Deployment Verification

- **Always:** Check drift immediately after pattern deployment
- **Expected:** MATCH status (no drift)
- **If drift:** Investigate pattern bug or missing customization

### Before Major Changes

- **Clean slate:** Reconcile all drift before system upgrades
- **Baseline:** Document clean MATCH state
- **After change:** Verify drift status returns to MATCH

### Documentation

- **Log drift findings** in operational journal
- **Track patterns** - recurring drift indicates pattern issue
- **Update patterns** based on common drift scenarios

---

## Related Documentation

- **Pattern Selection:** `docs/10-services/guides/pattern-selection-guide.md`
- **Deployment Cookbook:** `.claude/skills/homelab-deployment/COOKBOOK.md` (Recipe 6)
- **Skill Documentation:** `.claude/skills/homelab-deployment/SKILL.md`
- **ADR-007:** `docs/20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md`
- **Architecture Guide:** `docs/20-operations/guides/homelab-architecture.md`

---

**Maintained by:** patriark + Claude Code
**Review frequency:** Quarterly
**Next review:** 2026-02-14
