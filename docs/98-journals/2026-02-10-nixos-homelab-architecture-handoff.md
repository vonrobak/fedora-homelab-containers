# NixOS Homelab Architecture: Engineering Handoff

**Date:** 2026-02-10
**Author:** Claude Opus 4.6
**Status:** Architecture defined. Ready for implementation in a new session.
**Purpose:** Complete handoff document for a Claude Code session to build a NixOS-based homelab configuration from scratch.

---

## Why NixOS

The current homelab runs on Fedora Workstation 43 with 27 Podman containers managed via systemd quadlets. An Ansible playbook was built for disaster recovery (`/home/patriark/homelab-ansible/`). During that build, a fundamental insight emerged: **the Ansible playbook exists because the system's state is hard to reproduce.** A declarative system like NixOS eliminates the need for a convergence tool entirely -- the system definition IS the running state.

### Key advantages over current architecture

1. **No configuration drift by construction** -- The running system is the declaration. No gap between intended and actual state.
2. **The Ansible layer disappears** -- No Jinja2 templating, no task ordering, no handler notifications. NixOS module system handles dependency resolution.
3. **Atomic rollbacks** -- Every `nixos-rebuild switch` creates a bootable generation. Roll back in seconds, not hours.
4. **Reproducible builds** -- Nix flakes with pinned inputs guarantee identical systems across builds.
5. **Test before deploy** -- `nixos-rebuild build-vm` validates the entire configuration in a VM before applying.

---

## Current State Reference

### Hardware Target: fedora-htpc (192.168.1.70)

- **CPU:** AMD Ryzen 5 5600G (6 cores / 12 threads, 65W) with Radeon Vega iGPU (no compute capability)
- **RAM:** 30.7GB DDR4
- **Storage:**
  - System SSD: 119.2GB BTRFS NVMe (62% used)
  - BTRFS pool: 14.55 TiB across 4x 3.6TB drives (RAID1 metadata, 74% used, 3.67TiB free)
  - External backup: 16.4TiB WD-18TB (LUKS encrypted)
- **Network:** 1Gbps to UDM Pro gateway (192.168.1.1)
- **OS:** Fedora Workstation 43 (target: NixOS)

### Domain and Services

- **Domain:** patriark.org (Cloudflare DNS)
- **Port forwarding:** 80/443 TCP to 192.168.1.70
- **Pi-hole DNS:** 192.168.1.69 (Raspberry Pi 4, stays as-is)

**Subdomains:**

| Subdomain | Service | Auth |
|-----------|---------|------|
| home.patriark.org | Homepage dashboard | Authelia |
| sso.patriark.org | Authelia SSO | Self |
| vault.patriark.org | Vaultwarden | Native |
| traefik.patriark.org | Traefik dashboard | Authelia |
| jellyfin.patriark.org | Jellyfin media | Native |
| photos.patriark.org | Immich photos | Native |
| nextcloud.patriark.org | Nextcloud files | Native |
| grafana.patriark.org | Grafana monitoring | Authelia |
| prometheus.patriark.org | Prometheus metrics | Authelia |
| loki.patriark.org | Loki logs | Authelia |
| events.patriark.org | Gathio events | Authelia (partial) |
| ha.patriark.org | Home Assistant | Native |

### Current Container Inventory (27 containers, 13 service groups)

**Core Infrastructure:**
- Traefik (reverse proxy, Let's Encrypt, CrowdSec plugin)
- CrowdSec (threat intelligence engine)
- Authelia + Redis (SSO with YubiKey/WebAuthn MFA)

**Applications:**
- Nextcloud + MariaDB + Redis (file sync)
- Immich Server + ML + PostgreSQL + Redis (photos, v2.5.5 pinned)
- Jellyfin (media server, VAAPI hardware transcoding via iGPU)
- Vaultwarden (passwords)
- Gathio + MongoDB (events)
- Homepage (dashboard)
- Home Assistant + Matter Server (smart home)

**Monitoring:**
- Prometheus, Grafana, Loki, Alertmanager, Promtail, cAdvisor, Node Exporter, UnPoller

**Automation:**
- alert-discord-relay (custom-built)
- 53 systemd timers (daily docs, OODA loop, predictive maintenance, backups, etc.)

### Network Topology (8 Podman networks)

| Network | Subnet | Purpose |
|---------|--------|---------|
| reverse_proxy | 10.89.2.0/24 | Internet-facing + Traefik |
| monitoring | 10.89.4.0/24 | Prometheus, Grafana, exporters |
| auth_services | 10.89.3.0/24 | Authelia + Redis (internal) |
| media_services | 10.89.1.0/24 | Jellyfin |
| photos | 10.89.5.0/24 | Immich stack |
| nextcloud | 10.89.10.0/24 | Nextcloud + MariaDB + Redis |
| home_automation | 10.89.6.0/24 | HA + Matter |
| gathio | 10.89.7.0/24 | Gathio + MongoDB |

### Secrets Required

All secrets currently managed via Podman secrets + Ansible Vault. The full list with structure is documented in `/home/patriark/homelab-ansible/vault/secrets.yml.example`. Key secrets:

- Authelia: JWT secret, session secret, storage encryption key, OIDC HMAC
- Database passwords: MariaDB (Nextcloud), PostgreSQL (Immich), MongoDB (Gathio)
- API tokens: CrowdSec bouncer key, Home Assistant Prometheus token, UnPoller credentials
- Let's Encrypt: ACME account (auto-generated, stored in acme.json)
- Vaultwarden: Admin token
- Immich: Database password
- Discord: Webhook URLs for alert channels

### Production Configs Location

All configs are in `/home/patriark/containers/config/`:
- `traefik/` -- Static config, dynamic routers/middleware/TLS
- `authelia/` -- Configuration, user database
- `prometheus/` -- Scrape config, 9 alert rule files, 5 recording rule files
- `grafana/provisioning/` -- Datasources, 13 dashboard JSONs
- `loki/` -- Retention, schema, ingestion config
- `promtail/` -- Journal scraping, Traefik access log parsing
- `alertmanager/` -- Routes, Discord/webhook receivers
- `home-assistant/` -- configuration.yaml, 1400 lines of automations
- `homepage/` -- Dashboard widgets, bookmarks, services
- `gathio/` -- config.toml
- `unpoller/` -- up.conf
- `vaultwarden/` -- env template

Private details in `/home/patriark/containers/secrets/identity/`:
- `homelab-identity.yml` -- domain, subdomains, auth hardware, GitHub
- `network-inventory.yml` -- all hardware, devices, VLANs, capabilities
- `GUIDE.md` -- parsing guide

---

## Proposed NixOS Architecture

### Design Principles

1. **Single flake, single source of truth** -- The entire system described in one Nix flake
2. **Native services where possible** -- Traefik, CrowdSec, monitoring agents as NixOS services, not containers
3. **OCI containers for applications** -- Nextcloud, Immich, Jellyfin, etc. stay as containers (upstream doesn't provide Nix packages)
4. **sops-nix for secrets** -- Age-encrypted secrets committed to git, decrypted at activation time
5. **Fewer moving parts** -- Target ~18-20 containers (down from 27) by converting infrastructure to native services
6. **Same security model** -- Traefik + CrowdSec + Authelia + YubiKey MFA, same middleware chain

### What Becomes a Native NixOS Service

| Current Container | NixOS Equivalent | Rationale |
|---|---|---|
| Node Exporter | `services.prometheus.exporters.node` | First-class NixOS module, deeper host visibility |
| cAdvisor | `services.prometheus.exporters.cadvisor` or native systemd metrics | Container-aware by default |
| Promtail | `services.promtail` or direct journal → Loki | NixOS has native journal forwarding options |
| CrowdSec | `services.crowdsec` (community module) or systemd service | Runs better with host-level access |
| UnPoller | Native service (Go binary) | Simple binary, no container needed |

### What Stays as OCI Container

| Service | Reason |
|---------|--------|
| Nextcloud + MariaDB + Redis | Complex PHP app, upstream container is the supported deployment |
| Immich Server + ML + PostgreSQL + Redis | Tightly coupled multi-container stack, pinned version |
| Jellyfin | Media server with transcoding, container is standard deployment |
| Vaultwarden | Rust binary in container, well-tested upstream image |
| Gathio + MongoDB | Node.js app + MongoDB, container is simplest |
| Homepage | Dashboard container, minimal |
| Home Assistant + Matter Server | Complex Python app with hardware integrations |
| Traefik | Could be native, but container deployment allows CrowdSec plugin which is loaded at runtime |
| Authelia + Redis | Could be native, but container is simpler for the OIDC/WebAuthn stack |
| Prometheus | Could be native, but container deployment matches upstream docs |
| Grafana | Container is standard deployment |
| Loki | Container is standard deployment |
| Alertmanager | Container is standard deployment |
| alert-discord-relay | Custom-built, stays as container |

**Revised assessment:** After careful consideration, most services should remain as containers even on NixOS. The real wins from NixOS are:

1. **System-level declaration** -- firewall, storage, users, mounts, kernel params
2. **Atomic rollbacks** for the host OS
3. **Reproducible system builds** -- no Ansible needed
4. **Native exporters** (Node Exporter, potentially cAdvisor) for deeper host metrics
5. **sops-nix** for proper secret management
6. **Single-file system definition** instead of 141 Ansible files

The container count drops modestly (27 → ~23-24) but the architectural improvement is in how those containers are declared and managed.

### Network Simplification

Reduce from 8 networks to 4:

| Network | Subnet | Services | Rationale |
|---------|--------|----------|-----------|
| frontend | 10.89.2.0/24 | Traefik, all services needing reverse proxy | Single ingress network |
| backend | 10.89.3.0/24 | Inter-service communication (databases, Redis, internal APIs) | Trust boundary: no external access |
| monitoring | 10.89.4.0/24 | Prometheus, Grafana, Loki, Alertmanager, exporters | Isolated metrics plane |
| iot_bridge | 10.89.6.0/24 | Home Assistant + Matter Server | IoT VLAN bridge |

**Why fewer networks:** The 8-network design exists because Podman's flat networking requires explicit segmentation. With NixOS firewall rules per-container (via `nftables`), you can achieve the same isolation with fewer networks. The current design has networks where only 1-2 containers exist (media_services has only Jellyfin, gathio has only 2 containers). Consolidating to 4 networks reduces DNS complexity and the static IP management burden (ADR-018 exists because of 8-network aardvark-dns issues).

### Secret Management: sops-nix

Replace Podman secrets + Ansible Vault with sops-nix:

```nix
# secrets/secrets.yaml (committed to git, age-encrypted)
authelia_jwt_secret: ENC[AES256_GCM,data:...,type:str]
nextcloud_db_password: ENC[AES256_GCM,data:...,type:str]
# ... all secrets here

# In configuration.nix
sops.secrets."authelia_jwt_secret" = {
  sopsFile = ./secrets/secrets.yaml;
  owner = "authelia";
};
# Secret available at /run/secrets/authelia_jwt_secret
```

**Advantages over current approach:**
- Secrets in git (encrypted) -- no separate vault file to manage
- Decrypted at activation time only -- never stored in plaintext on disk
- Per-secret ownership and permissions
- age key on YubiKey or host SSH key for decryption

### Storage Configuration

```nix
# BTRFS pool mount (declarative fstab)
fileSystems."/mnt/btrfs-pool" = {
  device = "/dev/sdc";  # Parameterize per host
  fsType = "btrfs";
  options = [ "compress=zstd:1" "space_cache=v2" "autodefrag" "commit=120" ];
};

# Subvolume structure created via activation script
system.activationScripts.btrfsSubvolumes = ''
  for vol in subvol1-docs subvol2-media subvol3-photos subvol4-sensitive \
             subvol5-music subvol6-tmp subvol7-containers; do
    btrfs subvolume create /mnt/btrfs-pool/$vol 2>/dev/null || true
  done
  # NOCOW for databases
  for dir in prometheus loki postgresql-immich; do
    mkdir -p /mnt/btrfs-pool/subvol7-containers/$dir
    chattr +C /mnt/btrfs-pool/subvol7-containers/$dir 2>/dev/null || true
  done
'';
```

---

## Proposed Repository Structure

```
homelab-nixos/
  flake.nix                       # Entry point: inputs, outputs, system config
  flake.lock                      # Pinned dependency versions

  hosts/
    fedora-htpc/                  # Per-host configuration
      default.nix                 # Host-specific: hardware, storage, boot
      hardware-configuration.nix  # Auto-generated by nixos-generate-config

  modules/
    networking.nix                # Firewall, Podman networks, DNS
    storage.nix                   # BTRFS mounts, subvolumes, NOCOW
    users.nix                     # User accounts, SSH keys, linger

    containers/
      traefik.nix                 # Traefik container + config files
      authelia.nix                # Authelia + Redis containers
      crowdsec.nix                # CrowdSec container
      nextcloud.nix               # Nextcloud + MariaDB + Redis
      immich.nix                  # Immich + PostgreSQL + Redis + ML
      jellyfin.nix                # Jellyfin (conditional GPU)
      vaultwarden.nix             # Vaultwarden
      gathio.nix                  # Gathio + MongoDB
      homepage.nix                # Homepage dashboard
      home-assistant.nix          # HA + Matter Server
      monitoring.nix              # Prometheus, Grafana, Loki, Alertmanager

    services/
      node-exporter.nix           # Native NixOS service
      promtail.nix                # Native or container (evaluate)

    automation/
      timers.nix                  # systemd timers (docs, OODA, backups)

  configs/
    traefik/                      # Static files (routers.yml, middleware.yml, etc.)
    authelia/                     # Configuration templates
    prometheus/
      alerts/                     # Alert rules (static YAML)
      rules/                      # Recording rules
    grafana/
      dashboards/                 # 13 dashboard JSONs
    alertmanager/                 # Alert routing config
    loki/                         # Loki config
    home-assistant/               # HA config (automations, etc.)
    homepage/                     # Dashboard config

  secrets/
    secrets.yaml                  # sops-encrypted secrets
    .sops.yaml                    # sops configuration (age keys)

  scripts/                        # Operational scripts (adapted for NixOS)

  README.md
```

### Key Module Pattern

Each container module follows this pattern:

```nix
# modules/containers/nextcloud.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.nextcloud;
in {
  options.homelab.services.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud file sync";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud.${config.homelab.domain}";
    };
    # ... other options
  };

  config = lib.mkIf cfg.enable {
    # Container definitions
    virtualisation.oci-containers.containers.nextcloud = { ... };
    virtualisation.oci-containers.containers.nextcloud-db = { ... };
    virtualisation.oci-containers.containers.nextcloud-redis = { ... };

    # Config file deployment
    environment.etc."homelab/nextcloud/...".source = ...;

    # Traefik route (contributed to shared config)
    homelab.traefik.routes.nextcloud = { ... };
  };
}
```

The service toggle is just `homelab.services.nextcloud.enable = true;` in the host config. NixOS module system handles the rest -- if Nextcloud is disabled, its containers, configs, routes, and Prometheus scrape targets all disappear automatically.

---

## What to Omit (Complexity vs. Value)

### Skip for initial NixOS build

| Feature | Current Implementation | Why Skip |
|---------|----------------------|----------|
| OODA autonomous loop | 4 scripts + 2 timers + webhook receiver | High complexity, requires remediation framework that's tightly coupled to the current system. Add later once base is stable. |
| Autonomous predictive maintenance | Resource forecasting scripts | Depends on historical Prometheus data that won't exist on fresh install |
| alert-discord-relay | Custom Go/Python service | Rebuild after core monitoring works |
| Config drift detection | `check-drift.sh` | NixOS eliminates drift by construction |
| Security audit script | `security-audit.sh` (40+ checks) | Many checks are Fedora-specific. Write NixOS-native equivalent later. |
| SLO recording rules | 5 complex PromQL rule files | Copy as-is once Prometheus is running, but don't block on them |
| 53 systemd timers | Various automation | Start with essential timers only (backups, doc generation). Add others incrementally. |

### Keep for initial NixOS build (core value)

| Feature | Priority | Notes |
|---------|----------|-------|
| All 12 services (subdomains) | Must have | This is the homelab |
| Traefik + Let's Encrypt | Must have | Internet access to services |
| CrowdSec + Authelia + YubiKey | Must have | Security is non-negotiable |
| Prometheus + Grafana + Loki | Must have | Observability |
| Alertmanager + Discord | Should have | Alert routing |
| Alert rules (9 files) | Should have | Copy from production |
| Grafana dashboards (13) | Should have | Copy from production |
| BTRFS storage + NOCOW | Must have | Data integrity |
| Backup timers | Must have | Essential automation |
| Home Assistant automations | Must have | Copy 1400-line automations.yaml as-is |

---

## Implementation Plan

### Phase 0: NixOS Installation (manual, ~1 hour)

1. Download NixOS minimal ISO
2. Boot fedora-htpc from USB (keep current install on SSD until verified)
   - Option A: Install to separate drive/partition for safe testing
   - Option B: Install to VM first for validation, then bare metal
3. Run `nixos-generate-config` to produce `hardware-configuration.nix`
4. Set up initial flake with basic system (boot, networking, SSH, user account)
5. Verify SSH access from MacBook Air

### Phase 1: System Foundation (~30 files)

- Flake structure with host-specific config
- BTRFS storage mounts and subvolume creation
- Firewall (ports 80, 443, 8096/tcp, 7359/udp)
- User account with linger, SSH keys, subuid/subgid
- Podman rootless enabled
- sops-nix configured with age key
- **Testable:** SSH in, `podman run hello-world` works

### Phase 2: Networking + Core Infrastructure (~15 files)

- 4 Podman networks defined
- Traefik container with static + dynamic config
- CrowdSec container
- Authelia + Redis containers
- Let's Encrypt certificate provisioning
- **Testable:** `https://traefik.patriark.org` shows dashboard behind Authelia

### Phase 3: Applications (~20 files)

- Nextcloud + MariaDB + Redis
- Immich + PostgreSQL + Redis + ML (v2.5.5 pinned)
- Jellyfin (with VAAPI GPU passthrough)
- Vaultwarden
- Gathio + MongoDB
- Homepage
- Home Assistant + Matter Server
- **Testable:** All 12 subdomains responding, services functional

### Phase 4: Monitoring (~15 files)

- Prometheus + scrape targets for all enabled services
- Grafana + datasources + 13 dashboards
- Loki + retention config
- Alertmanager + Discord routes
- Node Exporter (native NixOS service)
- Promtail or journal → Loki forwarding
- Alert rules (copy 9 files) + recording rules (copy 5 files)
- **Testable:** Grafana dashboards populated, Prometheus targets all UP

### Phase 5: Essential Automation (~5 files)

- Backup timers (BTRFS snapshots, config backup)
- Auto-doc generation timer
- System update timer (`nixos-rebuild switch` equivalent of update-before-reboot)
- **Testable:** Timers listed in `systemctl list-timers`

---

## Migration Strategy

**Recommended: Parallel run, then cutover.**

1. Install NixOS to a separate drive or the same drive with a separate partition (BTRFS makes this easy with subvolumes)
2. Build and validate each phase against the VM or second boot entry
3. Once all services verified, migrate data:
   - BTRFS pool is shared (just mount it in NixOS config)
   - Application data lives on the pool, not the system SSD
   - Copy Let's Encrypt `acme.json` to new Traefik data dir
   - Recreate Podman secrets from sops-nix decrypted values
4. Update DNS/port forwarding if IP changes
5. Keep Fedora boot entry for 2 weeks as fallback

**Data that lives on the BTRFS pool (survives OS reinstall):**
- All media (Jellyfin, Nextcloud, Immich photos)
- Databases (PostgreSQL, MariaDB, MongoDB, SQLite)
- Prometheus metrics, Loki logs
- Home Assistant config and automations
- Container configs and state

**Data that must be recreated:**
- Podman secrets (from sops-nix)
- Let's Encrypt certificates (copy acme.json or re-issue)
- CrowdSec CAPI registration
- Systemd quadlet symlinks (handled by NixOS container definitions)

---

## Reference Commands for the Implementing Session

```bash
# Read current production configs
ls ~/containers/config/                              # All service configs
ls ~/containers/quadlets/                            # All container definitions
cat ~/containers/config/traefik/dynamic/routers.yml  # All routes

# Read identity/network info
cat ~/containers/secrets/identity/homelab-identity.yml
cat ~/containers/secrets/identity/network-inventory.yml

# Read the Ansible playbook for parameterized versions of everything
ls ~/homelab-ansible/roles/                          # 17 roles
cat ~/homelab-ansible/inventory/group_vars/all/services.yml  # All service params
cat ~/homelab-ansible/inventory/group_vars/all/networks.yml  # Network params
cat ~/homelab-ansible/vault/secrets.yml.example      # Secret structure

# Current system state
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"
podman network ls
systemctl --user list-units --type=service --state=running
```

---

## Key Gotchas to Carry Forward

These are hard-won lessons from the current homelab that must be preserved in the NixOS build:

1. **First Network= line gets default route** -- still applies to Podman on NixOS
2. **`:Z` SELinux labels on all bind mounts** -- NixOS can run SELinux but defaults to AppArmor; decide enforcement model
3. **BTRFS NOCOW for databases** -- still required for PostgreSQL, Prometheus, Loki, MariaDB, MongoDB
4. **Static IPs for multi-network containers** -- aardvark-dns ordering is a Podman issue, not Fedora-specific
5. **Traefik readTimeout: 600s** -- default 60s breaks large uploads (Immich, Nextcloud)
6. **No circuit breaker on Immich** -- ECONNRESET from clients triggers it incorrectly
7. **No retry middleware on upload routes** -- can't replay streamed uploads
8. **immich-ml 300s inactivity timeout** -- causes worker recycling and transient failures
9. **Immich pinned to v2.5.5** -- tight coupling between server, ML, and PostgreSQL extensions
10. **Nextcloud rate limits: 600/min, 3000 burst** -- needed for WebDAV PROPFIND tree-walking
11. **Home Assistant trusted_proxies: 10.89.2.0/24** -- must match Traefik's network subnet

---

## Success Criteria

The NixOS build is complete when:

- [ ] All 12 subdomains responding with valid TLS
- [ ] Authelia SSO working with YubiKey WebAuthn
- [ ] CrowdSec blocking malicious IPs
- [ ] Nextcloud sync working on all devices (iPhone, iPad, MacBook, Gaming PC)
- [ ] Immich accessible with existing photo library (254GB, 10,608 assets)
- [ ] Jellyfin streaming with VAAPI hardware transcoding
- [ ] Home Assistant controlling Hue lights and Roborock vacuum
- [ ] Prometheus scraping all targets, Grafana dashboards populated
- [ ] Alertmanager sending to Discord on test alert
- [ ] `nixos-rebuild switch` completes cleanly (full system rebuild)
- [ ] `nixos-rebuild switch --rollback` returns to previous generation
- [ ] BTRFS pool mounted with NOCOW on database directories
- [ ] Backup timers running
- [ ] System can be rebuilt from `flake.nix` + `secrets.yaml` + BTRFS pool data
