---
type: Guide
title: "Configuration Design Quick Reference Card"
description: "Quick-reference card companion to the configuration design principles — lookup tables for where ordering matters and common design decisions."
sensitivity: public
created: 2025-10-31
updated: 2025-12-31
---

# Configuration Design Quick Reference Card

**Companion to:** CONFIGURATION-DESIGN-PRINCIPLES.md  
**Purpose:** Quick lookup for common design decisions  
**Last Updated:** October 26, 2025

---

## 🚦 Order Matters? Quick Check

```
┌─────────────────────────────────────────────────────────┐
│  DOES ORDER MATTER?                                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ✅ YES - ORDER IS CRITICAL                             │
│  • Traefik middleware chain                             │
│  • Environment variable overrides in Quadlet            │
│  • Multiple Network= assignments (first = default)      │
│  • Shell script commands                                │
│  • BTRFS operations                                     │
│                                                          │
│  ⚠️  SOMETIMES - CONTEXT DEPENDENT                      │
│  • YAML lists (depends on what they represent)          │
│  • Systemd After=/Before= (for dependencies)            │
│                                                          │
│  ❌ NO - ORDER DOESN'T MATTER                           │
│  • Traefik router definitions                           │
│  • Traefik service definitions                          │
│  • Volume= mounts in Quadlet                            │
│  • Most directives within Quadlet sections              │
│  • Systemd Unit directives (processed as a graph)       │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 🛡️ Middleware Ordering Template

**Always use this order:**

```yaml
middlewares:
  - crowdsec-bouncer    # 1. FIRST: Block bad IPs (fastest check)
  - rate-limit          # 2. SECOND: Prevent abuse (fast check)
  - auth                # 3. THIRD: Authenticate (expensive check)
  - security-headers    # 4. LAST: Add headers to response
  # - cors              # Optional: After auth, before headers
```

**Why?**
```
Cost Pyramid:
    [Most Expensive]  Auth (database, bcrypt)
         ↑
    Rate Limit (memory check)
         ↑
    [Least Expensive] CrowdSec (cache lookup)

Principle: Fail fast at cheapest layer
```

---

## 🌐 Network Design Decision Tree

```
START: Adding new service
│
├─ Does it need external access?
│  ├─ YES → Must be on reverse_proxy network
│  └─ NO  → Can be on internal network only
│
├─ Does it need database access?
│  ├─ YES → Add to database network
│  └─ NO  → Only reverse_proxy network
│
├─ Does it expose sensitive data?
│  ├─ YES → Use dedicated network + auth
│  └─ NO  → Can share network with similar services
│
└─ RESULT: Network assignment determined
```

### Common Network Patterns

```
PATTERN 1: Public Web App
├─ Network: reverse_proxy only
└─ Example: Static website, public API

PATTERN 2: App with Database
├─ Network: reverse_proxy + database
└─ Example: Nextcloud, Gitea, Wiki

PATTERN 3: Pure Backend
├─ Network: database only
└─ Example: PostgreSQL, Redis

PATTERN 4: Monitoring Service
├─ Network: reverse_proxy + monitoring
└─ Example: Grafana

PATTERN 5: Multi-tenant
├─ Network: reverse_proxy + dedicated network
└─ Example: Isolated customer services
```

---

## 🌐 Traefik Configuration: Labels vs Dynamic Config

**Decision: ALWAYS use dynamic config files.**

```
┌─────────────────────────────────────────────────────┐
│  WHERE TO DEFINE TRAEFIK ROUTING?                   │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ✅ DYNAMIC CONFIG (routers.yml)                    │
│  • Single source of truth                           │
│  • Centralized security enforcement                 │
│  • Fail-fast middleware ordering guaranteed         │
│  • Clean separation of concerns                     │
│  • Git-friendly change tracking                     │
│                                                      │
│  ❌ CONTAINER LABELS                                │
│  • NO - Violates separation of concerns             │
│  • NO - Distributed routing (hard to audit)         │
│  • NO - Easy to misorder middleware                 │
│  • NO - Mixing deployment + routing concerns        │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**Deployment workflow:**

```bash
# 1. Create quadlet (NO labels)
nano ~/.config/containers/systemd/service.container

# 2. Add route to routers.yml
nano ~/containers/config/traefik/dynamic/routers.yml

# 3. Deploy
systemctl --user daemon-reload
systemctl --user enable --now service.service
```

**Quick template:**

```yaml
# ~/containers/config/traefik/dynamic/routers.yml

http:
  routers:
    service-name-secure:
      rule: "Host(`service.patriark.org`)"
      service: "service-name"
      middlewares:
        - crowdsec-bouncer@file      # 1. Block bad IPs
        - rate-limit@file             # 2. Rate limit
        - authelia@file               # 3. Authenticate (optional)
        - security-headers@file       # 4. Security headers
      tls:
        certResolver: letsencrypt

  services:
    service-name:
      loadBalancer:
        servers:
          - url: "http://service-name:port"
```

**See:** ADR-016 (Configuration Design Principles) for complete rationale.

---

## 🔐 Authentication Decision Matrix

```
┌─────────────────────────────────────────────────────┐
│  SHOULD SERVICE HAVE AUTH?                           │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Service Type              │ Auth? │ Why             │
│  ──────────────────────────┼───────┼────────────────│
│  Admin panel               │  YES  │ Sensitive       │
│  Personal files            │  YES  │ Private data    │
│  Media server              │  YES  │ Private content │
│  Monitoring dashboard      │  YES  │ System info     │
│  Service status page       │   NO  │ Public info     │
│  Public blog               │   NO  │ Intentionally   │
│  Public API (readonly)     │   NO  │ public          │
│  Documentation site        │   NO  │ (unless sensitive)│
│                                                      │
└─────────────────────────────────────────────────────┘

DEFAULT: When in doubt, require auth (fail-safe)
```

---

## 📦 Storage Location Decision Tree

```
What type of data?
│
├─ Configuration files
│  └─ Location: ~/containers/config/<service>
│  └─ Mount: Read-only preferred
│  └─ Example: Traefik YAML, app configs
│
├─ Small application data
│  └─ Location: ~/containers/data/<service>
│  └─ Mount: Read-write
│  └─ Example: App metadata, small databases
│
├─ Databases
│  └─ Location: ~/containers/db/<service>
│  └─ Special: chattr +C (NOCOW)
│  └─ Example: PostgreSQL, Redis data
│
├─ Large media files
│  └─ Location: /mnt/btrfs-pool/subvol5-media-video
│  └─ Mount: Read-write or read-only
│  └─ Example: Movies, TV shows
│
├─ User documents
│  └─ Location: /mnt/btrfs-pool/subvol1-docs
│  └─ Mount: Read-write
│  └─ Example: Nextcloud user files
│
└─ Archives/backups
   └─ Location: /mnt/btrfs-pool/subvol6-archives
   └─ Mount: Read-write
   └─ Example: Long-term storage
```

---

## 🔧 Quadlet File Template

**Use this as starting point for any new service:**

```ini
# ~/.config/containers/systemd/<service>.container

# ═══════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════
[Unit]
Description=<Service Name>
Documentation=<URL>
After=network-online.target
# After=<dependency>.service  # Add if depends on other service
Wants=network-online.target
# Requires=<dependency>.service  # Add if hard dependency

# ═══════════════════════════════════════════════
# CONTAINER CONFIGURATION
# ═══════════════════════════════════════════════
[Container]
Image=docker.io/<image>:<tag>
ContainerName=<service-name>
User=<uid>:<gid>  # Non-root user

# Networks (add multiple if needed)
Network=systemd-reverse_proxy.network
# Network=systemd-database.network  # Uncomment if needed

# Volumes (add as needed)
Volume=%h/containers/config/<service>:/config:Z
Volume=%h/containers/data/<service>:/data:Z

# Environment (add as needed)
Environment=KEY=value
# EnvironmentFile=%h/containers/config/<service>/env

# Health check (optional but recommended)
# HealthCmd=<command>
# HealthInterval=30s

# ═══════════════════════════════════════════════
# SERVICE BEHAVIOR
# ═══════════════════════════════════════════════
[Service]
Restart=on-failure
TimeoutStartSec=300

# ═══════════════════════════════════════════════
# INSTALLATION
# ═══════════════════════════════════════════════
[Install]
WantedBy=default.target
```

---

## 🌊 Traefik Router Template

**Use this as starting point for routing any service:**

```yaml
# ~/containers/config/traefik/dynamic/routers.yml

http:
  # ═══════════════════════════════════════════════
  # ROUTER DEFINITION
  # ═══════════════════════════════════════════════
  routers:
    <service>-router:
      rule: "Host(`<service>.patriark.org`)"
      entryPoints:
        - websecure  # HTTPS
      middlewares:
        - crowdsec-bouncer@file    # Always first
        - rate-limit@file           # Always second
        - auth-forward@file         # Add if needs auth
        - security-headers@file     # Always last
      service: <service>-service
      tls:
        certResolver: letsencrypt
  
  # ═══════════════════════════════════════════════
  # SERVICE DEFINITION
  # ═══════════════════════════════════════════════
  services:
    <service>-service:
      loadBalancer:
        servers:
          - url: "http://<container-name>:<port>"
```

---

## ⚡ Common Design Patterns

### Pattern: Web App with Database

```
┌─────────────────────────────────────┐
│  Components Needed                   │
├─────────────────────────────────────┤
│  1. Create database network          │
│  2. Deploy database (PostgreSQL)     │
│  3. Deploy cache (Redis)             │
│  4. Deploy app (on 2 networks)       │
│  5. Configure Traefik routing        │
│  6. Test and verify                  │
└─────────────────────────────────────┘

Networks:
  App:      reverse_proxy + database
  Database: database only
  Cache:    database only

Result:
  Traefik → App → Database ✅
  Traefik → Database ❌
```

### Pattern: Monitoring Stack

```
┌─────────────────────────────────────┐
│  Components Needed                   │
├─────────────────────────────────────┤
│  1. Create monitoring network        │
│  2. Deploy Prometheus                │
│  3. Deploy exporters                 │
│  4. Deploy Grafana (2 networks)      │
│  5. Configure Traefik                │
└─────────────────────────────────────┘

Networks:
  Grafana:    reverse_proxy + monitoring
  Prometheus: monitoring only
  Exporters:  monitoring only

Result:
  Traefik → Grafana → Prometheus ✅
  Traefik → Prometheus ❌
```

### Pattern: Public Service

```
┌─────────────────────────────────────┐
│  Components Needed                   │
├─────────────────────────────────────┤
│  1. Deploy service                   │
│  2. Configure Traefik (no auth)      │
│  3. Test access                      │
└─────────────────────────────────────┘

Networks:
  Service: reverse_proxy only

Middleware:
  - crowdsec-bouncer  ✅
  - rate-limit        ✅
  - auth              ❌ (intentionally removed)
  - security-headers  ✅
```

---

## 🚨 Common Mistakes to Avoid

### ❌ Mistake 1: Wrong Middleware Order
```yaml
# WRONG
middlewares:
  - auth
  - crowdsec-bouncer
# Result: Waste CPU authenticating banned IPs

# RIGHT
middlewares:
  - crowdsec-bouncer
  - auth
```

### ❌ Mistake 2: Missing Network Segmentation
```ini
# WRONG: Everything on one network
[Container]
Network=systemd-reverse_proxy.network
# Now Traefik can access database directly!

# RIGHT: Segmented networks
# App:
Network=systemd-reverse_proxy.network
Network=systemd-database.network
# Database:
Network=systemd-database.network
```

### ❌ Mistake 3: No Health Checks
```ini
# WRONG: No health check
[Container]
Image=myapp:latest

# RIGHT: With health check
[Container]
Image=myapp:latest
HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s
```

### ❌ Mistake 4: Running as Root
```ini
# WRONG: Implicit root
[Container]
Image=myapp:latest

# RIGHT: Explicit non-root
[Container]
Image=myapp:latest
User=1000:1000
```

### ❌ Mistake 5: No NOCOW for Databases
```bash
# WRONG: Database on BTRFS with COW
mkdir ~/containers/db/postgresql

# RIGHT: NOCOW for databases
mkdir ~/containers/db/postgresql
sudo chattr +C ~/containers/db/postgresql
```

---

## 📋 Pre-Deployment Checklist

**Use this checklist before deploying any new service:**

```
□ Service purpose clearly defined
□ Dependencies identified
□ Network segmentation planned
□ Storage locations determined
□ Authentication decision made
□ Security implications considered
□ Resource requirements known
□ Backup strategy planned
□ Failure modes identified
□ Documentation prepared
□ .gitignore updated (if secrets)
□ Testing plan ready
```

---

## 🔍 Troubleshooting Quick Guide

### Service Won't Start
```bash
# 1. Check systemd status
systemctl --user status <service>.service

# 2. Check container logs
podman logs <container>

# 3. Verify quadlet file
cat ~/.config/containers/systemd/<service>.container

# 4. Check network exists
podman network ls | grep <network>

# 5. Verify image exists
podman images | grep <image>
```

### Can't Access Service
```bash
# 1. Check Traefik logs
podman logs traefik | grep <service>

# 2. Verify router config
cat ~/containers/config/traefik/dynamic/routers.yml

# 3. Check middleware chain
# Look for middlewares: section in router

# 4. Test without auth
curl -I https://<service>.patriark.org
```

### Network Issues
```bash
# 1. Check container networks
podman inspect <container> | grep -A 10 Networks

# 2. Verify network exists
podman network inspect systemd-<network>

# 3. Check connectivity
podman exec <container> ping <other-container>

# 4. Verify DNS resolution
podman exec <container> nslookup <other-container>
```

---

## 💡 Quick Decision Flowchart

```
Adding new service?
│
├─ Read service documentation first ✅
│
├─ Determine network placement
│  └─ Use decision tree above
│
├─ Determine auth requirement
│  └─ Default: YES (unless good reason)
│
├─ Determine storage locations
│  └─ Config: SSD, Data: depends on size
│
├─ Create quadlet file
│  └─ Use template above
│
├─ Create Traefik router
│  └─ Use template above
│
├─ Deploy and test
│  └─ Follow deployment order
│
└─ Document decision
   └─ Update documentation
```

---

## 📚 Key Principles Summary

1. **Defense in Depth** - Multiple security layers
2. **Least Privilege** - Minimum necessary access
3. **Fail-Safe Defaults** - Secure by default
4. **Separation of Concerns** - One job per component
5. **Network Segmentation** - Isolate services
6. **Order Matters** - For middleware and some configs
7. **Document Decisions** - Future you will thank you

---

## 🎯 Most Important Rule

```
┌─────────────────────────────────────────────────┐
│                                                  │
│  When in doubt, choose the MORE SECURE option   │
│                                                  │
│  - Add auth (remove if truly needed)            │
│  - Use separate network (consolidate if safe)   │
│  - Run as non-root user                         │
│  - Make volumes read-only (unless write needed) │
│  - Apply all security middleware                │
│                                                  │
│  You can always relax security if needed,       │
│  but starting insecure is harder to fix.        │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

**Print this out and keep it handy!**

Document Version: 1.0  
Last Updated: October 26, 2025  
Companion to: CONFIGURATION-DESIGN-PRINCIPLES.md
