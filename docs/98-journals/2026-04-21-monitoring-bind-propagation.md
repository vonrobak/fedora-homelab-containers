# Monitoring Bind Propagation — ADR-023

**Date:** 2026-04-21
**PR:** _pending_
**ADR:** [ADR-023](../00-foundation/decisions/2026-04-21-ADR-023-monitoring-bind-propagation.md)
**Context:** Cross-project fallout investigation. Urd's drive-swap workflow (LUKS-encrypted BTRFS rotation between WD-18TB and WD-18TB1) was consistently failing the next unlock with `Error unlocking /dev/sdX: Failed to activate device: File exists`. Root cause diagnosed from the Urd side: the monitoring containers were holding the `/run/media/patriark/<LABEL>` mount in their namespace, pinning the LUKS dm-mapper refcount above zero. Restarting the containers was the recurring workaround. This journal is about landing the permanent fix on the homelab side.

---

## What shipped

| File | Change |
|---|---|
| `quadlets/cadvisor.container` | `Volume=/:/rootfs:ro` → `Volume=/:/rootfs:ro,rshared` |
| `quadlets/node_exporter.container` | `Volume=/:/host:ro,rslave` → `Volume=/:/host:ro,rshared`; `--collector.filesystem.mount-points-exclude` extended with `run/media/.+` |
| `docs/00-foundation/decisions/2026-04-21-ADR-023-monitoring-bind-propagation.md` | New ADR |
| `docs/00-foundation/decisions/2026-03-28-ADR-021-urd-backup-tool.md` | Added "Drive-swap safety" cross-reference at top of Integration Contract |

Post-deploy: both containers `active`, healthchecks pass, `shared:N` present on `/rootfs` and `/host` (was absent), filesystem metrics still cover `/`, `/boot`, `/boot/efi`, `/home`, `/mnt` — `/run/media/*` filtered out.

---

## Three things worth writing down

### `rslave` silently downgrades to `private` in rootless podman

node_exporter already carried `Volume=/:/host:ro,rslave` in its quadlet and had for a long time. Live `/proc/<pid>/mountinfo` showed no `master:X` field — the bind was effectively `private`. That's why host unmounts never propagated in.

The reason is a kernel permission check. To establish a slave relation, the caller must have CAP_SYS_ADMIN in the user namespace that owns the source mount. Rootless podman creates a new userns, host `/` is owned by the initial userns, and crun doesn't have the cap over that. The kernel silently falls back to `private` rather than erroring. The quadlet looks correct; the running mount does something different. Worth remembering whenever a rootless container is supposed to "receive" host mount events.

### `bind-nonrecursive=true` doesn't work on `/`

First attempt was `--mount type=bind,source=/,destination=/host,ro=true,bind-nonrecursive=true` — the clean "never see /run/media at all" path. Both containers failed to start with:

```
mount `/` to `host`: Invalid argument
```

Not a quadlet issue. Reproduced with a one-shot `podman run` against alpine. `bind-nonrecursive=true` works fine for `/etc` and other sub-paths, but fails specifically when source is `/`. crun's `open_tree()` without `AT_RECURSIVE` against the host root mount is rejected in rootless mode. This is kernel/crun, not podman or quadlet syntax — no workaround at the container layer short of binding specific subdirectories instead of `/`, which loses filesystem-collector coverage for anything not pre-declared.

### `rshared` is the working alternative — and it's safe here

Once slave was out and non-recursive was out, the remaining lever was `rshared`. `rshared` is bidirectional by kernel design: an unmount on either side propagates to peers. That's usually the reason to avoid it — a container could unmount something and affect the host.

Here it's fine. Rootless containers lack CAP_SYS_ADMIN in their userns, so they cannot initiate umount/mount in the first place. The "bidirectional" property is de facto one-way (host → container). Verified in `/proc/<pid>/mountinfo`: both containers now show `shared:N` on the root bind and all inherited submounts (including `/run/media/patriark/WD-18TB`). Host unmount of the drive will propagate in and release the reference.

---

## Validation status

- ✅ Containers start clean, healthchecks pass.
- ✅ `/proc/<pid>/mountinfo` shows `shared:N` on root bind for both containers.
- ✅ node_exporter metrics cover `/`, `/boot`, `/boot/efi`, `/home`, `/mnt`; no `/run/media/*` series.
- ✅ cAdvisor continues to report container cgroups (unchanged — pre-existing systemd-factory fallback).
- ⏳ End-to-end drive-swap validation: the next Urd offsite rotation will prove host unmount actually drops the container's mount reference. Until that happens in production, ADR-023 is accepted-but-unvalidated on the drive-swap outcome specifically.

---

## Cross-project note

Documented the integration contract on both sides. ADR-021's Integration Contract now opens with a "Drive-swap safety" paragraph pointing at ADR-023, so future contributors touching monitoring binds see the constraint before they break it. Urd's side will keep its own memory entry for the symptom.
