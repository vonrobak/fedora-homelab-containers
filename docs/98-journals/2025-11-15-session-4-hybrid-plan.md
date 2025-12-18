# Session 4: Context Framework + Auto-Remediation (Hybrid Plan)

**Date:** 2025-11-15 (Planning)
**Approach:** Hybrid (70% Context Framework + 30% Auto-Remediation)
**Target Level:** Level 2 Automation (Intelligent Semi-Autonomous)
**Estimated Duration:** 6-8 hours (2-3 CLI sessions)

---

## Executive Summary

Session 4 will create a **persistent system context layer** that makes Claude Skills deeply aware of your specific homelab environment, history, and patterns. Combined with **intelligent auto-remediation** for common issues, this transforms Claude from a helpful assistant into a **system-aware copilot** that learns from your homelab's behavior.

**Key Deliverables:**
1. **Context Framework** - Persistent system knowledge base
2. **Historical Issue Tracker** - Remember past problems and solutions
3. **Deployment Memory** - Learn from deployment patterns
4. **Auto-Remediation Engine** - Fix common issues automatically
5. **Enhanced Skill Integration** - All skills use context

**Impact:**
- Claude remembers your specific system state and history
- Recommendations based on **your actual data**, not generic advice
- Automatic fixes for recurring issues (disk cleanup, drift reconciliation)
- Foundation for future autonomous capabilities

---

## Architecture Overview

### Context Framework Structure

```
.claude/
├── context/                           # NEW: System context layer
│   ├── system-profile.json           # Hardware, networks, service inventory
│   ├── issue-history.json            # Past problems + resolutions
│   ├── deployment-log.json           # What was deployed when
│   ├── preferences.yml               # User preferences, risk tolerance
│   └── service-relationships.json    # Dependencies, networks, patterns
│
├── remediation/                       # NEW: Auto-remediation playbooks
│   ├── playbooks/
│   │   ├── disk-cleanup.yml          # Automated disk space recovery
│   │   ├── drift-reconciliation.yml  # Auto-fix config drift
│   │   ├── service-restart.yml       # Smart service recovery
│   │   └── resource-pressure.yml     # Handle memory/CPU pressure
│   ├── scripts/
│   │   ├── apply-remediation.sh      # Execute remediation playbook
│   │   └── log-remediation.sh        # Log automated actions
│   └── README.md                      # Remediation framework guide
│
└── skills/
    ├── homelab-intelligence/          # ENHANCED: Context-aware
    │   └── use-context.sh            # Context query helper
    ├── homelab-deployment/            # ENHANCED: Deployment memory
    │   └── learn-from-deployment.sh  # Update deployment log
    └── skill-integration-guide.md     # UPDATED: Context usage
```

### Data Flow

```
1. Context Collection (Passive)
   ├─ homelab-intel.sh runs → Updates system-profile.json
   ├─ Deployment completes → Updates deployment-log.json
   ├─ Issue resolved → Updates issue-history.json
   └─ User preferences expressed → Updates preferences.yml

2. Context Usage (Active)
   ├─ homelab-intelligence invoked → Queries issue-history.json
   │                                  "Last time disk was high..."
   ├─ homelab-deployment invoked → Queries deployment-log.json
   │                                "Based on your Redis pattern..."
   └─ Auto-remediation triggered → Queries playbooks
                                    "This matches disk-cleanup pattern"

3. Learning Loop
   └─ Every interaction updates context → Better recommendations next time
```

---

## Phase 1: Context Framework (4-5 hours)

### 1.1 System Profile Generation

**Objective:** Create persistent snapshot of your homelab's identity

**Files to Create:**
- `.claude/context/system-profile.json`
- `.claude/context/scripts/generate-system-profile.sh`
- `.claude/context/scripts/update-system-profile.sh`

**Data to Capture:**
```json
{
  "generated_at": "2025-11-15T10:00:00Z",
  "system": {
    "hostname": "fedora-htpc",
    "os": "Fedora 42",
    "kernel": "6.17.6",
    "selinux": "enforcing",
    "hardware": {
      "cpu_cores": 16,
      "memory_gb": 32,
      "system_disk_gb": 128,
      "storage_pools": ["btrfs-pool: 13TB"]
    }
  },
  "networks": {
    "systemd-reverse_proxy": {
      "subnet": "10.89.2.0/24",
      "purpose": "Public-facing services",
      "services": ["traefik", "jellyfin", "authelia"]
    },
    "systemd-monitoring": {
      "subnet": "10.89.X.0/24",
      "purpose": "Observability stack",
      "services": ["prometheus", "grafana", "loki"]
    }
    // ... other networks
  },
  "services": {
    "traefik": {
      "image": "docker.io/library/traefik:v3.2",
      "networks": ["systemd-reverse_proxy", "systemd-auth_services", "systemd-monitoring"],
      "role": "reverse-proxy",
      "criticality": "critical",
      "health_check": "http://localhost:8080/ping"
    }
    // ... other services (auto-populated from podman ps)
  },
  "thresholds": {
    "disk_warning_percent": 70,
    "disk_critical_percent": 80,
    "memory_warning_percent": 85,
    "swap_critical_mb": 7000
  }
}
```

**Generation Script:**
```bash
#!/bin/bash
# .claude/context/scripts/generate-system-profile.sh

set -euo pipefail

CONTEXT_DIR=".claude/context"
OUTPUT_FILE="$CONTEXT_DIR/system-profile.json"

# Gather system info
hostname=$(hostname)
os_version=$(grep ^NAME= /etc/os-release | cut -d= -f2 | tr -d '"')
kernel=$(uname -r)
selinux=$(getenforce | tr '[:upper:]' '[:lower:]')

# Gather hardware info
cpu_cores=$(nproc)
memory_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

# Gather network info (from podman network ls + inspect)
# Gather service inventory (from podman ps + quadlets)
# Generate JSON output

# TODO: Implementation details in CLI session
```

**Acceptance Criteria:**
- [ ] `generate-system-profile.sh` creates valid JSON
- [ ] Contains all 20 running services
- [ ] Contains all 5 networks with subnets
- [ ] Hardware specs accurate
- [ ] Can be regenerated to update (idempotent)

---

### 1.2 Issue History Tracker

**Objective:** Remember past problems and their solutions

**Files to Create:**
- `.claude/context/issue-history.json`
- `.claude/context/scripts/add-issue.sh`
- `.claude/context/scripts/query-issues.sh`

**Data Structure:**
```json
{
  "issues": [
    {
      "id": "ISS-001",
      "date": "2025-11-12",
      "severity": "critical",
      "category": "service-crash",
      "title": "CrowdSec crash-loop due to invalid profiles.yaml",
      "description": "CrowdSec restarted 3900+ times over 5 hours",
      "root_cause": "Invalid syntax in profiles.yaml: any(Alert.Events) not supported",
      "solution": "Rewrote profiles.yaml with Alert.GetScenario() syntax",
      "resolution_time_minutes": 45,
      "affected_services": ["crowdsec", "traefik-bouncer"],
      "related_files": [
        "~/containers/config/crowdsec/profiles.yaml"
      ],
      "prevention": "Add YAML syntax validation to deployment script",
      "recurrence_risk": "low",
      "related_adr": "ADR-006"
    },
    {
      "id": "ISS-002",
      "date": "2025-11-12",
      "severity": "warning",
      "category": "disk-space",
      "title": "System disk at 78% capacity",
      "description": "System SSD usage approaching 80% threshold",
      "root_cause": "Container image accumulation + journal logs",
      "solution": "podman system prune -af + journalctl --vacuum-time=7d",
      "resolution_time_minutes": 15,
      "space_freed_gb": 12,
      "prevention": "Schedule weekly cleanup via systemd timer",
      "recurrence_risk": "high"
    }
  ]
}
```

**Population Script:**
```bash
#!/bin/bash
# .claude/context/scripts/populate-issue-history.sh

# Parse docs/99-reports/*.md for past issues
# Look for patterns: "Root cause:", "Fix:", "Issue:"
# Generate issue-history.json from historical data

# Example: Parse 2025-11-12-system-intelligence-report.md
# Extract: CrowdSec issue, disk space warning, etc.
```

**Acceptance Criteria:**
- [ ] Script parses existing reports in `docs/99-reports/*.md`
- [ ] Extracts at least 10 historical issues
- [ ] JSON schema validates
- [ ] `query-issues.sh` can search by category/date/service
- [ ] New issues can be added via `add-issue.sh`

---

### 1.3 Deployment Memory Log

**Objective:** Learn from deployment patterns and outcomes

**Files to Create:**
- `.claude/context/deployment-log.json`
- `.claude/skills/homelab-deployment/scripts/record-deployment.sh`

**Data Structure:**
```json
{
  "deployments": [
    {
      "id": "DEP-001",
      "date": "2025-11-09",
      "service_name": "immich",
      "pattern_used": "document-management",
      "image": "ghcr.io/immich-app/immich-server:latest",
      "deployment_method": "manual",
      "duration_minutes": 45,
      "success": true,
      "issues_encountered": [
        "ML service required privileged mode for GPU",
        "Redis persistence needed for production use"
      ],
      "configurations_applied": {
        "memory_limit": "4G",
        "networks": ["systemd-reverse_proxy", "systemd-photos"],
        "volumes": [
          "~/containers/config/immich:/config:Z",
          "/mnt/btrfs-pool/subvol4-immich-data:/data:Z"
        ]
      },
      "lessons_learned": [
        "Always enable Redis AOF persistence for Immich",
        "ML container needs --privileged for GPU access"
      ],
      "related_commits": ["a758a97", "5530453"]
    }
  ]
}
```

**Integration Point:**
```bash
# In .claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh
# Add at end of successful deployment:

if [[ $? -eq 0 ]]; then
    # Record deployment to memory log
    ./.claude/context/scripts/record-deployment.sh \
        --service "$SERVICE_NAME" \
        --pattern "$PATTERN" \
        --image "$IMAGE" \
        --status "success" \
        --duration "$((END_TIME - START_TIME))"
fi
```

**Acceptance Criteria:**
- [ ] Deployment log populated from git history (last 189 commits)
- [ ] At least 15 deployments recorded
- [ ] Integration with deploy-from-pattern.sh working
- [ ] Can query: "How did we deploy Redis last time?"
- [ ] Lessons learned captured for future deployments

---

### 1.4 Enhanced Skill Integration

**Objective:** All skills use context proactively

**Files to Modify:**
- `.claude/skills/homelab-intelligence/SKILL.md`
- `.claude/skills/homelab-deployment/SKILL.md`
- `.claude/skills/skill-integration-guide.md`

**New Context-Aware Behaviors:**

**homelab-intelligence:**
```markdown
### Step 2.5: Check Issue History (NEW)

After analyzing current health, query issue-history.json:

```bash
./.claude/context/scripts/query-issues.sh \
    --category "disk-space" \
    --recurrence-risk "high" \
    --lookback-days 30
```

If current disk usage matches past issue pattern:
- Reference ISS-002 from 2025-11-12
- Say: "Last time disk was at 78%, we freed 12GB with..."
- Provide the exact solution that worked before
```

**homelab-deployment:**
```markdown
### Phase 1.5: Check Deployment History (NEW)

Before deploying, query deployment-log.json:

```bash
./.claude/context/scripts/query-deployments.sh \
    --service "redis" \
    --pattern "cache-service"
```

If similar deployment exists:
- Reference DEP-XXX
- Say: "Based on your Redis deployment from 2025-11-10..."
- Auto-populate memory limits, persistence settings from past success
- Warn about issues encountered previously
```

**Acceptance Criteria:**
- [ ] homelab-intelligence references issue history
- [ ] homelab-deployment uses deployment memory
- [ ] skill-integration-guide documents context usage
- [ ] Example interactions demonstrate context awareness

---

## Phase 2: Auto-Remediation (2-3 hours)

### 2.1 Remediation Playbook Framework

**Objective:** Define structured playbooks for common fixes

**Files to Create:**
- `.claude/remediation/playbooks/disk-cleanup.yml`
- `.claude/remediation/playbooks/drift-reconciliation.yml`
- `.claude/remediation/playbooks/service-restart.yml`
- `.claude/remediation/scripts/apply-remediation.sh`

**Playbook Example (disk-cleanup.yml):**
```yaml
name: disk-cleanup
version: 1.0
description: Automated disk space recovery when system disk exceeds threshold
category: resource-management
severity: warning
risk_level: low

triggers:
  - condition: "system_disk_usage_percent > 75"
    source: "homelab-intel.sh health score"
  - condition: "manual invocation"
    source: "user request"

prerequisites:
  - name: "Backup important data"
    check: "last_backup_age_days < 7"
    action: "warn_user"
  - name: "No critical services deploying"
    check: "no active deployments"
    action: "block_if_deploying"

steps:
  - name: "Check container image usage"
    command: "podman system df"
    parse_output: true
    decide: |
      if unused_images > 5GB:
        proceed_to_next_step
      else:
        skip_to_step: "check_journal_size"

  - name: "Prune unused images"
    command: "podman system prune -af --volumes"
    confirmation_required: false  # Safe operation
    expected_space_freed_gb: 5-15
    rollback: "none"  # Cannot rollback image pruning
    log_action: true

  - name: "Check journal size"
    command: "journalctl --user --disk-usage"
    parse_output: true
    decide: |
      if journal_size_gb > 2:
        proceed_to_next_step
      else:
        skip_to_step: "verify_results"

  - name: "Rotate journal logs"
    command: "journalctl --user --vacuum-time=7d"
    confirmation_required: false
    expected_space_freed_gb: 1-5
    log_action: true

  - name: "Verify results"
    command: "df -h / | awk 'NR==2 {print $5}'"
    success_criteria: "disk_usage_percent < 70"
    on_success: "log_success_and_exit"
    on_failure: "escalate_to_user"

post_actions:
  - name: "Record remediation"
    action: "log_to_issue_history"
    data:
      category: "disk-space"
      automated: true
      space_freed_gb: "${SPACE_FREED}"
  - name: "Update system profile"
    action: "refresh_system_profile"

escalation:
  condition: "space_freed_gb < 5 OR disk_usage_percent > 70"
  message: |
    Automated cleanup only freed ${SPACE_FREED}GB. Manual investigation needed.
    Recommend checking:
    1. Large files in ~/containers/data/
    2. BTRFS snapshot accumulation
    3. Backup logs in ~/containers/data/backup-logs/
```

**Acceptance Criteria:**
- [ ] 4 playbooks created (disk-cleanup, drift-reconciliation, service-restart, resource-pressure)
- [ ] Each playbook has clear triggers, steps, rollback plans
- [ ] Risk levels assigned (low/medium/high)
- [ ] User confirmation required for high-risk operations

---

### 2.2 Remediation Execution Engine

**Objective:** Execute playbooks safely with logging and rollback

**Files to Create:**
- `.claude/remediation/scripts/apply-remediation.sh`
- `.claude/remediation/scripts/parse-playbook.sh`
- `.claude/remediation/scripts/log-remediation.sh`

**Execution Script:**
```bash
#!/bin/bash
# .claude/remediation/scripts/apply-remediation.sh

set -euo pipefail

PLAYBOOK=""
DRY_RUN=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --playbook) PLAYBOOK="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Load playbook
PLAYBOOK_FILE=".claude/remediation/playbooks/${PLAYBOOK}.yml"
if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo "ERROR: Playbook not found: $PLAYBOOK_FILE"
    exit 1
fi

# Parse YAML (using yq or custom parser)
# Check prerequisites
# Execute steps sequentially
# Log all actions to remediation-log.json
# On failure, execute rollback if defined

# Example execution:
echo "Executing playbook: $PLAYBOOK"
echo "Dry run: $DRY_RUN"

# Step execution loop
for step in "${STEPS[@]}"; do
    echo "Running step: ${step[name]}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would execute: ${step[command]}"
    else
        eval "${step[command]}"
        log_remediation_action "$PLAYBOOK" "${step[name]}" "$?"
    fi
done

echo "Remediation complete"
```

**Acceptance Criteria:**
- [ ] Script parses YAML playbooks correctly
- [ ] Executes steps sequentially with error handling
- [ ] Dry-run mode shows what would be executed
- [ ] All actions logged to remediation-log.json
- [ ] Can rollback on failure (where possible)

---

### 2.3 Integration with Intelligence Skill

**Objective:** Auto-trigger remediation when issues detected

**Files to Modify:**
- `.claude/skills/homelab-intelligence/SKILL.md`
- `scripts/homelab-intel.sh` (optional enhancement)

**New Remediation Trigger Logic:**
```markdown
### Step 6: Auto-Remediation Check (NEW)

After analyzing health and providing recommendations, check if auto-remediation applies:

```bash
DISK_USAGE=$(jq -r '.metrics.disk_usage_system' latest-intel.json)

if [[ $DISK_USAGE -gt 75 ]]; then
    echo "Disk usage at ${DISK_USAGE}%. Auto-remediation available."

    # Check if user has enabled auto-remediation
    AUTO_REMEDIATE=$(yq eval '.remediation.auto_disk_cleanup' .claude/context/preferences.yml)

    if [[ "$AUTO_REMEDIATE" == "true" ]]; then
        echo "Auto-remediation enabled. Executing disk-cleanup playbook..."
        ./.claude/remediation/scripts/apply-remediation.sh --playbook disk-cleanup
    else
        echo "Would you like me to run automated disk cleanup? (y/n)"
        # Await user confirmation
    fi
fi
```
```

**Acceptance Criteria:**
- [ ] homelab-intelligence detects remediation opportunities
- [ ] Respects user preferences for auto-remediation
- [ ] Offers manual remediation as option
- [ ] Logs when remediation is triggered

---

### 2.4 Drift Auto-Reconciliation

**Objective:** Automatically fix configuration drift when detected

**Files to Create:**
- `.claude/remediation/playbooks/drift-reconciliation.yml`

**Integration:**
```bash
# In .claude/skills/homelab-deployment/scripts/check-drift.sh
# Add at the end after drift detection:

if [[ $DRIFT_DETECTED == true ]]; then
    echo ""
    echo "Drift detected in $SERVICE_NAME"

    # Check if auto-reconciliation enabled
    AUTO_FIX=$(yq eval '.remediation.auto_drift_fix' .claude/context/preferences.yml)

    if [[ "$AUTO_FIX" == "true" ]]; then
        echo "Auto-reconciliation enabled. Regenerating service..."

        # Backup current quadlet
        cp ~/.config/containers/systemd/${SERVICE_NAME}.container \
           ~/.config/containers/systemd/${SERVICE_NAME}.container.backup-$(date +%Y%m%d-%H%M%S)

        # Regenerate from pattern
        ./.claude/skills/homelab-deployment/scripts/deploy-from-pattern.sh \
            --service-name "$SERVICE_NAME" \
            --reconcile-only

        # Restart service
        systemctl --user daemon-reload
        systemctl --user restart ${SERVICE_NAME}.service

        echo "✓ Drift reconciled automatically"
    else
        echo "Auto-reconciliation disabled. Run manually with --reconcile flag"
    fi
fi
```

**Acceptance Criteria:**
- [ ] Drift detection triggers reconciliation offer
- [ ] User preference respected (auto vs manual)
- [ ] Backup created before reconciliation
- [ ] Service restarted and verified healthy
- [ ] Reconciliation logged to deployment-log.json

---

## Deliverables Checklist

### Context Framework
- [ ] `.claude/context/system-profile.json` (auto-generated from system state)
- [ ] `.claude/context/issue-history.json` (populated from 99-reports)
- [ ] `.claude/context/deployment-log.json` (populated from git history)
- [ ] `.claude/context/preferences.yml` (user preferences template)
- [ ] `.claude/context/scripts/generate-system-profile.sh`
- [ ] `.claude/context/scripts/query-issues.sh`
- [ ] `.claude/context/scripts/query-deployments.sh`
- [ ] `.claude/context/scripts/record-deployment.sh`

### Auto-Remediation
- [ ] `.claude/remediation/playbooks/disk-cleanup.yml`
- [ ] `.claude/remediation/playbooks/drift-reconciliation.yml`
- [ ] `.claude/remediation/playbooks/service-restart.yml`
- [ ] `.claude/remediation/playbooks/resource-pressure.yml`
- [ ] `.claude/remediation/scripts/apply-remediation.sh`
- [ ] `.claude/remediation/scripts/log-remediation.sh`
- [ ] `.claude/remediation/README.md`

### Enhanced Skills
- [ ] `.claude/skills/homelab-intelligence/SKILL.md` (updated with context usage)
- [ ] `.claude/skills/homelab-deployment/SKILL.md` (updated with deployment memory)
- [ ] `.claude/skills/skill-integration-guide.md` (context usage patterns)

### Documentation
- [ ] `.claude/context/README.md` (context framework guide)
- [ ] `docs/99-reports/2025-11-XX-session-4-implementation.md` (implementation log)
- [ ] Example context-aware interactions documented

---

## Success Criteria

### Functional Requirements

**Context Framework:**
1. System profile accurately reflects current state (20 services, 5 networks, hardware specs)
2. Issue history contains at least 10 past issues with solutions
3. Deployment log contains at least 15 historical deployments
4. Skills can query context and use it in recommendations

**Auto-Remediation:**
1. Disk cleanup playbook can free 5-15GB automatically
2. Drift reconciliation can fix common config drift
3. All remediations logged with before/after metrics
4. User confirmation required for high-risk operations

**Integration:**
1. homelab-intelligence says "Last time this happened..." referencing issue history
2. homelab-deployment says "Based on your Redis deployment..." referencing deployment log
3. Drift detection offers auto-fix with user confirmation
4. Health checks trigger remediation recommendations

### Quality Requirements

**Safety:**
- [ ] All destructive operations require confirmation (unless explicitly enabled)
- [ ] Backups created before any reconciliation
- [ ] Rollback procedures defined for reversible operations
- [ ] Dry-run mode works for all playbooks

**Logging:**
- [ ] All automated actions logged with timestamp, outcome, metrics
- [ ] Context updates auditable (who changed what when)
- [ ] Remediation results measurable (space freed, services fixed)

**Usability:**
- [ ] Context queries fast (<1s for issue/deployment lookups)
- [ ] Clear error messages when context unavailable
- [ ] Graceful degradation if context files missing

---

## CLI Execution Plan

### Session 4A: Context Framework (3-4 hours)

**Pre-session checklist:**
- [ ] Pull latest from `claude/plan-skills-enhancement-01FRfDgNytQdvP6uKqkCR1CL`
- [ ] Ensure homelab-intel.sh working (Session 3.5 fixes)
- [ ] Verify 99-reports directory has historical data

**Execution sequence:**
```bash
# 1. Create directory structure
mkdir -p .claude/context/scripts
mkdir -p .claude/remediation/{playbooks,scripts}

# 2. Generate system profile
cd .claude/context/scripts
# Create generate-system-profile.sh (from plan above)
chmod +x generate-system-profile.sh
./generate-system-profile.sh
# Verify: cat ../system-profile.json | jq '.'

# 3. Populate issue history
# Create populate-issue-history.sh
./populate-issue-history.sh
# Verify: cat ../issue-history.json | jq '.issues | length'

# 4. Build deployment log
# Create build-deployment-log.sh (parse git log)
./build-deployment-log.sh
# Verify: cat ../deployment-log.json | jq '.deployments | length'

# 5. Test context queries
./query-issues.sh --category disk-space
./query-deployments.sh --service redis

# 6. Update skill integration guide
cd ../../skills
# Edit skill-integration-guide.md with context patterns

# 7. Commit Session 4A
git add .claude/context
git commit -m "Session 4A: Context framework implementation"
git push -u origin claude/plan-skills-enhancement-01FRfDgNytQdvP6uKqkCR1CL
```

**Validation checkpoints:**
- After step 2: system-profile.json contains all services
- After step 3: issue-history.json has 10+ issues
- After step 4: deployment-log.json has 15+ deployments
- After step 5: Query scripts return accurate results

---

### Session 4B: Auto-Remediation (2-3 hours)

**Pre-session checklist:**
- [ ] Session 4A complete and committed
- [ ] Context framework working
- [ ] System disk at moderate usage (for testing cleanup)

**Execution sequence:**
```bash
# 1. Create playbooks
cd .claude/remediation/playbooks
# Create disk-cleanup.yml (from plan above)
# Create drift-reconciliation.yml
# Create service-restart.yml
# Create resource-pressure.yml

# 2. Create execution engine
cd ../scripts
# Create apply-remediation.sh
chmod +x apply-remediation.sh

# Test dry-run
./apply-remediation.sh --playbook disk-cleanup --dry-run

# 3. Test disk cleanup remediation
# (First check current disk usage)
df -h /
# Run playbook
./apply-remediation.sh --playbook disk-cleanup
# Verify space freed
df -h /

# 4. Integrate with check-drift.sh
cd ../../skills/homelab-deployment/scripts
# Edit check-drift.sh to offer auto-reconciliation

# Test drift reconciliation
./check-drift.sh jellyfin

# 5. Enhance homelab-intelligence skill
cd ../../homelab-intelligence
# Edit SKILL.md to add auto-remediation triggers

# 6. Create preferences template
cd ../../../context
cat > preferences.yml <<EOF
remediation:
  auto_disk_cleanup: false          # Require confirmation
  auto_drift_fix: false              # Require confirmation
  auto_service_restart: true         # Safe to auto-restart

risk_tolerance: medium               # low | medium | high
confirmation_required_for:
  - destructive_operations
  - large_changes

deployment_preferences:
  default_memory_limit: "2G"
  prefer_patterns: true
  always_check_health: true
EOF

# 7. Commit Session 4B
git add .claude/remediation .claude/context/preferences.yml
git add .claude/skills/homelab-intelligence/SKILL.md
git add .claude/skills/homelab-deployment/scripts/check-drift.sh
git commit -m "Session 4B: Auto-remediation framework + skill enhancements"
git push
```

**Validation checkpoints:**
- After step 2: Playbooks parse correctly (valid YAML)
- After step 3: Disk cleanup actually frees space
- After step 4: Drift detection offers reconciliation
- After step 5: Skills reference context in recommendations

---

## Testing Scenarios

### Scenario 1: Context-Aware Health Check

**Setup:** Run homelab-intelligence after implementing context

**Expected Behavior:**
```
User: "How is the system?"

Claude:
  Running homelab-intel.sh...

  Health Score: 78/100 ⚠️

  Warnings:
  - System disk at 78% (90GB / 118GB)

  💡 I've seen this before (ISS-002, 2025-11-12):
     Last time disk was at 78%, we freed 12GB by:
     1. Pruning unused container images (freed 8GB)
     2. Rotating journal logs (freed 4GB)

  Would you like me to run the same automated cleanup now?
```

**Validation:**
- [ ] References specific past issue (ISS-002)
- [ ] Provides exact solution that worked before
- [ ] Offers automated remediation

---

### Scenario 2: Deployment Memory Usage

**Setup:** Deploy Redis using cache-service pattern

**Expected Behavior:**
```
User: "Deploy Redis for session storage"

Claude:
  Checking deployment history for Redis...

  📋 Found similar deployment (DEP-015, 2025-11-10):
     - Pattern: cache-service
     - Memory: 512MB (worked well)
     - Persistence: Enabled AOF (recommended for production)
     - Networks: systemd-auth_services

  I'll use the same configuration that worked before.

  Deploying redis-sessions with:
  - Memory: 512MB
  - Persistence: AOF enabled
  - Networks: systemd-auth_services

  [Deployment proceeds with learned settings]
```

**Validation:**
- [ ] Queries deployment-log.json
- [ ] References past successful deployment
- [ ] Auto-populates settings from history
- [ ] Explains why those settings chosen

---

### Scenario 3: Automated Drift Fix

**Setup:** Manually modify jellyfin.container, then run drift detection

**Expected Behavior:**
```
User: "Check if services have drifted"

Claude:
  Running drift detection...

  Service: jellyfin
    ⚠️ DRIFT DETECTED
    - Memory limit: 4G (quadlet) vs 8G (running)
    - Networks: Order differs

  🔧 Auto-reconciliation available:
     I can regenerate the quadlet from your media-server-stack pattern
     and restart the service to match the declared configuration.

  This will:
  1. Backup current quadlet
  2. Regenerate from pattern
  3. Restart jellyfin service

  Proceed with auto-reconciliation? (y/n)
```

**Validation:**
- [ ] Detects drift accurately
- [ ] Offers automated fix
- [ ] Explains what will happen
- [ ] Requires confirmation
- [ ] Creates backup before changing

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Context files grow too large** | Medium | Low | Implement rotation, keep last 90 days |
| **Automated remediation causes outage** | Low | High | Require confirmation for risky ops, dry-run first |
| **Context data out of sync** | Medium | Medium | Auto-refresh on intel script runs |
| **Playbook logic errors** | Medium | Medium | Extensive testing, rollback procedures |
| **Privacy concerns (context in git)** | Low | Medium | Add .gitignore for sensitive context data |

**Mitigation Plan:**
- All destructive operations require user confirmation by default
- Dry-run mode for all playbooks before execution
- Automated backups before any configuration changes
- Context data versioned with timestamps for rollback
- Logging of all automated actions for audit trail

---

## Future Enhancements (Beyond Session 4)

### Session 5 Ideas:
1. **Multi-Service Orchestration** (Option 1 from original plan)
   - Stack deployment patterns
   - Dependency graph resolution
   - Atomic rollback

2. **Predictive Analytics**
   - Analyze trends from issue history
   - Predict when disk will fill based on growth rate
   - Recommend preventive maintenance

3. **Natural Language Context Queries**
   - "What happened with CrowdSec last week?"
   - "How did we solve the Immich GPU issue?"
   - "Show me all Redis deployments"

4. **Skill Recommendation Engine**
   - Auto-suggest which skill to invoke based on context
   - "This looks like a deployment issue, shall I run deployment skill?"

5. **Backup Integration**
   - Record backup events in context
   - Auto-verify backup success
   - Alert when backup patterns break

---

## Estimated Timeline

**Session 4A (Context Framework):**
- Setup: 30 min
- System profile generation: 1 hour
- Issue history population: 1 hour
- Deployment log building: 1 hour
- Integration & testing: 30 min
- **Total: 4 hours**

**Session 4B (Auto-Remediation):**
- Playbook creation: 1.5 hours
- Execution engine: 1 hour
- Testing & validation: 1 hour
- Skill integration: 30 min
- **Total: 4 hours**

**Grand Total: 6-8 hours** (likely 2-3 CLI sessions)

---

## Success Metrics

After Session 4 completion:

**Quantitative:**
- [ ] Context queries respond in <1 second
- [ ] Auto-remediation frees 5-15GB disk space (tested)
- [ ] Drift reconciliation success rate >95%
- [ ] At least 3 context-aware interactions demonstrated

**Qualitative:**
- [ ] Claude references specific past issues by ID
- [ ] Recommendations based on actual system data
- [ ] Automated fixes complete without user intervention
- [ ] Skills feel "aware" of system history

**Foundation for Future:**
- [ ] Context layer extensible for new data types
- [ ] Remediation framework supports new playbooks
- [ ] Skills can easily add context usage
- [ ] Clear path to Level 3 automation

---

## Getting Started

**Ready to execute?**

```bash
# Pull this plan to fedora-htpc
cd ~/containers
git pull origin claude/plan-skills-enhancement-01FRfDgNytQdvP6uKqkCR1CL

# Review the plan
cat docs/99-reports/2025-11-15-session-4-hybrid-plan.md

# Start Session 4A when ready
# Follow "Session 4A: Context Framework" execution sequence above
```

**Questions before starting:**
1. Should auto-remediation require confirmation by default? (Recommended: Yes)
2. How many days of issue history to keep? (Recommended: 90 days)
3. Should context files be gitignored or committed? (Recommended: Commit schema, gitignore data)

---

**Plan Created:** 2025-11-15
**Status:** Ready for CLI execution
**Expected Outcome:** Context-aware Claude Skills with intelligent auto-remediation
**Next Steps:** Execute Session 4A on fedora-htpc CLI
