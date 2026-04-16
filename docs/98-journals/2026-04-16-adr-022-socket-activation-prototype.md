# Socket Activation Prototype — Lessons Learned

**Date:** 2026-04-16
**Branch:** `prototype/traefik-socket-activation`
**ADR:** [ADR-022](../00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md) (Proposed)
**Related:** [2026-03-17 pasta source-NAT investigation](2026-03-17-pasta-source-nat-investigation.md), launchpad `docs/99-reports/2026-04-12-nat-security-model-violation.md`, research `docs/99-reports/2026-04-16-nat-remediation-research.md`

## What happened

Two months after the NAT-source-IP root cause was pinned down (2026-03-17 journal), and four days after the exposure-window forensic review (2026-04-14 report) confirmed MFA had held throughout the period where CrowdSec and rate-limiting were effectively inert, the remediation finally landed on something buildable. Not via the path the launchpad had framed (UDM PROXY protocol), but via a path the launchpad had missed entirely: systemd socket activation.

The prototype took one session. Write two `.socket` units, edit `traefik.container` to drop `PublishPort=` and accept `Sockets=`, `systemctl stop traefik`, `systemctl start http.socket https.socket`, curl — and the access log's `ClientHost` field changed from `10.89.2.69` (the shared rootlessport source) to real source IPs. The HTTP→HTTPS redirect caveat the research had flagged (Traefik #12469) did not reproduce.

It worked on the first try, which is itself worth interrogating.

## What I'd call out as real lessons

### 1. The launchpad's ranking axis was wrong, and that mattered for more than a month

The 2026-04-12 launchpad ranked options by "architectural elegance" — how much of the existing design had to change. On that axis, UDM PROXY protocol wins (no host changes), rootful Traefik loses (different privilege model), and socket activation wasn't even in the list.

The 2026-04-16 research session added two axes — **blast radius** and **reversibility** — and the ranking inverted. Socket activation became #1 not because it was elegant, but because: (a) if it fails, `systemctl stop http.socket https.socket && revert the quadlet edit` is a 10-second rollback with zero data migration; (b) if Traefik is compromised, nothing new happens (still rootless, still in its network); (c) no external system (UDM firmware, Cloudflare account, TLS certs) changes.

"What does rolling this back look like, on a Wednesday at 23:00, while something is broken?" is a better question than "what changes least." I want to remember that the next time I'm sizing an architecture option — ask reversibility before elegance.

### 2. "We already considered the options" is not "we considered all the options"

The launchpad was thorough on the options it enumerated — five, with a cost/risk/rootless-preserved matrix. It was wrong because socket activation simply wasn't in the search space. There's no heuristic that would have caught that from inside the launchpad's own framing; it needed an outside perspective that started from "how can we preserve source IPs without moving any boundaries" rather than "which of these five architectural moves do we make."

Corollary for future remediation work: when the candidate list makes the trade-offs all feel equally bad, that's a signal to reopen the search, not to pick the least-bad one.

### 3. Read the research doc, don't paraphrase from memory

Two places where the research doc had precise information and I nearly lost it:

- It said "two new quadlet files" for the `.socket` units. **Quadlet doesn't handle `.socket` files** — `.container`, `.network`, `.volume`, `.pod`, `.build`, `.kube`, `.image`, `.artifact`. Socket units are native systemd units, live in `~/.config/systemd/user/`. The terminology was imprecise; trusting it verbatim would have meant putting socket units in `~/.config/containers/systemd/` where quadlet would ignore them and systemd would never see them. Verified with `man 5 quadlet` before writing the files.
- It said add `Notify=true`. That's correct, but with a side effect: quadlet flips `--sdnotify=conmon` to `--sdnotify=container`, which depends on Traefik itself calling `sd_notify(READY=1)`. Traefik v2+ does, so this works, but if we'd been remediating a service that doesn't implement sd_notify, `Notify=true` would hang the unit for `TimeoutStartSec` before failing. Worth knowing that `Notify=healthy` is the more conservative fallback — it waits on the podman healthcheck instead of trusting the app.

### 4. `Sockets=` in `[Service]` works via quadlet passthrough, which isn't obvious

Quadlet doesn't have a native `Sockets=` key in `[Container]`. What does work: put `Sockets=http.socket` in the `[Service]` section of the `.container` file, and quadlet forwards it into the generated service unit's `[Service]` section unchanged. The existing `[Service]` block in `traefik.container` (for `Restart=`, `MemoryMax=`, etc.) is the same passthrough mechanism; I just hadn't realized its full range before.

`quadlet -user -dryrun` was essential for confirming this — one command, full text of every generated `.service`. Using it to verify the quadlet output *before* daemon-reload caught one invalid assumption (that `Sockets=` might get stripped) and would have caught worse if I'd made worse mistakes.

### 5. The validation that convinced me wasn't the one I expected

I'd expected the moment of truth to be external Internet traffic showing up with real source IPs in the access log. But I don't have an easy way to generate external-origin traffic in a test window. What actually settled it was: I `curl`ed the public hostname from the homelab host itself, the request hairpinned through the UDM Pro's NAT, and the access log showed `"ClientHost":"192.168.1.1"` — the gateway's NAT IP, not `10.89.2.69`.

That's evidence that the rootlessport SNAT path is fully bypassed: if rootlessport were still in the path, it would have rewritten that to `10.89.2.69` regardless of what came in. The *source* IP value is less important than the *identity of the IP-rewriting process* that's no longer in the path. `ss -tlnp | grep :443` agrees — the listener socket owner is `traefik,pid=2941993` (the process inside the container), with `conmon` and `fuse-overlayfs` in the credential chain. No rootlessport.

Different evidence than I'd planned to collect, better evidence for the actual question.

### 6. A 6-week remediation window, a 1-session fix

The NAT violation was identified on 2026-03-17. The launchpad was written 2026-04-12. The forensic review that established MFA had held was 2026-04-14. The research that surfaced socket activation was 2026-04-16 morning. The prototype that verified it works was 2026-04-16 evening.

The gap between "problem understood" and "solution prototyped" was dominated by time spent on the wrong framing (UDM-side solutions) rather than implementation difficulty. Once the right path was named, it was a one-session job. That ratio — weeks-of-framing to hours-of-implementation — is worth noting as a pattern. Future-me, if you're spending more than a session on "which option" for something that's clearly implementable in an afternoon, the problem is probably the option set, not the choice within it.

### 7. Two outstanding verifications I cannot do alone

The prototype is green on five of five criteria I can check from one machine. Two criteria require conditions I can't manufacture:

- **CrowdSec bouncer organic drops.** The internet is hostile; real bouncer drops will appear in `cscli metrics` within minutes to hours of this being live. I can't force the internet to probe. Flagging this as "wait and watch" rather than "tested."
- **Independent per-IP rate-limit buckets.** This needs ≥2 distinct external source IPs hitting the same service concurrently. Could be observed organically, could be manufactured with a VPN + operator phone on cellular, but is not something I can run in-session.

Not a reason to block the merge, but I want to not pretend I verified what I didn't. The access-log evidence proves the *source IP preservation* that both bullets rely on — if the real IPs are in the log, CrowdSec and rate-limit will act on them. The remaining verification is "does the downstream machinery do what we believe it does with correct inputs," which is a weaker claim to need evidence for.

## What I would do differently

- **I would have started from `man 5 quadlet` before writing any `.socket` files.** That's the ground truth for what quadlet knows how to process. I came close to making a placement mistake that would have been confusing to debug.
- **I would have run `quadlet -user -dryrun` as the *first* step after editing the quadlet, not after starting to worry whether it had worked.** It's a pure-function preview of what systemd will see. No reason to wait until after daemon-reload to look.
- **I would have resisted the urge to label the `.socket` files as "quadlets."** The research doc did this loosely; I mirrored it in the ADR text. Corrected in the journal here — they're systemd units, not quadlets. The terminological precision matters because it determines where the files live and who processes them.

## What this unblocks

Downstream of ADR-022 landing:
- Rate-limit middlewares (especially `rate-limit-home-assistant: burst=600` and similar) are now oversized; they can be retuned down once per-IP buckets become meaningful. Separate ticket.
- CLAUDE.md's "Security Architecture" five-layer model stops being stale once this ships.
- The security-auditor skill enhancement (Track B in the launchpad) becomes meaningful again — there's actually something to audit against.
- The NAT violation memory entry (`project_nat_security_violation`) can be substantially trimmed after merge.

What this does not unblock: the Vaultwarden event log gap (`EVENTS_DAYS_RETAIN` never set), the HA/Jellyfin host-LAN `PublishPort=` bypasses, the Bitwarden-breached Authelia password exposure window. Those are independent findings from the 2026-04-14 and 2026-04-16 reports; none of them block this merge and none of them get fixed by it.
