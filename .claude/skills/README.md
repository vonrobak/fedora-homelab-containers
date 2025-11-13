# Claude Code Skills for Homelab

This directory contains Claude Code skills tailored for homelab infrastructure management.

## Organization Structure

```
.claude/skills/
├── homelab-intelligence/          # Custom: System health monitoring & diagnostics
│   └── SKILL.md
├── systematic-debugging/          # Adapted: Debugging methodology for infrastructure
│   ├── SKILL.md                  # Generic debugging framework
│   └── HOMELAB-TROUBLESHOOTING.md  # Homelab-specific integration
├── git-advanced-workflows/        # Adapted: Git workflows for infrastructure as code
│   ├── SKILL.md                  # Generic Git techniques
│   └── HOMELAB-INTEGRATION.md    # Homelab Git workflow integration
├── claude-code-analyzer/          # Generic: Claude Code usage optimization
│   ├── SKILL.md
│   ├── scripts/
│   └── references/
└── archived/                      # Less relevant skills
    └── prompt-engineering-patterns/
```

## Active Skills

### 1. homelab-intelligence
**Purpose:** Comprehensive system health monitoring and diagnostics

**When to use:**
- User asks "how is the system?"
- Before making significant infrastructure changes
- Periodically for proactive monitoring
- When diagnosing system-wide issues

**Key features:**
- Runs `homelab-intel.sh` for comprehensive health check
- Analyzes JSON output with health scoring
- Provides contextualized recommendations
- References homelab-specific documentation (ADRs, guides)

**Integration:**
- Calls `~/containers/scripts/homelab-intel.sh`
- Reads output from `docs/99-reports/intel-<timestamp>.json`
- References `CLAUDE.md` troubleshooting workflows
- Links to service-specific guides in `docs/10-services/guides/`

### 2. systematic-debugging
**Purpose:** Four-phase debugging methodology for infrastructure issues

**When to use:**
- ANY service failure or unexpected behavior
- Before proposing fixes (enforces root cause analysis first)
- Troubleshooting multi-component systems
- Performance issues

**Key features:**
- Phase 1: Root cause investigation (REQUIRED before fixes)
- Phase 2: Pattern analysis (compare with working examples)
- Phase 3: Hypothesis testing (one change at a time)
- Phase 4: Implementation (create test, fix, verify)

**Homelab integration:** See `HOMELAB-TROUBLESHOOTING.md`
- Service logs: `journalctl --user -u <service>.service`
- Container logs: `podman logs <container>`
- Network debugging: `podman network inspect`
- Traefik routing: Dashboard + logs
- Monitoring stack: Multi-service dependencies

### 3. git-advanced-workflows
**Purpose:** Advanced Git techniques for infrastructure as code

**When to use:**
- Cleaning up feature branches before PR
- Finding when configuration broke (git bisect)
- Working on multiple services simultaneously (worktrees)
- Applying hotfixes across environments (cherry-pick)
- Recovering from Git mistakes (reflog)

**Key features:**
- Interactive rebase for clean commit history
- Cherry-picking for selective changes
- Git bisect for finding breaking changes
- Worktrees for parallel work
- Reflog for recovery

**Homelab integration:** See `HOMELAB-INTEGRATION.md`
- Follows branch naming conventions (feature/, bugfix/, docs/, hotfix/)
- Preserves ADR commit history
- Integrates with quadlet deployment workflow
- References homelab Git standards from `CLAUDE.md`

### 4. claude-code-analyzer
**Purpose:** Optimize Claude Code usage and create configurations

**When to use:**
- Setting up new Claude Code project
- Optimizing auto-allowed tools
- Creating slash commands for common operations
- Building custom agents for complex workflows
- Discovering community skills/agents

**Key features:**
- Analyzes Claude Code history for usage patterns
- Suggests auto-allow tool configurations
- Discovers relevant GitHub community resources
- Helps create agents, skills, slash commands
- Provides CLAUDE.md templates

**Note:** Generic skill, not yet adapted for homelab specifics

## Using Skills

Skills are automatically loaded by Claude Code when their trigger conditions are met. You can also explicitly invoke them:

```
User: "How is my homelab doing?"
→ Triggers: homelab-intelligence skill
→ Runs: ./scripts/homelab-intel.sh
→ Analyzes: JSON output
→ Provides: Health summary with recommendations

User: "Jellyfin won't start"
→ Triggers: systematic-debugging skill
→ Follows: 4-phase troubleshooting process
→ Uses: homelab-specific diagnostic commands
→ References: CLAUDE.md troubleshooting workflows

User: "Clean up my feature branch"
→ Triggers: git-advanced-workflows skill
→ Uses: Interactive rebase workflow
→ Follows: Homelab branch naming conventions
→ Preserves: ADR commits as separate
```

## Skill Integration with Homelab

All active skills integrate with homelab infrastructure:

**Scripts:**
- `~/containers/scripts/homelab-intel.sh` - System intelligence
- `~/containers/scripts/homelab-diagnose.sh` - Comprehensive diagnostics
- `~/containers/scripts/homelab-snapshot.sh` - Point-in-time snapshot

**Documentation:**
- `CLAUDE.md` - Troubleshooting workflows, Git conventions, commands
- `docs/*/guides/` - Living documentation (updated in place)
- `docs/*/journal/` - Dated learning logs (immutable)
- `docs/*/decisions/` - ADRs (architecture decisions, never edited)

**Configuration:**
- `~/.config/containers/systemd/*.container` - Quadlet files
- `~/containers/config/` - Service configurations
- `.gitignore` patterns for secrets

## Archived Skills

**prompt-engineering-patterns**
- Generic LLM prompt optimization skill
- Low relevance for infrastructure operations
- Archived to `archived/` directory
- Can be restored if needed for documentation or automation scripts

## Skill Development Guidelines

When creating or adapting skills for this homelab:

1. **Reference existing tools:**
   - Use homelab scripts (`./scripts/`)
   - Link to documentation (`docs/`)
   - Follow configuration patterns (`config/`)

2. **Follow homelab conventions:**
   - Branch naming from `CLAUDE.md`
   - Documentation structure from `docs/CONTRIBUTING.md`
   - Service patterns from ADRs

3. **Integrate with workflows:**
   - systemd service management
   - Podman container operations
   - Traefik routing verification
   - Prometheus/Grafana monitoring

4. **Test with real scenarios:**
   - Use actual service failures
   - Verify troubleshooting steps work
   - Validate Git workflows with test repositories

## Quick Reference

| Task | Skill | Command/Trigger |
|------|-------|-----------------|
| Check system health | homelab-intelligence | "How is my homelab?" |
| Debug service failure | systematic-debugging | "Jellyfin won't start" |
| Clean Git history | git-advanced-workflows | "Clean up my feature branch" |
| Find breaking commit | git-advanced-workflows | "Find when config broke" |
| Optimize Claude Code | claude-code-analyzer | "Analyze my Claude Code usage" |

## Future Skill Ideas

Potential skills to develop for this homelab:

- **homelab-deployment** - Automated service deployment workflows
- **backup-orchestration** - Backup verification and restore procedures
- **security-audit** - Security configuration validation
- **performance-optimization** - Resource usage analysis and tuning
- **disaster-recovery** - Runbook generation and testing

---

**Last Updated:** 2025-11-13
**Organization:** Homelab infrastructure management
**Integration:** Fedora 42, Podman rootless, systemd quadlets
