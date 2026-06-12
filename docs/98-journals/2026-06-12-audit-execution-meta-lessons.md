# From Audit to Execution in One Session — Meta-Lessons

**Date:** 2026-06-12 (evening session)
**Scope:** holistic audit → trajectories report → quick wins (#291) → ADR-031 Phase 3 design +
cross-repo pre-build (#293, htpc-mgmt `4a3a325`/`98be16a`, #296) → sidecar alert coverage (#294)
**Companion:** the forward-looking handoff is
[2026-06-12-handoff-post-audit-followups](2026-06-12-handoff-post-audit-followups.md).
This entry is only about what the day *taught*.

## 1. Config-as-code gaps corrupt audits, not just operations

The audit's exploration agent concluded the autonomous OODA loop was "designed but never
scheduled" — because `autonomous-operations.timer` wasn't in the repo. It runs daily at 06:33.
22 of 37 live timers were untracked, and the audit *of* that gap was itself misled *by* that
gap. The damage radius of untracked state isn't limited to drift and rebuild risk: every
meta-activity that reasons from the repo (audits, agents, new contributors, future-you) inherits
the blind spot and confidently produces wrong conclusions from it. "Is it in git?" is therefore
not just a recovery question — it's an epistemic one.

## 2. Designed-but-dormant capability rots in ways config review cannot see

The remediation webhook was inert for ~6 months with a placeholder token — that part was
visible by grep. What no amount of config reading could reveal: even with a real token it could
never have worked, because the handler bound `127.0.0.1` and rootless containers cannot reach
host loopback. The second defect was only discoverable by *exercising the path* (a wget from
inside the alertmanager container). Dormant capability needs activation drills, not audits;
a path that has never carried traffic should be presumed broken in at least one way nobody
has imagined. (The same lesson re-proved at micro scale: both "secrets" written today were
initially mode 0600 and unreadable by the `nobody`-uid containers — caught only by running
the read.)

## 3. Premise verification beat the written record three times in one day

- The "15 unalerted sidecars" audit finding was mostly false: `ContainerNotRunning` already
  covers all 37 services via cgroup absence detection. One live PromQL query corrected what
  a name-grep had concluded.
- GH#140's framing ("Immich folder-integrity incompatibility, consult upstream") pointed at the
  wrong actor: the real cause was rootless uid-mapping — container-1000 mapped to a subuid the
  host-1000-owned library didn't match. `keep-id` fixed in minutes what had idled six weeks as
  a research task.
- The htpc-mgmt handoff said "vault strategy TBD"; the receiving session found ADR-006 existed
  and the secret was already vaulted.

The pattern: written state (issues, handoffs, audit findings) decays the moment it's written,
and the cheapest correction is one direct measurement before acting. This generalizes the
existing verify-the-issue's-own-evidence rule from issues to *all* inherited claims — including
one's own from earlier the same day.

## 4. A mass restart is involuntary chaos engineering — schedule the insight, not the accident

The 34-service hardening restart did more validation in an hour than weeks of steady state:
it fired the egress observatory on 5 startup-only destinations (exposing that the 18-day
baseline window contained zero restarts → **L-076**, now in lessons.md), exercised the full
alert pipeline, and load-tested boot ordering. Two takeaways beyond L-076 itself: (a) baselines
must be seeded across *event regimes*, not just time; (b) the monthly update loop's restarts
will now act as a recurring regression test for exactly this class — an accidental property
worth keeping deliberate.

## 5. The fix that proves itself by failing is the best verification

The GH#276 directory-mount acceptance test initially *failed* — reload returned 500,
permission denied on the freshly-written file. That failure was the proof: under the old
single-file bind, the stale inode would have kept serving happily and the reload would have
"succeeded". A fix for a silent-failure bug should be tested by looking for the *new, loud*
failure mode, and finding it is success.

## 6. Documented gotchas don't transfer to procedures by themselves

The stacked-PR closure (parent branch deleted before retargeting the child → child PR
irrecoverably closed) happened today — to an agent that had read the journal documenting the
identical June incident *that same morning*. Narrative knowledge ("this once went wrong")
did not produce procedural behavior ("therefore always retarget first"). The lesson is now
encoded as an explicit ordered procedure in session memory; the general rule: when a postmortem
yields a rule, write the rule as *steps in the order they must happen*, colocated where the
action is taken — not as a story.

## Artifacts

- Lessons.md: **L-076** added (steady-state baselines blind to event-driven behavior)
- Memory: stacked-PR procedure hardened in `feedback_commit_signing_via_github_squash`;
  trajectories + DNS-HA memories updated
- The day's full delivery record lives in the PR bodies (#291, #293, #294, #296) and GH#292
