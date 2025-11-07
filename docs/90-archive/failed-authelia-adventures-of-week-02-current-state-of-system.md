> **🗄️ ARCHIVED:** 2025-11-07
>
> **Reason:** Failed Authelia deployment attempt - abandoned in favor of TinyAuth
>
> **Superseded by:** `docs/10-services/guides/tinyauth.md`
>
> **Historical context:** Week 2 of homelab build attempted to deploy Authelia for SSO with WebAuthn/YubiKey support. After several days of troubleshooting, discovered that WebAuthn requires valid TLS certificates (self-signed certs blocked by browsers). Rather than deploy Let's Encrypt before fully understanding the system, pragmatically chose TinyAuth as simpler authentication solution.
>
> **Value:** Important lesson - "Perfect is the enemy of good." Starting simple (TinyAuth) allowed progress while preserving option to upgrade to Authelia later with proper TLS infrastructure.
>
> **Related:** See also `week02-failed-authelia-but-tinyauth-goat.md` for the decision to pivot
>
> ---

# Current System State Analysis - 2025-10-22

## 📊 What's Actually Working Right Now

### ✅ Working Services

1. **Jellyfin** - FULLY FUNCTIONAL
   - URL: https://jellyfin.patriark.lokal
   - Status: Accessible without errors
   - Container: Running, healthy
   - Network: Connected to systemd-reverse_proxy
   - Authentication: None currently (direct access)

2. **Traefik** - PARTIALLY WORKING
   - Container: Running
   - Ports: 80, 443, 8080 all listening
   - Network: systemd-reverse_proxy
   - Routing: Working for Jellyfin ✅
   - Dashboard: NOT accessible on https://traefik.patriark.lokal ❌

3. **DNS Resolution** - WORKING PERFECTLY
   - auth.patriark.lokal → 192.168.1.70 ✅
   - jellyfin.patriark.lokal → 192.168.1.70 ✅
   - traefik.patriark.lokal → 192.168.1.70 ✅
   - Pi-hole resolving correctly

### ❌ Not Working Services

1. **Authelia** - BROKEN
   - Container: Crashes repeatedly (restart counter: 82+)
   - Error: "redis connection error: context deadline exceeded"
   - Root cause: Multi-network configuration issues
   - Status: In crash loop, not functional

2. **Authelia-Redis** - RUNNING BUT ISOLATED
   - Container: Running
   - Network: systemd-auth_services only
   - Problem: Authelia can't reach it reliably

3. **Traefik Dashboard** - NOT ACCESSIBLE
   - URL: https://traefik.patriark.lokal returns error
   - Likely cause: Router configuration references non-working Authelia

---

## 🔍 Root Cause Analysis

### Why Jellyfin Works But Traefik Dashboard Doesn't

**Jellyfin works because:**
- It has its own Traefik labels (from original setup)
- Doesn't require authentication (no middleware blocking it)
- Direct routing works: browser → Traefik → Jellyfin ✅

**Traefik dashboard doesn't work because:**
- Router configuration (in routers.yml) requires `tinyauth@docker` or `traefik-auth` middleware
- Middleware references Authelia (which is broken)
- When middleware fails, Traefik returns error
- Result: Can't access dashboard ❌

### The Authelia Situation

**Timeline of issues:**
1. Original setup had Authelia working with Redis
2. Attempted to add SMTP support → added smtp_password secret
3. Secret mounting syntax was wrong (file vs Podman secret confusion)
4. Fixed secret syntax → Redis connection broke
5. Added multi-network support (auth_services + reverse_proxy)
6. Redis became unreachable due to network routing issues
7. Current state: Authelia in crash loop

**Technical problems:**
- Container multi-network complexity
- Podman secret vs file-based secret confusion
- Redis connection across network boundaries
- Configuration file complexity (200+ lines)
- Dependencies (Redis, secrets, networks, configs)
- Difficult to debug (cryptic errors)

---

## 🎯 Evidence-Based Decision Framework

### Question 1: Do You Need Authentication at All?

**Consider:**
- Currently accessing only from home LAN (192.168.1.0/24)
- No internet exposure yet
- Jellyfin has its own built-in authentication
- You're the only user

**Scenarios:**

**A) LAN-only access forever:**
- No authentication needed
- UDM Pro firewall protects from outside
- Simpler, faster, nothing to break

**B) Future internet access:**
- Need authentication layer
- Protects services from public internet
- Adds complexity but necessary for security

**Your answer determines next steps.**

---

### Question 2: If You Need Auth, Which Solution?

Let's compare options with evidence:

#### Option A: No Authentication
**Pros:**
- Simplest possible setup ✅
- Nothing to break ✅
- Jellyfin has built-in auth ✅
- Works right now ✅

**Cons:**
- Can't safely expose to internet ❌
- Anyone on LAN has full access ❌
- No unified login ❌

**Best for:** 
- LAN-only setups
- Single user
- Don't plan internet exposure

---

#### Option B: Authelia (Current Attempt)
**Pros:**
- Full-featured SSO solution
- 2FA support (TOTP, WebAuthn)
- Comprehensive access control
- Well-documented (in theory)

**Cons:**
- **EMPIRICAL EVIDENCE from your experience:**
  - 3 days of troubleshooting
  - Multiple breaking changes
  - Redis dependency caused issues
  - Secret management confusion
  - Network routing complexity
  - Crash loops and restarts
  - Still not working after extensive effort

**Reality check:**
- If it takes 3 days and still doesn't work, is it the right choice?
- Complexity doesn't equal better
- Time spent debugging = time not building homelab

**Best for:**
- Large homelabs with many users
- Organizations needing compliance
- People who enjoy debugging complex systems
- **NOT for: Getting something working quickly**

---

#### Option C: Tinyauth
**Pros:**
- Modern, purpose-built for Traefik forward auth
- Single container (no Redis)
- Simple configuration (environment variables)
- Active development (v4 released recently)
- Similar to Authelia but simpler
- Optional 2FA (TOTP)
- Optional OAuth (Google, GitHub)

**Cons:**
- Less mature than Authelia
- Fewer features (but you probably don't need them)
- Smaller community

**Evidence:**
- Designed specifically to solve Authelia's complexity
- Creator's motivation: "Authelia lacked out-of-the-box Traefik support"
- No database, no Redis, no complex config
- Users report it "just works"

**Best for:**
- Modern Traefik setups
- People who want SSO without complexity
- Homelabs with 1-10 users
- **You, probably**

---

#### Option D: Traefik BasicAuth
**Pros:**
- Built into Traefik (no extra containers)
- Rock solid reliability
- Browser-native (no cookies/sessions)
- 5 minutes to setup
- Impossible to break

**Cons:**
- No SSO (separate login per service)
- No 2FA
- Basic browser popup (not pretty)
- No OAuth

**Best for:**
- Quick and dirty protection
- People who value reliability over features
- Temporary solution while deciding

---

#### Option E: Cloudflare Tunnel + Access
**Pros:**
- Handles internet exposure AND authentication
- Zero port forwarding needed
- Cloudflare's infrastructure (DDoS protection)
- OAuth built-in
- No dynamic DNS needed

**Cons:**
- Requires Cloudflare account
- Traffic goes through Cloudflare
- Learning curve
- Less control

**Best for:**
- People uncomfortable with port forwarding
- Want enterprise-grade security
- Don't mind third-party involved

---

#### Option F: Tailscale (VPN Approach)
**Pros:**
- Zero authentication needed (VPN handles it)
- Works from anywhere
- No port forwarding
- Very secure (WireGuard)
- Easy to use

**Cons:**
- Requires Tailscale client on devices
- Not "web-native" (need VPN connected)
- Doesn't help with public-facing services

**Best for:**
- Personal access only
- Mobile access
- Maximum security
- **Actually might be perfect for you**

---

## 📋 Comparison Matrix

| Feature | None | Authelia | Tinyauth | BasicAuth | Cloudflare | Tailscale |
|---------|------|----------|----------|-----------|------------|-----------|
| **Setup Time** | 0 min | 3 days (failed) | 10 min | 5 min | 30 min | 20 min |
| **Complexity** | None | Very High | Low | Very Low | Medium | Low |
| **Containers** | 0 | 2 | 1 | 0 | 1 | 1 |
| **Dependencies** | None | Redis | None | None | Internet | Internet |
| **SSO** | No | Yes | Yes | No | Yes | N/A |
| **2FA** | No | Yes | Optional | No | Yes | Built-in |
| **OAuth** | No | Limited | Yes | No | Yes | N/A |
| **Reliability** | 100% | 0% (yours) | High | 100% | High | High |
| **Internet Exposure** | No | Yes | Yes | Yes | Yes | No (VPN) |
| **Your Success Rate** | 100% | 0% | Unknown | N/A | N/A | N/A |

---

## 🧪 What Does the Evidence Say?

### From Your 3-Day Journey:

**Facts:**
1. Jellyfin works perfectly WITHOUT authentication ✅
2. Authelia has failed repeatedly despite extensive effort ❌
3. DNS, Traefik, networking all work fine ✅
4. Problem is ONLY the authentication layer ❌
5. You have BTRFS snapshots to recover ✅

**Conclusion:**
Your infrastructure is solid. Authelia is the problem, not you.

---

## 💡 Recommendations Based on Your Needs

### Immediate Recommendation: **Choice Path Based on Goals**

#### If Goal: "Get homelab working, learn other things"
**→ Use Tinyauth or BasicAuth**
- Pros: Working in <10 minutes
- Cons: Not as feature-rich as Authelia
- Why: Your time is valuable, move forward

#### If Goal: "Learn complex auth systems, enjoy debugging"
**→ Keep trying Authelia**
- Pros: Learning experience
- Cons: More days of debugging
- Why: Educational value

#### If Goal: "Personal access only, maximum security"
**→ Use Tailscale**
- Pros: No auth layer needed, VPN handles everything
- Cons: Not for public services
- Why: Might be perfect for your use case

#### If Goal: "Expose to internet safely, zero hassle"
**→ Use Cloudflare Tunnel + Access**
- Pros: Handles DDNS + auth + security
- Cons: Traffic through Cloudflare
- Why: Comprehensive solution

---

## 🎲 My Honest Assessment

### What I Think You Should Do:

**Option 1: BTRFS Rollback + Tinyauth (RECOMMENDED)**

**Reasoning:**
1. Your BTRFS snapshot has a working state
2. Jellyfin working proves infrastructure is solid
3. Authelia has consumed 3 days without success
4. Tinyauth is purpose-built for exactly your use case
5. 10 minutes to working auth vs more days of Authelia debugging

**Steps:**
```bash
# 1. Rollback to pre-Authelia state
sudo btrfs subvolume snapshot /home /home-before-tinyauth
sudo btrfs subvolume delete /home/@home
sudo btrfs subvolume snapshot /home-snapshot-from-before-authelia /home/@home
reboot

# 2. Setup Tinyauth (10 minutes)
# 3. Back to building homelab features
```

**Why this makes sense:**
- Clean slate with working foundation
- Modern solution purpose-built for Traefik
- Proven to work for others
- Your goal is homelab, not authentication expert
- Time better spent on other projects

---

**Option 2: Keep Current State, Add BasicAuth (FASTEST)**

**Reasoning:**
1. Jellyfin already works
2. Just need Traefik dashboard access
3. 5 minutes to working
4. Can always switch to Tinyauth later

**Steps:**
```bash
# 1. Remove broken Authelia references
# 2. Add BasicAuth to Traefik
# 3. Done in 5 minutes
```

**Why this makes sense:**
- Minimal changes to working system
- Gets you unblocked immediately
- Can evaluate other options later
- No rollback needed

---

**Option 3: Try Authelia One More Time (NOT RECOMMENDED)**

**Reality check:**
- 3 days of effort already invested
- Still broken after multiple fix attempts
- Complexity indicates this will keep happening
- Your time is valuable

**Only do this if:**
- You specifically want to learn Authelia internals
- You have another week to debug
- You enjoy troubleshooting complex systems
- Authentication is your hobby project

---

## 📊 Current System Inventory

### Containers Running:
```
jellyfin        - Up 47 hours (healthy) ✅
authelia-redis  - Up 47 hours ❌ (orphaned)
traefik         - Up X seconds ✅ (partially working)
authelia        - Crash loop ❌
```

### Networks:
```
systemd-reverse_proxy - Traefik, Jellyfin ✅
systemd-auth_services - Redis, Authelia (broken) ❌
```

### Configuration Files:
```
~/containers/config/authelia/configuration.yml - 200+ lines, complex ❌
~/containers/config/traefik/traefik.yml - Working ✅
~/containers/config/traefik/dynamic/*.yml - Partially working
~/.config/containers/systemd/*.container - Mixed state
```

### Backups Available:
```
~/containers/backups/security-fixes-* - Multiple backups ✅
~/containers/backups/authelia-removal-* - Ready if needed ✅
BTRFS snapshots - Full system recovery available ✅
```

---

## 🎯 Decision Time: What Do YOU Want?

### Question 1: What's your primary goal?
- [ ] A) Get homelab working quickly
- [ ] B) Learn authentication systems deeply
- [ ] C) Just want Jellyfin accessible remotely
- [ ] D) Build a production-grade setup

### Question 2: How much more time to spend on auth?
- [ ] A) 10 minutes (BasicAuth or Tinyauth)
- [ ] B) Another day (keep trying Authelia)
- [ ] C) Doesn't matter, want it perfect

### Question 3: What features do you actually need?
- [ ] A) Just password protection
- [ ] B) SSO across services
- [ ] C) 2FA
- [ ] D) OAuth (Google login)
- [ ] E) All of the above

### Question 4: Internet exposure plans?
- [ ] A) LAN only for now
- [ ] B) Want internet access soon
- [ ] C) Internet access is main goal
- [ ] D) Just me via VPN is fine

---

## 🚀 Recommended Next Steps

### Based on Evidence:

**My recommendation: Option 1 (BTRFS Rollback + Tinyauth)**

**Why:**
1. **Evidence of Authelia complexity**: 3 days, still broken
2. **Evidence of working infrastructure**: Jellyfin works perfectly
3. **Evidence of valid alternative**: Tinyauth designed for this exact use case
4. **Evidence of time value**: You want to BUILD homelab, not debug auth
5. **Evidence of recoverability**: BTRFS snapshots = safety net

**This gets you:**
- Working authentication in 10 minutes
- Clean, simple setup
- Time to work on other homelab features
- Internet-ready when you need it
- Ability to try Authelia later if you want

---

## 📝 Dynamic DNS Solution (Separate Issue)

### Current Situation:
- Domain: patriark.org (registered at Hostinger)
- Server: 192.168.1.70 (local)
- Public IP: 62.249.184.112 (needs updating when it changes)

### Solution Options:

**Option A: Hostinger's API + ddclient**
- Install ddclient on your server
- Configure to update Hostinger DNS automatically
- Works with most ISPs

**Option B: Cloudflare (Recommended)**
- Transfer DNS to Cloudflare (free)
- Use Cloudflare DDNS updater
- Better tools, faster updates
- Bonus: Cloudflare Tunnel option available

**Option C: DuckDNS + CNAME**
- Free DDNS service
- Point subdomain CNAME to DuckDNS
- Simple, reliable

**I can provide detailed setup for whichever you choose after we solve the auth question.**

---

## ✅ Summary

**What works:**
- Jellyfin ✅
- Traefik (partial) ✅
- DNS ✅
- Networks ✅
- Your infrastructure ✅

**What doesn't:**
- Authelia ❌
- Traefik dashboard access ❌

**Evidence-based conclusion:**
- Authelia is too complex for your needs
- Tinyauth or BasicAuth will work better
- BTRFS rollback gives clean slate
- Focus on homelab features, not debugging auth

**Your call:**
What do you want to do? I'll support whatever decision you make, but the evidence points toward moving away from Authelia.

