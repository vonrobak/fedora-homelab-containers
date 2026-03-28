# Prompt for Urd Claude Code session

## Context

Urd runs in production on a homelab managed at `~/containers/` (separate Git repo). That project just created ADR-021 documenting the integration contract between the homelab and Urd:

`~/containers/docs/00-foundation/decisions/2026-03-28-ADR-021-urd-backup-tool.md`

Read that ADR. It lists the specific metrics, file paths, systemd units, and alert rules the homelab depends on.

## Task

Add appropriate documentation to the Urd project (CLAUDE.md, CONTRIBUTING.md, or wherever you judge best) that captures two things:

1. **Cross-repo awareness.** Urd's external interface (metric names, heartbeat schema, CLI flags used by systemd units, `.prom` file format) is consumed by the homelab's monitoring stack. Changes to that interface need a corresponding update to the homelab's ADR-021 at the path above.

2. **Public release intent.** Urd is currently tailored to one homelab, but its goal is public release as a general-purpose BTRFS backup tool for any Linux user. The metrics output, notification dispatch, and observability features must remain monitoring-agnostic. Urd writes well-formed Prometheus textfile exposition format to a user-configured path — it does not assume any specific monitoring stack, alert system, or notification service consumes it. Keep homelab-specific concerns (which Grafana dashboard, which Discord webhook, which alert rules) out of Urd's code and defaults.

Keep the addition concise. Evaluate which project doc is the right home for this — don't necessarily put everything in CLAUDE.md if a different location is more appropriate.
