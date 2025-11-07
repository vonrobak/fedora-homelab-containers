# Traefik Middleware Configuration: Analysis & Improvement Guide

**Current Config Analysis:** middleware.yml
**Focus:** CrowdSec integration, interoperability, and advanced patterns
**Last Updated:** October 26, 2025

---

## Table of Contents

1. [Current Configuration Analysis](#current-configuration-analysis)
2. [Immediate Improvements](#immediate-improvements)
3. [CrowdSec Deep Dive](#crowdsec-deep-dive)
4. [Advanced Middleware Patterns](#advanced-middleware-patterns)
5. [Future-Ready Configuration](#future-ready-configuration)
6. [Testing & Validation](#testing--validation)

---

## Current Configuration Analysis

### What You Have (Good Foundation!)

```yaml
http:
  middlewares:
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          enabled: true
          crowdsecMode: live
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiKey: *redacted*
    
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
    
    tinyauth:
      forwardAuth:
        address: "http://tinyauth:3000/api/auth/traefik"
        authResponseHeaders:
          - "Remote-User"
          - "Remote-Email"
          - "Remote-Name"
    
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        customFrameOptionsValue: "SAMEORIGIN"
```

### ✅ Strengths

1. **Good security foundation** - All essential layers present
2. **CrowdSec properly configured** - Plugin mode with LAPI connection
3. **Forward auth working** - Tinyauth integration
4. **Basic security headers** - HSTS, XSS protection, frame options
5. **Rate limiting** - Prevents basic abuse

### ⚠️  Areas for Improvement

1. **CrowdSec configuration is minimal** - Missing advanced features
2. **Single rate limit** - No differentiation by endpoint/user
3. **Limited security headers** - Missing CSP, Referrer-Policy, Permissions-Policy
4. **No request/response logging** - Hard to debug issues
5. **No IP whitelisting** - For admin access
6. **No circuit breaker** - For service health
7. **No retry logic** - For transient failures
8. **No compression** - For performance
9. **No custom error pages** - For better UX

---

## Immediate Improvements

### Improved Configuration (Version 2)

```yaml
http:
  middlewares:
    # ═══════════════════════════════════════════════════════════
    # CROWDSEC BOUNCER - Enhanced Configuration
    # ═══════════════════════════════════════════════════════════
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          # Core settings
          enabled: true
          logLevel: INFO
          updateIntervalSeconds: 60  # Cache refresh interval
          defaultDecisionSeconds: 60  # Default ban duration
          
          # LAPI Connection
          crowdsecMode: live
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiKey: *redacted*
          crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key  # Alternative: use file
          
          # Advanced features
          crowdsecCapiMachineId: ""  # For CAPI (community blocklist)
          crowdsecCapiPassword: ""   # For CAPI
          crowdsecCapiScenarios:     # Which scenarios to pull from CAPI
            - crowdsecurity/http-probing
            - crowdsecurity/http-crawl-non_statics
            - crowdsecurity/http-sensitive-files
          
          # Forwarded headers (for correct IP detection behind proxies)
          forwardedHeadersCustomName: X-Forwarded-For
          clientTrustedIPs:          # Trust these IPs for X-Forwarded-For
            - 10.89.2.0/24           # reverse_proxy network
            - 192.168.1.0/24         # Local network
          
          # Ban behavior
          httpTimeoutSeconds: 10
          crowdsecLapiTLSInsecureVerify: false
          
          # Custom ban page (optional)
          # banTemplateFile: /etc/traefik/ban-page.html

    # ═══════════════════════════════════════════════════════════
    # RATE LIMITING - Tiered approach
    # ═══════════════════════════════════════════════════════════
    
    # Standard rate limit (most services)
    rate-limit:
      rateLimit:
        average: 100      # 100 requests
        burst: 50         # Allow bursts of 50
        period: 1m        # Per minute
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1      # Use first IP in X-Forwarded-For
    
    # Strict rate limit (sensitive endpoints)
    rate-limit-strict:
      rateLimit:
        average: 30       # More restrictive
        burst: 10
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
    
    # Very strict rate limit (auth endpoints)
    rate-limit-auth:
      rateLimit:
        average: 10       # Very restrictive for login
        burst: 5
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1
    
    # Generous rate limit (public APIs)
    rate-limit-public:
      rateLimit:
        average: 200
        burst: 100
        period: 1m
        sourceCriterion:
          requestHost: true
          ipStrategy:
            depth: 1

    # ═══════════════════════════════════════════════════════════
    # AUTHENTICATION
    # ═══════════════════════════════════════════════════════════
    tinyauth:
      forwardAuth:
        address: "http://tinyauth:3000/api/auth/traefik"
        
        # Trust forward headers from auth service
        trustForwardHeader: true
        
        # Headers to pass to backend
        authResponseHeaders:
          - "Remote-User"
          - "Remote-Email"
          - "Remote-Name"
          - "Remote-Groups"      # For future RBAC
        
        # Headers to pass in auth request
        authRequestHeaders:
          - "X-Forwarded-Method"
          - "X-Forwarded-Proto"
          - "X-Forwarded-Host"
          - "X-Forwarded-Uri"
          - "X-Forwarded-For"
        
        # TLS configuration (for future HTTPS to auth service)
        # tls:
        #   ca: /path/to/ca.crt
        #   cert: /path/to/cert.crt
        #   key: /path/to/key.key
        #   insecureSkipVerify: false

    # ═══════════════════════════════════════════════════════════
    # SECURITY HEADERS - Comprehensive
    # ═══════════════════════════════════════════════════════════
    security-headers:
      headers:
        # Basic security
        frameDeny: false  # We'll use customFrameOptionsValue instead
        customFrameOptionsValue: "SAMEORIGIN"
        browserXssFilter: true
        contentTypeNosniff: true
        
        # HSTS (HTTP Strict Transport Security)
        stsSeconds: 31536000        # 1 year
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true        # Force even on HTTP
        
        # Content Security Policy (CSP)
        contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self';"
        
        # Referrer Policy
        referrerPolicy: "strict-origin-when-cross-origin"
        
        # Permissions Policy (formerly Feature Policy)
        permissionsPolicy: "geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()"
        
        # Additional security headers
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          X-Robots-Tag: "none"  # Prevent indexing of internal services
          Server: ""            # Hide server header
          X-Powered-By: ""      # Hide powered-by header
    
    # Strict headers for admin panels
    security-headers-strict:
      headers:
        frameDeny: true  # No iframes at all
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        contentSecurityPolicy: "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none';"
        referrerPolicy: "no-referrer"
        permissionsPolicy: "geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()"
        customResponseHeaders:
          X-Robots-Tag: "noindex, nofollow"
          Server: ""
    
    # Relaxed headers for public content
    security-headers-public:
      headers:
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        referrerPolicy: "strict-origin-when-cross-origin"
        # More permissive CSP for public content
        contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data: https:;"

    # ═══════════════════════════════════════════════════════════
    # IP WHITELISTING - For admin access
    # ═══════════════════════════════════════════════════════════
    admin-whitelist:
      ipWhiteList:
        sourceRange:
          - 192.168.1.0/24    # Local network
          - 10.89.2.0/24      # Container network
          # - YOUR_VPN_SUBNET  # Add your VPN subnet
        ipStrategy:
          depth: 1            # Check X-Forwarded-For

    # Trusted IPs only (for internal APIs)
    internal-only:
      ipWhiteList:
        sourceRange:
          - 10.89.2.0/24      # Only container network
          - 10.89.3.0/24      # Database network
          - 10.89.4.0/24      # Monitoring network

    # ═══════════════════════════════════════════════════════════
    # PERFORMANCE OPTIMIZATIONS
    # ═══════════════════════════════════════════════════════════
    compression:
      compress:
        excludedContentTypes:
          - text/event-stream  # Don't compress SSE
        minResponseBodyBytes: 1024  # Only compress responses > 1KB

    # ═══════════════════════════════════════════════════════════
    # RELIABILITY PATTERNS
    # ═══════════════════════════════════════════════════════════
    
    # Circuit breaker (prevents cascade failures)
    circuit-breaker:
      circuitBreaker:
        expression: "NetworkErrorRatio() > 0.30"  # Open if >30% network errors
        checkPeriod: 10s
        fallbackDuration: 30s
        recoveryDuration: 10s
    
    # Retry logic for transient failures
    retry:
      retry:
        attempts: 3
        initialInterval: 100ms

    # ═══════════════════════════════════════════════════════════
    # REQUEST MODIFICATION
    # ═══════════════════════════════════════════════════════════
    
    # Strip prefixes (for API versioning)
    strip-api-prefix:
      stripPrefix:
        prefixes:
          - /api/v1
          - /api/v2
    
    # Add prefix (for routing)
    add-api-prefix:
      addPrefix:
        prefix: /api

    # ═══════════════════════════════════════════════════════════
    # CORS HANDLING
    # ═══════════════════════════════════════════════════════════
    cors-headers:
      headers:
        accessControlAllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
        accessControlAllowHeaders:
          - "*"
        accessControlAllowOriginList:
          - "https://app.patriark.org"
          - "https://admin.patriark.org"
        accessControlMaxAge: 100
        addVaryHeader: true
        accessControlAllowCredentials: true

    # ═══════════════════════════════════════════════════════════
    # REDIRECT HANDLING
    # ═══════════════════════════════════════════════════════════
    
    # HTTPS redirect
    https-redirect:
      redirectScheme:
        scheme: https
        permanent: true
        port: 443
    
    # WWW redirect (if you want www.patriark.org → patriark.org)
    redirect-non-www:
      redirectRegex:
        regex: "^https://www\\.(.*)"
        replacement: "https://${1}"
        permanent: true

    # ═══════════════════════════════════════════════════════════
    # CUSTOM ERROR PAGES
    # ═══════════════════════════════════════════════════════════
    error-pages:
      errors:
        status:
          - "403"
          - "404"
          - "500"
          - "502"
          - "503"
        service: error-page-service
        query: /{status}.html

    # ═══════════════════════════════════════════════════════════
    # BUFFERING (for large uploads)
    # ═══════════════════════════════════════════════════════════
    buffering:
      buffering:
        maxRequestBodyBytes: 10485760  # 10 MB
        memRequestBodyBytes: 2097152   # 2 MB
        maxResponseBodyBytes: 10485760  # 10 MB
        memResponseBodyBytes: 2097152   # 2 MB
        retryExpression: "IsNetworkError() && Attempts() < 3"
```

---

## CrowdSec Deep Dive

### Understanding CrowdSec Bouncer Plugin

**How it works:**

```
┌─────────────────────────────────────────────────────────┐
│  CrowdSec Integration Flow                               │
└─────────────────────────────────────────────────────────┘

1. Traefik receives request
        │
        ↓
2. crowdsec-bouncer middleware checks
        │
        ├─→ Query LAPI: Is this IP banned?
        │   (Cache checked first, then LAPI if needed)
        │
        ├─→ Check decision cache
        │   └─ Hit: Use cached decision (fast)
        │   └─ Miss: Query LAPI (slower, but cached)
        │
        ↓
3. Decision made
        │
        ├─→ IP is banned
        │   └─ Return 403 Forbidden (request stops here)
        │
        └─→ IP is clean
            └─ Continue to next middleware

4. Cache updated every updateIntervalSeconds (60s)
```

### CrowdSec Configuration Explained

```yaml
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      # ════════════════════════════════════════════════════
      # LOGGING & MONITORING
      # ════════════════════════════════════════════════════
      enabled: true
      logLevel: INFO  # DEBUG for troubleshooting, INFO for production
      
      # ════════════════════════════════════════════════════
      # CACHE BEHAVIOR (Critical for Performance!)
      # ════════════════════════════════════════════════════
      updateIntervalSeconds: 60  # How often to refresh decision cache
      # Lower = More accurate but more LAPI queries
      # Higher = Better performance but slower ban propagation
      # Recommended: 60s (good balance)
      
      defaultDecisionSeconds: 60  # Default ban duration if not specified
      
      # ════════════════════════════════════════════════════
      # LAPI CONNECTION (Local API)
      # ════════════════════════════════════════════════════
      crowdsecMode: live  # "live" = query LAPI, "stream" = streaming (advanced)
      crowdsecLapiScheme: http  # Use "https" if you enable TLS
      crowdsecLapiHost: crowdsec:8080
      
      # Authentication (choose ONE method)
      crowdsecLapiKey: *redacted*  # Option 1: Inline key (current)
      # crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key  # Option 2: File (better!)
      
      # TLS settings (if using HTTPS to LAPI)
      # crowdsecLapiTLSInsecureVerify: false  # Verify TLS cert
      # crowdsecLapiTLSCertificateAuthority: /path/to/ca.pem
      # crowdsecLapiTLSCertificateBouncer: /path/to/bouncer.pem
      # crowdsecLapiTLSCertificateBouncerKey: /path/to/bouncer-key.pem
      
      # ════════════════════════════════════════════════════
      # CAPI INTEGRATION (Community API - Shared Blocklist)
      # ════════════════════════════════════════════════════
      # This is POWERFUL - subscribe to global threat intelligence!
      
      crowdsecCapiMachineId: ""     # Your CAPI machine ID
      crowdsecCapiPassword: ""      # Your CAPI password
      
      # Which attack scenarios to subscribe to
      crowdsecCapiScenarios:
        # Web attacks
        - crowdsecurity/http-probing
        - crowdsecurity/http-crawl-non_statics
        - crowdsecurity/http-sensitive-files
        - crowdsecurity/http-bad-user-agent
        - crowdsecurity/http-path-traversal-probing
        
        # Brute force
        - crowdsecurity/http-bf
        - crowdsecurity/http-bf-wordpress
        
        # CVE exploits
        - crowdsecurity/CVE-2021-41773  # Apache path traversal
        - crowdsecurity/CVE-2022-26134  # Confluence RCE
      
      # How to get CAPI credentials:
      # 1. Register on CrowdSec console: https://app.crowdsec.net
      # 2. Create a Security Engine
      # 3. Generate enrollment key
      # 4. Run: podman exec crowdsec cscli console enroll <key>
      # 5. Get machine ID: podman exec crowdsec cscli machines list
      
      # ════════════════════════════════════════════════════
      # IP DETECTION (CRITICAL for correct blocking!)
      # ════════════════════════════════════════════════════
      
      # Trust X-Forwarded-For from these IPs
      clientTrustedIPs:
        - 10.89.2.0/24    # reverse_proxy network (Traefik itself)
        - 192.168.1.0/24  # Local network (UDM Pro)
      
      # Custom header name (if not using X-Forwarded-For)
      forwardedHeadersCustomName: X-Forwarded-For
      
      # Why this matters:
      # Without proper IP detection, CrowdSec bans Traefik's IP
      # instead of the actual attacker's IP!
      
      # ════════════════════════════════════════════════════
      # BAN BEHAVIOR
      # ════════════════════════════════════════════════════
      httpTimeoutSeconds: 10  # Timeout for LAPI queries
      
      # Custom ban page (optional)
      # banTemplateFile: /etc/traefik/ban-page.html
      # Must be HTML with {{.Title}} and {{.Message}} placeholders
```

### CrowdSec LAPI Key Management (Best Practice)

**Current (less secure):**
```yaml
crowdsecLapiKey: <key-in-plaintext>
```

**Better (use file):**

1. **Create secret file:**
```bash
mkdir -p ~/containers/secrets
echo "your-api-key-here" > ~/containers/secrets/crowdsec_api_key
chmod 600 ~/containers/secrets/crowdsec_api_key
```

2. **Mount in Traefik quadlet:**
```ini
# ~/.config/containers/systemd/traefik.container
[Container]
Volume=%h/containers/secrets/crowdsec_api_key:/run/secrets/crowdsec_api_key:ro,Z
```

3. **Reference in middleware.yml:**
```yaml
crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
# Remove crowdsecLapiKey line
```

### Enabling CAPI (Community Blocklist)

**Step 1: Enroll CrowdSec**
```bash
# Get enrollment key from https://app.crowdsec.net
podman exec crowdsec cscli console enroll <your-enrollment-key>

# Verify enrollment
podman exec crowdsec cscli console status
```

**Step 2: Get Machine Credentials**
```bash
# List machines
podman exec crowdsec cscli machines list

# Output will show:
# NAME               IP ADDRESS    LAST UPDATE           STATUS  VERSION
# <machine-id>       172.x.x.x     2025-10-26T12:00:00Z  ✔️       v1.6.0

# Get machine password (for CAPI)
podman exec crowdsec cat /etc/crowdsec/local_api_credentials.yaml
```

**Step 3: Update Middleware**
```yaml
crowdsec-bouncer:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      crowdsecCapiMachineId: "<machine-id-from-step-2>"
      crowdsecCapiPassword: "<password-from-step-2>"
      crowdsecCapiScenarios:
        - crowdsecurity/http-probing
        - crowdsecurity/http-crawl-non_statics
        # Add more as needed
```

**Step 4: Verify**
```bash
# Check CAPI status
podman exec crowdsec cscli capi status

# Should show subscribed scenarios
podman exec crowdsec cscli scenarios list
```

**Benefits of CAPI:**
- Receive global blocklist of known bad IPs
- Community intelligence from thousands of CrowdSec users
- Proactive blocking before they attack you
- Reduced false positives (community-verified threats)

---

## Advanced Middleware Patterns

### Pattern 1: Middleware Chains for Different Service Types

```yaml
# In routers.yml, reference middleware chains:

http:
  routers:
    # ════════════════════════════════════════════════════
    # Public service (no auth)
    # ════════════════════════════════════════════════════
    homepage-router:
      rule: "Host(`home.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-public@file
        - compression@file
        - security-headers-public@file
      service: homepage-service
    
    # ════════════════════════════════════════════════════
    # Standard authenticated service
    # ════════════════════════════════════════════════════
    jellyfin-router:
      rule: "Host(`jellyfin.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - tinyauth@file
        - compression@file
        - security-headers@file
      service: jellyfin-service
    
    # ════════════════════════════════════════════════════
    # Admin panel (strict security)
    # ════════════════════════════════════════════════════
    traefik-router:
      rule: "Host(`traefik.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - admin-whitelist@file        # IP restriction
        - rate-limit-strict@file
        - tinyauth@file
        - security-headers-strict@file
      service: api@internal
    
    # ════════════════════════════════════════════════════
    # API endpoint (with CORS)
    # ════════════════════════════════════════════════════
    api-router:
      rule: "Host(`api.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit@file
        - cors-headers@file
        - tinyauth@file
        - compression@file
        - security-headers@file
      service: api-service
    
    # ════════════════════════════════════════════════════
    # Authentication endpoint (very strict rate limit)
    # ════════════════════════════════════════════════════
    auth-router:
      rule: "Host(`auth.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-auth@file        # Very strict
        - compression@file
        - security-headers-strict@file
      service: tinyauth-service
    
    # ════════════════════════════════════════════════════
    # Internal API (container network only)
    # ════════════════════════════════════════════════════
    internal-api-router:
      rule: "Host(`internal-api.patriark.org`)"
      middlewares:
        - internal-only@file          # IP whitelist
        - rate-limit@file
        - security-headers@file
      service: internal-api-service
```

### Pattern 2: Layered Security with Circuit Breakers

```yaml
# High-availability service with all protections
nextcloud-router:
  rule: "Host(`nextcloud.patriark.org`)"
  middlewares:
    # Layer 1: Security
    - crowdsec-bouncer@file
    - rate-limit@file
    
    # Layer 2: Reliability
    - circuit-breaker@file
    - retry@file
    
    # Layer 3: Authentication
    - tinyauth@file
    
    # Layer 4: Performance
    - compression@file
    - buffering@file
    
    # Layer 5: Headers
    - security-headers@file
  service: nextcloud-service
```

### Pattern 3: Conditional Middleware (Advanced)

```yaml
# Different behavior for internal vs external access
# Requires Traefik v3+ and advanced rules

http:
  routers:
    grafana-external:
      rule: "Host(`grafana.patriark.org`) && !ClientIP(`192.168.1.0/24`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-strict@file
        - tinyauth@file
        - security-headers@file
      service: grafana-service
      priority: 100
    
    grafana-internal:
      rule: "Host(`grafana.patriark.org`) && ClientIP(`192.168.1.0/24`)"
      middlewares:
        - rate-limit-public@file  # More lenient for internal
        - tinyauth@file
        - security-headers@file
      service: grafana-service
      priority: 101  # Higher priority = evaluated first
```

---

## Future-Ready Configuration

### Phase 1: Add Monitoring Stack (Current Priority)

```yaml
# Add these middlewares for monitoring services

http:
  middlewares:
    # Prometheus scraping (internal only)
    prometheus-whitelist:
      ipWhiteList:
        sourceRange:
          - 10.89.4.0/24  # monitoring network
    
    # Grafana-specific (already covered above)
    
    # Loki-specific (for log ingestion)
    loki-whitelist:
      ipWhiteList:
        sourceRange:
          - 10.89.2.0/24  # reverse_proxy network
          - 10.89.4.0/24  # monitoring network

# Router examples
  routers:
    prometheus-router:
      rule: "Host(`prometheus.patriark.org`)"
      middlewares:
        - prometheus-whitelist@file  # Internal only!
        - tinyauth@file
        - security-headers-strict@file
      service: prometheus-service
    
    loki-router:
      rule: "Host(`loki.patriark.org`)"
      middlewares:
        - loki-whitelist@file
        - rate-limit@file
        - tinyauth@file
      service: loki-service
```

### Phase 2: OAuth2/OIDC Integration (Future)

```yaml
# When migrating to Keycloak/Authentik

http:
  middlewares:
    # OAuth2 Proxy middleware
    oauth2-proxy:
      forwardAuth:
        address: "http://oauth2-proxy:4180"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Auth-Request-User
          - X-Auth-Request-Email
          - X-Auth-Request-Groups
          - X-Auth-Request-Access-Token
        authRequestHeaders:
          - Cookie
          - X-Forwarded-For
          - X-Forwarded-Proto
          - X-Forwarded-Host
    
    # Group-based access control
    admin-group-only:
      plugin:
        traefik-plugin-header-match:
          headers:
            X-Auth-Request-Groups:
              - admin
              - sysadmin

# Router with RBAC
  routers:
    admin-panel-router:
      rule: "Host(`admin.patriark.org`)"
      middlewares:
        - crowdsec-bouncer@file
        - rate-limit-strict@file
        - oauth2-proxy@file
        - admin-group-only@file  # Only admin group
        - security-headers-strict@file
      service: admin-service
```

### Phase 3: Advanced Observability

```yaml
# Add custom request/response logging

http:
  middlewares:
    # Access log middleware (Traefik v3+)
    access-log:
      accessLog:
        fields:
          defaultMode: keep
          names:
            ClientUsername: drop  # Don't log usernames in access logs
          headers:
            defaultMode: keep
            names:
              Authorization: drop  # Don't log auth headers
              Cookie: drop
    
    # Custom metrics
    custom-metrics:
      plugin:
        traefik-plugin-metrics:
          addStatusCodeLabel: true
          addMethodLabel: true
          addEntryPointLabel: true
```

### Phase 4: WAF Integration

```yaml
# Web Application Firewall (ModSecurity/Coraza)

http:
  middlewares:
    waf:
      plugin:
        traefik-modsecurity-plugin:
          modSecurityUrl: "http://waf:8080"
          maxBodySize: 10485760  # 10 MB
          timeout: 10s
          
# Chain before auth for pre-filtering
  routers:
    webapp-router:
      middlewares:
        - crowdsec-bouncer@file
        - waf@file              # Add WAF
        - rate-limit@file
        - tinyauth@file
```

---

## Testing & Validation

### Test CrowdSec Integration

```bash
# 1. Verify bouncer registration
podman exec crowdsec cscli bouncers list
# Should show traefik-bouncer as active

# 2. Test manual ban
MY_IP=$(curl -s ifconfig.me)
podman exec crowdsec cscli decisions add --ip $MY_IP --duration 5m --reason "Test ban"

# 3. Try accessing service
curl -I https://jellyfin.patriark.org
# Should return 403 Forbidden

# 4. Check Traefik logs
podman logs traefik | grep $MY_IP
# Should show "blocked by crowdsec"

# 5. Remove test ban
podman exec crowdsec cscli decisions delete --ip $MY_IP

# 6. Verify it works now
curl -I https://jellyfin.patriark.org
# Should return 200 or redirect to auth
```

### Test Rate Limiting

```bash
# Test rate limit with curl
for i in {1..150}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://jellyfin.patriark.org
  sleep 0.1
done

# First 100 should return 200/302
# Next 50 should return 200/302 (burst)
# After that should return 429 (Too Many Requests)
```

### Test Middleware Chain Order

```bash
# Test that CrowdSec blocks before auth
# 1. Ban your IP
podman exec crowdsec cscli decisions add --ip $(curl -s ifconfig.me) --duration 5m

# 2. Try to access (should get 403, not auth redirect)
curl -I https://jellyfin.patriark.org
# Expected: 403 Forbidden (not 302 to auth page)

# This confirms CrowdSec runs BEFORE auth middleware
```

### Test Security Headers

```bash
# Check security headers are applied
curl -I https://jellyfin.patriark.org

# Should see:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# X-Content-Type-Options: nosniff
# X-Frame-Options: SAMEORIGIN
# X-XSS-Protection: 1; mode=block
# Content-Security-Policy: ...
# Referrer-Policy: ...
```

### Monitor CrowdSec Metrics

```bash
# View CrowdSec metrics
podman exec crowdsec cscli metrics

# View decisions (bans)
podman exec crowdsec cscli decisions list

# View alerts
podman exec crowdsec cscli alerts list

# View hub scenarios
podman exec crowdsec cscli scenarios list
```

---

## Summary: Recommended Immediate Changes

### 1. **Move API Key to Secret File** (Security)
```bash
# Create secret
echo "your-api-key" > ~/containers/secrets/crowdsec_api_key
chmod 600 ~/containers/secrets/crowdsec_api_key

# Update traefik.container
Volume=%h/containers/secrets:/run/secrets:ro,Z

# Update middleware.yml
crowdsecLapiKeyFile: /run/secrets/crowdsec_api_key
```

### 2. **Add Advanced CrowdSec Features** (Security)
```yaml
# Add to middleware.yml
updateIntervalSeconds: 60
logLevel: INFO
clientTrustedIPs:
  - 10.89.2.0/24
  - 192.168.1.0/24
forwardedHeadersCustomName: X-Forwarded-For
```

### 3. **Enable CAPI** (Security)
```bash
# Enroll with CrowdSec console
podman exec crowdsec cscli console enroll <key>

# Update middleware.yml with CAPI credentials
```

### 4. **Add Tiered Rate Limiting** (Performance & Security)
```yaml
# Add to middleware.yml
rate-limit-strict:   # For admin panels
rate-limit-auth:     # For auth endpoints
rate-limit-public:   # For public content
```

### 5. **Enhance Security Headers** (Security)
```yaml
# Add CSP, Referrer-Policy, Permissions-Policy
# See improved configuration above
```

### 6. **Add IP Whitelisting** (Security)
```yaml
# For admin panels
admin-whitelist:
  ipWhiteList:
    sourceRange:
      - 192.168.1.0/24
```

### 7. **Add Compression** (Performance)
```yaml
compression:
  compress: {}
```

---

## Quick Reference: Middleware Order by Service Type

```
PUBLIC SERVICE:
  crowdsec → rate-limit-public → compression → headers-public

AUTHENTICATED SERVICE:
  crowdsec → rate-limit → auth → compression → headers

ADMIN PANEL:
  crowdsec → ip-whitelist → rate-limit-strict → auth → headers-strict

API ENDPOINT:
  crowdsec → rate-limit → cors → auth → compression → headers

AUTH ENDPOINT:
  crowdsec → rate-limit-auth → compression → headers-strict

INTERNAL ONLY:
  internal-only → rate-limit → headers
```

---

**Document Version:** 1.0
**Created:** October 26, 2025
**Purpose:** Comprehensive middleware configuration guide with focus on CrowdSec and interoperability
