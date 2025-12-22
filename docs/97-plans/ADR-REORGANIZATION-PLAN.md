# ADR Reorganization Plan

**Date:** 2025-12-22
**Status:** Proposed - Awaiting User Approval
**Impact:** Standardizes ADR naming and numbering across all documentation

---

## Executive Summary

Current ADR files have significant inconsistencies:
- **Duplicate numbering:** decision-001, decision-006, decision-007, decision-008 appear multiple times
- **Mixed naming:** Some use "decision-XXX", some use "ADR-XXX", some have no prefix
- **Missing numbers:** ADR-003 referenced but doesn't exist as a standalone file
- **Non-ADR files:** Audit reports and migration reports mixed with ADRs

**Proposed Solution:** Renumber all ADRs sequentially (ADR-001 through ADR-014) based on chronological date, standardize naming, and relocate non-ADR documents.

---

## Issues Identified

### 1. Duplicate ADR Numbers

| Number | Files | Status |
|--------|-------|--------|
| decision-001 | 10-services (quadlets), 40-monitoring (monitoring stack) | ❌ Duplicate |
| decision-006 | 10-services (vaultwarden), 30-security (crowdsec), 20-operations (dependency mapping) | ❌ Triple duplicate! |
| decision-007 | 10-services (nextcloud auth), 20-operations (pattern deployment) | ❌ Duplicate |
| decision-008 | 10-services (nextcloud passwordless), 20-operations (autonomous ops - as "ADR-008") | ❌ Duplicate |

### 2. Naming Format Inconsistencies

- ✅ Correct: `2025-11-10-decision-004-authelia-sso-mfa-architecture.md`
- ✅ Correct: `2025-12-11-ADR-008-autonomous-operations-alert-quality.md`
- ❌ Inconsistent: `2025-11-08-immich-deployment-architecture.md` (no number)
- ❌ Inconsistent: `2025-11-13-config-data-directory-strategy.md` (no number)

### 3. Non-ADR Files in decisions/ Directories

- `2025-12-20-audit-001-nextcloud-configuration-audit.md` - Audit report, not ADR
- `2025-12-20-migration-001-nextcloud-secrets-migration.md` - Migration report, not ADR
- `2025-10-25-decision-001-quadlets-vs-generated-units.md` - Comparison guide, not ADR (ADR-002 covers this)

---

## Proposed Sequential Numbering

**Principle:** Number ADRs chronologically by date, maintaining one sequential series across all categories.

| New Number | Date | Current Name | New Name | Category | Status |
|------------|------|--------------|----------|----------|--------|
| **ADR-001** | 2025-10-20 | decision-001-rootless-containers | ADR-001-rootless-containers | 00-foundation | ✅ Keep as-is |
| **ADR-002** | 2025-10-25 | decision-002-systemd-quadlets-over-compose | ADR-002-systemd-quadlets-over-compose | 00-foundation | ✅ Keep as-is |
| **ADR-003** | 2025-11-06 | decision-001-monitoring-stack-architecture | ADR-003-monitoring-stack-architecture | 40-monitoring | 🔄 Rename |
| **ADR-004** | 2025-11-08 | immich-deployment-architecture | ADR-004-immich-deployment-architecture | 10-services | 🔄 Rename |
| **ADR-005** | 2025-11-10 | decision-004-authelia-sso-mfa-architecture | ADR-005-authelia-sso-mfa-architecture | 30-security | 🔄 Rename |
| **ADR-006** | 2025-11-11 | decision-005-authelia-sso-yubikey-deployment | ADR-006-authelia-sso-yubikey-deployment | 30-security | 🔄 Rename |
| **ADR-007** | 2025-11-12 | decision-006-vaultwarden-architecture | ADR-007-vaultwarden-architecture | 10-services | 🔄 Rename |
| **ADR-008** | 2025-11-12 | decision-006-crowdsec-security-architecture | ADR-008-crowdsec-security-architecture | 30-security | 🔄 Rename |
| **ADR-009** | 2025-11-13 | config-data-directory-strategy | ADR-009-config-data-directory-strategy | 00-foundation | 🔄 Rename |
| **ADR-010** | 2025-11-14 | decision-007-pattern-based-deployment | ADR-010-pattern-based-deployment | 20-operations | 🔄 Rename |
| **ADR-011** | 2025-12-02 | decision-006-service-dependency-mapping | ADR-011-service-dependency-mapping | 20-operations | 🔄 Rename |
| **ADR-012** | 2025-12-11 | ADR-008-autonomous-operations-alert-quality | ADR-012-autonomous-operations-alert-quality | 20-operations | 🔄 Rename |
| **ADR-013** | 2025-12-20 | decision-007-nextcloud-native-authentication | ADR-013-nextcloud-native-authentication | 10-services | 🔄 Rename |
| **ADR-014** | 2025-12-20 | decision-008-nextcloud-passwordless-authentication | ADR-014-nextcloud-passwordless-authentication | 10-services | 🔄 Rename |

---

## Non-ADR Files to Relocate

### 1. Comparison Guide (Not an ADR)

**File:** `docs/10-services/decisions/2025-10-25-decision-001-quadlets-vs-generated-units.md`

**Issue:** This is a technical comparison/guide, not an architecture decision. ADR-002 already documents the decision to use quadlets.

**Proposed Action:**
- **Move to:** `docs/00-foundation/guides/quadlets-vs-generated-units-comparison.md`
- **Rationale:** It's educational content explaining the difference, not a decision record

### 2. Audit Report (Not an ADR)

**File:** `docs/10-services/decisions/2025-12-20-audit-001-nextcloud-configuration-audit.md`

**Issue:** This is an audit report analyzing compliance with design principles, not an architecture decision.

**Proposed Action:**
- **Move to:** `docs/99-reports/2025-12-20-nextcloud-configuration-audit.md`
- **Rationale:** It's a formal assessment report, belongs in reports directory

### 3. Migration Report (Not an ADR)

**File:** `docs/10-services/decisions/2025-12-20-migration-001-nextcloud-secrets-migration.md`

**Issue:** This is an operational migration report documenting how credentials were migrated, not an architecture decision.

**Proposed Action:**
- **Move to:** `docs/98-journals/2025-12-20-nextcloud-secrets-migration-report.md`
- **Rationale:** It's a chronological activity log, fits journal structure

---

## Naming Convention Standard

Going forward, all ADRs will follow this pattern:

```
YYYY-MM-DD-ADR-###-brief-descriptive-name.md
```

**Examples:**
- ✅ `2025-10-20-ADR-001-rootless-containers.md`
- ✅ `2025-12-20-ADR-013-nextcloud-native-authentication.md`
- ❌ `2025-10-20-decision-001-rootless-containers.md` (old format)

---

## Journal Entry Review (Last 10 Days)

**Reviewed entries:**
- 2025-12-15-security-improvements-and-automation.md
- 2025-12-18-documentation-structure-reorganization.md
- 2025-12-19-alert-optimization-slo-enhancement.md
- 2025-12-20-nextcloud-deployment-and-ocis-decommission.md
- 2025-12-21-nextcloud-background-jobs-and-error-resolution.md
- 2025-12-21-nextcloud-monitoring-enhancement-alert-fixes.md

**Conclusion:** ✅ None qualify as ADRs

**Rationale:**
- All are operational reports documenting *what was done*, not *architectural decisions*
- Implementation details belong in journals
- No significant architectural choices that warrant ADR documentation
- The actual architectural decision (e.g., SLO-based alerting) is an implementation of ADR-012 principles

---

## Internal Content Updates Required

Many ADRs reference other ADRs by their old numbers. These internal references need updating.

### ADR-001 (Rootless Containers)
**Current references:**
```markdown
Related ADRs: ADR-002 (Systemd Quadlets), ADR-003 (Traefik Reverse Proxy)
```

**Updated references:**
```markdown
Related ADRs: ADR-002 (Systemd Quadlets)
```
**Note:** ADR-003 is now Monitoring Stack, not Traefik. Remove this reference as Traefik isn't covered by a dedicated ADR.

### ADR-002 (Systemd Quadlets)
**Current reference:** Points to comparison file in 10-services/decisions
**Action:** Update reference after moving comparison guide

### ADR-005 (Authelia SSO & MFA)
**Current references:** Mentions ADR-001, ADR-002, ADR-003 (as monitoring)
**Action:** Verify ADR-003 reference is correct (should be)

### ADR-006 (Authelia YubiKey)
**Current "Supersedes":** References TinyAuth de facto
**Action:** No change needed

### ADR-007 (Vaultwarden)
**Current references:** Mentions ADR-001, ADR-002, ADR-003, ADR-005
**Action:** Verify all references map to new numbering

### ADR-008 (CrowdSec)
**Current references:** Links to guides and other docs
**Action:** Verify internal doc paths are correct

### ADR-009 (Config/Data Strategy)
**Current references:** Mentions ADR-006 (should now be ADR-008 - CrowdSec)
**Action:** Update reference from decision-006 to ADR-008

### ADR-010 (Pattern-Based Deployment)
**Current references:** Mentions ADR-002
**Action:** Verify reference is correct

### ADR-013 (Nextcloud Native Auth)
**Current references:** Mentions ADR-008 (should now be ADR-014 - Nextcloud Passwordless)
**Action:** Update all ADR-008 references to ADR-014

### ADR-014 (Nextcloud Passwordless)
**Current references:** Mentions ADR-007 (should now be ADR-013 - Nextcloud Native Auth)
**Action:** Update ADR-007 references to ADR-013

---

## CLAUDE.md Updates Required

**Current CLAUDE.md content:**
```markdown
**ADR supersession pattern:**
```markdown
## Status: Superseded by ADR-XXX
```

**Key decisions shaping this homelab:**
- **ADR-001: Rootless Containers** ✅ Correct
- **ADR-002: Systemd Quadlets Over Docker Compose** ✅ Correct
- **ADR-003: Monitoring Stack** ❌ Currently listed as future, actually exists
- **ADR-005: Authelia SSO with YubiKey-First Authentication** ❌ Should reference both ADR-005 and ADR-006
```

**Required Updates:**
1. Add ADR-003 to the list (Monitoring Stack Architecture)
2. Add references to ADR-004 through ADR-014
3. Update all ADR paths in decision references
4. Update ADR template paths in documentation

---

## Implementation Steps

### Phase 1: File Renames (Using git mv)

Execute all renames in a single commit to preserve history:

```bash
cd /home/patriark/containers/docs

# ADR-003: Monitoring Stack
git mv 40-monitoring-and-documentation/decisions/2025-11-06-decision-001-monitoring-stack-architecture.md \
       40-monitoring-and-documentation/decisions/2025-11-06-ADR-003-monitoring-stack-architecture.md

# ADR-004: Immich
git mv 10-services/decisions/2025-11-08-immich-deployment-architecture.md \
       10-services/decisions/2025-11-08-ADR-004-immich-deployment-architecture.md

# ADR-005: Authelia SSO & MFA
git mv 30-security/decisions/2025-11-10-decision-004-authelia-sso-mfa-architecture.md \
       30-security/decisions/2025-11-10-ADR-005-authelia-sso-mfa-architecture.md

# ADR-006: Authelia YubiKey
git mv 30-security/decisions/2025-11-11-decision-005-authelia-sso-yubikey-deployment.md \
       30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md

# ADR-007: Vaultwarden
git mv 10-services/decisions/2025-11-12-decision-006-vaultwarden-architecture.md \
       10-services/decisions/2025-11-12-ADR-007-vaultwarden-architecture.md

# ADR-008: CrowdSec
git mv 30-security/decisions/2025-11-12-decision-006-crowdsec-security-architecture.md \
       30-security/decisions/2025-11-12-ADR-008-crowdsec-security-architecture.md

# ADR-009: Config/Data Strategy
git mv 00-foundation/decisions/2025-11-13-config-data-directory-strategy.md \
       00-foundation/decisions/2025-11-13-ADR-009-config-data-directory-strategy.md

# ADR-010: Pattern Deployment
git mv 20-operations/decisions/2025-11-14-decision-007-pattern-based-deployment.md \
       20-operations/decisions/2025-11-14-ADR-010-pattern-based-deployment.md

# ADR-011: Service Dependency Mapping
git mv 20-operations/decisions/2025-12-02-decision-006-service-dependency-mapping.md \
       20-operations/decisions/2025-12-02-ADR-011-service-dependency-mapping.md

# ADR-012: Autonomous Operations Alert Quality
git mv 20-operations/decisions/2025-12-11-ADR-008-autonomous-operations-alert-quality.md \
       20-operations/decisions/2025-12-11-ADR-012-autonomous-operations-alert-quality.md

# ADR-013: Nextcloud Native Auth
git mv 10-services/decisions/2025-12-20-decision-007-nextcloud-native-authentication.md \
       10-services/decisions/2025-12-20-ADR-013-nextcloud-native-authentication.md

# ADR-014: Nextcloud Passwordless
git mv 10-services/decisions/2025-12-20-decision-008-nextcloud-passwordless-authentication.md \
       10-services/decisions/2025-12-20-ADR-014-nextcloud-passwordless-authentication.md
```

### Phase 2: Relocate Non-ADR Files

```bash
# Move comparison guide to guides directory
git mv 10-services/decisions/2025-10-25-decision-001-quadlets-vs-generated-units.md \
       00-foundation/guides/quadlets-vs-generated-units-comparison.md

# Move audit report to reports
git mv 10-services/decisions/2025-12-20-audit-001-nextcloud-configuration-audit.md \
       99-reports/2025-12-20-nextcloud-configuration-audit.md

# Move migration report to journals
git mv 10-services/decisions/2025-12-20-migration-001-nextcloud-secrets-migration.md \
       98-journals/2025-12-20-nextcloud-secrets-migration-report.md
```

### Phase 3: Update Internal References

Update references within ADR files:

1. **ADR-009** (Config/Data Strategy):
   - Line 227: Change "ADR-006" reference to "ADR-008" (CrowdSec)

2. **ADR-013** (Nextcloud Native Auth):
   - Update all "ADR-008" references to "ADR-014" (Nextcloud Passwordless)
   - Line 322: Update related decisions list

3. **ADR-014** (Nextcloud Passwordless):
   - Update all "ADR-007" references to "ADR-013" (Nextcloud Native Auth)
   - Line 363: Update related decisions list

### Phase 4: Update CLAUDE.md

Update the ADR section in CLAUDE.md:

```markdown
## Architecture Decision Records (ADRs)

**Key decisions shaping this homelab:**

- **ADR-001: Rootless Containers** - All containers run unprivileged
- **ADR-002: Systemd Quadlets Over Docker Compose** - Native systemd integration
- **ADR-003: Monitoring Stack Architecture** - Prometheus + Grafana + Loki
- **ADR-004: Immich Deployment Architecture** - Multi-container photo management
- **ADR-005: Authelia SSO & MFA Architecture** - Initial SSO design
- **ADR-006: Authelia SSO with YubiKey-First** - Phishing-resistant hardware auth
- **ADR-007: Vaultwarden Architecture** - Self-hosted password manager
- **ADR-008: CrowdSec Security Architecture** - IP reputation and threat intelligence
- **ADR-009: Config vs Data Directory Strategy** - Storage organization principles
- **ADR-010: Pattern-Based Deployment** - Automated service deployment
- **ADR-011: Service Dependency Mapping** - Automated dependency discovery
- **ADR-012: Autonomous Operations Alert Quality** - SLO-based alerting
- **ADR-013: Nextcloud Native Authentication** - CalDAV/CardDAV compatibility
- **ADR-014: Nextcloud Passwordless Auth** - FIDO2/WebAuthn implementation
```

---

## Validation Checklist

After completing all changes:

- [ ] All ADR files follow `YYYY-MM-DD-ADR-###-name.md` format
- [ ] Sequential numbering ADR-001 through ADR-014 with no gaps
- [ ] No duplicate ADR numbers exist
- [ ] All internal ADR references updated
- [ ] CLAUDE.md ADR list updated
- [ ] Non-ADR files moved to appropriate locations
- [ ] All moves done with `git mv` (history preserved)
- [ ] Git commit with descriptive message
- [ ] Documentation builds without broken links

---

## Git Commit Message

```
docs: Standardize ADR naming and sequential numbering (ADR-001 to ADR-014)

BREAKING CHANGE: All ADR file paths have changed

- Renumbered all ADRs sequentially by date (ADR-001 through ADR-014)
- Standardized naming: YYYY-MM-DD-ADR-###-description.md
- Resolved duplicate numbering (decision-006 appeared 3 times!)
- Updated internal cross-references between ADRs
- Relocated non-ADR files:
  - Comparison guide → 00-foundation/guides/
  - Audit report → 99-reports/
  - Migration report → 98-journals/
- Updated CLAUDE.md with complete ADR list

All changes preserve git history via `git mv`.

Refs: #ADR-reorganization
```

---

## Risk Assessment

**Low Risk:**
- All changes use `git mv` (history preserved)
- No automation depends on ADR file names
- Internal references being updated systematically
- Non-ADR files being moved to more appropriate locations

**Medium Risk:**
- Links in external documentation might break
- User might have bookmarks to old file paths

**Mitigation:**
- Comprehensive commit message explains all changes
- This plan document serves as migration guide
- User can review plan before execution

---

**Plan Status:** Awaiting user approval
**Estimated Time:** 30-45 minutes to execute all changes
**Rollback:** `git reset --hard` before committing
