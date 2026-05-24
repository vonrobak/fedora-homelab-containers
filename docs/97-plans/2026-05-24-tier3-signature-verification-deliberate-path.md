# Tier 3 Plan: Authenticity Verification on the Deliberate-Update Path

**Date Created:** 2026-05-24
**Status:** Approved (executable) — detailed from the 2026-05-23 outline after the signing survey
**Implements:** ADR-030 (P6 authenticity; P1 deliberate-not-ambient; P3 cooling-off)
**Supersedes:** the Tier 3 section of `2026-05-23-tier3-4-signatures-and-egress-detection-outline.md`
(the pull-time `policy.json` approach — see "Why the approach changed")

> Tier 4 (egress detection) remains outline-only in the original document.

---

## TL;DR

The signing survey (2026-05-24) found that **podman's `policy.json` can enforce
nothing on this fleet**, so Tier 3 enforces authenticity with **cosign on the
deliberate-update path** instead — at the one moment a human deliberately adopts a
new digest. This is *more* aligned with ADR-030's P1/P3 spine than pull-time
enforcement would have been, and it keeps the boot/restart path untouched.

---

## What the survey found (verified 2026-05-24)

Surveyed all 32 external image references with a digest-pinned containerized
cosign v3.0.6 (`cosign tree`), a skopeo tag-scheme probe, and `gh attestation
verify` for the GHCR app images.

| Finding | Result |
|---|---|
| Images with a registry-attached sigstore signature | **1 / 32** — `ghcr.io/home-assistant/home-assistant` only |
| Images with GitHub build-provenance attestations | **0** of the 6 GHCR app images (immich-server/-ml/postgres, homepage, gathio, unpoller, audiobookshelf) |
| All other publishers (docker.io, quay.io, gcr.io, codeberg.org) | nothing |

HA's signature is genuine and verifiable: keyless GitHub-Actions cosign signature,
Rekor-logged, OIDC issuer `https://token.actions.githubusercontent.com`, certificate
SAN `https://github.com/home-assistant/core/.github/workflows/builder.yml@refs/tags/<release>`.

**The decisive limitation.** `man 5 containers-policy.json` (podman 5.8.2, installed)
specifies that `sigstoreSigned.fulcio` requires **both `oidcIssuer` and `subjectEmail`**,
and `pki` offers only `subjectEmail`/`subjectHostname`. There is **no URI-SAN /
workflow-identity match field**. GitHub-Actions keyless certs carry a *URI SAN*, not an
email — so podman 5.8.2 **cannot express HA's identity**. The one image that is signed
is the one image `policy.json` cannot verify. Pull-time enforceable coverage = **0**.

## Why the approach changed (outline → this plan)

The outline assumed the standard play: install cosign, write `policy.json`, enforce
`sigstoreSigned` per publisher at pull time. The survey invalidates that:

1. **Coverage via stock `policy.json` is zero** (the limitation above).
2. **Pull-time is the wrong checkpoint for this ADR.** ADR-030's spine is P1
   (trust accepted deliberately, never ambiently) and P3 (cooling-off). Pull-time
   `policy.json` enforces trust *ambiently* on every pull — including boot and the
   reboot wrapper's Phase 3 — which is the boot-critical fragility ADR-030's
   "where digests live" section deliberately avoided.
3. **cosign already verifies what `policy.json` can't.** It validated HA cleanly
   against the URI-SAN identity. Only the pull-time enforcement *surface* is broken,
   not the verification capability.

So Tier 3 verifies authenticity **at the moment of deliberate adoption** (where a
human is already in the loop, after a bake), using cosign — and leaves `policy.json`
permissive and documented.

## Design

### Components

1. **Signers registry** — `config/supply-chain/signers.yaml`
   One entry today (HA): repo, `certificate-identity-regexp`, `certificate-oidc-issuer`.
   Schema documented so an email-identity (or future URI-SAN) signer is a one-line add.

2. **Known-unsigned manifest** — `config/supply-chain/known-unsigned.md`
   The 30 unsigned images + the "GHCR has no provenance" finding. This is P6's
   "tracked, not silently trusted" artifact. Regenerable; surfaced in the pin index.

3. **Verifier** — `scripts/verify-image-signature.sh <repo>@<digest>`
   Runs the pinned containerized cosign against the signer entry for the repo.
   **Exit codes (the load-bearing contract):**
   - `0` — verified against a known identity
   - `3` — no signer entry for this repo (unsigned-but-tracked; **not** a failure)
   - `1` — a signer entry exists but verification **FAILED** (fail-closed)
   - `2` — tooling/network error (cosign image missing, Rekor/registry unreachable) —
     a transient signal, **not** fail-closed; the operator retries
   Writes a Prometheus textfile metric (see Observability).

4. **Enforcing gate** — in `scripts/pin-container-image.sh`
   Before the `--apply` write, call the verifier on `${repo}@${D}`:
   - exit `1` (FAILED) → **abort the pin** (a signature that should verify but doesn't
     is a red alarm: possible key compromise or tampered artifact)
   - exit `0` → proceed; record `# ADR-030 P6: signature verified <identity> (<date>)`
     as an adjacent quadlet comment beside the existing P1/P2 comments
   - exit `3` → proceed; optionally record `# ADR-030 P6: no publisher signature (tracked unsigned)`
   - exit `2` → abort with a *retry* message (distinct from FAILED)
   - `--skip-verify` — loud, logged escape hatch for the legitimate "HA changed its
     workflow path and I reviewed the new SAN" case, so the gate can't deadlock.

   *Rationale for this integration point:* pins move **only** through
   `pin-container-image.sh` — the P1 deliberate-acceptance action. The gate fires once,
   at a human's adoption, after a bake. It never touches boot/restart/reboot.
   **Do not** gate `update-before-reboot.sh` (Phase 3 only *ensures pins present*; it
   never moves one — gating it would reintroduce boot-path fragility).

5. **Advisory check** — in `scripts/check-image-updates.sh`
   The Sun-10:00 notify feed already resolves each image's available `current` digest.
   For images with a signer entry, verify that available digest and annotate:
   `✓ signature verified` / `✗ SIGNATURE FAILED — do not adopt`. Visibility only
   (the script's "never changes anything" contract); front-loads the trust signal
   *before* the bake interval. No `set -e` disruption.

6. **Audit view** — `scripts/generate-image-pin-index.sh`
   Add a **"Signed"** column: `✓ <identity>` / `— tracked-unsigned` / `✗ FAILED`,
   making the 1/32 coverage (and its growth) explicit in the single reviewable doc.

7. **cosign itself** — pinned `ghcr.io/sigstore/cosign/cosign:v3.0.6@sha256:de9c65…`,
   run as a throwaway container. It is a supply-chain input; it appears in the pin index
   like any other image.

### Observability / fail-closed shape

Reuse the existing rails: node_exporter textfile collector
(`~/containers/data/backup-metrics/*.prom`, scraped by Prometheus) →
Alertmanager → `alert-discord-relay`.

- **Synchronous (primary):** the gate aborts with a loud stderr message naming the
  expected identity and digest. A human is already at the keyboard.
- **Durable:** `verify-image-signature.sh` writes
  `~/containers/data/backup-metrics/supply-chain-signatures.prom`:
  ```
  supply_chain_signature_verify{service="home-assistant",repo="…",result="ok|failed"} 1|0
  supply_chain_signature_last_verify_timestamp{service="home-assistant"} <epoch>
  ```
  Alertmanager rule: `supply_chain_signature_verify{result="failed"} == 1` → **critical**
  Discord; optional `time() - …_last_verify_timestamp > 90d` → **warning** (stale pin / P3 drift).
- **Passive:** the pin-index "Signed" column.

**Three-way discrimination is the key detail:** verification-FAILED (critical,
fail-closed, abort) ≠ no-signer-on-file (the 30, never alarms) ≠ cosign-unreachable
(warn + retry, never hard-block on a network blip).

### What stays out of scope (recorded as deferred)

- **`policy.json` / `registries.d` enforcement** — blocked on podman gaining
  URI-SAN / workflow-identity matching. `policy.json` stays `insecureAcceptAnything`,
  with a justifying comment so it is not later misread as an oversight.
- **Pull-time enforcement of any kind.**
- **Signing our own local builds** (alert-discord-relay, proton-bridge) — a
  Tier-2-adjacent future, not Tier 3's upstream-authenticity remit. Noted, not built.

## Upstream dependency to revisit

When podman/containers-image `sigstoreSigned` gains URI-SAN / workflow-identity
matching, pull-time `policy.json` enforcement for HA-class keyless signers becomes
expressible, and the cosign deliberate-path gate can be **promoted** to (or
complemented by) pull-time policy. Exact constraint to recheck:
`man 5 containers-policy.json` `sigstoreSigned.fulcio` mandates `oidcIssuer`+`subjectEmail`;
`pki` offers only `subjectEmail`/`subjectHostname`; neither matches a URI SAN.

## Execution order

1. `config/supply-chain/signers.yaml` + `config/supply-chain/known-unsigned.md`
2. `scripts/verify-image-signature.sh` — write, then **test end-to-end against HA**
   (must verify) and a negative case (must fail-closed) before wiring anything.
3. Gate into `pin-container-image.sh` (fail-closed, `--skip-verify`).
4. Advisory into `check-image-updates.sh`.
5. "Signed" column in `generate-image-pin-index.sh`; regenerate `AUTO-IMAGE-PIN-INDEX.md`.
6. Alertmanager rule + route (existing Discord relay).
7. Docs: mark the outline's Tier 3 superseded; update `project_supply_chain_hardening`
   memory with the survey result + the podman URI-SAN upstream-dependency note.

## Success criteria

- `verify-image-signature.sh` verifies HA's current digest (exit 0) and fails closed
  (exit 1) on a tampered/wrong identity — both demonstrated.
- `pin-container-image.sh` aborts a pin on verification FAILURE and proceeds (with the
  right comment) on verified / no-signer; `--skip-verify` works and is loud.
- The pin index shows the "Signed" column with HA `✓` and the rest `tracked-unsigned`.
- A verification failure surfaces in Discord via the existing relay; transient cosign
  errors warn rather than block.
- `policy.json` remains permissive **by documented decision**, with the upstream
  dependency recorded.
- No new code on the boot/restart/reboot path.

## Risks

- **HA changes its builder workflow path** → identity-regexp stops matching → gate
  fails-closed on a legitimate update. *Mitigation:* identity stored as a regexp
  (`builder.yml@refs/tags/.*`); loud `--skip-verify` after manual SAN review; a
  blocking failure at adoption is the *correct* response to a changed signing identity.
- **Sole signer looks like over-engineering.** *Mitigation:* framed as the extensible
  P6 pilot — the second signer is a one-line config add; the pin-index column makes the
  1/32 reality and its growth path explicit.
- **Permissive `policy.json` misread as a gap later.** *Mitigation:* justifying comment
  + the upstream-dependency note; the audit index shows authenticity *is* enforced, on
  the deliberate-adoption axis.

## Progress Log

- 2026-05-24 — Plan created from the outline after the signing survey; approach changed
  from pull-time `policy.json` to a deliberate-path cosign gate due to the podman 5.8.2
  URI-SAN limitation. Direction approved (Option A).
</content>
</invoke>
