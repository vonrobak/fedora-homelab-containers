# Architecture Diagrams - Homelab Infrastructure

**Note:** These diagrams use Mermaid syntax and render automatically in GitHub, GitLab, and many markdown viewers.

---

## 1. High-Level System Architecture

```mermaid
graph TB
    Internet((Internet))
    Router[Home Router<br/>Port Forward 80/443]
    Traefik[Traefik Reverse Proxy<br/>Let's Encrypt TLS]

    Internet --> Router
    Router --> Traefik

    Traefik --> CrowdSec[CrowdSec<br/>IP Reputation]
    Traefik --> Authelia[Authelia SSO<br/>YubiKey 2FA]
    Authelia --> Redis[Redis<br/>Session Storage]

    Traefik --> Media[Media Services]
    Traefik --> Monitoring[Monitoring Stack]
    Traefik --> Photos[Photo Management]

    Media --> Jellyfin[Jellyfin<br/>Media Streaming]

    Photos --> Immich[Immich<br/>Photo Management]
    Photos --> ImmichML[Immich ML<br/>Face Detection]
    Photos --> Postgres[PostgreSQL<br/>Immich Database]

    Monitoring --> Prometheus[Prometheus<br/>Metrics]
    Monitoring --> Grafana[Grafana<br/>Dashboards]
    Monitoring --> Loki[Loki<br/>Log Aggregation]
    Monitoring --> Alertmanager[Alertmanager<br/>Discord Alerts]

    style Traefik fill:#ff9900
    style Authelia fill:#ff6b6b
    style CrowdSec fill:#4ecdc4
    style Prometheus fill:#e84a5f
    style Grafana fill:#f79f1f
```

---

## 2. Security Layers (Fail-Fast Architecture)

```mermaid
graph LR
    A[Internet Request] --> B{1. CrowdSec<br/>IP Reputation}
    B -->|Known Attacker| Z1[❌ Blocked]
    B -->|Clean IP| C{2. Rate Limiting<br/>100-200 req/min}
    C -->|Exceeded| Z2[❌ HTTP 429]
    C -->|Within Limit| D{3. Authelia SSO<br/>YubiKey + Password}
    D -->|Not Authenticated| Z3[❌ Redirect to SSO]
    D -->|Authenticated| E[4. Security Headers<br/>HSTS, CSP]
    E --> F[✅ Backend Service]

    style B fill:#4ecdc4
    style C fill:#feca57
    style D fill:#ff6b6b
    style E fill:#48dbfb
    style F fill:#1dd1a1
    style Z1 fill:#ee5a6f
    style Z2 fill:#ee5a6f
    style Z3 fill:#ee5a6f
```

**Why this order?**
- Each layer is computationally more expensive than the previous
- Reject bad traffic early (fail-fast) to save resources
- CrowdSec: Cache lookup (~1ms)
- Rate limiting: Memory check (~5ms)
- Authelia: Database + session + WebAuthn (~50-200ms)

---

## 3. Network Segmentation

```mermaid
graph TB
    subgraph "systemd-reverse_proxy"
        Traefik[Traefik]
        Authelia[Authelia]
        Jellyfin[Jellyfin]
        Immich[Immich]
        Homepage[Homepage]
    end

    subgraph "systemd-auth_services"
        Authelia2[Authelia]
        Redis[Redis Session Storage]
    end

    subgraph "systemd-media_services"
        Jellyfin2[Jellyfin]
    end

    subgraph "systemd-photos"
        Immich2[Immich]
        ImmichML[Immich ML]
        Postgres[PostgreSQL]
        RedisImmich[Redis Immich]
    end

    subgraph "systemd-monitoring"
        Prometheus[Prometheus]
        Grafana[Grafana]
        Loki[Loki]
        Promtail[Promtail]
        Alertmanager[Alertmanager]
        NodeExporter[Node Exporter]
        cAdvisor[cAdvisor]
    end

    Traefik -.->|auth check| Authelia2
    Authelia2 -.->|session| Redis

    style Traefik fill:#ff9900
    style Authelia fill:#ff6b6b
    style Authelia2 fill:#ff6b6b
    style Redis fill:#d63031
```

**Key Principles:**
- Services join networks based on trust level and communication needs
- First network in quadlet determines default route
- Internal-only services on single network
- External services span multiple networks

---

## 4. Authentication Flow

```mermaid
sequenceDiagram
    participant User
    participant Browser
    participant Traefik
    participant Authelia
    participant Redis
    participant Service
    participant YubiKey

    User->>Browser: Navigate to grafana.patriark.org
    Browser->>Traefik: HTTPS Request
    Traefik->>Authelia: Verify session (ForwardAuth)
    Authelia->>Redis: Check session
    Redis-->>Authelia: No valid session
    Authelia-->>Traefik: HTTP 302 (Redirect to SSO)
    Traefik-->>Browser: Redirect to sso.patriark.org

    Browser->>Authelia: Show login page
    User->>Browser: Enter username + password
    Browser->>Authelia: Submit credentials
    Authelia->>Authelia: Validate password (Argon2id)
    Authelia-->>Browser: Prompt for 2FA (WebAuthn)

    Browser->>YubiKey: Request assertion
    User->>YubiKey: Touch key
    YubiKey-->>Browser: Signed assertion
    Browser->>Authelia: Submit WebAuthn assertion
    Authelia->>Authelia: Verify YubiKey signature
    Authelia->>Redis: Create session (1h TTL)
    Authelia-->>Browser: HTTP 302 (Redirect to Grafana)

    Browser->>Traefik: HTTPS Request (with session cookie)
    Traefik->>Authelia: Verify session
    Authelia->>Redis: Check session
    Redis-->>Authelia: Valid session
    Authelia-->>Traefik: HTTP 200 + Headers
    Traefik->>Service: Forward request (with auth headers)
    Service-->>Browser: Grafana dashboard

    Note over Browser,Redis: Subsequent requests use cached session (no YubiKey required)
```

---

## 5. Monitoring & Observability Architecture

```mermaid
graph TB
    subgraph "Data Sources"
        Containers[16 Containers<br/>stdout/stderr]
        SystemdJournal[Systemd Journal<br/>Service logs]
        NodeMetrics[Node Exporter<br/>System metrics]
        cAdvisor[cAdvisor<br/>Container metrics]
        TraefikMetrics[Traefik<br/>HTTP metrics]
        AutheliaMetrics[Authelia<br/>Auth metrics]
    end

    subgraph "Collection"
        Promtail[Promtail<br/>Log Shipper]
        Prometheus[Prometheus<br/>Metrics Scraper<br/>15s interval]
    end

    subgraph "Storage"
        Loki[Loki<br/>Log Storage<br/>7-day retention]
        PrometheusDB[Prometheus TSDB<br/>15-day retention]
    end

    subgraph "Visualization & Alerting"
        Grafana[Grafana<br/>Dashboards]
        Alertmanager[Alertmanager<br/>Alert Router]
        Discord[Discord<br/>Webhook Notifications]
    end

    Containers --> Promtail
    SystemdJournal --> Promtail
    Promtail --> Loki

    NodeMetrics --> Prometheus
    cAdvisor --> Prometheus
    TraefikMetrics --> Prometheus
    AutheliaMetrics --> Prometheus
    Prometheus --> PrometheusDB

    PrometheusDB --> Grafana
    Loki --> Grafana

    PrometheusDB --> Alertmanager
    Alertmanager --> Discord

    style Prometheus fill:#e84a5f
    style Grafana fill:#f79f1f
    style Loki fill:#00b894
    style Alertmanager fill:#fdcb6e
    style Discord fill:#7289da
```

**Three Pillars of Observability:**
1. **Metrics** (Prometheus) - What is happening? (counters, gauges, histograms)
2. **Logs** (Loki) - Why is it happening? (event details)
3. **Alerts** (Alertmanager) - When should I be notified?

---

## 6. Data Flow - User Request Journey

```mermaid
flowchart TD
    Start([User: https://grafana.patriark.org])
    DNS[DNS Resolution<br/>→ Public IP]
    Router[Router Port Forward<br/>80/443 → fedora-htpc]

    Start --> DNS
    DNS --> Router
    Router --> Traefik

    Traefik{Traefik<br/>Reverse Proxy}

    Traefik --> MW1{CrowdSec<br/>Middleware}
    MW1 -->|Malicious IP| Block1[❌ HTTP 403<br/>Blocked by CrowdSec]
    MW1 -->|Clean IP| MW2{Rate Limit<br/>Middleware}

    MW2 -->|Exceeded| Block2[❌ HTTP 429<br/>Too Many Requests]
    MW2 -->|Within Limit| MW3{Authelia<br/>Middleware}

    MW3 -->|No Session| Redirect[HTTP 302<br/>→ sso.patriark.org]
    Redirect --> SSO[SSO Portal<br/>Username + Password + YubiKey]
    SSO -->|Authenticated| Session[Create Session<br/>Redis 1h TTL]
    Session --> MW3

    MW3 -->|Valid Session| MW4[Security Headers<br/>Middleware]
    MW4 --> GrafanaService[Grafana Container<br/>:3000]
    GrafanaService --> Response[✅ HTTP 200<br/>Grafana Dashboard]

    Response --> User([User Browser])

    style Traefik fill:#ff9900
    style MW1 fill:#4ecdc4
    style MW2 fill:#feca57
    style MW3 fill:#ff6b6b
    style MW4 fill:#48dbfb
    style GrafanaService fill:#1dd1a1
    style Block1 fill:#ee5a6f
    style Block2 fill:#ee5a6f
```

---

## 7. Service Dependencies

```mermaid
graph TD
    Traefik[Traefik<br/>Reverse Proxy]
    Authelia[Authelia<br/>SSO]
    Redis[Redis<br/>Sessions]
    CrowdSec[CrowdSec<br/>Bouncer]

    Grafana[Grafana]
    Prometheus[Prometheus]
    Loki[Loki]
    Alertmanager[Alertmanager]

    Jellyfin[Jellyfin]

    Immich[Immich]
    ImmichML[Immich ML]
    Postgres[PostgreSQL]
    RedisImmich[Redis Immich]

    Traefik --> Authelia
    Authelia --> Redis
    Traefik --> CrowdSec

    Traefik --> Grafana
    Traefik --> Prometheus
    Traefik --> Loki
    Traefik --> Alertmanager

    Grafana --> Prometheus
    Grafana --> Loki
    Alertmanager --> Prometheus

    Traefik --> Jellyfin

    Traefik --> Immich
    Immich --> ImmichML
    Immich --> Postgres
    Immich --> RedisImmich

    style Traefik fill:#ff9900
    style Authelia fill:#ff6b6b
    style Redis fill:#d63031
    style Prometheus fill:#e84a5f
    style Grafana fill:#f79f1f
```

**Critical Dependencies:**
- **Traefik** depends on nothing (entry point)
- **Authelia** depends on Redis (sessions)
- **Grafana** depends on Prometheus + Loki (data sources)
- **Immich** depends on PostgreSQL + Redis + Immich ML

---

## 8. Deployment Workflow

```mermaid
flowchart LR
    Start([New Service<br/>Deployment])

    Create[Create Quadlet<br/>~/.config/containers/systemd/]
    Config[Configure Traefik<br/>dynamic/routers.yml<br/>dynamic/middleware.yml]
    AccessControl[Configure Authelia<br/>access_control rules]

    Reload[systemctl --user<br/>daemon-reload]
    Start2[systemctl --user<br/>start service.service]

    Health{Health Check<br/>Passing?}
    Monitor[Monitor Logs<br/>podman logs -f]

    Start --> Create
    Create --> Config
    Config --> AccessControl
    AccessControl --> Reload
    Reload --> Start2
    Start2 --> Health

    Health -->|No| Monitor
    Monitor --> Troubleshoot[Troubleshoot<br/>Fix Issues]
    Troubleshoot --> Reload

    Health -->|Yes| Enable[systemctl --user<br/>enable service.service]
    Enable --> Document[Update Documentation<br/>Service guide]
    Document --> Done([✅ Deployment<br/>Complete])

    style Create fill:#3498db
    style Config fill:#9b59b6
    style AccessControl fill:#e74c3c
    style Health fill:#f39c12
    style Done fill:#2ecc71
```

---

## 9. Backup Strategy

```mermaid
graph TB
    System[System SSD<br/>128GB]
    BTRFS[BTRFS Pool<br/>3x 4TB HDDs]

    subgraph "Backup Workflow"
        Subvol[subvol7-containers<br/>Container Data]
        Snapshot[BTRFS Snapshot<br/>btrfs-snapshot-backup.sh]
        Store[snapshots/<br/>Retention Policy]
    end

    System -->|Container configs| Git[Git Repository<br/>400+ commits]
    BTRFS --> Subvol
    Subvol -->|Daily 2am| Snapshot
    Snapshot --> Store

    Store -->|Retention| Daily[7 Daily<br/>Snapshots]
    Store -->|Retention| Weekly[4 Weekly<br/>Snapshots]
    Store -->|Retention| Monthly[6 Monthly<br/>Snapshots]

    Git -->|Push| GitHub[GitHub Repository<br/>Off-site Backup]

    style Git fill:#f39c12
    style Snapshot fill:#2ecc71
    style GitHub fill:#3498db
```

**Backup Coverage:**
- **Configurations:** Git repository (version-controlled)
- **Container data:** BTRFS snapshots (point-in-time recovery)
- **Secrets:** Podman secrets (tmpfs, not persisted - manual backup required)

---

## 10. Health Check & Auto-Recovery

```mermaid
stateDiagram-v2
    [*] --> Healthy: Service starts

    Healthy --> Checking: Health check interval<br/>(10-30s)
    Checking --> Healthy: Check passes
    Checking --> Unhealthy: Check fails

    Unhealthy --> Checking: Retry (3 attempts)
    Unhealthy --> Restarting: Health check failed<br/>3 times

    Restarting --> Starting: systemd restarts<br/>service
    Starting --> Healthy: Health check passes<br/>after restart
    Starting --> Failed: Restart failed<br/>multiple times

    Failed --> ManualIntervention: Requires admin<br/>investigation

    note right of Healthy
        Service operational
        Accepting requests
    end note

    note right of Unhealthy
        Service degraded
        Not accepting requests
    end note

    note right of Failed
        Persistent failure
        Alert triggered
    end note
```

**Auto-Recovery Configuration:**
```ini
[Container]
HealthCmd=wget --spider http://localhost:9091/api/health
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s

[Service]
Restart=on-failure
RestartSec=30s
```

---

## Diagram Usage

### For Portfolio/Resume

1. **High-Level Architecture** - Shows overall system design
2. **Security Layers** - Demonstrates defense-in-depth
3. **Monitoring Architecture** - Shows observability practices

### For Documentation

4. **Network Segmentation** - Reference for service deployment
5. **Authentication Flow** - Troubleshooting SSO issues
6. **Data Flow** - Understanding request journey

### For Presentations

7. **Service Dependencies** - Understanding critical paths
8. **Deployment Workflow** - Onboarding new team members
9. **Backup Strategy** - Disaster recovery planning

---

## How to View These Diagrams

**GitHub/GitLab:** Renders automatically in markdown files

**VS Code:** Install "Markdown Preview Mermaid Support" extension

**Online:** Copy to https://mermaid.live for editing

**Export:** Use mermaid-cli to generate PNG/SVG:
```bash
npm install -g @mermaid-js/mermaid-cli
mmdc -i ARCHITECTURE-DIAGRAMS.md -o diagrams.pdf
```

---

**Pro Tip:** These diagrams can be embedded in your portfolio website, presentations, or printed documentation. They're version-controlled in Git and update as the architecture evolves.
