# Strategic Options for Next Phase

**Date:** 2025-11-11
**Context:** Post-CLI work session - Authelia deployed, Force Multiplier Week complete
**Purpose:** Present clear, actionable options for continued homelab evolution

---

## Current Position

**What's Working:**
- ✅ Authelia SSO with YubiKey authentication (production)
- ✅ 100% health check and resource limit coverage (portfolio-ready)
- ✅ AI intelligence system (trend analysis)
- ✅ Comprehensive monitoring (Prometheus, Grafana, Loki)
- ✅ Excellent documentation (ADRs, journals, guides)

**What's Pending:**
- ⏳ TinyAuth decommissioning (1-2 week confidence period)
- ⏳ GPU acceleration deployment (hardware validation needed)
- ⏳ Authelia service guide documentation
- ⏳ Root domain redirect configuration

**System Health:** 🟢 **EXCELLENT** (95/100)

---

## Option 1: Consolidate & Document (Recommended First)

**Focus:** Complete the current phase before adding new features

### Tasks

1. **Create Authelia Service Guide** (1-2 hours)
   - Location: `docs/10-services/guides/authelia.md`
   - Content:
     - Overview and architecture
     - YubiKey enrollment procedures
     - User management (adding users, managing groups)
     - Troubleshooting common issues
     - Integration patterns for new services
     - Mobile app compatibility patterns

2. **Create System State Report** (30 minutes)
   - Location: `docs/99-reports/2025-11-11-system-state-post-authelia.md`
   - Content:
     - Service inventory (16 services)
     - Authentication architecture (Authelia SSO)
     - Health and resource metrics
     - Network topology
     - Storage utilization
     - Performance baselines

3. **Update CLAUDE.md** (30 minutes)
   - Remove TinyAuth references (mark as deprecated)
   - Add Authelia commands and common operations
   - Update authentication section (YubiKey-first)
   - Add ADR-005 to key decisions list
   - Update service list (16 services)

4. **Archive TinyAuth Documentation** (after 1-2 week confidence period)
   - Move `docs/10-services/guides/tinyauth.md` → `docs/90-archive/`
   - Add archival header with context
   - Update `docs/90-archive/ARCHIVE-INDEX.md`
   - Remove TinyAuth middleware from Traefik config
   - Stop tinyauth.service

### Why This Option

**Pros:**
- ✅ Completes current work (no loose ends)
- ✅ Portfolio-ready documentation
- ✅ Future reference for troubleshooting
- ✅ Clean foundation for next phase
- ✅ Low risk (documentation tasks)

**Cons:**
- ⚠️ No new features (consolidation only)
- ⚠️ Less exciting than building new things

**Estimated Time:** 3-4 hours total

**Outcome:** Clean, well-documented system ready for next evolution

---

## Option 2: Deploy GPU Acceleration (Performance Focus)

**Focus:** Unlock 5-10x ML performance improvement for Immich

### Tasks

1. **Validate GPU Prerequisites** (10 minutes)
   ```bash
   cd ~/containers
   git pull origin claude/cli-work-continuation-011CV2uAKpZuRynDLGUvXfvy
   ./scripts/detect-gpu-capabilities.sh
   ```

   **Script checks:**
   - AMD GPU hardware detection (lspci)
   - `/dev/kfd` exists (Kernel Fusion Driver)
   - `/dev/dri` exists (Direct Rendering Infrastructure)
   - User in `render` group
   - Device permissions correct
   - Disk space (35GB needed for ROCm image)
   - GPU architecture (gfx version)

2. **Deploy ROCm-Enabled Immich ML** (20-30 minutes)
   ```bash
   ./scripts/deploy-immich-gpu-acceleration.sh
   ```

   **Script automates:**
   - GPU validation
   - Configuration backup (CPU-only quadlet)
   - Baseline performance measurement
   - ROCm quadlet deployment
   - Image pull (35GB - 10-15 min first time)
   - Health check monitoring (10 min startup period)
   - GPU utilization verification
   - Rollback instructions

3. **Performance Testing** (30 minutes)
   - Upload 10-20 test photos
   - Trigger ML processing (face detection, smart search)
   - Monitor GPU utilization: `watch -n 1 'cat /sys/class/drm/card*/device/gpu_busy_percent'`
   - Compare to CPU baseline
   - Document performance improvement

4. **Documentation** (30 minutes)
   - Update `docs/10-services/guides/immich.md` with GPU section
   - Create deployment report: `docs/99-reports/2025-11-11-gpu-acceleration-deployment.md`
   - Document actual performance metrics
   - Add troubleshooting notes if issues encountered

### Why This Option

**Pros:**
- ✅ Immediate tangible benefit (5-10x faster)
- ✅ Validates all Day 4-5 work
- ✅ Better user experience (faster smart search)
- ✅ Learning AMD ROCm (valuable expertise)
- ✅ GPU acceleration = portfolio highlight

**Cons:**
- ⚠️ Hardware-dependent (requires AMD GPU on fedora-htpc)
- ⚠️ RDNA 3.5 may need workarounds (HSA overrides)
- ⚠️ Large image pull (35GB)
- ⚠️ Potential troubleshooting if hardware issues

**Estimated Time:** 1.5-2 hours (+ 15 min image pull)

**Outcome:** GPU-accelerated Immich with documented performance improvement

**Rollback:** Easy via script (restore CPU-only quadlet)

---

## Option 3: Dashboard Deployment (User Experience Focus)

**Focus:** Create unified landing page for homelab services

### Options for Dashboard

**A. Heimdall** (Lightweight, simple)
- Single-page dashboard with service links
- Custom icons and organization
- Minimal resource usage (~50MB RAM)
- No authentication (rely on Authelia for service protection)

**B. Homepage** (Modern, feature-rich)
- Service status widgets
- Integration with Prometheus, Sonarr, Radarr, etc.
- Docker container monitoring
- Weather, search, bookmarks
- Higher resource usage (~150MB RAM)

**C. Homer** (Static, simple)
- YAML configuration
- Service links and categories
- No backend (static HTML/JS)
- Extremely lightweight (~20MB RAM)

### Tasks

1. **Choose Dashboard Solution** (research: 30 minutes)
   - Compare features vs resource usage
   - Check Traefik integration patterns
   - Review documentation quality

2. **Deploy Dashboard** (1-2 hours)
   - Create quadlet: `~/.config/containers/systemd/dashboard.container`
   - Configure Traefik routing: `routers.yml`
   - Add Authelia middleware (optional - dashboard could be public)
   - Health check and resource limits
   - Custom configuration (service links, icons)

3. **Configure Root Domain Redirect** (30 minutes)
   - Update `routers.yml`: `patriark.org` → `https://dashboard.patriark.org`
   - Test redirect from root domain
   - Fix current TinyAuth error state

4. **Documentation** (30 minutes)
   - Create `docs/10-services/guides/dashboard.md`
   - Create deployment journal: `docs/10-services/journal/2025-11-11-dashboard-deployment.md`
   - Update service list in CLAUDE.md

### Why This Option

**Pros:**
- ✅ Improves user experience (single landing page)
- ✅ Fixes root domain redirect issue
- ✅ Portfolio showcase (professional appearance)
- ✅ Service discovery (friends/family can see what's available)
- ✅ Quick wins (relatively simple deployment)

**Cons:**
- ⚠️ New service = more moving parts
- ⚠️ Additional resource usage (50-150MB RAM)
- ⚠️ Maintenance overhead (keeping links updated)

**Estimated Time:** 2-3 hours

**Outcome:** Professional landing page at `patriark.org` or `dashboard.patriark.org`

---

## Option 4: Portfolio Preparation (Career Focus)

**Focus:** Package homelab work for job applications and showcase

### Tasks

1. **Create Portfolio Document** (2-3 hours)
   - Location: `docs/PORTFOLIO.md` (or separate repo)
   - Content:
     - Project overview (problem statement, solution)
     - Architecture diagrams (network, service topology)
     - Technology stack (Podman, Traefik, Authelia, Prometheus, etc.)
     - Key achievements (100% coverage, YubiKey SSO, GPU acceleration)
     - Challenges overcome (dual auth anti-pattern, rate limiting, etc.)
     - Screenshots (dashboards, authentication flow)
     - Metrics (performance, reliability, security posture)

2. **Architecture Diagrams** (2-3 hours)
   - Network topology (segmentation, services per network)
   - Security layers (fail-fast middleware ordering)
   - Authentication flow (Authelia + YubiKey + SSO)
   - Data flow (logs → Loki, metrics → Prometheus → Grafana)
   - Tools: draw.io, mermaid, or similar

3. **Public Repository Preparation** (1-2 hours)
   - Review all committed files for secrets (already gitignored)
   - Create public README.md (project overview, tech stack)
   - Add LICENSE file (MIT, Apache 2.0, or other)
   - Consider separating scripts into public repo (sanitize any personal info)
   - Add `.github/` templates (if desired)

4. **Screenshots and Demos** (1-2 hours)
   - Grafana dashboards (system metrics, service health)
   - Authelia authentication flow (YubiKey prompt)
   - Traefik dashboard (service routing)
   - Immich photo management
   - Jellyfin media streaming
   - Intelligence reports (trend analysis)

5. **Resume Bullet Points** (30 minutes)
   - "Deployed enterprise-grade SSO with hardware 2FA (YubiKey/WebAuthn) protecting 16+ services"
   - "Achieved 100% health check and resource limit coverage (production-ready reliability)"
   - "Implemented AI-driven trend analysis detecting system optimizations (-1.2GB memory)"
   - "Configured AMD ROCm GPU acceleration (5-10x ML performance improvement)"
   - "Architected layered security (CrowdSec IP reputation, rate limiting, phishing-resistant auth)"

### Why This Option

**Pros:**
- ✅ Career advancement (job applications)
- ✅ Demonstrates breadth (infrastructure, security, monitoring, ML)
- ✅ Demonstrates depth (troubleshooting, architecture decisions, trade-offs)
- ✅ Shows learning ability (ADRs document evolution)
- ✅ Portfolio piece (tangible proof of skills)

**Cons:**
- ⚠️ Time-intensive (5-8 hours total)
- ⚠️ No new functionality (packaging existing work)
- ⚠️ Requires context switching (technical → presentation)

**Estimated Time:** 6-10 hours

**Outcome:** Portfolio-ready documentation and artifacts for job applications

---

## Option 5: Additional Services (Feature Expansion)

**Focus:** Add new services to the homelab

### Potential Services

**A. Vaultwarden (Password Manager)**
- Self-hosted Bitwarden server
- Integrates with Authelia (optional - has own auth)
- Secure password/secrets storage
- Browser extensions, mobile apps
- **Value:** Centralized secrets management
- **Effort:** 2-3 hours (deployment + testing)

**B. Nextcloud (File Sync & Collaboration)**
- Self-hosted Dropbox alternative
- File storage, calendar, contacts
- Requires PostgreSQL, Redis
- Resource-intensive (~500MB RAM + database)
- **Value:** Data sovereignty, file sync
- **Effort:** 4-6 hours (complex deployment)

**C. Wireguard UI (VPN Management)**
- Web UI for Wireguard VPN management
- Add/remove peers, generate configs
- Current Wireguard exists (terminal-only management)
- **Value:** Easier VPN management
- **Effort:** 2-3 hours

**D. Uptime Kuma (External Monitoring)**
- Public-facing service monitoring
- Status page for friends/family
- Heartbeat monitoring
- Notification integrations
- **Value:** External validation (can services be reached?)
- **Effort:** 1-2 hours

**E. PiHole / AdGuard Home (DNS-based Ad Blocking)**
- Network-wide ad blocking
- DNS server with filtering
- Dashboard showing blocked queries
- **Value:** Privacy, reduced bandwidth
- **Effort:** 2-3 hours

### Why This Option

**Pros:**
- ✅ Expands capabilities
- ✅ New learning opportunities
- ✅ Practical utility (depending on service)
- ✅ Portfolio breadth (more services = more tech stack)

**Cons:**
- ⚠️ Resource usage (RAM, CPU, disk)
- ⚠️ Maintenance overhead (more services = more updates)
- ⚠️ Complexity creep (diminishing returns)
- ⚠️ System SSD space constraints (128GB)

**Estimated Time:** 2-6 hours per service

**Outcome:** Additional capabilities, broader tech stack

**Caution:** Assess actual need vs "shiny new service" syndrome

---

## Option 6: Advanced Authelia Features (SSO Expansion)

**Focus:** Leverage Authelia's advanced capabilities

### Potential Enhancements

**A. LDAP Backend** (Instead of File-based Users)
- Centralized user directory
- Integration with enterprise auth systems
- Scalable user management
- **Value:** Learning enterprise IAM patterns
- **Effort:** 3-4 hours (OpenLDAP deployment + Authelia config)
- **Reality Check:** Overkill for single-user homelab

**B. OAuth2/OIDC Provider Configuration**
- Authelia as OAuth2 authorization server
- Applications authenticate via OAuth (not just ForwardAuth)
- More complex, more flexible
- **Value:** Learning OAuth flows
- **Effort:** 4-6 hours (complex configuration + testing)
- **Reality Check:** ForwardAuth already working well

**C. Multi-User Onboarding**
- Add family/friends as users
- Group-based access control (admins vs users)
- TOTP enrollment for non-YubiKey users
- **Value:** Real multi-user experience
- **Effort:** 1-2 hours (add users, test access)
- **Consideration:** Support burden (troubleshooting auth issues)

**D. Advanced Access Policies**
- Time-based access (work hours only)
- Geographic restrictions (via GeoIP)
- Device-based policies (trusted devices)
- **Value:** Learning advanced IAM patterns
- **Effort:** 2-3 hours (policy development + testing)
- **Reality Check:** Complexity without clear benefit

**E. Security Events & Analytics**
- Failed login monitoring
- Alert on repeated failures (brute force)
- Dashboard for auth events
- **Value:** Security visibility
- **Effort:** 2-3 hours (Prometheus exporter + Grafana dashboard)
- **Benefit:** Actual value (detect attacks)

### Why This Option

**Pros:**
- ✅ Deeper expertise with Authelia
- ✅ Enterprise IAM learning
- ✅ Security improvements (monitoring, alerts)
- ✅ Leverages existing investment

**Cons:**
- ⚠️ Complexity without proportional benefit (some features)
- ⚠️ Overkill for single-user environment (LDAP, OAuth)
- ⚠️ Maintenance overhead

**Estimated Time:** 2-6 hours per enhancement

**Outcome:** Advanced IAM expertise, deeper Authelia knowledge

**Recommendation:** Focus on **security events & analytics** (practical value)

---

## Recommended Path: Phased Approach

### Phase 1: Consolidation (Week 1)
**Goal:** Complete current work, clean documentation

1. Create Authelia service guide (1-2 hours)
2. Create system state report (30 minutes)
3. Update CLAUDE.md (30 minutes)
4. **Decision:** Deploy GPU acceleration OR dashboard (2-3 hours)

**Total time:** 4-6 hours
**Outcome:** Clean, well-documented system + one new feature

### Phase 2: Portfolio Preparation (Week 2)
**Goal:** Package work for job applications

1. Create portfolio document (2-3 hours)
2. Architecture diagrams (2-3 hours)
3. Screenshots and demos (1-2 hours)
4. Resume bullet points (30 minutes)

**Total time:** 6-9 hours
**Outcome:** Job-ready portfolio artifacts

### Phase 3: Expansion (Week 3+)
**Goal:** Add new capabilities based on actual needs

**Options:**
- Dashboard deployment (if not done in Phase 1)
- GPU acceleration (if not done in Phase 1)
- Additional service (Vaultwarden, Uptime Kuma, etc.)
- Advanced monitoring (security events, analytics)

**Total time:** Variable (2-6 hours per feature)
**Outcome:** Expanded capabilities, continued learning

---

## Decision Framework

### Choose Based On:

**If you need immediate resume/portfolio boost:**
→ **Option 4: Portfolio Preparation**

**If you want tangible performance improvement:**
→ **Option 2: GPU Acceleration** (hardware-dependent)

**If you want better user experience:**
→ **Option 3: Dashboard Deployment**

**If you want clean, maintainable system:**
→ **Option 1: Consolidate & Document** (recommended first step)

**If you want new features/capabilities:**
→ **Option 5: Additional Services** (choose 1-2 max)

**If you want deeper expertise in current tech:**
→ **Option 6: Advanced Authelia Features** (focus on security monitoring)

### Risk Assessment

**Low Risk:**
- Option 1 (documentation)
- Option 4 (portfolio - no system changes)

**Medium Risk:**
- Option 2 (GPU - hardware-dependent, rollback available)
- Option 3 (dashboard - new service, but simple)
- Option 6 (Authelia enhancements - can break auth if misconfigured)

**Higher Risk:**
- Option 5 (new services - more complexity, resource usage)

### Resource Usage Impact

**No impact:**
- Option 1, Option 4

**Low impact (<200MB RAM):**
- Option 2 (GPU - same service, different image)
- Option 3 (dashboard - 50-150MB)

**Medium impact (200-500MB RAM):**
- Option 5 (most additional services)
- Option 6 (LDAP backend, additional monitoring)

**High impact (>500MB RAM):**
- Option 5 (Nextcloud)

**System SSD constraints:** 128GB (currently ~60% used)
- GPU: +35GB (temporary - image download)
- Additional services: +1-5GB each

---

## My Recommendation: Hybrid Approach

### This Week (Phase 1: Consolidation + One Feature)

**Priority 1: Documentation** (3-4 hours)
1. ✅ Create Authelia service guide
2. ✅ Create system state report
3. ✅ Update CLAUDE.md

**Priority 2: Choose ONE feature** (2-3 hours)
- **If hardware available:** Deploy GPU acceleration (high value, validates Days 4-5 work)
- **If no GPU or hardware issues:** Deploy dashboard (improves UX, fixes root domain)

**Outcome:** Clean, documented system + one meaningful improvement

### Next Week (Phase 2: Portfolio)

**If job searching active:**
- Portfolio document (2-3 hours)
- Architecture diagrams (2-3 hours)
- Screenshots and demos (1-2 hours)

**If not job searching:**
- Skip for now, revisit when needed

### Future Weeks (Phase 3: Expansion)

**Only add services with CLEAR use case:**
- Vaultwarden: If managing passwords across devices
- Uptime Kuma: If want external validation/status page
- Security monitoring: If want auth event visibility

**Avoid:**
- "Shiny new service" syndrome
- Complexity without proportional benefit
- Resource-heavy services without clear value

---

## Questions to Consider

### Before Next Steps

1. **Job search status:** Active → prioritize portfolio
2. **GPU hardware available:** Yes → prioritize GPU deployment
3. **Current pain points:** What's frustrating/missing in current setup?
4. **Time available:** 2-4 hours/week or 8+ hours/week?
5. **Learning goals:** Deep expertise (current tech) vs breadth (new services)?

### For Each Option

1. **What problem does this solve?** (Real problem or "would be cool"?)
2. **What's the maintenance burden?** (Updates, monitoring, troubleshooting)
3. **What's the resource impact?** (RAM, disk, CPU)
4. **What do I learn?** (New tech, deeper expertise, transferable skills)
5. **Portfolio value?** (Adds breadth, demonstrates depth, shows judgment)

---

## Conclusion

**Current state:** Exceptional (95/100) - Production-ready homelab

**Recommendation:** Start with **Option 1 (Consolidation)** + **Option 2 or 3 (GPU or Dashboard)**

**Rationale:**
- Complete current work (no loose ends)
- Add one meaningful feature (performance or UX)
- Portfolio-ready documentation
- Clean foundation for future expansion

**Estimated total time:** 5-7 hours
**Outcome:** Clean, documented, improved system ready for portfolio showcase or continued expansion

**Next decision point:** After consolidation, choose based on job search status (portfolio) or learning goals (new services/features)

---

**Prepared by:** Claude Code (Web)
**Date:** 2025-11-11
**Purpose:** Guide strategic decision-making for homelab evolution
