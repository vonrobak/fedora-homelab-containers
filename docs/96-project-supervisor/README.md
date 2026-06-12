# 96-project-supervisor — Situational Awareness

This directory houses distilled, project-level orientation documents. Together they give a
human operator or an LLM session fast, reliable situational awareness without re-reading the
raw record (journals, reports, git history).

## Document family

| Document | Question it answers | Status |
|----------|--------------------|--------|
| [lessons.md](lessons.md) | What have we learned the hard way? | Live |
| roadmap.md | Where are we going? | Planned |
| status.md | Where are we now? | Planned |
| registry.md | What has been done before? | Planned |

## Relationship to the rest of the documentation

- **`98-journals/`** is the raw chronological record — narratives, debugging sessions, session notes.
- **`99-reports/`** holds incident reports, postmortems, audits, and automated snapshots.
- **ADRs** (`docs/*/decisions/`) record individual architectural decisions and their rationale.
- **This directory** holds the *synthesis*: durable conclusions distilled from those sources,
  kept current as the system evolves.

Documents here are curated, not generated. Each defines its own update protocol in its header
(see "How to add a lesson" in lessons.md). When a statement here conflicts with a journal entry,
this directory wins — it is maintained; journals are immutable history.
