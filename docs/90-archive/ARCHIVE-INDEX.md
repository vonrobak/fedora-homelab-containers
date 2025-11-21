# Archive Index

**Last Updated:** 2025-11-18
**Purpose:** Catalog of archived documentation with archival context

---

## Overview

This directory contains **superseded documentation** preserved for historical reference. Files here are:
- No longer current or accurate
- Replaced by newer documentation
- Failed experiments or abandoned approaches
- Historical snapshots of system evolution

**These files should NOT be used for operations** - they are historical artifacts only.

---

## Archival Categories

### 📚 Superseded Documentation

**What:** Documentation replaced by newer, more accurate versions

| File | Archived | Reason | Superseded By |
|------|----------|--------|---------------|
| `20251025-documentation-index.md` | 2025-11-07 | Outdated index with broken references | `docs/README.md` |
| `20251025-homelab-architecture-diagrams.md` | 2025-11-07 | Superseded by current architecture docs | `docs/20-operations/guides/architecture-diagrams.md` |
| `20251025-homelab-architecture-finalform.md` | 2025-11-07 | Called "final form" but architecture evolved | `docs/20-operations/guides/homelab-architecture.md` |
| `HOMELAB-ARCHITECTURE-DOCUMENTATION.md` | 2025-11-07 | Earlier version, now outdated | `docs/20-operations/guides/homelab-architecture.md` |
| `QUICK-REFERENCE.md` | 2025-11-07 | Commands out of date, structure changed | Service-specific guides in `docs/10-services/guides/` |
| `quick-reference.md` | 2025-11-07 | Duplicate of QUICK-REFERENCE | (same as above) |
| `quick-reference-v2.md` | 2025-11-07 | Second iteration, also outdated | (same as above) |
| `tinyauth-service-guide.md` | 2025-11-14 | TinyAuth superseded by Authelia SSO | `docs/10-services/guides/authelia.md` + ADR-005 |
| `tinyauth-setup-guide.md` | 2025-11-14 | TinyAuth setup obsolete after Authelia migration | `docs/30-security/decisions/2025-11-11-decision-005-authelia-sso-yubikey-deployment.md` |

**Why preserved:** Shows documentation evolution and early architectural decisions. TinyAuth guides document the pragmatic "start simple, upgrade later" authentication journey from basic username/password to hardware-based 2FA with YubiKey.

---

### 🔬 Failed Experiments

**What:** Attempted implementations that didn't work out

| File | Date | Experiment | Outcome |
|------|------|------------|---------|
| `failed-authelia-adventures-of-week-02-current-state-of-system.md` | 2025-10-22 | Authelia SSO deployment | Failed due to complexity, switched to TinyAuth |
| `week02-failed-authelia-but-tinyauth-goat.md` | 2025-10-22 | Same experiment, different perspective | TinyAuth chosen as simpler alternative |
| `authelia-diag-20251020-183321.txt` | 2025-10-20 | Diagnostic output during Authelia attempt | Troubleshooting logs before abandoning |
| `script2-week2-authelia-dual-domain.md` | 2025-10-21 | Dual-domain Authelia approach | Never completed, TinyAuth deployed instead |

**Why preserved:** Important learning - documents what DIDN'T work and why
- Authelia was too complex for initial needs
- WebAuthn required valid TLS (self-signed certificates blocked it)
- TinyAuth provided "good enough" solution
- Authelia remains on roadmap for future (with proper TLS + hardware 2FA)

**Lesson:** Sometimes simpler is better. Perfect is enemy of good.

---

### 📋 Planning & Checklists (Historical)

**What:** Week 2 planning documents and checklists from early project phase

| File | Date | Purpose | Status |
|------|------|---------|--------|
| `checklist-week02.md` | 2025-10-20 | Week 2 task checklist | Completed, archived |
| `week02-implementation-plan.md` | 2025-10-20 | Week 2 implementation strategy | Completed, evolved differently than planned |
| `week02-security-and-tls.md` | 2025-10-20 | Security hardening plan | Completed, documented in security guides |
| `quick-start-guide-week02.md` | 2025-10-20 | Week 2 quick start | Superseded by service guides |
| `TOMORROW-QUICK-START.md` | 2025-10-22 | Next-day task list | Completed, no longer relevant |
| `revised-learning-plan.md` | 2025-10-20 | Adjusted learning roadmap | Mostly followed, now outdated |
| `progress.md` | 2025-10-22 | Early progress tracking | Superseded by journal entries |

**Why preserved:** Shows project planning evolution and how plans change during execution

**Insight:** Original plans were ambitious but realistic. Actual implementation followed ~70% of plan, with pragmatic adjustments (TinyAuth instead of Authelia, etc.)

---

### 📅 Session Planning & Handoffs (Completed)

**What:** Planning and handoff documents for completed Claude Code sessions

| File | Archived | Session | Superseded By |
|------|----------|---------|---------------|
| `2025-11-09-handoff-next-steps.md` | 2025-11-18 | Planning session | Session execution reports in 99-reports/ |
| `2025-11-14-session-2-cli-handoff.md` | 2025-11-18 | Session 2 | `2025-11-14-session-2-validation-report.md` |
| `2025-11-14-session-3-proposal.md` | 2025-11-18 | Session 3 | `2025-11-14-session-3-completion-summary.md` |
| `pr-description-planning-session.md` | 2025-11-18 | Planning PR | PR merged/closed |

**Why preserved:** Documents planning-to-execution workflow and session coordination between Claude Code Web and CLI

**Historical value:** Shows how Web/CLI hybrid approach evolved, session planning methodology, and how Claude Code sessions build on each other. These handoff documents were transitional - valuable during execution but superseded by completion reports.

---

### 📊 Storage Architecture Evolution

**What:** Multiple iterations of storage documentation as design evolved

| File | Date | Version | Status |
|------|------|---------|--------|
| `20251023-storage_data_architecture_revised.md` | 2025-10-23 | Revision 1 | Superseded by Rev 2 |
| `20251024-storage_data_architecture-and-2fa-proposal.md` | 2025-10-24 | Combined storage + 2FA | Split into separate docs |
| `2025-10-24-storage_data_architecture_tailored_addendum.md` | 2025-10-24 | Addendum to main doc | Consolidated into Rev 2 |
| `storage-architecture-addendum-2025-10-25T14-34-55Z.md` | 2025-10-25 | Timestamped addendum | Consolidated |

**Current authoritative:** `docs/99-reports/20251025-storage-architecture-authoritative-rev2.md`

**Why preserved:** Shows how storage design evolved through multiple revisions
- Initial design was good but incomplete
- BTRFS subvolume strategy refined over time
- NOCOW requirements discovered during deployment

---

### 🔧 Configuration Snapshots

**What:** Point-in-time summaries and configuration states

| File | Date | Purpose | Value |
|------|------|---------|-------|
| `DOMAIN-CHANGE-SUMMARY.md` | 2025-10-21 | Domain migration documentation | Historical context for domain change |
| `summary-revised.md` | 2025-10-22 | System state summary | Superseded by 99-reports/ snapshots |
| `latest-summary.md` | 2025-10-23 | "Latest" snapshot (no longer latest) | Superseded |
| `SCRIPT-EXPLANATION.md` | 2025-10-21 | Script documentation | Unclear which script, low value |
| `readme.md` | 2025-10-22 | Early project readme | Superseded by current README.md |

**Why preserved:** Provides timestamps for when certain changes occurred

---

### 🔍 Diagnostic Outputs

**What:** System diagnostic reports from troubleshooting sessions

| File | Date | Type | Context |
|------|------|------|---------|
| `homelab-diagnose-20251021-165859.txt` | 2025-10-21 | Full system diagnostic | Pre-monitoring stack |
| `system-state-20251022-213400.txt` | 2025-10-22 | System state report | Mid-deployment |
| `pre-letsencrypt-diag-20251022-161247.txt` | 2025-10-22 | Pre-certificate diagnostic | Before Let's Encrypt setup |
| `20251025-storage-survey.txt` | 2025-10-25 | Storage usage survey | Before BTRFS pool expansion |
| `authelia-diag-20251020-183321.txt` | 2025-10-20 | Authelia troubleshooting | Failed deployment attempt |

**Why preserved:** Diagnostic outputs capture system state at specific moments
- Useful for understanding system evolution
- Shows what issues existed and when
- Demonstrates troubleshooting process

**Note:** Current diagnostics go to `docs/99-reports/` with better naming

---

### 🗑️ Backup Files (.bak) - ✅ PREVIOUSLY REMOVED

**What:** Git-tracked backup files (anti-pattern!) that were removed

**Status:** ✅ These files were already removed before 2025-11-18 cleanup

**Files that were removed:**
- `readme.bak-20251021-172023.md`
- `readme.bak-20251021-221915.md`
- `quick-reference.bak-20251021-172023.md`
- `quick-reference.bak-20251021-221915.md`

**Reason for removal:** Git already provides complete history, backup files polluted repository

**Lesson learned:** Use Git for versioning, not file copies with .bak extensions

---

### 📦 Nextcloud Planning (Abandoned/Postponed)

**What:** Nextcloud installation planning document

| File | Date | Status |
|------|------|--------|
| `NEXTCLOUD-INSTALLATION-GUIDE.md` | 2025-10-24 | Planned but not implemented |

**Why archived:** Nextcloud deployment postponed indefinitely
- Current focus: monitoring and observability
- Nextcloud adds significant complexity (PostgreSQL, Redis, etc.)
- May deploy in future when ready for additional services

**Why preserved:** Complete planning already done, ready when needed

---

## Archival Policies

### When to Archive

Archive a file when:
1. **Superseded:** Newer, more accurate documentation exists
2. **Obsolete:** Technology/approach no longer in use
3. **Failed:** Experiment didn't work out (but preserve learning)
4. **Outdated:** Information no longer reflects current state

### When NOT to Archive

Don't archive:
- Current operational documentation (goes in `guides/`)
- Recent journal entries (stay in `journal/` for at least 6 months)
- Active ADRs (even if decision later reversed, ADR stays in `decisions/`)

### How to Archive

```bash
# 1. Move to archive
git mv docs/<category>/<file>.md docs/90-archive/

# 2. Add archival header (see template below)
# 3. Update ARCHIVE-INDEX.md (this file)
# 4. Commit with reason
git commit -m "Archive <file>: <reason>"
```

### Archival Header Template

Add to top of archived file:

```markdown
> **🗄️ ARCHIVED:** YYYY-MM-DD
>
> **Reason:** [Why this was archived]
>
> **Superseded by:** [Link to current doc, if applicable]
>
> **Historical context:** [Why this document existed and what it represented]
>
> **Value:** [Why we're keeping this instead of deleting]
>
> ---
```

---

## Usage Guidelines

### For Historical Research

**When to consult archive:**
- Understanding how current architecture evolved
- Learning from past mistakes (failed experiments)
- Researching why certain decisions were made
- Tracking when specific changes occurred

**Example:** "Why did we choose TinyAuth over Authelia?"
→ Read `failed-authelia-adventures` and `week02-failed-authelia-but-tinyauth-goat.md`

### For Learning

**Value of archived docs:**
- Shows real learning progression (not sanitized success stories)
- Documents dead ends and why they failed
- Demonstrates iterative improvement
- Honest account of complexity and challenges

**Example:** Multiple storage architecture revisions show how design refined through real-world usage

### For Documentation Maintenance

**Use archive to:**
- Avoid recreating failed approaches
- Learn from past documentation mistakes
- Understand what information users actually needed (vs what was documented)
- Track documentation evolution

---

## Cleanup Recommendations

### Immediate Actions

1. **Remove .bak files** - Git already tracks history
   ```bash
   git rm docs/90-archive/*.bak-*.md
   ```

2. **Add archival headers** to key files:
   - Failed experiments (Authelia docs)
   - Superseded architecture docs
   - Old indexes and references

### Future Archival Candidates

**From active documentation** (periodically review):
- Journal entries >1 year old (keep most recent year active)
- Deployment logs for decommissioned services
- Reports superseded by newer state snapshots

**Don't archive:**
- ADRs (immutable by design, stay in `decisions/`)
- Current guides (updated in place)
- Recent journal entries (<6 months)

---

## Statistics

**Archive contents:**
- Total files: 42
- Markdown docs: 38
- Diagnostic outputs: 4
- Backup files: 0 (previously removed)
- Significant docs: ~21 (with useful historical context)

**Categories:**
- Superseded documentation: 9 files (includes TinyAuth guides)
- Failed experiments: 4 files
- Planning/checklists: 7 files
- Session handoffs: 4 files (added 2025-11-18)
- Storage evolution: 4 files
- Configuration snapshots: 5 files
- Diagnostic outputs: 5 files
- Backup files: 0 (previously removed)

**Date range:** October 20, 2025 - November 18, 2025 (includes Session 4 context framework completion)

---

## Lessons from Archive

### What We Learned

**From failed Authelia experiment:**
- Complex != better
- Valid TLS certificates matter for WebAuthn
- Start simple, add complexity when needed
- "Good enough" beats "perfect someday"

**From storage iterations:**
- Design evolves through real-world usage
- Initial designs are rarely perfect
- Document decisions AND revisions
- NOCOW matters for databases on BTRFS

**From multiple quick-reference versions:**
- One canonical reference > many variations
- Consolidate instead of duplicate
- Use Git for versioning, not file copies

**From diagnostic outputs:**
- Timestamped snapshots are valuable
- Troubleshooting logs tell important stories
- System state at problem time helps future debugging

### Applied to Current Documentation

**Improvements made:**
- Single source of truth for each topic
- Clear naming conventions (no more "v2", "revised", "final")
- Proper versioning through Git (no .bak files)
- Structured directories (guides vs journal vs decisions)
- Archive with metadata (this index!)

---

## Questions?

**"Should I reference archived docs?"**
- Only for historical context, never for operations

**"Should I delete archived docs?"**
- No! They provide valuable historical context and learning

**"When do I move something to archive?"**
- When superseded by newer documentation
- When experiment/approach abandoned
- When information no longer accurate

**"What about old journal entries?"**
- Keep recent ones active (6-12 months)
- Archive very old ones (>1 year) when they're no longer referenced

---

**Maintained by:** patriark + Claude Code
**Review frequency:** Quarterly
**Next review:** 2025-02-07
**Purpose:** Preserve project history while keeping current docs clean
