# Tier 1 Plan: Digest Pinning + Update De-Automation

**Date Created:** 2026-05-23
**Status:** Implemented (uncommitted) — 2026-05-23
**Last Updated:** 2026-05-23
**Implements:** ADR-030 (P1, P2, P3, P4) — Container Supply-Chain Trust Model
**Reconciles with:** PLAN-1 (Auto-Update Safety Net), `audit-update-paths.sh`

## Objective

Eliminate the unattended, unverified, mutable-tag pull path for high-blast-radius
services, and establish content-addressed (digest) image references with a
deliberate, reviewable update workflow. This is the highest-ROI tier: it closes
the conveyor belt by which a poisoned upstream tag reaches execution.

## Background (verified 2026-05-23)

- **0 of 37** images are digest-pinned; **22 ride `:latest`**.
- **17 services** carry `AutoUpdate=registry`; **`unpoller`** additionally has
  `Pull=newer`. The auto-update set includes the egress/blast-radius tier:
  `traefik`, `crowdsec`, `jellyfin`, `qbittorrent`, plus `grafana`, `homepage`,
  `audiobookshelf`, `navidrome`, and the exporters.
- Unattended pulls run via `~/.config/systemd/user/podman-auto-update-weekly.service`
  (`ExecStart=/usr/bin/podman auto-update`, wrapped by
  `scripts/pre-update-health-check.sh` and `scripts/post-update-health-check.sh`)
  on `podman-auto-update-weekly.timer` (`Sun *-*-* 03:00:00`).
- `scripts/check-image-updates.sh` already runs `podman auto-update --dry-run`
  (notify-only) via `check-image-updates.timer` (`Sun *-*-* 10:00:00`).
- `scripts/update-before-reboot.sh` Phase 3 pulls **every** image by its current
  tag (`podman pull "$IMAGE"`), which would silently re-float any pin.
- Tooling present: **skopeo 1.22.2**, **podman 5.8.2**. No central manifest tooling
  needed (per ADR-030 architecture decision: in-quadlet pins + audit index).

## Approach

### 1. De-automate unattended pulls (P1, P4)

- Remove `AutoUpdate=registry` (and `unpoller`'s `Pull=newer`) from the
  **egress/blast-radius tier first** (`reverse_proxy` members), then the rest.
- **Repurpose, don't delete, PLAN-1's safety net.** Keep
  `pre/post-update-health-check.sh` and the rollback logic; convert
  `podman-auto-update-weekly.service` from an unattended trigger into an
  operator-invoked deliberate-update path that still runs digest changes through
  the health checks. Decide explicitly whether to disable the *timer* while
  keeping the *service* runnable on demand.
- Keep `check-image-updates.sh` as the notify-only "what's available" feed (P1's
  visibility half). Confirm its dry-run still reports usefully once images are
  digest-pinned (auto-update dry-run keys off `AutoUpdate=registry`; if removing
  that label blinds it, replace with a skopeo-based "newer digest available" check
  — see open question).

### 2. Digest-pin production images (P2)

- For each service, resolve the current tag to a digest:
  `skopeo inspect docker://<ref:tag> --format '{{.Digest}}'`.
- Write `Image=<repo>@sha256:<digest>` with the tag retained as an adjacent
  comment, e.g. `# tag: 16-alpine (resolved 2026-05-23)`.
- **Sequence by blast radius:** (a) internet-facing/egress tier
  (traefik, authelia, crowdsec, nextcloud, immich-server, vaultwarden, forgejo,
  qbittorrent, alert-discord-relay, proton-bridge); (b) databases
  (mariadb, postgres, mongo, redis/valkey, immich-postgres); (c) internal-only
  monitoring/exporters.
- `daemon-reload` + restart per service; verify health after each (do not batch
  the whole fleet blind).

### 3. Cooling-off cadence (P3)

- Define the bake interval as an **operator checklist**, not automation: e.g. only
  adopt a digest ≥N days old with no incident signal (advisories, upstream
  issues, ecosystem chatter) for that image. Internal-only tier may use a shorter
  interval (P4 — already contained).
- Document where the operator checks for incident signal before bumping.

### 4. Audit index (ADR-030 architecture)

- Add a generator script (AUTO-* style, alongside the existing
  `auto-doc-orchestrator.sh`) that parses every quadlet `Image=` line and emits a
  single reviewable doc: service → repo → pinned digest → tag comment → resolved
  date → mutability status (flag any still-floating reference). Centralises the
  audit *view* without touching the write path.

### 5. Guard extension (P4)

- Add an **egress-axis guard** (sibling to `audit-update-paths.sh`) that fails if
  any egress-tier service carries `AutoUpdate=registry`, or if any production
  service is unpinned (still on a mutable tag). Wire it into the same checks
  `audit-update-paths.sh` participates in.
- **Reconcile `update-before-reboot.sh` Phase 3:** make the pull step digest-aware
  so it no longer re-floats pinned images (a `podman pull` of a digest is a no-op
  if present; ensure it does not pull tags for pinned services).

## Critical files

- `quadlets/*.container` — `Image=` lines (digest + tag comment); remove
  `AutoUpdate=`/`Pull=` from the relevant set.
- `~/.config/systemd/user/podman-auto-update-weekly.{service,timer}` — repurpose/disable.
- `scripts/update-before-reboot.sh` — Phase 3 pull logic.
- `scripts/check-image-updates.sh` — keep/adapt notify-only feed.
- `scripts/audit-update-paths.sh` — model for the new egress guard.
- New: digest-resolve helper + audit-index generator (naming per repo convention).

## Open questions (resolve during execution)

- Does removing `AutoUpdate=registry` blind `podman auto-update --dry-run`? If so,
  the notify feed becomes a skopeo digest-diff check.
- Disable `podman-auto-update-weekly.timer` outright, or keep it as a manual
  `systemctl --user start` deliberate path?
- Per-service rollback verification: confirm `git revert` of a digest + restart is
  equivalent to BTRFS rollback for stateless services.

## Success Criteria

- 0 egress-tier services carry `AutoUpdate=registry` (or `Pull=newer`).
- All production images are digest-pinned with a tag comment; audit index shows 0
  unintended floating references.
- Audit-index generator runs cleanly and is wired into the doc pipeline.
- New egress guard is green and fails closed on a deliberately-introduced violation.
- `update-before-reboot.sh` no longer silently re-floats pinned images.
- A test digest bump flows through `pre/post-update-health-check.sh` and is
  `git revert`-able.

## Progress Log

- 2026-05-23 — Plan created from ADR-030; grounded in verified system facts.
- 2026-05-23 — **Egress trio executed** (first increment, not batched). Resolved the
  open question first: removing `AutoUpdate=registry` **does** drop a service from
  `podman auto-update --dry-run` (notify count 17→15), confirming the notify feed
  loses pinned services. Then, one service at a time with health gating:
  - `crowdsec` → `@sha256:2f527c9b…` (index digest), `AutoUpdate=registry` removed.
  - `authelia` → `@sha256:0c824dca…` (index digest); had no AutoUpdate label.
  - `traefik` → `@sha256:6b9cbca6…` (index digest), `AutoUpdate=registry` removed.
  For all three the **running image == current `:latest`** (tags had not drifted),
  so the pin freezes the already-baked image (P3 satisfied inherently); refs were
  present locally so restarts pulled nothing. All verified `healthy`; full chain
  serves (`traefik.patriark.org` → 302 → `sso.patriark.org` 200); jellyfin native
  302; `audit-update-paths.sh` still green. **Timer untouched** (still updates the
  other 15 labeled services). **Not yet committed.**
  - **Next:** skopeo digest-diff notify replacement for pinned services; then
    de-automate the rest of the fleet (don't batch); audit-index generator; egress
    guard; `update-before-reboot.sh` Phase-3 digest-awareness; timer decision.
- 2026-05-23 — **Tier 1 COMPLETE (remaining items, uncommitted).** All bullets above done:
  - **Fleet de-automated + pinned.** 15 auto-updating services pinned to their running
    `.ImageDigest` (drift-proof "pin what's baked") + `AutoUpdate`/`Pull` removed,
    **restarted one at a time** with health gating (internal exporters, then egress
    apps; all healthy). 16 stateful/floating services **arm-pinned** (pinned to running
    digest, `daemon-reload`, no restart per operator decision — pin matches what's
    running, takes effect on next natural restart). Result: **34/34 registry images
    digest-pinned, 0 floating**; 2 localhost builds (alert-discord-relay, proton-bridge)
    deferred to Tier 2.
  - **New tooling:** `scripts/pin-container-image.sh` (digest-resolve+apply helper,
    uses `podman inspect .ImageDigest`), `scripts/generate-image-pin-index.sh`
    (→ `docs/AUTO-IMAGE-PIN-INDEX.md`, wired into `auto-doc-orchestrator.sh` Phase 5),
    `scripts/audit-egress-updates.sh` (P4 egress guard — sibling to `audit-update-paths.sh`).
  - **Notify feed replaced:** `scripts/check-image-updates.sh` rewritten as a skopeo
    digest-diff (pinned digest vs current tag digest); resolves the open question
    (de-automation blinds `podman auto-update --dry-run`). First run: up-to-date=20,
    available=12, local=2, failed=2 (transient GHCR burst-throttle on immich; retry-once
    + inter-call delay added). Notify timer (Sun 10:00) retained.
  - **`update-before-reboot.sh` Phase 3** now digest-aware: pull list derived from
    quadlet `Image=` lines; pinned refs *ensured present* (no re-float), only mutable
    tags pulled. (Fixed a `tr -d '[:space:]']` newline-collapse bug during build.)
  - **Timer decision:** `podman-auto-update-weekly.timer` **disabled + stopped** (the
    unattended 03:00 path is gone); `.service` + pre/post health-check scripts kept for
    the deliberate-bump path.
  - **Verification:** both guards green (egress + statefulness); full middleware chain
    serves post-restart (traefik 302 → sso 200; jellyfin/homepage/grafana/immich/nextcloud
    OK); 36/36 containers running, 0 unhealthy; no new failed units.
  - **Open question (resolved):** removing `AutoUpdate=registry` does blind the old
    `podman auto-update --dry-run` feed — superseded by the skopeo digest-diff feed.
  - **Residual / next:** Tier 2 (localhost build-input pinning), Tier 3 (policy.json
    still `insecureAcceptAnything` — signatures), Tier 4 (egress detection). Commit
    pending (enables the `git revert` rollback path). immich notify-check needs the
    retry validated under load.
