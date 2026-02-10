# Ansible Disaster Recovery Playbook for Fedora Silverblue

**Date:** 2026-02-10
**Author:** Claude Opus 4.6
**Status:** Complete. Repository pushed to GitHub (private).

---

## Summary

Built a complete Ansible playbook that can reproduce the entire homelab from scratch on a fresh Fedora Silverblue installation. The playbook captures all 27 containers, 13 service groups, 8 networks, monitoring stack, security layers, and automation timers as parameterized Jinja2 templates with service-group toggles.

**Repository:** `https://github.com/vonrobak/homelab-ansible` (private)
**Location on disk:** `/home/patriark/homelab-ansible/`

---

## What Was Built

### Scale

- **141 files** committed (159 on disk, 18 gitignored)
- **49 Jinja2 templates** -- every container quadlet and config file
- **74 YAML files** -- inventory, tasks, handlers, defaults, playbooks
- **13 Grafana dashboard JSONs** -- full dashboard set copied from production
- **9 Prometheus alert rule files** + **5 recording rule files**
- **5 playbooks** -- site, bootstrap, deploy, verify, update
- **17 roles** across 7 deployment phases

### Architecture

```
Phase 1: System Bootstrap (requires sudo)
  roles/system-base      -- rpm-ostree packages, firewall, linger, SELinux
  roles/btrfs-storage    -- BTRFS mount, subvolumes, NOCOW directories

Phase 2: Podman Infrastructure
  roles/podman-networks  -- 8 network definitions
  roles/podman-secrets   -- All secrets from Ansible Vault

Phase 3: Core Infrastructure
  roles/traefik          -- Reverse proxy + static/dynamic config
  roles/crowdsec         -- Security engine
  roles/authelia         -- SSO + Redis session store

Phase 4: Applications (each toggleable)
  roles/nextcloud        -- Nextcloud + MariaDB + Redis
  roles/immich           -- Immich + PostgreSQL + Redis + ML
  roles/jellyfin         -- Media server (conditional GPU passthrough)
  roles/vaultwarden      -- Password manager
  roles/gathio           -- Events + MongoDB
  roles/homepage         -- Dashboard
  roles/home-assistant   -- HA + Matter Server

Phase 5: Monitoring
  roles/monitoring       -- All 8 monitoring containers as one role

Phase 6: Automation
  roles/automation       -- Scripts + systemd timers (Silverblue-adapted)

Phase 7: Verification
  roles/verification     -- Health checks + routing verification + report
```

### Key Design Decisions

**Service toggles** -- Every service group has `services.<name>.enabled` in inventory. Disabling a service cascades through Traefik routes, Prometheus scrape targets, verification lists, and monitoring configs via Jinja2 conditionals.

**Parameterized everything** -- IPs, memory limits, images, hostnames, domains all live in `inventory/group_vars/all/services.yml`. Host-specific overrides (GPU passthrough, storage paths, BTRFS device) go in `inventory/host_vars/`.

**Silverblue adaptations** -- Only two packages need layering (`git`, `jq`). Update script uses `rpm-ostree upgrade` instead of `dnf update`. BTRFS tools are pre-installed.

**Secrets via Ansible Vault** -- All passwords, API keys, and tokens in `vault/secrets.yml`. Vault structure documented in `vault/secrets.yml.example`.

### Verification

All 5 playbooks pass `ansible-playbook --syntax-check`:
- `playbooks/site.yml` -- Full deployment (all phases)
- `playbooks/bootstrap.yml` -- Phase 1 only (system-level, needs reboot)
- `playbooks/deploy.yml` -- Phases 2-6 (user-level, no reboot)
- `playbooks/verify.yml` -- Phase 7 only
- `playbooks/update.yml` -- Rolling container image updates

### What's Not Covered

- **alert-discord-relay** -- Uses a localhost-built image, not templated
- **Homepage widget configs** -- API keys and service-specific YAML (services.yaml, bookmarks.yaml) need manual configuration after deployment
- **Home Assistant automations** -- 1,400 lines of automations are user-specific and evolve through the UI, not suitable for static templating
- **CrowdSec CAPI registration** -- Requires manual `cscli capi register` after first boot
- **Data restoration** -- Playbook rebuilds infrastructure, not data. BTRFS snapshots or rsync needed for databases, media, photos

---

## Process Notes

The build took one extended Claude Code session. Production configs were gathered by 4 parallel exploration agents reading all quadlet files, Traefik configs, Authelia settings, Prometheus/Grafana/Loki configs, and service-specific files. Templates were generated from those production references with parameterization.

Two issues were caught during syntax checking:
1. Empty `vault_password_file =` in ansible.cfg caused Ansible to interpret the project directory as a vault file -- fixed by commenting it out
2. Verification role had `set_fact` task at bottom of file but variables were needed earlier -- fixed by reordering

---

## Reflections

The Ansible playbook is a solid disaster recovery tool. It captures the "what" of the homelab comprehensively. However, building it surfaced a deeper architectural question: the playbook exists because the system's state is hard to reproduce. A truly declarative system (like NixOS) wouldn't need a separate convergence tool -- the system definition would BE the running state.

This insight led to a separate exploration of what a from-scratch NixOS rebuild would look like. See the companion journal entry: `2026-02-10-nixos-homelab-architecture-handoff.md`.
