---
type: ADR
title: "ADR-039: Egress Baseline Scoping for High-Rotation Cloud-API Endpoints (CrowdSec CAPI)"
description: "ADR amending ADR-030 P7 to generate CrowdSec's egress allowance from AWS-published eu-west-1 ranges, ending the re-baseline treadmill for its rotating cloud API."
sensitivity: public
created: 2026-06-14
updated: 2026-06-14
---

# ADR-039: Egress Baseline Scoping for High-Rotation Cloud-API Endpoints (CrowdSec CAPI)

**Date:** 2026-06-14
**Status:** Accepted (implemented 2026-06-14: `scripts/sync-aws-egress-ranges.sh`,
crowdsec block regenerated in `egress-baseline.yaml` to 67 published `eu-west-1` EC2
prefixes + static CloudFront/Cloudflare entries, monthly-loop drift check wired into
`monthly-update.sh`)
**Amends:** ADR-030 (Container Supply-Chain Trust Model) — refines P7 (Tier 4 egress
observatory) baseline-scoping policy for one class of destination. ADR-030's principles
and the egress-baseline.yaml frozen-prefix model are otherwise unchanged.

---

## Context

The Tier-4 egress observatory (ADR-030 P7) classifies every observed *public* egress
destination against a frozen-prefix allow-list (`config/supply-chain/egress-baseline.yaml`).
A raw socket connection carries **no SNI/hostname**, so classification is a pure CIDR
membership test — deliberately no DNS/ASN/whois on the hot path (sovereignty + no
boot-path dependency). The documented cost of that model is: *re-baseline by hand when a
provider rotates into a new range.*

For **crowdsec** that cost has stopped being occasional. In ~48h the crowdsec egress
allowance was re-baselined **three times** — #275 (`176.34.0.0/16`, `54.192.0.0/12`),
#296 (CloudFront `52.84.0.0/15`), #299 (`79.125.0.0/18` → `/17`) — each a benign AWS or
Cloudflare range its CAPI/hub rotated into, each TLS-verified as `api.crowdsec.net` /
`hub-data.crowdsec.net` before being added. The root cause is structural, not incidental:

- **`api.crowdsec.net` is fronted by AWS API Gateway in `eu-west-1`** (the flagged IP's
  default vhost is `*.execute-api.eu-west-1.amazonaws.com`). API Gateway answers from a
  large, **rotating** pool across AWS's published `eu-west-1` ranges. Per-IP — even
  per-/18 — allow-listing chases a moving target by construction.
- **The detection this preserves is already marginal.** crowdsec's allowance *already*
  carries ~25 AWS prefixes (Amazon Technologies Inc. `/9`–`/15` ×13, Amazon.com Inc. ×6,
  Amazon Data Services Ireland `/17`+`/16`). crowdsec→AWS visibility is therefore mostly
  surrendered already; the rotations that trip the alert fall in the *gaps between* huge
  allow-listed blocks. The marginal byte of detection bought by keeping those gaps is
  small.
- **The cost is alert fatigue, which erodes the observatory itself.** Each rotation fires
  `EgressUnexpectedDestination` (warning) and, if it holds past 1h,
  `EgressUnexpectedDestinationPersistent` (critical). Three benign critical-eligible
  alerts in two days trains the operator to read "crowdsec egress alert" as "another
  rotation, ignore" — which is exactly how a *real* crowdsec exfil alert would later be
  dismissed. Noise on the IP-reputation layer is not free.

This collides with a deliberate baseline-design decision (the `infrastructure: []`
choice): broad ranges are rejected because "everyone may reach any CDN" lets a compromised
service hide behind shared infrastructure. So the question is not "broad vs. narrow" in
the abstract — it is whether **crowdsec specifically**, given its CAPI-behind-API-Gateway
architecture, should keep paying per-rotation toil for detection it has already largely
surrendered.

## Decision

### D1 — Scope crowdsec's cloud-API egress to AWS-published `eu-west-1` ranges

Replace crowdsec's reactively-hand-widened AWS prefix set with the **AWS-published
`eu-west-1` ranges** that host CrowdSec CAPI (the `EC2`/`AMAZON` service prefixes in
`ip-ranges.json` for `region=eu-west-1`), retaining the existing Cloudflare hub ranges
(`hub-data`/`version.crowdsec.net`) as-is. Rationale: where the legitimate endpoint is a
provider-fronted, high-rotation API, the *provider's own published range list* is the
tightest honest description of "where this service legitimately talks" — tighter than
"all AWS," far more stable than chasing individual rotations.

### D2 — Generation is deliberate and offline; the classifier hot path is unchanged

A sync step — run during the monthly update loop (ADR-036 cadence), **reviewed before
commit** — fetches `ip-ranges.json`, filters to the `eu-west-1` `EC2`/`AMAZON` prefixes,
and regenerates crowdsec's AWS allowance block in `egress-baseline.yaml`. The classifier
remains a pure prefix-membership test: **no DNS/ASN/whois/HTTP on the hot path** (ADR-030
P7 design preserved). The mechanism is the *existing* per-service allow-list — only the
*source* of crowdsec's AWS prefixes changes from "observed IPs, hand-widened" to "AWS's
published list, deliberately synced."

### D3 — Crowdsec-only carve-out, gated by demonstrated churn

The published-range treatment applies **only** to a service that has demonstrated
**repeated benign rotation across a provider's published pool** (gate: **≥3 benign
re-baselines**). Today only crowdsec qualifies. Every other service keeps the tight
observed-prefix model, and `infrastructure: []` is **unchanged** — this is a per-service
widening, never a shared one. A second service reaching the gate gets its own ADR-style
note, not an automatic promotion.

### D4 — The signal is sharpened, not discarded

Because crowdsec's legitimate egress becomes fully characterised as
`{AWS eu-west-1 published} ∪ {Cloudflare hub}`, **any** crowdsec egress outside that set
— a non-AWS / non-eu-west-1 / non-Cloudflare destination — is now a *meaningful* anomaly
instead of being buried in benign-rotation noise. `EgressUnexpectedDestination{service=crowdsec}`
goes from "routinely benign" back to "actionable."

### D5 — Residual risk, accepted and documented

Exfil from a *compromised* crowdsec to an `eu-west-1` EC2 destination is no longer
detected by the observatory (it blends with CAPI). This mirrors the vaultwarden
peer-swarm residual-risk note and is accepted because: (a) the loss is marginal —
crowdsec→AWS was already ~surrendered by the pre-existing 25+ AWS prefixes; this *bounds
and formalises* that rather than expanding it; (b) crowdsec's image is digest-pinned with
a bake interval (ADR-030/036), so the compromise path is narrow; (c) crowdsec is an
IP-reputation layer, not a data store — a low-value exfil target; (d) D4 restores a real
off-profile signal that the noisy status quo had effectively disabled.

**Implementation status:** Implemented 2026-06-14. `scripts/sync-aws-egress-ranges.sh`
fetches `ip-ranges.json` (offline/deliberate), collapses the `eu-west-1` EC2 prefixes,
and splices them between `BEGIN/END generated` markers in `egress-baseline.yaml` (`--write`;
default is preview + diff + a coverage self-check that refuses to drop an observed IP).
The crowdsec block is now 67 published `eu-west-1` EC2 prefixes (superseding #299's hand
`/17` and the earlier `/9`–`/16` hand ranges) plus two static entries — CloudFront
(`52.84.0.0/15`, hub-cdn) and Cloudflare (`104.16.0.0/12`, `172.64.0.0/13`, version/hub-data)
— neither of which has hit the D3 gate. All 80 observed crowdsec destinations classify as
expected (`egress_unexpected_destination_count{service="crowdsec"} = 0`). A notify-only
drift check runs in `monthly-update.sh` Step 1.

## Consequences

**Positive**
- Ends the crowdsec re-baseline treadmill (3 PRs in 48h → 0 for AWS rotations).
- Restores actionable signal on the crowdsec egress alert (D4) — the observatory's value
  for this service goes *up*, not down.
- Keeps the classifier hot path pure (no runtime provider lookups); the provider-range
  dependency lives only in a deliberate, reviewed, offline sync (D2).

**Negative / accepted**
- crowdsec→`eu-west-1`-EC2 exfil is unobservable (D5). Bounded to one region of one
  provider for one digest-pinned, low-value-target service; compensated by D4's sharpened
  off-region signal.
- A new maintenance surface: the AWS-range sync must re-run when AWS publishes new
  `eu-west-1` EC2 prefixes. Deliberately rare and ride-along with the monthly loop;
  errors defer (a stale-but-narrower list just re-flags a benign rotation — the current
  behaviour), never rush.

**Neutral**
- The `≥3 benign re-baselines` gate (D3) is a first guess; tune as a second candidate
  service appears. The gate is the dial that keeps this from sliding into "allow-list
  whole clouds for everyone."

## Alternatives Considered

- **Status quo — reactive per-rotation widening.** Rejected: the toil is recurring and
  the alert fatigue actively erodes the observatory's signal, while the detection
  preserved is marginal (crowdsec→AWS already mostly allow-listed).
- **Suppress crowdsec egress alerts / move crowdsec to `peer_swarm` (count-only).**
  Rejected: throws away the sharpened off-region signal (D4). `peer_swarm` models
  *unbounded random peers* (qbittorrent, vaultwarden icons), not a bounded cloud-API
  front whose legitimate destinations are a known published set.
- **Allow-list all of AWS (all regions), or promote AWS to `infrastructure`.** Rejected:
  gives *every* service cover behind AWS and guts the per-service-scoping principle
  (`infrastructure: []`). `eu-west-1`-only, crowdsec-only is the tight bound.
- **Hostname/SNI-based classification (TLS peek / eBPF SNI capture).** Rejected: adds the
  exact hot-path dependency and complexity ADR-030 P7 deliberately avoided; out of
  proportion for a single-user homelab. It would *solve* the rotation problem generally,
  but at a cost the threat model doesn't justify here. Revisit only if many services hit
  the D3 gate.

## References

- **ADR-030** — Container Supply-Chain Trust Model (P7 egress observatory; the model this
  refines).
- **ADR-036** — Bake Policy & Exception Lane (the monthly deliberate-update cadence the D2
  sync rides on).
- `config/supply-chain/egress-baseline.yaml` — frozen-prefix model, the `infrastructure: []`
  no-broad-ranges decision, and crowdsec's current hand-widened AWS allowance.
- PR **#275** / **#296** / **#299** — the three benign crowdsec re-baselines that
  demonstrate the rotation churn.
- AWS `ip-ranges.json` (`region`/`service`-tagged published prefixes) — the D1/D2 source
  of truth; `79.125.0.0/17` is published as `eu-west-1` `EC2`.

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** The third benign crowdsec AWS-rotation re-baseline in 48h (#299, `79.125.93.93`),
which surfaced that per-IP allow-listing an API-Gateway-fronted CAPI endpoint is a
treadmill whose alert-fatigue cost outweighs the marginal detection it preserves.
