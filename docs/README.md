# Homelab Documentation

**System:** fedora-htpc production environment
**Status:** 🎯 Production | 🔐 SSO with YubiKey | 📊 Full Observability | 🤖 Autonomous Operations

---

## Quick Start

**New to this homelab?** Start with the [repository README](../README.md) — it has the recommended reading path. Then:

1. Review [CONTRIBUTING.md](CONTRIBUTING.md) for documentation conventions
2. Explore service guides in `*/guides/` subdirectories
3. Read the ADRs in `*/decisions/` for the *why* behind the architecture

**Live system views (auto-generated daily):**
[Service Catalog](AUTO-SERVICE-CATALOG.md) · [Network Topology](AUTO-NETWORK-TOPOLOGY.md) · [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) · [Documentation Index](AUTO-DOCUMENTATION-INDEX.md)

---

## Structure

```
docs/
├── 00-foundation/                      # Core concepts
│   ├── guides/                         # Podman, networking, design patterns
│   └── decisions/                      # Fundamental ADRs
│
├── 10-services/                        # Service documentation
│   ├── guides/                         # Immich, Jellyfin, Traefik, etc.
│   └── decisions/                      # Service architecture ADRs
│
├── 20-operations/                      # Operations procedures
│   ├── guides/                         # Storage, monitoring, maintenance
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
└── AUTO-*.md                           # Generated daily from the live system
```

Internal working notes (journals, plans, reports, archive) live in a private
knowledge vault outside this repository — see the boundary section of
[CONTRIBUTING.md](CONTRIBUTING.md). What you see here is the curated, public layer:
every document carries `sensitivity: public` frontmatter.

---

## Finding What You Need

**Frequently used guides:**
- **Architecture overview:** `20-operations/guides/homelab-architecture.md`
- **Immich / Jellyfin / Traefik / Authelia:** `10-services/guides/`
- **Monitoring stack:** `40-monitoring-and-documentation/guides/monitoring-stack.md`
- **Secrets model:** `30-security/guides/secrets-management.md`
- **Backups:** [Urd](https://github.com/vonrobak/urd) (ADR-021)

**Operational tooling** (run from the repo root):
```bash
./scripts/homelab-intel.sh              # Health score (0-100) + recommendations
./scripts/query-homelab.sh "status?"    # Natural language queries
./scripts/security-audit.sh             # 53-check security audit
```

Full script catalog: `20-operations/guides/automation-reference.md`

---

*Documentation conventions, frontmatter schema, and the public/private boundary are specified in [CONTRIBUTING.md](CONTRIBUTING.md).*
