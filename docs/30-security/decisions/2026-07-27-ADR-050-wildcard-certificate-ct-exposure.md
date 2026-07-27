---
type: ADR
title: "ADR-050: One Wildcard Certificate — Certificate Transparency as the Real Publisher of the Estate"
description: "ADR replacing per-host TLS certificates with a single patriark.org + *.patriark.org certificate, because per-host issuance wrote every service hostname into Certificate Transparency — public, permanent, append-only — including the password manager. Records the two-part mechanic (default store + no router-level certResolver), the stored-certificate purge without which the change is a no-op, and the capabilities deliberately traded away: per-service key isolation, granular renewal monitoring, and CT as a free external inventory of one's own exposure."
sensitivity: public
created: 2026-07-27
updated: 2026-07-27
---

# ADR-050: One Wildcard Certificate — Certificate Transparency as the Real Publisher of the Estate

**Status:** Accepted (implemented 2026-07-27, PR #353)

## Context

The owner discovered that the auto-generated documentation published every service
hostname to a public GitHub repository, including `vault.patriark.org` — the
Vaultwarden instance. Those views were moved to the private
knowledge vault under the documentation-boundary policy (ADR-043, PR #352), but
investigating the exposure produced a more consequential finding.

**The repository was never the publisher of record.** Traefik issued a separate
certificate per hostname, deriving each request from the router's `Host()` rule. The
live endpoint confirmed it:

```
subject=CN=vault.patriark.org
X509v3 Subject Alternative Name: DNS:vault.patriark.org
```

Every such issuance writes the hostname into Certificate Transparency logs, which are
public, append-only, permanent, and continuously mined by scanners looking for exactly
this — freshly provisioned self-hosted services. `acme.json` held **21 certificates**,
one per name, including five hostnames (`auth`, `prometheus`, `alertmanager`, `home`,
`cloud`) belonging to services long since retired but still being renewed every
~60 days.

So scrubbing hostnames from documentation, or even from the repository entirely, could
not un-publish them. Let's Encrypt had already published them, and no action can
retract a CT entry.

Two facts shaped the decision:

1. **What CT gives an adversary is a name.** What the public repository additionally
   gave was *correlation* — name → running image digest → middleware chain → which
   routes bypass Authelia → rate-limit tier → alert thresholds. That correlation is the
   more valuable artifact and mostly lives in `config/`, not in documentation.
2. **The domain already has wildcard DNS → WAN.** Subdomain guessing therefore yields
   nothing; DNS is not the enumeration channel. CT was.

The owner's framing was the operative one: the password manager being internet-reachable
is an accepted risk, but "telling everyone on the internet exactly what web address to
target seems like it is inviting too much trouble."

## Decision

**One certificate — `patriark.org` with SAN `*.patriark.org` — serves every router.**
No router requests a certificate of its own.

This has two halves, and the second is load-bearing.

### 1. A default certificate on the TLS store

`config/traefik/dynamic/tls.yml`:

```yaml
tls:
  stores:
    default:
      defaultGeneratedCert:
        resolver: letsencrypt
        domain:
          main: "patriark.org"
          sans:
            - "*.patriark.org"
```

Issued through the **existing** `letsencrypt` DNS-01 resolver. No Cloudflare-side
change: the same `Zone:DNS:Edit` token covers wildcard issuance, and DNS-01 is already
mandatory for wildcards.

### 2. No router may carry its own `certResolver`

All 18 routers in `routers.yml` declare a bare `tls: {}` and inherit the store default.
The `certResolver: letsencrypt` line was removed from every one.

**This is the half that actually stops CT publication.** Traefik selects the
certificate to present from the SNI hostname alone — router rules are evaluated after
the handshake and cannot influence it — and an exact-hostname match takes precedence
over a wildcard match. A router retaining its own `certResolver` therefore obtains a
per-host certificate, serves it in preference to the wildcard, and writes that name
back into CT, silently and permanently. Adding the wildcard without removing the
per-router resolvers is a no-op with the appearance of a fix.

### 3. Stored per-host certificates must be purged

Not visible in the diff (`acme.json` is gitignored), and equally load-bearing.

Traefik prefers an exact-match **stored** certificate over the store default, *and*
renews stored certificates regardless of what routers ask for — observed live during
implementation:

```
INF Renewing ACME certificate: {Main:ha.patriark.org SANs:[]}
```

Leaving the 21 stored certificates in place would have kept both behaviours alive: the
old certificates would continue to be served, and CT would continue receiving every
name every ~60 days. They were removed after backing up `acme.json` outside the
repository, leaving exactly one certificate.

## Scope and limits

- **`*.patriark.org` matches exactly one label.** `vault.patriark.org` is covered;
  `a.b.patriark.org` would not be. All 18 rules are single-label; this constrains future
  naming.
- **The apex requires an explicit SAN** — hence `main: patriark.org` alongside the
  wildcard, validated together at `_acme-challenge.patriark.org`.
- **Names already in CT stay there permanently.** This stops forward publication only.
  Erasing the 21 logged names would require renaming the services, which is out of scope
  and disruptive.
- **Local resolution is untouched.** Pi-hole/Unbound answer a split-horizon A record
  (LAN clients get `192.168.1.70`, the internet gets the WAN address); certificate
  issuance is a separate plane, reached over the Cloudflare API. ACME propagation checks
  are already pinned to `1.1.1.1`/`8.8.8.8` in `traefik.yml`, deliberately bypassing the
  local resolver — so renewal cannot be broken by a Pi-hole outage.

## Validation gate

All satisfied before Status → Accepted:

- All 15 routed hostnames serve `CN=patriark.org` with SAN `*.patriark.org`
- Every route returns its expected status: 200 (native auth), 302 (Authelia or app
  redirect), 403 (`pihole`, via its pre-existing `ip-allowlist`)
- `acme.json` holds exactly one certificate; no per-host re-issuance observed
- Owner-verified from a real client: Bitwarden on iPhone from **both** the LAN and the
  internet, plus Navidrome, Audiobookshelf, Nextcloud and Immich. Mobile and
  browser-extension clients validate differently than a browser, so this check was
  required, not optional (L-049)

## Consequences

### Accepted costs

- **CT is no longer a free external inventory of one's own exposure.** This is the
  subtlest cost and was under-weighted during implementation. Every newly exposed
  service used to appear in a public, tamper-resistant log — an outside record of what
  was *actually* exposed, independent of local tooling and not falsifiable by a mistake
  in that tooling. A carelessly added router now produces no external trace. The signal
  that served an adversary served the owner identically; both were given up together.
  Remaining inventory (`routers.yml`, `check-drift.sh`, the generated system views) is
  entirely local and can be wrong in correlated ways.
- **Estate-wide key blast radius.** A leaked key permits impersonation of any subdomain;
  revocation and reissue are all-or-nothing. Mitigating factor: the per-host keys already
  shared a single `acme.json`, so the at-rest delta is small — what changed is the
  *rotation* unit, not the storage.
- **No per-service rotation.** Previously one service's certificate could be reissued on
  suspicion. The smallest rotation unit is now the whole estate.
- **Renewal failure is total and binary**, including LAN access through the split-horizon
  view. Previously one service failed loudly while others kept working.
- **Monitoring granularity.** `TLSCertExpiringSoon` and the renewal-overdue warning group
  by `cn` and still fire correctly, but on one series instead of ~15: they report *that*
  renewal failed, not *which* host.
- **A future per-host carve-out silently republishes that name.** Restoring
  `certResolver` to one router for a legitimate reason (mTLS, a pinned chain) returns
  that hostname to CT with no warning. It must be a deliberate, recorded act — that
  requirement is the main reason this ADR exists.

### Gains

- New service hostnames no longer enumerate publicly.
- New services get working TLS immediately, with no issuance wait and no new CT entry.
- Comfortably further from Let's Encrypt's per-registered-domain rate limits.
- Five retired hostnames stopped being renewed for services that no longer exist.

### Explicitly not degraded

CT monitoring for **mis-issuance** against the domain — someone else obtaining a
certificate for `patriark.org` — works exactly as before. Only self-inventory was lost.

## Alternatives considered

- **Scrub hostnames from the repository and history.** Rejected: 66 tracked files and
  287 occurrences, plus 3 forks outside the owner's control, and it would not have
  touched CT — the actual publisher. Would have produced a strong feeling of closure
  while changing nothing (see L-091, L-102).
- **Rename services to unguessable hostnames.** The only route to erasing the 21 logged
  names. Rejected for now: disruptive to every client and bookmark, and it treats
  hostname secrecy as a security control rather than what it is — attack-surface
  reduction.
- **Take Vaultwarden off the internet (VPN-only).** Not rejected — **deferred as a
  separate decision**, and the more consequential one. Bitwarden clients cache the vault
  locally, so only sync requires the tunnel. Fronting Vaultwarden with Authelia instead
  is a known trap: it sits in the native-auth tier deliberately, and the `/api` +
  `/identity` bypass rules mobile and extension clients need are precisely the L-030
  iterative-breakage pattern that cost five rounds on Gathio.

## Implementation note (operational gotcha)

`systemctl --user restart traefik.service` does **not** yield a cold process under
[ADR-022](../../00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md)
socket activation: `http.socket`/`https.socket` re-trigger the unit, and the respawned
Traefik continued serving its previous in-memory certificate store while `acme.json` on
disk already held only the wildcard. Two restarts appeared to fail for this reason
alone. A genuine cold start requires stopping the socket units as well.

Separately, an overlapping restart put two Traefik processes in flight simultaneously;
both attempted to create the same `_acme-challenge.patriark.org` TXT record and
Cloudflare rejected the duplicate (`81058: An identical record already exists`), leaving
two orphaned records that had to be deleted through the API. Certificate operations
should be performed from a verified single-process state.

## References

- [PR #353](https://github.com/vonrobak/fedora-homelab-containers/pull/353) — implementation
- [PR #352](https://github.com/vonrobak/fedora-homelab-containers/pull/352) — the auto-doc exposure that surfaced this
- [ADR-022](../../00-foundation/decisions/2026-04-16-ADR-022-traefik-socket-activation.md) — socket activation, source of the restart gotcha
- [ADR-016](../../00-foundation/decisions/2025-12-31-ADR-016-configuration-design-principles.md) — all routing in dynamic config, which is why the router change is one file
- L-091, L-102 — check what is already public before scrubbing; CT publishes hostnames
