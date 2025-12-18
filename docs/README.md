# Homelab Documentation

**Last Updated:** 2025-12-18
**System:** fedora-htpc production environment
**Documentation Files:** 200+ files across structured directories
**Status:** 🎯 Production | 🔐 SSO with YubiKey | 📊 Full Observability | 🤖 Autonomous Operations

---

## 🚀 Quick Start

**New to this homelab?** Start here:
1. Read this index (you are here)
2. Review [CONTRIBUTING.md](CONTRIBUTING.md) for documentation conventions
3. Browse [98-journals/](98-journals/) for chronological project history
4. Check [97-plans/](97-plans/) for active planning documents
5. Explore service guides in `*/guides/` subdirectories

**Common tasks:**
- **Health check:** `./scripts/homelab-intel.sh`
- **Natural language query:** `./scripts/query-homelab.sh "your question"`
- **System diagnostics:** `./scripts/homelab-diagnose.sh`

---

## 📖 Documentation Structure

### Three-Tier Organization

This documentation uses a **clear separation of concerns**:

1. **Forward-looking** (`97-plans/`) - Strategic plans and roadmaps
2. **Historical** (`98-journals/`) - Chronological project timeline
3. **Current state** (`*/guides/`) - Living reference documentation

### Directory Overview

```
docs/
├── 97-plans/                           # Strategic planning documents
│   ├── PROJECT-A-DISASTER-RECOVERY-PLAN.md
│   ├── SESSION-5-MULTI-SERVICE-ORCHESTRATION-PLAN.md
│   └── [Status: Proposed | In Progress | Implemented]
│
├── 98-journals/                        # Complete chronological history (FLAT)
│   ├── 2025-10-20-day01-foundation-learnings.md
│   ├── 2025-11-09-strategic-assessment.md
│   ├── 2025-12-18-quarterly-documentation-review.md
│   └── [92 entries - sessions, deployments, strategic thinking]
│
├── 99-reports/                         # System state snapshots
│   ├── intel-*.json                    (94 automated health reports)
│   ├── resource-forecast-*.json        (predictive analytics)
│   └── SYSTEM-STATE-2025-11-06.md      (formal infrastructure snapshot)
│
├── 00-foundation/                      # Core concepts
│   ├── guides/                         # Podman, networking, design patterns
│   └── decisions/                      # Fundamental ADRs
│
├── 10-services/                        # Service documentation
│   ├── guides/                         # Immich, Jellyfin, Traefik, etc.
│   └── decisions/                      # Service architecture ADRs
│
├── 20-operations/                      # Operations procedures
│   ├── guides/                         # Backup, monitoring, maintenance
│   ├── decisions/                      # Operational policy ADRs
│   └── runbooks/                       # DR and incident response
│
├── 30-security/                        # Security hardening
│   ├── guides/                         # SSH, YubiKey, secrets management
│   ├── decisions/                      # Security architecture ADRs
│   └── runbooks/                       # Security incidents
│
├── 40-monitoring-and-documentation/    # Observability
│   ├── guides/                         # Prometheus, Grafana, Loki, SLOs
│   └── decisions/                      # Monitoring decisions
│
└── 90-archive/                         # Superseded documentation
```

---

## 🎯 Finding What You Need

### Current System Information

**System health:**
```bash
./scripts/homelab-intel.sh              # Health score (0-100) + recommendations
./scripts/query-homelab.sh "status?"    # Natural language queries
```

**Service guides:** All in `*/guides/` subdirectories
- **Immich:** `10-services/guides/immich.md`
- **Jellyfin:** `10-services/guides/jellyfin.md`
- **Traefik:** `10-services/guides/traefik.md`
- **Authelia:** `10-services/guides/authelia.md` (SSO + YubiKey MFA)
- **Monitoring:** `40-monitoring-and-documentation/guides/monitoring-stack.md`
- **Backup:** `20-operations/guides/backup-strategy.md`

### Understanding Project History

**Chronological timeline:** Browse `98-journals/` sorted by date
```bash
# What happened in November?
ls -1 98-journals/2025-11-*.md

# Recent work (last 10 entries)
ls -1t 98-journals/*.md | head -10

# Find strategic assessments
grep -l "strategic" 98-journals/*.md
```

**Key milestones:**
- 2025-10-20: Foundation learnings (Podman, networking)
- 2025-10-23: First service deployment (Jellyfin)
- 2025-11-06: Monitoring stack operational
- 2025-11-11: Authelia SSO with YubiKey deployed
- 2025-11-28: Autonomous operations activated
- 2025-12-18: Documentation structure reorganized

### Planning Documents

**Active plans:** See `97-plans/`
- Disaster recovery testing framework
- Security hardening roadmap
- Autonomous operations expansion
- Multi-service orchestration

Plans include status metadata (Proposed | In Progress | Implemented).

### Architecture Decisions

**Why certain choices were made:** See `*/decisions/` subdirectories

**Key ADRs:**
- **ADR-001:** Rootless containers (00-foundation)
- **ADR-002:** Systemd quadlets over Docker Compose (00-foundation)
- **ADR-003:** Monitoring stack architecture (40-monitoring)
- **ADR-004:** Authelia SSO with YubiKey-first authentication (30-security)
- **ADR-006:** Service dependency mapping (20-operations)
- **ADR-008:** Autonomous operations alert quality (20-operations)

---

## 📂 Directory Details

### 97-plans: Strategic Planning

**Purpose:** Forward-looking plans, proposals, and roadmaps

**Contents:**
- Project proposals (PROJECT-A, PROJECT-B, etc.)
- Session planning documents
- Implementation roadmaps
- Strategic initiatives

**Lifecycle:**
- Plans stay in 97-plans throughout their lifecycle
- Status updated via metadata in file header
- Implementation documented in 98-journals
- Manually archived by user when no longer relevant

**Naming:** Will be migrating to `YYYY-MM-DD-description.md` format

### 98-journals: Chronological History

**Purpose:** Complete project timeline in one place

**Contents:**
- Daily/weekly work logs
- Deployment summaries
- Strategic assessments
- Implementation notes
- Session summaries
- Troubleshooting logs
- Incident reports

**Characteristics:**
- **Flat structure** - All 92 files in one directory
- **Chronologically sorted** - YYYY-MM-DD prefix enables natural sorting
- **Immutable** - Never edited after creation (append-only log)
- **Complete timeline** - Shows both tactical work AND strategic thinking

**Why flat?**
- Easier to browse chronologically: `ls 98-journals/2025-11-*.md`
- Single source of truth for "what happened when"
- Simplifies navigation vs. multi-directory search

### 99-reports: System State Snapshots

**Purpose:** Machine-generated reports and formal state documentation

**Contents:**
- **Automated JSON reports:**
  - `intel-YYYYMMDD-HHMMSS.json` - Daily system health (used by automation)
  - `resource-forecast-YYYYMMDD-HHMMSS.json` - Predictive analytics
  - `weekly-latest.json` - Weekly rollup
- **Formal snapshots:**
  - `SYSTEM-STATE-YYYY-MM-DD.md` - Infrastructure state documentation

**Automation dependencies:**
- `weekly-intelligence-report.sh` reads last 7 `intel-*.json` files
- `autonomous-check.sh` reads latest `intel-*.json`
- **DO NOT rename JSON files** - glob patterns are hardcoded

---

## 🛠️ Common Tasks

### Deploying a New Service

1. Check architectural fit (networking, security, resources)
2. Create journal entry: `98-journals/YYYY-MM-DD-<service>-deployment.md`
3. Deploy and test (use deployment patterns from `.claude/skills/homelab-deployment/`)
4. Create/update service guide: `10-services/guides/<service>.md`
5. If architectural decision made, create ADR: `*/decisions/YYYY-MM-DD-decision-NNN-<title>.md`

### Planning a New Project

1. Create plan: `97-plans/<descriptive-name>.md` (will migrate to dated format)
2. Add status metadata in file header
3. As work progresses, document in `98-journals/YYYY-MM-DD-<work-log>.md`
4. Update plan status when completed

### Regular Maintenance

**Weekly:**
- Review `podman ps` for service health
- Check disk usage: `df -h / /mnt/btrfs-pool`
- Review monitoring dashboards

**Monthly:**
- Update service guides if configurations changed
- Review planning documents for progress
- Check for documentation needing archival

**Quarterly:**
- Full documentation audit (review all guides for accuracy)
- Update documentation index (this file)
- Review and clean up journals for potential archival

---

## 🔍 Search Tips

### Finding Files by Topic

```bash
# Search all documentation for a keyword
grep -r "traefik" docs/ --include="*.md"

# Find all guides
find docs/*/guides -name "*.md"

# Find journals from specific month
ls -1 docs/98-journals/2025-11-*.md

# Find all ADRs
find docs/*/decisions -name "*.md"
```

### Finding Latest Information

```bash
# Most recently updated files
find docs/ -name "*.md" -type f -mtime -7

# Latest system health report
./scripts/homelab-intel.sh

# Most recent journal entries
ls -1t docs/98-journals/*.md | head -10
```

---

## 📚 External Resources

### Project Documentation
- **CLAUDE.md** - AI assistant context and common commands
- **CONTRIBUTING.md** - Documentation contribution guide
- **README.md** - This file

### Key Scripts
- `scripts/homelab-intel.sh` - System health scoring + recommendations
- `scripts/homelab-diagnose.sh` - Comprehensive diagnostics
- `scripts/query-homelab.sh` - Natural language queries (cached)
- `scripts/autonomous-check.sh` - OODA loop assessment

See `docs/20-operations/guides/automation-reference.md` for complete script catalog.

---

## 🎓 Learning Path

### New to Homelabs

Read journals chronologically to follow the learning journey:

1. **Foundation** (Oct 20-22, 2025)
   - 2025-10-20: Day 1 foundation learnings
   - 2025-10-21: Day 2 networking exploration
   - 2025-10-22: Day 3 pods exploration

2. **First Services** (Oct 23-25)
   - 2025-10-23: Jellyfin deployment
   - 2025-10-25: Traefik quadlet migration

3. **Security** (Oct 26-30)
   - 2025-10-26: YubiKey inventory
   - 2025-10-30: YubiKey success summary

4. **Operational Maturity** (Nov 2025)
   - 2025-11-06: Monitoring stack deployment
   - 2025-11-07: Backup automation
   - 2025-11-11: Authelia SSO deployment
   - 2025-11-28: Autonomous operations activated

---

## ❓ FAQ

**Q: Where do I find the latest system state?**
A: Run `./scripts/homelab-intel.sh` for current health, or check latest `99-reports/intel-*.json`

**Q: Should I update an existing doc or create a new one?**
A: Update guides (living docs), create new journal entries (dated logs). See CONTRIBUTING.md for details.

**Q: Where do I document a new service deployment?**
A: Create journal entry in `98-journals/YYYY-MM-DD-<service>-deployment.md`, then create/update guide in `10-services/guides/<service>.md`

**Q: What's the difference between plans and journals?**
A: Plans are forward-looking (what we'll do). Journals are historical (what we did). Plans stay in 97-plans; implementation gets documented in 98-journals.

---

## 🎯 Documentation Maturity

**Current Status (Dec 18, 2025):**
- ✅ Three-tier structure implemented (plans / journals / reports)
- ✅ Flat journal directory for chronological browsing
- ✅ 92 journal entries consolidated
- ✅ 13 planning documents organized
- ✅ Automated reports separated from human docs
- ✅ Core service guides complete
- ✅ Key ADRs written (ADR-001 through ADR-008)
- ⏳ Plan files need YYYY-MM-DD prefix migration
- ⏳ Next quarterly audit: March 2026

---

## 📞 Getting Help

**System issues:**
- `./scripts/homelab-intel.sh` for health assessment
- `./scripts/homelab-diagnose.sh` for diagnostics
- Service guides in `10-services/guides/`

**Natural language queries:**
```bash
./scripts/query-homelab.sh "what services are using the most memory?"
./scripts/query-homelab.sh "is jellyfin running?"
```

---

**Remember:** Documentation is a love letter to your future self. Keep it current, clear, and kind. 💙

**Last maintained:** 2025-12-18 by Claude Code
**Review frequency:** Quarterly
**Next review:** 2026-03-18
