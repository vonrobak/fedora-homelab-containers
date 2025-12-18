# Homelab-Deployment Skill: Implementation Plan

**Date:** 2025-11-13
**Context:** Building the highest-ROI Claude Code skill for automated service deployment
**Priority:** CRITICAL - Foundation for autonomous operations
**Estimated Effort:** 6-8 hours (1-2 sessions)

---

## Executive Summary

The homelab-deployment skill will transform service deployment from manual, error-prone processes (OCIS took 5 iterations) to systematic, validated workflows. This is the **highest ROI skill** identified in the strategic assessment.

**Expected Impact:**
- Deployment time: 30-60 min → 10-15 min
- Error rate: ~40% → <5%
- Documentation: Manual → Auto-generated
- Consistency: Ad-hoc → Standardized

**Philosophy:** Deployment should be boring, predictable, and self-documenting.

---

## Skill Architecture

### Directory Structure

```
.claude/skills/homelab-deployment/
├── SKILL.md                              # Main skill definition
├── README.md                             # Skill documentation
├── templates/                            # Deployment templates
│   ├── quadlets/
│   │   ├── web-app.container            # Standard web application
│   │   ├── database.container           # Database service
│   │   ├── monitoring-service.container # Monitoring component
│   │   └── background-worker.container  # Background job service
│   ├── traefik/
│   │   ├── public-service.yml           # Public web service route
│   │   ├── authenticated-service.yml    # Auth-required service
│   │   ├── admin-service.yml            # Admin panel (strict security)
│   │   └── api-service.yml              # API with CORS
│   ├── prometheus/
│   │   └── service-scrape-config.yml    # Prometheus scrape job
│   └── documentation/
│       ├── service-guide.md             # docs/10-services/guides/ template
│       └── deployment-journal.md        # docs/10-services/journal/ template
├── scripts/
│   ├── validate-quadlet.sh              # Pre-deployment validation
│   ├── check-prerequisites.sh           # Environment checks
│   ├── deploy-service.sh                # Main deployment orchestrator
│   ├── test-deployment.sh               # Post-deployment verification
│   └── rollback-deployment.sh           # Rollback failed deployment
├── references/
│   ├── common-patterns.md               # Web app, database, monitoring patterns
│   ├── network-selection-guide.md       # Which networks for which services
│   ├── security-checklist.md            # Security validation
│   └── troubleshooting-guide.md         # Common deployment issues
└── examples/
    ├── jellyfin-deployment.md           # Real-world example: Media server
    ├── vaultwarden-deployment.md        # Real-world example: Password manager
    └── monitoring-service-deployment.md # Real-world example: Prometheus exporter
```

---

## Phase 1: Core Skill Definition (SKILL.md)

### Skill Metadata

```yaml
---
name: homelab-deployment
description: Automated service deployment with validation, templating, and verification - use when deploying new services, updating existing deployments, or troubleshooting deployment issues (project)
---
```

### Skill Content Structure

```markdown
# Homelab Service Deployment

## Overview

Systematic service deployment workflow that eliminates common mistakes and ensures consistent, documented deployments.

## When to Use

**Always use for:**
- Deploying new services
- Updating existing service configurations
- Troubleshooting deployment failures
- Validating deployment before execution
- Rolling back failed deployments

**Triggers:**
- User asks to "deploy <service>"
- User mentions service won't start after deployment
- User asks "how do I deploy a new service?"
- User requests deployment validation

## Core Principle

**Every deployment follows the same workflow:**
1. Validate prerequisites
2. Generate configuration from templates
3. Deploy and verify
4. Document changes

**No ad-hoc deployments. No manual config editing without validation.**

## The Deployment Workflow

### Phase 1: Discovery & Planning

**Gather information about the service:**

1. **Service Identity**
   - Name (container name, service name)
   - Image (registry/image:tag)
   - Purpose (media server, database, auth service, etc.)
   - Documentation link (official docs)

2. **Resource Requirements**
   - Memory limits
   - CPU shares
   - Disk space
   - Special hardware (GPU, etc.)

3. **Network Requirements**
   - Which networks? (Use network-selection-guide.md)
   - Does it need reverse proxy access?
   - Does it need database access?
   - Does it need monitoring?
   - Does it expose metrics?

4. **Security Requirements**
   - Public or authenticated?
   - Which middleware? (CrowdSec, rate limiting, Authelia)
   - Sensitive data handling
   - Secrets management

5. **Storage Requirements**
   - Configuration files location
   - Data storage location
   - Database storage (NOCOW needed?)
   - Media files (large files)
   - Logs

6. **Dependencies**
   - Database required?
   - Cache required? (Redis)
   - Other services?
   - Network creation needed?

### Phase 2: Pre-Deployment Validation

**Run checks BEFORE any deployment:**

```bash
# Execute validation script
./claude/skills/homelab-deployment/scripts/check-prerequisites.sh \
  --service-name jellyfin \
  --image docker.io/jellyfin/jellyfin:latest \
  --networks systemd-reverse_proxy,systemd-media_services,systemd-monitoring \
  --ports 8096 \
  --config-dir ~/containers/config/jellyfin \
  --data-dir ~/containers/data/jellyfin

# Validation checklist:
# ✓ Image exists in registry
# ✓ Networks exist
# ✓ Ports available (not in use)
# ✓ Config directory created
# ✓ Data directory created with correct permissions
# ✓ Parent directories exist
# ✓ Sufficient disk space
# ✓ No conflicting services
# ✓ DNS resolves (for external dependencies)
```

**If validation fails, STOP. Fix issues before proceeding.**

### Phase 3: Configuration Generation

**Generate configuration from templates:**

1. **Select Template Pattern**
   - Web application → `templates/quadlets/web-app.container`
   - Database → `templates/quadlets/database.container`
   - Monitoring → `templates/quadlets/monitoring-service.container`
   - Background worker → `templates/quadlets/background-worker.container`

2. **Customize Quadlet**
   ```bash
   # Copy template
   cp .claude/skills/homelab-deployment/templates/quadlets/web-app.container \
      ~/.config/containers/systemd/jellyfin.container

   # Substitute values
   sed -i "s/{{SERVICE_NAME}}/jellyfin/g" ~/.config/containers/systemd/jellyfin.container
   sed -i "s|{{IMAGE}}|docker.io/jellyfin/jellyfin:latest|g" ~/.config/containers/systemd/jellyfin.container
   sed -i "s/{{MEMORY_LIMIT}}/4G/g" ~/.config/containers/systemd/jellyfin.container
   # ... etc
   ```

3. **Validate Quadlet Syntax**
   ```bash
   # Run validation
   ./claude/skills/homelab-deployment/scripts/validate-quadlet.sh \
     ~/.config/containers/systemd/jellyfin.container

   # Checks:
   # ✓ Valid INI syntax
   # ✓ Required fields present
   # ✓ Network names match systemd- prefix
   # ✓ Volume paths use :Z SELinux labels
   # ✓ Health check defined
   # ✓ Resource limits set
   ```

4. **Generate Traefik Route** (if externally accessible)
   ```bash
   # Select template based on security tier
   # Public → templates/traefik/public-service.yml
   # Authenticated → templates/traefik/authenticated-service.yml
   # Admin → templates/traefik/admin-service.yml
   # API → templates/traefik/api-service.yml

   # Customize route
   cp .claude/skills/homelab-deployment/templates/traefik/authenticated-service.yml \
      ~/containers/config/traefik/dynamic/jellyfin-router.yml

   # Substitute values
   sed -i "s/{{SERVICE_NAME}}/jellyfin/g" ~/containers/config/traefik/dynamic/jellyfin-router.yml
   sed -i "s/{{HOSTNAME}}/jellyfin.patriark.org/g" ~/containers/config/traefik/dynamic/jellyfin-router.yml
   sed -i "s/{{PORT}}/8096/g" ~/containers/config/traefik/dynamic/jellyfin-router.yml
   ```

5. **Generate Prometheus Scrape Config** (if metrics exposed)
   ```bash
   # Add to prometheus.yml
   # Template: templates/prometheus/service-scrape-config.yml
   ```

### Phase 4: Deployment Execution

**Deploy the service:**

```bash
# Execute deployment
./claude/skills/homelab-deployment/scripts/deploy-service.sh \
  --service jellyfin \
  --wait-for-healthy

# Deployment steps (automated):
# 1. Create container from quadlet
#    systemctl --user daemon-reload
#
# 2. Enable service persistence
#    systemctl --user enable jellyfin.service
#
# 3. Start service
#    systemctl --user start jellyfin.service
#
# 4. Wait for healthy state
#    for i in {1..30}; do
#      podman healthcheck run jellyfin && break
#      sleep 2
#    done
#
# 5. Reload Traefik (if route added)
#    # Traefik watches files, no manual reload needed
#
# 6. Restart Prometheus (if scrape config added)
#    systemctl --user restart prometheus.service
```

### Phase 5: Post-Deployment Verification

**Verify deployment succeeded:**

```bash
# Execute verification
./claude/skills/homelab-deployment/scripts/test-deployment.sh \
  --service jellyfin \
  --internal-port 8096 \
  --external-url https://jellyfin.patriark.org \
  --expect-auth

# Verification checklist:
# ✓ Service running
# ✓ Health check passing
# ✓ Internal endpoint accessible (curl http://localhost:8096/)
# ✓ Traefik route exists in dashboard
# ✓ External URL accessible (curl https://jellyfin.patriark.org)
# ✓ Authentication working (redirect to Authelia)
# ✓ Monitoring scraping (Prometheus target UP)
# ✓ Logs clean (no errors in journalctl)
```

**If verification fails, investigate with systematic-debugging skill.**

### Phase 6: Documentation

**Generate documentation automatically:**

1. **Service Guide** (docs/10-services/guides/jellyfin.md)
   ```bash
   # Generate from template
   ./claude/skills/homelab-deployment/scripts/generate-docs.sh \
     --service jellyfin \
     --type guide \
     --output docs/10-services/guides/jellyfin.md

   # Auto-populated with:
   # - Service description
   # - Configuration details
   # - Network topology
   # - Management commands
   # - Troubleshooting
   ```

2. **Deployment Journal** (docs/10-services/journal/YYYY-MM-DD-jellyfin-deployment.md)
   ```bash
   # Generate deployment log
   ./claude/skills/homelab-deployment/scripts/generate-docs.sh \
     --service jellyfin \
     --type journal \
     --output docs/10-services/journal/$(date +%Y-%m-%d)-jellyfin-deployment.md

   # Auto-populated with:
   # - Deployment timestamp
   # - Configuration used
   # - Verification results
   # - Issues encountered
   # - Resolution steps
   ```

3. **Update CLAUDE.md**
   ```bash
   # Add service to Common Commands section
   # Add to Troubleshooting section if needed
   ```

### Phase 7: Git Commit

**Commit deployment changes:**

```bash
# Add all deployment artifacts
git add ~/.config/containers/systemd/jellyfin.container
git add ~/containers/config/traefik/dynamic/jellyfin-router.yml
git add ~/containers/config/prometheus/prometheus.yml  # if modified
git add docs/10-services/guides/jellyfin.md
git add docs/10-services/journal/$(date +%Y-%m-%d)-jellyfin-deployment.md

# Commit with structured message
git commit -m "$(cat <<'EOF'
Deploy Jellyfin media server

- Add quadlet configuration (4G memory, systemd networks)
- Configure Traefik route with Authelia authentication
- Add Prometheus scrape target
- Generate service documentation

Configuration:
  Image: docker.io/jellyfin/jellyfin:latest
  Networks: reverse_proxy, media_services, monitoring
  Middleware: CrowdSec → Rate limit → Authelia

Verification: ✓ Service healthy, ✓ External access working
EOF
)"

# Push changes
git push origin main
```

## Rollback Procedure

**If deployment fails:**

```bash
# Execute rollback
./claude/skills/homelab-deployment/scripts/rollback-deployment.sh \
  --service jellyfin

# Rollback steps:
# 1. Stop service
#    systemctl --user stop jellyfin.service
#
# 2. Disable service
#    systemctl --user disable jellyfin.service
#
# 3. Remove container
#    podman rm jellyfin
#
# 4. Remove quadlet
#    rm ~/.config/containers/systemd/jellyfin.container
#
# 5. Remove Traefik route
#    rm ~/containers/config/traefik/dynamic/jellyfin-router.yml
#
# 6. Reload systemd
#    systemctl --user daemon-reload
#
# 7. Document rollback reason
```

## Integration with Other Skills

**This skill works with:**

- **systematic-debugging**: Use when deployment fails
- **homelab-intelligence**: Verify system health before deployment
- **git-advanced-workflows**: Clean commit history
- **security-audit** (future): Validate security configuration

## Templates Reference

### Quadlet Template Variables

**All templates support these substitutions:**

```
{{SERVICE_NAME}}     - Container/service name
{{IMAGE}}            - Container image (registry/name:tag)
{{MEMORY_LIMIT}}     - Memory limit (e.g., 4G)
{{MEMORY_HIGH}}      - Memory high watermark (e.g., 3G)
{{CPU_SHARES}}       - CPU shares (optional)
{{NICE}}             - Process priority (optional)
{{CONFIG_DIR}}       - Configuration directory path
{{DATA_DIR}}         - Data directory path
{{NETWORKS}}         - Comma-separated network list
{{PORTS}}            - Exposed ports
{{ENVIRONMENT}}      - Environment variables
{{HEALTH_CMD}}       - Health check command
```

### Network Selection Guide

**Use this decision tree:**

```
Service needs external access (web UI/API)?
  YES → Add systemd-reverse_proxy
  NO  → Skip

Service needs database access?
  YES → Add systemd-database (if exists) or service-specific network
  NO  → Skip

Service provides/consumes metrics?
  YES → Add systemd-monitoring
  NO  → Skip

Service handles authentication?
  YES → Add systemd-auth_services
  NO  → Skip

Service processes media?
  YES → Add systemd-media_services
  NO  → Skip

Service manages photos?
  YES → Add systemd-photos
  NO  → Skip
```

**First network determines default route (internet access)!**

### Middleware Selection Guide

**Security tiers:**

```
PUBLIC SERVICE (no auth required):
  crowdsec-bouncer@file
  rate-limit-public@file
  security-headers-public@file

AUTHENTICATED SERVICE (standard):
  crowdsec-bouncer@file
  rate-limit@file
  authelia@file
  security-headers@file

ADMIN SERVICE (strict):
  crowdsec-bouncer@file
  admin-whitelist@file
  rate-limit-strict@file
  authelia@file
  security-headers-strict@file

API SERVICE:
  crowdsec-bouncer@file
  rate-limit@file
  cors-headers@file
  authelia@file
  security-headers@file

INTERNAL ONLY:
  internal-only@file
  rate-limit@file
  security-headers@file
```

## Common Patterns

### Pattern 1: Web Application with Database

**Components:**
1. Database service (PostgreSQL/MySQL/Redis)
2. Web application service
3. Traefik route
4. Prometheus scraping (optional)

**Network topology:**
```
Database:     systemd-database (internal only)
Web app:      systemd-reverse_proxy, systemd-database, systemd-monitoring
Traefik:      systemd-reverse_proxy (already configured)
Prometheus:   systemd-monitoring (already configured)
```

**Example:** Vaultwarden (password manager)

### Pattern 2: Monitoring Service

**Components:**
1. Monitoring service (exporter, scraper, etc.)
2. Prometheus scrape config
3. Grafana dashboard (optional)

**Network topology:**
```
Service:      systemd-monitoring
Prometheus:   systemd-monitoring
```

**Example:** Node Exporter, cAdvisor

### Pattern 3: Media Processing Service

**Components:**
1. Media service
2. Traefik route with optional auth
3. Large storage volumes
4. Optional transcoding (GPU access)

**Network topology:**
```
Service:      systemd-reverse_proxy, systemd-media_services, systemd-monitoring
```

**Example:** Jellyfin, Plex, Immich

### Pattern 4: Authentication Service

**Components:**
1. Auth service
2. Session storage (Redis)
3. Traefik ForwardAuth configuration
4. User database

**Network topology:**
```
Auth service: systemd-reverse_proxy, systemd-auth_services
Redis:        systemd-auth_services
```

**Example:** Authelia, Authentik

## Error Handling

**Common deployment errors and solutions:**

### Error: "Network not found"

**Cause:** Network doesn't exist or wrong name

**Solution:**
```bash
# Check existing networks
podman network ls

# Create network if needed
podman network create systemd-<name>

# Fix quadlet network name (must start with systemd-)
sed -i 's/Network=reverse_proxy/Network=systemd-reverse_proxy/' \
  ~/.config/containers/systemd/service.container
```

### Error: "Permission denied" on volume mount

**Cause:** Missing `:Z` SELinux label

**Solution:**
```bash
# Fix volume mount in quadlet
sed -i 's|:/config|:/config:Z|' ~/.config/containers/systemd/service.container
sed -i 's|:/data|:/data:Z|' ~/.config/containers/systemd/service.container
```

### Error: "Port already in use"

**Cause:** Another service using the port

**Solution:**
```bash
# Find what's using the port
ss -tulnp | grep <port>

# Change service port OR stop conflicting service
```

### Error: "Service fails health check"

**Cause:** Health check command incorrect or service not ready

**Solution:**
```bash
# Check service logs
journalctl --user -u service.service -n 50

# Verify health check command
podman inspect service | grep -A 5 Healthcheck

# Test health check manually
podman healthcheck run service

# Increase health check timeout if needed
```

### Error: "Traefik 502 Bad Gateway"

**Cause:** Service not reachable from Traefik

**Solution:**
```bash
# 1. Verify service running
systemctl --user status service.service

# 2. Check networks match
podman network inspect systemd-reverse_proxy | grep traefik
podman network inspect systemd-reverse_proxy | grep service

# 3. Test from Traefik container
podman exec traefik wget -O- http://service:port/

# 4. Check Traefik logs
podman logs traefik | grep service
```

## Success Criteria

**Deployment is complete when:**

- [ ] Service running and healthy
- [ ] Internal endpoint accessible
- [ ] External URL accessible (if public)
- [ ] Authentication working (if required)
- [ ] Monitoring configured (if applicable)
- [ ] Documentation generated
- [ ] Git commit created
- [ ] No errors in logs

## Notes

- Always validate before deploying
- Use templates, don't create from scratch
- Document as you deploy
- Test thoroughly before considering complete
- Roll back if verification fails

---

**This skill ensures every deployment is systematic, validated, and documented.**
```

---

## Phase 2: Template Creation

### Template 1: Web Application Quadlet

**File:** `templates/quadlets/web-app.container`

```ini
# ~/.config/containers/systemd/{{SERVICE_NAME}}.container
# Generated by homelab-deployment skill

# ═══════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════
[Unit]
Description={{SERVICE_DESCRIPTION}}
Documentation={{DOCS_URL}}
After=network-online.target
Wants=network-online.target

# ═══════════════════════════════════════════════
# CONTAINER CONFIGURATION
# ═══════════════════════════════════════════════
[Container]
Image={{IMAGE}}
ContainerName={{SERVICE_NAME}}
AutoUpdate=registry

# Networks (first network provides default route)
{{#NETWORKS}}
Network={{NETWORK}}
{{/NETWORKS}}

# Volumes
Volume={{CONFIG_DIR}}:/config:Z
Volume={{DATA_DIR}}:/data:Z
{{#ADDITIONAL_VOLUMES}}
Volume={{VOLUME}}
{{/ADDITIONAL_VOLUMES}}

# Environment variables
{{#ENVIRONMENT}}
Environment={{ENV_VAR}}
{{/ENVIRONMENT}}

# Ports (for internal access, Traefik handles external)
{{#PORTS}}
PublishPort={{PORT}}
{{/PORTS}}

# Health check
HealthCmd={{HEALTH_CMD}}
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3

# Resource limits
[Service]
MemoryMax={{MEMORY_LIMIT}}
MemoryHigh={{MEMORY_HIGH}}
{{#CPU_SHARES}}
CPUShares={{CPU_SHARES}}
{{/CPU_SHARES}}
{{#NICE}}
Nice={{NICE}}
{{/NICE}}

# Service behavior
Restart=on-failure
RestartSec=30s
TimeoutStartSec=300
TimeoutStopSec=60

# ═══════════════════════════════════════════════
# INSTALLATION
# ═══════════════════════════════════════════════
[Install]
WantedBy=default.target
```

### Template 2: Authenticated Traefik Route

**File:** `templates/traefik/authenticated-service.yml`

```yaml
# ~/containers/config/traefik/dynamic/{{SERVICE_NAME}}-router.yml
# Generated by homelab-deployment skill

http:
  routers:
    {{SERVICE_NAME}}-secure:
      rule: "Host(`{{HOSTNAME}}`)"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer@file      # 1. Block bad IPs
        - rate-limit@file             # 2. Prevent abuse
        - authelia@file               # 3. Authenticate
        - security-headers@file       # 4. Security headers
      service: {{SERVICE_NAME}}-service
      tls:
        certResolver: letsencrypt

  services:
    {{SERVICE_NAME}}-service:
      loadBalancer:
        servers:
          - url: "http://{{SERVICE_NAME}}:{{PORT}}"
        healthCheck:
          path: "{{HEALTH_PATH}}"
          interval: "30s"
          timeout: "10s"
```

### Template 3: Service Guide Documentation

**File:** `templates/documentation/service-guide.md`

```markdown
# {{SERVICE_NAME}} - {{SERVICE_DESCRIPTION}}

**Last Updated:** {{TIMESTAMP}}
**Maintainer:** Claude Code (auto-generated)

## Overview

{{SERVICE_PURPOSE}}

**Access:** {{#PUBLIC}}https://{{HOSTNAME}}{{/PUBLIC}}{{^PUBLIC}}Internal only{{/PUBLIC}}
**Status:** {{#MONITORING}}Monitored via Prometheus{{/MONITORING}}
**Authentication:** {{#AUTH_REQUIRED}}Authelia SSO required{{/AUTH_REQUIRED}}{{^AUTH_REQUIRED}}Public{{/AUTH_REQUIRED}}

## Configuration

**Container:**
- Image: `{{IMAGE}}`
- Memory: {{MEMORY_LIMIT}}
- Networks: {{NETWORKS}}

**Storage:**
- Config: `{{CONFIG_DIR}}`
- Data: `{{DATA_DIR}}`

**Traefik Route:**
{{#TRAEFIK_ENABLED}}
- Hostname: `{{HOSTNAME}}`
- Middleware: {{MIDDLEWARE_CHAIN}}
- TLS: Let's Encrypt
{{/TRAEFIK_ENABLED}}
{{^TRAEFIK_ENABLED}}
- Not externally accessible
{{/TRAEFIK_ENABLED}}

## Management Commands

```bash
# Start service
systemctl --user start {{SERVICE_NAME}}.service

# Stop service
systemctl --user stop {{SERVICE_NAME}}.service

# Restart service
systemctl --user restart {{SERVICE_NAME}}.service

# View status
systemctl --user status {{SERVICE_NAME}}.service

# View logs
journalctl --user -u {{SERVICE_NAME}}.service -f

# Check health
podman healthcheck run {{SERVICE_NAME}}

# Access container shell
podman exec -it {{SERVICE_NAME}} /bin/bash
```

## Troubleshooting

### Service won't start

```bash
# Check systemd status
systemctl --user status {{SERVICE_NAME}}.service

# Check container logs
podman logs {{SERVICE_NAME}} --tail 50

# Verify configuration
cat ~/.config/containers/systemd/{{SERVICE_NAME}}.container

# Check network connectivity
podman network inspect {{PRIMARY_NETWORK}} | grep {{SERVICE_NAME}}
```

### Can't access via web

{{#TRAEFIK_ENABLED}}
```bash
# Check Traefik routing
podman logs traefik | grep {{SERVICE_NAME}}

# Verify route exists
curl -I https://{{HOSTNAME}}

# Test internal access
curl -I http://localhost:{{PORT}}/
```
{{/TRAEFIK_ENABLED}}

### High resource usage

```bash
# Check current resource usage
podman stats {{SERVICE_NAME}}

# View historical metrics (Grafana)
# Navigate to Service Health dashboard
```

## Related Documentation

- Deployment: `docs/10-services/journal/{{DEPLOYMENT_DATE}}-{{SERVICE_NAME}}-deployment.md`
- Architecture: `CLAUDE.md` - Services section
{{#ADR_REFERENCE}}
- Architecture Decision: `{{ADR_PATH}}`
{{/ADR_REFERENCE}}

## Quick Reference

| Property | Value |
|----------|-------|
| Container Name | {{SERVICE_NAME}} |
| Image | {{IMAGE}} |
| Internal Port | {{PORT}} |
| External URL | {{#PUBLIC}}https://{{HOSTNAME}}{{/PUBLIC}}{{^PUBLIC}}N/A{{/PUBLIC}} |
| Health Check | {{HEALTH_CMD}} |
| Memory Limit | {{MEMORY_LIMIT}} |
| Deployed | {{DEPLOYMENT_DATE}} |
```

---

## Phase 3: Script Implementation

### Script 1: Prerequisites Checker

**File:** `scripts/check-prerequisites.sh`

```bash
#!/usr/bin/env bash
# Pre-deployment validation
# Checks environment is ready for deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Parse arguments
SERVICE_NAME=""
IMAGE=""
NETWORKS=""
PORTS=""
CONFIG_DIR=""
DATA_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --service-name) SERVICE_NAME="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --networks) NETWORKS="$2"; shift 2 ;;
        --ports) PORTS="$2"; shift 2 ;;
        --config-dir) CONFIG_DIR="$2"; shift 2 ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "Pre-Deployment Validation: $SERVICE_NAME"
echo "=========================================="
echo ""

# Check 1: Image exists
echo "Checking image availability..."
if podman image exists "$IMAGE" 2>/dev/null || \
   podman pull "$IMAGE" &>/dev/null; then
    check_pass "Image exists or pulled successfully: $IMAGE"
else
    check_fail "Image not found: $IMAGE"
fi

# Check 2: Networks exist
echo ""
echo "Checking networks..."
IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS"
for network in "${NETWORK_ARRAY[@]}"; do
    if podman network exists "$network" 2>/dev/null; then
        check_pass "Network exists: $network"
    else
        check_fail "Network not found: $network"
        echo "  Create with: podman network create $network"
    fi
done

# Check 3: Ports available
echo ""
echo "Checking port availability..."
IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
for port in "${PORT_ARRAY[@]}"; do
    if ! ss -tulnp 2>/dev/null | grep -q ":$port "; then
        check_pass "Port available: $port"
    else
        check_fail "Port already in use: $port"
        echo "  In use by: $(ss -tulnp 2>/dev/null | grep ":$port " | awk '{print $6}')"
    fi
done

# Check 4: Directories
echo ""
echo "Checking directories..."
for dir in "$CONFIG_DIR" "$DATA_DIR"; do
    if [[ -d "$dir" ]]; then
        check_pass "Directory exists: $dir"
    else
        check_warn "Directory missing: $dir (will be created)"
        mkdir -p "$dir" 2>/dev/null && \
            check_pass "Created directory: $dir" || \
            check_fail "Failed to create: $dir"
    fi
done

# Check 5: Disk space
echo ""
echo "Checking disk space..."
SYSTEM_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $SYSTEM_USAGE -lt 80 ]]; then
    check_pass "System disk usage: ${SYSTEM_USAGE}%"
else
    check_fail "System disk critically full: ${SYSTEM_USAGE}%"
    echo "  Run cleanup before deploying"
fi

# Check 6: No conflicting service
echo ""
echo "Checking for conflicts..."
if podman ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    check_fail "Container already exists: $SERVICE_NAME"
    echo "  Remove with: podman rm $SERVICE_NAME"
elif systemctl --user list-units --all | grep -q "${SERVICE_NAME}.service"; then
    check_fail "Service already exists: ${SERVICE_NAME}.service"
    echo "  Check with: systemctl --user status ${SERVICE_NAME}.service"
else
    check_pass "No conflicting services found"
fi

# Check 7: SELinux
echo ""
echo "Checking security..."
SELINUX=$(getenforce 2>/dev/null || echo "Unknown")
if [[ "$SELINUX" == "Enforcing" ]]; then
    check_pass "SELinux enforcing (volume labels required)"
else
    check_warn "SELinux not enforcing: $SELINUX"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary:"
echo "  Passed: $CHECKS_PASSED"
echo "  Failed: $CHECKS_FAILED"
echo ""

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed. Ready to deploy.${NC}"
    exit 0
else
    echo -e "${RED}✗ $CHECKS_FAILED check(s) failed. Fix issues before deploying.${NC}"
    exit 1
fi
```

### Script 2: Quadlet Validator

**File:** `scripts/validate-quadlet.sh`

```bash
#!/usr/bin/env bash
# Validate quadlet syntax and best practices

set -euo pipefail

QUADLET_FILE="$1"

if [[ ! -f "$QUADLET_FILE" ]]; then
    echo "Error: File not found: $QUADLET_FILE"
    exit 1
fi

echo "Validating quadlet: $QUADLET_FILE"
echo "=========================================="

ERRORS=0
WARNINGS=0

# Check INI syntax
if ! grep -q '^\[Unit\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Container\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Service\]' "$QUADLET_FILE" || \
   ! grep -q '^\[Install\]' "$QUADLET_FILE"; then
    echo "✗ Missing required sections"
    ((ERRORS++))
else
    echo "✓ All required sections present"
fi

# Check network naming
if grep -q '^Network=' "$QUADLET_FILE"; then
    if grep '^Network=' "$QUADLET_FILE" | grep -q 'systemd-'; then
        echo "✓ Network names use systemd- prefix"
    else
        echo "✗ Network names missing systemd- prefix"
        ((ERRORS++))
    fi
fi

# Check SELinux labels
if grep -q '^Volume=' "$QUADLET_FILE"; then
    if grep '^Volume=' "$QUADLET_FILE" | grep -qv ':Z'; then
        echo "⚠ Some volumes missing :Z SELinux label"
        ((WARNINGS++))
    else
        echo "✓ All volumes have SELinux labels"
    fi
fi

# Check health check
if grep -q '^HealthCmd=' "$QUADLET_FILE"; then
    echo "✓ Health check defined"
else
    echo "⚠ No health check defined"
    ((WARNINGS++))
fi

# Check resource limits
if grep -q '^MemoryMax=' "$QUADLET_FILE"; then
    echo "✓ Memory limit set"
else
    echo "⚠ No memory limit"
    ((WARNINGS++))
fi

echo ""
echo "Validation complete:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"

if [[ $ERRORS -eq 0 ]]; then
    echo "✓ Quadlet is valid"
    exit 0
else
    echo "✗ Fix errors before deploying"
    exit 1
fi
```

---

## Phase 4: Testing Strategy

### Test 1: Deploy Test Service

**Service:** httpbin (simple HTTP testing service)

```bash
# Deploy using skill
"Deploy httpbin service at test.patriark.org"

# Expected workflow:
# 1. Skill gathers info about httpbin
# 2. Validates prerequisites
# 3. Generates quadlet from web-app template
# 4. Generates Traefik route
# 5. Deploys and verifies
# 6. Generates documentation

# Verification:
curl https://test.patriark.org/get
# Should return JSON response
```

### Test 2: Deploy with Database

**Service:** PostgreSQL + web app (e.g., Wiki.js)

```bash
# Deploy database first
"Deploy PostgreSQL database for wiki"

# Deploy web app
"Deploy Wiki.js connected to PostgreSQL"

# Expected workflow:
# 1. Create systemd-database network (if not exists)
# 2. Deploy PostgreSQL on systemd-database
# 3. Deploy Wiki.js on systemd-reverse_proxy + systemd-database
# 4. Configure Traefik
# 5. Verify connectivity
```

### Test 3: Rollback Failed Deployment

**Scenario:** Deploy service with incorrect config

```bash
# Deploy with wrong port
"Deploy service-test with port 99999"

# Health check fails
# Skill detects failure
# Triggers rollback automatically

# Verification:
# - Service removed
# - Quadlet deleted
# - Traefik route removed
```

### Test 4: Documentation Generation

**Verify:**
- Service guide created in `docs/10-services/guides/`
- Deployment journal created in `docs/10-services/journal/`
- CLAUDE.md updated with service commands

---

## Phase 5: Success Metrics

### Deployment Time Reduction

**Baseline (Manual):**
- Planning: 5-10 min
- Configuration: 10-20 min
- Testing: 5-10 min
- Fixing mistakes: 10-30 min
- Documentation: 10-15 min
- **Total: 40-85 min**

**With Skill:**
- Planning: 2-3 min (skill asks questions)
- Validation: 1 min (automated)
- Configuration: 2 min (template-based)
- Deployment: 2-3 min (automated)
- Verification: 2-3 min (automated)
- Documentation: 1 min (auto-generated)
- **Total: 10-15 min**

**Time Savings: 70-80%**

### Error Rate Reduction

**Manual Deployment Errors (from OCIS experience):**
1. Network naming (systemd-reverse_proxy.network)
2. Missing secrets
3. Permission errors
4. Initialization steps
5. Middleware conflicts

**Expected Error Rate:**
- Manual: ~40% (2 out of 5 attempts fail)
- With skill: <5% (validation prevents most errors)

**Error Reduction: 87.5%**

### Consistency Improvement

**Measured by:**
- All services follow same pattern: YES/NO
- Documentation always generated: YES/NO
- Security best practices applied: YES/NO
- Git commits structured: YES/NO

**Target: 100% consistency**

---

## Implementation Timeline

### Session 1: Foundation (2-3 hours)

**Tasks:**
1. Create skill structure (directories)
2. Write SKILL.md (core skill definition)
3. Create web-app quadlet template
4. Create authenticated Traefik route template
5. Write check-prerequisites.sh script

**Deliverables:**
- Basic skill structure
- First working template
- Prerequisites validation

### Session 2: Templates & Scripts (2-3 hours)

**Tasks:**
1. Create remaining quadlet templates (database, monitoring, worker)
2. Create Traefik route templates (public, admin, API)
3. Write validate-quadlet.sh script
4. Write deploy-service.sh orchestrator
5. Write test-deployment.sh verifier

**Deliverables:**
- Complete template library
- Full deployment automation

### Session 3: Documentation & Testing (2-3 hours)

**Tasks:**
1. Create documentation templates
2. Write generate-docs.sh script
3. Write rollback-deployment.sh script
4. Test with httpbin deployment
5. Test with real service (e.g., new monitoring exporter)
6. Refine based on learnings

**Deliverables:**
- Auto-documentation working
- Tested with real deployments
- Production-ready skill

**Total Estimated Time: 6-9 hours**

---

## Next Steps

### Immediate (This Session)

1. Create skill directory structure
2. Write SKILL.md outline
3. Create first template (web-app.container)
4. Write check-prerequisites.sh

### Next Session

1. Complete remaining templates
2. Write deployment scripts
3. Test with httpbin

### Future Enhancements

1. Interactive deployment wizard
2. Deployment preview (dry-run mode)
3. Configuration diff (compare with existing)
4. Deployment history tracking
5. One-command rollback to previous version
6. Integration with homelab-intelligence (pre-flight check)

---

## Conclusion

The homelab-deployment skill will transform service deployment from error-prone, time-consuming manual work to systematic, validated, automated workflows.

**Key Benefits:**
- 70-80% time savings
- 87.5% error reduction
- 100% consistency
- Auto-generated documentation
- Rollback capability
- Integration with existing skills

**This is the foundation for autonomous infrastructure management.**

---

**Implementation Plan Version:** 1.0
**Created:** 2025-11-13
**Status:** Ready for implementation
**Priority:** CRITICAL - Highest ROI skill
