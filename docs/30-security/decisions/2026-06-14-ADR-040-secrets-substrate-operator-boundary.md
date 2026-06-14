# ADR-040: Secrets Substrate & Operator Boundary

**Date:** 2026-06-14
**Status:** **Superseded by [ADR-041](./2026-06-14-ADR-041-secrets-openbao-substrate-boundary.md)**
(2026-06-14, same day). What changed is the **substrate mechanism**: the substrate side
(htpc-mgmt ADR-007) chose **OpenBao as a system-scope service** as the Phase-1 source of
truth, so the per-podman-secret TPM-seal + boot-oneshot specified in **D2** was **not built**
(OpenBao's encrypted storage barrier subsumes it), and "OpenBao = deferred Phase 2" (**D6**)
is now Phase 1. The cross-repo boundary (D3), the operator-boundary stance (D1: no read-wall
without privilege separation, deferred), the cycling-by-class schema (D4), and DR (D5) carry
forward into ADR-041. ADR-040 is **retained for its still-valid findings**: the Podman `file`
driver is not encrypted at rest; Vaultwarden cannot be a live broker; the LLM read-wall
requires privilege separation. Body unchanged below.

---

## Context

`secrets-management.md` (2025-12-26) is stale, and an audit on 2026-06-14 found two of its
central claims false:

- **"Podman secrets are encrypted at rest" is wrong.** The default `file` driver stores the
  30 live secrets **base64-encoded** in `secretsdata.json` — plaintext-equivalent. Worse,
  that file sits on the **unencrypted** btrfs pool. A pool disk that later fails or is
  disposed of cannot always be securely wiped (a failing drive can't be rewritten; an RMA
  hands it over un-erased), so any secret ever written to it is a disposal leak. This is the
  most concrete present vulnerability, and it is unrelated to any LLM threat.
- **Vaultwarden cannot be a live secrets broker.** Bitwarden Secrets Manager / `bws` is a
  proprietary-licensed feature Vaultwarden has declined to implement. Vaultwarden stays a
  cold human-vault and DR escrow only.

The triggering goal was broader: a secrets system **more secure and more user-friendly**
than the base64 store, that ideally lets an LLM operator (Claude Code) **inject secrets it
cannot read**. Following that requirement to its end produced the load-bearing finding:

> **As long as the agent runs as `patriark`, it can read every runtime secret.** It owns
> the rootless containers, so it can always `podman exec <svc> env` or
> `podman secret inspect --showsecret`. No secret store, no TPM scheme, and no broker
> changes this — even OpenBao's deny-read token is bypassed by reading the value out of the
> container that legitimately pulled it. **A real "the LLM cannot read secrets" property
> requires privilege separation** (running the agent as a non-`patriark` user that cannot
> exec the containers). There is no substitute.

Two hardware/OS facts from the same diagnostics shaped the substrate:

- **TPM2 is present and usable, but `systemd-creds` TPM keys are system-scope only.**
  `systemd-creds --user --with-key=tpm2` returns *"Selected key not available in --uid=
  scoped mode, refusing"*; `patriark` is not in `tss` and cannot reach `/dev/tpmrm0`. So the
  clean "rootless quadlet does `LoadCredential=` from the TPM" path **does not exist** here.
  TPM sealing/unsealing must happen at root scope and be handed to the rootless world.
- **The host's boot chain is not measured** (no measured-boot / UKI). PCR-binding sealed blobs would buy
  ~zero tamper-resistance while forcing a re-seal on every firmware/kernel change. So:
  no-PIN, **no PCR binding**.

Finally, the **endgame is already known**: a planned storage role-reversal will move the
pool onto already-encrypted (LUKS) drives.
A LUKS pool encrypts *everything* at rest, which **subsumes** per-secret at-rest crypto. So
the substrate decided here is explicitly a **bridge**, not a destination.

## Decision

### D1 — Operator boundary: privilege separation is the only read-wall, and it is *deferred*

The "LLM cannot read" property is recorded as achievable **only** via privilege separation,
and is **deferred** as a discrete future project. In the interim the agent stays `patriark`
and **can** read runtime secrets — this is accepted, because the realistic threat is
*accidental* leakage (a value into a transcript / log / commit) and the need for an audit
trail, not a malicious local Claude. The interim design therefore targets
**accidental-leak prevention + at-rest encryption + audit + rotation**, and does **not**
claim a runtime read-wall. The honest scope is stated so a future reader does not mistake a
broker (D6) for the wall it cannot provide.

### D2 — At-rest substrate: TPM-seal + tmpfs store + root boot-oneshot (rootless preserved)

Each secret is sealed at **root scope** (`systemd-creds --with-key=tpm2 encrypt`) into a
`.cred` blob (useless without *this* TPM). The rootless podman secret store is moved onto
**tmpfs** so cleartext never persists on disk (swap is `zram0` — RAM-backed — so tmpfs
cannot bleed to disk either). A **root boot-oneshot** unseals the blobs and repopulates the
store at boot. Unattended (no-PIN), **no PCR binding** (justified above). **All 30 `Secret=`
quadlet lines stay unchanged** — services keep consuming via `type=env`/`type=mount`. Net:
a pulled/disposed pool disk decrypts to nothing; at runtime values remain `patriark`-readable
(D1). This is the **bridge** to the LUKS-pool endgame, after which the TPM-seal layer becomes
optional belt-and-suspenders (the tmpfs "no cleartext persists" property and the
seal-path-behind-root boundary remain valuable regardless).

### D3 — Repo boundary: material in htpc-mgmt, handles in containers

The **mechanism, the sealed blobs, the secrets ledger, and the DR/escrow runbook live in
htpc-mgmt** (the substrate repo — Forgejo-private; this is *host provisioning*, the same
class as LUKS/storage/kernel-hardening, and the most sensitive operational material has no
business on the GitHub-primary containers repo). The **handles stay in containers**: the
quadlets' `Secret=…,type=env,target=…` lines and Authelia `file://` references are
*consumption contracts* — they name a secret and how it is read, holding no value. **The
interface between the two repos is the secret name.** This ADR records the decision and the
boundary; htpc-mgmt builds the mechanism as an **Ansible role** (its "declarative over
imperative" principle) and writes its **own ADR reconciling with htpc-mgmt ADR-006**
(which previously scoped workload secrets *out* of the substrate — this refines that line:
the substrate now owns *provisioning the workload secret store*, never the routing). A
consistency check diffs ledger handles against `grep Secret= ~/containers/quadlets/`; the
ledger is the source of truth.

### D4 — Cycling schema: class-based cadence; the migration *is* a rotation event

Rotation is driven by blast-radius and rotation-safety, not a blanket interval, tracked in a
**no-values ledger** (`name, owning-service(s), class, issue-date, last-rotated,
rotation-method, blast-radius`):

| Class | Members (examples) | At migration | Ongoing |
|---|---|---|---|
| Single-service tokens | grafana, crowdsec_api_key, pihole, unpoller, exporters | seal + rotate | 90 d, scripted |
| External-issued | cloudflare_dns_token, navidrome lastfm, discord webhook | seal + rotate (re-mint at provider) | per provider / on exposure |
| Session/JWT (rotate ⇒ re-login) | authelia_jwt_secret, authelia_session_secret, immich-jwt-secret | seal + rotate | on exposure |
| DB-coupled | nextcloud/forgejo/gathio/immich DB creds | seal + rotate **in a maintenance window, ADR-029 dump first** | on-event only (annual ceiling) |
| **Crypto keys w/ data-at-rest meaning** | **authelia_storage_key** (encrypts DB), **forgejo_signing_key** (commit-verification history) | **seal IN PLACE — do NOT rotate** | only with a migration plan |
| Roots of trust | TPM recovery, Vaultwarden master, (later) OpenBao unseal | escrow offline | on device/personnel change |

Because the at-rest migration recreates every secret, it **doubles as a rotation event**:
seal-and-rotate the rotatable classes so cleartext recoverable from a disposed/failed pool disk goes
stale; **seal-in-place** the data-meaning keys. Phase 1 scope = high-value subset first
(Authelia keys, DB creds, forgejo signing key, Cloudflare token).

### D5 — DR: Vaultwarden + offline paper, with the circular dependencies broken

Plaintext and the TPM-recovery path are escrowed in **Vaultwarden**; the irreducible roots
(Vaultwarden master password, TPM recovery key) are **printed offline**. Two circular
dependencies are explicitly broken: (a) Vaultwarden's own admin token must be recoverable
*without* the secret store it backs (master password is human-memorized + offline-printed);
(b) TPM-sealed blobs are host-bound, so OS reinstall / board failure recovers by **re-sealing
from escrow**, never from git. The htpc-mgmt reinstall-runbook gains a "re-seal podman
secrets from Vaultwarden escrow" step in its DR order.

### D6 — Phase 2: OpenBao, deferred and deliberate

OpenBao (sovereign Vault fork) is the deferred Phase 2. It does **not** deliver the read-wall
(D1), but it buys what the bridge cannot: a tamper-evident **audit log** of every secret
access, **deny-read on the agent token** (kills *accidental* reads by construction), and
**dynamic/leased DB credentials** + a rotation engine that operationalizes D4. It reuses the
same TPM-auto-unseal-at-boot pattern (D2) for its own unseal — it layers on the bridge, it
does not replace it. Triggered when the audit/dynamic-secrets value is wanted, or as the
substrate matures.

## Consequences

**Positive**
- Closes the concrete disposal/theft leak (D2): a pulled pool disk — including a failing,
  un-wipeable one — decrypts to nothing.
- Zero churn on the workload side: all 30 `Secret=` lines and Authelia `file://` refs
  unchanged (D3); the containers repo learns *less* about secret topology, not more.
- Honest posture: the read-wall's true cost (privilege separation) is recorded, not papered
  over by a broker (D1/D6); rotation is finally safe-by-class (D4).
- Sovereignty: the most sensitive operational material lives only on owned infrastructure
  (Forgejo-private htpc-mgmt), never on the GitHub mirror.

**Negative / accepted**
- No runtime read-wall in the interim — the agent as `patriark` can read secrets (D1).
  Accepted; revisited only by adopting privilege separation.
- New cross-repo coupling: a secret is defined in two repos (handle in containers, blob +
  ledger in htpc-mgmt). Mitigated by the D3 consistency check; drift is possible if it lapses.
- New host machinery (root boot-oneshot, tmpfs store, cross-scope ordering) — fiddly to get
  right, and a boot-time dependency for every secret-consuming service.

**Neutral**
- The TPM-seal layer is a bridge; when the LUKS-pool role-reversal lands it becomes optional.
  Not wasted (tmpfs + seal-behind-root persist their value), but its at-rest role sunsets.

## Alternatives Considered

- **Keep the base64 store / friction-only on it.** Rejected: leaves the disposal leak
  standing and keeps the false "encrypted at rest" claim.
- **Podman `pass`/`shell` secret driver (GPG-encrypted).** Real encryption, but the GPG key
  must live somewhere: on a YubiKey (touch-gated → breaks unattended boot, the exact
  constraint that bars the forgejo signing key from hardware) or on disk adjacent to the data
  (no real protection). TPM solves precisely this "hardware key the host can use unattended."
- **SOPS + age in git.** Its value is decrypt-anywhere multi-machine — the *opposite* of the
  decision that runtime secrets never leave fedora-htpc. Good for config-as-code, wrong as the
  secrets backbone here. (htpc-mgmt ADR-006 already named sops+age its own future successor
  for *substrate* secrets — a separate question.)
- **OpenBao now.** Rejected as the *first* step: it does not provide the read-wall (D1), and
  its at-rest/secret-zero story still needs the TPM-unseal machinery D2 builds. Sequenced as
  Phase 2 (D6).
- **Privilege separation now.** The only real read-wall, but it reshapes the entire agent
  workflow (repo ACLs, git-signing, service control all need explicit grants). Deferred (D1),
  not dropped.
- **LUKS-encrypt the whole pool now.** The endgame answer, but in-place re-encryption of a
  live multi-TB btrfs pool is a large, risky, separately-funded project (the role-reversal).
  The targeted TPM-seal bridge gets the secrets-specific win now without it.

## References

- `docs/30-security/guides/secrets-management.md` — the stale guide this supersedes (to be
  rewritten as a pointer).
- **ADR-028** — Podman secret-store path split (the secret store lives on
  `subvol7-containers/storage` with an XDG symlink; the tmpfs move MUST account for this).
- **ADR-030** — Container Supply-Chain Trust Model (digest pinning narrows the
  compromise path that makes D1's residual risk acceptable); **ADR-029** — DB dump backbone
  (required before any DB-coupled rotation, D4); **ADR-038** — merge-commit workflow.
- **htpc-mgmt ADR-006** (substrate secrets strategy this refines), **ADR-001**
  (substrate-not-workloads — the boundary D3 evolves), **ADR-005** (storage-as-code) — in the
  private substrate repo.
- Superseded by **ADR-041** (workload-side boundary) and **htpc-mgmt ADR-007** (OpenBao mechanism).

---

**Decision made by:** User (patriark) + Claude Code analysis (design session 2026-06-14).
**Trigger:** A request to modernize secrets management surfaced that the documented store was
plaintext-on-unencrypted-disk and that the "LLM cannot read" goal is unreachable without
privilege separation — forcing an explicit, honest split between the achievable at-rest
bridge and the deferred operator boundary.
