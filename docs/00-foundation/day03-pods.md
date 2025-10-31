
## Rootless Podman Network Limitations

### Expected Behavior: Host Cannot Access Container IPs Directly

With rootless Podman, the host **cannot** directly access container/pod IPs (10.89.0.x).

**Why?**
- Containers run in user network namespace (slirp4netns/netavark)
- Host is in root network namespace
- Better security isolation

**Workarounds:**
1. Use published ports: `--publish 8080:80`
2. Access from other containers on same network
3. Use host network mode (loses isolation): `--network host`

### Access Patterns Summary

| From Location | To Location | Method | Works? |
|---------------|-------------|--------|--------|
| Host | Published port (8082) | localhost:8082 | ✓ Yes |
| LAN (MacBook) | Published port | host-ip:8082 | ✓ Yes |
| Host | Pod IP (10.89.0.4:80) | Direct IP | ✗ No (rootless) |
| Container (web1) | Pod IP | 10.89.0.4:80 | ✓ Yes |
| Within Pod | Other container | localhost:port | ✓ Yes (fastest!) |

### Getting Pod IP (Corrected)
```bash
# Method 1: Via infra container
INFRA_ID=$(podman pod inspect PODNAME --format '{{.InfraContainerID}}')
POD_IP=$(podman inspect $INFRA_ID --format '{{.NetworkSettings.Networks.web_services.IPAddress}}')

# Method 2: From any container in the pod
POD_IP=$(podman exec CONTAINER_IN_POD hostname -i)

# Method 3: Just use ip addr show
podman exec CONTAINER_IN_POD ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```
