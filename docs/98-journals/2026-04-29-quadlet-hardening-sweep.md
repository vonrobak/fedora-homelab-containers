# Quadlet Hardening Sweep — Resource Governance + Healthcheck Cadence on the Critical Path

**Date:** 2026-04-29
**PR:** #183
**Closes:** #143 (OOMPolicy), #144 (CPUQuota tiers), #152 (redis-authelia eviction), #153 (healthcheck cadence)
**Defers:** #140 (Immich `User=1000:1000`) — investigation comment posted on the issue
**Context:** Triage pass on the open-issue backlog (16 open). Identified three plausible session-batches: quadlet hardening, Authelia config cleanup, monitoring exporters. Picked quadlet hardening because it was the only batch that closed a high-severity issue (#140) — though that one ended up deferred for reasons documented below.

---

## What shipped

12 quadlet files changed, 26 insertions / 11 deletions. Single PR per the audit's recommendation that #143 + #144 land together so a misshapen quota doesn't ship without its OOM safety net.

### #143 — `OOMPolicy=kill` on 6 critical-path services
`traefik, authelia, prometheus, redis-authelia, nextcloud-db, postgresql-immich`. Default `OOMPolicy=stop` can leave a unit "running" with the main PID OOM-killed; `=kill` transitions cleanly to `failed` so `Restart=on-failure` actually triggers. Cheap and uncontroversial.

### #144 — CPUQuota tier matrix, **rescaled for 12 cores**
This is the interesting one. The audit recommended `200% / 150% / 100% / 50%` for never-throttle / foreground / background / truly-bg. That sizing assumed a 4-core HTPC. On 12 cores, 200% = ~16% of total CPU — that would have manufactured artificial scarcity for the edge in exactly the auth-storm scenario the quota was meant to prevent.

Rescaled to preserve the *relative* tiering (background can't starve foreground under contention) without capping the never-throttle tier below typical demand:

| Tier            | Old (4-core) | New (12-core) | Services                          |
|-----------------|--------------|---------------|-----------------------------------|
| Never-throttle  | 200%         | **400%**      | traefik, prometheus, authelia     |
| Foreground      | 150%         | **400%**      | nextcloud, immich-server          |
| Background      | 100%         | **600%**      | jellyfin, immich-ml               |
| Truly bg        | 50%          | **200%**      | qbittorrent                       |

Authelia bumped 100→400% to share Traefik's tier — SSO failure cascades to all protected services, so it's as critical as routing.

The 12-core thing is worth flagging: the audit was a snapshot from a different machine class, and the recommendations got copy-pasted into the issue body without recalibration. Future-me, before applying any "audit recommends X%": run `nproc`.

### #152 — redis-authelia eviction
`--maxmemory 128mb → 200mb` (still 50MB headroom under `MemoryMax=256M`); `--maxmemory-policy allkeys-lru → volatile-lru`. Sessions have TTLs, regulation counters do not — `volatile-lru` evicts only sessions under pressure so brute-force protection survives an eviction wave instead of resetting alongside everything else.

### #153 — Healthcheck cadence
`HealthInterval=10s, HealthTimeout=3s` on traefik, authelia, prometheus, alertmanager, redis-authelia. Was 30s/10s. Cuts worst-case unhealthy-detection from ~90s to ~30s on the fail-fast path. Background services stay on defaults — no point polling Jellyfin every 10s.

---

## The Immich deferral (#140) — why it's not a one-line revert

User flagged caution on #140 going in. Investigation justified it.

```
$ podman exec immich-server id
uid=0(root) gid=0(root)

$ stat -c '%U:%G %u:%g' /mnt/btrfs-pool/subvol3-opptak/immich
patriark:patriark 1000:1000
```

Container runs as **UID 0 inside**, which rootless Podman maps to **host UID 1000** (the rootless userns "root" mapping). That's why files written by container-root land as `patriark:patriark` and everything works today despite the absent `User=`.

`User=1000:1000` becomes `--user 1000:1000` on `podman run`, which selects an in-container UID **inside the user namespace**. With the default rootless userns:
- container UID 0    → host UID 1000  (the rootless root mapping)
- container UID 1000 → host UID **100999**  (drawn from `/etc/subuid`)

So adding `User=1000:1000` does **not** preserve current ownership — it shifts Immich's writes to host UID 100999, which can't read the existing 10K photos owned by 1000:1000. That's almost certainly what the original "folder integrity check" failure surfaced as. The TODO in the quadlet (`Revisit after consulting Immich community or upstream fix`) was written as if upstream had a fix to wait for. Upstream isn't the bug — the userns layout is.

Two viable paths, both non-trivial:
1. `PodmanArgs=--userns=keep-id:uid=1000,gid=1000` + `User=1000:1000`. Keeps host UID 1000 visible as in-container UID 1000, no chown needed. **Risk:** keep-id changes the userns layout — supplementary GIDs and `/dev/dri` access (GPU group for VAAPI) may behave differently. Needs a transcode test.
2. `User=1000:1000` + `chown -R 100999:100999` of the Immich subvol. Breaks Nextcloud's read-only `/external/opptak` mount until that user is fixed. One-way door.

Path 1 is the ergonomic one. Both wanted a separate branch, separate test gates, separate risk profile. Posted the writeup as a comment on #140 so the next attempt has a playbook instead of a TODO.

---

## Execution surprises

**The wrong hostnames in my smoke test.** First-pass curl loop hit `qbittorrent.patriark.org` (404) and `auth.patriark.org/api/health` (404) and I briefly thought I'd broken something. Real names: `torrent.patriark.org` and `sso.patriark.org`. Lesson: pull the hostnames from `routers.yml`, not memory. Doubly true on a fresh-cache session.

**One sleep-loop block.** Tried to chain `sleep 25 && systemctl is-active ...` after a shorter sleep had already elapsed; the harness blocks chained sleeps used as polling. Switched to `until ...; do sleep 3; done` in `run_in_background:true` and got a clean notification when services settled. Worth remembering: for "wait for things to come up," the until-loop pattern is what the harness wants.

**`podman ps` reports container health independently of `systemctl is-active`.** Mid-restart cycle, four services were `activating` per systemd while the containers themselves were already `(healthy)` per Podman. The systemd unit waits for the entrypoint to finish initial setup (varies by image), but the healthcheck is satisfied earlier. Both signals are useful — systemd for "is the unit happy," Podman for "is the application accepting traffic."

---

## Verification snapshot (as merged)

```
OOMPolicy:    traefik=kill authelia=kill prometheus=kill redis-authelia=kill
              nextcloud-db=kill postgresql-immich=kill
CPUQuota:     traefik=4s authelia=4s prometheus=4s nextcloud=4s immich-server=4s
              jellyfin=6s immich-ml=6s qbittorrent=2s
Redis:        maxmemory=209715200 (200MB) policy=volatile-lru
Healthcheck:  traefik authelia prometheus alertmanager redis-authelia → 10s/3s
Auth chain:   traefik.patriark.org → 302 sso.patriark.org/?rd=... (intact)
homelab-intel: 80/100, only pre-existing C002 SSD-90% warning
journalctl -p err since restart: no entries on critical services
```

---

## Lessons / for future-me

**Always re-check audit numbers against the actual host.** `nproc`, `free -h`, `df -h` before applying any percentage- or size-based recommendation from a doc that wasn't written this week. The 4-core → 12-core rescaling was a 2x miss in the wrong direction; on a smaller machine the audit's numbers would have been fine.

**Defense-in-depth annotations rot when the mechanism changes.** The Immich quadlet's TODO ("revisit after upstream fix") had been there long enough that picking it up cold made me assume upstream was the blocker. The actual blocker is the rootless userns layout, which has nothing to do with Immich. Annotations that lock in *the explanation you had at the time* age worse than annotations that point at the symptom.

**One PR per "thing that needs to be tested as a unit."** The audit explicitly grouped #143+#144 because mis-sized quotas without OOM safety can create new failure modes. Splitting them to "land trivial first, hard second" would have shipped the risk without the cushion. Bundling #152+#153 alongside cost nothing — same restart cycle, same verification surface.

**Triage matters more than throughput on backlog days.** Three batches were plausible from the 16 open issues; the chosen one closed 1 high-severity + 3 medium/low in one verifiable PR with a clean restart cycle. The Authelia and monitoring-exporter batches are still there for next time, scoped and ready.

---

## Soak items (next ~7 days)

- `evicted_keys` on redis-authelia (visibility lands when #150 ships `redis_exporter`; until then, manual `redis-cli info stats | grep evicted_keys`)
- Authelia auth latency p99 during evening usage spike — should be unchanged or lower with the 100→400% bump
- Any unit transitions to `failed` on the OOMPolicy=kill set (would indicate the new policy actually fired, which would also indicate a memory sizing problem worth investigating separately)
