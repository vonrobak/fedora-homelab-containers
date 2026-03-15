# Governance File Optimization

**Date:** 2026-03-15

## Why This Matters

CLAUDE.md and MEMORY.md are loaded into every Claude Code session. At 701 and 164 lines respectively, they consumed ~865 lines of context window before a single prompt was read. More importantly, the structure had drifted from its design intent: MEMORY.md was supposed to be a lightweight index pointing to individual files, but had become a monolithic dump of everything learned over 4 months. CLAUDE.md had accumulated operational runbooks and command references that Claude already knows or can find in linked docs.

The cost isn't just tokens — it's signal-to-noise. A session working on a Traefik route change doesn't need Authelia redis commands or BTRFS NOCOW instructions in its immediate context. But it absolutely needs the middleware chain and the ADR-016 routing convention. The goal was to keep what shapes decisions and remove what merely documents procedures.

## What Changed

**CLAUDE.md: 701 → 182 lines (74% reduction)**

Added a Philosophy section — the sovereignty framing that explains *why* this project exists. Every service replaces a cloud dependency; every decision should increase owner understanding. This was nowhere in the governance files, which meant fresh sessions had no way to know that "should we use Cloudflare Tunnel?" has a different default answer in this project than in most homelabs.

Removed all sections that were either trivially discoverable (systemd commands, podman commands), duplicated in linked docs (SLO framework, Loki queries, autonomous operations), or ephemeral (resource usage numbers that stale within weeks). Kept the Quick Reference table so nothing is lost — just one hop away instead of inline.

The critical addition during self-review: the standard middleware chains for new routes. The original plan would have shipped CLAUDE.md without specifying whether a new service gets Authelia or not, and without naming the exact middleware identifiers (`rate-limit@file` vs `rate-limit-public@file`). That's the kind of omission that produces a working-but-insecure deployment.

**MEMORY.md: 164 → 23 lines, backed by 14 individual files**

Converted from inline content to a proper index. Each memory file has frontmatter (type, name, description) so the system can decide relevance without loading the full content. The descriptions are specific enough to trigger correctly — "10 bugs in deploy-from-pattern.sh" will load when someone is about to use that script, not when they're doing unrelated work.

The 14 files split along natural boundaries: platform gotchas (22 items that prevent repeating mistakes), per-service state (Nextcloud, Immich, audio, qBittorrent), operational context (network hardening, known gaps, decommissioned services), and references (network inventory, doc structure). User profile and feedback are separate types with different loading heuristics.

**README.md and .github/claude.md:** Updated counts (30 containers, 13 SLOs, 19 ADRs, 53 checks), added sovereignty framing to README, added ADR-019 reference to GitHub review bot instructions.

## How to Think About This Going Forward

The governance files now have a clear hierarchy:

1. **CLAUDE.md** — always loaded, shapes every decision. Only put things here that apply to *most* sessions. If it wouldn't change behavior in >50% of conversations, it belongs in a memory file or linked doc.

2. **MEMORY.md index** — always loaded, but just pointers. Descriptions should be specific enough that a session can decide whether to load the file. Vague descriptions like "project notes" defeat the purpose.

3. **Memory files** — loaded on-demand. Good for service-specific state, learned gotchas, and context that's critical when relevant but noise otherwise. These should be updated when state changes, not appended indefinitely.

4. **Linked docs** (ADRs, guides, runbooks) — never auto-loaded. For deep reference when actively working in that domain.

The key maintenance question for any new piece of knowledge: *"Will a fresh session need this to avoid making a mistake, or will it discover this naturally by reading the code?"* If the former, it goes in CLAUDE.md or a memory file. If the latter, it doesn't need to be in governance files at all.
