# ADR-027: Forward-Only NOCOW Placement on subvol8-db (Policy)

**Date:** 2026-04-22
**Status:** Accepted
**Companion:** ADR-025 (deferred DB migration — unchanged)
**First tenant:** `unifi-syslog` (UDM Pro SIEM forensic log receiver)

## Context

ADR-025 designs a dedicated NOCOW subvolume (`/mnt/btrfs-pool/subvol8-db`) for write-hot, snapshot-hostile workloads, and defers the migration of five existing databases pending 60 days of measurements (earliest review 2026-06-18). That ADR remains in force for the deferred question it scopes.

During deployment of the UDM Pro SIEM syslog pipeline (2026-04-22), a net-new write-hot workload needed a storage home:

- `unifi-syslog` writes append-only log files at UDM event rate (tens to hundreds of entries per minute under normal load, higher under incidents).
- Keeping the write in `subvol7-containers` would inherit the same COW-in-snapshotted-subvol antipattern ADR-025 describes — growing extent counts on every write, every daily snapshot pinning more old extents.
- Placing it on `subvol8-db` is additive: the subvolume was already created as part of ADR-025's preparation work, and adding a greenfield tenant incurs none of the migration risk ADR-025 correctly insists on quantifying first.

The open ADR-025 question is about **migrating existing DBs** — risk-laden, reversibility-sensitive, measurement-gated. The placement question for **new workloads** is different: a greenfield write has no migration, no rollback artifact to protect, no service to stop. Deferring new NOCOW-candidate workloads to `subvol7-containers` "until ADR-025 resolves" would actively create more migration debt, not less.

This ADR separates the two questions and establishes a forward-only placement policy.

## Decision

**All new write-hot or snapshot-hostile workloads land on `/mnt/btrfs-pool/subvol8-db` from day one.** Existing workloads remain where they are; their migration remains the deferred question ADR-025 owns.

A workload qualifies as NOCOW-candidate if any of the following apply:

- **Append-only log streams** with sustained write rate (syslog receivers, audit trails, metric scrape targets not covered by a dedicated TSDB engine).
- **Database engines with built-in integrity checksumming** (PostgreSQL `data_checksums`, MariaDB/InnoDB, MongoDB/WiredTiger, Prometheus TSDB, Loki chunks).
- **Random-write patterns that fragment under COW** (B-tree rewrites, page updates, write-ahead logs).

A workload does **not** qualify and stays on `subvol7-containers` if:

- Writes are whole-file rewrites (Redis RDB snapshots, config files, image caches).
- Snapshot-based rollback is genuinely valuable (container configs, application state an operator wants to revert with `btrfs subvolume snapshot`).
- It's not meaningfully write-hot (low-rate, small-file workloads below any fragmentation threshold).

For the ambiguous middle, err toward `subvol7-containers` — the cost of "wrong" placement there is fragmentation only, which is exactly what ADR-025 is measuring anyway. The cost of "wrong" placement on `subvol8-db` is loss of snapshot rollback, which is harder to retrofit.

## Scope boundary with ADR-025

| Question | Owner |
|---|---|
| New workloads that meet NOCOW criteria | **This ADR** — land on `subvol8-db` |
| Existing DBs in `subvol7-containers` (5 services enumerated in ADR-025) | **ADR-025** — deferred until 2026-06-18 measurement review |
| Redis, Gathio redis, container configs, caches | Neither — stays on `subvol7-containers` by design |

ADR-025's acceptance criteria, migration procedure, and defensive tooling requirements are **unchanged**. If measurements on 2026-06-18 say "migrate," ADR-025's plan executes exactly as written. If they say "don't migrate," ADR-025 is withdrawn and the existing DBs stay on `subvol7-containers` — this ADR's forward-placement policy is unaffected either way.

## Baseline storage layout (after this ADR)

```
/mnt/btrfs-pool/subvol8-db/            [NOT in Urd snapshot set]
└── unifi-syslog/                      [root:root 0755; container uid 0 = host uid 1000]
    └── udm.log                        [syslog-ng output; rotated daily × 14 by logrotate]
```

Compression on the subvolume root: `btrfs property set ... compression none`. NOCOW via `chattr +C` was attempted and returned EINVAL on kernel 6.19 for reasons not yet traced; for the `unifi-syslog` tenant this is accepted because (a) the subvolume is not snapshotted, so there's no COW-amplification fight to win, and (b) append-only log writes are not the fragmentation-sensitive pattern NOCOW is most valuable for. Future DB tenants (if ADR-025 accepts migration) will need the flag to work; that's on ADR-025 to resolve.

## Integration requirements per new tenant

When adding a tenant to `subvol8-db`, the deploying change must:

1. **Create the per-service directory** under `/mnt/btrfs-pool/subvol8-db/<service>/` with ownership matching the container's effective host UID (typically `patriark:patriark` for rootless root-in-container; container subuid for LSIO PUID-mapped services).
2. **Bind-mount with `:Z`** in the quadlet per ADR-001.
3. **Not add the path to Urd's backup set.** `subvol8-db` is intentionally excluded from snapshots. If the tenant's data is operationally valuable (e.g., DBs), backup coverage is through application-level dumps (ADR-024 for DBs, tenant-specific for others). If the data is reconstructible (log streams, caches), no backup is needed — document that in the tenant's runbook.
4. **Document the tenant** in this ADR's first-tenant list below, with a one-liner on why it qualified and how backup (if any) is handled.

## Tenants

| Tenant | Added | Workload class | Backup |
|---|---|---|---|
| `unifi-syslog` | 2026-04-22 | Append-only UDP syslog receiver | None — forensic logs are replayable from UDM retention; 14-day logrotate locally |

This table is the living record. New tenants add a row; it does not require a new ADR unless the placement policy itself changes.

## Consequences

**Positive:**
- New write-hot workloads avoid the COW-in-snapshotted-subvol antipattern from day one, regardless of what ADR-025's measurements say for existing DBs.
- `subvol8-db` earns incremental load, giving real-world data on the subvolume's behavior before the (hypothetical) DB migration event needs to rely on it.
- The ADR boundary is clean: greenfield placement vs. migration of live services are distinct decisions with distinct risk profiles, handled by distinct ADRs.

**Negative:**
- `subvol8-db` now has live operational dependencies before ADR-025's measurement window closes. If ADR-025 is ultimately withdrawn ("don't migrate"), `subvol8-db` still persists — it has tenants. That's fine, but worth naming: ADR-027 locks in the subvolume as a permanent fixture independent of ADR-025's outcome.
- Tenants on `subvol8-db` have no filesystem-snapshot rollback path. The tenant table's "Backup" column must be explicit for every entry; "None" is an acceptable answer only when the data is genuinely reconstructible.

**Constraints:**
- No tenant may rely on snapshot rollback for recovery. If one needs it, it belongs on `subvol7-containers` and the write-hotness cost is accepted, not hidden.
- Adding a tenant does not require a new ADR, but does require updating the tenant table in this document and referencing the ADR in the tenant's deployment journal.

## Related

- **ADR-001:** Rootless containers and `:Z` SELinux labeling — unchanged.
- **ADR-019:** Filesystem permission model — the two-layer ACL pattern ADR-025 describes applies when DB tenants (with container subuid ownership) move in. For `unifi-syslog` (host-uid-owned), the simpler single-owner pattern suffices.
- **ADR-024:** Dump-based backup — not directly invoked by `unifi-syslog`, but the mechanism DB tenants will use when/if they migrate.
- **ADR-025:** Deferred DB migration — this ADR does **not** change its deferral. That ADR's measurement window and 2026-06-18 review date stand.
- **Journal:** `docs/98-journals/2026-04-22-udm-pro-siem-syslog-pipeline.md` — first deployment to exercise this policy.
