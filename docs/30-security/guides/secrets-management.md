---
type: Guide
title: "Secrets Management (workload side)"
description: "Workload-side secrets-management guide describing the OpenBao substrate model and the Secret= name-based consumption contract this repo owns."
sensitivity: public
created: 2025-12-31
updated: 2026-06-14
---

# Secrets Management (workload side)

**Rewritten:** 2026-06-14. This replaces the previous version (2025-12-26), whose model was
stale and **wrong on one key point**: it claimed "Podman secrets are encrypted at rest." They
are **not** — the default Podman `file` driver stores secrets **base64-encoded**
(plaintext-equivalent). At-rest protection is now provided by the **OpenBao substrate**
(below), not by the podman store.

> **Canonical references**
> - **Mechanism** (how secrets are stored, unsealed, synced, rotated): **htpc-mgmt ADR-007** — *substrate repo, Forgejo-private.*
> - **Boundary & decision** (this repo): [ADR-041](../decisions/2026-06-14-ADR-041-secrets-openbao-substrate-boundary.md) (supersedes [ADR-040](../decisions/2026-06-14-ADR-040-secrets-substrate-operator-boundary.md)).

---

## The model

```
OpenBao  (system service, htpc-mgmt-owned substrate; TPM-auto-unsealed; localhost TLS)
   │   source of truth for the ~30 runtime secrets
   ▼
root sync oneshot  →  podman secrets recreated in a TMPFS cache (ADR-028 store path)
   ▼
your containers consume them UNCHANGED via   Secret=<name>,type=env|mount,target=…
```

- OpenBao is **substrate**, not a workload — not a container, not a quadlet, not in the fleet.
  This repo never talks to it.
- The podman-secret cache is **tmpfs-only** (RAM; `zram` swap, never disk). The
  base64-on-unencrypted-pool leak (recoverable from a disposed disk) is closed by OpenBao's encrypted
  storage barrier.
- **Every `Secret=` handle is byte-for-byte unchanged.** Consumption is identical from each
  container's point of view — that is the entire point.

## The consumption contract (what this repo owns)

A service declares the secrets it needs in its quadlet. The secret **name** is the whole
interface between this repo and the substrate:

```ini
[Container]
# environment-variable injection (most services)
Secret=grafana_admin_password,type=env,target=GF_SECURITY_ADMIN_PASSWORD

# file mount (Authelia file://, the forgejo signing key, gathio, ha-prometheus-token)
Secret=forgejo_signing_key,type=mount,target=/run/secrets/forgejo_signing_key,uid=1000,gid=1000,mode=0600
```

- The name in `Secret=<name>` must exist in OpenBao and in htpc-mgmt's manifest. A **three-way
  consistency check** (OpenBao ↔ `grep Secret= quadlets/` ↔ manifest) catches drift.
- To see what a service consumes: `grep Secret= quadlets/<service>.container`.
- After editing a quadlet: `systemctl --user daemon-reload && systemctl --user restart <service>.service` (unchanged).

## Creating or rotating a secret

**Do this through the substrate, not here.** `podman secret rm/create` is **not** the
sanctioned path — it would diverge from OpenBao (the source of truth) and be overwritten at
the next sync/reboot.

- Create / rotate / list → htpc-mgmt's **`secretctl`** wrapper (see htpc-mgmt ADR-007).
- Rotation is **read-once at container start**, so rotating a secret means **restarting the
  consuming service**. Live per-lease dynamic credentials are a per-service opt-in, not the
  default.

## What is NOT here

Mechanism, secret values, AppRoles/policies, the unseal/TPM machinery, the ledger, and
DR/escrow all live in **htpc-mgmt (ADR-007)**. This repo deliberately holds only the
consumption-by-name contract — keeping secret topology off the GitHub-primary mirror.

## Honest scope

There is **no "LLM cannot read" wall**: an agent running as `patriark` can read secret values
out of the containers that consume them. Privilege separation is the only real wall and is
**deferred** (the OpenBao system-service shape seeds it — the agent cannot reach OpenBao
itself, only the consuming containers). See ADR-041 D5 and ADR-040's retained findings.

## Related

- [ADR-041](../decisions/2026-06-14-ADR-041-secrets-openbao-substrate-boundary.md) — workload-side boundary (current).
- [ADR-040](../decisions/2026-06-14-ADR-040-secrets-substrate-operator-boundary.md) — superseded; retained findings (file driver not encrypted, Vaultwarden not a broker, read-wall needs privilege separation).
- **htpc-mgmt ADR-007** — the OpenBao mechanism (substrate repo).
- [Security Audit Guide](./security-audit.md)
