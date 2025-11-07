# Homelab Documentation

**Last Updated:** 2025-11-07
**System:** fedora-htpc production environment
**Documentation Files:** 83+ markdown files

---

## 🚀 Quick Start

**New to this homelab?** Start here:
1. Read this index (you are here)
2. Review [CONTRIBUTING.md](CONTRIBUTING.md) for documentation conventions
3. Check [99-reports/](99-reports/) for latest system state
4. Browse [guides/](*/guides/) subdirectories for current operational documentation

**Making changes?** See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Documentation structure and conventions
- Naming standards
- When to update vs. create new
- Templates for each document type

---

## 📖 Documentation Structure

### Hybrid Approach

This documentation uses a **hybrid structure** that provides:
- **Reference documentation** (`guides/`) - Current "how-to" information (living documents)
- **Learning journal** (`journal/`) - Chronological project evolution (immutable logs)
- **Architecture decisions** (`decisions/`) - ADRs documenting why choices were made

### Directory Overview

```
docs/
├── 00-foundation/           # Core concepts and design patterns
│   ├── guides/             # Podman, networking, middleware (living)
│   ├── journal/            # Early learning experiments (dated)
│   └── decisions/          # Fundamental architectural choices
├── 10-services/            # Service-specific documentation
│   ├── guides/             # Service operation guides (living)
│   ├── journal/            # Deployment logs (dated)
│   └── decisions/          # Service architecture choices
├── 20-operations/          # Operational procedures
│   ├── guides/             # Backup, recovery, maintenance (living)
│   ├── journal/            # Operational changes log (dated)
│   └── decisions/          # Operational policy decisions
├── 30-security/            # Security configuration
│   ├── guides/             # Security procedures (living)
│   ├── incidents/          # Post-mortems (dated)
│   └── decisions/          # Security architecture
├── 40-monitoring-and-documentation/
│   ├── guides/             # Monitoring stack guides (living)
│   └── journal/            # Project state evolution (dated)
├── 90-archive/             # Superseded documentation
└── 99-reports/             # System state snapshots (dated)
```

---

## 🎯 Finding What You Need

### Current System Information

**System State:** Latest in [99-reports/](99-reports/) (sorted by date, newest first)

**Running Services:** See monitoring guide
- Location: `40-monitoring-and-documentation/guides/monitoring-stack.md`
- Quick check: `podman ps`

**Service Guides:**
- Jellyfin: `10-services/guides/jellyfin.md` (to be created)
- Traefik: `10-services/guides/traefik.md` (to be created)
- Monitoring: `40-monitoring-and-documentation/guides/monitoring-stack.md`
- Backup: `20-operations/guides/backup-strategy.md`

### Understanding How We Got Here

**Learning Journey:** Browse `journal/` subdirectories chronologically

**Key Milestones:**
1. **Foundation** (`00-foundation/journal/`) - Podman, networking, pods
2. **Services** (`10-services/journal/`) - Traefik, Jellyfin, monitoring deployments
3. **Security** (`30-security/journal/`) - SSH hardening, YubiKey setup
4. **Backup** (`20-operations/journal/`) - BTRFS snapshot automation

### Architecture Decisions

**Why certain choices were made:** See `decisions/` subdirectories

**Key ADRs** (to be created):
- ADR-001: Rootless containers over privileged
- ADR-002: Traefik over Caddy/Nginx
- ADR-003: Systemd quadlets over docker-compose
- ADR-004: Monitoring stack architecture

---

## 📂 Category Guides

### 00-foundation: Core Concepts

**What's here:** Fundamental homelab concepts and design patterns

**Key guides:**
- Podman fundamentals (rootless, networking, volumes)
- Middleware ordering and security layers
- Configuration design principles
- Network architecture

**When to read:** Before deploying new services or making architectural changes

---

### 10-services: Service Documentation

**What's here:** Deployment and operation of individual services

**Services documented:**
- Traefik (reverse proxy)
- Jellyfin (media server)
- TinyAuth (authentication)
- Monitoring stack (Prometheus, Grafana, Loki)
- Alertmanager (alerting + Discord relay)

**When to read:** When deploying, troubleshooting, or modifying a service

---

### 20-operations: Day-to-Day Operations

**What's here:** Operational procedures and maintenance

**Key guides:**
- Backup and restore strategy
- BTRFS snapshot automation
- System diagnostics and health checks
- Maintenance schedules

**When to read:** During regular maintenance or incident response

---

### 30-security: Security Hardening

**What's here:** Security configuration, incidents, hardening procedures

**Key guides:**
- SSH infrastructure and YubiKey setup
- Secrets management policy
- Traefik middleware configuration
- Security audit procedures

**Incidents:** Post-mortems in `incidents/` subdirectory

**When to read:** Before exposing services to internet, during security reviews

---

### 40-monitoring-and-documentation: Observability

**What's here:** Monitoring stack and project documentation

**Key guides:**
- Monitoring stack operation (Prometheus, Grafana, Loki)
- Alert configuration and management
- Documentation contribution guide

**Project state:** Evolution tracked in `journal/` subdirectory

**When to read:** Setting up monitoring, creating alerts, or documenting work

---

### 90-archive: Historical Documentation

**What's here:** Superseded documentation preserved for historical context

**Structure:** Files retain original names with archival metadata header

**When to read:** Researching why old approaches were abandoned

**Note:** Check `ARCHIVE-INDEX.md` (to be created) for archival reasons

---

### 99-reports: System State Snapshots

**What's here:** Point-in-time system state documentation

**Naming:** `YYYY-MM-DD-<type>-<description>.md`

**Types:**
- `system-state` - Complete infrastructure snapshot
- `deployment-summary` - Service deployment reports
- `storage-architecture` - Storage configuration snapshots

**When to read:** Understanding system evolution or preparing for changes

**Latest reports:**
- `2025-11-07-backup-implementation-summary.md`
- `2025-11-07-btrfs-backup-automation-report.md`
- `2025-11-06-system-state.md`
- `DOCUMENTATION-REVIEW-2025-11-07.md`

---

## 🛠️ Common Tasks

### Deploying a New Service

1. Check architectural fit (networking, security, resources)
2. Create deployment journal entry: `10-services/journal/YYYY-MM-DD-<service>-deployment.md`
3. Deploy and test
4. Create/update service guide: `10-services/guides/<service>.md`
5. Update system state report: `99-reports/YYYY-MM-DD-system-state.md`
6. If architectural decision made, create ADR: `10-services/decisions/YYYY-MM-DD-decision-NNN-<title>.md`

### Updating Operational Procedure

1. Update the guide: `20-operations/guides/<procedure>.md`
2. Create journal entry explaining why: `20-operations/journal/YYYY-MM-DD-<change>.md`
3. If old procedure fundamentally different, archive it with metadata

### Responding to Security Incident

1. Resolve the incident first (document later)
2. Create incident post-mortem: `30-security/incidents/YYYY-MM-DD-incident-<description>.md`
3. Update affected guides: `30-security/guides/<relevant-guide>.md`
4. If policy change needed, create ADR: `30-security/decisions/YYYY-MM-DD-decision-NNN-<title>.md`

### Regular Maintenance

**Weekly:**
- Review `podman ps` for service health
- Check disk usage: `df -h / /mnt/btrfs-pool`
- Review monitoring dashboards

**Monthly:**
- Update service guides if configurations changed
- Review and update system state report
- Check for documentation needing archival

**Quarterly:**
- Full documentation audit (review all guides for accuracy)
- Update documentation index (this file)
- Clean up archive (ensure metadata is complete)

---

## 🔍 Search Tips

### Finding Files by Topic

```bash
# Search all documentation for a keyword
grep -r "traefik" docs/ --include="*.md"

# Find all guides
find docs/*/guides -name "*.md"

# Find journal entries from specific month
find docs/ -name "2025-11-*.md"

# Find all ADRs
find docs/*/decisions -name "*.md"
```

### Finding Latest Information

```bash
# Most recently updated files
find docs/ -name "*.md" -type f -mtime -7

# Latest system state report
ls -t docs/99-reports/*system-state*.md | head -1

# Most recent journal entries
find docs/*/journal -name "*.md" -type f | sort -r | head -10
```

---

## 📚 External Resources

### Project Documentation
- **CLAUDE.md** - AI assistant context and common commands
- **CONTRIBUTING.md** - Documentation contribution guide
- **README.md** - This file

### Scripts
- `scripts/homelab-diagnose.sh` - Comprehensive system diagnostics
- `scripts/btrfs-snapshot-backup.sh` - Automated backup system
- `scripts/security-audit.sh` - Security compliance check

### Configuration
- `config/traefik/` - Reverse proxy configuration
- `config/prometheus/` - Metrics and alerting rules
- `config/grafana/` - Dashboard provisioning

---

## 🎓 Learning Path

### New to Homelabs

1. **Foundation concepts** (`00-foundation/journal/`)
   - Start with early "day" numbered files
   - Read in chronological order to follow learning journey

2. **First service deployment** (`10-services/journal/`)
   - See how Jellyfin was deployed
   - Understand Traefik reverse proxy integration

3. **Security hardening** (`30-security/journal/`)
   - SSH infrastructure evolution
   - YubiKey hardware authentication setup

4. **Operational maturity** (`20-operations/journal/`)
   - Backup automation development
   - Monitoring stack deployment

### Experienced with Containers

Skip the learning journey and go straight to guides:
- `00-foundation/guides/` - Architecture patterns
- `10-services/guides/` - Service operation
- `20-operations/guides/` - Operational procedures
- `30-security/guides/` - Security configuration

### Contributing to Project

1. Read `CONTRIBUTING.md` first
2. Follow naming conventions
3. Place documentation in appropriate category and subdirectory
4. Create dated journal entries for changes, update living guides for corrections
5. Write ADRs for architectural decisions

---

## ❓ FAQ

**Q: Where do I find the latest system state?**
A: `docs/99-reports/` sorted by date (newest first)

**Q: How do I know if a service guide is current?**
A: All guides in `*/guides/` subdirectories are living documents kept current. Check "Last Updated" date at top.

**Q: Should I update an existing doc or create a new one?**
A: Update guides (living docs), create new journal entries (dated logs). See CONTRIBUTING.md for details.

**Q: Where do I document a new service deployment?**
A: Create journal entry in `10-services/journal/YYYY-MM-DD-<service>-deployment.md`, then create guide in `10-services/guides/<service>.md`

**Q: What if I find outdated documentation?**
A: If it's a guide, update it. If it's a journal/report, leave it (it's historical). If it's completely obsolete, move to archive with metadata.

**Q: Where do I find architecture decision rationale?**
A: Check `*/decisions/` subdirectories for ADRs explaining why choices were made.

---

## 🎯 Documentation Maturity

**Current Status:**
- ✅ Hybrid structure implemented
- ✅ Category directories with subdirectories created
- ✅ Contribution guide (CONTRIBUTING.md) written
- ✅ CLAUDE.md updated with new structure
- ⏳ Migration of existing files to new structure (in progress)
- ⏳ Creation of service guides (pending)
- ⏳ Creation of ADRs for key decisions (pending)
- ⏳ Archive cleanup and metadata addition (pending)

**Next Steps:**
1. Migrate existing documentation to appropriate subdirectories
2. Create service guides for all running services
3. Write ADRs documenting major architectural decisions
4. Clean up archive with proper metadata
5. Implement automated documentation linting

---

## 📞 Getting Help

**Documentation issues?** Check CONTRIBUTING.md or examine existing files for examples

**System issues?** See:
- Latest system state report in `99-reports/`
- Troubleshooting sections in service guides
- `scripts/homelab-diagnose.sh` for diagnostic information

**Security concerns?** See:
- `30-security/guides/` for current security posture
- `30-security/incidents/` for past incident learnings

---

**Remember:** Documentation is a love letter to your future self. Keep it current, clear, and kind. 💙

**Last maintained:** 2025-11-07 by Claude Code
**Review frequency:** Monthly
**Next review:** 2025-12-07
