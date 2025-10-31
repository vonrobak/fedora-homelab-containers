# Week 2 Learning Plan: Security, TLS & Authentication Hardening

**Date:** 2025-10-21  
**Phase:** Internet-Readiness  
**Goal:** Transition from secure local-only lab to a hardened, publicly accessible environment.

---

## 🎯 Objectives

1. Obtain and manage **valid TLS certificates** using Let’s Encrypt DNS-01 via Hostinger.
2. Implement **Authelia email notifications** and test recovery workflows.
3. Validate **WebAuthn + YubiKey** integration with proper TLS.
4. Establish **encrypted backup procedures** with Restic.
5. Begin **monitoring setup** (Prometheus + Grafana scaffolding).

---

## 🧠 Key Learning Outcomes

- ACME DNS-01 challenge flow and API integration.
- Reverse proxy TLS termination and dynamic config loading.
- Identity workflows (TOTP, WebAuthn, SMTP recovery).
- Secure secret injection into containers.
- Designing reproducible infrastructure through systemd Quadlets.

---

## 🗓️ Daily Breakdown

### **Day 8 – Let’s Encrypt via Hostinger API**
**Focus:** DNS-01 challenge automation.

**Tasks:**
- Obtain Hostinger API token.
- Configure `traefik.yml` and `acme.json`.
- Verify automatic certificate issuance.
- Inspect Traefik logs for ACME transactions.

**Verification:**
```bash
podman logs traefik | grep -i acme
curl -vI https://jellyfin.patriark.dev
