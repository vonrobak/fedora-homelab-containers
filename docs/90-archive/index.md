---
layout: default
title: Home
nav_order: 1
---

# Production-Grade Homelab Infrastructure

**Enterprise-level self-hosted infrastructure demonstrating DevOps/SRE best practices**

[![Health Score](https://img.shields.io/badge/Health%20Score-95%2F100-brightgreen)](#metrics--results)
[![Services](https://img.shields.io/badge/Services-16-blue)](#technology-stack)
[![Coverage](https://img.shields.io/badge/Coverage-100%25-success)](#key-achievements)
[![Documentation](https://img.shields.io/badge/Docs-90%2B%20files-informational)](README.md)

---

## Quick Links

<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0;">
  <a href="PORTFOLIO.html" style="text-decoration: none; color: inherit;">
    <div style="border: 2px solid #4CAF50; padding: 20px; border-radius: 8px; background: #f9f9f9;">
      <h3 style="margin-top: 0;">📄 Portfolio Document</h3>
      <p>Comprehensive project showcase with technical achievements, challenges solved, and transferable skills.</p>
    </div>
  </a>

  <a href="ARCHITECTURE-DIAGRAMS.html" style="text-decoration: none; color: inherit;">
    <div style="border: 2px solid #2196F3; padding: 20px; border-radius: 8px; background: #f9f9f9;">
      <h3 style="margin-top: 0;">🏗️ Architecture Diagrams</h3>
      <p>10 Mermaid diagrams showing system architecture, security layers, network segmentation, and data flows.</p>
    </div>
  </a>

  <a href="RESUME-BULLET-POINTS.html" style="text-decoration: none; color: inherit;">
    <div style="border: 2px solid #FF9800; padding: 20px; border-radius: 8px; background: #f9f9f9;">
      <h3 style="margin-top: 0;">📝 Resume Bullets</h3>
      <p>40+ job-ready resume bullet points tailored for DevOps, SRE, and Platform Engineering roles.</p>
    </div>
  </a>

  <a href="README.html" style="text-decoration: none; color: inherit;">
    <div style="border: 2px solid #9C27B0; padding: 20px; border-radius: 8px; background: #f9f9f9;">
      <h3 style="margin-top: 0;">📚 Documentation Index</h3>
      <p>90+ markdown files organized by category with guides, ADRs, journals, and reports.</p>
    </div>
  </a>
</div>

---

## 🎯 Project Highlights

### 100% Reliability Coverage

All 16 services have:
- ✅ Health check monitoring
- ✅ Resource limits (OOM protection)
- ✅ Auto-recovery strategies
- ✅ Comprehensive logging

### Phishing-Resistant Authentication

- 🔐 YubiKey/WebAuthn (FIDO2) hardware 2FA
- 🔐 Single sign-on across 5+ admin services
- 🔐 Zero successful phishing attempts possible

### AI-Driven Intelligence

- 🤖 Proactive trend analysis
- 🤖 Detected 8% memory optimization
- 🤖 Historical analysis capabilities
- 🤖 Predictive capacity planning (planned)

### Enterprise Observability

- 📊 Prometheus metrics (15-second scraping)
- 📊 Grafana dashboards
- 📊 Loki log aggregation
- 📊 Alertmanager routing to Discord

---

## 🛠️ Technology Stack

<table>
  <tr>
    <th>Category</th>
    <th>Technologies</th>
  </tr>
  <tr>
    <td><strong>Container Runtime</strong></td>
    <td>Podman 5.x (rootless, daemonless)</td>
  </tr>
  <tr>
    <td><strong>Orchestration</strong></td>
    <td>systemd quadlets (native Linux)</td>
  </tr>
  <tr>
    <td><strong>Reverse Proxy</strong></td>
    <td>Traefik v3.3 (Let's Encrypt)</td>
  </tr>
  <tr>
    <td><strong>Security</strong></td>
    <td>CrowdSec, Authelia, YubiKey/WebAuthn</td>
  </tr>
  <tr>
    <td><strong>Monitoring</strong></td>
    <td>Prometheus, Grafana, Loki, Alertmanager</td>
  </tr>
  <tr>
    <td><strong>Storage</strong></td>
    <td>BTRFS (snapshots, CoW filesystem)</td>
  </tr>
</table>

---

## 📈 Key Metrics

| Metric | Value |
|--------|-------|
| **Health Score** | 95/100 |
| **Services Running** | 16/16 |
| **Health Check Coverage** | 100% |
| **Resource Limit Coverage** | 100% |
| **Memory Optimization** | -8% (AI-detected) |
| **Authentication Latency** | <200ms (p95) |
| **Uptime** | 99%+ |
| **Documentation Files** | 90+ |

---

## 🏗️ Architecture at a Glance

### Security Layers (Fail-Fast Design)

```
Internet Request
    ↓
[1] CrowdSec IP Reputation (cache lookup - fastest)
    ↓ Reject known attackers
[2] Rate Limiting (memory check)
    ↓ Throttle excessive requests
[3] Authelia SSO (YubiKey + password - most expensive)
    ↓ Hardware 2FA verification
[4] Security Headers (response modification)
    ↓
✅ Backend Service
```

**Why this order?** Each layer is computationally more expensive than the previous. Reject malicious traffic early to save resources.

See [Architecture Diagrams](ARCHITECTURE-DIAGRAMS.html) for complete visual documentation.

---

## 📚 Documentation Structure

This project includes 90+ markdown files organized into:

- **00-foundation/** - Core concepts, ADRs (5 major decisions)
- **10-services/** - Service-specific operational guides
- **20-operations/** - Backup, recovery, maintenance procedures
- **30-security/** - Authentication, hardening, incident response
- **40-monitoring/** - Observability stack documentation
- **99-reports/** - Point-in-time system state snapshots

All documentation follows Architecture Decision Record (ADR) methodology.

---

## 🎓 Learning Journey

### Real-World Problem-Solving

This project documents actual challenges and solutions:

**Rate Limiting for Modern SPAs:**
- Problem: 10 req/min too restrictive for web apps
- Solution: Increased to 100 req/min for asset-heavy applications
- Lesson: Standard API rate limits don't account for SPA architecture

**Dual Authentication Anti-Pattern:**
- Problem: Layering SSO on top of native auth breaks mobile apps
- Solution: Removed Authelia from Immich, use native auth only
- Lesson: Not all services need SSO—consider UX implications

**Database Encryption Key Mismatch:**
- Problem: Service won't start after changing secret delivery method
- Solution: Backup, delete database, recreate with correct key
- Lesson: Secret format changes may require data migration

*See [Authelia Deployment Journal](30-security/journal/2025-11-11-authelia-deployment.html) for 1,000+ lines of detailed troubleshooting.*

---

## 🔑 Skills Demonstrated

<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px;">
  <div>
    <h4>Infrastructure</h4>
    <ul>
      <li>Container orchestration</li>
      <li>Service reliability</li>
      <li>Configuration management</li>
      <li>Monitoring & observability</li>
    </ul>
  </div>

  <div>
    <h4>Security</h4>
    <ul>
      <li>Hardware 2FA (YubiKey)</li>
      <li>Defense in depth</li>
      <li>Secrets management</li>
      <li>Network segmentation</li>
    </ul>
  </div>

  <div>
    <h4>Software Engineering</h4>
    <ul>
      <li>Documentation (ADRs)</li>
      <li>Problem solving</li>
      <li>Scripting & automation</li>
      <li>Version control (Git)</li>
    </ul>
  </div>

  <div>
    <h4>DevOps & SRE</h4>
    <ul>
      <li>CI/CD concepts</li>
      <li>Observability (3 pillars)</li>
      <li>Incident response</li>
      <li>Capacity planning</li>
    </ul>
  </div>
</div>

---

## 🚀 Getting Started

### Explore the Documentation

1. **Start here:** [Documentation Index](README.html)
2. **Understand "why":** [Architecture Decision Records](00-foundation/decisions/)
3. **Learn operations:** [Service Guides](10-services/guides/)
4. **See problem-solving:** [Deployment Journals](30-security/journal/)

### Adapt to Your Environment

This repository can serve as:
- Learning resource for homelab enthusiasts
- Reference architecture for container orchestration
- Documentation methodology example
- Portfolio piece demonstrating DevOps/SRE skills

**Fork it, adapt it, learn from it!**

---

## 📞 Contact

**For hiring inquiries or questions:**
- GitHub: [@YOUR_USERNAME](https://github.com/YOUR_USERNAME)
- LinkedIn: [Your Name](https://linkedin.com/in/yourprofile)
- Email: admin@example.com

---

## ⭐ Star This Project

If this project helped you learn something new or serves as inspiration for your own homelab, please consider giving it a star! It helps others discover it.

---

*This homelab demonstrates production-ready infrastructure implementation suitable for DevOps, SRE, or Platform Engineering roles.*

**Explore:** [Portfolio](PORTFOLIO.html) | [Diagrams](ARCHITECTURE-DIAGRAMS.html) | [Resume Bullets](RESUME-BULLET-POINTS.html) | [Docs](README.html)
