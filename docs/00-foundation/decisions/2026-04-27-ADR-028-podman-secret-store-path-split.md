# ADR-028: Podman Secret-Store Path Split After Storage Migration

**Date:** 2026-04-27
**Status:** Accepted
**Related:** ADR-025 (deferred DB migration), the 2026-04-18 storage migration that moved `graphRoot` to `/mnt/btrfs-pool/subvol7-containers/storage`
**Surfaced by:** [`2026-04-27-sso-recovery-and-secret-store-bomb-private.md`](../../98-journals/2026-04-27-sso-recovery-and-secret-store-bomb-private.md)

## Context

The 2026-04-18 storage migration moved Podman's `graphRoot` from the default `~/.local/share/containers/storage/` to `/mnt/btrfs-pool/subvol7-containers/storage/` via `~/.config/containers/storage.conf`'s `rootless_storage_path` setting. The migration verified that running containers stayed running and that new container starts could resolve images, networks, and volumes from the new location.

It did not verify that secret mounts still resolved. They did not.

Podman's file-driver secret store has two state files:

| File | Purpose | Path read by |
|---|---|---|
| `secrets/filedriver/secretsdata.json` | base64-encoded payload for every secret | runtime container start (`--secret <name>`) |
| Same file | metadata index used for listing/inspect | `podman secret ls`, `podman secret inspect` |

Both *should* live under graphRoot, and after migration both *do* live at `/mnt/btrfs-pool/subvol7-containers/storage/secrets/filedriver/secretsdata.json`. However, the runtime mount code path on this Podman version reads from the legacy XDG path `~/.local/share/containers/storage/secrets/filedriver/secretsdata.json` regardless of `rootless_storage_path`. The CLI honors `rootless_storage_path`; the runtime does not.

After the migration, the legacy XDG directory contained only `secretsdata.lock` (zero bytes) — no `secretsdata.json`. Effect:

- `podman secret ls` worked. Listed every secret, correct names, correct IDs.
- `podman secret inspect <name>` worked. Returned valid metadata.
- `podman run --rm --secret <name> alpine cat /run/secrets/<name>` failed with `Error: <secret-id>: no such secret`.
- Every container *currently running* was unaffected because secrets are read at start, not at runtime. They held the values they got at their last successful start.
- Every container *not yet restarted* was a ticking time bomb. The first secret-using service to restart (Traefik, on 2026-04-27) failed to start with the cryptic ID-only error. Authelia, MariaDB, PostgreSQL, Vaultwarden, Immich, MongoDB, Redis instances, Grafana, monitoring stack, homepage tile API keys — ~25 services across the stack — would have failed the same way on next restart.

The latency between the migration (2026-04-18) and the discovery (2026-04-27) was nine days. The next reboot or `dnf update` would have brought the stack up degraded with no obvious common cause.

This is not a Podman bug; it's a known split between graphRoot relocation (which honors the config) and the file-driver secret store (which does not, on this version). Whether future Podman versions unify the paths is unknown and not a basis for this ADR.

## Decision

**Maintain a symlink at the legacy XDG path pointing to the migrated secret-store data file.**

```
~/.local/share/containers/storage/secrets/filedriver/secretsdata.json
  → /mnt/btrfs-pool/subvol7-containers/storage/secrets/filedriver/secretsdata.json
```

The symlink:

- Resolves the runtime mount path's read to the actually-populated data file.
- Stays coherent with `podman secret create`/`rm` operations because those write to the migrated location (graphRoot/secrets), and the symlink simply re-views the same bytes.
- Has no separate state to drift — there is no copy to keep in sync.
- Inherits SELinux context `data_home_t` from the legacy parent dir, which matches the target's context (also `data_home_t`). Podman runtime opens the symlink, follows it, reads with the target's context. No SELinux denial.

Not chosen:

- **Copying the file periodically.** Drift risk: any `podman secret create` writes to one location only; the copy at the other goes stale. The next runtime mount would read stale data, which is a worse failure mode than "no such secret" (silent stale credentials in containers).
- **Bind-mounting one directory onto the other.** Requires root, not viable in the rootless model. Also brittle across reboots without a systemd mount unit.
- **Setting an environment variable to override the secret-store path.** No documented variable exists for this on the file driver; `CONTAINERS_STORAGE_CONF` doesn't help because the issue is the runtime ignoring the config it already reads.
- **Reverting the storage migration.** Massively over-correcting for a one-line fix. The migration's other benefits (capacity, BTRFS features) are intact.

## Consequences

**Positive:**

- Every secret-consuming container can now restart, get pulled by autoupdate, or come up after reboot without failing on secret resolution.
- Future `podman secret create` operations work transparently — they write to graphRoot, the symlink picks up the change.
- Recovery of this same failure on a different host (different user, different graphRoot) is one symlink command.

**Negative:**

- A hidden invariant: `~/.local/share/containers/storage/secrets/filedriver/secretsdata.json` must remain a symlink, not a regular file. A future cleanup pass that "tidies up" legacy XDG paths could break secrets again silently. Mitigation: F1 below makes this detectable in the security audit.
- If Podman ever fixes the runtime to honor `rootless_storage_path`, the symlink becomes a no-op (target read directly via the config-honoring path, and the symlink is also followed and lands on the same file). Harmless to leave in place.
- If the migrated path is ever re-migrated (e.g., to a new disk), this ADR's symlink target needs updating — not automatic.

**Neutral:**

- This is system state on the homelab host, not a config artifact in the Git repo. Restoration after a host rebuild requires re-running the symlink command (one line, in the post-restore checklist).

## Verification (becomes audit rule SA-CTR-08-runtime)

The CLI-side check (`podman secret ls`) is necessary but insufficient. The runtime-side check is:

```bash
podman run --rm --secret <secret_name> alpine true
```

Exit code 0 = secret is mountable. Non-zero with "no such secret" = the path split is back, regardless of what `podman secret ls` says.

The security audit (`scripts/security-audit.sh`) will be extended with **SA-CTR-08-runtime**: enumerate every secret name referenced in `quadlets/*.container`, run the above check for each, FAIL on any non-zero. Implementation effort: ~5 minutes. This is the tripwire that would have caught the original break the morning after 2026-04-20 instead of nine days later.

The existing **SA-CTR-08** (CLI-level "all Podman secrets resolve correctly") stays in place; the runtime check is additive, not a replacement.

## Restoration procedure (post-host-rebuild)

```bash
# Verify the migrated data file exists
test -f /mnt/btrfs-pool/subvol7-containers/storage/secrets/filedriver/secretsdata.json

# Recreate the legacy directory if the rebuild lost it
mkdir -p ~/.local/share/containers/storage/secrets/filedriver

# Re-establish the symlink
ln -sf /mnt/btrfs-pool/subvol7-containers/storage/secrets/filedriver/secretsdata.json \
       ~/.local/share/containers/storage/secrets/filedriver/secretsdata.json

# Verify
podman run --rm --secret crowdsec_api_key alpine true && echo OK
```

## Lessons reinforced (not the ADR itself, but worth pinning)

- A storage migration's acceptance criteria must include "a representative secret-using container can be stopped, started, and reach a healthy state with secrets mounted." The 2026-04-18 migration did not. The cost of adding this step is one container restart; the cost of skipping it was nine days of latent risk.
- "`podman info` confirms graphRoot moved" is a true statement that does not imply "all stored state moved correctly." Trust the runtime, not the introspection.
- Whenever a Podman feature splits responsibilities between the CLI and the runtime, assume divergence until proven otherwise. The file-driver secret store is one example; there may be others (network state, image metadata) lurking with similar splits that haven't surfaced yet because nothing has stress-tested them.
