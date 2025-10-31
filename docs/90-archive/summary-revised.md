# Homelab System Summary (Revised)

**Date:** 2025-10-21  
**Host:** `fedora-htpc`  
**Purpose:** Secure, rootless, educational homelab for service orchestration and modern identity management.

---

## 1. System Overview

| Component | Version | Notes |
|------------|----------|-------|
| **OS** | Fedora Linux 42 (Workstation) | SELinux enforcing |
| **Kernel** | 6.16.12-200.fc42.x86_64 | Up 2 days |
| **Container Engine** | Podman 5.6.2 (rootless) | Systemd Quadlets |
| **Firewall** | firewalld active | Zone: FedoraWorkstation |
| **DNS** | Pi-hole @ 192.168.1.69 | `.lokal` domain |
| **Host IP** | 192.168.1.70 | Default route via 192.168.1.1 |
| **Ports open** | 80, 443, 8096, 7359 | 8080 (admin) |

---

## 2. Active Containers

| Service | Image | Ports | Networks | Status |
|----------|--------|--------|-----------|--------|
| **Traefik** | `docker.io/library/traefik:v3.2` | 80,443,8080 | `reverse_proxy` | ✅ Running |
| **Authelia** | `docker.io/authelia/authelia:latest` | 9091 | `auth_services`, `reverse_proxy` | ✅ Running (healthy) |
| **Authelia-Redis** | `docker.io/library/redis:7-alpine` | 6379 | `auth_services` | ✅ Running |
| **Jellyfin** | `docker.io/jellyfin/jellyfin:latest` | 8096/tcp, 7359/udp | `media_services`, `reverse_proxy` | ✅ Running (healthy) |

---

## 3. Network Architecture

| Network | CIDR | Purpose | DNS | Containers |
|----------|------|----------|------|-------------|
| **reverse_proxy** | 10.89.2.0/24 | Ingress routing (Traefik ⇄ services) | ✓ Pi-hole | traefik, jellyfin, authelia |
| **media_services** | 10.89.1.0/24 | Internal media | ✓ Pi-hole | jellyfin |
| **auth_services** | 10.89.3.0/24 | Authentication + Redis | ✓ Pi-hole | authelia, redis |
| **web_services** | 10.89.0.0/24 | Reserved for web apps | ✓ Pi-hole | (empty) |

**Design principle:** Each functional group has its own isolated bridge network, minimizing broadcast scope and exposure.

UDM Pro has four VLANs as well as a Wireguard subnet
VLAN1 - 192.168.1.0/24 # Default
VLAN2 - 192.168.2.0/24 # IoT
VLAN3 - 192.168.3.0/24 # NoT
VLAN4 - 192.168.99.0/24 # Guest
Wireguard - 192.168.100.1/24    # Not fully configured. The user wants to configure connection through his public domain in such a way that when connected remotely through wireguard, the user can talk to self-hosted services on the fedora-htpc server at 192.168.1.70/*.patriark.lokal in a secure way

All VLANs except Wireguard uses pihole for DNS with specific firewall rules. In future Wireguard subnet should also be able to use pihole + unbound for dns

Of particular interest for the future is advanced zone based firewall segmentation of VLANs on UDM Pro and possibly making a dedicated VLAN for self-hosted services and/or DMZ for web-exposed servers

---

## 4. Security Posture

| Control | Status | Comment |
|----------|---------|----------|
| Rootless containers | ✅ | Non-root Podman setup |
| SELinux enforcing | ✅ | Context-level isolation |
| Network segmentation | ✅ | Three functional bridges |
| MFA (TOTP + YubiKey) | ✅ | Tested via Authelia |
| Rate limiting / session protection | ✅ | Configured |
| Valid TLS certificates | ⚠️ Self-signed | Next milestone |
| Email notifications | ❌ | SMTP not configured |
| Monitoring / alerting | ❌ | Planned (Week 3) |
| Tested backups | ❌ | Planned (Restic) |
| Intrusion detection | ❌ | Falco/Auditd candidates |
| Secrets management | ⚠️ File-based | Move to environment variables |

**Score:** 7 / 13 → *Functional but not internet-ready.*

---

## 5. Known Issues

1. **Authelia login loop** – Cookie/session mismatch under self-signed TLS.  
   → Fix after valid certs.  
2. **Redis secret hardcoded** – Replace with env var injection.  
3. **Self-signed certificates** – Block WebAuthn & cause UX friction.  
4. **Monitoring missing** – No proactive alerting.  
5. **Firewall zone mixing** – Review before exposing ports 80/443.

---

## 6. Upcoming Learning & Build Plan

### 🗓 Week 2 — *Security & Identity Hardening*
- [ ] Automate Let’s Encrypt via Traefik ACME (Hostinger DNS).
- [ ] Configure SMTP notifications in Authelia.
- [ ] Validate WebAuthn with all three YubiKeys.
- [ ] Introduce Restic-based backup/restore tests.
- [ ] Write first threat model document.

### 🗓 Week 3 — *Observability & Resilience*
- [ ] Deploy Prometheus + Grafana dashboards.
- [ ] Add Loki + Promtail for logs.
- [ ] Establish alert rules (disk space, container restarts).
- [ ] Evaluate Podman auto-update behavior in production.

### 🗓 Week 4 — *Internet Exposure Simulation*
- [ ] Configure Cloudflare or Hostinger public DNS.
- [ ] Expose Traefik with TLS termination.
- [ ] Conduct penetration-style self-audit (headers, CSP, CORS).
- [ ] Document backup and recovery drills.

---

## 7. Hardware Tokens & MFA

| Key | Model | Serial | Purpose |
|-----|--------|--------|----------|
| YubiKey #1 | 5C NFC | 17735753 | Primary |
| YubiKey #2 | 5 NFC | 16173971 | Backup |
| YubiKey #3 | 5Ci | 11187313 | Spare (off-site) |

✅ FIDO2 + TOTP enabled  
🔒 PINs set, rotation schedule defined

---

## 8. Storage Architecture

/ # btrfs-subvolume

/home # btrfs-subvolume

/home/patriark/containers/
➜  ~ ls -la ~/containers
drwxr-xr-x. 1 patriark patriark 114 okt.  21 16:55 backups
lrwxrwxrwx. 1 patriark patriark  43 okt.  19 12:15 cache -> /mnt/btrfs-pool/subvol6-tmp/container-cache
drwxr-xr-x. 1 patriark patriark 100 okt.  20 16:25 config
drwxr-xr-x. 1 patriark patriark 104 okt.  19 12:15 data
drwxr-xr-x. 1 patriark patriark 116 okt.  22 12:54 docs
lrwxrwxrwx. 1 patriark patriark  41 okt.  20 12:33 quadlets -> /home/patriark/.config/containers/systemd
drwxr-xr-x. 1 patriark patriark 990 okt.  21 22:18 scripts
drwx------. 1 patriark patriark  56 okt.  20 18:45 secrets
➜  ~ ls -la ~/containers/data
drwxr-xr-x. 1 patriark patriark   0 okt.  19 11:39 jellyfin
drwxr-xr-x. 1 patriark patriark   0 okt.  19 11:39 monitoring
drwxr-xr-x. 1 patriark patriark   0 okt.  19 11:39 nextcloud
lrwxrwxrwx. 1 patriark patriark  34 okt.  19 12:15 subvol7-containers -> /mnt/btrfs-pool/subvol7-containers
drwxr-xr-x. 1 patriark patriark   0 okt.  19 11:39 traefik
➜  ~ tree ~/containers/docs
/home/patriark/containers/docs
├── 00-foundation
│   ├── day01-learnings.md
│   ├── day02-networking.md
│   ├── day03-pod-commands.md
│   ├── day03-pods.md
│   └── day03-pods-vs-containers.md
├── 10-services
│   ├── day04-jellyfin-final.md
│   ├── day06-complete.md
│   ├── day06-quadlet-success.md
│   ├── day06-traefik-routing.md
│   ├── day07-yubikey-inventory.md
│   └── quadlets-vs-generated.md
├── 20-operations
│   ├── progress.md
│   ├── quick-reference.bak-20251021-172023.md
│   ├── quick-reference.bak-20251021-221915.md
│   ├── quick-reference.md
│   ├── quick-reference-v2.md
│   ├── readme.bak-20251021-172023.md
│   ├── readme.bak-20251021-221915.md
│   ├── readme.md
│   ├── revised-learning-plan.md
│   ├── storage-layout.md
│   ├── summary-revised.md
│   └── week02-security-and-tls.md
├── 30-security
└── 99-reports
    ├── authelia-diag-20251020-183321.txt
    ├── homelab-diagnose-20251021-165859.txt
    ├── latest-summary.md
    └── organize-docs.sh
➜  ~ ls -la ~/containers/quadlets 
lrwxrwxrwx. 1 patriark patriark 41 okt.  20 12:33 /home/patriark/containers/quadlets -> /home/patriark/.config/containers/systemd
➜  ~ ls -la ~/containers/scripts 
-rwxr-xr-x. 1 patriark patriark 2747 okt.  20 18:37 authelia_apply_fixes.sh
-rwxr-xr-x. 1 patriark patriark 3513 okt.  20 18:32 authelia_diag.sh
-rwxr-xr-x. 1 patriark patriark 2030 okt.  20 18:45 authelia_nuke_jwt_warning.sh
-rwxr-xr-x. 1 patriark patriark 2097 okt.  20 20:31 backup-day7-attempt1.sh
-rwxr-xr-x. 1 patriark patriark  652 okt.  20 20:33 cleanup-authelia.sh
-rwxr-xr-x. 1 patriark patriark  662 okt.  20 21:21 create-authelia-secrets-fixed.sh
-rwxr-xr-x. 1 patriark patriark  936 okt.  20 21:04 create-authelia-secrets.sh
-rwxr-xr-x. 1 patriark patriark 2707 okt.  19 14:15 day02-final-check.sh
-rwxr-xr-x. 1 patriark patriark 2036 okt.  20 16:07 day06-success-check.sh
-rwxr-xr-x. 1 patriark patriark 2918 okt.  21 08:45 day07-summary.sh
-rw-r--r--. 1 patriark patriark 2150 okt.  19 21:16 demo-stack-status.sh
-rwxr-xr-x. 1 patriark patriark 3124 okt.  20 14:33 deploy-jellyfin-with-traefik.sh
-rwxr-xr-x. 1 patriark patriark 1646 okt.  20 21:07 deploy-secure-authelia.sh
-rwxr-xr-x. 1 patriark patriark 2318 okt.  20 14:15 deploy-traefik.sh
-rwxr-xr-x. 1 patriark patriark  835 okt.  20 16:27 generate-authelia-secrets.sh
-rwxr-xr-x. 1 patriark patriark 5420 okt.  21 16:58 homelab-diagnose.sh
-rwxr-xr-x. 1 patriark patriark 9568 okt.  21 17:20 homelab-docs-refresh.sh
-rwxr-xr-x. 1 patriark patriark 9568 okt.  21 22:18 homelab-docs-refresh-v002.sh
-rwxr-xr-x. 1 patriark patriark 5569 okt.  20 11:28 jellyfin-manage.sh
-rwxr-xr-x. 1 patriark patriark 3981 okt.  20 11:28 jellyfin-status.sh
-rwxr-xr-x. 1 patriark patriark 1749 okt.  19 21:18 show-pod-status.sh
-rwxr-xr-x. 1 patriark patriark 1601 okt.  20 20:39 update-traefik-domains.sh

/mnt/btrfs-pool # BTRFS Pool consisting of three hard drives with the subsequent BTRFS subvolumes
├── subvol1-docs # documents - mostly private - intended for Nextcloud - already setup as a smb share
├── subvol2-pics # public pictures - intended for Nextcloud and perhaps Immich if it can be logically separated from - already setup as a smb share
├── subvol3-opptak # private video and photo recorded by user collection - intended for Immich and Nextcloud - already setup as a smb share
├── subvol4-multimedia # Read only multimedia directory for Jellyfin - already setup as a smb share
├── subvol5-music # personal music collection - already shared to Jellyfin - read only - already setup as a smb share
├── subvol6-tmp # 
└── subvol7-containers # secondary place for container related stuff that needs much space and/or can benefit from BTRFS snapshots


Backup strategy:
- **Config → Restic (encrypted)** # user comment - is this necessary when already having encrypted BTRFS snapshots of /, /home and the various /btrfs-pool subvolumes?
- **Media → BTRFS snapshots**
- **Cache → excluded** -# user comment - viable as can be placed on a btrfs subvolume

---

## 9. Design Trade-offs & Recommendations

| Topic | Best Practice | Trade-off |
|-------|----------------|------------|
| **TLS Automation** | Use DNS-01 via Hostinger API | Adds API dependency |
| **Network Exposure** | Public = Traefik only; internal = all others | More config complexity |
| **Secret Management** | Use Podman secrets or env vars | Reduced portability |
| **Observability** | Centralized logs + metrics | ~300–400MB RAM cost |
| **Firewall Policy** | Two zones (`internal`, `public`) | Requires manual interface mapping | # UDM-pro also has advanced firewall zone policies that the user wants to explore in the future - particularly with VLAN segmentation

---

## 10. Definition of “Internet-Ready”

System qualifies when:
- ✅ Valid certificates issued by Let’s Encrypt  
- ✅ SMTP + recovery notifications working  
- ✅ Backups verified and restorable  
- ✅ Monitoring with alerts active  
- ✅ Minimal open ports (80/443 only)

**Readiness target:** End of Week 2 → ~70% confidence

---

### ✍️ Closing Note

This homelab demonstrates *secure-by-default principles* with clear isolation layers.  
The next steps—TLS, observability, and recovery—will elevate it to near-production standards while keeping experimentation space open.

---
