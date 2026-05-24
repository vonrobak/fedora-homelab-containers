# Restore-test incident: a tmpfs blowout that uncovered a dead DR control

**Date:** 2026-05-24
**Context:** The monthly disaster-recovery restore-test (`scripts/test-backup-restore.sh`)
exhausted the `/tmp` tmpfs during its 2026-05-24 run and left ~13 GB behind. I was asked to
look into it. An incident report written from the *urd* repo
(`docs/99-reports/2026-05-24-incident-restore-test-tmpfs-exhaustion.md`) had already
diagnosed the tmpfs side and listed open items. This journal is the homelab-side resolution
— and the story of how the reported symptom turned out to be the smaller half of the bug.

Landed across PR #225 (`0fc0f5c`, the fix), this journal (#226), and a follow-up — PR #227
(`3989dff`) — that resolved a snapshot-*selection* bug surfaced by this journal's own Next
Steps (see "Follow-up" below). Self-contained; read it cold.

---

## The tool, in one paragraph

`test-backup-restore.sh` runs on the last Sunday of each month
(`backup-restore-test.timer`). For each of six BTRFS subvolumes it finds the latest local
snapshot, picks 50 random files, copies them to a scratch dir, and `cmp`s them byte-for-byte
against the live source — proving the backups are *restorable*, not merely present. It then
writes a text/JSON report and a Prometheus textfile metric (`backup_restore_test_*`) that
`config/prometheus/alerts/backup-alerts.yml` alerts on. It is the only automated answer to
"are my backups actually recoverable?"

## What actually happened

The reported failure: scratch was `/tmp` (a 16 GB RAM-backed tmpfs with a per-user quota),
sampling was 50 files *by count* regardless of size, and `subvol3-opptak` holds single media
files of 45–76 GB. Fifty random files there blew past tmpfs, `cp` hit ENOSPC, the run FAILed,
and cleanup ran *only on success* — so the failed run's ~13 GB was the one thing kept. Real,
but a nuisance.

The real finding came from one question the incident report couldn't answer from outside:
**did the failure alert fire?** It couldn't have — because the metric file did not exist.
Tracing that: the script's journal ends at `Generating Reports` and nothing after; no `.json`,
no `.prom`. The script was dying *inside* `generate_test_report()`, before
`export_prometheus_metrics()`. The cause was a `set -e` landmine:

```bash
local total=0
for result in "${TEST_RESULTS[@]}"; do
    ((total++))    # post-increment evaluates to the OLD value (0) → (( )) returns exit 1
                   # → under `set -e`, the script aborts here, every single run
```

I reproduced it in isolation (`bash -c 'set -e; t=0; ((t++)); echo nope'` exits 1 without
printing), and confirmed the **previous month's** log (2026-04-26) — a month where the
restore validation actually *passed* 50/50 — truncated at the identical point. So the metric
had **never** been emitted; the `backup_restore_test_*` series never existed in Prometheus;
and both alerts in `backup-alerts.yml` (a *critical* `==0` and a 35-day staleness warning)
had no series to match and were silently dead. The script also exited `status=1/FAILURE`
every month, but `OnFailure` was commented out, so nothing was ever said.

**Net: the monthly DR restore-test had been a blind, self-reporting-as-failed control since
at least April. The tmpfs blowout is simply what finally made a human look.**

## The open items, resolved by evidence

- **No corruption.** Zero checksum mismatches in the failed run; all 46 errors were ENOSPC
  copy failures.
- **The SKIPs were false.** The three subvolumes that reported `SKIP (0 files)` each have
  100+ files in their latest snapshot. They were skipped because the tool couldn't write its
  `mktemp` file-list to the full tmpfs, and a 0-count list was treated as "benign empty."
- **The alert wasn't missing — its producer was.** The incident report's "failures are
  silent, wire `OnFailure=email-…`" had the right symptom and the wrong fix. The
  Prometheus → Alertmanager → discord rail already existed; `email-notification@` never did.

## What was done (the fix)

All in `scripts/test-backup-restore.sh`, verified on throwaway runs before touching anything
scheduled:

- **Metric crash (the root cause):** converted all six `((var++))` sites to
  `var=$((var+1))`. The script now reaches metric export on every path.
- **Scratch off tmpfs:** `RESTORE_TEST_DIR` → `/mnt/btrfs-pool/subvol6-tmp/restore-tests`
  (the pool's designated scratch subvolume, ~2.9 TB), and `export TMPDIR` to the same place
  so `mktemp`/`shuf` temp files leave tmpfs too.
- **Size-aware sampling:** skip files > 256 MiB and stop a subvolume after 2 GiB copied. A
  multi-GB media file exercises the *same* `cp`+`cmp` on the *same* BTRFS read path as a small
  one — it adds no restore assurance, only byte volume.
- **Unconditional cleanup:** a single `trap … EXIT` removes the scratch root on every exit,
  success or failure. The failed run no longer leaks; only the log and metrics persist.
- **Honest outcomes:** a preflight free-space guard, and an explicit "has files but none
  testable → FAIL" distinct from "snapshot genuinely empty → SKIP."
- **Provenance:** `get_latest_snapshot()` set its `source` inside a command-substitution
  subshell (lost in the parent → every report row said `Source: unknown`); now returned via
  stdout.
- **Doc fix:** the service unit's misleading commented `OnFailure=email-…` replaced with a
  note describing the real Prometheus rail, so no one re-adds a dead path.

**Verification (full suite):** 6/6 PASS, all metrics emitted, `Source: local`, **peak scratch
332 MiB** (was 13 GB), `/tmp` untouched, scratch auto-cleaned. The 13 GB leftover was deleted
(btrfs confirmed the reclaim: 76.4 GiB used / 34.8 GiB free).

---

## Follow-up: a manual "fix" that only moved the target (PR #227)

This journal's Next Steps flagged that `subvol3-opptak`'s latest *local* snapshot looked 63
days old (2026-03-22) — a possible backup gap. It wasn't: the record was healthy, and
`20260322-opptak` was just a redundant old snapshot, which was deleted. But deleting it didn't
resolve the symptom — it *shifted* it: the next run then validated `20260329`, the new oldest.

The real cause was in `get_latest_snapshot()`: it chose the snapshot to test with
`ls -1td | head -1` — sorted by **mtime**. BTRFS read-only snapshots inherit the source
subvolume's root-dir mtime, so for any subvol whose root dir isn't touched between snapshots,
**every snapshot shares one identical mtime**; `ls -t`'s tie-break then deterministically
returns the alphabetically-first name = the **oldest** snapshot. A fleet-wide check found
**7 of 9 subvolumes were silently validating a stale snapshot** (opptak tested `20260329`
while `20260524` existed; htpc-home/-root tested `20260514`).

So the restore-test had been proving an *old* backup restorable, not the current one — and the
">30 days old" staleness warning was watching the wrong snapshot, so it couldn't flag a real
freshness gap either. Fix (PR #227): select by the date in the snapshot **name**
(`YYYYMMDD[-HHMM]` sorts lexically == chronologically) via `ls -1d | sort -r | head -1`, at all
three selection sites. Verified: a full run now selects each subvolume's latest snapshot
(`Using snapshot:` cross-checked against latest-by-name — all six ✓). The backups themselves
were healthy throughout; only the *selection* was wrong.

---

## Lessons learned

1. **The reported symptom was the surface, not the cause.** "Restore-test fills /tmp" was
   true and fixable, but it hid a worse, invisible failure. The thing that cracked it open was
   asking a question the symptom didn't prompt: *given it failed, did anyone get told?* When an
   incident hands you a tidy cause, walk the **whole** causal chain to the detection edge — the
   "was this even noticed?" link is where dead controls hide.

2. **A control that silently fails is worse than no control.** No restore-test would at least
   be a known gap. A restore-test that exits FAILURE every month while emitting no metric and
   raising no alert produces *false confidence* — the most expensive kind. The lesson is
   concrete: an alert is not "wired" until you've seen it fire against a real failing or
   *missing* input. These two alerts were syntactically perfect and had been inert for months.
   Verify the watcher has data, not just rules.

3. **The cheapest forensic was the highest-leverage.** Reading a truncated log and running one
   `bash -c` reproduction reframed the entire incident — from "size the tmpfs / cap the
   sample" to "the metric has never existed." That cost about two minutes and was worth more
   than any amount of fix-writing would have been against the wrong problem. Spend the one
   command that tests the premise before building on it.

4. **`set -e` + `((var++))` is a mid-script landmine, and the danger is the *partial* run.**
   It's a known footgun, but its real teeth here weren't "the script crashes" — they were
   "the script crashes *after* doing the visible work and *before* the side-effect that
   matters" (metric export). A job can look like it ran, produce a partial report, and still
   never reach its tail. When auditing the many `set -e` bash scripts in this repo, grep for
   `((…++))` and ask what lives downstream of it.

5. **An external report is a hypothesis, not a work order.** The urd-side report was an
   excellent diagnosis of everything visible from outside the homelab — and it confidently
   prescribed a fix (`OnFailure` email) for a rail that already existed and a producer that was
   actually broken. Re-verifying its framing from *inside* the system changed the fix entirely.
   Trust a report's facts; re-test its conclusions before acting.

6. **On BTRFS, `df` lies about reclaimed space.** After deleting the 13 GB, `df -h` still read
   23 G free; `btrfs filesystem usage` correctly read 34.8 GiB free. On a copy-on-write
   filesystem with snapshots, `btrfs fi usage` is the source of truth, and a deletion can stay
   "used" if a snapshot pins it. Don't claim a reclaim from `df` alone.

7. **"Couldn't verify" is not "verified nothing to do."** The false SKIP — degrading silently
   to "skipped" under resource pressure instead of "could not test" — is the same failure
   class as the dead metric: a tool quietly reporting a non-result as an acceptable one. The
   fix made the distinction loud. Any check that can be *prevented* from running must say so
   differently from a check that ran and found nothing.

8. **Deleting the symptom can just move the target — chase the mechanism.** The 63-day-old
   snapshot wasn't a backup gap; removing it didn't fix anything, it shifted the test onto the
   next-oldest snapshot. The bug was the *selection rule* (mtime sort on snapshots that all
   share an mtime), not any single snapshot. When a manual cleanup appears to "resolve" an
   anomaly, confirm *why* — a deterministic wrong-selection will silently re-acquire a new
   wrong target. (Also: on BTRFS, "latest snapshot" means latest by the date in the name, never
   by mtime — see lesson 6's cousin.)

## Next steps

- ~~**Adjacent finding to chase:** `subvol3-opptak`'s latest local snapshot looked 63 days
  old.~~ **RESOLVED** — false alarm (healthy record; one redundant old snapshot, since
  deleted), but chasing it uncovered the mtime-selection bug fixed in **PR #227** (see
  Follow-up). Backups are healthy.
- The first real green monthly run is **2026-06-28** — confirm it PASSes and that the
  `backup_restore_test_success` series now appears in Prometheus and the alerts evaluate.
- Optional consistency: point `db-restore-test.sh`'s sqlite scratch (`mktemp`) at the same
  disk-backed dir; low risk today (only the small vaultwarden dump decompresses to `/tmp`).
- Optional: a one-line note in `docs/20-operations/guides/disaster-recovery.md` recording that
  DR scratch lives on `subvol6-tmp`.
