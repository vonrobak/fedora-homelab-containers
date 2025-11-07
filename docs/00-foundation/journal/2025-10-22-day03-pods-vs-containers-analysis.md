# Pods vs Separate Containers: Decision Guide

## What We Built Today

### demo-stack Pod Architecture
```
Pod: demo-stack (10.89.0.x)
│
├─ demo-app (Flask web application)
│  ├─ Listens on: 0.0.0.0:5000
│  ├─ Connects to: localhost:5432 (PostgreSQL)
│  └─ Connects to: localhost:6379 (Redis)
│
├─ demo-db (PostgreSQL database)
│  └─ Listens on: 0.0.0.0:5432 (accessible within pod only)
│
└─ demo-cache (Redis)
   └─ Listens on: 0.0.0.0:6379 (accessible within pod only)

External Access: Host:8083 → Pod:5000 (app only)
Internal Communication: All via localhost (microseconds latency)
```

## Pods (Shared Network Namespace)

### ✅ Use Pods When:

1. **Tightly Coupled Services**
   - App depends on specific version of database
   - Services must be deployed together
   - Example: WordPress + MySQL, our demo-stack

2. **Low Latency Critical**
   - Microsecond-level communication needed
   - High-frequency inter-service calls
   - Example: Trading app + in-memory cache

3. **Sidecar Pattern**
   - Logging agent alongside app
   - Service mesh proxy (Envoy)
   - Monitoring agent
   - Example: App + Fluentd + Prometheus exporter

4. **Shared Fate Desired**
   - If one fails, all should fail together
   - Lifecycle is identical
   - Example: App + Database migration container

5. **Simplified Configuration**
   - No need for service discovery
   - No DNS lookup overhead
   - Localhost "just works"

### ❌ Don't Use Pods When:

1. **Independent Scaling Needed**
   - Scale app to 5 instances, DB stays at 1
   - Different resource requirements
   - Example: Stateless API + Shared PostgreSQL

2. **Different Update Cycles**
   - App updates weekly, DB updates yearly
   - Want to restart one without affecting others
   - Risk: Pod restart affects ALL containers

3. **Shared/Reusable Services**
   - One database serving multiple apps
   - Shared cache cluster
   - Central authentication service
   - Example: Multiple apps → One PostgreSQL

4. **Network Isolation Required**
   - Security boundaries between services
   - Multi-tenant applications
   - Compliance requirements
   - Example: Customer A app ←/→ Customer B app

5. **Service Discovery Needed**
   - Dynamic service locations
   - Load balancing across instances
   - Microservices architecture

## Separate Containers (Bridge Network)

### ✅ Use Separate Containers When:

1. **Microservices Architecture**
   - Independent deployment
   - Different teams own services
   - Example: API Gateway, Auth, User Service, Order Service

2. **Shared Infrastructure**
   - One PostgreSQL, many applications
   - Shared Redis cluster
   - Central logging service

3. **Horizontal Scaling**
   - Scale components independently
   - Example: 10 app containers → 1 DB container

4. **Service Mesh / Load Balancing**
   - Traffic routing between services
   - Canary deployments
   - A/B testing

## Performance Comparison

### Within Pod (localhost):
- **Latency**: 0.05-0.1 ms (microseconds)
- **Throughput**: 40+ Gbps (memory speed)
- **DNS**: Not needed
- **Overhead**: Minimal (kernel system call only)
- **Security**: Shared namespace (less isolation)

### Between Containers (bridge network):
- **Latency**: 0.5-2 ms (milliseconds)
- **Throughput**: 1-10 Gbps (depends on network)
- **DNS**: Required (aardvark-dns lookup)
- **Overhead**: Network stack processing
- **Security**: Isolated namespaces (better isolation)

**Performance gain**: localhost is typically **10-40x faster**

## Real-World Decision Examples

### Example 1: Nextcloud
**Should use: Pod** ✓
- App, Database, Redis, Cron tightly coupled
- Frequent DB queries (file metadata)
- Cache hit rate critical for performance
- All share same lifecycle
```
Pod: nextcloud
├─ nextcloud-app (PHP)
├─ nextcloud-db (PostgreSQL)
├─ nextcloud-redis (Cache)
└─ nextcloud-cron (Background jobs)
```

### Example 2: Multi-Service Platform
**Should use: Separate Containers** ✓
- Independent services
- Different scaling needs
- Shared database
```
Network: production
├─ traefik (1 instance - proxy)
├─ api-gateway (2 instances - load balanced)
├─ auth-service (2 instances)
├─ user-service (3 instances)
├─ order-service (5 instances - high traffic)
├─ postgres (1 instance - shared DB)
└─ redis (1 instance - shared cache)
```

### Example 3: GitLab
**Should use: Pod** ✓
- Complex application with many components
- All components must be same version
- Tight integration requirements
```
Pod: gitlab
├─ gitlab-app (Rails)
├─ gitlab-db (PostgreSQL)
├─ gitlab-redis (Cache)
├─ gitlab-sidekiq (Background jobs)
└─ gitlab-gitaly (Git repository storage)
```

## Port Conflicts in Pods

**Critical**: Only ONE container per port in a pod.
```bash
# ❌ THIS FAILS (both try port 80):
podman pod create --name webpod --publish 8080:80
podman run --pod webpod nginx:alpine    # Binds to 80
podman run --pod webpod httpd:alpine    # Tries to bind to 80 → ERROR

# ✓ THIS WORKS (different internal ports):
podman pod create --name webpod --publish 8080:80 --publish 8081:8080
podman run --pod webpod nginx:alpine           # Binds to 80
podman run --pod webpod -e PORT=8080 myapp    # Binds to 8080
```

## Migration Strategies

### From Separate Containers → Pod
1. Ensure services are on same network
2. Test connectivity via container names
3. Create pod with all containers
4. Update configs to use localhost
5. Test thoroughly before removing old setup

### From Pod → Separate Containers
1. Deploy new containers on bridge network
2. Update connection strings (localhost → container-name)
3. Test with both systems running
4. Switch traffic to new containers
5. Remove pod when confident

## Cost/Benefit Analysis

### Our demo-stack Example

**As Pod (current):**
- Pros: Simple, fast, easy to deploy
- Cons: Can't scale DB separately, all restart together
- **Best for**: Development, testing, single-user deployments

**As Separate Containers:**
- Pros: Can scale app independently, DB can be shared
- Cons: Slight latency overhead, more complex configuration
- **Best for**: Production, multi-app environments

## Summary Table

| Criteria | Use Pod | Use Separate Containers |
|----------|---------|------------------------|
| Coupling | Tight | Loose |
| Scaling | Together | Independent |
| Latency | Critical | Acceptable |
| Updates | Same cycle | Different cycles |
| Failure mode | Shared fate | Isolated |
| Configuration | Simple | Complex |
| Reusability | Low | High |
| Security isolation | Lower | Higher |

## Our Recommendation

**Start with separate containers** unless you specifically need:
- Microsecond latency (localhost)
- Simplified networking (no DNS)
- Atomic deployment (all or nothing)

**For homelab services:**
- Jellyfin: Separate container (standalone) ✓
- Nextcloud: Pod (app + DB + Redis + cron) ✓
- Traefik: Separate container (reverse proxy) ✓
- Monitoring: Separate containers (flexibility) ✓
- Demo/dev apps: Pods (simplicity) ✓
