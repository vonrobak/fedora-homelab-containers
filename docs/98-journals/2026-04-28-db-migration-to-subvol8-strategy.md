# Database Migration to subvol8-db — Long-Term Strategy

**Date:** 2026-04-28
**Status:** Planning. Captures intent, not yet a binding ADR.
**Trigger:** During T3.2 (Loki → subvol8-db) we discovered that `chattr +C` on subvol8-db actually works once the inherited `m` (no-compress) flag is dropped first. ADR-027 had recorded "EINVAL on kernel 6.19, reasons not yet traced" and accepted the limitation; that limitation is now lifted. The path is open to migrate the homelab's existing databases off the snapshotted `subvol7-containers` and onto the dedicated, NOCOW-capable `subvol8-db` — which is what ADR-025 deferred to a 2026-06-18 measurement review.
**Companion ADRs:** ADR-024 (dump-based backup), ADR-025 (deferred DB migration), ADR-027 (forward-only NOCOW placement on subvol8-db).

---

## Why this is worth doing carefully, not quickly

These are the homelab's most important persistent stores. A botched migration loses real user data — Nextcloud files, Immich photos, password history, event invitations — that is not reconstructible from logs or replay. The reward (better fragmentation behavior + escape from snapshot extent-pinning) is real but bounded; the cost of a mistake is high and highly visible. There's no operational pressure forcing this — current databases work, just sub-optimally on COW + snapshots. So this is explicitly **a careful, measured, multi-month workstream**, not a sprint.

Best practices that follow from this:
- **One database at a time.** No batched migrations. Each gets its own PR, its own validation window, its own rollback decision.
- **Dump-based migration where the engine supports it.** `mariadb-dump`, `pg_dump`, `mongodump` produce logically-consistent backups that can be restored to any version-compatible target. Filesystem-level `rsync` is a fallback only when (a) the engine has no dump format that captures all state, or (b) the data volume makes dump+restore wall-time prohibitive.
- **Service stop is required.** Live `rsync` of an active DB is wrong; the WAL/transaction log moves while you copy. Best practice is a clean shutdown, dump or rsync, restore, start, validate.
- **Old data path stays in place** for ≥7 days post-migration as a rollback artifact.
- **Application-level smoke test** before declaring success. "DB starts" is necessary, not sufficient. Need to actually use the application end-to-end (upload a file to Nextcloud, view a photo in Immich, decrypt a password in Vaultwarden) before considering a migration complete.

---

## Inventory of candidates

After today's Loki migration, the following candidates remain on `subvol7-containers`. The "NOCOW today" column reflects whether the existing directory has `+C` set (per `lsattr -d`) — a "No" means COW writes have been happening since the directory was first created, and the database is paying full fragmentation cost on the existing path.

| Service | Engine | Current path on subvol7 | NOCOW today | Snapshotted | User-data sensitivity | Migration approach |
|---|---|---|---|---|---|---|
| `prometheus` | TSDB | `subvol7-containers/prometheus` | **Yes** (`+C`) | Yes | Low — TSDB rebuilds from scrape; 30-day retention is recovery-cheap | rsync (engine-level dump not standard) |
| `gathio-db` | MongoDB | `subvol7-containers/gathio-db` | **Yes** (`+C`) | Yes | Medium — event invitations & RSVPs, no replay source | `mongodump` + restore |
| `nextcloud-db` | MariaDB 11 | `subvol7-containers/nextcloud-db/data` | **No** | Yes | High — file metadata, share links, user accounts | `mariadb-dump` + restore |
| `nextcloud-redis` | Redis 7 | `subvol7-containers/nextcloud-redis/data` | n/a (cache, RDB whole-file rewrite) | Yes | Low — session cache, regenerable | **Stays** on subvol7 per ADR-027 ("whole-file rewrites" exclusion) |
| `immich-postgres` | Postgres 16 + vectorchord | `subvol7-containers/immich/postgres` | **Yes** (`+C`) | Yes | High — photo metadata, ML embeddings, ~10K assets | `pg_dump` + restore (vectorchord version-pinned per ADR-015) |
| `immich-redis` | Redis | (verify) | n/a | Yes | Low | **Stays** on subvol7 |
| `home-assistant` | SQLite | `subvol7-containers/home-assistant/home-assistant_v2.db` | (verify) | Yes | Medium — automation history, sensor data | Stop, file-copy, start (SQLite is small-file) |
| `authelia-redis` | Redis | (verify) | n/a | Yes | Low — session cache | **Stays** on subvol7 |

**Loki** (already on subvol8-db post-2026-04-28): not listed above. Already migrated.

**Discovered defects worth flagging:**
- `nextcloud-db` directory has **no `+C` flag** despite being a MariaDB instance with InnoDB random-write patterns. The CLAUDE.md gotcha "Loki/PostgreSQL/Prometheus need `chattr +C` before first use" was not enforced for MariaDB at first deploy. Cannot retrofit with `chattr +C` on a populated directory (no-op on existing extents). The migration to subvol8-db is the natural fix — restore lands in a fresh dir that inherits `+C`.

---

## Migration order (risk-graduated)

The first migration is the riskiest because it's the first time we're exercising the full procedure on a real DB. Pick the lowest-stakes service to learn on:

### Phase 1 — Pilot: `prometheus`

**Why first:** TSDB data is reconstructible from active scrapes. If the migration corrupts data, we lose at most 30 days of historical metrics — recoverable, non-personal, no user-visible regression. Also: rsync rather than dump-based, which exercises the simpler half of the procedure first.

**Procedure:**
1. Stop `prometheus.service` cleanly (sends SIGTERM; Prometheus flushes head block to disk on shutdown).
2. Create `/mnt/btrfs-pool/subvol8-db/prometheus`, drop `m`, set `+C`, verify with `lsattr -d`.
3. `rsync -aAXH --info=progress2` from old to new.
4. Update `quadlets/prometheus.container` `Volume=` line.
5. `daemon-reload`, start, verify scrape resumes (check `up` metric for self-scrape).
6. Application smoke test: a Grafana dashboard panel renders correctly with data spanning the migration window.
7. Old path stays in place for ≥7 days. New path's first daily compaction (after ~2h) writes new files into the `+C` directory — verify via `lsattr` on a chunk file.

**Acceptance:** zero data gap visible in any retention-window dashboard, zero scrape errors, fragmentation visibly lower on next `filefrag` check (forward-looking; baseline today is unmeasured but should be measured pre-migration).

### Phase 2 — `gathio-db` (MongoDB)

**Why second:** dump-based engine with stable backup format, but a relatively simple schema and small data volume. Validates the dump-restore half of the procedure on something low-stakes.

**Procedure:**
1. `podman exec gathio-mongo mongodump --out /tmp/dump` (with auth flags from secret).
2. Stop `gathio-mongo.service`.
3. Create new path on subvol8-db, set `+C`, update quadlet `Volume=`.
4. Start, then `mongorestore` the dump.
5. Application smoke test: view event list at `gathio.patriark.org`, RSVP a test event end-to-end.

**Acceptance:** all pre-existing events visible with attendees intact, RSVP flow works, no auth errors.

### Phase 3 — `home-assistant` (SQLite)

**Why third:** simple single-file DB; gives us a reference for how SQLite behaves on subvol8-db before we attempt the larger relational engines.

**Procedure:** stop HA, copy the .db file, update quadlet `Volume=` (only the data subdir), start. Validate via Lovelace dashboard rendering recent sensor history.

### Phase 4 — `nextcloud-db` (MariaDB)

**Why fourth:** the highest-value migration in personal terms (file metadata, share links, user accounts), and the one with no current `+C`. This is also where `mariadb-dump` workflow gets a real test.

**Procedure:**
1. Pre-flight: trigger a Nextcloud OCC `db:add-missing-indices` and `db:convert-filecache-bigint` to ensure schema is healthy.
2. Stop `nextcloud.service` first (clients see read-only mode briefly), then `nextcloud-db.service`.
3. From a temporary mariadb container with the same image version, mount old data path read-only, dump to file: `mariadb-dump --all-databases --single-transaction --routines --triggers > nextcloud-full.sql`. (Single-transaction guarantees consistency on InnoDB; routines/triggers cover stored procedures Nextcloud may install.)
4. Create fresh `/mnt/btrfs-pool/subvol8-db/nextcloud-db/data`, set `+C`, set ownership to MariaDB's container UID.
5. Update quadlet `Volume=`, start `nextcloud-db.service`. Wait for `mysqld` to initialize empty data dir.
6. Restore: `mariadb < nextcloud-full.sql`.
7. Start `nextcloud.service`, wait for healthcheck (`needsDbUpgrade:false`).
8. Application smoke test:
   - Login as admin via web UI
   - Browse to a known directory and verify file listing matches pre-migration
   - Open a calendar event (CalDAV)
   - Trigger a desktop client sync and verify zero-conflict completion
9. Run `occ files:scan --all` to verify file index integrity against actual files on disk.

**Acceptance:** all pre-existing files accessible to all users, share links resolve, calendar/contacts intact, mobile clients sync without re-prompting credentials.

**Rollback discipline:** if any acceptance criterion fails, the rollback path is straightforward — the old `subvol7-containers/nextcloud-db/data` is untouched; flip the quadlet `Volume=` line back, restart. The dump file is the artifact you fall back FROM if the new path is corrupt; the old data dir is what you fall back TO if the dump-restore was flawed.

### Phase 5 — `immich-postgres`

**Why last:** highest complexity. vectorchord extension is version-pinned per ADR-015, ML embeddings are large, photo metadata is irreplaceable in the sense that re-derivation from raw files would lose user actions (album organization, tags, favorites).

**Procedure:** broadly mirrors phase 4 with `pg_dump --format=custom` instead of `mariadb-dump`. Critical version match: postgres-vectorchord image at the exact pinned tag (no upgrade jumps during migration). Validate vectorchord index integrity post-restore by triggering a smart-search query.

**Pre-condition:** phase 4 must be fully clean (≥14 days post-migration with no rollback) before starting phase 5. We're not running two high-stakes migrations simultaneously.

---

## What stays on subvol7 deliberately

Per ADR-027's exclusion criteria:

- Redis instances (whole-file RDB snapshots, not random-write patterns)
- Container config directories (snapshot-based rollback genuinely valuable)
- Caches and ephemeral state

These are correct on subvol7-containers and should not be migrated.

---

## Per-migration checklist (template)

For each phase, the executing PR/journal must answer:

- [ ] Pre-migration data size measured (`du -sh`)
- [ ] Pre-migration fragmentation measured (`filefrag` on a representative file) — gives us a quantitative before/after
- [ ] Service successfully stopped and verified inactive (no zombie process)
- [ ] New path created with `chattr -m && chattr +C`, verified by `lsattr -d`
- [ ] Dump or rsync completed with byte/row count verification
- [ ] Fresh start succeeds, healthcheck passes
- [ ] Application-level smoke test executed and documented
- [ ] Old path retained for ≥7 days as rollback artifact
- [ ] `lsattr` on a newly-written file confirms `+C` inherited
- [ ] Post-migration fragmentation measured (compare to baseline)
- [ ] Tenant table in ADR-027 updated with new row

The post-migration `filefrag` measurement is the empirical signal that the whole exercise was worth doing. If extents are still fragmenting on subvol8-db (somehow), we've learned something important; if they hold flat, ADR-025's hypothesis is validated.

---

## Calendar and gating

- **2026-05-28 (~1 month)**: phase 1 (`prometheus`) candidate window. Earliest. Only after the Nextcloud burst-rate-limit soak (T2.2) finishes cleanly on 2026-05-05 and a few weeks of stable operation are observed.
- **+30 days per phase**: phase N+1 may start 30 days after phase N succeeds without rollback. This is a soft gate — adjust based on real observations.
- **2026-06-18 ADR-025 review**: this strategy supersedes ADR-025's "wait until 2026-06-18 to decide" framing with a "we have a plan, executing it" framing. ADR-025 should be updated (or marked superseded) on or before that date to reflect the new posture.

There is no deadline. If a phase reveals a structural problem (e.g., fragmentation doesn't actually improve on subvol8-db), the strategy halts and we re-evaluate before continuing.

---

## What this document is not

- Not a binding ADR. It's a planning record. Each phase will produce its own PR, its own journal, and either succeed or get rolled back. ADR-025 owns the architectural decision; this owns the execution plan.
- Not a guarantee that all five phases will happen. If midway through we conclude the cost-benefit doesn't justify continuing (e.g., subvol8-db's NOCOW behavior turns out to be marginally better only), we stop and document why.
- Not exhaustive. CrowdSec's local DB, Authelia's session store, and other minor stateful surfaces are not enumerated above; they are evaluated against ADR-027's criteria when their migration becomes interesting (or not).

## What's open for the next session

- Decide whether this should become a new ADR (e.g. ADR-029) or remain a planning journal that updates ADR-025 in-place. Recommendation: leave as planning journal until phase 1 is complete; convert to ADR-029 after the first migration validates the procedure.
- Run baseline fragmentation measurement on all candidate services so phase 1 has something to compare against. ~10 min: `for d in prometheus nextcloud-db immich/postgres ...; do sudo filefrag -v /path/to/largest-file | tail -1; done`.
- Confirm `+C` status on the directories listed as "(verify)" above.
