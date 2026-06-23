# The planned reboot that proved last week's inference: graceful-shutdown's hardcoded fleet skipped a database

**Date:** 2026-06-23
**Status:** #307 + #308 merged (PR #312, merge commit `6e96da8`; substance `edd0465`, `8a981bc`). #308 applied (Prometheus restarted, snapshot live). Follow-ups filed: #306, #309, #310, #311. Lesson **L-079** recorded.
**Origin:** First full post-ADR-036 cycle executed for real — `monthly-update.sh` (adopted 9 images, PR #305) → `prepare-for-reboot.sh` → `sudo dnf update -y` → reboot. The owner opened a session just after boot to: verify the updates, evaluate whether `prepare-for-reboot.sh` is still necessary in its current form, check the container boot sequencing, look at a slow Prometheus startup, and explain an unexplained password+YubiKey prompt he had denied.

This is the **empirical reboot test** the 2026-06-22 journal (Lesson 3) said was "the one way to convert inference into fact — worth doing on the next planned reboot." It did, and the inference was wrong in a way that mattered.

---

## What shipped

| Package | PR/Issue | Content |
|---|---|---|
| Dynamic graceful-shutdown fleet | #307 (PR #312, `edd0465`) | `graceful-shutdown.sh` now derives the stop set at runtime from `quadlets/*.container` and classifies by name pattern into the same 6 tiers, replacing the hardcoded `PHASES` array. First-match-wins keeps exporters in Supporting (`postgres-exporter` → tier 1, not the DB tier). Post-run guard fails loudly if any container survives. `--dry-run` verified all 37 services covered, `forgejo-db` now in Data. |
| Prometheus memory-snapshot | #308 (PR #312, `8a981bc`) | `--enable-feature=memory-snapshot-on-shutdown` added to the quadlet. Applied: daemon-reload + restart. |
| Follow-ups filed (not fixed) | #306, #309, #310, #311 | forgejo-mirror post-reboot keyring failure; post-reboot-verify failed-unit blind spot; prepare-for-reboot phase-3/4 redundancy; udisks2 SEGV. |
| Distilled lesson | L-079 | "Derive fleet service lists at runtime; hardcoded lists silently drift." |

The updates themselves were clean: 37/37 containers healthy, `needsDbUpgrade:false`, kernel `7.0.12-201`, `needs-restarting -r` clear. `post-reboot-verify.sh` reported ALL PASSED — see Finding 4 for why that was partly a false green.

## Finding 1 — the inference was wrong: graceful-shutdown skipped `forgejo-db`, and it fell to the reboot transition

Last week I downgraded graceful-shutdown from "load-bearing" to "asymmetric tail-risk insurance," reasoning that systemd's `After=`/`Requires=` already order the stop and the only real risk is the `user@` 60s stop budget. The reboot logs showed a **third failure mode I'd missed: the script's hardcoded fleet list had drifted, so it never stopped `forgejo-db` (PostgreSQL) at all.**

Timeline (pre-reboot boot, CEST):
- ~16:24 — graceful phase quiesced the *listed* DBs cleanly (`nextcloud-db` "Shutdown complete", `postgresql-immich` fast-shutdown, `gathio-db` "mongod shutdown complete exitCode:0").
- 16:33:53–57 — `forgejo-db` was still running and got stopped by the **systemd reboot transition** instead, emitting `pasta` netns + `aardvark-dns` "destructive transaction" errors, a failed `veth` delete, and `forgejo-db.service: ... status=125`.

PostgreSQL did log a clean `database system is shut down` at 16:33:54, so **nothing corrupted this cycle** — but only because PG flushed inside systemd's budget. The deliberate "quiesce the DB while the host is still up" guarantee was simply *not delivered* for a database, silently. The static `PHASES` array (last meaningfully edited before Forgejo existed) omitted **9 running services**: `forgejo`, `forgejo-db`, `unifi-syslog`, `proton-bridge`, and 5 exporters. `adopt-baked.sh` knew about forgejo (it had just adopted it hours earlier); the shutdown script didn't. This exact loose end was even flagged in #304 ("graceful-shutdown.sh hard-coded fleet") — it was a known smell that turned out to have teeth.

**Verdict on "is prepare-for-reboot.sh necessary in its current form?"** The graceful-shutdown phase *is* necessary — but it was only *appearing* to do its job. Now that membership is derived from quadlets it actually covers every DB, including ones added later. The manifest phase (feeds `post-reboot-verify.sh`) stays valuable. The image phases (3/4) are near-redundant when run right after `adopt-baked.sh`, and Phase 4's prune mildly undercuts the ADR-030 local-rollback fast-path — split out as #310, not fixed here.

## Finding 2 — fix the class of bug, not the instance: discover, don't enumerate

The instinct-level fix was "add forgejo-db to the array." That just resets the drift clock. The real fix is to stop maintaining a parallel notion of "the fleet": enumerate `quadlets/*.container` (the systemd source of truth, confirmed 1:1 with running container names), classify by role, and **fail loudly via a post-run `podman ps` guard** if anything survives — which also catches non-quadlet orphans the discovery can't see. Resisting a second hardcoded helper (an `is_known_app` list) during implementation was deliberate; the roster print + end-guard give visibility without re-introducing the very anti-pattern. Generalized as L-079.

## Finding 3 — graceful shutdown does not avoid Prometheus WAL replay; the memory snapshot does

Prometheus shut down cleanly pre-reboot ("See you next time!" 16:24:14) yet still spent **16.1s replaying the WAL** on boot (`chunk_snapshot_load_duration=0s`). Graceful shutdown only avoids *corruption repair*, not replay — a distinction worth remembering. The lever is `--enable-feature=memory-snapshot-on-shutdown`: on a clean SIGTERM it writes a head-chunk snapshot and loads that instead of replaying. It's well-aligned because the quadlet's own comment cites "~20s of WAL-replay reads on subvol8-db" as the reason Prometheus sits in boot tier C (ADR-035) — so this attacks the exact I/O that justified the demotion.

Applied and confirmed live: log now says *"memory snapshot on shutdown enabled"*, loads a snapshot in **186µs**, and WAL replay dropped to **1.48s**. (Bigger picture: the ~5.5 min from boot to Prometheus *starting* is the deliberate tier ordering and storm-avoidance trade-off — left untouched. Loki at ~14 min, not Prometheus, is the real boot long-pole.)

## Finding 4 — the unexplained YubiKey prompt was the mirror, and the verifier hid the failure

The password+touch prompt the owner denied was `forgejo-mirror.service`: it pushes to the local Forgejo over SSH using the FIDO signing key via the `gcr` agent. It had run **unattended every hour for 18 hours** (keyring already unlocked), then failed only on the **first run after boot** (16:46:58, the same second `gcr-ssh-agent` restarted) because a tty2 console login doesn't auto-unlock gnome-keyring. Benign — but it then failed every hour after (denying left the keyring locked). Two structural points:
- Using the *commit-signing* FIDO key for *localhost transport auth* couples an unattended timer to an interactive hardware-presence path. A dedicated passphraseless deploy key for `git@127.0.0.1` is the durable fix (#306).
- `post-reboot-verify.sh` reported **ALL CHECKS PASSED** while three units were failed (`forgejo-mirror`, `podman-user-wait-network-online`, `udisks2`). It checks a curated list, never `systemctl --user --failed` — a verifier that can go green with failed units present (#309). Same "curated list drifts" family as L-079.

Incidental: committing #307/#308 (FIDO-signed) unlocked the keyring, so the mirror is now clearable with a manual start; #306 stays open for the durable fix.

## Finding 5 — boot tiering worked; one host-service casualty

No I/O exhaustion storm this reboot — ADR-035 tiering held (crowdsec→traefik→…→prometheus 16:39→…→loki 16:48, deliberately last). The one non-container casualty: `udisks2.service` **SEGV core-dumped** at 16:39:58 (2 GB peak) in the openssl `legacy.so` / libblockdev-SMART / libnvme path, right after `dnf` bumped openssl to 3.5.7. Host service, socket-reactivates; but given `sdc` is the aging weak drive, it's worth a backtrace before assuming it's just a package regression (#311).

## Loose ends
- **#306** — forgejo-mirror durable fix (dedicated localhost deploy key) + distinguish auth-vs-unreachable error string. Mirror is currently failed; clearable now that the keyring is unlocked.
- **#309** — `post-reboot-verify.sh` must scan `--failed`; allowlist known-benign units explicitly.
- **#310** — `prepare-for-reboot.sh` phase-3 redundancy + phase-4 prune-vs-rollback + the `monthly-update.sh` double-invocation footgun.
- **#311** — `udisks2` SEGV backtrace; rule in/out the openssl-3.5.7 path vs `sdc`.
- The 2026-06-22 Lesson-3 empirical test is now **done** — and it changed the answer: graceful-shutdown was not merely insurance, it was quietly under-covering a DB. Worth re-running the "reboot without graceful-shutdown" comparison only if we ever want to retire it again.
