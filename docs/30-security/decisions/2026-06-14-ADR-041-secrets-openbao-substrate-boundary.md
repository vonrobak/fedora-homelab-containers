---
type: ADR
title: "ADR-041: Runtime Secrets via OpenBao Substrate — Workload-Side Boundary"
description: "ADR sourcing runtime secrets from a self-hosted OpenBao substrate service, keeping every Secret= handle byte-for-byte unchanged with the secret name as the sole cross-repo interface."
sensitivity: public
created: 2026-06-14
updated: 2026-06-14
---

# ADR-041: Runtime Secrets via OpenBao Substrate — Workload-Side Boundary

**Date:** 2026-06-14
**Status:** Accepted. **Supersedes ADR-040** (its substrate *mechanism* and Phase
sequencing; ADR-040's *findings* are retained by reference). Documents the **workload side**
of **htpc-mgmt ADR-007** ("Runtime secrets via a self-hosted OpenBao substrate service",
2026-06-14), which is canonical for the mechanism.

---

## Context

ADR-040 explored a bridge in which each podman secret was individually TPM-sealed and a root
boot-oneshot repopulated a tmpfs store. The substrate side instead adopted **OpenBao** (FOSS
Vault fork) as a system-scope service and the Phase-1 source of truth (htpc-mgmt ADR-007;
Infisical was rejected — it paywalls dynamic secrets and phones home). OpenBao's encrypted
storage barrier **subsumes** the per-blob TPM seal, so ADR-040's D2 mechanism was **not
built**, and "OpenBao = deferred Phase 2" (D6) is now Phase 1.

This ADR records only what **this** repo (the GitHub-primary workload repo) owns, so the two
repos state the same boundary with zero contradiction. ADR-040's still-valid findings carry
by reference: the Podman `file` driver is not encrypted at rest (base64); Vaultwarden cannot
be a live broker; the LLM read-wall requires privilege separation.

## Decision

### D1 — Source of truth is OpenBao, a substrate system service (not in this fleet)

OpenBao runs system-scope under a dedicated non-`patriark` `openbao` user, localhost-only
(127.0.0.1:8200, TLS), TPM-auto-unsealed at boot (no PIN). It is **not a container, not a
quadlet, not in the service fleet** — it is host substrate, owned entirely by htpc-mgmt
(ADR-001/002 over there). This repo's containers **never** talk to it.

### D2 — Consumption is byte-for-byte unchanged

A root sync oneshot reads OpenBao and recreates podman secrets in a **tmpfs** cache at the
existing store path (ADR-028). Therefore **every `Secret=` consumption handle in this repo's
quadlets — whether `type=env` or `type=mount`/file — stays byte-for-byte unchanged.** (~30
secret names; several are file mounts: Authelia's three, the forgejo signing key + `.pub`,
`gathio_mongodb_password`, `ha-prometheus-token`.) Zero workload churn. The
base64-on-unencrypted-pool at-rest leak is closed by OpenBao's storage
barrier; the podman-secret cache is cleartext but **tmpfs-only** (`zram` swap, never disk).

### D3 — The interface between the repos is the secret NAME

- **htpc-mgmt owns** (substrate, Forgejo-private): the OpenBao install/config, unseal/TPM
  machinery, policies + AppRoles, the sync oneshot, the tmpfs mount, the `secretctl` wrapper,
  the generated no-values ledger/manifest, the consistency check, and DR/escrow.
- **This repo owns:** only the unchanged `Secret=` consumption handles and the three secrets
  docs (this ADR, the superseded ADR-040, the `secrets-management.md` pointer).
- A **three-way consistency check** (OpenBao names ↔ `grep Secret= quadlets/` ↔ htpc-mgmt
  manifest) enforces agreement by name. No secret topology, values, or mechanism live here
  beyond the consumption contract.

### D4 — Creation/rotation go through htpc-mgmt, not `podman secret` here

`secretctl` (htpc-mgmt) is the sanctioned create/rotate/list path. This repo does **not**
document `podman secret rm/create` as the way to change a secret — that would diverge from
OpenBao (the source of truth) and be overwritten at the next sync/reboot. Because consumption
is **read-once at container start**, live per-lease dynamic credentials are **not generally
consumable** — rotation means a service restart, and dynamic creds are a **per-service
opt-in**, not the baseline. What is realized fleet-wide is OpenBao-as-source-of-truth + audit
+ scheduled/static-role rotation.

### D5 — Honest scope (stated, not oversold)

There is **no LLM read-wall**: an agent running as `patriark` can still read secret *values*
out of the containers that consume them. **Privilege separation is the only real wall and is
deferred** — though the system-service shape *seeds* it (the agent already cannot reach
OpenBao itself, only the consuming containers). DR carries a deliberate circular dependency —
OpenBao's recovery keys are escrowed in Vaultwarden while Vaultwarden's admin token is an
OpenBao-managed secret — broken by the offline Vaultwarden master password; the procedure
lives in htpc-mgmt ADR-007.

## Consequences

**Positive**
- Zero workload churn: every `Secret=` handle unchanged; secret topology stays off the
  GitHub-primary repo (the name is the only interface).
- The concrete at-rest leak (base64 on the unencrypted pool, recoverable from a disposed disk) is
  closed by OpenBao's barrier + tmpfs cache.
- Audit and scheduled rotation are gained; the boundary is tight (no mechanism overlap).

**Negative / accepted**
- No runtime read-wall in the interim (D5); revisited only by adopting privilege separation.
- Cross-repo coupling — a secret is named in two repos — mitigated by the D3 consistency check.

**Neutral**
- Dynamic per-lease credentials remain a future per-service opt-in, not a fleet baseline (D4).

## References

- **htpc-mgmt ADR-007** — *canonical* for the OpenBao mechanism, policies, unseal, sync,
  `secretctl`, ledger, and DR (substrate repo, Forgejo-private).
- **ADR-040** (superseded) — retained findings: file driver not encrypted; Vaultwarden not a
  live broker; the read-wall needs privilege separation.
- **ADR-028** — the podman secret-store path the tmpfs cache lands on; **ADR-030** — digest
  pinning narrows the compromise path that makes D5's residual risk acceptable.
- `docs/30-security/guides/secrets-management.md` — rewritten as the thin workload-side pointer.

---

**Decision made by:** User (patriark) + Claude Code (cross-repo close-out, 2026-06-14).
**Trigger:** Finalization of the substrate-side OpenBao design (htpc-mgmt ADR-007) required
this repo's three secrets documents to supersede ADR-040's mechanism and state the identical
boundary, with the workload side documenting only consumption-by-name.
