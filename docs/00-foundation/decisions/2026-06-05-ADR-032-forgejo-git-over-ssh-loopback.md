---
type: ADR
title: "ADR-032: Forgejo Git-over-SSH — Loopback-Bound"
description: "ADR enabling loopback-bound git-over-SSH on the Forgejo instance so headless SSH sessions can authenticate with an SSH key instead of a keyring-locked HTTPS token."
sensitivity: public
created: 2026-06-05
updated: 2026-06-05
---

# ADR-032: Forgejo Git-over-SSH — Loopback-Bound

**Date:** 2026-06-05
**Status:** Accepted (Implemented 2026-06-05)

---

## Context

Forgejo (`git.patriark.org`) was deployed HTTPS-only — `DISABLE_SSH=true` +
`START_SSH_SERVER=false` — with git-over-SSH **explicitly deferred** (see `project_forgejo`
notes / original deployment). Auth and transport were Basic-over-HTTPS with a personal access
token; commit-signature *verification* worked over HTTPS without SSH ever being enabled.

A new requirement broke that posture's fit: **work on the repos from headless SSH sessions into
fedora-htpc** (from fedora-jern / MacBook Air, including while away from home). That surfaced a
credential problem the HTTPS-token model can't solve cleanly:

- The HTTPS token now lives in the **GNOME keyring** (`git-credential-libsecret`), which is
  **unlocked by the graphical login**. A non-graphical SSH session can't open it, and since SSH
  login is key-based (FIDO2), PAM never sees a password to auto-unlock it. So the token is simply
  **unavailable in headless SSH sessions.**
- The fallbacks each fail the bar: plaintext `store` re-introduces an unencrypted token; podman
  secrets' default `file` driver is base64 (not encrypted) and targets *containers*, not host
  CLIs; `pass` needs a GPG key that doesn't exist.
- SSH **agent forwarding** — the textbook "don't store a credential on the box" answer — was
  blocked by the workstation's global `IdentityAgent none` (a workaround for a *believed*
  gnome-keyring inability to sign sk/FIDO2 keys).

The right tool for authenticating git operations *inside an SSH session on the box* is an SSH key,
not an HTTPS token. Forgejo is the only remote that couldn't do that, because its SSH server was
off.

## Decision

### D1 — Enable Forgejo's built-in SSH server, published to loopback only

`START_SSH_SERVER=true`, `SSH_LISTEN_PORT=2222`, `SSH_PORT=2222`, `SSH_DOMAIN=localhost`,
`DISABLE_SSH=false`, and crucially **`PublishPort=127.0.0.1:2222:2222`** — bound to the host
loopback, not `0.0.0.0`. Only processes already on htpc (i.e. the owner's authenticated SSH
sessions) can reach it. **No LAN exposure, no internet exposure, no firewall change, no Traefik
involvement** (SSH is raw TCP, not HTTP). This reverses the "git-over-SSH deferred" posture, but in
a contained way: the attack surface added to the network is *zero*.

### D2 — Reuse the existing hardware key for auth; route via an ssh_config alias

Forgejo authenticates SSH by matching the offered public key against keys on the account. The htpc
FIDO2 signing key (already registered for verification) **doubles as the auth key** — no new key.
The `forgejo` remote uses an `~/.ssh/config` alias (`forgejo-local` → `HostName 127.0.0.1`,
`Port 2222`, `User git`) because the workstation's existing config aliases `localhost` to
`fedora-htpc.lokal`. `git push/pull forgejo` is now **token-free** over SSH.

### D3 — Remove the obsolete `IdentityAgent none` workaround (root-cause fix)

Evidence (verified against the new Forgejo SSH endpoint): the gnome-keyring `gcr-ssh-agent`
(**gcr 4.4**) **does** sign sk/FIDO2 keys — agent-based auth returns *"Authenticated"*, while
*file-based* signing (forced by `IdentityAgent none`) fails silently in the auth path
(`Server accepts key → No more authentication methods`). The workaround was therefore **obsolete
and actively breaking** sk auth. It is removed from the global `Host *`. ssh now uses the
persistent gcr agent, whose socket is exported in the **systemd `--user` environment** and kept
alive by **lingering**, so it is reachable in headless SSH sessions. Validated: daily outbound SSH
to UDM Pro and Pi-hole still authenticates cleanly.

## Consequences

### Positive

- **The headless-SSH credential problem is solved without storing any secret** — git to Forgejo
  authenticates with the always-present hardware key via the agent, from any on-htpc session.
- Zero new network attack surface: loopback-only, key-based auth, closed instance
  (`REQUIRE_SIGNIN_VIEW`, `DISABLE_REGISTRATION`).
- The sk-auth fix is **global** — every SSH host benefits, and the ssh_config is simpler (a stale
  workaround retired, documented inline).
- The HTTPS path (Traefik routing, web UI, SSH-signed-commit *verification*) is **unaffected**;
  both transports coexist.

### Negative

- Reverses a deliberate "no git-over-SSH" posture — one more enabled subsystem to reason about
  (mitigated: loopback bind makes it equivalent-to-off from any other host's perspective).
- Forgejo-SSH usability depends on the htpc graphical session keeping the agent populated
  (acceptable on an always-on auto-login HTPC; loopback means no remote exposure regardless).
- The htpc signing key now also serves **auth** (mild auth/signing reuse) — accepted: it's
  hardware-backed and the endpoint is loopback-scoped.

### Risks

- **Re-binding the published port off loopback** would instantly expose an SSH service. Mitigated
  by the explicit `127.0.0.1` bind and this ADR recording loopback as the invariant; widening to a
  LAN bind must be a deliberate follow-up that also adds CrowdSec/fail2ban on the port.
- **The global `IdentityAgent none` removal** is an outbound-SSH change affecting every host —
  validated against UDM/Pi-hole/Forgejo; one-line revert (re-add `IdentityAgent none` to `Host *`)
  if a host regresses. Inbound SSH into htpc is untouched.

## Alternatives Considered

- **HTTPS token in the GNOME keyring (libsecret).** The chosen store for *desktop* sessions, but
  GUI-unlocked → unusable headless. Kept for graphical use; rejected for the SSH-session case.
- **HTTPS token in podman secrets.** Default `file` driver is base64 (no encryption) and is built
  to inject into *containers*, not feed host CLIs; doesn't cover `fj` either. Right tool only when a
  *container* consumes the token (e.g. a future automated mirror job). Rejected here.
- **HTTPS token in plaintext `store`.** Works headless but unencrypted at rest. Rejected as the end
  state.
- **`pass` (GPG-encrypted) token store.** Encrypted *and* headless-capable, and would also unlock
  podman's `pass` secret driver — but requires generating a GPG key (none exists) and keeps Forgejo
  on HTTPS. A viable path; **deferred**, not rejected.
- **SSH agent forwarding from the laptops.** The canonical "no secret on the server" answer, but
  blocked by the workstation's `IdentityAgent none` and unnecessary for a loopback service the htpc
  key reaches directly. Superseded by D3 (which fixes the agent generally).
- **LAN-bound (not loopback) Forgejo SSH.** Would let the laptops push to Forgejo *directly* without
  first SSHing into htpc — but adds real LAN attack surface and demands brute-force protection on
  the port. Rejected for now (loopback matches the stated SSH-into-htpc workflow); trivially
  widenable later if the need appears.

## Related

- **`project_forgejo` deployment** — the HTTPS-only/native-auth posture this ADR amends.
- **ADR-006** — YubiKey-First Authentication (the sk key now also serves git auth).
- **ADR-016** — Configuration Design Principles (N/A to SSH: raw TCP, no Traefik route).
- **ADR-030** — Container Supply-Chain Trust Model (image still digest-pinned; unaffected).
- Session journal: `docs/98-journals/2026-06-04-forgejo-ssh-commit-signing-homelab-mirror-private.md`.

---

**Decision made by:** User (patriark) + Claude Code analysis
**Trigger:** Owner request for a practical, best-practice way to authenticate git work from SSH
sessions into the homelab (including while away) — the HTTPS token in the GUI-unlocked keyring is
unavailable in headless sessions, so the credential model had to move from HTTPS-token to SSH-key.
