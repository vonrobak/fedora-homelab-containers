# Documentation Contribution Guide

**Last Updated:** 2025-12-18
**Purpose:** Standards and conventions for homelab documentation

---

## Quick Start

**Before adding documentation:**
1. Determine document type (guide, journal, plan, decision)
2. Choose the appropriate directory
3. Follow naming conventions below
4. Place in correct location

---

## Directory Structure

```
docs/
├── 97-plans/              # Strategic planning documents
│   └── [forward-looking plans and roadmaps]
│
├── 98-journals/           # Chronological project history (FLAT)
│   └── [all dated logs, sessions, deployments]
│
├── 99-reports/            # System state snapshots
│   ├── intel-*.json      # Automated health reports
│   └── SYSTEM-STATE-*.md # Formal infrastructure snapshots
│
├── 00-foundation/         # Core concepts and design patterns
│   ├── guides/           # Living reference documentation
│   └── decisions/        # Architecture Decision Records
│
├── 10-services/          # Service-specific documentation
│   ├── guides/           # Service operation guides
│   └── decisions/        # Service architecture decisions
│
├── 20-operations/        # Operational procedures and architecture
│   ├── guides/           # How-to operational documentation
│   ├── decisions/        # Operational policy decisions
│   └── runbooks/         # Disaster recovery procedures
│
├── 30-security/          # Security configuration and incidents
│   ├── guides/           # Security procedures and policies
│   ├── decisions/        # Security architecture decisions
│   └── runbooks/         # Incident response procedures
│
├── 40-monitoring-and-documentation/
│   ├── guides/           # Monitoring and documentation guides
│   └── decisions/        # Monitoring decisions
│
└── 90-archive/           # Superseded documentation
```

---

## Document Types

### 1. Guides (Living Documents)

**Purpose:** Reference documentation that's kept current

**Characteristics:**
- Updated in place when information changes
- No date prefix in filename
- Focus on "how it is now" not "how it was"

**Location:** `*/guides/`

**Naming:**
```
<topic>.md
<service-name>.md
<procedure-name>.md

Examples:
- podman-fundamentals.md
- jellyfin.md
- backup-strategy.md
- middleware-patterns.md
```

**Template:**
```markdown
# <Title>

**Last Updated:** YYYY-MM-DD
**Maintainer:** <username>

## Overview
[Current state description]

## [Sections as appropriate]
...
```

---

### 2. Journal Entries (Dated Logs)

**Purpose:** Chronological record of learning, changes, and progress

**Characteristics:**
- Never updated after creation (append-only)
- Always has date prefix
- Records the journey and decision context
- Includes session logs, deployments, strategic assessments

**Location:** `98-journals/` (flat directory, all entries together)

**Naming:**
```
YYYY-MM-DD-<description>.md

Examples:
- 2025-11-07-monitoring-deployment.md
- 2025-10-26-middleware-ordering-experiment.md
- 2025-11-05-project-state-crossroads.md
- 2025-11-12-session-summary.md
- 2025-11-09-strategic-assessment.md
```

**Template:**
```markdown
# <Title>

**Date:** YYYY-MM-DD
**Context:** [Why this work was done]

## What Was Done
...

## Lessons Learned
...

## Next Steps
...
```

---

### 3. Plans (Strategic Documents)

**Purpose:** Forward-looking plans, proposals, and roadmaps

**Characteristics:**
- Living documents (status updated as work progresses)
- Always has date prefix
- Includes status metadata
- Not archived automatically (user decides)

**Location:** `97-plans/`

**Naming:**
```
YYYY-MM-DD-<description>.md

Examples:
- 2025-11-22-disaster-recovery-plan.md
- 2025-11-28-autonomous-operations-expansion.md
- 2025-12-01-multi-service-orchestration.md
```

**Template:**
```markdown
# <Plan Title>

**Date Created:** YYYY-MM-DD
**Status:** Proposed | In Progress | Implemented
**Last Updated:** YYYY-MM-DD

## Objective
[What are we trying to achieve?]

## Approach
[How will we do it?]

## Success Criteria
[How will we know it worked?]

## Implementation Timeline
[Key milestones - no specific dates]

## Progress Log
[Update as work progresses]
```

**Lifecycle:**
- Plans stay in 97-plans throughout their lifecycle
- Update status metadata as work progresses
- Document implementation in 98-journals
- Archive manually when no longer relevant

---

### 4. Architecture Decision Records (ADRs)

**Purpose:** Document significant architectural decisions and their rationale

**Characteristics:**
- Immutable once written (never edited, only superseded)
- Numbered sequentially
- Follows ADR format

**Location:** `*/decisions/`

**Naming:**
```
YYYY-MM-DD-decision-<number>-<title>.md

Examples:
- 2025-10-20-decision-001-rootless-containers.md
- 2025-10-25-decision-002-traefik-over-caddy.md
- 2025-11-06-decision-003-monitoring-stack-architecture.md
```

**Template:**
```markdown
# ADR-<number>: <Title>

**Date:** YYYY-MM-DD
**Status:** Accepted | Superseded by ADR-XXX | Deprecated

## Context
[What is the issue motivating this decision?]

## Decision
[What is the change we're proposing/making?]

## Consequences
[What becomes easier or more difficult?]

## Alternatives Considered
[What other options were evaluated?]
```

---

### 5. Reports (System State Snapshots)

**Purpose:** Automated system reports and formal infrastructure snapshots

**Characteristics:**
- Immutable historical record
- Machine-generated (JSON) or formal snapshots (markdown)
- Consumed by automation or used as authoritative reference

**Location:** `99-reports/`

**Contents:**
- **Automated JSON:** `intel-*.json`, `resource-forecast-*.json` (do not modify)
- **Formal snapshots:** `SYSTEM-STATE-YYYY-MM-DD.md` (rare, authoritative)

**Note:** Most dated markdown documentation now goes in `98-journals/`. Only use `99-reports/` for:
- Automated system output (JSON)
- Formal infrastructure state snapshots (rare)

**Naming for formal snapshots:**
```
SYSTEM-STATE-YYYY-MM-DD.md

Example:
- SYSTEM-STATE-2025-11-06.md
```

---

### 6. Incident Post-Mortems

**Purpose:** Document security incidents and operational failures

**Characteristics:**
- Written after incident resolution
- Focus on learning, not blame
- Include remediation and prevention

**Location:** `30-security/incidents/`

**Naming:**
```
YYYY-MM-DD-incident-<description>.md

Examples:
- 2025-11-05-incident-secrets-in-git.md
- 2025-10-20-incident-certificate-expiry.md
```

**Template:**
```markdown
# Incident: <Title>

**Date:** YYYY-MM-DD
**Severity:** Critical | High | Medium | Low
**Status:** Resolved | Ongoing

## Summary
[One-paragraph description]

## Timeline
[Chronological events]

## Root Cause
[What actually caused this?]

## Impact
[What was affected?]

## Resolution
[How was it fixed?]

## Prevention
[How do we prevent recurrence?]

## References
[Related documentation, commits, etc.]
```

---

## Naming Conventions Summary

| Document Type | Date Prefix? | Location | Example |
|---------------|--------------|----------|---------|
| Guide | No | `*/guides/` | `jellyfin.md` |
| Journal | Yes | `98-journals/` | `2025-11-07-deployment-log.md` |
| Plan | Yes | `97-plans/` | `2025-11-22-disaster-recovery.md` |
| ADR | Yes | `*/decisions/` | `2025-11-07-decision-001-title.md` |
| Report | N/A | `99-reports/` | `SYSTEM-STATE-2025-11-06.md` or `intel-*.json` |
| Incident | Yes | `98-journals/` | `2025-11-23-immich-data-loss-incident.md` |

---

## When to Update vs. Create New

### Update Existing (Guides)
- Service configuration changed
- Operational procedure improved
- Architectural diagram needs correction
- Best practices evolved

### Create New (Journal/Plan/ADR)
- Documenting a change or deployment → journal
- Planning a new project or initiative → plan
- Recording an architectural decision → ADR
- Session work log → journal
- Strategic assessment → journal
- Learning log from experimentation → journal

---

## Archiving Documentation

### When to Archive

Archive a document when:
1. **Superseded:** A newer document replaces it entirely
2. **Obsolete:** Technology/service no longer in use
3. **Outdated:** Information no longer relevant
4. **Consolidated:** Multiple docs merged into one

### How to Archive

```bash
# 1. Move to archive
git mv docs/<category>/<file>.md docs/90-archive/

# 2. Add archival header to the file
```

**Archival Header:**
```markdown
> **ARCHIVED:** YYYY-MM-DD
> **Reason:** [Why archived]
> **Superseded by:** [Link to new doc if applicable]
> **Historical context:** [Why this doc existed]
```

### Archive Index

Update `docs/90-archive/ARCHIVE-INDEX.md` when archiving:

```markdown
## YYYY-MM-DD: <filename>
- **Original location:** docs/<category>/<filename>
- **Reason:** [Why archived]
- **Superseded by:** [New doc if applicable]
- **Value:** [Why keeping it in archive]
```

---

## Documentation Review Checklist

Before committing documentation:

- [ ] File is in correct directory (97-plans/, 98-journals/, */guides/, */decisions/)
- [ ] Filename follows naming convention
- [ ] Date prefix is present (if required for document type)
- [ ] Document has required metadata header
- [ ] Internal links are valid
- [ ] Code examples are tested
- [ ] Sensitive information removed (secrets, passwords, API keys)
- [ ] CLAUDE.md updated if architecture/process changed

---

## Maintenance Schedule

### After Every Major Change
- Update relevant guide documents
- Create journal entry documenting the change
- Create ADR if architectural decision was made

### Monthly
- Review guides for accuracy
- Check for broken links
- Identify candidates for archival

### Quarterly
- Comprehensive documentation audit
- Update documentation index
- Clean up archive (add metadata)
- Review naming convention compliance

---

## Tools and Automation

### Check for Broken Links
```bash
# Find markdown files with links to non-existent files
grep -r "\[.*\](.*\.md)" docs/ | while read line; do
  # Extract file paths and verify they exist
  # (script to be implemented)
done
```

### List Files Violating Naming Convention
```bash
# Find files in 98-journals/, 97-plans/, or decisions/ without date prefix
find docs/98-journals docs/97-plans docs/*/decisions -name "*.md" ! -name "20[0-9][0-9]-*"
```

### Identify Archival Candidates
```bash
# Find journal entries older than 1 year
find docs/98-journals -name "*.md" -mtime +365
```

---

## Examples

### Example 1: Deploying New Service

**Steps:**
1. Create deployment journal entry: `docs/98-journals/2025-11-07-vaultwarden-deployment.md`
2. Create/update service guide: `docs/10-services/guides/vaultwarden.md`
3. If architectural decision made: `docs/10-services/decisions/2025-11-07-decision-004-vaultwarden-database-choice.md`
4. Update `CLAUDE.md` if needed

### Example 2: Planning a New Project

**Steps:**
1. Create plan: `docs/97-plans/2025-11-22-disaster-recovery-testing.md`
2. Add status metadata in file header
3. As work progresses, document in journals: `docs/98-journals/2025-11-23-dr-testing-phase1.md`
4. Update plan status when milestones complete

### Example 3: Security Incident

**Steps:**
1. Create incident journal: `docs/98-journals/2025-11-07-incident-exposed-api-key.md`
2. Update security guide if process changed: `docs/30-security/guides/secrets-management.md`
3. Create ADR if policy changed: `docs/30-security/decisions/2025-11-07-decision-005-mandatory-vault.md`

### Example 4: Operational Procedure Change

**Steps:**
1. Update procedure guide: `docs/20-operations/guides/backup-restore.md`
2. Create journal entry explaining why: `docs/98-journals/2025-11-07-backup-procedure-improvement.md`
3. Archive old procedure if completely replaced

---

## Questions?

When in doubt:
1. Check existing docs for similar examples
2. Prefer creating new dated docs over updating old ones
3. Guides are living, everything else is immutable
4. Archive rather than delete
5. Document decisions, not just implementations

---

**Remember:** Documentation is a love letter to your future self. Be kind to them. 💙
