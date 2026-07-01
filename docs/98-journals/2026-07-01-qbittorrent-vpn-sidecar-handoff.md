# Handoff — qBittorrent VPN Egress Sidecar (gluetun + ProtonVPN)

**Date:** 2026-07-01
**Status:** Phase 1 half-built. Inert artifacts committed; live cutover pending, **blocked on one owner action** (create the VPN secret).
**Branch:** `feat/qbittorrent-vpn-sidecar` (commit `1f6df39`, signed). Not pushed, no PR yet.
**Decision record:** `docs/00-foundation/decisions/2026-07-01-ADR-042-vpn-egress-sidecar-qbittorrent.md`

---

## Why

qBittorrent egresses its BitTorrent swarm (~360 concurrent peer connections) **directly on the
home WAN IP** — the "troublesome traffic". Fix: route qBittorrent through a `gluetun` VPN sidecar
(ProtonVPN/WireGuard) with a kill-switch, so only an encrypted tunnel leaves the router and a
tunnel drop leaks nothing. Closes the "no VPN" adjacent finding in `config/supply-chain/known-egress.md`.

Choices already made: **ProtonVPN** (consolidates on Proton; keeps port-forwarding option open),
**WireGuard**, **Phase 1 = outbound-only (NO port forwarding; that's Phase 2)**.

## What is already done (committed on the branch, all inert — nothing enabled)

- `quadlets/gluetun.container` — the sidecar. Digest-pinned `qmcgaw/gluetun@sha256:b0ee2135…`
  (ADR-030), `NET_ADMIN` + `/dev/net/tun`, kill-switch firewall, ProtonVPN/WireGuard env,
  `Secret=gluetun_wireguard_key`, holds static IP **`10.89.2.85`** (the slot qBittorrent uses today).
  Exit country = **Estonia** (`SERVER_COUNTRIES=Estonia`, digital-rights posture) **+
  `PORT_FORWARD_ONLY=on`** — MANDATORY: Estonia's 5 Proton servers include 3 Secure Core (CH-EE/SE-EE)
  that BLOCK P2P; the filter pins to the 2 standard P2P servers (EE#13/EE#23, Tallinn). Only 2 usable
  ⇒ no in-country fallback (kill-switch = offline if both down). Editable before cutover.
- `docs/00-foundation/decisions/2026-07-01-ADR-042-…md` — the decision + trade-offs + deploy gate.
- `config/gluetun/.gitkeep` — runtime-state dir for the mount.

**Live services are untouched.** qBittorrent, Traefik, and the egress baseline are all still their
original versions. The hazardous edits were deliberately deferred to the cutover (this worktree IS
the running config — editing `qbittorrent.container` or `routers.yml` now would take effect on the
next daemon-reload / Traefik auto-reload and could break the running service before gluetun exists).

---

## ⬜ OWNER ACTION — do this first (unblocks everything)

**1. Get a ProtonVPN WireGuard key.** `account.protonvpn.com` → **Downloads → WireGuard configuration**:
- Name it e.g. `gluetun-htpc`; platform **GNU/Linux (Router)**.
- **NAT-PMP / Port Forwarding OFF** (Phase 2 only).
- Server/country choice here is irrelevant: ProtonVPN WG keys are **account-wide**, so gluetun's
  `SERVER_COUNTRIES=Estonia` selection works with a key generated for any country (no need to match).
- Create → copy the **`PrivateKey`** line from the generated config. (gluetun needs only the private key.)

**2. Create the podman secret on the host** (run it yourself; the assistant never sees the key). This
form avoids shell-history leakage and the trailing newline that breaks WireGuard keys:
```bash
read -rs WGKEY            # paste the PrivateKey, press Enter (not echoed, not logged)
printf '%s' "$WGKEY" | podman secret create gluetun_wireguard_key -
unset WGKEY
```
Verify it exists: `podman secret ls | grep gluetun_wireguard_key`

> **Why `podman secret create` and not `secretctl`:** ADR-041/CLAUDE.md describe an OpenBao substrate,
> but as of 2026-07-01 **OpenBao is not live and `secretctl` does not exist** (verified: no `:8200`,
> no service; all 30 fleet secrets are still `podman secret` file-driver). This secret follows the
> current mechanism and migrates into OpenBao with the rest when that goes live (same name).

Then start a session and say: *"the gluetun_wireguard_key secret is created, run the cutover."*

---

## Cutover — assistant runs this once the secret exists (atomic, ~2 min)

**Edit 1 — `quadlets/qbittorrent.container`:**
```
# [Unit]: was
After=network-online.target reverse_proxy-network.service
Wants=network-online.target reverse_proxy-network.service
# → becomes
After=network-online.target gluetun.service
Wants=network-online.target
BindsTo=gluetun.service                       # kill-switch lifecycle: qBt stops if gluetun stops

# [Container]: was
Network=systemd-reverse_proxy:ip=10.89.2.85
DNS=192.168.1.69
# → becomes (qBt joins gluetun's netns; DNS now resolves through the tunnel)
Network=container:gluetun
# (DNS line removed)
```

**Edit 2 — `config/traefik/dynamic/routers.yml`:** the `qbittorrent` service loadBalancer url
`http://qbittorrent:8085` → `http://gluetun:8085`. (Router/middlewares/`torrent.patriark.org` unchanged.)

**Edit 3 — `config/supply-chain/egress-baseline.yaml`:** add `- gluetun` to `peer_swarm_services`
(gluetun becomes the sampled egress-tier container; its shared-netns socket table shows the swarm,
so it inherits count-only). Note qBittorrent is now behind it.

**Apply (order matters — frees the 10.89.2.85 IP before gluetun claims it):**
```bash
systemctl --user daemon-reload
systemctl --user stop qbittorrent.service           # releases 10.89.2.85
systemctl --user start gluetun.service
# wait for tunnel: watch until healthy
podman ps --filter name=gluetun --format '{{.Status}}'
# confirm exit IP is ProtonVPN (gluetun control API):
podman exec gluetun wget -qO- http://localhost:8000/v1/publicip/ip; echo
systemctl --user start qbittorrent.service
```

## Deploy gate — NOT done until all three pass (L-049)

```bash
# 1. WebUI reachable through gluetun
curl -I https://torrent.patriark.org                       # expect 200 / auth redirect

# 2. qBittorrent's public IP == ProtonVPN (it shares gluetun's netns)
podman exec qbittorrent curl -s https://api.ipify.org; echo # expect the ProtonVPN IP, NOT the WAN IP

# 3. LEAK TEST — stop the tunnel, qBittorrent must have ZERO connectivity (no WAN fallback)
systemctl --user stop gluetun.service
podman exec qbittorrent curl -s --max-time 5 https://api.ipify.org; echo "rc=$?"   # MUST fail/timeout
systemctl --user start gluetun.service && systemctl --user start qbittorrent.service
```
Then: one real torrent confirmed downloading through the tunnel, `service-validator` /
`verify-deployment.sh qbittorrent` clean.

## Finish

- Commit the cutover edits on the same branch (signed), then **open the PR** (full verified change =
  gluetun quadlet + ADR + qBt netns switch + Traefik reroute + baseline). Merge-commit only (ADR-038).
- Update `config/supply-chain/known-egress.md` "Adjacent finding" (the no-VPN note) to "resolved, ADR-042".

## Gotchas / context for a fresh session

- **Live-config rule:** this worktree is the running config. Don't edit `qbittorrent.container` /
  `routers.yml` until the cutover, and don't return the worktree to `main` across the applied-but-unmerged
  branch.
- **Rootless WireGuard:** gluetun uses userspace wireguard-go (rootless) — `NET_ADMIN` + `/dev/net/tun`
  are enough; no kernel-WG sysctls. If the tunnel won't establish, that's the first thing to check.
- **Observatory honesty:** the swarm noise does NOT disappear from the observatory — it moves to gluetun
  (still count-only). The real win is at the wire (single encrypted tunnel) + the airtight kill-switch.
- **SSH signing:** `export SSH_AUTH_SOCK=/run/user/1000/gcr/ssh` before `git commit` in a plain SSH session.
- **Phase 2 (later):** ProtonVPN NAT-PMP port forwarding via gluetun + a gluetun→qBittorrent port-sync
  hook, for better ratios. Regenerate the WG key with port forwarding enabled.

## References

- ADR-042 (this work) · ADR-030 P7 (egress observatory, `peer_swarm_services`) · ADR-041 (secret handles,
  target state) · ADR-018 (static-IP) · ADR-038 (merge-commit only).
- Memory: `project_qbittorrent` (in-progress state), `project_secrets_architecture` (OpenBao not-live note).
