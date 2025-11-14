# ADR-007: Pattern-Based Deployment Automation

**Date:** 2025-11-14
**Status:** Accepted
**Supersedes:** Manual deployment via service-specific bash scripts

## Context

Prior to Session 3 (2025-11-14), service deployment followed ad-hoc approaches:

1. **Service-specific scripts** - Individual deployment scripts (e.g., `deploy-jellyfin-with-traefik.sh`)
2. **Manual quadlet creation** - Copy-paste-modify from existing services
3. **Inconsistent patterns** - Each deployment slightly different
4. **No validation** - Manual checks for prerequisites, health, drift
5. **No reusability** - Similar services (databases, web apps) deployed from scratch each time

**Problems identified:**
- **High cognitive load** - Each deployment requires remembering all best practices
- **Human error prone** - Easy to forget BTRFS NOCOW, network ordering, Traefik labels
- **No health awareness** - Deployments proceed even when system unhealthy
- **Configuration drift** - No mechanism to detect running container vs quadlet mismatches
- **Knowledge loss** - Best practices lived in ad-hoc scripts, not reusable patterns

**Session 3 delivered:**
- 9 deployment patterns (YAML-based templates)
- `deploy-from-pattern.sh` orchestrator
- `check-drift.sh` drift detection
- `check-system-health.sh` health integration
- Comprehensive documentation (guides, cookbook, integration guide)

**Requirements:**
- Consistent deployment experience across service types
- Validation before deployment (health, prerequisites)
- Capture best practices in reusable patterns
- Support customization without abandoning patterns
- Drift detection to maintain configuration accuracy

## Decision

**Adopt pattern-based deployment as the PRIMARY deployment method** for all future services using the homelab-deployment Claude Code skill.

### Deployment Workflow

**Standard deployment:**
```bash
cd .claude/skills/homelab-deployment

# 1. Check system health (automatic or manual)
./scripts/check-system-health.sh

# 2. Deploy from pattern
./scripts/deploy-from-pattern.sh \
  --pattern <pattern-name> \
  --service-name <name> \
  --hostname <hostname> \
  --memory <size>

# 3. Verify deployment
./scripts/check-drift.sh <name>
systemctl --user status <name>.service
```

### Pattern Library (9 Patterns)

1. **media-server-stack** - Jellyfin, Plex (GPU, large storage)
2. **web-app-with-database** - Wiki.js, Bookstack (standard web apps)
3. **document-management** - Paperless-ngx (OCR, multi-container)
4. **authentication-stack** - Authelia + Redis (SSO with YubiKey)
5. **password-manager** - Vaultwarden (self-contained vault)
6. **database-service** - PostgreSQL, MySQL (BTRFS NOCOW)
7. **cache-service** - Redis, Memcached (sessions, caching)
8. **reverse-proxy-backend** - Internal services (strict auth)
9. **monitoring-exporter** - Node exporter, cAdvisor (metrics)

### Pattern Structure (YAML)

```yaml
name: pattern-name
category: service-type
description: Human-readable description

quadlet:
  container:
    image: docker.io/library/image:tag
    networks:
      - systemd-reverse_proxy.network
      - systemd-monitoring.network
    volumes:
      - /data/path:/container/path:Z
    labels:
      traefik.enable: "true"
      traefik.http.routers.service.rule: "Host(`{{hostname}}`)"

systemd:
  service:
    memory: "{{memory}}"
    memory_high: "{{memory_high}}"

validation_checks:
  - check: image_exists
  - check: network_exists
    value: systemd-reverse_proxy
  - check: btrfs_nocow
    path: /data/path

deployment_notes: |
  Important information about this pattern
  - Prerequisites
  - Post-deployment steps
  - Common customizations

post_deployment:
  - action: verify_health_check
  - action: check_traefik_routing
  - action: test_service_access
```

### Intelligence Integration

**Health-aware deployment:**
- `check-system-health.sh` runs `homelab-intel.sh` for health scoring
- Health score 0-100 with thresholds:
  - **90-100:** Excellent - proceed with any deployment
  - **75-89:** Good - proceed with monitoring
  - **50-74:** Degraded - address warnings first
  - **0-49:** Critical - block deployment, fix issues
- Override available with `--force` or `--skip-health-check`

**Drift detection:**
- `check-drift.sh` compares running containers vs quadlet definitions
- Categories: ✓ MATCH, ✗ DRIFT (reconcile), ⚠ WARNING (informational)
- Checks: Image version, memory limits, networks, volumes, Traefik labels
- JSON output available for automation

## Rationale

### Consistency and Best Practices

**Pattern templates encode proven configurations:**
- Network ordering (reverse_proxy first for internet access)
- SELinux labels (`:Z` on all volume mounts)
- BTRFS NOCOW for databases
- Traefik middleware chains (CrowdSec → rate limit → auth → security headers)
- Systemd dependencies and restart policies
- Resource limits (Memory, MemoryHigh, CPUWeight)

**Eliminates "forgot to..." mistakes:**
- Forgot NOCOW → database performance degraded
- Forgot network order → container can't reach internet
- Forgot `:Z` → permission denied errors
- Forgot Traefik labels → service not routable

### Reusability and Knowledge Capture

**Similar services share patterns:**
- All PostgreSQL/MySQL deployments use `database-service` pattern
- All web apps use `web-app-with-database` pattern
- Captures best practices once, reuse forever

**Pattern evolution:**
- When deploying similar service 2-3 times, create new pattern
- Patterns improve through real-world usage
- Documentation built-in (deployment_notes, post_deployment checklist)

### Validation and Safety

**Pre-deployment validation:**
- System health check prevents deploying to unhealthy system
- Prerequisite checks (image exists, networks exist, ports available)
- BTRFS NOCOW verification for database patterns

**Post-deployment verification:**
- Drift detection confirms quadlet matches running container
- Health check endpoints validated
- Traefik routing tested

**Fail-fast principle:**
- Validation errors stop deployment before partial failure
- Clear error messages with remediation steps
- `--dry-run` mode for safety

### Claude Code Integration

**Skill invocation patterns:**
- Claude Code can autonomously deploy services using patterns
- Integration guide defines when to invoke homelab-deployment skill
- Decision tree for pattern selection
- Multi-skill workflows (Health → Deploy → Verify)

**User assistance:**
- Pattern selection guide helps users choose correct pattern
- Cookbook provides quick recipes for common tasks
- Service-specific guides reference pattern deployment

## Consequences

### Positive Outcomes

**Faster deployments:**
- 5-minute pattern deployment vs 20-30 minutes manual
- No research/recall overhead for best practices
- Pre-validated configurations reduce trial-and-error

**Fewer errors:**
- Pattern validation catches mistakes before deployment
- Consistent configurations reduce troubleshooting
- Drift detection maintains accuracy over time

**Better documentation:**
- Patterns are self-documenting (deployment_notes section)
- Post-deployment checklists ensure nothing missed
- Pattern library serves as reference architecture

**Transferable skills:**
- Pattern-based deployment aligns with industry practices (Helm, Terraform)
- Infrastructure-as-code principles applied to homelab
- Reusable across projects/environments

### Negative Consequences

**Learning curve:**
- Users must understand pattern structure and customization
- YAML syntax less familiar than bash scripts
- Pattern selection requires understanding service requirements

**Pattern maintenance:**
- Patterns must evolve with best practices
- Need to update multiple patterns for ecosystem-wide changes
- Testing required after pattern modifications

**Customization friction:**
- Heavy customization may require manual deployment
- Some edge cases don't fit existing patterns
- Trade-off between pattern rigidity and flexibility

### Trade-Offs

**Standardization vs Flexibility:**
- **Chosen:** Patterns handle 80% of deployments, manual for edge cases
- **Alternative:** Pure manual deployment (maximum flexibility, no consistency)
- **Alternative:** Strict patterns only (maximum consistency, no flexibility)

**Complexity vs Simplicity:**
- **Chosen:** YAML patterns + orchestrator script (moderate complexity)
- **Alternative:** Docker Compose (simpler syntax, less systemd integration)
- **Alternative:** Bash templates (simpler, less structured validation)

**Pre-validation vs Speed:**
- **Chosen:** Health checks + prerequisite validation (slower but safer)
- **Alternative:** Skip validation for speed (faster but error-prone)
- **Override:** `--skip-health-check` flag available when needed

## Implementation Details

### Pattern File Locations

```
.claude/skills/homelab-deployment/
├── patterns/                    # Pattern library
│   ├── media-server-stack.yml
│   ├── web-app-with-database.yml
│   ├── database-service.yml
│   └── ... (9 total)
├── scripts/
│   ├── deploy-from-pattern.sh   # Main orchestrator
│   ├── check-drift.sh           # Drift detection
│   ├── check-system-health.sh   # Health integration
│   └── check-prerequisites.sh   # Validation logic
└── COOKBOOK.md                  # Quick recipes
```

### Variable Substitution

**Pattern variables:**
```yaml
image: docker.io/library/{{image_name}}:{{image_tag}}
```

**Command-line replacement:**
```bash
--var image_name=postgres --var image_tag=16-alpine
```

**Built-in variables:**
- `{{hostname}}` - Service hostname (e.g., jellyfin.patriark.org)
- `{{service_name}}` - Container/service name
- `{{memory}}` - Memory limit (e.g., 2G)
- `{{memory_high}}` - Memory soft limit (75% of memory)

### Drift Detection Algorithm

**Comparison categories:**
1. **Image** - Running vs quadlet image:tag
2. **Memory** - Running limits vs quadlet Memory/MemoryHigh
3. **Networks** - Running networks vs quadlet Network= lines
4. **Volumes** - Running mounts vs quadlet Volume= lines
5. **Labels** - Traefik labels (routing, middleware, ports)

**Status determination:**
- **MATCH:** All categories match
- **DRIFT:** Any category mismatch (requires reconciliation)
- **WARNING:** Minor differences (network order, label formatting)

**Reconciliation:**
```bash
# Drift detected
./scripts/check-drift.sh jellyfin
# Output: DRIFT (memory mismatch)

# Fix: Restart to apply quadlet
systemctl --user restart jellyfin.service

# Verify
./scripts/check-drift.sh jellyfin
# Output: MATCH
```

### Health Scoring Integration

**homelab-intel.sh metrics:**
- Disk usage (system SSD + BTRFS pool)
- Memory usage and pressure
- Critical service status (Traefik, Prometheus, etc.)
- Load average and CPU trends
- BTRFS fragmentation and errors

**Decision logic:**
```bash
health_score=$(./scripts/check-system-health.sh --quiet | jq .health_score)

if [[ $health_score -lt 50 ]]; then
  echo "CRITICAL: System health too low ($health_score/100)"
  echo "Fix critical issues before deployment"
  exit 1
elif [[ $health_score -lt 70 ]]; then
  echo "WARNING: System health degraded ($health_score/100)"
  echo "Consider addressing warnings before deployment"
  # Continue with deployment
fi
```

## Alternatives Considered

### Alternative 1: Docker Compose / Podman Compose

**Pros:**
- Industry standard, widely known syntax
- Simpler YAML structure
- Extensive community support and examples

**Cons:**
- Doesn't integrate with systemd natively (wrapper layer)
- No built-in health awareness or drift detection
- Less control over systemd service properties
- Doesn't align with existing quadlet architecture (ADR-002)

**Verdict:** Rejected - Conflicts with ADR-002 (systemd quadlets over compose)

### Alternative 2: Ansible Playbooks

**Pros:**
- Full automation framework with rich ecosystem
- Idempotent by design
- Can manage entire system state

**Cons:**
- Significant complexity for single-host homelab
- Requires learning Ansible syntax and concepts
- Overkill for 10-20 services
- Heavyweight dependency

**Verdict:** Rejected - Too complex for homelab scale

### Alternative 3: Helm-like Templating (Go templates)

**Pros:**
- More powerful templating (conditionals, loops, functions)
- Industry alignment (Kubernetes Helm charts)

**Cons:**
- Go template syntax more complex than simple variable substitution
- Requires Go tooling or template processor
- Over-engineered for current needs

**Verdict:** Rejected - YAML + simple variable substitution sufficient

### Alternative 4: Continue with Service-Specific Scripts

**Pros:**
- No new concepts to learn
- Maximum flexibility per service
- Already working

**Cons:**
- Doesn't scale beyond 10-15 services
- Knowledge fragmentation across scripts
- No systematic validation
- High error rate on manual deployments

**Verdict:** Rejected - Session 3 experience proved patterns superior

## Follow-Up Actions

### Documentation Integration (This Session - Session 3.5)

- [x] Create Pattern Selection Guide (520 lines)
- [x] Create Skill Integration Guide (650 lines)
- [x] Create Deployment Cookbook (430 lines)
- [x] Update CLAUDE.md with pattern deployment section
- [ ] Create ADR-007 (this document)
- [ ] Update service guides with pattern examples (jellyfin.md, vaultwarden-deployment.md)
- [ ] Update architecture guide with pattern ecosystem reference
- [ ] Create drift detection workflow guide
- [ ] Create pattern customization guide
- [ ] Create health-driven operations guide

### Pattern Expansion (Future)

**Planned patterns:**
- **photo-management-stack** - Immich (app + postgres + redis + ML + typesense)
- **reverse-proxy-multi-backend** - Services with multiple backend containers
- **scheduled-job** - Backup services, batch processors

**Pattern refinement:**
- Add `--var` support for all configurable values
- Template conditionals (e.g., GPU device only if specified)
- Network creation automation

### Automation Integration (Future)

**Claude Code proactive deployment:**
- Detect user intent ("I want to deploy X") → invoke homelab-deployment skill
- Pattern matching ("set up a wiki" → web-app-with-database pattern)
- Health-check integration (auto-check before deployment)

**Workflow automation:**
- Weekly drift detection across all services
- Automated reconciliation of minor drift
- Health monitoring with deployment blocking

### Metrics and Monitoring (Future)

**Pattern usage tracking:**
- Which patterns most frequently used
- Success rate per pattern
- Common customizations (inform pattern evolution)

**Deployment metrics:**
- Time-to-deploy per pattern
- Validation failure rates
- Post-deployment drift frequency

## Related Documentation

- **Pattern Selection Guide:** `docs/10-services/guides/pattern-selection-guide.md`
- **Skill Integration Guide:** `docs/10-services/guides/skill-integration-guide.md`
- **Deployment Cookbook:** `.claude/skills/homelab-deployment/COOKBOOK.md`
- **Skill Documentation:** `.claude/skills/homelab-deployment/SKILL.md`
- **Session 3 Completion:** `docs/99-reports/2025-11-14-session-3-completion-summary.md`
- **ADR-002 (Systemd Quadlets):** `docs/00-foundation/decisions/2025-10-25-decision-002-systemd-quadlets-over-compose.md`

## Success Criteria

**This decision is successful if:**
- [ ] 80%+ of new deployments use pattern-based approach
- [ ] Pattern library covers common service types (media, web, database, cache)
- [ ] Deployment errors decrease significantly
- [ ] Configuration drift detected and corrected systematically
- [ ] Claude Code successfully invokes patterns autonomously
- [ ] Users reference pattern guides as primary deployment documentation
- [ ] New patterns emerge from real-world usage (photo management, etc.)

**Evaluation date:** 2025-12-14 (1 month after adoption)

---

**Decision made by:** patriark + Claude Code (Session 3.5)
**Document status:** Living (will update with success criteria results)
**Review frequency:** Quarterly or when pattern coverage gaps identified
