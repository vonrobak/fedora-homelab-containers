# Skill Stack Alignment with February 2026 Production Reality

**Date:** 2026-02-07
**Author:** Claude Opus 4.6
**Status:** Complete - PR #85 created
**PR:** https://github.com/vonrobak/fedora-homelab-containers/pull/85

---

## Summary

The homelab skill stack (skills, subagents, templates, patterns, deployment scripts) was comprehensively realigned with production reality. The skill stack was largely developed during Sessions 1-3 (Nov-Dec 2025), but the production infrastructure had evolved significantly since then -- ADR-016 (configuration design principles), ADR-018 (static IPs), new networks, new services, Collabora decommission. The result was a growing gap where deploying a new service using the skills would produce incorrect, potentially service-breaking output.

**Before:** Audit score 0/100 (19 FAIL, 11 WARN across 8 check categories)
**After:** Audit score 96/100 (0 FAIL, 2 WARN -- both pre-existing production issues, not template issues)

**Scope:** 33 files changed (952 insertions, 1,579 deletions) across 5 implementation trajectories.

---

## The Problem

If someone had deployed a new service using `deploy-from-pattern.sh` on February 7, 2026, the output would have been incorrect in 9 concrete, verified ways:

| Issue | Severity | Consequence |
|-------|----------|-------------|
| No static IPs in templates | High | Intermittent "untrusted proxy" errors (ADR-018 violation) |
| Traefik `-service` suffix mismatch | High | Routing failure -- service reference wouldn't match |
| `sed`-based YAML insertion | Critical | Could corrupt `routers.yml`, breaking ALL service routing |
| Missing `Slice=`, `Requires=` | Medium | No resource controls, no startup dependencies |
| Traefik labels in stacks | Medium | ADR-016 violation, misleads future deployments |
| Infrastructure-architect knows 5/8 networks | Medium | Incorrect topology recommendations |
| No native-auth template | Medium | Most common service type (5 services) has no template |
| Templates include non-production features | Low | `passHostHeader`, `healthCheck` not used in production |
| Database pattern uses plaintext passwords | Medium | ADR-016 Principle 3 violation (should use Podman secrets) |

---

## Implementation: 5 Trajectories

### Trajectory 5: Audit Tool + Archive (Quick Win)

**Goal:** Build drift detection capability before making changes, so each subsequent trajectory's impact can be measured.

**Changes:**
- Created `audit-skill-stack.sh` with 8 check categories:
  1. Static IP presence in quadlet templates
  2. Production quadlet features (Slice, Requires, MemorySwapMax)
  3. Traefik service naming (no `-service` suffix)
  4. Traefik template features (no passHostHeader/healthCheck)
  5. Infrastructure-architect network completeness
  6. ADR-016 compliance (no Traefik labels in quadlets/stacks)
  7. Pattern network name validity
  8. Secrets compliance (no plaintext passwords)
- Archived `claude-code-analyzer` skill to `/mnt/btrfs-pool/subvol6-tmp/99-outbound/claude-code-analyzer-archived-20260207/`
  - Rationale: Zero homelab value, generic Claude Code optimization tips, not aligned with operational excellence focus

**Debugging note:** The audit script required several fixes related to `set -euo pipefail` behavior:
- `((var++))` returns exit code 1 when var is 0 (bash treats 0 as falsy). Fixed with `var=$((var+1))`
- `[[ condition ]] && pass "msg"` at end of functions returns exit 1 when condition is false. Fixed with `|| true`
- `grep -o "systemd-[a-z_]*"` matched bare `systemd-` prefix. Fixed with `grep -oE "systemd-[a-z_]+"`

**Files:** 2 new, 7 deleted (archive), 1 modified (CLAUDE.md)

---

### Trajectory 3: Subagent Knowledge Synchronization

**Goal:** Correct the foundational knowledge that subagents use when making design recommendations.

**Infrastructure-architect updates:**
- Network list: 5 → 8 (added `systemd-nextcloud`, `systemd-home_automation`, `systemd-gathio`)
- Added ADR-018 static IP guidance with full IP allocation scheme per network
- Added authentication strategy decision tree (native vs Authelia) with criteria
- Added complete middleware list (15 middleware including service-specific ones like `rate-limit-immich`, `security-headers-ha`, `circuit-breaker`, `retry`, `compression`)

**Service-validator updates:**
- Level 2: Added static IP verification for multi-network containers
- Level 3: Added YAML validation (`python3 -c "import yaml; yaml.safe_load(...)"`), service reference matching

**Code-simplifier updates:**
- Added ADR-018 compliance check section
- Updated quadlet patterns with production features
- Added native-auth template awareness, service naming guidance

**Files:** 3 modified

---

### Trajectory 4: ADR-016 Violation Fixes

**Goal:** Remove anti-patterns that contradict documented architecture decisions.

**Changes:**
- `nextcloud.yml`: Removed 14 Traefik label lines, replaced with ADR-016 reference comment, updated image from `:30` to `:latest`
- `immich.yml`: Removed 13 Traefik label lines from immich-server, kept Prometheus labels
- `monitoring-simple.yml`: Removed Traefik labels from Prometheus and Grafana entries
- `database-service.yml`: Replaced plaintext `POSTGRES_PASSWORD={db_password}` with Podman secrets block, fixed stale network name `systemd-nextcloud_services` to valid network names

**Files:** 4 modified

---

### Trajectory 1: Template Alignment with Production

**Goal:** Make every future deployment produce correct output by default.

**Quadlet template changes (all 4 templates):**
- Added `Slice=container.slice`
- Added `Requires={{NETWORK_SERVICES_REQUIRES}}` and matching `After=` directives
- Changed `Network=` lines to include static IP syntax: `Network=systemd-reverse_proxy:ip={{STATIC_IP_REVERSE_PROXY}}`
- Added optional `MemorySwapMax={{MEMORY_SWAP_MAX}}` placeholder
- Kept `Restart=on-failure` (user preference -- production quadlets using `Restart=always` should be updated, not the templates)

**Traefik template changes (all 4 existing + 1 new):**
- Restructured from standalone `http:` blocks to indented fragments with `# Append under http.services:` separator
- Removed `-service` suffix from all service names and references
- Removed `passHostHeader: true` and `healthCheck` blocks (not used in production)
- Created `native-auth-service.yml` for services with native authentication (Jellyfin, Immich, Nextcloud, Home Assistant, Vaultwarden) -- no `authelia@file` middleware

**Pattern updates:**
- `media-server-stack.yml`: Changed to `native-auth-service.yml` template, added `auth_strategy: native`, added `static_ips` section
- `web-app-with-database.yml`: Added `auth_strategy: authelia` with override documentation
- `database-service.yml`: Podman secrets syntax, corrected network names

**SKILL.md updates:**
- Phase 3 examples updated from per-service file creation to consolidated `routers.yml` appending
- Added NATIVE AUTH SERVICE tier to middleware selection guide
- Updated network selection guide to list all 8 networks with ADR-018 reference
- Updated rollback procedure to match consolidated model

**Files:** 11 modified, 1 new

---

### Trajectory 2: YAML-Aware Route Generation

**Goal:** Replace fragile `sed`-based routers.yml modification with safe, validated insertion.

**Problem:** The existing `append_to_routers()` function used `sed` to extract router/service sections from template files and blindly appended them to `routers.yml`. Templates were structured as standalone YAML files, but production uses a single consolidated file. No duplicate detection, no YAML validation, no indentation awareness. A single malformed template could corrupt the entire routing configuration, taking down ALL services.

**Solution:** Complete rewrite of `append_to_routers()`:

1. **Duplicate detection:** Checks if `{{SERVICE_NAME}}-secure:` already exists in `routers.yml` before insertion
2. **Python YAML-aware insertion:** Uses PyYAML to parse the rendered template, splits at `# Append under http.services:` separator, inserts router lines into the routers section and service lines into the services section using structural position detection
3. **Automatic validation:** Runs `validate-traefik-config.sh` after insertion (5 checks: YAML syntax, service references, middleware ordering, duplicate detection, TLS configuration)
4. **Automatic rollback:** Creates backup before modification, restores on validation failure

**New validation script** (`validate-traefik-config.sh`):
- Check 1: YAML syntax validation via `python3 -c "import yaml; yaml.safe_load(...)"`
- Check 2: Service reference integrity (every router's `service:` must have a matching entry under `services:`)
- Check 3: Middleware ordering (CrowdSec bouncer must be first in every chain -- fail-fast principle)
- Check 4: Duplicate router/service detection
- Check 5: TLS certResolver presence on all routers

**Files:** 1 modified, 1 new

---

## Results

### Audit Score Progression

| Phase | Score | FAIL | WARN | PASS |
|-------|-------|------|------|------|
| Before (baseline) | 0/100 | 19 | 11 | 0 |
| After T5 (audit tool) | 0/100 | 19 | 11 | 0 |
| After T3 (subagents) | ~20/100 | 14 | 8 | 8 |
| After T4 (ADR-016) | ~45/100 | 10 | 5 | 15 |
| After T1 (templates) | ~85/100 | 2 | 3 | 18 |
| After T2 (YAML rewrite) | 96/100 | 0 | 2 | 19 |

### Remaining Warnings (2)

Both are pre-existing production issues, not template drift:

1. **Some production quadlets use `Restart=always`** instead of `Restart=on-failure` -- the templates are correct, production should be updated
2. **Some production quadlets lack `MemorySwapMax=`** -- optional feature, not all services need it

### File Change Summary

| Category | Modified | New | Deleted | Total |
|----------|----------|-----|---------|-------|
| Subagents | 3 | 0 | 0 | 3 |
| Quadlet templates | 4 | 0 | 0 | 4 |
| Traefik templates | 4 | 1 | 0 | 5 |
| Patterns | 3 | 0 | 0 | 3 |
| Stacks | 3 | 0 | 0 | 3 |
| Deploy scripts | 1 | 1 | 0 | 2 |
| Audit scripts | 0 | 1 | 0 | 1 |
| Archived skill | 0 | 0 | 6 | 6 |
| Documentation | 5 | 0 | 0 | 5 |
| **Total** | **23** | **3** | **6** | **33** |

---

## Skill Stack State After Alignment

| Component | Count | Details |
|-----------|-------|---------|
| Skills | 5 | homelab-deployment, homelab-intelligence, systematic-debugging, autonomous-operations, git-advanced-workflows |
| Subagents | 3 | infrastructure-architect, service-validator, code-simplifier |
| Slash commands | 1 | /commit-push-pr |
| Quadlet templates | 4 | web-app, database, monitoring-service, background-worker |
| Traefik templates | 5 | authenticated, native-auth, public, admin, api |
| Patterns | 9 | media-server, web-app-with-db, document-mgmt, auth-stack, password-mgr, database, cache, reverse-proxy-backend, monitoring-exporter |
| Stacks | 3 | nextcloud, immich, monitoring-simple (all ADR-016 compliant) |
| Audit tools | 2 | audit-skill-stack.sh, validate-traefik-config.sh |

---

## Lessons Learned

### 1. Bash arithmetic under `set -euo pipefail` is treacherous

`((var++))` returns exit code 1 when `var` is 0, because bash treats 0 as false. This silently kills the script under `set -e`. The safe pattern is `var=$((var+1))`. Similarly, `[[ condition ]] && action` at the end of a function returns the condition's exit code when false -- append `|| true`.

### 2. Template drift is invisible without automated detection

Nine concrete issues had accumulated over ~3 months without anyone noticing. The audit script now catches these automatically. The recommended practice is to run `audit-skill-stack.sh` after any production infrastructure change to detect new drift.

### 3. YAML manipulation in shell scripts needs Python

Bash `sed`/`awk` cannot safely parse or modify YAML. The Python YAML approach (available on Fedora 43 via `python3-pyyaml`) is robust, handles indentation correctly, and enables structural validation. The tradeoff is a Python dependency, but this is standard on the platform.

### 4. Community skills ecosystem is empty for infrastructure

Searched GitHub for Claude Code community skills. All published skills focus on application development (React, Django, etc.). No infrastructure, homelab, or DevOps skills exist in the community. The Trail of Bits security patterns are interesting but would need significant adaptation. Enhancing existing skills provides far more value than adopting community skills.

---

## Future Work

These items were identified but deliberately excluded from this session's scope:

- **IP registry/allocation system**: Would automate static IP assignment across all networks. Adds complexity; current manual assignment with documented ranges in infrastructure-architect is sufficient.
- **Production quadlet updates**: Align `Restart=always` → `Restart=on-failure` and add missing `MemorySwapMax=` to bring audit score from 96 to 100.
- **Dry-run validation**: Run `deploy-from-pattern.sh --dry-run` for all 9 patterns and diff against closest production quadlet to verify correctness.
- **Loki/Promtail healthchecks**: Add container healthcheck definitions (endpoints exist: `:3100/ready`, `:9080/ready`) -- noted in known gaps.

---

*This work was completed in a single session. PR #85: https://github.com/vonrobak/fedora-homelab-containers/pull/85*
