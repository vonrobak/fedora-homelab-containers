# Day 6: Quadlet Migration Success

## What We Learned (The Hard Way!)

### Key Insight: Quadlet Network Naming
**Critical Discovery:** Quadlet-managed networks are prefixed with `systemd-`

- Quadlet file: `media_services.network`
- Actual network: `systemd-media_services`
- Reference in containers: `Network=media_services.network`

### The Problem We Solved
1. **Initial issue:** Old networks existed from manual creation
2. **Error:** "subnet already used" - Quadlets couldn't create duplicates
3. **Solution:** Remove old networks, let Quadlets create them fresh
4. **Result:** Properly managed infrastructure

### Troubleshooting Process
1. ✓ Read actual error messages (journalctl)
2. ✓ Check systemd dependencies (list-dependencies)
3. ✓ Verify what exists (podman network ls)
4. ✓ Remove conflicting resources
5. ✓ Let Quadlets manage lifecycle

## Final Working Configuration

### Network Quadlets
Location: `~/.config/containers/systemd/*.network`

**media_services.network:**
```ini
[Unit]
Description=Media Services Network

[Network]
Subnet=10.89.1.0/24
Gateway=10.89.1.1
DNS=192.168.1.69
```

**reverse_proxy.network:**
```ini
[Unit]
Description=Reverse Proxy Network

[Network]
Subnet=10.89.2.0/24
Gateway=10.89.2.1
DNS=192.168.1.69
```

### Container Quadlet
Location: `~/.config/containers/systemd/jellyfin.container`

**Key sections:**
```ini
[Container]
# Reference networks by their .network filename
Network=media_services.network
Network=reverse_proxy.network

# Traefik labels (critical for reverse proxy)
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.lokal`)
Label=traefik.http.routers.jellyfin.entrypoints=websecure
Label=traefik.http.routers.jellyfin.tls=true
Label=traefik.http.services.jellyfin.loadbalancer.server.port=8096
Label=traefik.http.routers.jellyfin.middlewares=authelia@file,security-headers@file
Label=traefik.docker.network=reverse_proxy
```

### Systemd Generated Services
Quadlets automatically generate:
- `jellyfin.service` ← from jellyfin.container
- `media_services-network.service` ← from media_services.network
- `reverse_proxy-network.service` ← from reverse_proxy.network

**Dependencies:** jellyfin.service requires both network services to start first.

## Verification Results
```bash
# Container running: ✓
podman ps | grep jellyfin
# e0fcd8270201  jellyfin  Up 42 seconds (healthy)

# Networks connected: ✓
podman inspect jellyfin | jq -r '.[0].NetworkSettings.Networks | keys[]'
# systemd-media_services
# systemd-reverse_proxy

# Traefik labels present: ✓
podman inspect jellyfin | jq '.[0].Config.Labels' | grep traefik
# 7 traefik labels found
```

## Systems Design Concepts Applied

1. **Declarative Infrastructure**
   - Describe desired state in files
   - System ensures state is achieved
   - No imperative "how to" commands

2. **Dependency Management**
   - Networks must exist before containers
   - Systemd handles ordering automatically
   - Failures cascade appropriately

3. **Idempotency**
   - Running daemon-reload multiple times = same result
   - Systemd figures out what changed
   - Safe to repeat operations

4. **Resource Lifecycle**
   - Networks created by Quadlets
   - Containers reference networks
   - Proper cleanup on removal

5. **Separation of Concerns**
   - Network configuration in .network files
   - Container configuration in .container files
   - Each component manages one thing well

## What Makes Quadlets Better

| Aspect | Generated Services | Quadlets |
|--------|-------------------|----------|
| Configuration | Imperative (commands) | Declarative (state) |
| Readability | Low (100+ lines bash) | High (60 lines INI) |
| Maintenance | Regenerate each time | Edit and reload |
| Networks | Manual creation | Managed by systemd |
| Dependencies | Manual ordering | Automatic |
| Debugging | Difficult | Clear error messages |

## Lessons Learned

1. **Read the errors carefully** - They tell you exactly what's wrong
2. **Check what exists** - Don't assume, verify
3. **Understand the tools** - Quadlets have specific behaviors (naming, prefixes)
4. **Clean slate helps** - Remove conflicts, let tools manage resources
5. **Patience pays off** - Troubleshooting teaches more than instant success

## Next Steps

Now that Jellyfin runs from Quadlet:
- ✓ All configuration in version-controllable files
- ✓ Easy to replicate on another system
- ✓ Clear separation of concerns
- ✓ Proper systemd integration
- → Ready to verify Traefik integration
- → Ready to add more services (Nextcloud on Day 8)

## Commands Reference
```bash
# View Quadlet files
ls -la ~/.config/containers/systemd/

# Reload after editing
systemctl --user daemon-reload

# Manage services
systemctl --user start jellyfin.service
systemctl --user status jellyfin.service
systemctl --user restart jellyfin.service

# Check dependencies
systemctl --user list-dependencies jellyfin.service

# View generated services
systemctl --user cat jellyfin.service

# Debug network issues
journalctl --user -u media_services-network.service -n 20
journalctl --user -u reverse_proxy-network.service -n 20
```

## Achievement Unlocked: Systems Administrator

You just debugged a complex systemd + Podman + networking issue by:
- Reading logs systematically
- Understanding dependencies
- Resolving resource conflicts
- Implementing infrastructure as code

**This is professional-level systems work!** 🎓
