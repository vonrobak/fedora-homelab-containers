# Homelab Roadmap Proposals - November 2025

**Date:** 2025-11-07
**Status:** Proposed - Awaiting Decision
**Context:** Project has reached operational maturity with solid foundation. Ready for strategic expansion.

---

## Current State Summary

### ✅ What's Working
- **Infrastructure**: Rootless Podman + systemd quadlets on Fedora 42
- **Services**: Traefik, Jellyfin, TinyAuth, Prometheus, Grafana, Loki, Alertmanager
- **Security**: Multi-layer middleware, network segmentation, Let's Encrypt TLS
- **Monitoring**: Complete observability stack with Discord alerts
- **Documentation**: 88+ markdown files in hybrid structure (guides/journal/decisions)
- **Backup**: BTRFS automation ready (awaiting activation)

### ⚠️ Gaps & In-Progress
- CrowdSec bouncer (configured but not active)
- Authelia SSO (partially deployed, needs completion)
- Backup automation (created but not activated)
- PostgreSQL infrastructure (not deployed - needed for future services)

### 📊 Resource Status
- **System SSD**: 128GB (currently 50% full)
- **BTRFS Pool**: 14TB (plenty of space for expansion)
- **Memory**: ~1.5GB used by containers (headroom available)
- **CPU**: Low utilization (transcoding spikes normal)

---

## Immich Overview

**What is Immich?**
Self-hosted photo and video management solution (Google Photos alternative)

**Key Capabilities:**
- Automatic photo backup from mobile devices
- ML-powered face detection and object recognition
- Advanced search (people, objects, locations)
- Albums, sharing, timeline views
- Mobile apps (iOS/Android)
- Hardware-accelerated transcoding

**Technical Requirements:**
- **PostgreSQL** database (with pgvector extension for ML)
- **Redis** for job queuing and caching
- **4 containers**: immich-server, immich-machine-learning, immich-web, immich-microservices
- **Storage**: Significant space for photos/videos (BTRFS pool ideal)
- **Optional**: Hardware acceleration (Intel QuickSync, NVIDIA, AMD - fedora-htpc has AMD GPU)

**Why Immich for Learning?**
- Demonstrates complex multi-container orchestration
- First database deployment (PostgreSQL + Redis pattern transferable to Nextcloud, etc.)
- Machine learning workload integration
- Mobile app integration
- Storage management at scale
- Performance optimization opportunities

---

## Three Roadmap Proposals

### Proposal A: "Foundation First" - Risk Minimization

**Philosophy:** Complete and harden existing infrastructure before expansion

**Timeline:** 4-6 weeks

**Rationale:** Lock in reliability and operational excellence before adding complexity

#### Phase 1: Operational Hardening (Week 1-2)

**Priority 1: Activate Backup System**
- Enable BTRFS backup timers
- Test restore procedures (file + full system)
- Validate external backup destination
- Document recovery runbooks

**Priority 2: Complete Security Stack**
- Activate CrowdSec bouncer (threat intelligence)
- Complete Authelia deployment with YubiKey 2FA
- Migrate from TinyAuth to Authelia for SSO
- Security audit and penetration testing

**Priority 3: System Health**
- Address system SSD space (94% → <80%)
- Implement log rotation across all services
- Optimize Prometheus/Loki retention policies
- Create capacity planning dashboard

#### Phase 2: Infrastructure Gaps (Week 3-4)

**Database Infrastructure:**
- Deploy PostgreSQL 16 (separate network: `systemd-database`)
- Deploy Redis (for general use)
- Create database backup procedures
- Document database deployment pattern

**Monitoring Enhancements:**
- Create service health dashboard
- Implement uptime tracking (SLO/SLI)
- Add alerting for capacity issues
- Deploy cAdvisor for container metrics

**Documentation:**
- Create ADRs for all major decisions
- Write service operation guides
- Quarterly documentation audit
- Implement doc-lint automation

#### Phase 3: Immich Deployment (Week 5-6)

**Deployment Steps:**
1. Create `systemd-photos` network
2. Deploy PostgreSQL for Immich (with pgvector)
3. Deploy Redis for Immich
4. Deploy Immich containers (4 total)
5. Configure Traefik routing with authentication
6. Set up BTRFS subvolume for photo storage
7. Configure hardware acceleration (AMD GPU)
8. Mobile app setup and testing
9. Create comprehensive Immich guide

**Learning Outcomes:**
- Complex service dependencies
- Database initialization and migrations
- ML workload management
- Mobile integration
- Multi-container networking

#### Ongoing: Monitoring & Refinement

**Continuous Improvements:**
- Weekly backup verification
- Monthly security reviews
- Quarterly system state reports
- Performance tuning based on metrics

---

### Proposal B: "Immich-Driven Learning" - Fast Track

**Philosophy:** Deploy Immich immediately, learn infrastructure gaps hands-on

**Timeline:** 2-3 weeks

**Rationale:** Real-world needs drive best learning; infrastructure follows demand

#### Phase 1: Immich Deployment (Week 1)

**Day 1-2: Database Layer**
- Create `systemd-database` network
- Deploy PostgreSQL 16 container
- Deploy Redis container
- Configure persistent storage on BTRFS
- Implement NOCOW for database performance
- Create database backup strategy

**Day 3-4: Immich Stack**
- Deploy Immich containers (server, ML, web, microservices)
- Configure Traefik routing: `photos.patriark.org`
- Set up authentication (TinyAuth initially)
- Configure AMD GPU hardware acceleration
- Test upload and basic functionality

**Day 5-7: Integration & Polish**
- Create BTRFS subvolume for photo library
- Configure mobile app (iOS/Android)
- Optimize ML performance
- Create monitoring dashboards for Immich
- Document deployment in journal

#### Phase 2: Backfill Infrastructure (Week 2)

**Activate Backup System:**
- Enable BTRFS backup automation
- Add Immich photos to backup tier
- Test PostgreSQL backup/restore
- Add database to monitoring

**Security Hardening:**
- Activate CrowdSec bouncer
- Migrate Immich to Authelia authentication
- Add rate limiting for upload endpoints
- Security review of photo access patterns

**System Maintenance:**
- Address SSD space issues
- Optimize container resource limits
- Implement log rotation
- Create capacity alerts

#### Phase 3: Refinement (Week 3)

**Performance Optimization:**
- ML inference benchmarking
- Database query optimization
- Thumbnail generation tuning
- Upload parallelization testing

**Documentation:**
- Create Immich deployment ADR
- Write Immich operation guide
- Document database deployment pattern
- Update system state report

**Learning Capture:**
- Document challenges encountered
- Create troubleshooting guide
- Write blog post on deployment (optional)
- Share lessons learned

---

### Proposal C: "Balanced Expansion" - Hybrid Approach

**Philosophy:** Parallel tracks - harden existing + deploy new in stages

**Timeline:** 4 weeks

**Rationale:** Best of both worlds - maintain momentum while building solid foundation

#### Week 1: Foundation + Planning

**Infrastructure Track:**
- ✅ Activate BTRFS backup automation
- ✅ Activate CrowdSec bouncer
- ✅ Address SSD space issues (cleanup, optimization)
- ✅ Create database deployment plan

**Immich Track:**
- 📚 Research Immich architecture thoroughly
- 📚 Design network topology for photos service
- 📚 Plan storage strategy (subvolume structure)
- 📚 Create deployment checklist
- 📋 Write Immich deployment ADR (document decisions upfront)

**Documentation Track:**
- Create missing service guides (Traefik, Jellyfin, Monitoring)
- Write ADRs for existing decisions
- Update CLAUDE.md with database deployment pattern

#### Week 2: Database Infrastructure + Immich Foundation

**Infrastructure Track:**
- Deploy PostgreSQL 16 (general purpose, can serve multiple services)
- Deploy Redis (general purpose)
- Create `systemd-database` network
- Implement database backup automation
- Create PostgreSQL operation guide

**Immich Track:**
- Deploy Immich-specific PostgreSQL instance (with pgvector)
- Deploy Immich Redis instance
- Test database connectivity
- Configure BTRFS storage: `/mnt/btrfs-pool/subvol8-photos/`
- Apply NOCOW attribute to database directories

**Monitoring Track:**
- Add database monitoring (postgres_exporter)
- Create database health dashboard
- Set up alerts for database issues

#### Week 3: Immich Deployment + Security Hardening

**Immich Track:**
- Deploy Immich containers (all 4)
- Configure Traefik routing: `photos.patriark.org`
- Integrate with authentication (TinyAuth initially)
- Configure AMD GPU hardware acceleration
- Test basic functionality
- Create Immich monitoring dashboard

**Security Track:**
- Complete Authelia deployment
- Migrate services from TinyAuth to Authelia SSO
- Implement hardware 2FA (YubiKey) for sensitive services
- Security audit of new database exposure
- Update middleware chains for Immich

**Backup Track:**
- Test backup/restore procedures (file level)
- Add PostgreSQL to automated backups
- Validate photo library backup strategy
- Document recovery procedures

#### Week 4: Integration, Optimization & Documentation

**Integration:**
- Mobile app setup (iOS/Android)
- Migrate Immich to Authelia authentication
- Configure sharing and album features
- Test upload performance from mobile devices

**Optimization:**
- ML inference performance tuning
- Database query optimization
- Thumbnail generation benchmarking
- Resource limit adjustments based on monitoring

**Documentation:**
- Create comprehensive Immich operation guide
- Document database deployment pattern (reusable)
- Write deployment journal entry
- Update system state report
- Create troubleshooting guide
- Document lessons learned

**Validation:**
- Full system backup test
- Disaster recovery simulation
- Performance baseline documentation
- Capacity planning for 1 year of photos

---

## Comparison Matrix

| Aspect | Proposal A | Proposal B | Proposal C |
|--------|------------|------------|------------|
| **Timeline** | 4-6 weeks | 2-3 weeks | 4 weeks |
| **Risk Level** | Lowest | Highest | Medium |
| **Learning Speed** | Slow & methodical | Fast & intense | Balanced |
| **Immich Deploy** | Week 5-6 | Week 1 | Week 2-3 |
| **Foundation Quality** | Excellent | Good | Very Good |
| **Complexity** | Linear | Chaotic | Parallel |
| **Documentation** | Comprehensive | Catch-up | Progressive |
| **Best For** | Risk-averse, methodical learner | Fast learner, high tolerance for troubleshooting | Balanced approach, real-world pace |

---

## Detailed Comparison

### Proposal A: Foundation First

**Pros:**
- ✅ Most reliable path
- ✅ Each layer fully tested before next
- ✅ Comprehensive documentation throughout
- ✅ Lower troubleshooting burden
- ✅ Best practices established before complexity
- ✅ Clear separation of concerns

**Cons:**
- ❌ Slower time to Immich
- ❌ May feel like busywork (hardening existing)
- ❌ Less excitement/motivation
- ❌ Theoretical learning before practical application
- ❌ Risk of perfectionism paralysis

**Ideal If:**
- You value stability over speed
- You prefer methodical, linear progress
- You want to minimize troubleshooting
- You're building for long-term sustainability
- You have limited time per session (need predictable tasks)

---

### Proposal B: Immich-Driven Learning

**Pros:**
- ✅ Fastest path to desired outcome (Immich)
- ✅ Immediate motivation (using photo management)
- ✅ Real-world problem-driven learning
- ✅ Infrastructure gaps become obvious quickly
- ✅ Exciting and engaging
- ✅ Mobile app integration early

**Cons:**
- ❌ Higher troubleshooting burden
- ❌ May encounter database issues without foundation
- ❌ Backfilling infrastructure is less satisfying
- ❌ Documentation plays catch-up
- ❌ Potential for technical debt
- ❌ More complex rollback if issues arise

**Ideal If:**
- You learn best by doing
- You have higher tolerance for troubleshooting
- You want immediate practical value
- You're motivated by working product
- You have time for intensive debugging sessions

---

### Proposal C: Balanced Expansion

**Pros:**
- ✅ Parallel progress (something always happening)
- ✅ Immich within 2-3 weeks (reasonable timeline)
- ✅ Foundation improvements alongside deployment
- ✅ Progressive documentation
- ✅ Realistic pace (mirrors real-world DevOps)
- ✅ Lower risk than Proposal B, faster than Proposal A

**Cons:**
- ❌ More cognitive load (multiple tracks)
- ❌ Requires discipline to maintain both tracks
- ❌ Context switching between infrastructure and deployment
- ❌ More complex project management
- ❌ Potential for abandoning one track

**Ideal If:**
- You can dedicate 5-10 hours per week
- You like variety (different tasks each session)
- You want balance between excitement and stability
- You're comfortable with parallel work streams
- You value both learning and practical outcomes

---

## Recommendation

**My recommendation: Proposal C (Balanced Expansion)**

**Rationale:**

1. **Realistic**: Mirrors how real infrastructure teams work (improvements + new projects)
2. **Motivating**: Immich deployment within 2-3 weeks maintains excitement
3. **Sustainable**: Foundation work prevents technical debt
4. **Learning-Rich**: Parallel tracks expose you to different problem domains
5. **Portfolio Value**: Demonstrates ability to balance maintenance + innovation
6. **Risk-Managed**: Critical foundation items (backups, CrowdSec) completed early

**Key Success Factors:**
- **Week 1 is critical** - activate backups and clean up SSD space before adding complexity
- **Document as you go** - don't let documentation lag
- **Stick to the tracks** - resist temptation to skip infrastructure work when Immich gets exciting
- **Use the monitoring** - let Prometheus/Grafana guide optimization decisions

---

## Next Steps After Choosing

### If Proposal A:
1. Review and activate backup automation tomorrow
2. Create CrowdSec activation checklist
3. Schedule security audit
4. Set PostgreSQL deployment for Week 3

### If Proposal B:
1. Create Immich deployment checklist immediately
2. Research PostgreSQL + pgvector setup
3. Plan BTRFS subvolume strategy
4. Block 6-8 hours for intensive Week 1 deployment

### If Proposal C:
1. Activate backup automation tomorrow (Week 1, Day 1)
2. Begin Immich research and ADR writing
3. Create parallel task tracking (Kanban board or todo lists)
4. Schedule Week 1 foundation tasks

---

## Open Questions

**For User to Decide:**

1. **Learning Style**: Do you prefer linear (A), intense (B), or parallel (C)?

2. **Time Availability**: How many hours per week can you dedicate?
   - <5 hours/week → Proposal A
   - 5-10 hours/week → Proposal C
   - 10+ hours/week → Proposal B or C

3. **Risk Tolerance**: How comfortable are you with troubleshooting complex issues?
   - Low → Proposal A
   - Medium → Proposal C
   - High → Proposal B

4. **Motivation**: What keeps you engaged?
   - Process and methodology → Proposal A
   - Shipping product → Proposal B
   - Balanced progress → Proposal C

5. **Photo Volume**: How many photos are we talking about?
   - <10k photos → Simpler Immich setup
   - 10k-50k → Standard deployment
   - 50k+ → Need careful performance planning

6. **Mobile Backup Priority**: How urgent is automated photo backup from phone?
   - Can wait 4-6 weeks → Proposal A
   - Want within 2-3 weeks → Proposal C
   - Need ASAP → Proposal B

---

## Beyond Immich: Future Service Candidates

Once database infrastructure is in place, the following services become viable:

**Tier 1: Database-Dependent Services**
- **Nextcloud**: File sync, calendars, contacts (PostgreSQL)
- **Vaultwarden**: Password manager (SQLite or PostgreSQL)
- **Paperless-NGX**: Document management (PostgreSQL)
- **GitTea/Forgejo**: Self-hosted Git (PostgreSQL)

**Tier 2: Complementary Services**
- **FreshRSS**: RSS feed reader
- **Linkding**: Bookmark manager
- **Wallabag**: Read-it-later service
- **Miniflux**: Minimal RSS reader

**Tier 3: Advanced Services**
- **Tandoor Recipes**: Recipe management
- **Audiobookshelf**: Audiobook/podcast server
- **Navidrome**: Music streaming (alternative to Jellyfin for music)

**Infrastructure Services**
- **Uptime Kuma**: Status page and uptime monitoring
- **Dozzle**: Real-time log viewer
- **Portainer**: Container management UI (optional, CLI is better for learning)

---

## Success Metrics

Regardless of which proposal is chosen, success looks like:

**Technical:**
- ✅ Immich operational with <1 hour downtime/month
- ✅ Photos backed up automatically (local + external)
- ✅ PostgreSQL pattern documented and reusable
- ✅ Mobile app integrated and tested
- ✅ Hardware acceleration working
- ✅ ML features functional (face detection, object recognition)
- ✅ System disk usage <80%
- ✅ All services monitored in Grafana

**Learning:**
- ✅ Understand multi-container orchestration
- ✅ Database deployment and management
- ✅ ML workload integration
- ✅ Performance optimization techniques
- ✅ Mobile app integration patterns
- ✅ Complex service networking

**Documentation:**
- ✅ Immich deployment guide created
- ✅ Database deployment pattern documented
- ✅ Troubleshooting guide written
- ✅ ADR documenting architectural decisions
- ✅ System state report updated

**Portfolio:**
- ✅ Blog post on Immich deployment (optional)
- ✅ Comprehensive GitHub documentation
- ✅ Demonstrable production system
- ✅ Lessons learned captured

---

## Conclusion

All three proposals will get you to a homelab with Immich running. The choice depends on:
- **Your learning style** (methodical vs. hands-on)
- **Your available time** (intensive vs. spread out)
- **Your risk tolerance** (stability vs. speed)
- **Your motivation** (process vs. product)

**The "right" choice is the one you'll actually complete.**

If uncertain, **start with Proposal C Week 1 tasks** (activate backups, activate CrowdSec, research Immich). After Week 1, you can pivot:
- Slow down → Proposal A
- Speed up → Proposal B
- Continue → Proposal C

**No decision is permanent.** The beauty of documented infrastructure is you can adjust the roadmap as you learn what works for you.

---

**Prepared by:** Claude Code
**Date:** 2025-11-07
**Status:** Awaiting user decision
**Next Step:** User selects proposal and commits to Week 1 tasks
