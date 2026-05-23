# Proton Mail Bridge Container

**Status:** Active — deployed via `proton-bridge.container` quadlet (`systemctl --user`
unit is `active`/`generated`). SMTP relay for homelab services on the `mail` network.
First-run still needs interactive GPG/`pass`/Proton-login setup; once initialized,
state persists in the mounted volumes on `subvol7-containers/proton-bridge/`. See
`docs/98-journals/2026-03-31-proton-bridge-smtp-integration-attempt.md` for the
integration history.

## Build inputs & supply-chain verification (ADR-030 P5/P6)

The 84 MB RPM is **not committed** (gitignored via `builds/**/*.rpm`). Two committed
artifacts pin its provenance, and the build **fails closed** if either check fails:

| Artifact | Committed? | Verifies |
|----------|-----------|----------|
| `protonmail-bridge-3.23.1-1.x86_64.rpm` | no (gitignored) | — |
| `protonmail-bridge-3.23.1-1.x86_64.rpm.sha256` | yes | exact bytes (`sha256sum -c`) |
| `bridge_pubkey.gpg` | yes | authenticity (`rpm --checksig`) |

- **Expected RPM SHA-256:** `ffd001f7aab07d09b99d6af3e81afe88ed27f9caf0502d37887dcbfea11c39c4`
- **Proton signing key fingerprint:** `D51E64D3 E63EDC3E EF7864CE E2C75D68 E6234B07`
  (`Proton Technologies AG (ProtonMail Bridge developers) <bridge@protonmail.ch>`,
  rsa4096, fetched from <https://proton.me/download/bridge/bridge_pubkey.gpg>).
- **Base image** is digest-pinned in the `Containerfile`.

## Build

```bash
# 1. Download the RPM from https://proton.me/mail/bridge
#    Place at: builds/proton-bridge/protonmail-bridge-3.23.1-1.x86_64.rpm
# 2. Build (verification runs automatically; build aborts on hash/signature mismatch):
podman build -t localhost/proton-bridge:3.23.1 builds/proton-bridge/
```

To verify the RPM by hand before building:

```bash
cd builds/proton-bridge
sha256sum -c protonmail-bridge-3.23.1-1.x86_64.rpm.sha256
gpg --show-keys bridge_pubkey.gpg   # confirm fingerprint above
```

When bumping the bridge version: replace the RPM, regenerate the `.sha256` sidecar
(`sha256sum protonmail-bridge-<ver>-1.x86_64.rpm > <same>.sha256`), update the version
strings in `Containerfile` + this README, and re-resolve the base digest if updating Fedora.
