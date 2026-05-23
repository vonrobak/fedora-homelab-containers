# ADR-030: Container Supply-Chain Trust Model

**Date:** 2026-05-23
**Status:** Accepted
**Supersedes:** ADR-015 (the update *trust model* — see "Relationship to ADR-015". ADR-015's BTRFS rollback and health-validation mechanisms remain valid and are reused here.)

---

## Context

Supply-chain attacks against software repositories and registries have escalated
from occasional incidents to industrialised campaigns. The May 2026 "Megalodon"
campaign injected malicious commits into ~5,561 GitHub repositories in a six-hour
window using stolen tokens (push-to-master, no PR, forged `ci-bot`/`build-bot`
identities); the payload fires inside the *downstream consumer's* build/CI and
steals credentials. The transmission path to a homelab is indirect but real:
*poisoned commit upstream → upstream's own CI builds and publishes a poisoned
image under the **same moving tag** → we pull it on the next `podman pull`.* The
mutable tag is the conveyor belt.

This ADR exists because the homelab's current posture — established by ADR-015
when the dominant risk was understood to be *running outdated software* — is
optimised against the wrong threat for this class of attack. The exposure is
**measured, not assumed** (verified 2026-05-23):

- **0 of 37** image references are pinned by digest; **22 ride `:latest`**, the
  rest ride floating major/minor tags (`:16`, `:7-alpine`, `:11`, `:33`, `:15`,
  `:stable`). Only Immich (`v2.7.5`) and proton-bridge (`3.23.1`) carry specific
  version tags — and even those are registry-mutable, not content-addressed.
- **17 services carry `AutoUpdate=registry`** and pull unattended every Sunday at
  03:00 via `podman-auto-update-weekly.service`. That set includes **`traefik`,
  `crowdsec`, `jellyfin`, and `qbittorrent`** — i.e. the reverse proxy and the
  IP-reputation engine, our highest-blast-radius, internet-facing components.
- `policy.json` is `insecureAcceptAnything`: **no signature or provenance
  verification** is enforced at pull time.
- All ten internet-facing services reach the Internet via the `reverse_proxy`
  network. A poisoned image among them has an open egress path.
- Two locally-built images extend the supply chain to *build* inputs:
  `alert-discord-relay` builds `FROM python:3.11-slim` (floating) with
  transitive-unpinned, unhashed `pip` dependencies and is egress-capable;
  `proton-bridge` installs a manually-downloaded RPM with no recorded
  checksum/signature check (its Fedora base and repo packages are GPG-signed, so
  that part is lower risk).

Two important framings emerged from the analysis:

1. **The existing update guard tracks the wrong axis for this threat.**
   `audit-update-paths.sh` correctly keeps *stateful schema* services off the
   auto-update path — but that guard exists for **availability** (the 2026-04-06
   Nextcloud SLO collapse), keyed on *statefulness*. Supply-chain risk is keyed on
   **blast radius / egress capability**, an orthogonal axis. That is precisely why
   `traefik` and `crowdsec` — "stateless," so permitted by the availability guard —
   sit on the unattended pull path despite being the worst things to silently
   replace.

2. **Cryptographic primitives are available but unused.** Podman 5.8.2 and skopeo
   1.22.2 are installed; both digest pinning and sigstore `policy.json` are
   supported today. `cosign` and `pip-tools` are **not** installed (prerequisites
   for signature verification and hash-locked Python builds, respectively). The
   repository has **no GitHub Actions workflows**, so Megalodon's *direct* CI-token
   vector is low; our residual repo risk is branch-protection and token hygiene.

The question this ADR answers is therefore not "pin or don't pin" but: **what is
our trust model for accepting a container image — and its build inputs — into
execution?**

## Decision

Adopt a **supply-chain trust model** governed by the principles below. This is a
design contract, not a procedure; concrete sequencing lives in the Tier
implementation plans under `docs/97-plans/` and is executed against these
principles.

The unifying idea: a supply-chain attack is **transitive trust failure**. Every
durable defense reduces to one of six axes — *minimise* trust surface, verify
*integrity*, verify *authenticity/provenance*, control the *time* trust is
accepted, *contain* blast radius, and *detect* post-compromise. The principles map
to those axes.

### P1 — Trust is accepted deliberately, never ambiently *(minimise / time)*

No service adopts a new image version without an explicit, reviewable, revertible
action by the operator. Unattended `podman auto-update` of mutable tags is retired
as the default acceptance mechanism. A *notify-only* feed of what is available is
retained (the goal is no **unattended** trust acceptance, not going dark on
patching).

### P2 — Integrity by content address *(integrity)*

Production image references resolve to immutable digests (`Image=…@sha256:…`). The
human-readable tag is preserved as an adjacent comment for legibility. **Tags are
for discovery; the digest is the execution contract.** A digest is the container
equivalent of a lockfile hash: the registry cannot serve different bytes under the
same digest, so a re-pointed tag or a poisoned upstream rebuild cannot silently
change what runs.

### P3 — A cooling-off interval precedes adoption *(time)*

A new digest is adopted only after a bake interval during which no incident signal
appears for that image. This trades CVE-patch *latency* (acceptable here: single
user, no uptime SLA, instant BTRFS rollback) for the ecosystem's *detection*
latency — most poisoned releases are caught within hours to days. Time is the
cheapest control against a freshly-poisoned-but-validly-published artifact.

### P4 — Blast radius defines update rigor, orthogonally to statefulness *(contain / minimise)*

Update rigor is determined by what a compromised image could *do*, not only by
whether it owns a schema. This ADR introduces an **egress/blast-radius axis**
alongside the existing statefulness axis:

- **Egress-capable / internet-facing tier** (the `reverse_proxy` members) gets the
  strictest controls: digest-pinned, never on `AutoUpdate=registry`, longest bake.
- **Internal-only tier** (`Internal=true` networks, no egress) may relax the bake
  interval because exfiltration is already contained — though pinning still applies.

The statefulness guard (`audit-update-paths.sh`) and this egress guard are
complementary, not redundant.

### P5 — First-party builds pin their inputs *(integrity / minimise)*

Locally-built images are accountable for their build inputs to the same standard
as runtime images: base images pinned by digest, and language/package
dependencies locked by hash (including transitive dependencies, which are the
actual gap). A build that resolves dependencies freshly at build time is a live
instance of the very threat this ADR addresses.

### P6 — Authenticity is verified where publishers support it; graduated, not all-or-nothing *(authenticity)*

Integrity (P2) guarantees "the same bytes every time," not "the right bytes from
the right publisher." Authenticity requires signatures/provenance. We move
`policy.json` off `insecureAcceptAnything` toward sigstore enforcement **per
publisher**, starting with provenance-bearing sources (e.g. GHCR images built via
OIDC), while explicitly tolerating unsigned images from publishers who do not sign
yet — tracked, not silently trusted. Blanket enforcement that breaks legitimate
unsigned images is rejected as brittle.

### P7 — Containment is a first-class supply-chain control *(contain / detect)*

The existing rootless + SELinux + segmented-network posture is treated as a
supply-chain control, because it bounds what a poisoned image can *do*. Egress is
the residual exfiltration path and therefore the locus for future detection
investment. This is the only line of defense against a **validly-signed but
malicious** artifact from a legitimately-compromised maintainer — which no pin or
signature can catch.

### P8 — The project's own repository is part of the supply chain *(minimise / authenticity)*

The repository that defines this infrastructure is itself an upstream of it.
Branch protection (no direct push to `main`, PR required), short-lived scoped
tokens (no long-lived write PATs), and signed merges are required controls — the
direct lesson of Megalodon's push-to-master vector.

### Architecture: where digests live

Digests are written **in the quadlet** (where Podman reads them), with the tag as
an adjacent comment, and a generated **audit index** aggregates every pin into a
single reviewable document. This satisfies ADR-016's *intent* (one auditable view)
without its literal centralisation: a central manifest feeding a quadlet generator
would insert a fragile templating step into the boot-critical path, since Podman
quadlets have no native external-variable substitution. We centralise the audit
**view**, not the **write path**.

### Non-goals

This ADR does **not**: mandate same-day patching; require signatures from
publishers who do not sign; replace BTRFS rollback or the health-validated update
wrapper (PLAN-1) — both are retained and reused on the deliberate update path;
require digest-pinning of the Fedora host (`dnf` already verifies GPG-signed RPMs;
the host is not the weak link).

## Consequences

### Positive

- The unattended "pull whatever the tag points to" path — the conveyor belt for a
  poisoned upstream — is removed for the highest-risk services.
- Updates become git diffs of digests: a reviewable, timestamped audit log and an
  instant `git revert` rollback path complementing BTRFS snapshots.
- The trust model is made explicit and axis-aligned, so future services inherit a
  defined posture rather than an accidental one.
- Build inputs gain the same accountability as runtime images, closing the one
  live build-time exposure.

### Negative

- Manual digest bumps add friction to updating. (This friction *is* the control —
  it is the human checkpoint and the time delay — but it is real ongoing effort.)
- CVE patches land later than under continuous auto-update. Mitigated by the
  notify-only feed (visibility), the single-user/no-SLA context, and rollback.
- Signature enforcement (P6) has partial coverage by design and adds policy
  surface that must be maintained as publishers' signing practices change.

### Risks

- **False confidence in pinning.** A digest pinned from an already-poisoned image
  faithfully pins poison. P2 is necessary but not sufficient; it must travel with
  P3 (bake) and, where possible, P6 (authenticity). This is called out so pinning
  is never mistaken for completeness.
- **Stale pins as a security debt.** Deliberate updates can become *no* updates.
  The notify-only feed and a periodic review cadence exist to counter drift.
- **The irreducible residual.** A validly-signed malicious artifact from a
  compromised maintainer defeats P2 and P6. Only P3, P7, and detection bound it;
  this risk is accepted and explicitly assigned to the containment/detection axis
  rather than pretended away.

## Alternatives Considered

- **Keep ADR-015's auto-update model, rely on the PLAN-1 health wrapper.**
  Rejected as the *security* control: PLAN-1 protects *availability* (rollback on a
  broken image), not *integrity* (it would faithfully health-check a working but
  malicious image). Its machinery is retained and repurposed, not relied on for
  this threat.
- **Stop all updates / pin and never move.** Rejected: trades supply-chain risk
  for an accumulating CVE-staleness risk. The goal is *deliberate* acceptance, not
  *no* acceptance — hence the notify-only feed and bake cadence.
- **Central digest manifest + quadlet generator.** Rejected: a literal reading of
  ADR-016 that adds a fragile generation step on the boot-critical path. Chose
  in-quadlet pins + generated audit index instead.
- **Digest pinning alone as sufficient.** Rejected: integrity ≠ authenticity (see
  Risks). Pinning is the foundation, not the whole.
- **Blanket signature enforcement.** Rejected: would block legitimate unsigned
  images and create brittle breakage; P6 is graduated per publisher.

## Relationship to ADR-015

ADR-015's core thesis — *"the security risk of running outdated software outweighs
the stability risk of automatic updates,"* therefore prefer `:latest` +
auto-update — is **superseded** for the trust model. It was written against
breakage/staleness risk and predates the supply-chain reframing; under this threat
class, *unattended acceptance of mutable tags* is itself the dominant risk for
high-blast-radius services. ADR-015's still-valid contributions — BTRFS snapshot
rollback, the pre/post-update health-validation workflow, and the recognition that
single-user/no-SLA context permits aggressive rollback — are preserved and reused
here. ADR-015's status is updated to point forward to this ADR; its body is left
intact per the repository's ADR-immutability convention.

## Related

- **ADR-015** — Container Update Strategy (superseded trust model; mechanisms reused)
- **ADR-016** — Configuration Design Principles (single source of truth → audit index)
- **ADR-001** — Rootless Containers (rootless + SELinux underpin P7 containment)
- **ADR-021 / ADR-029** — BTRFS backup (Urd) and DB storage/rollback (underpin P3/P7)
- **PLAN-1** — Auto-Update Safety Net (health-validation wrapper, reused on the deliberate path)
- Implementation plans: `docs/97-plans/2026-05-23-tier1-…`, `…-tier2-…`, `…-tier3-4-…`

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** Escalation of registry/repository supply-chain campaigns (Megalodon, May 2026) against a homelab with unattended, unverified, mutable-tag update paths.
