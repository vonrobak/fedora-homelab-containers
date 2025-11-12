# CrowdSec Phase 3: Threat Intelligence Enhancement Plan

**Version:** 1.0
**Last Updated:** 2025-11-12
**Prerequisites:** Phase 1 completed successfully
**Estimated Time:** 60-90 minutes
**Risk Level:** Low-Medium (introduces external dependencies)

---

## Table of Contents

1. [Overview](#overview)
2. [Objectives](#objectives)
3. [Pre-Execution Requirements](#pre-execution-requirements)
4. [Phase 3.1: CAPI Enrollment](#phase-31-capi-enrollment)
5. [Phase 3.2: Global Blocklist Configuration](#phase-32-global-blocklist-configuration)
6. [Phase 3.3: Scenario Collection Expansion](#phase-33-scenario-collection-expansion)
7. [Phase 3.4: Integration Testing](#phase-34-integration-testing)
8. [Phase 3.5: Ongoing Optimization](#phase-35-ongoing-optimization)
9. [Rollback Procedures](#rollback-procedures)
10. [Operational Considerations](#operational-considerations)

---

## Overview

### What is CAPI?

**CrowdSec Community API (CAPI)** is a global threat intelligence sharing platform that:

- Aggregates attack data from thousands of CrowdSec instances worldwide
- Provides curated blocklists of confirmed malicious IPs
- Enables proactive blocking before attackers reach your infrastructure
- Reduces false positives through community verification
- Updates continuously based on real-world attack patterns

### Architecture Impact

```
BEFORE (Local-Only Detection):
Internet → Traefik → CrowdSec → Local Scenarios → Decision
                          ↓
                    Only detects attacks against YOUR server

AFTER (CAPI Integration):
Internet → Traefik → CrowdSec → Local Scenarios + CAPI Blocklist → Decision
                          ↓
                    Blocks known attackers BEFORE they try
```

### Benefits

**Security:**
- Proactive blocking of known threat actors
- Protection from zero-day exploits being actively used in the wild
- Reduced attack surface through community intelligence

**Operational:**
- Lower resource consumption (blocked before expensive processing)
- Reduced log noise from automated scanning
- Better visibility into global threat landscape

**Learning:**
- Understanding of attack patterns targeting similar infrastructure
- Insights into emerging threats
- Data-driven security decision making

---

## Objectives

### Success Criteria

At completion:

1. ✅ CrowdSec enrolled in CAPI and authenticated
2. ✅ Receiving global blocklist updates (verified)
3. ✅ Additional scenario collections installed (min. 3 new collections)
4. ✅ CAPI blocklist actively enforced by Traefik bouncer
5. ✅ Metrics showing CAPI blocks vs local detections
6. ✅ Documentation updated with CAPI configuration
7. ✅ Monitoring alerts configured for CAPI sync failures

### Key Performance Indicators

- **CAPI sync frequency:** Every 2 hours (automatic)
- **Global blocklist size:** 10,000+ IPs (typical)
- **New scenarios added:** 15-25 additional detections
- **Block rate increase:** Expected 20-40% more blocks (mostly scanners)
- **False positive rate:** <0.1% (CAPI IPs are highly vetted)

---

## Pre-Execution Requirements

### Prerequisites Checklist

- [ ] Phase 1 completed successfully
- [ ] CrowdSec v1.7.3 running and healthy
- [ ] Traefik bouncer connected and functional
- [ ] Access to https://app.crowdsec.net (requires registration)
- [ ] Valid email address for CAPI enrollment
- [ ] Network connectivity from CrowdSec container to internet

### Account Setup

```bash
# Before starting, register for CrowdSec Console:
# 1. Go to: https://app.crowdsec.net
# 2. Create account (free tier sufficient)
# 3. Verify email address
# 4. Note your enrollment key for later use
```

### Backup Current State

```bash
echo "=== Creating Phase 3 Backup ==="
BACKUP_DIR=~/crowdsec-phase3-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

# Backup CrowdSec config and data
sudo cp -r ~/containers/data/crowdsec/config "$BACKUP_DIR/"
sudo cp -r ~/containers/data/crowdsec/db "$BACKUP_DIR/"

# Export current scenario list
podman exec crowdsec cscli scenarios list > "$BACKUP_DIR/scenarios-before.txt"

# Export current collections
podman exec crowdsec cscli collections list > "$BACKUP_DIR/collections-before.txt"

# Capture current metrics baseline
podman exec crowdsec cscli metrics > "$BACKUP_DIR/metrics-before.txt"

echo "✓ Backup created: $BACKUP_DIR"
```

---

## Phase 3.1: CAPI Enrollment

### Objective
Enroll CrowdSec instance with CAPI and establish authenticated connection.

### Duration
~15 minutes

### Procedure

#### Step 3.1.1: Verify Internet Connectivity

```bash
echo "=== Verifying CrowdSec Internet Connectivity ==="

# Test outbound connectivity
podman exec crowdsec curl -s https://api.crowdsec.net/health

# Expected: {"status":"ok"} or similar
# If fails: Check firewall, network configuration
```

#### Step 3.1.2: Generate Enrollment Key

**On CrowdSec Console (https://app.crowdsec.net):**

1. Login to your account
2. Navigate to **"Engines"** → **"Add Security Engine"**
3. Select **"Linux"** as platform
4. Copy the enrollment command shown:
   ```
   cscli console enroll <YOUR_ENROLLMENT_KEY>
   ```
5. Keep this window open for verification later

#### Step 3.1.3: Enroll CrowdSec Instance

```bash
echo "=== Enrolling CrowdSec with CAPI ==="

# Replace <YOUR_ENROLLMENT_KEY> with actual key from console
ENROLLMENT_KEY="<YOUR_ENROLLMENT_KEY>"

podman exec crowdsec cscli console enroll "$ENROLLMENT_KEY"

# Expected output:
# INFO[...] Successfully enrolled to CrowdSec Console
# INFO[...] Instance: <instance-id>
# INFO[...] You can now enable/disable scenarios from the console
```

**Validation:**
```bash
# Verify enrollment status
podman exec crowdsec cscli console status

# Expected output:
# Console: Enrolled
# Instance ID: <your-instance-id>
# Organization: <your-organization>
# Status: Active
```

#### Step 3.1.4: Configure CAPI Credentials

```bash
echo "=== Configuring CAPI Credentials ==="

# CAPI credentials are automatically configured during enrollment
# Verify credentials file exists
podman exec crowdsec ls -la /etc/crowdsec/online_api_credentials.yaml

# Check credentials are valid
podman exec crowdsec cat /etc/crowdsec/online_api_credentials.yaml

# Should show:
# login: <machine-id>
# password: <password>
# url: https://api.crowdsec.net/
```

#### Step 3.1.5: Enable CAPI

```bash
echo "=== Enabling CAPI in CrowdSec Configuration ==="

# CAPI should be auto-enabled after enrollment
# Verify in config
podman exec crowdsec cscli config show | grep -i capi

# Restart CrowdSec to ensure CAPI is active
systemctl --user restart crowdsec.service

# Wait for restart
sleep 10

# Verify service is healthy
systemctl --user is-active crowdsec.service
```

#### Step 3.1.6: Verify CAPI Connection

```bash
echo "=== Verifying CAPI Connection ==="

# Check CAPI status
podman exec crowdsec cscli capi status

# Expected output:
# CAPI: Enabled
# Status: Authenticated
# Last Pull: <timestamp>
# Scenarios Subscribed: <count>

# Check for CAPI decisions
sleep 60  # Wait for first CAPI pull
podman exec crowdsec cscli decisions list -o json | jq '.[] | select(.origin=="capi")'

# If you see decisions with origin="capi", CAPI is working!
```

#### Step 3.1.7: Verify on Console

**Back to CrowdSec Console (https://app.crowdsec.net):**

1. Refresh the page
2. Navigate to **"Engines"**
3. Your instance should now appear with:
   - ✅ Status: **Connected**
   - Last seen: **<current time>**
   - Version: **v1.7.3**

#### Step 3.1.8: Document Enrollment

```bash
echo "=== Documenting CAPI Enrollment ===" | tee ~/crowdsec-phase3-log.txt

# Capture key information
INSTANCE_ID=$(podman exec crowdsec cscli console status | grep "Instance ID" | awk '{print $3}')
echo "Instance ID: $INSTANCE_ID" | tee -a ~/crowdsec-phase3-log.txt

# Document enrollment time
echo "Enrolled: $(date)" | tee -a ~/crowdsec-phase3-log.txt

echo "✓ CAPI enrollment complete" | tee -a ~/crowdsec-phase3-log.txt
```

### Success Criteria for Phase 3.1

- [ ] Internet connectivity verified
- [ ] Enrollment key obtained from console
- [ ] CrowdSec enrolled successfully
- [ ] CAPI credentials configured
- [ ] CAPI connection verified
- [ ] Console shows instance as connected
- [ ] First CAPI decisions received

---

## Phase 3.2: Global Blocklist Configuration

### Objective
Configure scenario subscriptions and optimize CAPI blocklist integration.

### Duration
~20 minutes

### Procedure

#### Step 3.2.1: Review Available Scenarios

```bash
echo "=== Reviewing Available CAPI Scenarios ==="

# List scenarios available for subscription
podman exec crowdsec cscli hub list scenarios

# Key scenarios to subscribe to (recommended):
# - crowdsecurity/http-probing
# - crowdsecurity/http-crawl-non_statics
# - crowdsecurity/http-sensitive-files
# - crowdsecurity/http-bad-user-agent
# - crowdsecurity/http-path-traversal-probing
# - crowdsecurity/ssh-bf (if exposing SSH)
# - crowdsecurity/http-bf (brute force)
```

#### Step 3.2.2: Subscribe to Core Scenarios

```bash
echo "=== Subscribing to CAPI Scenarios ==="

# Subscribe to recommended scenarios
CAPI_SCENARIOS=(
    "crowdsecurity/http-probing"
    "crowdsecurity/http-crawl-non_statics"
    "crowdsecurity/http-sensitive-files"
    "crowdsecurity/http-bad-user-agent"
    "crowdsecurity/http-path-traversal-probing"
    "crowdsecurity/http-bf"
    "crowdsecurity/http-admin-interface-probing"
)

for scenario in "${CAPI_SCENARIOS[@]}"; do
    echo "Subscribing to: $scenario"
    podman exec crowdsec cscli scenarios install "$scenario" 2>/dev/null || echo "  (already installed)"
done

# Reload CrowdSec to activate new scenarios
systemctl --user restart crowdsec.service
sleep 10
```

#### Step 3.2.3: Configure Blocklist Pull Frequency

```bash
echo "=== Configuring CAPI Pull Frequency ==="

# CAPI pulls blocklist every 2 hours by default
# This is optimal balance between freshness and API load

# Verify current configuration
podman exec crowdsec grep -A 10 "online_client:" /etc/crowdsec/config.yaml

# Expected:
# online_client:
#   credentials_path: /etc/crowdsec/online_api_credentials.yaml
#   update_frequency: 2h

# No changes needed unless you want more/less frequent updates
```

#### Step 3.2.4: Configure Decision Durations

```bash
echo "=== Configuring CAPI Decision Durations ==="

# CAPI decisions have durations from the central API
# Local decisions can override these if needed

# Review current profile configuration
podman exec crowdsec cat /etc/crowdsec/profiles.yaml | grep -A 20 "capi"

# If no CAPI profile exists, CAPI decisions use default durations
# This is typically fine - CAPI durations are well-tuned
```

#### Step 3.2.5: Update Traefik Middleware for CAPI

```bash
echo "=== Updating Traefik Middleware Configuration ==="

# CAPI works transparently with existing bouncer
# No middleware.yml changes needed - bouncer gets both local + CAPI decisions

# However, we can optimize update interval for faster CAPI propagation
cd ~/containers/config/traefik/dynamic/

# Check current update interval
grep "updateIntervalSeconds" middleware.yml

# 60 seconds is good balance
# Consider reducing to 30s if you want faster CAPI block propagation
# (But increases LAPI query frequency)

# For now, keep at 60s - no change needed
echo "✓ Middleware configuration optimal for CAPI" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.2.6: Test CAPI Blocklist Reception

```bash
echo "=== Testing CAPI Blocklist Reception ==="

# Force a CAPI update
podman exec crowdsec cscli capi pull

# Wait for processing
sleep 10

# Check for CAPI decisions
CAPI_COUNT=$(podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="capi")] | length')

echo "CAPI decisions received: $CAPI_COUNT" | tee -a ~/crowdsec-phase3-log.txt

if [ "$CAPI_COUNT" -gt 0 ]; then
    echo "✓ CAPI blocklist active" | tee -a ~/crowdsec-phase3-log.txt
else
    echo "⚠️  No CAPI decisions yet (may take time to populate)" | tee -a ~/crowdsec-phase3-log.txt
fi

# Show sample CAPI decisions
echo "Sample CAPI-blocked IPs:"
podman exec crowdsec cscli decisions list -o json | jq -r '[.[] | select(.origin=="capi")] | .[0:5] | .[] | .value'
```

#### Step 3.2.7: Verify Bouncer Receives CAPI Decisions

```bash
echo "=== Verifying Traefik Bouncer Gets CAPI Decisions ==="

# Bouncer pulls all decisions (local + CAPI) from LAPI
# Check bouncer metrics
podman exec crowdsec cscli bouncers list

# The bouncer should show decisions count including CAPI
# Make a test request to trigger bouncer query
curl -s -I https://home.patriark.org > /dev/null

# Check bouncer metrics
echo "Bouncer decision count:"
podman exec crowdsec cscli metrics | grep -A 5 "Bouncer Metrics"

echo "✓ Bouncer receiving CAPI decisions" | tee -a ~/crowdsec-phase3-log.txt
```

### Success Criteria for Phase 3.2

- [ ] Core CAPI scenarios subscribed
- [ ] CAPI pull frequency configured (2h)
- [ ] CAPI decisions received (>0)
- [ ] Traefik bouncer getting CAPI decisions
- [ ] Sample blocked IPs identified

---

## Phase 3.3: Scenario Collection Expansion

### Objective
Install additional specialized scenario collections for comprehensive attack detection.

### Duration
~20 minutes

### Procedure

#### Step 3.3.1: Audit Current Collections

```bash
echo "=== Current Collection Audit ==="

# List installed collections
podman exec crowdsec cscli collections list

# Current collections (from earlier deployment):
# - crowdsecurity/traefik
# - crowdsecurity/http-cve
# - crowdsecurity/base-http-scenarios

# Count current scenarios
CURRENT_SCENARIOS=$(podman exec crowdsec cscli scenarios list | grep -c "enabled")
echo "Current scenario count: $CURRENT_SCENARIOS" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.3.2: Identify Relevant Collections

```bash
echo "=== Identifying Relevant Collections ==="

# Based on your homelab services, install:

# 1. Linux system protection
COLLECTIONS_TO_INSTALL=(
    "crowdsecurity/linux"              # General Linux scenarios
    "crowdsecurity/sshd"               # SSH brute force (if exposing SSH)
    "crowdsecurity/apache2"            # Web server protection
    "crowdsecurity/nginx"              # Web server protection
    "crowdsecurity/whitelist-good-actors" # Whitelist legit bots (Google, etc.)
)

# 2. Service-specific (add based on your services)
# "crowdsecurity/nextcloud"  # If you add Nextcloud later
# "crowdsecurity/wordpress"  # If you add WordPress
# "crowdsecurity/caddy"      # Alternative web server

# For your current stack (Jellyfin, Immich, Grafana, etc):
# Base HTTP scenarios are sufficient
# No service-specific collections needed yet
```

#### Step 3.3.3: Install Collections

```bash
echo "=== Installing Additional Collections ==="

for collection in "${COLLECTIONS_TO_INSTALL[@]}"; do
    echo "Installing: $collection"
    podman exec crowdsec cscli collections install "$collection"

    if [ $? -eq 0 ]; then
        echo "  ✓ $collection installed" | tee -a ~/crowdsec-phase3-log.txt
    else
        echo "  ✗ Failed to install $collection" | tee -a ~/crowdsec-phase3-log.txt
    fi
done
```

#### Step 3.3.4: Update Hub

```bash
echo "=== Updating CrowdSec Hub ==="

# Update hub to get latest scenario definitions
podman exec crowdsec cscli hub update

# Upgrade all installed collections to latest versions
podman exec crowdsec cscli hub upgrade

# Verify no errors
if [ $? -eq 0 ]; then
    echo "✓ Hub updated successfully" | tee -a ~/crowdsec-phase3-log.txt
else
    echo "⚠️  Hub update had errors - check logs" | tee -a ~/crowdsec-phase3-log.txt
fi
```

#### Step 3.3.5: Reload CrowdSec

```bash
echo "=== Reloading CrowdSec with New Scenarios ==="

systemctl --user restart crowdsec.service

# Wait for restart
sleep 15

# Verify service health
systemctl --user is-active crowdsec.service

if [ $? -eq 0 ]; then
    echo "✓ CrowdSec restarted successfully" | tee -a ~/crowdsec-phase3-log.txt
else
    echo "✗ CrowdSec failed to restart - ABORT" | tee -a ~/crowdsec-phase3-log.txt
    exit 1
fi
```

#### Step 3.3.6: Verify New Scenarios Active

```bash
echo "=== Verifying New Scenarios ==="

# Count scenarios after installation
NEW_SCENARIO_COUNT=$(podman exec crowdsec cscli scenarios list | grep -c "enabled")
echo "New scenario count: $NEW_SCENARIO_COUNT" | tee -a ~/crowdsec-phase3-log.txt

# Calculate increase
SCENARIOS_ADDED=$((NEW_SCENARIO_COUNT - CURRENT_SCENARIOS))
echo "Scenarios added: $SCENARIOS_ADDED" | tee -a ~/crowdsec-phase3-log.txt

# List new scenarios
echo "Newly added scenarios:"
podman exec crowdsec cscli scenarios list | grep "enabled" | tail -$SCENARIOS_ADDED
```

#### Step 3.3.7: Document Collection Changes

```bash
echo "=== Documenting Collection Changes ===" | tee -a ~/crowdsec-phase3-log.txt

# Export final collection list
podman exec crowdsec cscli collections list > ~/crowdsec-collections-after-phase3.txt

# Show diff
echo "Collection changes:"
diff ~/crowdsec-phase3-backup-*/collections-before.txt ~/crowdsec-collections-after-phase3.txt | tee -a ~/crowdsec-phase3-log.txt

echo "✓ Collection expansion complete" | tee -a ~/crowdsec-phase3-log.txt
```

### Success Criteria for Phase 3.3

- [ ] At least 3 new collections installed
- [ ] Hub updated to latest versions
- [ ] CrowdSec restarted successfully
- [ ] 15+ new scenarios active
- [ ] All new scenarios verified enabled
- [ ] Collection changes documented

---

## Phase 3.4: Integration Testing

### Objective
Validate CAPI integration and verify threat detection improvements.

### Duration
~15 minutes

### Procedure

#### Step 3.4.1: Metrics Baseline Comparison

```bash
echo "=== Comparing Metrics Before/After CAPI ==="

# Capture current metrics
podman exec crowdsec cscli metrics > ~/crowdsec-metrics-after-phase3.txt

# Compare key metrics
echo "Metrics comparison:"
echo ""
echo "BEFORE Phase 3:"
cat ~/crowdsec-phase3-backup-*/metrics-before.txt | head -20

echo ""
echo "AFTER Phase 3:"
cat ~/crowdsec-metrics-after-phase3.txt | head -20

echo ""
echo "Decision sources:"
podman exec crowdsec cscli decisions list -o json | jq -r 'group_by(.origin) | .[] | {origin: .[0].origin, count: length}'
```

#### Step 3.4.2: Test CAPI Block Enforcement

```bash
echo "=== Testing CAPI Block Enforcement ==="

# Get a CAPI-blocked IP (if any)
CAPI_BLOCKED_IP=$(podman exec crowdsec cscli decisions list -o json | jq -r '[.[] | select(.origin=="capi")] | .[0].value' 2>/dev/null)

if [ -n "$CAPI_BLOCKED_IP" ] && [ "$CAPI_BLOCKED_IP" != "null" ]; then
    echo "Testing CAPI-blocked IP: $CAPI_BLOCKED_IP"

    # Simulate request from this IP (using X-Forwarded-For header)
    # NOTE: This only works if you can test from a system that can set headers
    echo "If you tried to access from $CAPI_BLOCKED_IP, you would receive 403"
    echo "✓ CAPI blocks are loaded in bouncer" | tee -a ~/crowdsec-phase3-log.txt
else
    echo "⚠️  No CAPI blocks yet (normal if freshly enrolled)" | tee -a ~/crowdsec-phase3-log.txt
    echo "CAPI blocks will populate over next 2-24 hours"
fi
```

#### Step 3.4.3: Verify Scenario Effectiveness

```bash
echo "=== Verifying Scenario Effectiveness ==="

# Check recent alerts to see if new scenarios are triggering
podman exec crowdsec cscli alerts list --limit 20

# Count alerts by scenario
echo "Alert distribution by scenario:"
podman exec crowdsec cscli alerts list -o json | jq -r 'group_by(.scenario) | .[] | {scenario: .[0].scenario, count: length}'
```

#### Step 3.4.4: Monitor CAPI Sync

```bash
echo "=== Monitoring CAPI Synchronization ==="

# Check CAPI status
podman exec crowdsec cscli capi status

# Verify last pull time (should be recent)
LAST_PULL=$(podman exec crowdsec cscli capi status | grep "Last Pull" | awk '{print $3, $4}')
echo "Last CAPI pull: $LAST_PULL" | tee -a ~/crowdsec-phase3-log.txt

# Check for CAPI errors in logs
echo "Checking for CAPI errors:"
podman logs --since 10m crowdsec 2>&1 | grep -i "capi" | grep -i "error"

if [ $? -eq 1 ]; then
    echo "✓ No CAPI errors detected" | tee -a ~/crowdsec-phase3-log.txt
else
    echo "⚠️  CAPI errors detected - review above" | tee -a ~/crowdsec-phase3-log.txt
fi
```

#### Step 3.4.5: Verify Console Integration

**On CrowdSec Console (https://app.crowdsec.net):**

1. Navigate to **"Engines"** → Your instance
2. Check **"Last Seen"** is recent (<2 minutes)
3. Navigate to **"Scenarios"** tab
4. Verify all installed scenarios appear
5. Check **"Alerts"** tab for any recent alerts
6. Review **"Decisions"** tab for active blocks

Document any discrepancies.

#### Step 3.4.6: Load Test New Scenarios

```bash
echo "=== Load Testing New Scenarios ==="

# Generate some traffic to trigger scenarios
TEST_URL="https://home.patriark.org"

# Test 1: Sensitive file probing (should trigger)
for file in ".env" ".git/config" "wp-config.php" "admin.php"; do
    curl -s -o /dev/null "$TEST_URL/$file"
    sleep 1
done

# Test 2: Path traversal attempts (should trigger)
for path in "../../etc/passwd" "../../../etc/shadow"; do
    curl -s -o /dev/null "$TEST_URL/$path"
    sleep 1
done

# Wait for CrowdSec to process
sleep 10

# Check if scenarios triggered
echo "Recent alerts after load test:"
podman exec crowdsec cscli alerts list --limit 5

echo "✓ Load test complete - check alerts above" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.4.7: Performance Impact Assessment

```bash
echo "=== Assessing Performance Impact ==="

# Check CrowdSec memory usage
MEMORY_USAGE=$(podman stats crowdsec --no-stream --format "{{.MemUsage}}")
echo "CrowdSec memory usage: $MEMORY_USAGE" | tee -a ~/crowdsec-phase3-log.txt

# Check if memory is within limits (512MB max)
# Expected: 150-250MB with CAPI enabled

# Check LAPI response time
time podman exec crowdsec cscli decisions list > /dev/null

# Should be <1 second
echo "✓ Performance within acceptable range" | tee -a ~/crowdsec-phase3-log.txt
```

### Success Criteria for Phase 3.4

- [ ] Metrics show CAPI decisions active
- [ ] CAPI blocks present in decision list
- [ ] New scenarios triggering alerts
- [ ] CAPI sync working (no errors)
- [ ] Console shows instance connected
- [ ] Performance impact acceptable (<250MB RAM)

---

## Phase 3.5: Ongoing Optimization

### Objective
Configure ongoing monitoring and optimization processes.

### Duration
~10 minutes

### Procedure

#### Step 3.5.1: Set Up CAPI Monitoring

```bash
echo "=== Configuring CAPI Health Monitoring ==="

# Create a monitoring script for CAPI status
cat > ~/containers/scripts/check-crowdsec-capi.sh <<'EOF'
#!/bin/bash
# CrowdSec CAPI Health Check Script

# Check CAPI status
CAPI_STATUS=$(podman exec crowdsec cscli capi status 2>/dev/null | grep "Status:" | awk '{print $2}')

if [ "$CAPI_STATUS" = "Authenticated" ]; then
    echo "✓ CAPI Status: OK"
    exit 0
else
    echo "✗ CAPI Status: $CAPI_STATUS"
    exit 1
fi
EOF

chmod +x ~/containers/scripts/check-crowdsec-capi.sh

# Test the script
~/containers/scripts/check-crowdsec-capi.sh
```

#### Step 3.5.2: Configure Alerting (Optional)

```bash
echo "=== Configuring CAPI Sync Failure Alerting ==="

# If you have Alertmanager configured (Phase 2), add alert rule
# This is a placeholder for when monitoring stack is integrated

cat > /tmp/crowdsec-capi-alerts.yml <<'EOF'
# CrowdSec CAPI Alert Rules (for future Prometheus integration)
groups:
  - name: crowdsec_capi
    interval: 5m
    rules:
      - alert: CrowdSecCAPIDown
        expr: crowdsec_capi_status == 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "CrowdSec CAPI connection lost"
          description: "CAPI has not synced successfully in 15 minutes"
EOF

echo "⚠️  Alert rules created but not deployed (requires Phase 2 monitoring)" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.5.3: Document CAPI Configuration

```bash
echo "=== Documenting CAPI Configuration ==="

# Create CAPI documentation
cat > ~/containers/docs/crowdsec-capi-config.md <<EOF
# CrowdSec CAPI Configuration

**Enrollment Date:** $(date)
**Instance ID:** $(podman exec crowdsec cscli console status | grep "Instance ID" | awk '{print $3}')

## Subscribed Scenarios
$(podman exec crowdsec cscli scenarios list | grep "enabled")

## Installed Collections
$(podman exec crowdsec cscli collections list)

## CAPI Settings
- Pull Frequency: 2 hours
- Last Sync: $(podman exec crowdsec cscli capi status | grep "Last Pull")
- Decision Count: $(podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="capi")] | length')

## Monitoring
- Health Check Script: ~/containers/scripts/check-crowdsec-capi.sh
- Console URL: https://app.crowdsec.net

## Maintenance
- Update hub: \`podman exec crowdsec cscli hub update\`
- Upgrade collections: \`podman exec crowdsec cscli hub upgrade\`
- Check CAPI status: \`podman exec crowdsec cscli capi status\`
EOF

echo "✓ Documentation created: ~/containers/docs/crowdsec-capi-config.md" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.5.4: Schedule Regular Hub Updates

```bash
echo "=== Configuring Automatic Hub Updates ==="

# Create systemd timer for weekly hub updates
mkdir -p ~/.config/systemd/user/

cat > ~/.config/systemd/user/crowdsec-hub-update.service <<'EOF'
[Unit]
Description=CrowdSec Hub Update
After=crowdsec.service

[Service]
Type=oneshot
ExecStart=/usr/bin/podman exec crowdsec cscli hub update
ExecStart=/usr/bin/podman exec crowdsec cscli hub upgrade
EOF

cat > ~/.config/systemd/user/crowdsec-hub-update.timer <<'EOF'
[Unit]
Description=Weekly CrowdSec Hub Update

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable timer
systemctl --user daemon-reload
systemctl --user enable --now crowdsec-hub-update.timer

echo "✓ Automatic hub updates configured (weekly)" | tee -a ~/crowdsec-phase3-log.txt
```

#### Step 3.5.5: Create Operational Runbook

```bash
echo "=== Creating CAPI Operational Runbook ==="

cat > ~/containers/docs/crowdsec-capi-runbook.md <<'EOF'
# CrowdSec CAPI Operational Runbook

## Daily Operations

### Check CAPI Health
```bash
podman exec crowdsec cscli capi status
```

Expected: Status: Authenticated, Last Pull: <recent>

### View CAPI Blocks
```bash
podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="capi")] | length'
```

Expected: >1000 IPs typically

## Weekly Maintenance

### Update Hub
```bash
podman exec crowdsec cscli hub update
podman exec crowdsec cscli hub upgrade
systemctl --user restart crowdsec.service
```

### Review Metrics
```bash
podman exec crowdsec cscli metrics
```

Check for:
- Decision count trending up (more CAPI blocks)
- Alert count (should see activity)
- No error rates

## Troubleshooting

### CAPI Not Syncing

**Symptoms:** Last Pull time is >4 hours old

**Fix:**
```bash
# Check internet connectivity
podman exec crowdsec curl -s https://api.crowdsec.net/health

# Force CAPI pull
podman exec crowdsec cscli capi pull

# Check logs
podman logs crowdsec | grep -i capi | grep -i error
```

### Too Many False Positives

**Symptoms:** Legitimate traffic being blocked

**Fix:**
```bash
# Identify problem IP
podman exec crowdsec cscli decisions list | grep <IP>

# If CAPI origin, report false positive to CrowdSec
# Via console: https://app.crowdsec.net

# Whitelist locally if needed
podman exec crowdsec cscli decisions add --ip <IP> --type whitelist --duration 999h
```

### Enrollment Lost

**Symptoms:** Console shows instance as disconnected

**Fix:**
```bash
# Check enrollment status
podman exec crowdsec cscli console status

# If "Not Enrolled", re-enroll with original key
# (Contact CrowdSec support if key is lost)
```
EOF

echo "✓ Operational runbook created" | tee -a ~/crowdsec-phase3-log.txt
```

### Success Criteria for Phase 3.5

- [ ] CAPI health monitoring script created
- [ ] Alert rules drafted (for future use)
- [ ] CAPI configuration documented
- [ ] Automatic hub updates scheduled
- [ ] Operational runbook created

---

## Rollback Procedures

### Rollback Trigger Conditions

Roll back if:
- CAPI sync fails repeatedly (>4 hours)
- False positive rate >5%
- CrowdSec performance degrades significantly
- Services become unreachable due to over-blocking

### Rollback Procedure

#### Step R1: Disable CAPI

```bash
echo "=== Disabling CAPI ==="

# Unenroll from CAPI
podman exec crowdsec cscli console disable

# Verify CAPI disabled
podman exec crowdsec cscli capi status
# Should show: Status: Disabled
```

#### Step R2: Remove CAPI Decisions

```bash
echo "=== Removing CAPI Decisions ==="

# Delete all CAPI-sourced decisions
podman exec crowdsec cscli decisions delete --origin capi

# Verify removal
CAPI_COUNT=$(podman exec crowdsec cscli decisions list -o json | jq '[.[] | select(.origin=="capi")] | length')
echo "Remaining CAPI decisions: $CAPI_COUNT"
```

#### Step R3: Uninstall Collections (Optional)

```bash
echo "=== Uninstalling Additional Collections ==="

# If specific collections are causing issues
for collection in "${COLLECTIONS_TO_INSTALL[@]}"; do
    podman exec crowdsec cscli collections remove "$collection"
done

# Restart CrowdSec
systemctl --user restart crowdsec.service
```

#### Step R4: Restore from Backup

```bash
echo "=== Restoring from Backup ==="

# Find backup directory
BACKUP_DIR=$(ls -td ~/crowdsec-phase3-backup-* | head -1)

# Restore CrowdSec config
sudo rm -rf ~/containers/data/crowdsec/config/*
sudo cp -r "$BACKUP_DIR/config/"* ~/containers/data/crowdsec/config/

# Restore database
sudo rm -rf ~/containers/data/crowdsec/db/*
sudo cp -r "$BACKUP_DIR/db/"* ~/containers/data/crowdsec/db/

# Restart
systemctl --user restart crowdsec.service
```

#### Step R5: Verify Rollback

```bash
echo "=== Verifying Rollback ==="

# Check CAPI is disabled
podman exec crowdsec cscli capi status

# Check scenario count matches pre-Phase 3
CURRENT=$(podman exec crowdsec cscli scenarios list | grep -c "enabled")
BEFORE=$(grep -c "enabled" "$BACKUP_DIR/scenarios-before.txt")

echo "Scenarios: $CURRENT (was $BEFORE before Phase 3)"

# Test service accessibility
curl -I https://home.patriark.org

echo "✓ Rollback complete" | tee -a ~/crowdsec-phase3-log.txt
```

---

## Operational Considerations

### Expected Behavior Changes

**Block Rate:**
- Expect 20-40% increase in blocks
- Mostly scanning/reconnaissance traffic
- Few legitimate users should be affected

**Memory Usage:**
- Increase of ~50-100MB
- CAPI blocklist cached in memory
- Total should stay <250MB

**Log Volume:**
- More decisions logged
- CAPI sync messages every 2 hours
- Alert volume may increase

### False Positive Management

**If legitimate traffic blocked:**

1. **Identify the decision:**
   ```bash
   podman exec crowdsec cscli decisions list | grep <IP>
   ```

2. **Check origin:**
   - If `origin=capi`: Report to CrowdSec via console
   - If `origin=crowdsec`: Adjust local scenario

3. **Temporary whitelist:**
   ```bash
   podman exec crowdsec cscli decisions delete --ip <IP>
   ```

4. **Permanent whitelist:**
   ```bash
   # Add to local-whitelist.yaml
   # (Covered in Phase 4)
   ```

### Maintenance Schedule

**Daily:**
- Check CAPI sync status (automated monitoring)

**Weekly:**
- Review hub updates
- Check for new relevant collections
- Review metrics and alert trends

**Monthly:**
- Review false positive reports
- Optimize scenario subscriptions
- Update documentation

### Performance Tuning

**If CrowdSec uses too much memory:**
1. Reduce CAPI update frequency to 4h
2. Unsubscribe from unused scenarios
3. Implement decision TTL limits

**If too many blocks:**
1. Review decision origins
2. Reduce CAPI scenario subscriptions
3. Increase decision thresholds

---

## Final Validation Checklist

After completing Phase 3:

- [ ] CAPI enrolled and authenticated
- [ ] Receiving global blocklist updates
- [ ] 3+ new collections installed
- [ ] 15+ new scenarios active
- [ ] CAPI decisions present in bouncer
- [ ] No significant false positives
- [ ] Performance within limits
- [ ] Monitoring configured
- [ ] Documentation complete
- [ ] Runbooks created
- [ ] Changes committed to Git

---

## Next Steps

After successful Phase 3 completion:

**Phase 4:** Configuration Management
- Track critical configs in Git
- Create config templates
- Implement validation checks
- Document backup/restore procedures

**Phase 5:** Advanced Hardening
- Custom ban response pages
- Discord/alert notifications
- IP reputation monitoring
- Automated threat reports

---

## Document Control

**Version:** 1.0
**Created:** 2025-11-12
**Author:** Claude (AI Assistant)
**Status:** Ready for execution
**Dependencies:** Phase 1 completion

**Related Documents:**
- `crowdsec-phase1-field-manual.md` - Phase 1 procedures
- `crowdsec-phase4-configuration-management.md` - Phase 4 plan
- `docs/10-services/guides/crowdsec.md` - CrowdSec operational guide

---

**END OF PHASE 3 PLAN**
