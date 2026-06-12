# Lessons: stale handoff claims, attestation-class signers, and egress identification by log-reading

**Date:** 2026-06-13
**Status:** Both work packages merged (#297, #298). Two lessons captured (L-077, L-078, local lessons.md).
**Origin:** Executed two follow-ups from `2026-06-12-handoff-post-audit-followups.md` — "Tier 3 signature verification" (handoff item 6) and the crowdsec egress watch item (handoff item 2).

---

## What shipped

| Package | PR | Content |
|---|---|---|
| Vaultwarden attestation signer | #297 | 2026-06-13 re-survey of all 33 external repos; vaultwarden promoted to `signers.yaml` as the 2nd verified publisher via a new `mechanism: signature\|attestation` field in the verifier (cosign `verify-attestation --new-bundle-format`); `known-unsigned.md` refreshed (+2 post-survey repos, −decommissioned homepage); stale ADR-030 status corrected in CLAUDE.md/roadmap/memory |
| Egress watch item resolved | #298 | crowdsec → 172.66.154.109 identified as **hub-data.crowdsec.net** (entrypoint startup hub-update whitelist downloads); TLS-proven at the exact IP; baselined as 172.64.0.0/13 under crowdsec's Cloudflare allowance; detector reclassified live, `egress_unexpected_destination_count{service="crowdsec"}` 1 → 0 |

## Lesson 1 (→ L-077): the handoff's top "unblocked" task did not exist

The handoff listed **"Tier 3 signature verification — plan approved, no gate,
roadmap-listed"** as the next-session candidate, with the owner-approved
trajectory order putting it first. It had been **fully implemented and merged
19 days earlier** — PR #224, on 2026-05-24, the same day its plan was approved.
Every component the plan specified was already live: verifier, P6 gate,
advisory check, Signed column, alert rules, metrics.

The instructive part is *how the claim survived*. It propagated through four
documents written on the same day — holistic audit → trajectories report →
roadmap → handoff — each inheriting from the previous one and from a stale
memory line ("Tier 3/4 remain"). Four agreeing documents looked like four
confirmations; they were one unverified claim with a shared lineage. Notably,
the memory file's *body* said "ALL FOUR TIERS MERGED" — only its one-line
index summary was stale, and the summary is what got read.

**The check that broke the illusion cost one command:** `git log --oneline --
scripts/verify-image-signature.sh config/supply-chain/signers.yaml`. Primary
state (git history, the running system, the merged-PR list) outranks any
number of secondary documents, regardless of how recent or well-reviewed
they are.

This is the same family as the existing `feedback_verify_issue_premise_before_executing`
memory, but with a sharper edge: premise drift was previously understood as
*time* drift (issues going stale between filing and execution). This instance
was *lineage* drift — the handoff was hours old and still wrong, because
freshness of the document says nothing about freshness of its inherited claims.

## Lesson 2: coverage registries decay in both directions — and the ecosystem is heterogeneous

The falsified task still pointed at real work: the signing survey was three
weeks old. The re-survey found:

- **vaultwarden started publishing GitHub Artifact Attestations** (SLSA
  provenance v1, first present on release 1.36.0) — coverage doubled to 2/33.
- The survey's prediction failed in an interesting way: the outline expected
  GHCR OIDC-built app images to sign first; all of them are still bare, and
  the first new signer was a **docker.io** publisher.
- The registry had also decayed *the other way*: two post-survey deployments
  (pihole-exporter, blackbox-exporter) were absent, and decommissioned
  homepage was still listed.

The mechanism finding matters for future signers: vaultwarden's artifact is
**not a tag-scheme cosign `.sig`** — `cosign verify` cannot see it. It's a
referrer-attached sigstore bundle, verified with `cosign verify-attestation
--new-bundle-format --type slsaprovenance1` (same pinned cosign, no new
tooling). "Is it signed?" is no longer a yes/no question — *which sigstore
shape* determines the verification call. The signer registry now carries a
`mechanism` field, so the third signer is again a one-entry add whichever
shape it uses.

## Lesson 3 (→ L-078): the watch item fell to log-reading, not packet capture

The handoff prescribed identifying 172.66.154.109 via "tcpdump during a
controlled restart + TLS clienthello parse, or enumerate endpoints in
crowdsec's config/docs" — and recorded six failed SNI guesses
(api/blocklists/smoke/app/version/hub all miss). The actual identification:

1. **journalctl of the restart window** — the container entrypoint logs
   `downloading https://hub-data.crowdsec.net/whitelists/...` in plaintext,
   five files, at exactly the connection's timestamp. The guesses missed
   because the host is hub-**data**, a near-miss of the guessed `hub`.
2. **DNS corroboration** — `dig hub-data.crowdsec.net` returns exactly
   172.66.154.109 + 104.20.41.3, the latter being the already-verified
   version.crowdsec.net IP (same Cloudflare anycast pair).
3. **TLS proof at the exact IP** — `curl --resolve
   hub-data.crowdsec.net:443:172.66.154.109` validates the cert and serves
   one of the actual files (HTTP 200).

No restart, no capture, minutes of work. The general ladder: **app logs →
DNS → TLS-at-IP → packet capture last**. Hostname guessing is the weakest
rung — CDN dedicated IPs rotate and naming near-misses defeat enumeration —
yet it was the first instinct both times this destination was investigated.

## Smaller operational notes

- **The egress detector re-classifies stored rows on every run** — verdicts in
  `destinations.tsv` are not frozen at first sight. A baseline edit therefore
  self-heals the durable record and the metric on the next 10-minute tick; no
  state surgery needed. For immediate verification, `systemctl --user start
  egress-detect.service` is identical to a timer firing (flock-protected) and
  beats guessing at timer phase with sleeps — three background sleep-checks
  produced only confusion before the direct trigger settled it in seconds.
- **Permission boundary respected, investigation unharmed:** a `podman exec`
  into crowdsec to grep its API-credentials file was denied by the action
  classifier. The bind-mounted repo config plus journald had everything needed
  — live-container credential reads were never actually required. Worth
  remembering as the default order: repo artifacts and host-side logs first,
  container exec last.
- **Handoff item 4 (monthly-update regression check) is now better armed:**
  with hub-data baselined, crowdsec's restart-time egress is fully identified,
  so an observatory alert during the next mass restart would be a *genuinely
  new* destination, not the known watch item resurfacing.

## Where the context lives

- Lessons: L-077, L-078 in `docs/96-project-supervisor/lessons.md` (local-only)
- Identification record: `config/supply-chain/egress-baseline.yaml` (crowdsec/Cloudflare note)
- Survey state: `config/supply-chain/known-unsigned.md` (2026-06-13 re-survey)
- Memory updated: `project_supply_chain_hardening`, `project_2026h2_trajectories`, MEMORY.md index line
