# Podman Pod Commands Reference

## Pod Lifecycle

### Create Pod
```bash
# Basic pod
podman pod create --name mypod

# With published ports
podman pod create --name mypod --publish 8080:80

# With network
podman pod create --name mypod --network web_services

# Multiple ports
podman pod create --name mypod \
  --publish 8080:80 \
  --publish 8443:443
```

### Manage Pods
```bash
# List pods
podman pod ps

# Inspect pod
podman pod inspect mypod

# Start/stop/restart
podman pod start mypod
podman pod stop mypod
podman pod restart mypod

# Remove pod (stops all containers)
podman pod rm -f mypod
```

## Container Management in Pods

### Add Containers
```bash
# Run container in pod
podman run -d --pod mypod --name web nginx:alpine

# Multiple containers share network
podman run -d --pod mypod --name app myapp:latest
podman run -d --pod mypod --name db postgres:16
```

### List Containers in Pod
```bash
# Filter by pod
podman ps --filter pod=mypod

# Get pod details
podman pod inspect mypod | jq '.[].Containers[].Name'
```

## Networking

### Get Pod IP
```bash
# Via infra container
INFRA_ID=$(podman pod inspect mypod --format '{{.InfraContainerID}}')
podman inspect $INFRA_ID --format '{{.NetworkSettings.Networks.web_services.IPAddress}}'

# Or from any container in pod
podman exec CONTAINER_IN_POD hostname -i
```

### Published Ports
```bash
# Ports published at POD level
podman pod create --name web --publish 8080:80

# Containers bind internally
podman run -d --pod web nginx:alpine  # Listens on 80

# Access via host port
curl http://localhost:8080
```

## Systemd Integration

### Generate Systemd Services
```bash
# For entire pod
cd ~/.config/systemd/user
podman generate systemd --name mypod --files --new

# Generates:
# - pod-mypod.service
# - container-xxx.service (for each container)
# All with proper dependencies

# Enable and start
systemctl --user enable --now pod-mypod.service
```

## Troubleshooting

### Pod Won't Start
```bash
# Check pod status
podman pod ps -a

# Check logs
podman pod logs mypod

# Check individual containers
podman ps -a --filter pod=mypod
podman logs CONTAINER_NAME
```

### Port Already in Use
```bash
# Find what's using the port
ss -tlnp | grep 8080

# Check other pods
podman pod ps

# Stop conflicting service
sudo systemctl stop SERVICE_NAME
```

### Container Can't Communicate
```bash
# Verify shared namespace
podman exec container1 hostname -i
podman exec container2 hostname -i
# Should be SAME IP

# Check service is listening
podman exec container1 ss -tlnp | grep PORT

# Test from another container in pod
podman exec container2 curl http://localhost:PORT
```
