# Nextcloud Music external storage made writable for library ingestion

**Date:** 2026-06-26
**Status:** PR #317 merged (merge commit `9004ef4`, substance `631442f`). Live + verified server-side; owner to confirm client end-to-end.
**Origin:** A music copy from the Nextcloud desktop client (`mirall`, `192.168.1.71`) failed — `405` on `MKCOL`, `403` on `PUT` under `/Music/`.

## Root cause
Server-side, **by design**. `/Music` (`subvol5-music`) was read-only at two independent layers: the `:ro` bind mount *and* the external-storage `readonly: true` flag. The library is host-curated and mounted read-only into both Nextcloud and Navidrome so the containers can't mutate it. The client was behaving correctly; the server refused the writes.

(Aside: `fedora-jern` is the owner's dual-boot machine (Fedora Workstation 44 / Windows 11); `.71` was booted into its Windows side at copy time — the `mirall` UA `windows-10.0.26200` is a Win11 build, not Win10 — so name and OS are consistent, no host mix-up.)

## Change (owner opted to allow NC-side ingestion)
- Quadlet bind `:ro,z` → `:z` — kept the **shared lowercase** SELinux label because Navidrome mounts the same subvol `:ro,z`.
- POSIX ACL (ADR-019): `u:100032:rwx` (www-data) + `u:patriark:rwx` + `default:` across `subvol5-music` (121,906 entries) — host state, not git.
- `occ files_external:option 3 readonly false` — runtime state, not git.

## Verified
Mount shows `rw`; `www-data` write to `/external/music` succeeds (the exact op a WebDAV PUT performs); `occ` shows mount 3 `readonly` cleared; Navidrome unaffected — still `:ro`, still healthy.

## Trade-off accepted
Nextcloud users can now add/modify/**delete** files in the library Navidrome serves. Navidrome still cannot write it. If this proves too sharp, the safer pattern is a dedicated writable "drop" subfolder rather than the whole library writable.
