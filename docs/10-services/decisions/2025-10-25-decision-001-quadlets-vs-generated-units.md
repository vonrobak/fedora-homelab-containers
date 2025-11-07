# Quadlets vs Generated Systemd Services

## Why Quadlets Are Better

### 1. **Native Systemd Integration**
- Quadlets are actual systemd unit files
- Not generated scripts that call podman commands
- Systemd understands the configuration directly

### 2. **Declarative Configuration**
- Everything in one readable file
- No need to regenerate when making changes
- Just edit the .container file and reload

### 3. **Easier to Maintain**
```ini
# Quadlet (Simple!)
[Container]
PublishPort=8096:8096
Volume=%h/containers/config/jellyfin:/config:Z
```

vs
```bash
# Generated Service (Complex!)
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run --cidfile=%t/%n.ctr-id --cgroups=no-conmon...
ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
```

### 4. **Auto-Update Support**
```ini
[Container]
AutoUpdate=registry  # Built-in support!
```

Then use:
```bash
podman auto-update  # Updates all containers with AutoUpdate=registry
```

### 5. **Better Dependency Management**
```ini
[Unit]
After=network-online.target postgres.service
Requires=postgres.service
```

Systemd understands these relationships natively.

### 6. **No Regeneration Needed**
**Generated service:** Change volume? Regenerate entire service file.
**Quadlet:** Change volume? Edit one line, reload systemd.

## File Locations

### Quadlets
- System-wide: `/etc/containers/systemd/`
- User: `~/.config/containers/systemd/`

### What You Create
- `jellyfin.container` - Container configuration
- `media_services.network` - Network configuration
- `myapp.pod` - Pod configuration (if needed)

### What Systemd Creates (automatically)
- `jellyfin.service` - Actual systemd service
- Generated at: `systemctl --user daemon-reload`

## Quadlet Types

### .container
For individual containers (what we used for Jellyfin)

### .pod
For pods (we'll use this for Nextcloud)

### .volume
For named volumes

### .network
For custom networks

### .kube
For Kubernetes YAML files (advanced)

## Example: Our Jellyfin Setup

**Before (Generated):**
- Run complex podman command
- Generate systemd file with `podman generate systemd`
- 100+ lines of generated code
- Hard to understand
- Regenerate on every change

**After (Quadlet):**
- Write simple .container file
- 40 lines, human-readable
- Edit directly
- Just `systemctl --user daemon-reload` to apply changes

## Migration Path

1. Stop old service: `systemctl --user stop container-jellyfin.service`
2. Remove generated file: `rm ~/.config/systemd/user/container-jellyfin.service`
3. Create Quadlet: `~/.config/containers/systemd/jellyfin.container`
4. Reload: `systemctl --user daemon-reload`
5. Start new service: `systemctl --user start jellyfin.service`

Note the name change: `container-jellyfin.service` → `jellyfin.service`
