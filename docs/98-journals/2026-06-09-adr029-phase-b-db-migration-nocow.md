# ADR-029 Phase B — DB Migration to subvol8-db (NOCOW) — Session Lessons

**Date:** 2026-06-09
**Scope:** Executed Phase B of ADR-029 — migrated the 4 remaining COW-in-snapshot databases (`gathio-db`, `nextcloud-db`, `prometheus`, `postgresql-immich`) from `subvol7-containers` into `subvol8-db` (NOCOW). All 4 verified healthy on the new path. PR #258 fixed a preflight blocker first.
**Refs:** ADR-029 · GH#220 (execution reminder) · PR #258 · memory [[project_db_storage_architecture]] · [[project_platform_gotchas]]

---

## Lessons learned

**1. The dry-run preflight earned its entire keep — a swallowed-stderr permission failure was masquerading as a real negative.** `cmd_preflight` ran `btrfs subvolume show "$SUBVOL8"` *without* `sudo` — the only privileged call in the script missing it. As a non-root user it failed with `Operation not permitted`; `>/dev/null 2>&1` discarded the stderr, so preflight reported the *opposite of the truth* (`subvol8-db is NOT a subvolume`) and set `fail=1`. Under `--execute` that `fail=1` is hard-gated (`die "Preflight FAILED"`), and because the call lacked `sudo`, priming sudo wouldn't have helped — it would have **aborted the real migration mid-offline-window**. Two takeaways: (a) actually *run* the dry-run on safety-critical tooling before the window, don't just trust that it's ready; (b) never `2>&1`-swallow stderr on a privileged probe — a permission error and a genuine negative become indistinguishable. Ground-truthed subvolumehood the unprivileged way instead: inode `256` + `findmnt`.

**2. `chattr -m` then `+C` — and why "no `m`" still means "uncompressed."** The script does `chattr -m` (REMOVE the explicit no-compress attribute) then `chattr +C` (set NOCOW). The `-`/`+` is remove/add, so the dirs end with **only `C`, no `m`** (`lsattr -d` → `---------------C------` on all 4). This matters because this homelab previously proved the *explicit* `m` attribute causes harm/inconvenience alongside NOCOW — so the tool deliberately avoids leaving it set. BUT the data is still uncompressed regardless: NOCOW and compression are mutually exclusive on btrfs (`C` and `c` can't coexist). So "no `m`" ≠ "compressed" — don't conflate the two mechanisms. The compression loss is intrinsic to the NOCOW design and accepted (it's the price of killing COW fragmentation); only the separately-harmful `m` flag is avoided. **Invariant for any future NOCOW DB dir: end state should be `C` only, never `m`.**

**3. `--yes` "one gulp" was safe *because* each migrate is atomic and health-gated — and I verified that before trusting it.** Checked all 4 quadlets actually define healthchecks (`mongosh ping`, `healthcheck.sh`, `/-/healthy`, `pg_isready`) before recommending `--yes`; without a real healthcheck, `wait_healthy`'s `podman healthcheck run` would false-fail and auto-rollback every service. With real gates: unhealthy → auto-reverts the quadlet, source untouched; `|| break` halts the loop; source only *renamed* (never deleted) after health passes. Partial migration is acceptable by design. Don't hand someone a `--yes` loop without confirming the inner safety gate is real.

**4. Interactive sudo can't be driven through the agent's shell — the human runs the privileged loop.** The agent's Bash has no TTY and Fedora uses per-tty sudo timestamps, so `sudo -v` can't be primed for it and every privileged step would hang. The migration (sudo rsync/du/find/filefrag/mv) and even preflight were run by the user in their own terminal while the agent verified output line-by-line. Same shape as the ansible-become friction — the working pattern is "user elevates, agent reads the result."

## State at landing

- **Migrated + verified healthy on subvol8-db (NOCOW, `C`-only):** `gathio-db`, `nextcloud-db`, `prometheus`, `postgresql-immich`. No shared extents, sizes matched, sampled files all NOCOW.
- **Rollback artifacts retained:** sources at `<path>.pre-migration-2026-06-09` (incl. `nextcloud-db/data.pre-migration-…`). Delete after ~14 clean days: `./scripts/migrate-db-to-subvol8.sh cleanup <svc> --execute`.
- **PR #258 merged** (preflight `sudo` fix).
- **User rebooting now** (`dnf update && reboot`) → then `./scripts/post-reboot-verify.sh`.

## Finalization (2026-06-09)

1. ✅ Committed the 4 quadlet `Volume=` repoints + this journal (PR #260).
2. ✅ ADR-029 status → **Phase B executed** + tenant table/consequences updated; `[[project_db_storage_architecture]]` memory bumped.
3. ✅ Re-ran `filefrag-baseline.sh` (retargeted from the now-absent subvol7 paths to the subvol8 homes, in this change). Before/after below.
4. ✅ GH#220: "executed 2026-06-09" outcome posted on the closed reminder issue.

Same session, unrelated but surfaced *by* this migration's reboot: a recurring **boot I/O storm** was root-caused and the monitoring data-plane (prometheus/loki/grafana) reclassified to boot tier C — PR #259 / ADR-035.

### Fragmentation delta — the COW-defeated-by-snapshots antipattern, killed

`filefrag` extents/file, before (subvol7, COW-in-snapshot, 2026-05-22) → after (subvol8, NOCOW, 2026-06-09):

| DB | worst file | before | after |
|----|-----------|--------|-------|
| postgresql-immich | PG heap | mean 6.3 / max **1,862** | mean 0.9 / max **1** |
| nextcloud | `oc_filecache.ibd` | **11,777** | **6** |
| gathio-db | WiredTiger data | max **2,362** | **2** (the lone max-70 is a transient FTDC `diagnostic.data` file) |
| prometheus | persistent `chunks_head` | — | **4** |

NOCOW references (unchanged): forgejo-db mean 0.9 / max 18; loki mean 1.0.

**Note on prometheus:** its live `wal/00002638–2640` segments show max ~242 extents — expected for an append-heavy WAL actively being written, and truncated on checkpoint. The *persistent* TSDB (`chunks_head` = 4 extents) is flat, which is the durable measure. NOCOW killed the random-overwrite COW fragmentation; append-growth extents on a live WAL are normal and self-limiting.

Raw baselines (gitignored): `data/backup-logs/filefrag-baseline-2026-05-22-2245.txt` (before), `…-2026-06-09-0735.txt` (after).
