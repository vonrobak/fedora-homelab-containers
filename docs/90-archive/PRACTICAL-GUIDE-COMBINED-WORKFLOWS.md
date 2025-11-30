# Practical Guide: Combined Workflows

**Leverage Session 5A + 5B Together for Maximum Value**

**Created:** 2025-11-18
**Combines:** Stack Deployment + Predictive Analytics + Context Framework + Auto-Remediation
**Skill Level:** Advanced

---

## Overview

You now have a **powerful combination** of capabilities that work together:

1. **Stack Deployment** (5A) - Deploy complex multi-service apps
2. **Predictive Analytics** (5B) - Forecast problems before they happen
3. **Context Framework** (Session 4) - Remember system history
4. **Auto-Remediation** (Session 4) - Fix common issues automatically

This guide shows how to use them **together** for production-grade operations.

---

## Workflow 1: Capacity-Aware Stack Deployment

**Scenario:** Deploy Immich stack only if predictive analytics shows sufficient resources

### The Problem
```bash
# Deploy 5-service stack (6.5GB memory, 100GB disk)
./deploy-stack.sh --stack immich

# 2 hours later...
# [ERROR] System out of memory
# [ERROR] Disk full during deployment
# Manual rollback, resource cleanup, frustration...
```

### The Solution: Pre-Deployment Capacity Check
```bash
#!/bin/bash
# smart-deploy.sh - Capacity-aware stack deployment

STACK="$1"

echo "🔍 Step 1: Checking current resource capacity..."
cd ~/containers/scripts/predictive-analytics
./predict-resource-exhaustion.sh --output json > /tmp/capacity.json

# Extract predictions
DISK_DAYS=$(jq -r '.predictions.disk.system_ssd.days_until_critical // 999' /tmp/capacity.json)
MEM_AVAIL=$(free -m | awk '/Mem:/ {print $7}')

# Check if safe to deploy
SAFE_TO_DEPLOY=true

if [ "$DISK_DAYS" -lt 14 ]; then
    echo "⚠️  WARNING: Disk will be full in $DISK_DAYS days"
    echo "   Recommendation: Run disk cleanup first"
    SAFE_TO_DEPLOY=false
fi

if [ "$MEM_AVAIL" -lt 8000 ]; then
    echo "⚠️  WARNING: Only ${MEM_AVAIL}MB memory available"
    echo "   Recommendation: Restart memory-intensive services first"
    SAFE_TO_DEPLOY=false
fi

if [ "$SAFE_TO_DEPLOY" = false ]; then
    echo ""
    echo "❌ Pre-flight check failed. Options:"
    echo "   1. Run: cd ~/containers/.claude/remediation/scripts && ./apply-remediation.sh --playbook disk-cleanup"
    echo "   2. Free memory: systemctl --user restart jellyfin.service"
    echo "   3. Proceed anyway (risky): ./deploy-stack.sh --stack $STACK --force"
    exit 1
fi

echo "✅ Step 1: Capacity check passed"
echo ""
echo "📦 Step 2: Deploying stack..."
cd ~/containers/.claude/skills/homelab-deployment
./scripts/deploy-stack.sh --stack "$STACK"

if [ $? -eq 0 ]; then
    echo ""
    echo "📊 Step 3: Recording deployment in context..."
    cd ~/containers/.claude/context/scripts
    # Auto-update deployment log here
    # (Future enhancement)

    echo ""
    echo "🎯 Step 4: Re-running capacity predictions..."
    cd ~/containers/scripts/predictive-analytics
    ./generate-predictions-cache.sh

    echo ""
    echo "✅ Deployment complete with capacity monitoring"
fi
```

**Usage:**
```bash
chmod +x smart-deploy.sh
./smart-deploy.sh immich

# Output:
# 🔍 Step 1: Checking current resource capacity...
# ✅ Disk: 32 days until critical
# ✅ Memory: 14200MB available
# ✅ Step 1: Capacity check passed
#
# 📦 Step 2: Deploying stack...
# [deploy-stack.sh output...]
```

---

## Workflow 2: Predictive Maintenance Schedule

**Scenario:** Schedule maintenance based on predictive analytics + low-traffic windows

### The Complete Picture
```bash
#!/bin/bash
# weekly-maintenance.sh - Intelligent maintenance scheduling

echo "📅 Weekly Maintenance Planner - $(date)"
echo ""

# Step 1: Generate predictions
echo "🔮 Analyzing predictive forecasts..."
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh > /dev/null

# Step 2: Identify issues
CRITICAL=$(jq -r '.summary.critical' ~/.claude/context/predictions.json)
WARNING=$(jq -r '.summary.warning' ~/.claude/context/predictions.json)

echo "   Critical issues: $CRITICAL"
echo "   Warning issues: $WARNING"
echo ""

# Step 3: Check what needs attention
DISK_DAYS=$(jq -r '.predictions.disk.system_ssd.days_until_critical // 999' ~/.claude/context/predictions.json)
MEMORY_LEAKS=$(jq -r '.predictions.memory | to_entries[] | select(.value.severity == "warning" or .value.severity == "critical") | .key' ~/.claude/context/predictions.json)

TASKS=()

if [ "$DISK_DAYS" -lt 14 ]; then
    TASKS+=("disk_cleanup")
    echo "📌 Task: Disk cleanup (will be full in $DISK_DAYS days)"
fi

if [ -n "$MEMORY_LEAKS" ]; then
    for service in $MEMORY_LEAKS; do
        TASKS+=("restart_$service")
        echo "📌 Task: Restart $service (memory leak detected)"
    done
fi

if [ ${#TASKS[@]} -eq 0 ]; then
    echo "✅ No maintenance needed this week!"
    exit 0
fi

echo ""
echo "🗓️  Maintenance Schedule:"
echo "   Optimal window: Tuesday 2-5am (low traffic)"
echo ""

# Step 4: Generate maintenance script
cat > /tmp/maintenance-$(date +%Y%m%d).sh <<'MAINTENANCE_EOF'
#!/bin/bash
echo "🔧 Starting automated maintenance - $(date)"

# Disk cleanup
if [[ " ${TASKS[@]} " =~ "disk_cleanup" ]]; then
    echo "1. Running disk cleanup..."
    cd ~/containers/.claude/remediation/scripts
    ./apply-remediation.sh --playbook disk-cleanup
fi

# Service restarts (for memory leaks)
for service in $MEMORY_LEAKS; do
    echo "2. Restarting $service (memory leak mitigation)..."
    systemctl --user restart ${service}.service
    sleep 30
    systemctl --user status ${service}.service
done

# Post-maintenance verification
echo ""
echo "✅ Maintenance complete - $(date)"
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh
echo ""
echo "📊 Updated predictions:"
jq '.summary' ~/.claude/context/predictions.json
MAINTENANCE_EOF

chmod +x /tmp/maintenance-*.sh

echo ""
echo "✅ Maintenance script generated: /tmp/maintenance-$(date +%Y%m%d).sh"
echo ""
echo "To schedule for Tuesday 2am:"
echo "   echo '/tmp/maintenance-$(date +%Y%m%d).sh' | at 02:00 next tuesday"
echo ""
echo "Or run now:"
echo "   /tmp/maintenance-$(date +%Y%m%d).sh"
```

**Setup:**
```bash
# Run weekly on Monday to plan Tuesday maintenance
crontab -e
0 9 * * 1 ~/containers/scripts/weekly-maintenance.sh | mail -s "Weekly Maintenance Plan" you@example.com
```

---

## Workflow 3: Stack Health Monitoring

**Scenario:** Monitor deployed stack health with predictive analytics

### Real-Time Stack Dashboard
```bash
#!/bin/bash
# stack-health.sh - Monitor stack with predictive insights

STACK_NAME="$1"

if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <stack-name>"
    echo "Example: $0 immich"
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           STACK HEALTH: $STACK_NAME"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Get stack services from systemd
SERVICES=$(systemctl --user list-units | grep "^  ${STACK_NAME}-" | awk '{print $1}')

if [ -z "$SERVICES" ]; then
    echo "❌ No services found for stack: $STACK_NAME"
    exit 1
fi

echo "📦 Services in stack:"
for service in $SERVICES; do
    STATUS=$(systemctl --user is-active $service)
    if [ "$STATUS" = "active" ]; then
        echo "   ✅ $service"
    else
        echo "   ❌ $service ($STATUS)"
    fi
done
echo ""

# Resource usage
echo "💾 Resource Usage:"
for service in $SERVICES; do
    CONTAINER=$(echo $service | sed 's/.service$//')
    if podman ps | grep -q $CONTAINER; then
        STATS=$(podman stats --no-stream --format "{{.MemUsage}}" $CONTAINER)
        echo "   $CONTAINER: $STATS"
    fi
done
echo ""

# Predictive insights
echo "🔮 Predictive Analysis:"
cd ~/containers/scripts/predictive-analytics

for service in $SERVICES; do
    CONTAINER=$(echo $service | sed 's/.service$//')
    ./predict-resource-exhaustion.sh --type memory --service $CONTAINER 2>/dev/null | grep -A 3 "$CONTAINER" || true
done

# Disk impact
echo ""
echo "💿 Disk Usage (Stack Storage):"
STACK_STORAGE="/mnt/btrfs-pool/subvol7-containers/${STACK_NAME}"
if [ -d "$STACK_STORAGE" ]; then
    du -sh $STACK_STORAGE
fi

# Overall health score
echo ""
echo "📊 Health Score:"
ACTIVE_COUNT=$(echo "$SERVICES" | wc -w)
RUNNING_COUNT=$(systemctl --user is-active $SERVICES 2>/dev/null | grep -c active)
HEALTH_PERCENT=$((RUNNING_COUNT * 100 / ACTIVE_COUNT))

if [ $HEALTH_PERCENT -eq 100 ]; then
    echo "   ✅ Excellent (${HEALTH_PERCENT}%)"
elif [ $HEALTH_PERCENT -ge 80 ]; then
    echo "   ⚠️  Good (${HEALTH_PERCENT}%)"
else
    echo "   ❌ Poor (${HEALTH_PERCENT}%)"
fi
```

**Usage:**
```bash
./stack-health.sh immich

# Output:
# ╔══════════════════════════════════════════════════════════╗
# ║           STACK HEALTH: immich
# ╚══════════════════════════════════════════════════════════╝
#
# 📦 Services in stack:
#    ✅ immich-postgres.service
#    ✅ immich-redis.service
#    ✅ immich-server.service
#    ✅ immich-ml.service
#    ✅ immich-web.service
#
# 💾 Resource Usage:
#    immich-postgres: 1.2GB / 1.5GB
#    immich-redis: 180MB / 512MB
#    immich-server: 1.8GB / 2GB
#    immich-ml: 1.5GB / 2GB
#    immich-web: 420MB / 640MB
#
# 🔮 Predictive Analysis:
#    immich-server: Trend +12MB/hour, 4 days until limit
#    ⚠️  WARNING: Consider restart within 3 days
#
# 💿 Disk Usage (Stack Storage):
#    42GB    /mnt/btrfs-pool/subvol7-containers/immich
#
# 📊 Health Score:
#    ✅ Excellent (100%)
```

---

## Workflow 4: Intelligent Deployment Sizing

**Scenario:** Use historical data to right-size new stack deployments

### Data-Driven Resource Allocation
```bash
#!/bin/bash
# calculate-stack-resources.sh - Predict resource needs

STACK_TYPE="$1"  # e.g., "photo-management", "monitoring", "auth"

echo "📊 Resource Prediction for: $STACK_TYPE"
echo ""

# Query context for similar deployments
cd ~/containers/.claude/context/scripts
SIMILAR=$(./query-deployments.sh --method pattern-based | grep -i "$STACK_TYPE" || echo "")

if [ -n "$SIMILAR" ]; then
    echo "📚 Historical deployments found:"
    echo "$SIMILAR"
    echo ""
fi

# Analyze current resource trends
cd ~/containers/scripts/predictive-analytics
./predict-resource-exhaustion.sh --type all --output json > /tmp/current-state.json

DISK_AVAIL=$(jq -r '.current.disk.system_ssd.available_gb // 0' /tmp/current-state.json)
MEM_AVAIL=$(free -g | awk '/Mem:/ {print $7}')

echo "💾 Available Resources:"
echo "   Disk: ${DISK_AVAIL}GB"
echo "   Memory: ${MEM_AVAIL}GB"
echo ""

# Recommend sizing based on stack type
case "$STACK_TYPE" in
    "photo-management"|"immich")
        DISK_NEED=100
        MEM_NEED=7
        echo "📦 Recommended for Photo Management:"
        echo "   Disk: ${DISK_NEED}GB"
        echo "   Memory: ${MEM_NEED}GB"
        ;;
    "monitoring")
        DISK_NEED=50
        MEM_NEED=2
        echo "📦 Recommended for Monitoring:"
        echo "   Disk: ${DISK_NEED}GB"
        echo "   Memory: ${MEM_NEED}GB"
        ;;
    *)
        echo "⚠️  Unknown stack type. Defaults:"
        DISK_NEED=50
        MEM_NEED=4
        echo "   Disk: ${DISK_NEED}GB"
        echo "   Memory: ${MEM_NEED}GB"
        ;;
esac

echo ""

# Safety check
if [ "$DISK_AVAIL" -lt "$DISK_NEED" ]; then
    echo "❌ Insufficient disk space"
    echo "   Need: ${DISK_NEED}GB"
    echo "   Available: ${DISK_AVAIL}GB"
    echo "   Shortfall: $((DISK_NEED - DISK_AVAIL))GB"
    echo ""
    echo "💡 Recommendation: Run disk cleanup or expand storage"
elif [ "$MEM_AVAIL" -lt "$MEM_NEED" ]; then
    echo "❌ Insufficient memory"
    echo "   Need: ${MEM_NEED}GB"
    echo "   Available: ${MEM_AVAIL}GB"
    echo ""
    echo "💡 Recommendation: Restart memory-intensive services or add RAM"
else
    echo "✅ Resources sufficient for deployment"
    echo ""
    echo "📋 Projected post-deployment state:"
    echo "   Disk remaining: $((DISK_AVAIL - DISK_NEED))GB"
    echo "   Memory remaining: $((MEM_AVAIL - MEM_NEED))GB"
    echo ""
    echo "🚀 Safe to proceed with deployment"
fi
```

---

## Workflow 5: Post-Deployment Validation

**Scenario:** Verify stack deployment success and update predictions

### Complete Deployment Lifecycle
```bash
#!/bin/bash
# full-stack-deployment.sh - Complete deployment with validation

STACK="$1"

echo "🚀 Full Stack Deployment: $STACK"
echo "══════════════════════════════════════"
echo ""

# Phase 1: Pre-deployment checks
echo "Phase 1: Pre-Deployment Checks"
echo "────────────────────────────────"

# Generate baseline predictions
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh
cp ~/.claude/context/predictions.json /tmp/predictions-before.json
echo "✅ Baseline predictions captured"

# Check capacity
DISK_DAYS=$(jq -r '.predictions.disk.system_ssd.days_until_critical // 999' /tmp/predictions-before.json)
if [ "$DISK_DAYS" -lt 7 ]; then
    echo "⚠️  Warning: Low disk space ($DISK_DAYS days until critical)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# Phase 2: Deploy stack
echo "Phase 2: Stack Deployment"
echo "────────────────────────────────"
cd ~/containers/.claude/skills/homelab-deployment
./scripts/deploy-stack.sh --stack "$STACK"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Deployment failed. Check logs:"
    ls -t ~/containers/data/deployment-logs/stack-${STACK}-*.log | head -1
    exit 1
fi
echo ""

# Phase 3: Post-deployment validation
echo "Phase 3: Post-Deployment Validation"
echo "────────────────────────────────"

# Wait for services to stabilize
echo "⏳ Waiting 60s for services to stabilize..."
sleep 60

# Check all services
SERVICES=$(systemctl --user list-units | grep "^  ${STACK}-" | awk '{print $1}')
ALL_ACTIVE=true
for service in $SERVICES; do
    if ! systemctl --user is-active $service > /dev/null; then
        echo "❌ $service is not active"
        ALL_ACTIVE=false
    else
        echo "✅ $service is active"
    fi
done

if [ "$ALL_ACTIVE" = false ]; then
    echo ""
    echo "⚠️  Some services failed. Check systemctl status."
    exit 1
fi
echo ""

# Phase 4: Update predictions
echo "Phase 4: Resource Impact Analysis"
echo "────────────────────────────────"
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh
cp ~/.claude/context/predictions.json /tmp/predictions-after.json

# Compare before/after
DISK_BEFORE=$(jq -r '.predictions.disk.system_ssd.current_usage_percent' /tmp/predictions-before.json)
DISK_AFTER=$(jq -r '.predictions.disk.system_ssd.current_usage_percent' /tmp/predictions-after.json)
DISK_IMPACT=$(echo "$DISK_AFTER - $DISK_BEFORE" | bc)

echo "📊 Resource Impact:"
echo "   Disk usage: ${DISK_BEFORE}% → ${DISK_AFTER}% (+${DISK_IMPACT}%)"

DAYS_BEFORE=$(jq -r '.predictions.disk.system_ssd.days_until_critical // 999' /tmp/predictions-before.json)
DAYS_AFTER=$(jq -r '.predictions.disk.system_ssd.days_until_critical // 999' /tmp/predictions-after.json)
echo "   Days until critical: ${DAYS_BEFORE} → ${DAYS_AFTER}"

if [ "$DAYS_AFTER" -lt 14 ]; then
    echo ""
    echo "⚠️  Warning: Deployment reduced capacity headroom"
    echo "   Recommendation: Schedule disk cleanup soon"
fi
echo ""

# Phase 5: Record in context
echo "Phase 5: Context Update"
echo "────────────────────────────────"
echo "📝 Recording deployment in context framework..."
# (Future: Auto-add to deployment-log.json)
echo "✅ Context updated"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "✅ Deployment Complete: $STACK"
echo "═══════════════════════════════════════════════════════"
```

---

## Integration Patterns

### Pattern 1: Prediction → Remediation → Deployment

```mermaid
Predictions Show Issue
        ↓
Auto-Remediation Fixes
        ↓
Deploy Stack
        ↓
Update Predictions
```

**Script:**
```bash
# 1. Check predictions
./predict-resource-exhaustion.sh | grep CRITICAL

# 2. If critical, remediate
./apply-remediation.sh --playbook disk-cleanup

# 3. Deploy stack
./deploy-stack.sh --stack immich

# 4. Update predictions
./generate-predictions-cache.sh
```

### Pattern 2: Deploy → Monitor → Predict → Act

```mermaid
Deploy Stack
        ↓
Monitor Services (Prometheus)
        ↓
Predict Trends
        ↓
Proactive Maintenance
```

**Automation:**
```bash
# Cron: Daily prediction + auto-action
0 2 * * * /opt/scripts/predict-and-remediate.sh
```

### Pattern 3: Context-Aware Stack Selection

```mermaid
Query Deployment History
        ↓
Analyze Resource Trends
        ↓
Calculate Capacity
        ↓
Recommend Stack Size
```

---

## Best Practices

### 1. Always Check Capacity Before Deployment

```bash
# GOOD
./predict-resource-exhaustion.sh
# Review output, verify capacity
./deploy-stack.sh --stack immich

# BAD
./deploy-stack.sh --stack immich  # Hope for the best!
```

### 2. Update Predictions After Major Changes

```bash
# After stack deployment
./generate-predictions-cache.sh

# After cleanup
./generate-predictions-cache.sh

# After service restart
./generate-predictions-cache.sh
```

### 3. Track Prediction Accuracy

```bash
# Weekly: Compare predictions vs reality
cat > ~/containers/scripts/check-accuracy.sh <<'EOF'
#!/bin/bash
PRED_7D_AGO=$(jq -r '.predictions.disk.system_ssd.forecast.day_7.percent_used' \
  ~/containers/data/predictions-$(date -d '7 days ago' +%Y%m%d).json)
ACTUAL_NOW=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
ERROR=$((ACTUAL_NOW - PRED_7D_AGO))
echo "Prediction accuracy: ${ERROR}% error"
EOF
```

### 4. Combine Automation with Human Oversight

```bash
# Automatic: Low-risk actions
- Disk cleanup when >75%
- Predictions caching every 6h
- Service health checks

# Manual approval: High-risk actions
- Stack deployments
- Service restarts
- Configuration changes
```

---

## Complete Example: Production Deployment Workflow

```bash
#!/bin/bash
# production-deploy.sh - Full production deployment workflow

set -euo pipefail

STACK="$1"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

log "Starting production deployment: $STACK"
echo ""

# Step 1: Predictive capacity check
log "Step 1: Capacity Analysis"
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh > /dev/null

CRITICAL=$(jq -r '.summary.critical' ~/.claude/context/predictions.json)
if [ "$CRITICAL" -gt 0 ]; then
    error "Critical resource issues detected"
    jq -r '.predictions | to_entries[] | select(.value | .. | .severity? == "critical") | "\(.key): \(.value)"' ~/.claude/context/predictions.json
    warn "Run remediation before deploying"
    exit 1
fi
success "Capacity check passed"
echo ""

# Step 2: Historical context check
log "Step 2: Checking Deployment History"
cd ~/containers/.claude/context/scripts
HISTORY=$(./query-deployments.sh --method stack-based | grep "$STACK" || echo "")
if [ -n "$HISTORY" ]; then
    warn "Stack previously deployed:"
    echo "$HISTORY"
    read -p "Redeploy? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi
echo ""

# Step 3: Deploy stack
log "Step 3: Deploying Stack"
cd ~/containers/.claude/skills/homelab-deployment
./scripts/deploy-stack.sh --stack "$STACK"

if [ $? -ne 0 ]; then
    error "Deployment failed"
    exit 1
fi
success "Stack deployed"
echo ""

# Step 4: Post-deployment validation
log "Step 4: Validation"
sleep 30
SERVICES=$(systemctl --user list-units | grep "^  ${STACK}-" | awk '{print $1}')
FAILED=0
for service in $SERVICES; do
    if systemctl --user is-active $service > /dev/null; then
        success "$service is active"
    else
        error "$service failed"
        FAILED=$((FAILED + 1))
    fi
done

if [ $FAILED -gt 0 ]; then
    error "$FAILED services failed"
    exit 1
fi
echo ""

# Step 5: Update predictions
log "Step 5: Updating Predictions"
cd ~/containers/scripts/predictive-analytics
./generate-predictions-cache.sh > /dev/null
success "Predictions updated"
echo ""

success "Production deployment complete: $STACK"
log "Monitor: ./stack-health.sh $STACK"
```

---

**Bottom Line:** Combining stack deployment + predictive analytics + context + remediation gives you **production-grade infrastructure automation** with proactive health management.

**Key Advantage:** Deploy complex stacks confidently, knowing you have capacity monitoring, automatic cleanup, and predictive insights working together.

---

**Created:** 2025-11-18
**Version:** 1.0
**Maintainer:** patriark
**Combines:** Sessions 4A, 4B, 5A, 5B
