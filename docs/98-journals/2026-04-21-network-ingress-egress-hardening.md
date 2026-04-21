# Network Ingress/Egress Hardening — #141 + #142

**Date:** 2026-04-21
**PR:** #170 (merged)
**Closes:** #141, #142
**Context:** Two `config-review-2026-04-17` milestone follow-ups, bundled on the owner's call because they touched the same quadlets (`jellyfin.container`, `home-assistant.container`) and shared a restart surface.

---

## What shipped

| File | Change |
|---|---|
| `quadlets/media_services.network` | `+ Internal=true` |
| `quadlets/home_automation.network` | `+ Internal=true` |
| `quadlets/jellyfin.container` | `PublishPort=8096:8096` → `192.168.1.70:8096:8096`; same for `7359:7359/udp` |
| `quadlets/home-assistant.container` | `PublishPort=8123:8123` → `192.168.1.70:8123:8123` |

12 insertions, 5 deletions.

**#141 (egress).** `media_services` and `home_automation` were the only two non-`reverse_proxy` networks without `Internal=true`, inconsistent with the 8-network segmentation model in `CLAUDE.md`. Jellyfin and home-assistant already multi-network onto `reverse_proxy` for metadata/cloud egress, and matter-server is LAN-multicast only — nothing on either segment needed direct egress.

**#142 (ingress).** `PublishPort=8096:8096` etc. bind to `0.0.0.0` — every host interface. Native app auth was the *only* defense, since direct-port traffic bypasses the Traefik fail-fast chain (CrowdSec → rate-limit → security headers). Binding to the LAN IP means a firewalld misstep or a future secondary NIC can't accidentally expose the service without the chain.

---

## Two things worth writing down

### The issue body had the wrong IP

Issue #142 prescribed `PublishPort=192.168.1.69:...`. That's the Pi-hole DNS (referenced in every `DNS=192.168.1.69` line across the quadlets). The host's LAN interface on `enp3s0` is `192.168.1.70`. Caught it by running `ip -4 addr show` before editing. Fix went into the PR; the issue body was left alone and the correction noted in both the commit message and the PR body.

**Lesson:** evidence blocks in issues get copy-pasted across PRs as-is when they look right. One quick `ip a` before trusting a specific-value remediation would have been cheap here and caught it faster — worth adopting as reflex for any issue that names a literal IP/port/hostname.

### `Internal=true` is a no-op on network restart

Adding `Internal=true` to a `.network` quadlet and restarting the `*-network.service` unit looked like it applied — the service came back `active`, but `podman network inspect ... --format '{{.Internal}}'` still said `false`. Inspected the generated unit:

```
ExecStart=/usr/bin/podman network create --ignore --internal --dns ... systemd-media_services
```

`--ignore` short-circuits when the network already exists. Restarting the service re-runs create; create bails silently; network keeps its old flags. Had to explicitly `podman network rm` before the restart took effect.

**Sequence that worked:**
```
systemctl --user stop jellyfin home-assistant matter-server
systemctl --user daemon-reload
podman network rm systemd-media_services systemd-home_automation
systemctl --user restart media_services-network.service home_automation-network.service
systemctl --user start jellyfin home-assistant matter-server
```

This is a real platform gotcha, not a one-off — any change to a `.network` file that alters flags (not just DNS/subnet) will silently not apply. Candidate for `project_platform_gotchas.md`.

---

## Verification (all green before merge)

- `ss -tlnp` → `192.168.1.70:{8096,8123}` (was `*:...`)
- `ss -ulnp` → `192.168.1.70:7359`
- `podman exec matter-server python3 -c "socket.gethostbyname('google.com')"` → `gaierror` (egress blocked, as intended)
- `podman exec home-assistant curl https://www.home-assistant.io/` → `HTTP 200` (multi-network egress preserved via `reverse_proxy`)
- `podman exec jellyfin curl https://api.themoviedb.org/` → `HTTP 301` (metadata egress preserved)
- `curl -I https://{home,jellyfin}.patriark.org/` → `HTTP/2 302` (Traefik path unaffected)
- `curl -I http://192.168.1.70:{8123,8096}/` → reachable from LAN
- `curl -I http://127.0.0.1:8123/` → refused (expected consequence of the `host-ip:` form)
- All three containers `(healthy)` post-restart
- HA ↔ matter-server WebSocket (port 5580) reachable intra-network

---

## Scope kept narrow

`config-review-2026-04-17` has more MEDIUMs in the same milestone. None were touched in this session; the owner-tagged "bundle with" relationship was specifically `#141 ↔ #142`. The same-restart-surface criterion is what made bundling valuable — don't extend it to unrelated items just because the PR is open.
