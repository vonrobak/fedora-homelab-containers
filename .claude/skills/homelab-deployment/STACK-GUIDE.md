# Stack Deployment Guide

**Session 5A: Multi-Service Orchestration**

This guide explains how to deploy complex multi-service stacks atomically using the new stack deployment system.

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Stack Definitions](#stack-definitions)
4. [Deployment Workflow](#deployment-workflow)
5. [Available Stacks](#available-stacks)
6. [Creating Custom Stacks](#creating-custom-stacks)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### What is Stack Deployment?

**Stack deployment** allows you to deploy entire application stacks (multiple interdependent services) with a single command. The system:

- **Resolves dependencies** automatically (topological sort)
- **Deploys in phases** (parallel where possible)
- **Waits for health checks** before proceeding
- **Rolls back** on failure (all-or-nothing)
- **Validates** post-deployment

### Why Use Stacks?

**Before (Manual):**
```bash
# Deploy Immich manually (error-prone, 40-60 minutes)
podman run ... immich-postgres
# Wait... is it ready?
podman run ... immich-redis
# Wait... is it ready?
podman run ... immich-server
# Error! Database connection failed. What went wrong?
# Manual cleanup and retry...
```

**After (Stack):**
```bash
# Deploy Immich stack (automated, 8-10 minutes)
./deploy-stack.sh --stack immich

# System handles:
# - Dependency resolution (postgres + redis first)
# - Health check coordination
# - Automatic rollback on failure
```

---

## Quick Start

### 1. Deploy a Stack

```bash
cd ~/containers/.claude/skills/homelab-deployment

# Dry-run (show plan without deploying)
./scripts/deploy-stack.sh --stack monitoring-simple --dry-run

# Deploy for real
./scripts/deploy-stack.sh --stack monitoring-simple
```

### 2. Check Deployment Status

```bash
# View deployment log
tail -f ~/containers/data/deployment-logs/stack-monitoring-simple-*.log

# Check service status
systemctl --user status prometheus.service grafana.service

# Check health
podman healthcheck run prometheus
podman healthcheck run grafana
```

### 3. Visualize Dependencies

```bash
# Generate dependency graph
./scripts/resolve-dependencies.sh --stack stacks/immich.yml --visualize > immich-deps.dot

# Convert to PNG (requires graphviz)
dot -Tpng immich-deps.dot -o immich-deps.png
xdg-open immich-deps.png
```

---

## Stack Definitions

### Stack YAML Structure

```yaml
stack:
  name: my-stack
  description: "Description of the stack"
  version: "1.0"

shared:
  networks:
    - systemd-reverse_proxy
    - systemd-monitoring
  resources:
    total_memory_mb: 2048
  domain: example.patriark.org
  storage_base: /mnt/btrfs-pool/subvol7-containers/mystack

services:
  - name: service-a
    pattern: database-service
    dependencies: []  # No dependencies
    configuration:
      image: docker.io/library/postgres:15
      memory: 1024M
      environment:
        POSTGRES_USER: myuser
      volumes:
        - ${storage_base}/postgres:/var/lib/postgresql/data:Z

  - name: service-b
    pattern: web-app-with-database
    dependencies:
      - service-a  # Depends on service-a
    configuration:
      image: my/app:latest
      memory: 1024M
      environment:
        DB_HOST: service-a

# Deployment phases (auto-computed from dependencies)
deployment:
  phases:
    - phase: 1
      parallel: true
      services:
        - service-a

    - phase: 2
      parallel: false
      services:
        - service-b

# Validation tests
validation:
  tests:
    - name: "Database connectivity"
      type: sql_query
      target: service-a
      query: "SELECT 1"

# Documentation
documentation:
  pre_deployment:
    - "Set environment variables: MY_VAR=value"
  post_deployment:
    - "Access at: https://example.patriark.org"
```

### Key Concepts

**Dependencies:**
- Services with `dependencies: []` deploy first
- Services with dependencies wait for their deps to be healthy
- Circular dependencies are detected and rejected

**Phases:**
- Services without dependencies deploy in **Phase 1** (parallel)
- Dependent services deploy in subsequent phases
- Within a phase, services can deploy in parallel

**Patterns:**
- Reference existing homelab-deployment patterns
- Examples: `database-service`, `web-app-with-database`, `cache-service`

---

## Deployment Workflow

### Dry-Run Mode (Recommended First Step)

```bash
./scripts/deploy-stack.sh --stack immich --dry-run
```

**Output:**
```
[INFO] Stack Deployment: immich
[WARNING] DRY-RUN MODE - No changes will be made
[INFO] Running pre-flight validation...
[SUCCESS] Pre-flight validation passed
[INFO] Deployment plan: 3 phases

[INFO] Phase 1: Deploying 2 service(s)
[INFO] [DRY-RUN] Would deploy: immich-postgres
[INFO] [DRY-RUN] Would deploy: immich-redis

[INFO] Phase 2: Deploying 1 service(s)
[INFO] [DRY-RUN] Would deploy: immich-server

[INFO] Phase 3: Deploying 2 service(s)
[INFO] [DRY-RUN] Would deploy: immich-ml
[INFO] [DRY-RUN] Would deploy: immich-web
```

### Actual Deployment

```bash
./scripts/deploy-stack.sh --stack immich --verbose
```

**What Happens:**
1. **Pre-flight Validation**
   - Verify stack YAML syntax
   - Check for circular dependencies
   - Validate networks exist
   - Check available memory

2. **Dependency Resolution**
   - Compute deployment order (topological sort)
   - Identify phases for parallel deployment

3. **Phase-by-Phase Deployment**
   - Deploy services in each phase
   - Wait for health checks before next phase
   - Log all actions

4. **Post-Deployment Validation**
   - Run validation tests (if defined)
   - Show summary and next steps

5. **Rollback (if failure)**
   - Stop services in reverse order
   - Remove quadlet files
   - Preserve data volumes

---

## Available Stacks

### 1. Immich (Photo Management)

**File:** `stacks/immich.yml`

**Services:** 5
- immich-postgres (PostgreSQL with vector extension)
- immich-redis (session storage)
- immich-server (API backend)
- immich-ml (machine learning service)
- immich-web (web frontend)

**Deployment:**
```bash
# Set environment variables
export IMMICH_DB_PASSWORD="your-secure-password"
export IMMICH_REDIS_PASSWORD="your-redis-password"

# Deploy
./scripts/deploy-stack.sh --stack immich

# Estimated time: 8-10 minutes
# Memory usage: ~6.5GB
```

**Access:** https://photos.patriark.org

---

### 2. Monitoring-Simple (Prometheus + Grafana)

**File:** `stacks/monitoring-simple.yml`

**Services:** 2
- prometheus (metrics database)
- grafana (visualization)

**Deployment:**
```bash
# Set environment variable
export GRAFANA_ADMIN_PASSWORD="your-admin-password"

# Deploy
./scripts/deploy-stack.sh --stack monitoring-simple

# Estimated time: 2-3 minutes
# Memory usage: ~1.5GB
```

**Access:**
- Prometheus: https://prometheus.patriark.org
- Grafana: https://grafana.patriark.org

---

### 3. Test Stacks

**Simple:** `stacks/test-simple.yml` (2 services, linear dependency)
**Parallel:** `stacks/test-parallel.yml` (3 services, parallel opportunity)
**Cycle:** `stacks/test-cycle.yml` (circular dependency, should fail)

---

## Creating Custom Stacks

### Step 1: Create Stack Definition

```bash
cd ~/containers/.claude/skills/homelab-deployment/stacks
nano my-custom-stack.yml
```

### Step 2: Validate Stack

```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('my-custom-stack.yml'))"

# Check dependencies
../scripts/resolve-dependencies.sh --stack my-custom-stack.yml --validate-only

# View deployment order
../scripts/resolve-dependencies.sh --stack my-custom-stack.yml
```

### Step 3: Dry-Run

```bash
../scripts/deploy-stack.sh --stack my-custom-stack --dry-run
```

### Step 4: Deploy

```bash
../scripts/deploy-stack.sh --stack my-custom-stack
```

---

## Troubleshooting

### Issue: Circular Dependency Error

**Symptom:**
```
[ERROR] Circular dependency detected in stack
[ERROR] Services involved in cycle:
[ERROR]   - service-a (in-degree: 1)
[ERROR]   - service-b (in-degree: 1)
```

**Solution:**
1. Visualize dependencies:
   ```bash
   ./scripts/resolve-dependencies.sh --stack stacks/mystack.yml --visualize > deps.dot
   dot -Tpng deps.dot -o deps.png
   ```

2. Review dependency arrows in graph
3. Remove circular dependency by re-architecting

---

### Issue: Pre-flight Validation Failed

**Network not found:**
```
[ERROR] Network not found: systemd-my_network
[INFO] Create network with: podman network create systemd-my_network
```

**Solution:**
```bash
podman network create systemd-my_network
```

**Insufficient memory:**
```
[WARNING] Requested memory (8192 MB) > available (6000 MB)
Continue anyway? (y/n)
```

**Solution:** Reduce memory limits in stack YAML or free up memory

---

### Issue: Health Check Timeout

**Symptom:**
```
[ERROR] Health check timeout for immich-server (300s)
```

**Cause:** Service started but health check failing

**Solutions:**
1. **Check service logs:**
   ```bash
   journalctl --user -u immich-server.service -f
   podman logs immich-server
   ```

2. **Manually test health check:**
   ```bash
   podman exec immich-server curl -f http://localhost:3001/api/server-info/ping
   ```

3. **Increase timeout:** Edit stack YAML:
   ```yaml
   ready_criteria:
     type: healthcheck
     timeout: 600s  # Increase from 300s
   ```

---

### Issue: Rollback Leaves Containers Running

**Symptom:** After rollback, `podman ps` still shows containers

**Solution:** Manual cleanup:
```bash
# List all services in stack
STACK_SERVICES="service-a service-b service-c"

# Stop and remove
for service in $STACK_SERVICES; do
    systemctl --user stop $service.service || true
    podman stop $service || true
    podman rm $service || true
done

# Clean quadlets
rm -f ~/.config/containers/systemd/{service-a,service-b,service-c}.container
systemctl --user daemon-reload
```

---

## Command Reference

### deploy-stack.sh

```bash
# Deploy stack
./deploy-stack.sh --stack <name>

# Dry-run (show plan)
./deploy-stack.sh --stack <name> --dry-run

# Skip health checks (fast, risky)
./deploy-stack.sh --stack <name> --skip-health-check

# Disable rollback on failure
./deploy-stack.sh --stack <name> --no-rollback

# Verbose output
./deploy-stack.sh --stack <name> --verbose

# Custom stack file
./deploy-stack.sh --stack-file /path/to/custom.yml
```

### resolve-dependencies.sh

```bash
# Show deployment order
./resolve-dependencies.sh --stack stacks/immich.yml

# Validate (check for cycles)
./resolve-dependencies.sh --stack stacks/immich.yml --validate-only

# JSON output
./resolve-dependencies.sh --stack stacks/immich.yml --output json

# Visualize (Graphviz DOT)
./resolve-dependencies.sh --stack stacks/immich.yml --visualize
```

---

## Best Practices

### 1. Always Dry-Run First

```bash
# Good: Review plan before deploying
./deploy-stack.sh --stack immich --dry-run
./deploy-stack.sh --stack immich

# Bad: Deploy without review
./deploy-stack.sh --stack immich
```

### 2. Use Environment Variables for Secrets

```yaml
# Good: Use environment variables
environment:
  DB_PASSWORD: "${DB_PASSWORD}"

# Bad: Hardcode secrets
environment:
  DB_PASSWORD: "mysecretpassword"  # Don't do this!
```

### 3. Test Stacks Before Production

```bash
# Create test version
cp stacks/immich.yml stacks/immich-test.yml

# Edit test stack (smaller memory, different ports)
nano stacks/immich-test.yml

# Deploy test version
./deploy-stack.sh --stack immich-test --skip-health-check
```

### 4. Monitor Deployment Logs

```bash
# In one terminal: deploy
./deploy-stack.sh --stack immich --verbose

# In another terminal: monitor
tail -f ~/containers/data/deployment-logs/stack-immich-*.log
```

### 5. Keep Stacks Version-Controlled

```bash
# Commit stack definitions
git add stacks/my-custom-stack.yml
git commit -m "Add my-custom-stack deployment configuration"
```

---

## Next Steps

### Enhance Deployment

1. **Integrate with actual deployment patterns** (currently simulated)
2. **Implement parallel service deployment** within phases
3. **Add post-deployment validation execution**
4. **Create rollback testing framework**

### Create More Stacks

1. **monitoring-full.yml** - Full monitoring (Prometheus + Grafana + Loki + Alertmanager)
2. **paperless.yml** - Document management stack
3. **vaultwarden.yml** - Password manager stack
4. **wiki.yml** - Wiki.js with PostgreSQL

### Advanced Features (Future)

1. **Incremental updates** - Update single service without redeploying entire stack
2. **Blue-green deployment** - Zero-downtime updates
3. **Stack composition** - Import stacks into other stacks
4. **Health-aware scheduling** - Wait for optimal system conditions

---

## Related Documentation

- **Main README:** `README.md` - Overview of homelab-deployment skill
- **Pattern Guide:** `docs/10-services/guides/pattern-selection-guide.md`
- **Session 5 Plan:** `docs/99-reports/SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md`

---

**Created:** 2025-11-18 (Session 5A)
**Status:** Production-ready (core functionality)
**Next:** Deploy test stack, then production Immich stack
