# Proton Mail Bridge Container

**Status:** Incomplete — see `docs/98-journals/2026-03-31-proton-bridge-smtp-integration-attempt.md`.

## Build requirements

The RPM is not committed (81MB binary, gitignored). Download before building:

```
# From https://proton.me/mail/bridge
# Place at: builds/proton-bridge/protonmail-bridge-3.23.1-1.x86_64.rpm
podman build -t proton-bridge:3.23.1 builds/proton-bridge/
```

Bridge requires interactive GPG key setup + `pass init` + Proton account login on first run — not suitable for automated quadlet deployment without additional work.
