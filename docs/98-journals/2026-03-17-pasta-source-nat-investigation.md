# Rootlessport Source IP Selection in Multi-Network Containers

**Date:** 2026-03-17
**Status:** ROOT CAUSE IDENTIFIED — confirmed via source code, empirical tests, and upstream issue tracker
**Related:** [2026-03-12-vault-traffic-analysis.md](2026-03-12-vault-traffic-analysis.md), [2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md](2026-02-02-ROOT-CAUSE-CONFIRMED-dns-resolution-order.md), PR #110 (monitoring Internal=true), PR #118 (vault rate limit split)

---

## Executive Summary

All external traffic arriving at Traefik via rootless port forwarding is source-NAT'd to a single container IP chosen **non-deterministically** by `rootlessport`. The specific IP depends on Go map iteration order, which changed when Podman was upgraded from 5.7.1 to 5.8.0 on March 8, 2026. This is a known upstream issue ([containers/podman#12850](https://github.com/containers/podman/issues/12850), open since Jan 2022) with no planned fix.

The real external client IP is never preserved. Network segmentation between containers works correctly — this issue only affects how external traffic appears in Traefik's access logs.

---

## Root Cause: `GetRootlessPortChildIP` and Go Map Iteration

The port forwarding chain for rootless Podman containers:

```
External client → host:443 → pasta (rootless-netns) → rootlessport parent → pipe → rootlessport-child → container:443
```

The critical function is `GetRootlessPortChildIP` in [`containers/common/libnetwork/slirp4netns/slirp4netns.go`](https://github.com/containers/common/blob/main/libnetwork/slirp4netns/slirp4netns.go):

```go
func GetRootlessPortChildIP(slirpSubnet *net.IPNet, netStatus map[string]types.StatusBlock) string {
    // ...
    for _, status := range netStatus {
        for _, netInt := range status.Interfaces {
            for _, netAddress := range netInt.Subnets {
                ipv4 := netAddress.IPNet.IP.To4()
                if ipv4 != nil {
                    return ipv4.String()  // Returns FIRST IPv4 found
                }
            }
        }
    }
    // ...
}
```

It iterates `netStatus` — a `map[string]types.StatusBlock` — and returns the **first IPv4 address it encounters**. Go maps have [deliberately non-deterministic iteration order](https://go.dev/blog/maps). Which network "wins" depends on the Go runtime's internal hash seed, which changes per binary build. A Podman upgrade = new binary = new hash seed = potentially different network selected.

`rootlessport-child` then uses this IP as **both source and destination** when connecting to Traefik's published port inside the container namespace. Traefik sees this as the `ClientHost`.

### Confirmed with TCP connection table

Active connections inside Traefik's network namespace:

```
Local                     Remote                    State
10.89.3.69:35340          10.89.3.69:443            ESTABLISHED  ← rootlessport-child → Traefik
10.89.3.69:35356          10.89.3.69:443            ESTABLISHED  ← rootlessport-child → Traefik
10.89.3.69:53354          10.89.3.69:443            ESTABLISHED  ← rootlessport-child → Traefik
10.89.2.69:32834          10.89.2.71:80             ESTABLISHED  ← Traefik → vaultwarden (correct)
```

rootlessport-child connects from 10.89.3.69 to 10.89.3.69:443 — a loopback-routed connection using the auth_services IP. Traefik logs this as `ClientHost: 10.89.3.69`.

---

## What Changed: Podman 5.7.1 → 5.8.0

```
# From dnf logs:
2026-03-08 23:05:58  RPM install podman-5:5.8.0-1.fc43
2026-03-08 23:06:54  RPM uninstall podman-5:5.7.1-1.fc43
# Reboot: 2026-03-09 00:52
```

| Period | Podman Version | rootlessport Selected IP | Network |
|--------|---------------|--------------------------|---------|
| Jan 18 – Mar 7 | 5.7.1 | 10.89.4.x | monitoring |
| Mar 9 – present | 5.8.0 | 10.89.3.69 | auth_services |

The Podman 5.8.0 [release notes](https://github.com/containers/podman/releases/tag/v5.8.0) show no direct rootlessport changes. The shift is an indirect consequence of recompilation with an updated Go runtime (go1.25.7), which changed the map iteration hash seed.

Before static IPs (pre-PR #109), the selected IP was dynamic and changed on container restarts. This is why the vault traffic journal showed different 10.89.4.x addresses (4.45, 4.57, 4.73, 4.69) across restart boundaries. After static IPs, the selected IP is consistent but still on the wrong network.

---

## Initial Hypothesis Was Wrong

The original hypothesis attributed the IP shift to the monitoring `Internal=true` change in PR #110 (March 1). This was incorrect:

- The monitoring network became internal on **March 1** (PR #110)
- But vault traffic continued showing **10.89.4.69** (monitoring) on **March 7**
- The shift to 10.89.3.69 (auth_services) happened on **March 9** — after the Podman upgrade + reboot

`Internal=true` does **not** exclude a network from rootlessport's IP selection. All three networks are passed to `GetRootlessPortChildIP` regardless of their internal flag:

```
# podman inspect traefik → NetworkSettings.Networks:
systemd-auth_services: 10.89.3.69  (Internal=true)
systemd-monitoring:    10.89.4.69  (Internal=true)
systemd-reverse_proxy: 10.89.2.69
```

---

## Experiment: Controlled Traffic Source Identification

Seven controlled requests from known sources to determine what `ClientHost` Traefik records.

| # | Source | Networks | ClientHost | Interpretation |
|---|--------|----------|------------|----------------|
| 1 | Host (via localhost) | N/A — external | **10.89.3.69** | rootlessport NAT |
| 2 | Host (via LAN IP 192.168.1.70) | N/A — external | **10.89.3.69** | rootlessport NAT (same result) |
| 3 | vaultwarden | reverse_proxy | 10.89.2.1 | reverse_proxy gateway |
| 4 | nextcloud | reverse_proxy, nextcloud, monitoring | 10.89.2.1 | reverse_proxy gateway |
| 5 | prometheus | reverse_proxy, monitoring | 10.89.2.1 | reverse_proxy gateway |
| 6 | authelia | reverse_proxy, auth_services | 10.89.2.1 | reverse_proxy gateway |
| 7 | cadvisor (monitoring-only) | monitoring | 10.89.4.3 | cadvisor's actual IP |

**Key findings:**
- Container-to-container traffic works correctly and shows the actual source network
- External traffic always shows rootlessport's selected IP regardless of entry path
- cadvisor (monitoring-only) cannot resolve external DNS — `Internal=true` works for single-network containers
- Tests via localhost and via LAN IP produce identical results — the NAT happens inside the container namespace, not at the host level

---

## Reboot Correlation

Cross-referencing reboot dates with vault traffic IP subnets:

```
Reboot history:            Dominant vault IP subnet:
Feb  4  00:18              Jan 18 - Feb  2: 10.89.4.x (monitoring)
                           Feb  3:          10.89.3.6  (auth_services — brief)
                           Feb  5 - Feb  6: 10.89.2.x (reverse_proxy — brief)
Feb 16  12:49              Feb  8 - Feb 15: 10.89.4.x (monitoring — back)
Feb 22  23:38              Feb 21:          10.89.2.x (reverse_proxy — during outage)
                           Mar  7:          10.89.4.x (monitoring)
Mar  9  00:52 [Podman 5.8] Mar  9+:         10.89.3.x (auth_services — stable)
Mar 16  19:23              Mar 17:          10.89.3.x (auth_services — still stable)
```

Under Podman 5.7.1, the Go map iteration order was **mostly stable** (monitoring won) but occasionally shifted on reboot (Feb 3 → auth_services, Feb 5 → reverse_proxy, then back to monitoring). This is consistent with Go's map randomization: the hash seed is set per-process, so each new rootlessport process could theoretically pick a different network, though in practice the same binary tends to converge on the same ordering.

Under Podman 5.8.0, the ordering has been **completely stable** across two reboots (Mar 9 and Mar 16), consistently selecting auth_services.

---

## Implications for the Vault Traffic Journal

The vault traffic journal's IP-based analysis needs substantial revision:

1. **"15 unique container IPs" were not 15 distinct actors.** They were rootlessport's selected IP changing across container restarts (dynamic IPs before PR #109) and the occasional Go map reordering on reboot. All external traffic — scanners, legitimate clients, bots — appeared as a single IP per time period.

2. **"Scanner IP rotation" was Traefik restart artifacts.** When Traefik restarted, it got new dynamic IPs. The "scanner rotating from 10.89.3.3 to 10.89.2.76 to 10.89.2.83" was actually rootlessport getting different NAT IPs from different restarts, not an adversary rotating source addresses.

3. **Traffic categorization by user-agent remains valid.** The 87% scanner / 6% legitimate breakdown was based on user-agent analysis, which is unaffected by the source IP issue.

4. **The Feb 2 outage IP changes** (10.89.4.69 → 10.89.4.73 → 10.89.3.10 within 20 minutes) were probably caused by container restarts during the outage investigation. The DNS resolution root cause journal (Feb 2) documents multiple container restarts that day.

---

## Upstream Status

| Issue | Status | Summary |
|-------|--------|---------|
| [#12850](https://github.com/containers/podman/issues/12850) | **OPEN** (since Jan 2022) | Ordering of `--network` flags is disregarded. Networks stored in Go map, iteration order non-deterministic. Fix considered too complex (requires map→slice refactor throughout codebase + DB schema). |
| [#25865](https://github.com/containers/podman/issues/25865) | Closed (not planned) | Maintainer confirmed: "ordering is not deterministic." Suggested `--opt metric=<num>` for routing control. |
| [#28172](https://github.com/containers/podman/issues/28172) | Closed (duplicate of #12850) | Reports exact same problem: "Podman picks the first network... sometimes that's net1, sometimes net2." |
| [#8193](https://github.com/containers/podman/issues/8193) | OPEN | Alternate port handler that preserves source IP. No implementation. |

**No fix is planned.** The maintainers consider the Go map ordering a fundamental design issue that would require refactoring maps to ordered slices throughout the codebase and database schema.

---

## Practical Consequences

**What works:**
- Network segmentation between containers (east-west traffic) is correct
- `Internal=true` prevents single-network containers from reaching the internet
- Static IPs + `/etc/hosts` in Traefik (ADR-018) correctly routes Traefik→backend traffic

**What doesn't work:**
- Distinguishing external clients by IP in Traefik access logs
- Correlating access log IPs with CrowdSec IP reputation
- IP-based rate limiting per real client (all clients share one IP)
- Predicting which IP rootlessport will select after a Podman upgrade

**What would help but isn't implemented:**
- Traefik `forwardedHeaders` / PROXY protocol from an upstream device — but rootlessport doesn't set `X-Forwarded-For` with the real client IP, so there's nothing to forward. The real IP is lost at the rootlessport stage, before Traefik ever sees the connection.
- A fix for [Podman #8193](https://github.com/containers/podman/issues/8193) that preserves source IPs through rootlessport.
- Running Traefik rootful (loses the security benefit of rootless containers).

---

## Remaining Questions

1. **Could PROXY protocol on the UDM Pro help?** If the UDM Pro terminates TCP and re-establishes it with PROXY protocol headers to Traefik, the real client IP could be preserved. This would bypass rootlessport's NAT entirely at layer 7. Requires investigation of UDM Pro capabilities.

2. **Will future Podman versions change the selected IP again?** Every Podman upgrade with a new Go binary could shift the map iteration order. The selected network could change from auth_services to reverse_proxy or back to monitoring without warning. There is no way to pin it.

3. **Would a single-network Traefik design avoid this?** If Traefik were only on `reverse_proxy`, rootlessport would have only one IP to choose. Backend connectivity would require a different approach (host networking for specific connections, or sidecar proxies). This would be a significant architecture change.

---

## Next Steps Completed

| Step | Result |
|------|--------|
| 1. Verify from external source | Tested via LAN IP (192.168.1.70:443). Same result: ClientHost=10.89.3.69. |
| 2. Check pasta/Podman version | pasta 0^20260120.g386b5f5, Podman 5.7.1→5.8.0 (Mar 8). Upgrade is the inflection point. |
| 3. Test interface ordering | **Skipped** — source code analysis proves reordering Network= lines cannot help. The issue is Go map iteration in rootlessport, which ignores interface/declaration order. |
| 4. X-Forwarded-For preservation | Traefik receives no X-Forwarded-For. rootlessport doesn't inject one. The real IP is lost before Traefik sees the connection. UDM Pro PROXY protocol is the only remaining option. |
| 5. Check upstream issue tracker | Found [#12850](https://github.com/containers/podman/issues/12850) (open since 2022, no planned fix), [#25865](https://github.com/containers/podman/issues/25865) (closed, "not planned"), [#8193](https://github.com/containers/podman/issues/8193) (source IP preservation, open, no implementation). |

---

## Raw Test Commands

```bash
# Test 1-2: External requests (loopback + LAN IP)
curl -s -o /dev/null -w '%{http_code}' \
  -H 'User-Agent: SEGMENTATION-TEST-FROM-HOST' \
  https://vault.patriark.org/test-segmentation

curl -s -o /dev/null -w '%{http_code}' \
  --connect-to vault.patriark.org:443:192.168.1.70:443 \
  -H 'User-Agent: TEST-VIA-LAN-IP' \
  https://vault.patriark.org/test-lan

# Test 3-6: Container-originated requests
podman exec vaultwarden curl -s -o /dev/null -w '%{http_code}' \
  -H 'User-Agent: TEST-FROM-VAULTWARDEN' \
  https://vault.patriark.org/test-from-container --insecure

podman exec nextcloud curl -s -o /dev/null -w '%{http_code}' \
  -H 'User-Agent: TEST-FROM-NEXTCLOUD' \
  https://vault.patriark.org/test-from-nc --insecure

podman exec prometheus wget -q -O /dev/null \
  --header='User-Agent: TEST-FROM-PROMETHEUS' \
  'https://vault.patriark.org/test-from-mon' --no-check-certificate

podman exec authelia wget -q -O /dev/null \
  --header='User-Agent: TEST-FROM-AUTHELIA' \
  'https://vault.patriark.org/test-from-auth' --no-check-certificate

# Test 7: Internal-only container
podman exec cadvisor wget -q -O /dev/null \
  --header='User-Agent: TEST-FROM-CADVISOR' \
  'https://vault.patriark.org/test-from-internal' --no-check-certificate
# Result: "bad address" — cannot resolve external DNS ✓

podman exec cadvisor wget -q -O /dev/null \
  --header='User-Agent: TEST-FROM-CADVISOR-DIRECT' \
  'https://10.89.4.69/test-direct' --no-check-certificate
# Result: ClientHost=10.89.4.3 (cadvisor's real IP) ✓

# Inspect rootlessport connections
cat /proc/$(podman inspect traefik --format '{{.State.Pid}}')/net/tcp | \
  python3 -c "..." # (decode hex addresses — see investigation notes)

# Version info
pasta --version        # pasta 0^20260120.g386b5f5-1.fc43
podman version         # 5.8.0, go1.25.7
rpm -qa --last | grep podman  # installed 2026-03-09
```
