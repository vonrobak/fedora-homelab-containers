# Journal — Three-Tier DB Storage & Dump Backbone (Phase A)

**Date:** 2026-05-22
**Scope:** ADR-029 (supersedes ADR-024/025/027). Phase A built, tested, merged. Phase B specified + gated.
**PRs:** #217 (Phase A backbone + restore-test + retention + ADR-029 + unifi-syslog move). A follow-up PR adds the vaultwarden dump + filefrag baseline.

---

## TL;DR

A debate about whether `subvol8-db` should be a subvolume turned up two databases (`forgejo-db`, `loki`) with **zero backup**, and a backup convention (ADR-024 dumps) that had been *accepted but never built*. We designed and shipped a complete fix: a **three-tier, recovery-model storage architecture** with an application-consistent **dump backbone** for the six dumpable databases, **weekly restore-tests** that prove the dumps are restorable, observability + alerts, and a documented, gated **offline migration runbook** (Phase B). Loki was deliberately left as Tier 3 (no backup — regenerable). Testing caught ~8 real bugs before they could ever reach a 3am incident.

State now: 6 databases dumped nightly → offsite via Urd; all 6 restore-tested; loki is Tier 3 (no backup); `subvol8-db` cleaned to match its own model; one ADR is the single source of truth.

---

## How this started

The owner asked, essentially: "should `subvol8-db` be a subvolume or a plain NOCOW directory, and how should DB backups work?" Investigating ground truth (not the docs) revealed the docs had drifted from reality:

- **ADR-024** (dump-based backup) — accepted, **never implemented**.
- **ADR-027** (forward-only NOCOW placement) — accepted; put new write-hot engines on `subvol8-db` and *required* DB tenants to be backed up via ADR-024 dumps. Those dumps didn't exist → **`forgejo-db` and `loki` had no backup of any kind** (they live in `subvol8-db`, which is deliberately excluded from Urd snapshots).
- **ADR-025** (migrate the 5 existing DBs to `subvol8-db`) — deferred pending measurements.
- Meanwhile `gathio-db` and `prometheus` carried `chattr +C` (NOCOW) *inside the snapshotted `subvol7`* — the exact "COW defeated by snapshots" antipattern, live.

So the real problem wasn't subvolume-vs-directory; it was a missing backbone and three drifted ADRs.

---

## The architecture (ADR-029)

**Organize storage by *recovery model*, not data type.** Each tier's BTRFS treatment matches how the data is actually recovered:

| Tier | BTRFS | Backup | Members |
|------|-------|--------|---------|
| 1 Snapshot | COW, snapshot, offsite | `btrfs send` | user data, configs, **SQLite, Redis** |
| 2 Dump | **NOCOW, excluded from snapshots** | logical dump → Tier 1 → offsite | PostgreSQL, MariaDB, MongoDB, Prometheus, Loki |
| 3 Discard | NOCOW, excluded | none | *(empty)* |

**The tier boundary = the checksum question.** NOCOW disables BTRFS checksums, so it's only safe for engines that self-checksum (PG `data_checksums`, InnoDB, WiredTiger, TSDB CRC32). SQLite and Redis don't → they stay Tier 1 where BTRFS checksums + snapshot rollback protect them. **Growth rule:** *own checksums + native dump tool? → Tier 2 + dump job; else → Tier 1 with its app.*

Why this is correct, not just tidy: NOCOW only *works* because Tier 2 is excluded from snapshots — no snapshot to share extents, so no copy-on-first-write, so no fragmentation. Live DB files get write-in-place speed; the backup artifact is a tiny, compressed, application-consistent, version-portable dump.

---

## What was built (Phase A)

**`scripts/db-dump.sh`** (nightly `db-dump.timer` @ 01:30, before Urd's 04:00) — per-engine, failure-isolated, idempotent-per-day dumps to `subvol7-containers/db-dumps/<svc>/YYYY-MM-DD.<ext>.zst` (rides Urd offsite automatically):

| Engine | Container | Method |
|--------|-----------|--------|
| Immich PG | postgresql-immich | `pg_dump --format=custom --compress=0` |
| Forgejo PG | forgejo-db | `pg_dump --format=custom --compress=0` |
| Nextcloud | nextcloud-db | `mariadb-dump --single-transaction` as the **app user** |
| Gathio | gathio-db | `mongodump --archive` |
| Prometheus | prometheus | admin-API `tsdb/snapshot` + tar (retention 7) |
| Vaultwarden | vaultwarden | host `sqlite3 .backup` (online) + `PRAGMA integrity_check` |

*(Loki is **not** dumped — Tier 3. See lesson 2.)*

**`scripts/db-restore-test.sh`** (weekly `db-restore-test.timer` @ Sun 05:00) — restores each latest dump into a throwaway matching-version container (or `sqlite3`/archive check) and validates object counts: immich 61 tables, forgejo 128, nextcloud 162, gathio 1 db, prometheus archive integrity, vaultwarden 29 tables. **6/6** (loki excluded — Tier 3).

**Observability:** `data/backup-metrics/db-dumps.prom` + `db-restore-test.prom` (node_exporter textfile) → `config/prometheus/alerts/db-dump-alerts.yml` (`DbDumpFailed`, `DbDumpStale`, `DbDumpJobNotRunning`, `DbRestoreTestFailed`, `DbRestoreTestOverdue`).

**Other:** `--web.enable-admin-api` on `quadlets/prometheus.container`; per-engine retention (`prometheus=7`, default 14); `unifi-syslog` moved `subvol8-db → subvol7` (Tier 1); `scripts/filefrag-baseline.sh` for the Phase B fragmentation measurement; ADR-029 written, ADR-024/025/027 marked Superseded.

After cleanup, **`subvol8-db` holds only its NOCOW DB tenants: `forgejo-db`, `loki`.**

---

## Lessons learned (testing earned its keep)

1. **Prometheus textfile metrics must not use a `service` label.** The node_exporter scrape job sets a static `service="node_exporter"` target label that clobbers it (`honor_labels: false`), collapsing all per-engine series into one. Fix: label = `database`. (Urd uses `subvolume`, dependency-metrics use `homelab_service` — same reason.)
2. **Loki ended up as Tier 3 (no backup) once the freeze cost showed itself.** It's distroless (no shell/tar to exec) with 70k+ rotating files. Rejected in order: stop-rsync-start (~17 min downtime + WAL race, rc=23); host-side tar (permission-denied on mode-600 WAL files + slow, 143 s); live `podman cp` (races on rotation, rc=125 — and containers are *removed* on stop, so cp needs them running/paused). `podman pause` + `cp` looked good in a warm-cache test (~40 s) — but the **first real nightly run froze loki ~15 min (936 s)**: cold-cache seek-bound reads of 70k small files after Prometheus's 1.5 GB dump evicts the page cache (the ~40 s was a fluke). For regenerable log data that trade isn't worth it → loki excluded from backup. *Lesson: measure on a cold cache / in the real pipeline, not in isolation.*
3. **Nextcloud MariaDB `root` is locked down** (no password, no socket auth). Dump uses the app account, which has `ALL` on its own database — the whole instance.
4. **`zstd -f` is required.** A failed run leaves an empty `.tmp` that blocks the next run otherwise.
5. **Vaultwarden was *not* the hard case it looked like.** The deferral assumed a missing in-image `sqlite3` + subuid-owned data. Ground truth: the SQLite is **host-owned (uid 1000, mode 644)** and the **host has `sqlite3`** → a plain online `.backup` works, no sidecar. *Lesson: re-check the assumption before engineering around it.*
6. **PG restore readiness must probe the DATABASE, not `pg_isready`.** `pg_isready` passes when the server accepts connections (~8 s), but the immich/vectorchord image creates `POSTGRES_DB` ~40 s in — restoring too early gave "0 tables." Probe `psql -d $db -c 'SELECT 1'`.
7. **Never `pkill -f 'db-restore-test.sh'`** — the pattern self-matches the running shell's own command line and kills your command (exit 144). Lost a run to this.
8. **`m` (no-compress) and `+C` (NOCOW) are mutually exclusive inodes.** `compression=none` on `subvol8-db` sets `m`, which inherits to children, so a bare `chattr +C` returns EINVAL. Must `chattr -m` then `chattr +C` (relevant to Phase B).

Secondary: secrets stay inside the container (dump runs via `podman exec`; nothing in host `ps` args or the repo — robust to the ADR-028 secret-store path split). The only credential literal anywhere is a throwaway password for the ephemeral `--network none` restore-test containers.

---

## Trade-offs considered

- **Phase A/B split (hybrid).** Ship the additive, low-risk dump backbone now; gate the higher-risk storage migration on measurement + a track record. The adversarial review of the original bundled ADR-023 demanded exactly this.
- **Loki: not backed up (Tier 3).** The measured cost — a ~15 min nightly freeze on a cold cache — outweighed the value of backing up regenerable log data. Owner decision after the first real run; aligns with ADR-027's original stance. (Weekly cadence is the fallback if history ever matters.)
- **Prometheus dump = full 1.5 GB TSDB nightly, no dedup.** Capped local retention at 7 (≈10 GB); offsite growth governed by Urd's subvol7 retention. Future option: dump Prometheus weekly instead of daily. Accepted for now.
- **`--web.enable-admin-api`** exposes destructive TSDB endpoints to the unauthenticated monitoring network. Accepted: external path is Authelia-fronted, only the snapshot endpoint is used, the dump pre-cleans orphaned snapshots. Fallback would be a localhost-only second listener.
- **unifi-syslog → Tier 1 (overrides ADR-027).** ADR-027 deliberately placed it on subvol8-db. The owner chose to move it: append-only forensic logs you want point-in-time recovery for belong in the snapshot tier, the COW cost is negligible for append-only, and snapshot-incrementals are more offsite-efficient than nightly tars.
- **Vaultwarden stays Tier 1 + gets a bonus dump.** It's small, low-write, snapshot-rollback is valuable, and SQLite lacks self-checksums (NOCOW would *remove* its only integrity guarantee). The online `.backup` is an extra application-consistent, offsite, restore-tested copy of the most security-critical store.
- **Per-engine local retention** rather than a single global value — small DBs keep 14, Prometheus keeps 7.

---

## Current state (verified)

- 6 engines dumped (immich, forgejo, nextcloud, gathio, prometheus, vaultwarden); 6/6 restore-tests pass; Prometheus scrapes distinct `database`-labelled series; no db alerts firing. Loki = Tier 3 (no backup).
- Timers armed: `db-dump.timer` (01:30 daily), `db-restore-test.timer` (Sun 05:00).
- `subvol8-db` = `{forgejo-db (Tier 2, dumped), loki (Tier 3, no backup)}`.
- Phase A merged (PR #217, squash, signed). Vaultwarden + filefrag baseline = follow-up PR.
- Logrotate root copy for unifi-syslog's new path installed by the owner.

---

## HAND-OFF: Phase B (for a fresh Claude Code session)

**Goal:** migrate the four databases still in `subvol7` into `subvol8-db` so NOCOW *actually works* (no snapshot defeating it): `postgresql-immich`, `nextcloud-db/data`, `gathio-db`, `prometheus`. **Do NOT touch `forgejo-db` (Tier 2) or `loki` (Tier 3) — both already live in `subvol8-db`; loki is not backed up and not migrated.**

**Read first:** `docs/00-foundation/decisions/2026-05-22-ADR-029-three-tier-db-storage-and-dump-backup.md` (Phase B section is the authoritative runbook) and memory `project_db_storage_architecture`.

### Gate — do not start until all hold
1. **Dumps have a track record** of passing weekly restore-tests (they now exist; let `db-restore-test.timer` run a few Sundays and confirm `db_restore_test_success == 1` for all). The dumps are the migration's rollback safety net.
2. **Measurement justifies it.** Run `sudo bash scripts/filefrag-baseline.sh` and read the latest `data/backup-logs/filefrag-baseline-*.txt`. Per ADR-025/029 criteria, migrate if subvol7 DB files show high/growing extent counts vs the subvol8 reference. If fragmentation is negligible, Phase B can stay deferred indefinitely — that's a legitimate outcome.
3. **The defensive tool exists.** Build `scripts/migrate-db-to-subvol8.sh` (dry-run default, `--execute` gate, `rollback` subcommand) BEFORE migrating. Improvised shell is not acceptable here (this is the riskiest moment in the homelab's storage history).

### The window (the key unlock)
Run `scripts/update-before-reboot.sh` → it calls `graceful-shutdown.sh`, stopping every container cleanly. With the DBs cleanly shut down, the move is a **plain offline `rsync`**, not a live migration — no initdb-in-container, no Prometheus observability-gap choreography. Then `dnf update` + reboot + `post-reboot-verify.sh`.

### Per-service procedure (order small→large: gathio → nextcloud → prometheus → immich)
1. `mkdir` the empty target in `subvol8-db/<svc>/`, then **`chattr -m` then `chattr +C`** (the inherited `m` no-compress flag is mutually exclusive with `+C`; bare `+C` → EINVAL — see Lesson 8).
2. `rsync -aHX --numeric-ids <src>/ <target>/` — **NO `--reflink`, NO `--inplace`** (reflink shares extents and silently defeats NOCOW).
3. Assert `sudo lsattr -d <target>` shows `C` and `sudo filefrag -v <file>` shows no shared extents.
4. **Two-layer ACLs** (ADR-019): parent-traversal `setfacl -m u:<subuid>:--x /mnt/btrfs-pool/subvol8-db` + per-service `setfacl -R -m u:<subuid>:rwx <target>` + default ACL. **Verify each subuid first** via `/etc/subuid` + `podman inspect` — they differ: immich/nextcloud/gathio PG-family ≈ 100998, prometheus = 165533, and note forgejo-db is 100069 (different base) though it isn't migrating.
5. Edit the quadlet `Volume=` → new path; `systemctl --user daemon-reload`; start; healthcheck.
6. **Verify the secret still mounts** (ADR-028 lesson — a storage move once broke secret resolution silently): `podman run --rm --secret <name> alpine true`.
7. **PostgreSQL only:** `pg_controldata | grep -i checksum` first (the quadlet sets `--data-checksums`, so likely already on → skip). Only if off, `pg_checksums --enable` in place (safe because cleanly stopped).
8. Keep the source as `<svc>.pre-migration-<DATE>` for 14 days. **Rollback** = revert the quadlet `Volume=`, daemon-reload, restart; worst case restore from the prior night's dump.

### After migration
- Re-run `scripts/filefrag-baseline.sh` for the before/after fragmentation delta (the brag).
- Confirm the dump job still works against the new paths (it reads via `podman exec`/`podman cp`, so paths don't matter to it — but verify).
- Update ADR-029 status (Phase B done) + the tenant table; write a follow-up journal.
- Partial migration is acceptable; forced completion is not. If one service can't migrate cleanly, leave it in subvol7 and stop.

### Gotchas a fresh session must not relearn
- Containers are **removed** on `systemctl --user stop` (quadlet) — `podman cp`/`exec` need them running or paused.
- Don't `pkill -f` with a pattern matching your own command line.
- The dump metrics label is `database`, not `service`.
- Everything DB-related is documented in **ADR-029**; don't re-derive from the superseded ADR-024/025/027.

---

## Open / deferred (not blocking)
- Phase B (above) — gated.
- Optionally switch Prometheus to a weekly dump if the 1.5 GB/night offsite growth becomes a concern.
- `data/backup-metrics/*.prom` for vaultwarden/restore-test populate fully on the next scheduled timer runs.
