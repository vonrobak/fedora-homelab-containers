# Tier 3 + Tier 4 Outline: Signature Enforcement & Egress Detection

**Date Created:** 2026-05-23
**Status:** Proposed (outline — not yet detailed for execution)
**Last Updated:** 2026-05-23
**Implements:** ADR-030 (P6, P7) — Container Supply-Chain Trust Model

> These two tiers are intentionally outline-level. Tier 3 needs new tooling and a
> publisher-by-publisher signing survey; Tier 4 is research-level with no committed
> mechanism. They are documented now so the ADR has a forward path, and detailed
> into full plans when Tier 1–2 are complete.

---

## Tier 3 — Signature / Provenance Enforcement (P6) *(authenticity axis)*

**Why:** Digest pinning (Tier 1) guarantees *integrity* ("same bytes") but not
*authenticity* ("right publisher"). Tier 3 is the only verifiable defense against a
tag/registry account being used to publish a malicious image — short of source
compromise (which is Tier 4's residual).

**Verified starting state:**
- `policy.json` (`/etc/containers/policy.json`) = `insecureAcceptAnything`; no
  `~/.config/containers/policy.json`; no `~/.config/containers/registries.d/`.
- **`cosign` is not installed** (prerequisite).
- Podman 5.8.2 supports sigstore `sigstoreSigned` policy.

**Outline approach:**
1. **Signing survey** (its own task): for each registry/publisher in use
   (docker.io library, ghcr.io/* incl. immich/homepage/gathio/unpoller/audiobookshelf,
   quay.io/*, gcr.io, codeberg.org/forgejo, linuxserver, deluan), determine who
   publishes sigstore signatures / OIDC provenance and who does not. GHCR
   OIDC-built images are the most likely first candidates.
2. Install `cosign`; build `registries.d` + a user `policy.json`.
3. **Graduated enforcement:** `sigstoreSigned` for the signing subset (start with
   provenance-bearing GHCR), explicit `insecureAcceptAnything` per-repo for
   non-signers, tracked in a known-unsigned list (not silently trusted).
4. Verify pulls/restarts still succeed under the new policy before making it the
   default; ensure a signature failure fails closed and is observable.

**Risks / why outline-only:** partial coverage by design; brittle if a publisher
changes signing practices; misconfiguration can block legitimate images. Requires
the survey before any enforcement is safe.

**Success criteria (draft):** `policy.json` off blanket `insecureAcceptAnything`;
signing subset enforced via sigstore; documented known-unsigned exceptions; no
legitimate image blocked.

---

## Tier 4 — Egress Detection (P7) *(containment / detection axis)*

**Why:** The irreducible residual. A **validly-signed but malicious** image from a
legitimately-compromised maintainer defeats both pinning (Tier 1) and signatures
(Tier 3). The only remaining controls are containment (already strong) and
detecting/limiting what a compromised container does on the wire.

**Verified starting state:**
- Internal-only networks (`auth_services`, `monitoring`, `nextcloud`, `photos`,
  `gathio`, `mail`, `media_services`, `syslog`, `home_automation`, `forgejo`) are
  `Internal=true` — already no egress.
- The `reverse_proxy` network has egress; all 10 internet-facing services reach
  the Internet through it.
- Inbound is monitored (CrowdSec, Loki/Promtail); **outbound/behavioral container
  egress is not.**

**Outline options to evaluate (no commitment yet):**
- Per-container egress allow-listing (default-deny outbound, allow only known
  destinations) for the `reverse_proxy` tier.
- DNS egress logging (which domains containers resolve) as a low-cost detection
  signal feeding Loki/alerts.
- Flow/connection monitoring for anomalous outbound from the egress tier.

**Risks / why outline-only:** legitimate egress destinations must be enumerated
(false-positive risk); rootless networking constrains some host-level options;
this is detection/limiting, not prevention. Needs a design spike before a plan.

**Success criteria (draft):** a chosen mechanism gives visibility into (or
allow-lists) outbound from the `reverse_proxy` tier, with anomalies surfaced in the
existing monitoring stack.

---

## Progress Log

- 2026-05-23 — Outline created from ADR-030; Tier 3/4 deferred pending Tier 1–2 and
  the signing survey / egress design spike.
