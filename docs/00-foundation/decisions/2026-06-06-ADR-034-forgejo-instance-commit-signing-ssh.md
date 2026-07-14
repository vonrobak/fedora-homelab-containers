---
type: ADR
title: "ADR-034: Forgejo Instance Commit Signing (SSH)"
description: "ADR configuring the Forgejo instance to SSH-sign the merge/squash commits it creates server-side, closing the unsigned-merge-commit gap on main."
sensitivity: public
created: 2026-06-06
updated: 2026-06-06
---

# ADR-034: Forgejo Instance Commit Signing (SSH)

**Date:** 2026-06-06
**Status:** Accepted (config staged on branch `feat/forgejo-instance-commit-signing`;
activated once the instance key + podman secrets are created and Forgejo restarts)

---

## Context

Commit signing on the homelab moved to **SSH-format signatures** backed by FIDO2
hardware keys: authors sign their own commits with their YubiKeys, and the per-host
touch/PIN policy is recorded in **ADR-033**. Verification is host-agnostic
(`allowed_signers` carries no enforcing options) so any author's good signature
verifies as `G`.

That covers **author** commits. It does **not** cover commits the **forge itself**
creates. When a PR is merged — and especially **squash-merged**, the homelab's
preferred strategy for a clean linear `main` — Forgejo synthesises a *new* commit
server-side. Its committer is `<name>@noreply.git.patriark.org` and, with no instance
signing configured, that commit is **UNSIGNED**. So even though every author signs
locally, `main` steadily accumulates unsigned merge/squash commits.

This was verified on the sibling `jern-mgmt` project (2026-06-06): locally-authored
commits show `Good` SSH signatures; every server-side merge/squash commit on the
Forgejo instance is unsigned. The Forgejo instance was not configured to sign its own
commits.

This is the same class of gap GitHub solves by **re-signing merged `main` with its
web-flow key** (ADR-033 §D4). Our self-hosted forge had no equivalent.

### Constraints

- **A server cannot tap a YubiKey.** Forgejo runs unattended; the instance signer
  must be a **passphraseless software key**, not a FIDO2 credential. (This is a
  *different* key from any author key — it signs *as the forge*, not as a person.)
- **Forgejo / git / OpenSSH must support SSH signing.** Confirmed on the running
  instance (see Decision): Forgejo `15.0.2`, git `2.52.0` (≥2.34), OpenSSH `10.2p1`
  (≥8.2p1).
- **Config is by environment variables**, matching every other Forgejo setting in
  `quadlets/forgejo.container` (no `app.ini` is mounted). The `[repository.signing]`
  section name contains a dot, which Forgejo's `environment-to-ini` escapes as
  `_0X2E_`.
- **The private key is a secret** and must follow the repo's podman-secrets
  convention — never committed.

## Decision

Enable **instance commit signing** in **SSH format** on the Forgejo container, using a
dedicated passphraseless `ed25519` software key owned by the forge. Squash-merge stays
the default; every server-side merge/squash commit is now signed by the instance key
and shows **Verified**.

### D1 — `[repository.signing]` settings (env vars in the quadlet)

| ini (`[repository.signing]`) | Value | Quadlet env var |
|---|---|---|
| `FORMAT`        | `ssh` | `FORGEJO__repository_0X2E_signing__FORMAT` |
| `SIGNING_KEY`   | `/run/secrets/forgejo_signing_key.pub` | `…__SIGNING_KEY` |
| `SIGNING_NAME`  | `patriark.org Forgejo` | `…__SIGNING_NAME` *(quoted — has a space)* |
| `SIGNING_EMAIL` | `forgejo@git.patriark.org` | `…__SIGNING_EMAIL` |
| `MERGES`        | `always` | `…__MERGES` |

- `SIGNING_KEY` points at the **public** key. git invokes
  `ssh-keygen -Y sign -f <path>`, and ssh-keygen locates the **private** key by
  stripping `.pub` — so both files must sit at sibling paths. *(Empirically verified:
  signing `-f key.pub` with no agent and a passphraseless key succeeds, and the result
  verifies via `allowed_signers`.)*
- `SIGNING_EMAIL` becomes the signer **principal**. Author hosts add this principal +
  the instance public key to `~/.config/git/allowed_signers` so forge-created commits
  also verify **locally** (not just in the Forgejo UI).
- `SIGNING_NAME` contains a space, so the whole `Environment=` assignment is
  double-quoted — systemd splits unquoted `Environment=` values on whitespace.

### D2 — Key delivery via podman secrets (uid/gid-mapped, never committed)

The keypair is delivered as **two podman file secrets** mounted into the container,
matching the repo's secrets convention (cf. `gathio`, `prometheus`):

```
Secret=forgejo_signing_key,    type=mount,target=/run/secrets/forgejo_signing_key,    uid=1000,gid=1000,mode=0600
Secret=forgejo_signing_key_pub,type=mount,target=/run/secrets/forgejo_signing_key.pub,uid=1000,gid=1000,mode=0644
```

- The gitea process runs as **container uid 1000 (`git`)**, so the mounts set
  `uid=1000,gid=1000` (podman maps these through the rootless userns — a host bind
  mount would instead surface as container-root and the `git` user couldn't read a
  `0600` private key). Private key `0600`, public key `0644`.
- The **canonical key source** lives at `~/containers/secrets/forgejo_signing_key{,.pub}`
  (the `secrets/` dir is gitignored wholesale) as the DR copy; the podman secrets are
  created from it. The **private key is never committed.**

### D3 — Scope: `MERGES=always`

`MERGES=always` signs every server-side merge/squash/rebase commit. This is the
explicit gap being closed. CRUD web-editor commits (`CRUD_ACTIONS`) and the
repo-`INITIAL_COMMIT` are *not* signed by this change; the realistic path onto `main`
is reviewed PRs, which are covered. Those can be added later (`…__CRUD_ACTIONS=always`,
`…__INITIAL_COMMIT=always`) if web-editor commits to `main` become a thing.

## Consequences

### Positive

- **`main` is fully verifiable end-to-end:** author commits by FIDO2 YubiKeys
  (ADR-033), forge merge/squash commits by the instance key — and squash-merge can
  stay the default for clean linear history.
- **Verifiable locally too:** the instance principal in `allowed_signers` means
  `git log --show-signature` recognises forge commits on every machine, not only in the
  Forgejo UI. The public key is served at `/api/v1/signing-key.ssh`.
- **Convention-aligned:** env-var config + podman secrets, no new mechanism, no mounted
  `app.ini`.

### Negative / Risks

- **The instance signer is a passphraseless software key.** Anyone who can read the
  podman secret store (or `secrets/`) on htpc can mint commits that verify as the
  instance. This is the same trust property GitHub's web-flow signing key has, and is
  bounded by host hardening + the physical-security model (ADR-033). It is strictly an
  *instance* identity — it cannot impersonate an *author* (different key, different
  principal).
- **Key loss / rotation** invalidates the principal→key mapping: a regenerated key must
  be re-added to every author host's `allowed_signers`. Mitigated by the DR copy in
  `secrets/`.
- **Bootstrap commit is unsigned by Forgejo:** the very PR that introduces this config
  merges before signing is active, so that one merge commit is not instance-signed
  (expected, one-time).

## Verification

After creating the key + secrets and restarting Forgejo:

1. `curl -s https://git.patriark.org/api/v1/signing-key.ssh` returns the instance
   public key (`ssh-ed25519 AAAA…`).
2. Open a throwaway PR and **squash-merge** it; the resulting `main` commit shows
   **Verified** in the Forgejo UI (read it via
   `GET /repos/{o}/{r}/commits?sha=<sha>` → `.commit.verification.verified=true`,
   reason `patriark.org Forgejo`), and `git log --show-signature` recognises the
   instance signature once the principal is in `allowed_signers`.
3. Normal `git push` / `clone` (HTTPS and loopback-SSH, ADR-032) still work.

## Related

- **ADR-033** — Per-Host Commit-Signing Policy (author signing; this ADR is its
  forge-side complement). *(private)*
- **ADR-032** — Forgejo Git-over-SSH Loopback.
- **ADR-030** — Container Supply-Chain Trust Model (signed history is part of
  provenance).
- **ADR-006** — YubiKey-First Authentication.
- `project_forgejo` memory — Forgejo deployment + SSH signing end-to-end.

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** Sibling `jern-mgmt` verified that Forgejo server-side merge/squash commits
land unsigned even when authors sign locally — `main` needed the forge to sign its own
commits so squash-merge (default) and a fully verifiable history can coexist.
