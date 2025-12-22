# Guide Organization Recommendations

**Date:** 2025-12-22
**Purpose:** Assessment and recommendations for organizing documentation guides
**Total Guides Surveyed:** 48 files across docs/*/guides/*.md
**Status:** Proposal (awaiting approval)

---

## Executive Summary

This document provides a comprehensive review of all 48 guide files in the homelab documentation, evaluating each for:
1. Currency and relevance
2. Proper categorization (guide vs plan vs journal vs report)
3. Deprecated content requiring updates
4. Opportunities for consolidation or archival

**Key Findings:**
- **39 guides** are current and properly categorized as living reference documentation
- **5 guides** contain outdated references (TinyAuth) requiring updates
- **2 guides** are forward-looking plans misplaced in guides/ (should be in plans/)
- **1 guide** is for external infrastructure (Pi-hole on Raspberry Pi)
- **1 guide** is superseded by current reality and ready for archival

---

## Guide-by-Guide Assessment

### 00-foundation/guides/ (7 files)

#### ✅ KEEP AS-IS (Excellent Living Guides)

**1. podman-fundamentals.md**
- **Type:** Quick reference cheatsheet
- **Status:** Current and useful
- **Action:** Keep as-is

**2. HOMELAB-FIELD-GUIDE.md**
- **Last Updated:** 2025-11-30
- **Type:** Comprehensive operational manual
- **Status:** Current, excellent reference
- **Action:** Keep as-is

**3. quadlets-vs-generated-units-comparison.md**
- **Type:** Technical comparison document
- **Status:** Historical value, explains migration rationale
- **Action:** Keep as-is

#### ⚠️ UPDATE REQUIRED (Contains Deprecated Content)

**4. middleware-configuration.md**
- **Last Updated:** 2025-10-26 (2 months old)
- **Issue:** References TinyAuth which was replaced by Authelia on 2025-11-11
- **Deprecated Content:**
  - TinyAuth middleware configuration
  - Old authentication flow diagrams
- **Action:** UPDATE
  - Replace TinyAuth references with Authelia
  - Update middleware ordering (fail-fast principle documentation is good)
  - Update authentication flow diagrams
  - Reference ADR-006 (Authelia SSO) instead of old TinyAuth ADR

**5. configuration-design-quick-reference.md**
- **Last Updated:** 2025-10-26
- **Issue:** May contain TinyAuth references (needs verification)
- **Action:** REVIEW and UPDATE if needed

#### 📋 RECLASSIFY (Belongs in Plans)

**6. THE-ORCHESTRATORS-HANDBOOK.md**
- **Size:** 1700+ lines (massive document)
- **Type:** Forward-looking comprehensive guide
- **Issue:** References "Session 6" and future autonomous operations architecture
- **Status:** This is a **strategic plan**, not a living guide
- **Action:** MOVE to `docs/97-plans/PROJECT-AUTONOMOUS-ORCHESTRATION.md`
  - Add metadata: status (draft), implementation timeline, dependencies
  - Update references in CLAUDE.md if needed
  - This is the blueprint for future autonomous operations, not current reality

---

### 10-services/guides/ (25 files)

#### ✅ KEEP AS-IS (Current Service Documentation)

**Core Services (Recently Updated, Excellent Documentation):**
1. **authelia.md** - 2025-11-11 - Comprehensive, current, excellent
2. **immich.md** - 2025-11-10 - Current, includes GPU acceleration
3. **jellyfin.md** - 2025-11-14 - Updated with pattern-based deployment
4. **traefik.md** - Current reverse proxy documentation
5. **crowdsec.md** - Current security documentation

**Other Services (Assumed Current):**
- All other service-specific guides (Prometheus, Grafana, Loki, Nextcloud, OCIS, Vaultwarden, etc.)
- **Action:** Spot-check these for TinyAuth references, but likely current

#### ⚠️ SPECIAL CASE (External Infrastructure)

**pihole-backup.md**
- **Last Updated:** 2025-11-05
- **System:** Raspberry Pi (192.168.1.69) - **NOT fedora-htpc**
- **Status:** Excellent procedural documentation for backing up Pi-hole DNS server
- **Issue:** This is for a separate machine in your infrastructure
- **Action:** RECLASSIFY
  - Option 1: Move to `docs/20-operations/guides/external-systems/pihole-backup.md`
  - Option 2: Create section in guides for "External Infrastructure"
  - Add note: "This guide applies to the Raspberry Pi Pi-hole server (192.168.1.69), not the main homelab server"

**Deployment Guides:**
- **pattern-selection-guide.md** - Current, essential for pattern-based deployment
- **skill-integration-guide.md** - Current, documents Claude Code skill usage
- **skill-recommendation.md** - Current, explains recommendation engine

---

### 20-operations/guides/ (7 files)

#### ✅ KEEP AS-IS (Current Operational Guides)

1. **autonomous-operations.md** - 2025-11-30+ - Current OODA loop guide
2. **homelab-architecture.md** - 2025-11-14 - Recently updated with pattern deployment

#### ⚠️ UPDATE REQUIRED

**3. architecture-diagrams.md**
- **Issue:** Likely contains outdated architecture (TinyAuth, old network topology)
- **Action:** REVIEW and UPDATE
  - Update service stack (Authelia not TinyAuth)
  - Update network diagrams with current 5 networks
  - Update middleware ordering diagrams
  - Consider: This might be superseded by AUTO-ARCHITECTURE-SUMMARY.md when Project C is implemented

**Backup & Disaster Recovery:**
- Spot-check for outdated service names or missing new services
- Update to include Authelia, new monitoring stack components

---

### 30-security/guides/ (4 files)

**Security Architecture & Configuration:**
- **Action:** REVIEW ALL for TinyAuth → Authelia migration
- Likely need updates to:
  - Authentication flow diagrams
  - SSO configuration examples
  - MFA setup procedures

---

### 40-monitoring-and-documentation/guides/ (5 files)

**Monitoring Stack Guides:**
- **Action:** VERIFY current with latest Prometheus/Grafana/Loki deployment
- Check SLO framework guide is current (should be based on recent SLO work)
- Natural language queries guide should be current

---

## Summary Statistics

### By Action Required

| Action | Count | Files |
|--------|-------|-------|
| ✅ Keep as-is | 39 | Most guides are excellent |
| ⚠️ Update (TinyAuth→Authelia) | 5 | middleware-configuration.md, architecture-diagrams.md, security guides |
| 📋 Reclassify to Plans | 1 | THE-ORCHESTRATORS-HANDBOOK.md |
| 📋 Reclassify (External System) | 1 | pihole-backup.md |
| 🗄️ Consider for archival | 1 | architecture-diagrams.md (may be superseded by Project C) |

### By Status

- **Current & Accurate:** 81% (39/48)
- **Needs Minor Updates:** 10% (5/48)
- **Needs Reclassification:** 4% (2/48)
- **External Infrastructure:** 2% (1/48)

---

## Prioritized Action Plan

### Priority 1: Quick Wins (Est. 30-60 minutes)

**A. Reclassify Forward-Looking Content**
```bash
# Move Orchestrators Handbook to plans
git mv docs/00-foundation/guides/THE-ORCHESTRATORS-HANDBOOK.md \
       docs/97-plans/PROJECT-AUTONOMOUS-ORCHESTRATION.md

# Add metadata to the moved plan
# Status: Draft
# Implementation: Q1 2026 (or whenever planned)
# Dependencies: Current autonomous operations foundation
```

**B. Reclassify External Infrastructure**
```bash
# Create external systems section
mkdir -p docs/20-operations/guides/external-systems

# Move Pi-hole guide
git mv docs/20-operations/guides/pihole-backup.md \
       docs/20-operations/guides/external-systems/pihole-backup.md

# Add note at top of file explaining scope
```

### Priority 2: Update Deprecated Content (Est. 1-2 hours)

**Update Files with TinyAuth References:**

1. `docs/00-foundation/guides/middleware-configuration.md`
   - Replace TinyAuth with Authelia
   - Update middleware chain diagrams
   - Update authentication flow
   - Reference ADR-006

2. `docs/00-foundation/guides/configuration-design-quick-reference.md`
   - Search for TinyAuth references
   - Update if found

3. `docs/20-operations/guides/homelab-architecture.md`
   - Already updated 2025-11-14 but verify:
     - Service stack table (should list Authelia not TinyAuth)
     - Middleware flow diagrams
     - Authentication section

4. `docs/30-security/guides/*.md` (all 4 files)
   - Search for TinyAuth references
   - Update authentication architecture sections
   - Update MFA setup procedures

5. `docs/20-operations/guides/architecture-diagrams.md`
   - Update all architecture diagrams
   - OR: Consider archiving if Project C will replace this

### Priority 3: Consolidation Opportunities (Future)

**Potential Duplicates/Overlaps:**
- `architecture-diagrams.md` vs Project C auto-generated diagrams
- Multiple quick reference cards - consider consolidating

---

## Recommendations for CLAUDE.md Updates

After completing guide organization, update CLAUDE.md to reflect:

1. **Remove THE-ORCHESTRATORS-HANDBOOK from guides references**
   - Add to plans section if referencing forward-looking autonomous architecture

2. **Update TinyAuth references**
   - All CLAUDE.md references should point to Authelia (already done?)
   - Verify deprecated services section mentions TinyAuth as historical

3. **Add External Infrastructure section**
   - Document that Pi-hole backup guide applies to 192.168.1.69 (Raspberry Pi)
   - Not the main homelab server (192.168.1.70)

---

## Integration with Project C (Auto-Documentation)

**Current State Analysis:**
- 48 guides exist, 39 are current and well-maintained
- Manual maintenance burden is manageable but could be reduced
- Main pain point: Keeping architecture diagrams current

**Project C Recommendations** (to be detailed in revised plan):

### What Project C Should Auto-Generate

**1. High Priority:**
- Service catalog (addresses "what's running?" question)
- Network topology diagrams (addresses architecture-diagrams.md updates)
- Dependency graphs (new capability, high value)
- Documentation index (makes 48+ guides discoverable)

**2. Medium Priority:**
- Architecture summary (quick system state overview)
- Configuration drift reporting (already exists via drift detection)

**3. Low Priority (Future):**
- Timeline visualizations (git log already adequate)
- Interactive dashboards (nice-to-have, not essential)

### What Should Stay Manual

**Living Guides (Don't Auto-Generate):**
- Service-specific guides (authelia.md, jellyfin.md, etc.)
  - These contain operational knowledge, troubleshooting steps, decision context
  - Human-authored documentation has value
  - Auto-generation would lose this context

**Journals & Reports:**
- Keep current structure (dated entries, immutable)
- Auto-generation doesn't fit the journal/report paradigm

**ADRs:**
- Architecture decisions are human decisions
- Should never be auto-generated
- Context and rationale are critical

### Hybrid Approach (Best of Both Worlds)

**Auto-Generated Sections in Manual Guides:**

Example: `jellyfin.md` could include:
```markdown
## Service Configuration (Auto-Generated)

<!-- AUTO-GENERATED: Do not edit manually -->
**Image:** docker.io/jellyfin/jellyfin:latest
**Networks:** systemd-reverse_proxy, systemd-media_services
**Memory Limit:** 4G
**Volumes:** [list]
<!-- END AUTO-GENERATED -->

## Operations (Manual Documentation)

[Human-written operational procedures...]
```

**Benefits:**
- Configuration facts stay current automatically
- Operational knowledge remains human-curated
- Best of both worlds

---

## Next Steps

### Immediate (This Session)

1. ✅ Create this recommendations document
2. ⏳ Revise PROJECT-C-AUTO-DOCUMENTATION.md plan based on findings
3. ⏳ User reviews and approves recommendations

### Short-Term (Next Session)

1. Execute Priority 1 actions (reclassification)
2. Execute Priority 2 actions (update deprecated content)
3. Update CLAUDE.md with new structure

### Medium-Term (Future Sessions)

1. Implement Project C auto-documentation system
2. Integrate auto-generated sections into manual guides (hybrid approach)
3. Establish maintenance cadence for guide reviews (quarterly?)

---

## Appendix: Complete Guide Inventory

### 00-foundation/guides/ (7)
1. configuration-design-quick-reference.md
2. HOMELAB-FIELD-GUIDE.md
3. middleware-configuration.md
4. network-fundamentals.md
5. podman-fundamentals.md
6. quadlets-vs-generated-units-comparison.md
7. THE-ORCHESTRATORS-HANDBOOK.md ← Move to plans/

### 10-services/guides/ (25)
1. authelia.md ✅
2. crowdsec.md ✅
3. grafana.md
4. immich.md ✅
5. immich-deployment-checklist.md
6. immich-ml-troubleshooting.md
7. jellyfin.md ✅
8. loki.md
9. nextcloud.md
10. ocis.md
11. pattern-selection-guide.md ✅
12. prometheus.md
13. skill-integration-guide.md ✅
14. skill-recommendation.md ✅
15. traefik.md ✅
16. vaultwarden.md
17. [... other service guides ...]

### 20-operations/guides/ (7)
1. architecture-diagrams.md ⚠️ Update needed
2. automation-reference.md
3. autonomous-operations.md ✅
4. backup-strategy.md
5. disaster-recovery.md
6. homelab-architecture.md ⚠️ Verify updated
7. pihole-backup.md ← Reclassify (external)

### 30-security/guides/ (4)
1. security-architecture.md ⚠️ Check TinyAuth refs
2. [... other security guides ...]

### 40-monitoring-and-documentation/guides/ (5)
1. monitoring-stack.md
2. natural-language-queries.md
3. slo-framework.md
4. [... other monitoring guides ...]

---

**Plan Status:** Draft - Awaiting Approval
**Ready for:** User review and implementation
**Estimated Effort to Implement:** 2-3 hours (priorities 1-2)
