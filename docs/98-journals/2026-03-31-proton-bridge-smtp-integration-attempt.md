# Proton Mail Bridge SMTP Integration — Incomplete

**Date:** 2026-03-31
**Goal:** Deploy Proton Mail Bridge as containerized SMTP relay for Authelia and future services
**Status:** Partially complete — bridge deployed and authenticated, SMTP auth from Authelia blocked
**Blocking issue:** `454 4.7.0 invalid username or password` — bridge rejects AUTH even with correct credentials

---

## What Was Accomplished

### Infrastructure Built
- **Custom container image** built from official RPM (`localhost/proton-bridge:3.23.1`) — Fedora 43 base, includes `pass` for keychain, `nmap-ncat` for healthcheck, `socat` for port forwarding
- **Dedicated mail network** (`systemd-mail`, 10.89.9.0/24, Internal=true) created for SMTP relay isolation
- **Proton Bridge authenticated** — interactive CLI login completed with TOTP 2FA, account synced, credentials persisted to BTRFS storage
- **Quadlet and network files** created and symlinked
- **Podman secrets** created for SMTP username and password
- **Authelia quadlet** updated with mail network (10.89.9.78)
- **Bridge service running** — SMTP handshake responds on port 1025 (native) and port 25 (socat forwarder)

### Files Created
| File | Purpose |
|------|---------|
| `builds/proton-bridge/Containerfile` | Custom image from RPM |
| `builds/proton-bridge/entrypoint.sh` | Starts socat port 25→1025 forwarder + bridge |
| `quadlets/mail.network` | Dedicated SMTP network (10.89.9.0/24) |
| `quadlets/proton-bridge.container` | Service quadlet with keep-id + NET_BIND_SERVICE |
| Storage dirs on BTRFS pool | config, data, gnupg, password-store |

### Podman Secrets Created
- `proton_bridge_smtp_username`
- `proton_bridge_smtp_password`

---

## What Blocked Completion

### Problem 1: Authelia SMTP Port Bug (Worked Around)
Authelia v4.39.16 ignores the port in `smtp://host:port` addresses — always connects to port 25 regardless of the specified port. The deprecated `host`/`port` fields also auto-map to the same broken `smtp://` scheme.

**Workaround:** socat inside the bridge container forwards port 25 (bound to 0.0.0.0) → 127.0.0.1:1025 (bridge native). Required `AddCapability=NET_BIND_SERVICE` for privileged port binding.

### Problem 2: Bridge Binds to 127.0.0.1 Only (Worked Around)
Proton Bridge SMTP server listens on `127.0.0.1:1025`, not `0.0.0.0:1025`. Other containers on the mail network cannot reach it directly.

**Workaround:** Same socat forwarder — binds to `0.0.0.0:25`, forwards to `127.0.0.1:1025`.

### Problem 3: SMTP AUTH Rejected (UNRESOLVED)
```
454 4.7.0 invalid username or password
```

Even with the correct bridge-generated credentials (verified manually from `info` output), AUTH PLAIN is rejected. This occurs:
- On port 1025 directly (no socat)
- On port 25 via socat
- From inside the bridge container itself
- From the Authelia container
- With and without STARTTLS

**Hypothesis:** Proton Bridge may require STARTTLS to complete before accepting AUTH credentials. The manual test used plain-text AUTH PLAIN (base64-encoded credentials sent before TLS upgrade). When STARTTLS negotiation happens first (as Authelia attempts), the socat forwarder should pass through TLS transparently, but this was not verified due to lack of `openssl`/`swaks` tools in the containers.

**Alternative hypothesis:** The bridge-generated SMTP password may have been invalidated when the bridge service was restarted multiple times during debugging, or the password in the Podman secret doesn't match what the bridge currently expects.

---

## Current State

- **Authelia:** Reverted to `filesystem` notifier (working, OTPs written to `/data/notification.txt`)
- **Proton Bridge:** Running as a service, authenticated, SMTP responding on ports 25 and 1025
- **Mail network:** Created and functional, Authelia has connectivity to bridge
- **SMTP config:** Commented out in Authelia config, ready to uncomment when auth issue is resolved
- **SMTP secrets:** Commented out in Authelia quadlet

---

## Next Steps to Resolve

1. **Verify credentials:** Stop the bridge, re-run interactive CLI, run `info` to confirm the current SMTP password matches the Podman secret
2. **Test STARTTLS + AUTH:** Install `openssl` or `swaks` on the host (requires sudo) and test: `swaks --to test@test.com --from surfaceideology@pm.me --server 10.89.2.88:1025 --tls --auth PLAIN --auth-user surfaceideology@pm.me --auth-password <bridge-password>`
3. **Check bridge mode:** The bridge has "SSL" and "STARTTLS" security modes — verify it's set to STARTTLS (which is what the EHLO response advertises)
4. **Consider bridge version:** v3.23.1 may have SMTP auth quirks — check Proton Bridge release notes/issues

---

## Lessons Learned

1. **Proton Bridge is not designed for headless/container operation.** It's a desktop app that happens to have a CLI mode. The keychain requirement, GUI launcher binary, localhost-only binding, and interactive-only login all create friction for containerized deployment.

2. **Authelia v4.39.16 has a port parsing bug** for the `smtp://` scheme in the `notifier.smtp.address` field. The deprecated `host`/`port` format is the only workaround, and even that auto-maps to the broken scheme internally. Filed mentally as a known issue.

3. **Test the full chain before building infrastructure.** We built the network, quadlets, image, and secrets before confirming SMTP auth actually works. A 5-minute manual `telnet` test to the bridge would have surfaced the AUTH issue before any of the infrastructure work.

4. **socat is a useful workaround for port/binding issues** but adds complexity. The entrypoint script pattern (background socat + exec main process) works but makes the container harder to reason about.
