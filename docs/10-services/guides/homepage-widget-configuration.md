# Homepage Widget Configuration

## Overview

Homepage dashboard widgets are configured using Podman secrets for secure credential storage. This allows all configuration files to be safely committed to Git without exposing sensitive API keys.

## Current Widget Status

### ✅ Working Widgets

1. **Grafana** - Displays metrics and dashboard statistics
   - Credentials stored in Podman secrets
   - Uses admin API endpoint

2. **Prometheus** - Shows metric collection status
   - No authentication required
   - Direct HTTP endpoint access

3. **Loki** - Log aggregation health check
   - Uses `/ready` health endpoint
   - Simple ping status

4. **Traefik** - Reverse proxy health
   - Uses `/ping` endpoint
   - No authentication required

5. **Authelia** - SSO authentication status
   - Uses `/api/health` endpoint
   - Health check only

6. **CrowdSec** - Security threat protection
   - Uses `/health` endpoint
   - Internal network access

7. **Redis (Authelia)** - Session storage
   - Simple HTTP ping
   - Connection status only

### 🔧 Widgets Requiring API Keys

The following widgets need API keys to be generated through their respective web interfaces:

#### Jellyfin (Media Server)

**Generate API Key:**
1. Visit https://jellyfin.patriark.org
2. Login → Settings → API Keys
3. Click "+" to create new key
4. Name: "Homepage Dashboard"
5. Copy the generated key

**Configure:**
```bash
./scripts/homepage-add-api-key.sh jellyfin YOUR_API_KEY_HERE
```

#### Immich (Photo Management)

**Note:** Currently configured as simple ping (version endpoint) until API key is generated.

**Generate API Key:**
1. Visit https://photos.patriark.org
2. Login → Account Settings → API Keys
3. Click "New API Key"
4. Name: "Homepage Dashboard"
5. Copy the generated key

**Configure:**
```bash
./scripts/homepage-add-api-key.sh immich YOUR_API_KEY_HERE
```

Then update `services.yaml` to use widget instead of ping:
```yaml
- Immich:
    icon: immich.png
    href: https://photos.patriark.org
    description: Photo Management
    widget:
      type: immich
      url: http://immich-server:2283
      key: {{HOMEPAGE_VAR_IMMICH_API_KEY}}
```

## Architecture

### Podman Secrets

All sensitive credentials are stored as Podman secrets:

```bash
# List all Homepage secrets
podman secret ls | grep homepage

# Current secrets:
# - homepage_grafana_user
# - homepage_grafana_password
# - homepage_jellyfin_api_key (after generation)
# - homepage_immich_api_key (after generation)
```

### Quadlet Configuration

Secrets are mounted as environment variables in the container:

```ini
# ~/.config/containers/systemd/homepage.container
Secret=homepage_grafana_user,type=env,target=HOMEPAGE_VAR_GRAFANA_USER
Secret=homepage_grafana_password,type=env,target=HOMEPAGE_VAR_GRAFANA_PASSWORD
# Secret=homepage_jellyfin_api_key,type=env,target=HOMEPAGE_VAR_JELLYFIN_API_KEY
# Secret=homepage_immich_api_key,type=env,target=HOMEPAGE_VAR_IMMICH_API_KEY
```

### Services Configuration

Widget configurations reference environment variables using template syntax:

```yaml
# ~/containers/config/homepage/services.yaml
widget:
  type: grafana
  url: http://grafana:3000
  username: {{HOMEPAGE_VAR_GRAFANA_USER}}
  password: {{HOMEPAGE_VAR_GRAFANA_PASSWORD}}
```

## Adding New API Keys

Use the helper script:

```bash
cd ~/containers
./scripts/homepage-add-api-key.sh <service> <api-key>
```

The script will:
1. Create/update Podman secret
2. Update homepage.container quadlet (if needed)
3. Reload systemd daemon
4. Restart Homepage service
5. Verify service is running

## Widget Types

### Full Widgets (with statistics)
- **Grafana** - Dashboard count, data source count, alert count
- **Prometheus** - Target status, active alerts
- **Jellyfin** - Active streams, user count, library count (requires API key)
- **Immich** - Photo count, video count, storage usage (requires API key)

### Ping/Health Checks (status only)
- **Traefik** - Up/Down status
- **Loki** - Ready status
- **Authelia** - Health status
- **CrowdSec** - Health status
- **Redis** - Connection status
- **Immich** - Version check (temporary until API key added)

## Troubleshooting

### Widget Shows "API Error"

1. Check Homepage logs:
   ```bash
   podman logs homepage | tail -50
   ```

2. Verify secret exists:
   ```bash
   podman secret ls | grep homepage_<service>
   ```

3. Test API endpoint manually:
   ```bash
   # Example for Grafana
   curl -u patriark:PASSWORD http://grafana:3000/api/admin/stats
   ```

4. Verify quadlet has correct secret mounting:
   ```bash
   grep "Secret=" ~/.config/containers/systemd/homepage.container
   ```

### Widget Shows "Invalid Credentials"

1. Verify the secret contains correct value:
   ```bash
   podman secret inspect homepage_<service>_password
   ```

2. Recreate the secret:
   ```bash
   podman secret rm homepage_<service>_password
   echo "correct-password" | podman secret create homepage_<service>_password -
   systemctl --user restart homepage.service
   ```

### Service Not Reachable

1. Verify service is on correct network:
   ```bash
   podman inspect <service> | grep -A 5 Networks
   ```

2. Verify service is running:
   ```bash
   podman ps | grep <service>
   ```

3. Test network connectivity from Homepage:
   ```bash
   podman exec homepage wget -O- http://<service>:<port>/health
   ```

## Security Considerations

1. **Secrets in Git**: Never commit actual API keys to Git. Always use Podman secrets.

2. **Read-only API Keys**: When possible, generate read-only API keys for Homepage widgets.

3. **Key Rotation**: Periodically rotate API keys and update secrets:
   ```bash
   ./scripts/homepage-add-api-key.sh <service> <new-api-key>
   ```

4. **Minimal Permissions**: Grafana widget uses admin API, but consider creating a dedicated viewer account for production use.

## References

- [Homepage Documentation](https://gethomepage.dev/latest/widgets/)
- [Podman Secrets Documentation](https://docs.podman.io/en/latest/markdown/podman-secret.1.html)
- [Systemd Quadlet Secrets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#secret-options)
