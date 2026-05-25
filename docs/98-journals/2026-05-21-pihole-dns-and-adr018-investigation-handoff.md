# Handoff: Pi-hole "nothing blocked" anomaly + ADR-018 workaround obsolescence review

**Created:** 2026-05-21 (by Claude, end of Forgejo deployment session)
**For:** a fresh session with no context from the originating conversation
**Status:** OPEN — investigation not yet started
**Type:** two related-but-distinct investigations. Keep them separate; do not conflate.

---

## Why this exists

During a Forgejo deployment the owner raised two things:

1. **Pi-hole anomaly:** Lots of DNS requests in the Pi-hole query log attributed to "this server" / many marked as `localhost` (or similar), and **zero queries being blocked** — despite the owner browsing the web heavily from `fedora-htpc` (.70), where Pi-hole "used to" reliably block trackers/ads. "Now zero."
2. **A hunch:** that this is caused by "the custom DNS hack we made back in the day" (the ADR-018 `/etc/hosts` + static-IP workaround), and a request to determine **whether that workaround is even still needed**, or whether it was a remnant of a Podman multi-network DNS-ordering bug that may since be fixed.

**Important framing for the investigator:** these are almost certainly TWO separate issues. The ADR-018 hack is internal to the Traefik container and cannot, by itself, stop the *host's web browsing* from being filtered by Pi-hole. Don't let the owner's (understandable) hunch anchor you — verify independently. The leading hypothesis for #1 is browser-level DoH bypass, which has nothing to do with #2.

---

## Confirmed topology & facts (gathered 2026-05-21, verify if stale)

- **Pi-hole** runs on the **Raspberry Pi at `192.168.1.69`** (`raspberrypi`). This server is `fedora-htpc` at `192.168.1.70`. (`fedora-jern` = .71, MacBook = .11.)
- Host `/etc/resolv.conf` on fedora-htpc: `nameserver 192.168.1.69`, `search lokal`, `options edns0 trust-ad`, NetworkManager-managed.
- **No systemd-resolved stub** in use (`resolvectl status` returned empty) — so the OS resolves directly against Pi-hole, no 127.0.0.53 stub layer locally.
- Container DNS: quadlets and `.network` files use `DNS=192.168.1.69` (Pi-hole directly).
- Versions: `podman 5.8.2`, `aardvark-dns 1.17.1`, `netavark 1.17.2` (Fedora 44).
- Rootless Podman NATs container egress to the host IP, so container→Pi-hole queries should appear in Pi-hole as coming from **.70**, not localhost.

### The three mechanisms (do not conflate)

| # | Mechanism | Scope | Relevant to |
|---|-----------|-------|-------------|
| A | **Split-horizon / NAT hairpin** for `*.patriark.org` | LAN clients reaching public hostnames | Minor cleanup only |
| B | **ADR-018 `/etc/hosts` + static IPs** (`config/traefik/hosts`) | *Inside Traefik container*, backend name→network resolution | Thread B below |
| C | **Pi-hole filtering of host/browser DNS** | OS + browser DNS path | Thread A below |

A is `events.patriark.org` resolving to `.70` internally while `git.patriark.org` does not (inconsistent but harmless). Not the cause of anything here.

---

## Thread A — Pi-hole "nothing blocked"

> **UPDATE 2026-05-21:** Tested — `dig doubleclick.net @192.168.1.69` → `0.0.0.0`, `flurry.com` → `0.0.0.0`, `example.com` → real IPs. **Pi-hole blocking is confirmed healthy** (hypothesis 2 below is OUT). The disambiguator is settled: the problem is **client-side** — the browser's queries aren't reaching Pi-hole. Focus on hypothesis 1 (Vivaldi DoH) + hypothesis 3 (localhost-client puzzle). Don't re-run the gravity/blocking check.

### Hypotheses (ranked)

1. **Browser DoH bypass (PRIME SUSPECT).** Firefox/Chrome may be using DNS-over-HTTPS directly to Cloudflare/Google/NextDNS, bypassing the OS resolver entirely. This perfectly explains "OS/container queries show in Pi-hole, but my web-browsing trackers are never blocked": those lookups never reach Pi-hole. Firefox enables DoH automatically in many setups.
2. **Pi-hole blocking globally degraded.** Blocking toggled off, gravity/blocklists empty or failed to update, or Pi-hole running in a passthrough state. This would show as zero blocks for **all** clients, not just this workstation.
3. **Client misattribution ("localhost").** Need to identify the real source of the `localhost`/127.0.0.1 queries in Pi-hole. Options: queries from the Pi itself (gravity updates, its own resolver), an upstream/conditional-forwarding setup masking real clients, or the owner reading the Top-Clients panel where `localhost` = the Pi.

**Key disambiguator:** Is it zero blocks **globally** (→ hypothesis 2) or only for **this workstation's browsing** while other clients/devices still get blocks (→ hypothesis 1)? Establish this first.

### Diagnostic steps

- On a phone/another LAN device, browse to a known ad/tracker domain and check Pi-hole's live query log — is *anything* blocked for *any* client right now?
- Pi-hole admin: check **blocking enabled**, **gravity domain count** (Tools → Update Gravity / `pihole -g` count), and the query-log breakdown by client + by status (blocked vs forwarded vs cached).
- On fedora-htpc, test the OS path directly: `dig doubleclick.net @192.168.1.69` and `dig flurry.com @192.168.1.69` — if Pi-hole returns `0.0.0.0`/NXDOMAIN, OS-path blocking works and the gap is browser-side.
- Firefox: `about:config` → `network.trr.mode` (0/2/3/5 — 2/3 = DoH active) and `network.trr.uri`. Or about:networking#dns. Chrome: Settings → Privacy → "Use secure DNS".
- Network-level: check whether outbound DoH (443 to 1.1.1.1 / dns.google / mozilla.cloudflare-dns.com) is happening from .70. Consider whether to block/redirect DoH at the UDM to force clients onto Pi-hole.
- Confirm the UDM isn't handing out an alternate/secondary DNS server via DHCP that clients fall back to.

### Decision criteria

- If DoH: decide policy — disable browser DoH, or point browser DoH at a Pi-hole DoH endpoint, or block external DoH at the UDM.
- If gravity/blocking degraded: fix Pi-hole (re-enable, update gravity, check disk/health on the Pi).

---

## Thread B — Is the ADR-018 `/etc/hosts` + static-IP workaround still needed?

### Background (READ BEFORE TOUCHING)

- ADR: `docs/00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md`
- Root cause: `docs/98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md` (and the surrounding `2026-02-02-*` cluster — this was a **catastrophic network-failure incident**, with kernel-rollback tests and a symlink hypothesis).
- Mechanism: `config/traefik/hosts` (bind-mounted to Traefik's `/etc/hosts`) pins each backend service name to its `reverse_proxy` static IP (10.89.2.x, .69+). Without it, aardvark-dns returned multi-network container IPs in **undefined order**, so Traefik sometimes routed via the wrong network (e.g. monitoring) → broke routing / violated segmentation.
- **21 containers** currently carry `Network=systemd-reverse_proxy:ip=…` and depend on this: gathio, grafana, alertmanager, authelia, forgejo, nextcloud, home-assistant, prometheus, jellyfin, loki, audiobookshelf, immich-server, homepage, unpoller, traefik, proton-bridge, crowdsec, qbittorrent, vaultwarden, navidrome, alert-discord-relay.

**This is load-bearing infrastructure born from a catastrophic outage. Treat removal as high-risk. Do NOT rip it out casually.**

### What might have changed

- aardvark-dns/netavark have had multi-network ordering fixes over time. Current = aardvark-dns 1.17.1 / netavark 1.17.2 / podman 5.8.2. Determine which versions were in play during the Feb 2026 incident and whether the relevant ordering fix landed since. Check aardvark-dns release notes / upstream issues on multi-network DNS result ordering.

### Test methodology (safe, reversible)

1. Confirm the bug still reproduces *today* before assuming the fix is needed: on a multi-network container, repeatedly resolve a backend name from inside Traefik and observe whether aardvark returns a stable, correct (reverse_proxy) IP or a varying/wrong-network one. e.g. `podman exec traefik getent hosts gathio` many times, and compare against the container's actual reverse_proxy IP.
2. If aardvark now returns stable/correct ordering, pick ONE low-risk service (e.g. gathio) and test removing only its `/etc/hosts` entry — restart Traefik (remember: `config/traefik/hosts` is a **single-file bind mount**, inode-bound; edits require a Traefik restart to take effect, see platform gotchas) — and verify routing still hits the right network. Keep BTRFS snapshot / git revert ready.
3. Only after a service-by-service validation would wholesale removal be justified. The static IPs themselves are cheap to keep even if `/etc/hosts` becomes unnecessary; consider decoupling the two questions.

### Rollback safety

- All changes are in `config/traefik/hosts` and quadlet `Network=` lines, both in git. Revert + Traefik restart restores prior behavior. BTRFS snapshots available (ADR-021/Urd).

---

## Side note — Thread A's red herring

Be ready to explain to the owner *why* the ADR-018 hack (Thread B) does not cause the Pi-hole "nothing blocked" symptom (Thread A): it only affects the Traefik container's internal backend-name resolution; it does not sit in the path of the host's or browser's outbound DNS. They can be fixed/decided independently.

---

## References

- `config/traefik/hosts` — the ADR-018 override
- `docs/00-foundation/decisions/2026-02-04-ADR-018-static-ip-multi-network-services.md`
- `docs/98-journals/2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md`
- Platform gotchas memory: single-file bind mounts are inode-bound (Traefik restart needed after editing `hosts`); static IPs use .69+ convention.
