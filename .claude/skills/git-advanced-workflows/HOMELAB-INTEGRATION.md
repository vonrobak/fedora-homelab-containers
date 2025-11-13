# Homelab Git Workflow Integration

This document integrates the generic git-advanced-workflows skill with the homelab's specific practices.

## Homelab-Specific Git Workflow

Per `CLAUDE.md`, this project follows specific conventions:

### Branch Naming
```bash
# Features
feature/description

# Bugfixes
bugfix/description

# Documentation
docs/description

# Hotfixes
hotfix/description
```

### Merging Strategy
- **Squash and merge** for small changes
- **Create merge commit** for feature branches
- Auto-delete branches after merge

### GPG Signing & SSH
- All commits must be GPG signed
- SSH authentication (Ed25519 keys)
- Strict host key checking enabled

## Homelab-Adapted Workflows

### Workflow 1: Clean Feature Branch for Homelab PR

**Adapted for homelab infrastructure changes:**

```bash
# Start with feature branch
git checkout feature/monitoring-dashboard

# Interactive rebase to clean history
git rebase -i main

# Rebase operations specific to homelab:
# - Squash "fix typo in prometheus.yml" commits
# - Reword "update config" → "Monitoring: Add service health dashboard"
# - Keep separate commits for:
#   - Configuration changes
#   - Documentation updates
#   - ADR creation (if applicable)

# Force push (safe with --force-with-lease)
git push --force-with-lease origin feature/monitoring-dashboard

# Create PR with structured commit message
# Example good commit message:
# "Monitoring: Add Grafana service health dashboard
#
#  - Add dashboard JSON with service status panels
#  - Configure datasource for Prometheus
#  - Document dashboard in monitoring stack guide
#
#  Related ADR: docs/40-monitoring-and-documentation/decisions/ADR-003"
```

### Workflow 2: Hotfix Across Service Configurations

**Apply critical fix to multiple service configs:**

```bash
# Create fix on main (e.g., security header update)
git checkout main
git commit -m "Security: Fix Traefik CSP header for all services"

# Cherry-pick to feature branches if needed
git checkout feature/new-service
git cherry-pick abc123

# Or apply to historical config
git checkout release/v1.0
git cherry-pick abc123
```

### Workflow 3: Find When Service Configuration Broke

**Use bisect to find breaking configuration change:**

```bash
# Start bisect
git bisect start
git bisect bad HEAD  # Current: Jellyfin not accessible
git bisect good v1.0.0  # Known good: Before Traefik update

# Git checks out middle commit
# Test the service
systemctl --user restart jellyfin.service
curl -I https://jellyfin.patriark.org

# If accessible
git bisect good

# If not accessible
git bisect bad

# Continue until found
# Once found, reset
git bisect reset

# Automated version using service check
git bisect start HEAD v1.0.0
git bisect run ~/containers/scripts/test-jellyfin-health.sh
```

### Workflow 4: Work on Multiple Services Simultaneously

**Use worktrees for parallel service work:**

```bash
# Main work: Updating monitoring stack
cd ~/containers

# Emergency: Jellyfin needs immediate fix
git worktree add ../containers-hotfix hotfix/jellyfin-transcode

# Work on hotfix
cd ../containers-hotfix
# Fix Jellyfin quadlet
systemctl --user daemon-reload
systemctl --user restart jellyfin.service
git commit -m "Hotfix: Fix Jellyfin hardware acceleration"
git push origin hotfix/jellyfin-transcode

# Return to main work
cd ~/containers

# Clean up when hotfix merged
git worktree remove ../containers-hotfix
```

## Homelab-Specific Best Practices

### 1. Commit Messages Follow Project Standards

**Good examples:**
```
Monitoring: Add Prometheus disk space alerts
Jellyfin: Fix GPU hardware acceleration in quadlet
Security: Update Traefik middleware chain ordering
Documentation: Add ADR-007 for Immich deployment
```

**Bad examples:**
```
fix bug
update config
changes
WIP
```

### 2. Preserve Configuration History

**Don't rebase commits that:**
- Created or modified ADRs (Architecture Decision Records)
- Changed production service configurations
- Are referenced in documentation
- Have been deployed and documented in journal entries

### 3. Interactive Rebase for Documentation Clarity

**Combine commits for clarity:**
```bash
# Before rebase (messy):
- Add prometheus config
- Fix typo in prometheus config
- Update prometheus config again
- Add grafana dashboard
- Fix grafana dashboard
- Update CLAUDE.md

# After rebase (clean):
- Monitoring: Add Prometheus configuration with disk alerts
- Monitoring: Add Grafana service health dashboard
- Documentation: Update CLAUDE.md with monitoring commands
```

### 4. Cherry-Pick for Multi-Environment Configs

**When maintaining different environments:**
```bash
# Production fix
git checkout main
git commit -m "Traefik: Fix rate limiting for production load"

# Apply to development environment
git checkout feature/dev-environment
git cherry-pick abc123 --edit
# Modify commit message to note it's adapted for dev
```

## ADR Integration

When commits create or modify ADRs, preserve them in history:

```bash
# DON'T squash ADR commits
# This loses the decision timeline

# Good: Keep ADR commits separate
- Security: Add CrowdSec Phase 1 implementation
- Security: Add ADR-006 documenting CrowdSec architecture
- Monitoring: Integrate CrowdSec metrics with Prometheus

# Bad: Squashing loses ADR context
- Security: Add CrowdSec (combined)
```

## Recovery Workflows for Homelab

### Accidentally Removed Service Configuration

```bash
# Find when config was last good
git reflog | grep jellyfin

# Restore config file
git checkout abc123 -- config/jellyfin/

# Or recover entire service directory
git checkout abc123 -- .config/containers/systemd/jellyfin.container

# Commit restoration
git commit -m "Recovery: Restore Jellyfin configuration from abc123"
```

### Revert Breaking Traefik Change

```bash
# If Traefik change broke routing
git revert abc123

# Restart service with reverted config
systemctl --user restart traefik.service

# Verify fix
curl -I https://jellyfin.patriark.org
```

## Documentation References

When working with Git in this project:
- `CLAUDE.md` - Git workflow section
- `docs/*/decisions/` - ADRs (never edit, only supersede)
- `docs/*/journal/` - Dated learning logs (append-only)
- `docs/*/guides/` - Living docs (update in place)

## Integration with Homelab Scripts

**Test before committing:**
```bash
# Validate quadlet syntax
systemctl --user daemon-reload

# Run health checks
./scripts/homelab-intel.sh

# Generate snapshot for comparison
./scripts/homelab-snapshot.sh
```

**Include verification in commits:**
```bash
# Good commit includes verification
git commit -m "Jellyfin: Update quadlet with NOCOW optimization

Tested:
- systemctl --user status jellyfin.service - Running
- Health check: OK
- GPU acceleration: Verified with vainfo"
```

## Quick Reference Commands

```bash
# Homelab-specific Git workflow commands

# Clean up feature branch before PR
git checkout feature/my-feature
git rebase -i $(git merge-base HEAD main)
git push --force-with-lease origin feature/my-feature

# Cherry-pick service fix to multiple branches
git cherry-pick abc123

# Find when configuration broke
git bisect start HEAD <last-good-commit>
git bisect run ./scripts/test-service-health.sh

# Work on emergency fix without disrupting main work
git worktree add ../containers-emergency hotfix/critical

# Recover accidentally deleted config
git reflog
git checkout abc123 -- path/to/config

# Verify changes before committing
systemctl --user daemon-reload
./scripts/homelab-intel.sh
```

---

**Integration Version:** 1.0
**Last Updated:** 2025-11-13
**References:** CLAUDE.md, docs/CONTRIBUTING.md
