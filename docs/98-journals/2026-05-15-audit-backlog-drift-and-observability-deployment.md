# Audit-Backlog Drift, Scratch-Image Healthchecks, and the Inode Trap

**Date:** 2026-05-15
**PRs:** #189 (closed #148), #190 + #191 (closed #150)
**Closes:** #186 (verification done, no PR), #148 (Authelia dead rule), #149 (already solved manually), #150 (redis/postgres exporters + dashboards)
**Opens:** #188 (tracker for upstream ABS PR #5004)
**Context:** Backlog day. The 2026-04-17 config-review milestone still had four open issues. Worked them in numeric order — turned out the ordering matched difficulty closely enough that the easy wins primed the chunky one at the end.

---

## What shipped

| Issue | Outcome | Why interesting |
|-------|---------|-----------------|
| #186 | Closed (no code). Opened #188 to track upstream PR #5004. | The forensics post from #185 got maintainer engagement; the workaround revert has a home. |
| #148 | PR #189 merged. One dead Authelia rule removed; explanatory comment added. | 3-line diff. Cleanest issue in the queue. |
| #149 | Closed (no code). | The premise was stale — already solved via GNOME settings. |
| #150 | PRs #190 (exporters) + #191 (dashboards) merged. | The chunky one. Three new containers, a new Postgres role, two patched community dashboards. |

Net: four issues off the milestone, three of them with no surprises in the *implementation* — all the surprises were upstream of writing code.

---

## The recurring lesson: verify the premise, not the steps

Three of the four issues had drifted between filing (2026-04-17) and execution (2026-05-14):

**#149 was already solved.** The issue body opened with `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` returning `powersave` and proposed a 2-week measurement-then-A/B. Same command today returns `performance`. tuned is running `throughput-performance`, persists across reboot, and was switched on by the user via GNOME's Performance toggle some time in April. The remediation plan was meaningless; the right action was a closing comment.

**#148's verification command was for the wrong domain.** Body said `curl -I https://home.patriark.org/` and "expect 401 from HA itself." But `home.patriark.org` is the Homepage dashboard (under Authelia); HA is at `ha.patriark.org`. The issue's evidence section was correct — only the verification curl drifted. Caught it by reading routers.yml at lines 18 and 230 instead of trusting the issue text.

**#150's cross-reference was stale.** "Related: #154 (power-profiles-daemon) — handle together." Actual #154 is about nextcloud-redis password-in-argv. No relation. Either the issue numbering shifted between drafting and filing, or someone repurposed #154.

**#186's checklist didn't anticipate upstream PR #5004.** The checklist branched on "upstream fix merged" vs "no upstream fix" — but the world has a third state: "fix is open, mergeable, and being actively maintained by a contributor who already engaged with our forensics post." That state belongs in a long-lived tracker (#188), not in this issue's pass/fail tree.

The take-home isn't "issues rot" — that's obvious. It's that **the cheapest verification is the first thing to run, and the issue's own evidence commands are the obvious place to start.** Every drift above was caught in the first 30 seconds of grep/curl/cat. None required deep investigation. The cost of skipping that step would have been: a 2-week measurement plan for an already-solved problem, a confused "why is this curl returning 200 not 401" debug session, and a follow-up issue for a workaround that already has a home upstream.

Habit to keep: **before opening any file to edit, re-run the issue's own evidence commands and compare to expected.**

---

## The Podman single-file bind-mount inode trap

Edited `config/prometheus/prometheus.yml` to add three new scrape jobs. Reloaded Prometheus's config via the API. Targets endpoint showed only 12 jobs — the three new ones missing. Hash of the in-container file diverged from the host file even though the quadlet's volume mount is `:ro,Z` on that exact path.

Cause: the quadlet bind-mounts a **single file**, not a directory:

```
Volume=%h/containers/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z
```

Podman resolves single-file binds to the file's inode at container start. Tools that rewrite atomically (Edit, sed in-place, mv) replace the file by writing a temp and renaming it onto the path — the destination now has a *new* inode. The bind mount still points at the *old* inode, which is now orphaned (still on disk, no path).

A full service restart re-resolves the bind. Reload-via-HUP doesn't.

Fix in this session was a `systemctl --user restart prometheus.service`. Real fix is to convert the mount to a directory bind, which would survive atomic-replace edits. That's a one-line quadlet change and a one-line move into a subdirectory; deliberately not bundled with this session's PRs (out of scope, and the workaround is two commands).

This is the second time in three months the inode trap has bitten — same root cause hit Loki's config in March. Worth promoting from "I keep rediscovering this" to a real entry in [[project_platform_gotchas]].

---

## Scratch-image containers can't run shell-based healthchecks

Deployed two `quay.io/oliver006/redis_exporter` containers. Copy-pasted the healthcheck from `node_exporter.container`:

```
HealthCmd=wget --no-verbose --tries=1 -O /dev/null http://localhost:9121/metrics || exit 1
```

`podman ps`: `Up 6 minutes (unhealthy)`. Confirmed:

```
$ podman exec redis-authelia-exporter wget --version
Error: crun: executable file `wget` not found in $PATH
$ podman exec redis-authelia-exporter ls /bin /usr/bin
Error: crun: executable file `ls` not found in $PATH
```

oliver006/redis_exporter is FROM scratch — single Go binary, no shell, no coreutils. The healthcheck was bound to fail.

`postgres-exporter` from `quay.io/prometheuscommunity/postgres-exporter` worked fine — it's based on a small image with wget. Difference between the two communities' packaging choices, not a property of the exporter pattern.

The fix here was to drop `HealthCmd` entirely on the redis exporters. The real health signal for an exporter is the Prometheus `up{job=...}` metric, not a Podman healthcheck — Podman just confirms the *process* is alive, which `Restart=on-failure` already enforces.

General rule worth holding onto: **before writing a `HealthCmd`, check the image's base.** `podman run --rm --entrypoint sh <image> -c 'echo ok'` tells you in two seconds. If it fails, you're on a scratch/distroless image and shell-based healthchecks are off the table. Options at that point are (a) no healthcheck (lean on `Restart=on-failure` + scrape-level `up` metric), (b) a TCP-port probe from outside the container, or (c) bind-mount a static binary like `busybox` in.

---

## Community Grafana dashboards aren't drop-in (and the `instance` label confusion)

Community dashboards 763 (Redis) and 9628 (Postgres) needed three rounds of patching before they were useful:

**Round 1 — `__inputs` strips.** Both dashboards declare a `${DS_PROMETHEUS}` or `${DS_PROM}` input that's meant to be resolved by the import UI. File-based provisioning has no UI step, so the variable stays unresolved and queries silently return nothing. Fix: remove `__inputs`, hard-pin the datasource UID to `prometheus` everywhere it's referenced.

**Round 2 — datasource templating var.** The Postgres dashboard had a templating var of `type=datasource` whose `current` field needed pinning to `{text: "Prometheus", value: "prometheus"}`. The Redis dashboard didn't have one — its `${DS_PROM}` references were dangling after Round 1. String-replace to literal `prometheus` resolved it.

**Round 3 — the `instance` label collision.** This was the interesting one. Both dashboards filter panels by `instance=~"$instance"`, and the `instance` variable is fed by `label_values(<metric>, instance)`. Standard pattern for a fleet where each exporter target is a distinct host. **Our schema is different** — every scrape job in `prometheus.yml` sets `instance: 'fedora-htpc'` explicitly because we have one host:

```yaml
- job_name: 'redis-authelia'
  static_configs:
    - targets: ['10.89.4.92:9121']
      labels:
        instance: 'fedora-htpc'
        service: 'redis-authelia'
```

So `label_values(redis_up, instance)` returns `["fedora-htpc"]`. The dropdown has one entry. Selecting it gives you `redis_connected_clients{instance="fedora-htpc"}` — which matches **both** exporters, summing 2+77=79 clients with no way to separate them. The dashboard renders, technically; it's also unusable for telling which Redis is which.

Fix: repoint `$instance` from `instance` label to `service` label.

```diff
- query: label_values(redis_up, instance)
+ query: label_values(redis_up, service)
```

…and rewrite every `instance(=~|=|!=)"$instance"` panel filter to `service\1"$instance"`. Kept the variable's *name* as "instance" to avoid touching every `$instance` reference downstream. Now the Redis dashboard offers `["redis-authelia","redis-immich"]` and selecting either filters cleanly (2 vs 77 connected clients).

The general principle: **a third-party dashboard's filter assumptions need to match your label schema, or it's not a drop-in.** For a fleet with `instance` as the differentiator, the dashboards work as-is. For our one-host convention, `service` does the work. Either is fine — the question is which axis you've chosen and which axis the dashboard expects.

This patching is small (~30 lines of Python doing a JSON-AST walk) but it's not zero. Importing the same dashboard interactively through the Grafana UI would have silently produced the same broken-filter state — the import dialog doesn't know about your label schema.

---

## Scope clarification before chunky work

For #150 I asked two questions upfront:

1. Two Redis exporters per the issue, or three (include nextcloud-redis for symmetry)?
2. One PR (exporters + scrape configs + dashboards) or two (exporters first, dashboards second)?

User picked "2" and "two PRs." Both answers shaped the implementation: stayed inside the issue's scope on the Redis question, and got a clean exporters-only PR (#190) that proved metrics flowing before any dashboard work began. PR #190's verification was `redis_up=1, pg_up=1`; PR #191's verification was per-service filtering returning the right counts. Two distinct test surfaces, two distinct review surfaces.

If I'd guessed and gone with three Redis exporters in one big PR, the diff would have been twice as large and the user would have had to argue scope down inside the PR review. If I'd guessed and gone with one PR, the exporters' "are metrics flowing" check would have been entangled with the dashboards' "do filters resolve" check — and any dashboard rework (which there *was*) would have rolled back the exporter verification.

Habit to keep: **for any multi-file deployment, ask 1-2 scope questions before the first Write.** The questions force the user to declare a sequencing preference, which is exactly the information you don't have but need.

---

## Out-of-repo state belongs in the PR body

PR #190 created two pieces of state that aren't in the diff:

```bash
# 1. Podman secret holding the postgres exporter password
openssl rand -base64 32 | tr -d '/+=' | head -c 40 | podman secret create postgres-exporter-password -

# 2. Read-only monitoring role on postgresql-immich
podman exec -i postgresql-immich psql -U immich -d immich <<SQL
CREATE ROLE prometheus_exporter LOGIN PASSWORD '<from-step-1>';
GRANT pg_monitor TO prometheus_exporter;
SQL
```

Documented both in the PR body. The repo's `.gitignore` policy means secrets never land in the diff; the corollary is that the *recipe* for reproducing them does — otherwise a fresh-system restore from this repo would deploy three exporters of which one (postgres) silently can't authenticate. The merge would look clean and the bug would surface 24 hours later when nobody can remember what command was missing.

This pattern is worth treating as a hard rule for any quadlet that uses `Secret=` or any database that needs a non-default role: PR body lists every command run outside the diff, with the exact invocation.

---

## Lessons / for future-me

**The first verification step is reading the issue's own evidence and comparing to current state.** Three of four issues this session had drifted. The drift was always visible in the first 30 seconds. Habit: re-run the evidence commands before opening any editor.

**Single-file Podman binds are inode-bound. Atomic edits orphan them; service restart is required to re-bind.** Or convert the bind to a directory and bypass the trap entirely. Either way, "edited the config but the container doesn't see the change" should jump straight to this as the first hypothesis on single-file mounts.

**Check the container image's base before writing a HealthCmd.** Scratch and distroless images don't run shell. A two-second `podman run --rm --entrypoint sh <image>` answers it. Most exporter images are scratch.

**Community Grafana dashboards encode label-schema assumptions. Verify your `$instance` matches theirs.** When it doesn't, the dashboard renders but with subtly wrong panels — easy to mistake for "looks like data, must be working." If your fleet collapses `instance` to a single value, repoint to whatever label actually differentiates targets.

**Forensic writeups travel.** The ABS bug forensics from #185 got picked up by the maintainer who's now driving the upstream fix (PR #5004). That made #186 closable on a concrete trigger ("when #5004 merges") instead of indefinite. The hour spent writing the forensics post in March is paying off now.

**Scope-clarifying questions before chunky multi-file work cost minutes; recovering from wrong-scope assumptions costs hours.** Two questions on #150 saved an over-broad single PR.

**Out-of-repo state goes in the PR body, every time.** Podman secrets, DB roles, anything `.gitignore`'d. The recipe is the documentation; the diff alone is not enough to reproduce.

---

## Soak items (next ~7 days)

- **Watch upstream advplyr/audiobookshelf#5004.** When it merges, revert PR #185 (`ACCESS_TOKEN_EXPIRY=86400`) and bump the ABS image. Tracker is #188.
- **redis-immich eviction visibility.** Now that `redis_exporter` is scraping, `evicted_keys` is a real metric — worth a small alert if the 512M cap is sized too tight.
- **postgres-immich query latency baseline.** `pg_stat_statements` isn't enabled but `pg_stat_database_xact_commit` rate gives a rough TPS curve; useful as a baseline before the next Immich major bump.
- **Convert prometheus.yml mount to a directory bind.** Closes the inode-trap loophole for the config that gets edited most often.
