---
name: homelab-deployment
description: Automated service deployment with validation, templating, and verification - use when deploying new services, updating existing deployments, or troubleshooting deployment issues
---

# Homelab Service Deployment

## Overview

Systematic service deployment workflow that eliminates common mistakes and ensures consistent, documented deployments.

**Philosophy:** Deployment should be boring, predictable, and self-documenting.

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

## Integration with Subagents

This skill integrates with specialized subagents for design decisions, verification, and cleanup:

**Before Deployment (Phase 1):**
- **infrastructure-architect** - Design network topology, security architecture, deployment pattern selection
- Invoked when: User asks "how should I deploy..." or design questions exist
- Output: Comprehensive design document with network, security, resource, and integration decisions

**After Deployment (Phase 5):**
- **service-validator** - Comprehensive 7-level verification with "assume failure" mindset
- Invoked automatically: After service starts, before documentation
- Output: Structured verification report with confidence score, pass/warn/fail status

**After Verification (Phase 5.5 - Optional):**
- **code-simplifier** - Refactor configs to maintain pattern compliance, remove bloat
- Invoked optionally: After successful verification, for config cleanup
- Output: Simplified configs aligned with homelab patterns and ADRs

**Workflow with Subagents:**
```
User Request → infrastructure-architect (design)
            ↓
    homelab-deployment (implement)
            ↓
    service-validator (verify)
            ↓
    code-simplifier (cleanup - optional)
            ↓
    Documentation + Git Commit
```

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
./.claude/skills/homelab-deployment/scripts/check-prerequisites.sh \
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
# ✓ SELinux status verified
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
   ./.claude/skills/homelab-deployment/scripts/validate-quadlet.sh \
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
# Reload systemd to recognize new quadlet
systemctl --user daemon-reload

# Enable service for auto-start
systemctl --user enable jellyfin.service

# Start service
systemctl --user start jellyfin.service

# Wait for healthy state
for i in {1..30}; do
  podman healthcheck run jellyfin && break
  sleep 2
done

# Reload Traefik (if route added)
# Traefik watches files, no manual reload needed

# Restart Prometheus (if scrape config added)
systemctl --user restart prometheus.service
```

### Phase 5: Post-Deployment Verification

**Invoke service-validator subagent for comprehensive verification:**

The service-validator subagent uses a 7-level verification framework with an "assume failure until proven otherwise" mindset:

1. **Level 1: Service Health** (CRITICAL) - Systemd active, container running, health checks passing, no crash loops, clean logs
2. **Level 2: Network Connectivity** (HIGH) - On expected networks, internal endpoint accessible, DNS resolution
3. **Level 3: External Routing** (HIGH) - Traefik route exists, external URL responds, TLS valid, security headers present
4. **Level 4: Authentication Flow** (HIGH) - Authelia redirect working, middleware chain correct
5. **Level 5: Monitoring Integration** (MEDIUM) - Prometheus scraping, Loki ingestion, Grafana dashboard
6. **Level 6: Configuration Drift** (LOW) - Running config matches quadlet definition
7. **Level 7: Security Posture** (CRITICAL) - CrowdSec active, rate limiting, no direct host exposure

**Automated verification:**

```bash
# Claude automatically invokes service-validator subagent
# Which runs: ~/.claude/skills/homelab-deployment/scripts/verify-deployment.sh

# Manual verification (if needed):
~/.claude/skills/homelab-deployment/scripts/verify-deployment.sh \
  jellyfin \
  https://jellyfin.patriark.org \
  true  # expect Authelia auth
```

**Verification outcomes:**

- **VERIFIED (>90% confidence)**: Proceed to Phase 5.5 (optional simplification), then Phase 6 (documentation)
- **WARNINGS (70-90% confidence)**: Review warnings, decide if acceptable, proceed with caution
- **FAILED (<70% confidence)**: STOP - Invoke systematic-debugging skill, investigate failures, consider rollback

**Never document failed deployments.** Verification must pass before proceeding.

### Phase 5.5: Code Simplification (Optional)

**Invoke code-simplifier subagent to refactor configs:**

After successful verification, optionally clean up configurations to maintain pattern compliance:

```bash
# Claude may invoke code-simplifier subagent
# Simplifies: Quadlet directives, Traefik routes, environment variables
# Aligns with: Homelab patterns, ADRs, template standards
```

**Simplification examples:**

- Consolidate duplicate volume mounts
- Use systemd variables (%h for home directory)
- Deduplicate middleware chains in Traefik
- Remove commented-out configuration
- Align with pattern templates

**Safety:**
- BTRFS snapshot created before simplification
- Service restarted and re-verified after changes
- Rollback if re-verification fails

**Skip simplification if:**
- First deployment for this pattern (let it stabilize first)
- Security-critical configs (don't simplify Authelia, CrowdSec)
- Workarounds for known issues
- Config less than 24 hours old

### Phase 6: Documentation

**Generate documentation automatically:**

1. **Service Guide** (docs/10-services/guides/jellyfin.md)
   - Service description
   - Configuration details
   - Network topology
   - Management commands
   - Troubleshooting

2. **Deployment Journal** (docs/10-services/journal/YYYY-MM-DD-jellyfin-deployment.md)
   - Deployment timestamp
   - Configuration used
   - Verification results
   - Issues encountered
   - Resolution steps

3. **Update CLAUDE.md**
   - Add service to Common Commands section
   - Add to Troubleshooting section if needed

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
# Stop service
systemctl --user stop jellyfin.service

# Disable service
systemctl --user disable jellyfin.service

# Remove container
podman rm jellyfin

# Remove quadlet
rm ~/.config/containers/systemd/jellyfin.container

# Remove Traefik route
rm ~/containers/config/traefik/dynamic/jellyfin-router.yml

# Reload systemd
systemctl --user daemon-reload

# Document rollback reason
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

**IMPORTANT: First network determines default route (internet access)!**

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
