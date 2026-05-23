# Tier 2 Plan: First-Party Build Inputs + Repository Hardening

**Date Created:** 2026-05-23
**Status:** Proposed
**Last Updated:** 2026-05-23
**Implements:** ADR-030 (P5, P8) — Container Supply-Chain Trust Model

## Objective

Bring the homelab's *build-time* and *repository* supply chains up to the same
trust standard as runtime images: pin and hash-lock the inputs of locally-built
images, and protect the repository that defines the infrastructure.

## Background (verified 2026-05-23)

- **`alert-discord-relay` is a live build-time exposure.**
  `config/alert-discord-relay/Dockerfile`:
  - `FROM python:3.11-slim` — floating base tag.
  - `RUN pip install --no-cache-dir -r requirements.txt`, where
    `requirements.txt` pins only top-level versions (`Flask==3.0.0`,
    `requests==2.31.0`, `gunicorn==21.2.0`) — **no hashes**, and **transitive
    deps unpinned** (`urllib3`, `certifi`, `charset-normalizer`, `idna`, …
    resolve to latest-compatible at build time).
  - The container is **egress-capable** (on `reverse_proxy` first → default
    route; posts to a Discord webhook), so a poisoned build can exfiltrate.
- **`proton-bridge` has an unverified RPM input.**
  `builds/proton-bridge/Containerfile`:
  - `FROM registry.fedoraproject.org/fedora:43` — floating base (Fedora-signed
    chain mitigates).
  - `COPY protonmail-bridge-3.23.1-1.x86_64.rpm` then `dnf install -y` it — the
    RPM is manually downloaded from proton.me, **gitignored (not committed)**,
    with **no recorded checksum/signature-verification step**. Repo packages
    (`nmap-ncat`, `pass`, `socat`) are Fedora-signed and fine.
  - **Doc drift:** `builds/proton-bridge/README.md` says *"Status: Incomplete …
    not suitable for automated quadlet deployment"*, but the unit is `active` and
    `generated`. The README is stale.
- **Tooling/CI:** `pip-tools` is **not installed**. The repo has a `.github/`
  directory but **no `workflows/`** — no GitHub Actions, so no CI secrets to
  steal. Server-side squash-merge signing is in use (no local GPG key).

## Approach

### 1. `alert-discord-relay` — pin base + hash-lock deps (P5)

- Pin the base by digest: `FROM python:3.11-slim@sha256:<digest>` (resolve with
  `skopeo inspect`), tag retained as a comment.
- Generate a fully-resolved, **hash-locked** requirements file including
  transitive deps. Two viable paths (decide during execution):
  - **`pip-tools`** (`pip-compile --generate-hashes`) — requires installing
    `pip-tools`.
  - **`uv`** (`uv pip compile --generate-hashes`) — if preferred / present.
- Switch the build to `pip install --require-hashes -r requirements.lock` so a
  hash mismatch fails the build closed.
- Rebuild, verify the relay still posts to Discord, re-pin the resulting
  `localhost/alert-discord-relay` reference in its quadlet per Tier 1.

### 2. `proton-bridge` — pin base + verify the RPM (P5)

- Pin `fedora:43` by digest (tag as comment).
- Record the **expected SHA-256** of the Proton RPM (from proton.me / a trusted
  channel) in the build context, and add a verification step that fails the build
  if the local RPM's hash does not match before `dnf install`.
- Fix the stale `README.md` to reflect the actual `active` deployment state and
  document the RPM provenance + expected hash.

### 3. Repository hardening (P8)

- Enable **branch protection on `main`**: no direct pushes, require PR. Mirror on
  the self-hosted **Forgejo** repo if it is a push target.
- **Token hygiene:** short-lived, narrowly-scoped tokens; no long-lived write
  PATs/deploy keys. Inventory existing tokens and revoke over-scoped ones.
- Keep server-side squash-merge signing (no change).
- (No Actions workflows exist; this is branch/token *policy*, not CI hardening —
  if workflows are added later, they inherit ADR-030's posture.)

## Critical files

- `config/alert-discord-relay/Dockerfile`, `config/alert-discord-relay/requirements.txt`
  (+ new `requirements.lock`).
- `builds/proton-bridge/Containerfile`, `builds/proton-bridge/README.md`
  (+ recorded RPM hash).
- Quadlets for both `localhost/*` images (re-pin per Tier 1 after rebuild).
- Repository settings (GitHub `main`, Forgejo) — out-of-tree, document the change.

## Open questions (resolve during execution)

- `pip-tools` vs `uv` for hash generation — which to standardise on.
- Where to record the Proton RPM expected hash so it is reviewable but the 81 MB
  binary stays gitignored.
- Whether the GitHub remote is canonical or a mirror of Forgejo (determines where
  branch protection is primary).

## Success Criteria

- Both Containerfiles pin their base image by digest.
- `alert-discord-relay` builds with `--require-hashes` against a transitive-complete
  lock; a tampered hash fails the build.
- `proton-bridge` build verifies the RPM against a recorded hash before install;
  README reflects reality.
- Branch protection enabled on `main`; token inventory complete with over-scoped
  tokens revoked.

## Progress Log

- 2026-05-23 — Plan created from ADR-030; grounded in verified build-file audit.
