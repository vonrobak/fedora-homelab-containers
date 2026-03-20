# NixOS Homelab Rebuild Plan

**Status:** DRAFT
**Created:** 2026-03-19
**Target:** NixOS (replacing Fedora Workstation 43)
**Scope:** Full rebuild with best-tool-for-NixOS evaluation per service category
**Prerequisite:** ADR-020/021 required before execution (supersedes ADR-001, ADR-016, ADR-019)

---

## Executive Summary

Rebuild the homelab on NixOS to achieve full declarative reproducibility. The entire system -- boot, filesystems, firewall, services, monitoring, secrets -- is defined in a single flake. `nixos-rebuild switch` brings up the complete homelab from bare metal. Services are evaluated individually: NixOS native modules replace containers where modules are mature; OCI containers remain for services without good NixOS support. The migration eliminates 8 Podman networks, 38 quadlet files, and 56 bash scripts, replacing them with approximately 2,000 lines of Nix configuration that are type-checked and atomically upgradeable.

### Key Architectural Shifts

| Aspect | Current (Fedora + Podman) | Target (NixOS) |
|--------|--------------------------|----------------|
| OS updates | `dnf update` (non-atomic) | `nixos-rebuild switch` (atomic, instant rollback) |
| Service management | Podman quadlets + systemd | NixOS modules + OCI containers where needed |
| Network isolation | 8 Podman networks | systemd sandboxing + nftables per-service rules |
| Secrets | 27 Podman secrets | sops-nix (age-encrypted, declarative, in Git) |
| Reverse proxy | Traefik (container) | Nginx (NixOS module, native ACME) |
| IDS/IPS | CrowdSec (container + Traefik plugin) | CrowdSec (container) + fail2ban (native) |
| SELinux | Enforcing with :Z labels | AppArmor (NixOS default) + systemd sandboxing |
| Firewall | firewalld | nftables (declarative NixOS rules) |
| Config management | Git repo with YAML/INI/TOML | Single Nix flake (type-checked) |
| Backup | Custom 500-line bash script | btrbk (NixOS module, declarative) |

---

## 1. System Architecture

### 1.1 Flake Structure

```
nixos-homelab/
  flake.nix                          # Entry point
  flake.lock                         # Pinned dependencies
  hosts/
    homelab/
      default.nix                    # Host-level composition
      hardware-configuration.nix     # Auto-generated hardware config
  modules/
    base/
      boot.nix                       # Bootloader, kernel, sysctl
      filesystem.nix                 # BTRFS mounts, subvolumes, NOCOW
      networking.nix                 # Network config, DNS, firewall
      users.nix                      # User accounts, SSH keys
      nix-settings.nix               # Flake settings, garbage collection
    security/
      nginx.nix                      # Reverse proxy + ACME
      authelia.nix                   # SSO (OCI container)
      crowdsec.nix                   # IP reputation (OCI container)
      fail2ban.nix                   # Native IDS
      firewall.nix                   # nftables rules
    monitoring/
      prometheus.nix                 # Native Prometheus
      grafana.nix                    # Native Grafana
      loki.nix                       # Native Loki
      alertmanager.nix               # Native Alertmanager
      promtail.nix                   # Native Promtail
      node-exporter.nix              # Native Node Exporter
      unpoller.nix                   # OCI container
    services/
      nextcloud.nix                  # Native Nextcloud + MariaDB + Redis
      immich.nix                     # OCI containers (4-container stack)
      jellyfin.nix                   # Native Jellyfin
      vaultwarden.nix                # Native Vaultwarden
      home-assistant.nix             # OCI container
      navidrome.nix                  # Native systemd service
      audiobookshelf.nix             # OCI container
      gathio.nix                     # OCI containers (app + MongoDB)
      qbittorrent.nix                # OCI container
      homepage.nix                   # OCI container
    operations/
      backup.nix                     # btrbk (BTRFS snapshots)
      ddns.nix                       # Cloudflare DDNS timer
      maintenance.nix                # Auto-upgrade, garbage collection
  secrets/
    secrets.yaml                     # sops-encrypted secrets
    .sops.yaml                       # sops config (age keys)
  dashboards/                        # Grafana JSON dashboards
  alert-rules/                       # Prometheus alert YAML files
  recording-rules/                   # Prometheus recording rules
  tests/
    default.nix                      # NixOS integration tests
```

### 1.2 Flake Entry Point

```nix
# flake.nix
{
  description = "Patriark Homelab - NixOS";

  inputs = {
    # Pin to stable release for production reliability.
    # Use overlays for specific packages that need unstable versions.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/homelab
        sops-nix.nixosModules.sops
      ];
    };
  };
}
```

---

## 2. Base System Configuration

### 2.1 Boot and Kernel

```nix
# modules/base/boot.nix
{ config, pkgs, ... }: {
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelModules = [ "amdgpu" ];
    kernelParams = [ "iommu=pt" ];
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 512;
      "net.core.somaxconn" = 65535;
    };
  };
}
```

### 2.2 Filesystem and Storage

```nix
# modules/base/filesystem.nix
{ config, pkgs, ... }: {
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "compress=zstd:3" "noatime" "space_cache=v2" ];
  };

  # Existing BTRFS data pool (separate drive, do NOT format)
  fileSystems."/mnt/btrfs-pool" = {
    device = "/dev/disk/by-id/<DISK-ID>";
    fsType = "btrfs";
    options = [ "compress=zstd:3" "noatime" "space_cache=v2" ];
  };

  # Mount individual subvolumes
  # Repeat pattern for subvol1-docs through subvol7-containers
  fileSystems."/mnt/btrfs-pool/subvol7-containers" = {
    device = "/dev/disk/by-id/<DISK-ID>";
    fsType = "btrfs";
    options = [ "subvol=subvol7-containers" "compress=zstd:3" "noatime" ];
  };

  # NOCOW for database directories
  systemd.tmpfiles.rules = [
    "d /mnt/btrfs-pool/subvol7-containers/prometheus 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/loki 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/postgresql-immich 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/nextcloud-db 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/gathio-db 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/vaultwarden 0755 patriark patriark -"
    "d /mnt/btrfs-pool/subvol7-containers/navidrome 0755 patriark patriark -"
  ];

  # One-shot to set NOCOW on database directories
  systemd.services.setup-nocow = {
    description = "Set NOCOW attribute on database directories";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      for dir in prometheus loki postgresql-immich nextcloud-db gathio-db \
                 vaultwarden navidrome; do
        ${pkgs.e2fsprogs}/bin/chattr +C "/mnt/btrfs-pool/subvol7-containers/$dir" 2>/dev/null || true
      done
    '';
  };
}
```

### 2.3 Networking

```nix
# modules/base/networking.nix
{ config, ... }: {
  networking = {
    hostName = "homelab";
    domain = "patriark.org";
    nameservers = [ "192.168.1.69" ];   # Pi-hole
    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 8096 8123 ];
      allowedUDPPorts = [ 7359 ];
    };
    nftables.enable = true;
  };
}
```

### 2.4 Users

```nix
# modules/base/users.nix
{ config, pkgs, ... }: {
  users.users.patriark = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" "video" "render" "podman" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... patriark@homelab"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    vim git htop btrfs-progs jq curl
  ];
}
```

---

## 3. Security Layer

### 3.1 Reverse Proxy: Nginx (Replaces Traefik)

**Decision:** NixOS native Nginx module
**Rationale:** NixOS has the best Nginx module of any distro. Built-in ACME with automatic cert renewal. No container overhead. Declarative virtual host config. The Traefik-specific features (forwardAuth, rate limiting, circuit breakers) all have Nginx equivalents.

```nix
# modules/security/nginx.nix
{ config, pkgs, ... }: {
  # ACME certificates via Cloudflare DNS-01
  security.acme = {
    acceptTerms = true;
    defaults.email = "blyhode@hotmail.com";
    certs."patriark.org" = {
      domain = "patriark.org";
      extraDomainNames = [ "*.patriark.org" ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets.cloudflare-acme-env.path;
    };
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    appendHttpConfig = ''
      # Rate limiting zones (replaces Traefik rate-limit middleware)
      limit_req_zone $binary_remote_addr zone=standard:10m rate=100r/m;
      limit_req_zone $binary_remote_addr zone=strict:10m rate=30r/m;
      limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/m;
      limit_req_zone $binary_remote_addr zone=public:10m rate=200r/m;
      limit_req_zone $binary_remote_addr zone=nextcloud:10m rate=600r/m;
      limit_req_zone $binary_remote_addr zone=immich:10m rate=500r/m;
      limit_req_zone $binary_remote_addr zone=vw_auth:10m rate=5r/m;

      # Security headers (replaces Traefik security-headers middleware)
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;

      server_tokens off;
      client_max_body_size 10G;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    '';

    # HTTP → HTTPS redirect
    virtualHosts."_" = {
      listen = [{ port = 80; }];
      locations."/".return = "301 https://$host$request_uri";
    };

    # ── Authelia SSO Portal ──
    virtualHosts."sso.patriark.org" = {
      useACMEHost = "patriark.org";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9091";
        extraConfig = "limit_req zone=auth burst=5 nodelay;";
      };
    };

    # ── Authelia-protected services (Grafana example) ──
    virtualHosts."grafana.patriark.org" = {
      useACMEHost = "patriark.org";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          limit_req zone=standard burst=50 nodelay;
          auth_request /authelia;
          auth_request_set $user $upstream_http_remote_user;
          auth_request_set $groups $upstream_http_remote_groups;
          proxy_set_header Remote-User $user;
          proxy_set_header Remote-Groups $groups;
          error_page 401 = @authelia_redirect;
        '';
      };
      locations."/authelia" = {
        proxyPass = "http://127.0.0.1:9091/api/verify?rd=https://sso.patriark.org";
        extraConfig = ''
          internal;
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-For $remote_addr;
        '';
      };
      locations."@authelia_redirect".return =
        "302 https://sso.patriark.org/?rd=$scheme://$http_host$request_uri";
    };

    # ── Native auth services (no Authelia) ──
    # NOTE: Nextcloud vhost is NOT defined here.
    # The NixOS services.nextcloud module auto-creates
    # virtualHosts."nextcloud.patriark.org" via its built-in Nginx integration.
    # To add rate limiting and ACME to it, use:
    #   services.nextcloud.nginx.hstsMaxAge = 31536000;
    # And override the vhost via:
    #   services.nginx.virtualHosts."nextcloud.patriark.org" = {
    #     useACMEHost = "patriark.org";
    #     forceSSL = true;
    #   };
    # The module merges these settings with its own Nginx config.
    # Do NOT duplicate the vhost — it will fail at nixos-rebuild switch.
    # CalDAV/.well-known redirects are handled by the module automatically.

    virtualHosts."jellyfin.patriark.org" = {
      useACMEHost = "patriark.org";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
        extraConfig = "limit_req zone=public burst=100 nodelay;";
      };
    };

    virtualHosts."photos.patriark.org" = {
      useACMEHost = "patriark.org";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:2283";
        proxyWebsockets = true;
        extraConfig = ''
          limit_req zone=immich burst=2000 nodelay;
          client_max_body_size 50G;
        '';
      };
    };

    # Vaultwarden with split rate limiting
    virtualHosts."vault.patriark.org" = {
      useACMEHost = "patriark.org";
      forceSSL = true;
      locations."/identity/" = {
        proxyPass = "http://127.0.0.1:8000";
        extraConfig = "limit_req zone=vw_auth burst=2 nodelay;";
      };
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
        proxyWebsockets = true;
        extraConfig = "limit_req zone=standard burst=50 nodelay;";
      };
    };

    # Pattern continues for: home-assistant, audiobookshelf, navidrome,
    # qbittorrent, homepage, events (gathio), prometheus, loki
  };
}
```

### 3.2 CrowdSec

**Decision:** OCI container
**Rationale:** CrowdSec LAPI + collections work best as the upstream container. The Nginx bouncer runs natively, querying the LAPI.

```nix
# modules/security/crowdsec.nix
{ config, pkgs, ... }: {
  virtualisation.oci-containers.containers.crowdsec = {
    image = "docker.io/crowdsecurity/crowdsec:latest";
    environment = {
      COLLECTIONS = "crowdsecurity/nginx crowdsecurity/http-cve";
      GID = "1000";
    };
    volumes = [
      "/var/lib/crowdsec/db:/var/lib/crowdsec/data"
      "/var/lib/crowdsec/config:/etc/crowdsec"
      "/var/log/nginx:/var/log/nginx:ro"
    ];
    ports = [ "127.0.0.1:8180:8080" ];   # Port 8080 avoided — Nextcloud module uses it
    extraOptions = [ "--memory=512m" ];
  };

  # CrowdSec Nginx Bouncer integration
  #
  # CRITICAL: Nginx's auth_request module only honors ONE auth_request per
  # location block. You CANNOT chain auth_request /crowdsec + auth_request
  # /authelia — the second silently overrides the first. This rules out
  # Option B (standalone bouncer via auth_request).
  #
  # REQUIRED APPROACH: Use OpenResty (Nginx + Lua) with lua-resty-crowdsec.
  # This integrates CrowdSec inline (via access_by_lua) BEFORE auth_request,
  # preserving the fail-fast middleware ordering:
  #
  #   access_by_lua_block { require("crowdsec").check() }  # Layer 1: IP rep
  #   auth_request /authelia;                               # Layer 2: SSO
  #
  # Implementation:
  # 1. Replace pkgs.nginxMainline with pkgs.openresty in nginx.nix
  # 2. Install lua-resty-crowdsec module
  # 3. Configure CrowdSec LAPI connection in lua:
  #      lua_shared_dict crowdsec_cache 50m;
  #      init_by_lua_block {
  #        local cs = require "crowdsec"
  #        cs.init("/etc/crowdsec/bouncers/crowdsec-openresty.conf")
  #      }
  # 4. Add access_by_lua_block to each protected location (before auth_request)
  #
  # This provides the same inline request-blocking as the Traefik plugin,
  # with CrowdSec's global threat intel feeds, fail-fast ordering preserved.
}
```

### 3.3 Authelia

**Decision:** OCI container (Redis runs natively)
**Rationale:** No NixOS module. The container image is well-maintained. Existing `configuration.yml` reused with minor changes (Redis host → `127.0.0.1:6380`).

**WebAuthn/FIDO2 note (ADR-006):** The Authelia `webauthn:` config includes `rp_id` which is tied to the domain (`patriark.org`). Since the domain doesn't change, registered YubiKeys remain valid. However, verify that the `rp_origin` URL in `configuration.yml` matches `https://sso.patriark.org` exactly — any mismatch will break WebAuthn authentication. Test YubiKey login immediately after migration.

```nix
# modules/security/authelia.nix
{ config, pkgs, ... }: {
  # Redis for Authelia sessions (native)
  services.redis.servers.authelia = {
    enable = true;
    port = 6380;
    bind = "127.0.0.1";
    settings = {
      maxmemory = "64mb";
      maxmemory-policy = "allkeys-lru";
    };
  };

  virtualisation.oci-containers.containers.authelia = {
    image = "docker.io/authelia/authelia:latest";
    volumes = [
      "/etc/authelia:/config:ro"
      "/var/lib/authelia:/data"
    ];
    ports = [ "127.0.0.1:9091:9091" ];
    extraOptions = [ "--memory=512m" ];
  };
}
```

### 3.4 fail2ban (Supplements CrowdSec)

**Decision:** NixOS native module
**Rationale:** Local real-time ban enforcement. Complements CrowdSec's global threat intel.

```nix
# modules/security/fail2ban.nix
{ config, ... }: {
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
    jails = {
      nginx-botsearch.settings = {
        filter = "nginx-botsearch";
        logpath = "/var/log/nginx/access.log";
        maxretry = 2;
      };
      authelia.settings = {
        filter = "authelia";
        logpath = "/var/lib/authelia/authelia.log";
        maxretry = 3;
        bantime = "4h";
      };
    };
  };
}
```

---

## 4. Service-by-Service Decisions

### 4.1 Decision Summary

| Service | Decision | Rationale | Containers Eliminated |
|---------|----------|-----------|----------------------|
| **Nginx** (was Traefik) | Native module | Best Nginx module in any distro, built-in ACME | 1 |
| **CrowdSec** | OCI container | No NixOS module, LAPI ecosystem | 0 |
| **Authelia** | OCI container | No NixOS module, complex config | 0 |
| **Redis (auth)** | Native module | `services.redis` replaces redis-authelia container | 1 |
| **Prometheus** | Native module | Flagship NixOS module, declarative scrape configs | 1 |
| **Grafana** | Native module | Declarative datasources, provisioned dashboards | 1 |
| **Loki** | Native module | Native module, solves healthcheck issue | 1 |
| **Promtail** | Native module | Reads journald directly (no journal-export workaround) | 1 |
| **Alertmanager** | Native module | Declarative config, existing YAML reusable | 1 |
| **Node Exporter** | Native module | Zero-config native module | 1 |
| **cAdvisor** | **Drop** (see note) | Most services native; use systemd collector instead | 1 |
| **UnPoller** | OCI container | No NixOS module | 0 |
| **Alert Discord Relay** | Native systemd | Custom binary → Nix derivation + DynamicUser (see derivation stub below) | 1 |
| **Nextcloud** | Native module | Flagship module: handles PHP-FPM, MariaDB, Redis, cron | 3 |
| **Immich** | OCI containers | No NixOS module, custom PostgreSQL + vectorchord | 0 |
| **Jellyfin** | Native module | Direct GPU access, no device passthrough complexity | 1 |
| **Vaultwarden** | Native module | Mature module + systemd sandboxing | 1 |
| **Navidrome** | Native module | `services.navidrome` with built-in hardening | 1 |
| **Audiobookshelf** | OCI container | No NixOS module/package | 0 |
| **Home Assistant** | OCI container | HACS/Matter ecosystem requires container | 0 |
| **Matter Server** | OCI container | Requires specific dbus/BT access | 0 |
| **Gathio** | OCI container | No NixOS module | 0 |
| **MongoDB (Gathio)** | OCI container | SSPL license, not in nixpkgs | 0 |
| **qBittorrent** | OCI container | No NixOS module | 0 |
| **Homepage** | OCI container | No NixOS module | 0 |

**Result:** 30 containers → 12 OCI containers + 12 native services. 60% container reduction.

**cAdvisor drop impact:** Existing Grafana dashboards use cAdvisor metrics (`container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, etc.) for the 12 remaining OCI containers. Two options:
1. **Keep cAdvisor as OCI** for the remaining containers (simple, dashboards work unchanged)
2. **Port dashboards** to use `systemd` collector metrics for native services + Podman's built-in metrics endpoint for OCI containers. This requires rewriting dashboard queries.

Recommendation: Keep cAdvisor initially for the 12 OCI containers, retire it only after dashboards are ported.

### 4.2 Monitoring Stack (All Native)

#### Prometheus

```nix
# modules/monitoring/prometheus.nix
{ config, ... }: {
  services.prometheus = {
    enable = true;
    retentionTime = "15d";
    listenAddress = "127.0.0.1";
    port = 9090;
    webExternalUrl = "https://prometheus.patriark.org";

    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
      external_labels = { cluster = "homelab"; environment = "production"; };
    };

    alertmanagers = [{
      static_configs = [{ targets = [ "127.0.0.1:9093" ]; }];
    }];

    # Import existing alert/recording rule files directly
    ruleFiles = [
      ./alert-rules/infrastructure-critical.yml
      ./alert-rules/service-health.yml
      ./alert-rules/security-alerts.yml
      ./alert-rules/slo-multiwindow-alerts.yml
      # ... all existing rule files
    ];

    scrapeConfigs = [
      { job_name = "prometheus";
        static_configs = [{ targets = [ "127.0.0.1:9090" ]; }]; }
      { job_name = "node_exporter";
        static_configs = [{ targets = [ "127.0.0.1:9100" ]; }]; }
      { job_name = "grafana";
        static_configs = [{ targets = [ "127.0.0.1:3000" ]; }]; }
      { job_name = "nginx";
        static_configs = [{ targets = [ "127.0.0.1:9113" ]; }]; }
      { job_name = "alertmanager";
        static_configs = [{ targets = [ "127.0.0.1:9093" ]; }]; }
      { job_name = "loki";
        static_configs = [{ targets = [ "127.0.0.1:3100" ]; }]; }
      { job_name = "crowdsec";
        static_configs = [{ targets = [ "127.0.0.1:6060" ]; }]; }  # CrowdSec metrics on 6060, LAPI on 8180
      { job_name = "unpoller";
        static_configs = [{ targets = [ "127.0.0.1:9130" ]; }]; }
      { job_name = "navidrome";
        static_configs = [{ targets = [ "127.0.0.1:4533" ]; }]; }
      { job_name = "home-assistant";
        static_configs = [{ targets = [ "127.0.0.1:8123" ]; }];
        metrics_path = "/api/prometheus";
        bearer_token_file = config.sops.secrets.ha-prometheus-token.path; }
      { job_name = "vaultwarden";
        static_configs = [{ targets = [ "127.0.0.1:8000" ]; }]; }
    ];
  };
}
```

**Key insight:** Since all services run on localhost (native or port-published containers), Prometheus scrapes `127.0.0.1:PORT`. The entire ADR-018 static IP / multi-network DNS problem disappears.

#### Grafana

```nix
# modules/monitoring/grafana.nix
{ config, pkgs, ... }: {
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        root_url = "https://grafana.patriark.org";
      };
      "auth.proxy" = {
        enabled = true;
        header_name = "Remote-User";
        header_property = "username";
        auto_sign_up = true;
      };
    };
    provision = {
      datasources.settings.datasources = [
        { name = "Prometheus"; type = "prometheus";
          url = "http://127.0.0.1:9090"; isDefault = true; }
        { name = "Loki"; type = "loki";
          url = "http://127.0.0.1:3100"; }
      ];
      dashboards.settings.providers = [{
        name = "Homelab";
        folder = "Homelab";
        options.path = "/etc/grafana/dashboards";
      }];
    };
  };
}
```

#### Loki + Promtail

```nix
# modules/monitoring/loki.nix
{ config, ... }: {
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;
      server = { http_listen_port = 3100; };
      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };
      limits_config = {
        retention_period = "168h";
        ingestion_rate_mb = 16;
        ingestion_burst_size_mb = 32;
      };
      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
      };
    };
  };

  services.promtail = {
    enable = true;
    configuration = {
      server = { http_listen_port = 9080; };
      positions.filename = "/var/lib/promtail/positions.yaml";
      clients = [{ url = "http://127.0.0.1:3100/loki/api/v1/push"; }];
      scrape_configs = [
        {
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = { job = "systemd-journal"; host = "homelab"; };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }
        {
          job_name = "nginx";
          static_configs = [{
            targets = [ "localhost" ];
            labels = {
              job = "nginx"; host = "homelab";
              __path__ = "/var/log/nginx/*.log";
            };
          }];
        }
      ];
    };
  };
}
```

**Advantage:** Promtail reads journald directly — no `journal-export` workaround needed. Podman container logs are captured via journald automatically.

#### Alertmanager + Node Exporter

```nix
services.prometheus.alertmanager = {
  enable = true;
  listenAddress = "127.0.0.1";
  port = 9093;
  configFile = ./alertmanager.yml;  # Reuse existing config
};

services.prometheus.exporters.node = {
  enable = true;
  listenAddress = "127.0.0.1";
  port = 9100;
  enabledCollectors = [ "systemd" "processes" ];
};
```

### 4.3 Applications

#### Nextcloud (Native — Replaces 3 Containers)

```nix
# modules/services/nextcloud.nix
{ config, pkgs, ... }: {
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud30;
    hostName = "nextcloud.patriark.org";
    https = true;
    maxUploadSize = "10G";

    config = {
      dbtype = "mysql";
      dbname = "nextcloud";
      dbuser = "nextcloud";
      dbpassFile = config.sops.secrets.nextcloud-db-password.path;
      adminuser = "admin";
      adminpassFile = config.sops.secrets.nextcloud-admin-password.path;
    };

    settings = {
      overwriteprotocol = "https";
      default_phone_region = "NO";
      maintenance_window_start = 3;
      trusted_domains = [ "nextcloud.patriark.org" "localhost" ];
    };

    caching.redis = true;
    phpOptions = {
      "memory_limit" = "1G";
      "upload_max_filesize" = "10G";
      "post_max_size" = "10G";
    };
    autoUpdateApps.enable = true;
  };

  services.mysql = {
    enable = true;
    package = pkgs.mariadb_11;
    dataDir = "/mnt/btrfs-pool/subvol7-containers/nextcloud-db";
  };

  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    requirePassFile = config.sops.secrets.nextcloud-redis-password.path;
  };
}
```

#### Immich (OCI Containers — No NixOS Module)

```nix
# modules/services/immich.nix
{ config, pkgs, ... }:
let immichVersion = "v2.5.6";
in {
  virtualisation.oci-containers.containers.postgresql-immich = {
    image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
    environment = { POSTGRES_DB = "immich"; POSTGRES_USER = "immich"; };
    environmentFiles = [ config.sops.secrets.immich-db-env.path ];
    volumes = [
      "/mnt/btrfs-pool/subvol7-containers/postgresql-immich:/var/lib/postgresql/data"
    ];
    ports = [ "127.0.0.1:5432:5432" ];
    extraOptions = [ "--memory=1g" "--shm-size=128m" ];
  };

  virtualisation.oci-containers.containers.redis-immich = {
    image = "docker.io/valkey/valkey:latest";
    ports = [ "127.0.0.1:6381:6379" ];
    extraOptions = [ "--memory=256m" ];
  };

  virtualisation.oci-containers.containers.immich-server = {
    image = "ghcr.io/immich-app/immich-server:${immichVersion}";
    environment = {
      DB_HOSTNAME = "host.containers.internal";
      DB_PORT = "5432"; DB_USERNAME = "immich"; DB_DATABASE_NAME = "immich";
      REDIS_HOSTNAME = "host.containers.internal"; REDIS_PORT = "6381";
      IMMICH_MACHINE_LEARNING_URL = "http://host.containers.internal:3003";
    };
    environmentFiles = [ config.sops.secrets.immich-env.path ];
    volumes = [
      "/mnt/btrfs-pool/subvol3-opptak/immich:/usr/src/app/upload"
    ];
    ports = [ "127.0.0.1:2283:2283" ];
    extraOptions = [ "--device=/dev/dri:/dev/dri" "--memory=4g" ];
    dependsOn = [ "postgresql-immich" "redis-immich" ];
  };

  virtualisation.oci-containers.containers.immich-ml = {
    image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}";
    volumes = [ "/mnt/btrfs-pool/subvol7-containers/immich-ml-cache:/cache" ];
    ports = [ "127.0.0.1:3003:3003" ];
    extraOptions = [ "--memory=4g" ];
  };
}
```

#### Jellyfin (Native — Direct GPU Access)

```nix
# modules/services/jellyfin.nix
{ config, pkgs, ... }: {
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "patriark";
    group = "patriark";
    dataDir = "/mnt/btrfs-pool/subvol7-containers/jellyfin-config";
    cacheDir = "/mnt/btrfs-pool/subvol6-tmp/jellyfin-cache";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa                    # OpenGL + Vulkan
      libva                   # VA-API runtime
      vaapiVdpau              # VDPAU backend for VA-API
      # Note: libva-utils is diagnostic only (vainfo) — install in systemPackages, not here
      # For AMD Radeon Vega: mesa provides VAAPI through radeonsi driver
      # If hardware transcoding fails, also try: amdvlk, rocmPackages.clr
      # Verify with: vainfo --display drm --device /dev/dri/renderD128
    ];
  };

  # Bind-mount media libraries (read-only)
  fileSystems."/var/lib/jellyfin/media/multimedia" = {
    device = "/mnt/btrfs-pool/subvol4-multimedia";
    options = [ "bind" "ro" ];
  };
  fileSystems."/var/lib/jellyfin/media/music" = {
    device = "/mnt/btrfs-pool/subvol5-music";
    options = [ "bind" "ro" ];
  };
}
```

#### Vaultwarden (Native — systemd Sandboxing)

```nix
# modules/services/vaultwarden.nix
{ config, ... }: {
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    config = {
      DOMAIN = "https://vault.patriark.org";
      SIGNUPS_ALLOWED = false;
      WEBSOCKET_ENABLED = true;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8000;
      DATA_FOLDER = "/mnt/btrfs-pool/subvol7-containers/vaultwarden";
    };
    environmentFile = config.sops.secrets.vaultwarden-env.path;
  };

  # UID compatibility: The NixOS vaultwarden module runs as DynamicUser by default
  # (random UID). The current container uses UID 1000. Since DATA_FOLDER points to
  # the BTRFS pool, file ownership must match. Either:
  # 1. chown the data dir to the NixOS vaultwarden user after first start, or
  # 2. Override: systemd.services.vaultwarden.serviceConfig.DynamicUser = false;
  #    users.users.vaultwarden = { uid = 1000; group = "patriark"; };
  # Option 1 is cleaner — run chown once during migration.
}
```

#### Navidrome (Native NixOS Module)

```nix
# modules/services/navidrome.nix
{ config, pkgs, ... }: {
  services.navidrome = {
    enable = true;
    settings = {
      MusicFolder = "/mnt/btrfs-pool/subvol5-music";
      DataFolder = "/mnt/btrfs-pool/subvol7-containers/navidrome";
      Address = "127.0.0.1";
      Port = 4533;
      ScanSchedule = "1h";
      "Prometheus.Enabled" = true;
    };
    # Last.fm credentials via sops
    environmentFile = config.sops.secrets.navidrome-env.path;
  };
  # The NixOS module provides systemd hardening (DynamicUser, sandboxing)
  # automatically — no need for manual serviceConfig overrides.
}
```

#### Remaining OCI Containers

```nix
# Audiobookshelf
virtualisation.oci-containers.containers.audiobookshelf = {
  image = "ghcr.io/advplyr/audiobookshelf:latest";
  volumes = [
    "/mnt/btrfs-pool/subvol7-containers/audiobookshelf:/config"
    "/mnt/btrfs-pool/subvol4-multimedia/audiobooks:/audiobooks:ro"
    "/mnt/btrfs-pool/subvol4-multimedia/podcasts:/podcasts:ro"
  ];
  ports = [ "127.0.0.1:13378:80" ];
  extraOptions = [ "--memory=512m" ];
};

# Home Assistant (host network for mDNS/SSDP)
# SECURITY TRADE-OFF: --network=host gives HA full host network access.
# This is a regression from the current setup (isolated home_automation network).
# Required because mDNS/SSDP device discovery needs broadcast/multicast on the
# LAN interface, which container networks can't provide.
# Mitigations:
#   - Vet HACS plugins carefully — they run with host network access
#   - HA's built-in auth + Authelia on the Nginx route limits remote access
#   - macvlan network is a realistic near-term improvement (gives HA its own
#     LAN IP without full host access). Since UDM Pro is already in use,
#     create a DHCP reservation for the macvlan interface.
#     See Appendix B #6 for follow-up task.
virtualisation.oci-containers.containers.home-assistant = {
  image = "ghcr.io/home-assistant/home-assistant:stable";
  environment.TZ = "Europe/Oslo";
  volumes = [ "/var/lib/home-assistant:/config" ];
  extraOptions = [ "--memory=2g" "--network=host" ];
};

# Matter Server
virtualisation.oci-containers.containers.matter-server = {
  image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
  volumes = [ "/var/lib/matter-server:/data" ];
  extraOptions = [ "--memory=512m" "--network=host" ];
};

# Gathio + MongoDB
virtualisation.oci-containers.containers.gathio-db = {
  image = "docker.io/mongo:7";
  volumes = [ "/mnt/btrfs-pool/subvol7-containers/gathio-db:/data/db" ];
  ports = [ "127.0.0.1:27017:27017" ];
  extraOptions = [ "--memory=512m" ];
};

virtualisation.oci-containers.containers.gathio = {
  image = "ghcr.io/lowercasename/gathio:latest";
  environment = { DOMAIN = "events.patriark.org"; PORT = "3000"; TZ = "Europe/Oslo"; };
  ports = [ "127.0.0.1:3001:3000" ];
  dependsOn = [ "gathio-db" ];
  extraOptions = [ "--memory=768m" ];
};

# qBittorrent
virtualisation.oci-containers.containers.qbittorrent = {
  image = "lscr.io/linuxserver/qbittorrent:latest";
  environment = { PUID = "1000"; PGID = "1000"; TZ = "Europe/Oslo"; };
  volumes = [
    "/mnt/btrfs-pool/subvol7-containers/qbittorrent:/config"
    "/mnt/btrfs-pool/subvol6-tmp/Downloads:/downloads"
  ];
  ports = [ "127.0.0.1:8085:8085" ];
  extraOptions = [ "--memory=1g" ];
};

# Homepage
virtualisation.oci-containers.containers.homepage = {
  image = "ghcr.io/gethomepage/homepage:latest";
  volumes = [ "/etc/homepage:/app/config:ro" ];
  ports = [ "127.0.0.1:3002:3000" ];
  extraOptions = [ "--memory=256m" ];
};

# UnPoller
virtualisation.oci-containers.containers.unpoller = {
  image = "ghcr.io/unpoller/unpoller:latest";
  environmentFiles = [ config.sops.secrets.unpoller-env.path ];
  ports = [ "127.0.0.1:9130:9130" ];
  extraOptions = [ "--memory=256m" ];
};
```

---

## 5. Secrets Management: sops-nix

**Decision:** sops-nix with age encryption
**Rationale:** Secrets encrypted in Git (unlike Podman secrets stored outside repo). Age keys simpler than GPG. Each secret becomes `/run/secrets/<name>` with correct ownership.

```nix
sops = {
  defaultSopsFile = ../../secrets/secrets.yaml;
  age.keyFile = "/etc/age/keys.txt";
  secrets = {
    cloudflare-acme-env = {};
    authelia_jwt_secret = {};
    authelia_session_secret = {};
    authelia_storage_key = {};
    nextcloud-db-password = { owner = "nextcloud"; };
    nextcloud-admin-password = { owner = "nextcloud"; };
    nextcloud-redis-password = {};
    immich-env = {};
    immich-db-env = {};
    grafana-admin-password = { owner = "grafana"; };
    vaultwarden-env = {};
    ha-prometheus-token = { owner = "prometheus"; };
    discord-webhook-env = {};
    unpoller-env = {};
    navidrome-env = {};
    gathio-mongodb-password = {};
    crowdsec-api-key = {};
  };
};
```

### Migration from Podman Secrets

```bash
# Export from current system — use tmpfs to avoid plaintext on persistent storage
TMPDIR=$(mktemp -d --tmpdir=/dev/shm sops-migration.XXXXXX)
chmod 700 "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

podman secret ls --format '{{.Name}}' | while read name; do
  value=$(podman secret inspect "$name" --showsecret | jq -r '.SecretData' | base64 -d)
  echo "$name: $value"
done > "$TMPDIR/secrets-plain.yaml"

# On NixOS: generate age key, encrypt
age-keygen -o /etc/age/keys.txt
sops --encrypt --age "$(age-keygen -y /etc/age/keys.txt)" "$TMPDIR/secrets-plain.yaml" > secrets/secrets.yaml
```

---

## 6. Backup and Recovery

### 6.1 btrbk (Replaces Custom BTRFS Script)

**Decision:** NixOS native btrbk module
**Rationale:** Replaces the custom 500-line `btrfs-snapshot-backup.sh` with declarative snapshot policies.

```nix
# modules/operations/backup.nix
{ config, pkgs, ... }: {
  services.btrbk = {
    instances.homelab = {
      onCalendar = "daily";
      settings = {
        timestamp_format = "long-iso";
        snapshot_preserve_min = "2d";
        snapshot_preserve = "7d 4w 3m";
        target_preserve_min = "7d";
        target_preserve = "4w 6m 1y";

        volume."/mnt/btrfs-pool" = {
          snapshot_dir = ".snapshots";
          target = "/run/media/patriark/WD-18TB/backups";

          subvolume."subvol1-docs" = {};
          subvolume."subvol2-pics" = {};
          subvolume."subvol3-opptak" = {};
          subvolume."subvol4-multimedia" = {};
          subvolume."subvol5-music" = {};
          subvolume."subvol6-tmp" = {
            snapshot_preserve = "3d";
            target_preserve = "7d";
          };
          subvolume."subvol7-containers" = {};
        };
      };
    };
  };

  # Pre-backup database dumps
  # MariaDB uses socket auth (NixOS default) — no password needed for local root
  systemd.services."btrbk-homelab".preStart = ''
    ${pkgs.mariadb}/bin/mariadb-dump --socket=/run/mysqld/mysqld.sock \
      -u root --all-databases \
      > /mnt/btrfs-pool/subvol7-containers/nextcloud-db/dump-latest.sql

    ${pkgs.podman}/bin/podman exec postgresql-immich pg_dumpall -U immich \
      > /mnt/btrfs-pool/subvol7-containers/postgresql-immich/dump-latest.sql

    ${pkgs.podman}/bin/podman exec gathio-db mongodump \
      --archive=/data/db/dump-latest.archive 2>/dev/null || true
  '';
}
```

### 6.2 NixOS Rollback (Free)

Every `nixos-rebuild switch` creates a bootloader generation. Recovery is multi-layered:

1. **NixOS generation rollback** — instant, select previous generation at boot
2. **BTRFS snapshots** — data rollback via btrbk
3. **External drive backups** — disaster recovery via btrbk send/receive

---

## 7. Operational Tooling

### 7.1 Cloudflare DDNS

```nix
systemd.services.cloudflare-ddns = {
  description = "Cloudflare DDNS Update";
  serviceConfig = {
    Type = "oneshot";
    DynamicUser = true;
    EnvironmentFile = config.sops.secrets.cloudflare-acme-env.path;
  };
  script = ''
    IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
    ${pkgs.curl}/bin/curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
      -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"patriark.org\",\"content\":\"$IP\",\"proxied\":false}"
  '';
};
systemd.timers.cloudflare-ddns = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "*:0/5"; Persistent = true; };
};
```

### 7.2 Auto-Upgrade

```nix
system.autoUpgrade = {
  enable = true;
  flake = "github:patriark/nixos-homelab";
  dates = "Sat 04:00";
  allowReboot = false;   # Manual reboot after review
};

nix = {
  gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-flakes" "nix-command" ];
  };
};
```

### 7.3 Script Migration

| Category | Current Scripts | NixOS Approach |
|----------|----------------|----------------|
| Health/monitoring | homelab-intel.sh, autonomous-check.sh | Port as systemd timers + smaller scripts |
| Doc generation | auto-doc-orchestrator.sh, generate-*.sh | Port, adapt for native service discovery |
| Security audit | security-audit.sh | Rewrite (SELinux→AppArmor, quadlets→modules) |
| Backup | btrfs-snapshot-backup.sh (500 lines) | **Replaced by btrbk module** |
| Updates | update-before-reboot.sh | **Replaced by system.autoUpgrade** |
| DDNS | cloudflare-ddns.sh | **Replaced by systemd timer (above)** |
| Service mgmt | graceful-shutdown.sh | `systemctl` direct (simpler) |
| Diagnostics | homelab-diagnose.sh, query-homelab.sh | Port with adaptations |

**Expected reduction:** 56 scripts → ~15-20

### 7.4 Podman for Remaining Containers

```nix
virtualisation = {
  podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  oci-containers.backend = "podman";
};
```

All OCI containers bind to `127.0.0.1:PORT`. Nginx reverse-proxies to them. No Podman networks. No DNS resolution issues. No static IPs needed.

---

## 8. NixOS Testing

### 8.1 VM Testing (Before Production)

```bash
# Build and boot in QEMU (NixOS built-in)
nixos-rebuild build-vm --flake .#homelab
./result/bin/run-homelab-vm
```

### 8.2 Integration Tests

```nix
# tests/default.nix
{ pkgs, ... }: pkgs.nixosTest {
  name = "homelab-integration";
  nodes.homelab = { config, ... }: {
    imports = [ ../hosts/homelab ];
    security.acme.acceptTerms = true;
    # Disable ACME for test environment
  };
  testScript = ''
    homelab.wait_for_unit("nginx.service")
    homelab.wait_for_unit("prometheus.service")
    homelab.wait_for_unit("grafana.service")
    homelab.wait_for_unit("loki.service")
    homelab.succeed("curl -f http://localhost:9090/-/healthy")
    homelab.succeed("curl -f http://localhost:3000/api/health")
    homelab.succeed("curl -f http://localhost:3100/ready")
  '';
}
```

---

## 9. Data Migration Plan

### 9.1 Pre-Migration (Current Fedora System)

1. Full BTRFS snapshots of all 7 subvolumes
2. Database dumps (MariaDB, PostgreSQL, MongoDB)
3. Export Podman secrets → sops-nix conversion
4. Git archive of containers repo
5. Document GPU device paths and disk identifiers

### 9.2 NixOS Installation

1. Install NixOS on system drive (BTRFS root, separate from data pool)
2. Mount existing BTRFS data pool (no formatting)
3. Clone NixOS flake repo
4. Create age key, encrypt secrets with sops
5. `nixos-rebuild switch`

### 9.3 Migration Order

| Phase | Services | Hours |
|-------|----------|-------|
| 1: Core | Nginx + ACME, CrowdSec, Authelia + Redis | 0-2 |
| 2: Critical | Nextcloud, Vaultwarden | 2-4 |
| 3: Media | Jellyfin (verify GPU), Immich, Navidrome, Audiobookshelf | 4-6 |
| 4: Monitoring | Prometheus, Grafana, Loki, Promtail, Alertmanager, UnPoller | 6-8 |
| 5: Remaining | HA, Gathio, qBittorrent, Homepage, fail2ban | 8-10 |

### 9.4 Data Compatibility Risks

| Component | Risk | Mitigation |
|-----------|------|------------|
| MariaDB data dir | NixOS MariaDB version mismatch | Use dump/restore, not raw data dir |
| Prometheus TSDB | Version mismatch possible | Accept loss of 15d history |
| Nextcloud data/ | Must preserve exactly | Bind-mount existing subvol path |
| Immich PostgreSQL | Custom vectorchord extension | Same container image = no risk |
| Jellyfin config | Version-specific paths | Test before cutover |

---

## 10. Validation Checklist

```bash
# All services responding
for svc in sso vault nextcloud photos jellyfin grafana ha events musikk audiobookshelf torrent home; do
  curl -sf -o /dev/null -w "%{http_code} $svc\n" "https://$svc.patriark.org"
done

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'

# Database integrity
mariadb -u root -e "SELECT COUNT(*) FROM nextcloud.oc_users;"
podman exec postgresql-immich psql -U immich -c "SELECT count(*) FROM assets;"

# GPU transcoding
vainfo  # Should show AMD Radeon Vega profiles

# Certificate validity
echo | openssl s_client -servername patriark.org -connect localhost:443 2>/dev/null | openssl x509 -noout -dates

# System health
nixos-rebuild dry-activate --flake .#homelab  # Should show no changes
systemctl --failed  # Should be empty
```

---

## Appendix A: Service Port Map

All services bind to `127.0.0.1` (Nginx reverse-proxies):

| Service | Port | Type |
|---------|------|------|
| Nginx | 80, 443 | Native |
| Authelia | 9091 | OCI |
| CrowdSec LAPI | 8180 | OCI |
| Prometheus | 9090 | Native |
| Grafana | 3000 | Native |
| Loki | 3100 | Native |
| Alertmanager | 9093 | Native |
| Node Exporter | 9100 | Native |
| Promtail | 9080 | Native |
| Nextcloud | unix socket (module-managed) | Native (Nginx vhost auto-created by module) |
| Jellyfin | 8096 | Native |
| Vaultwarden | 8000 | Native |
| Navidrome | 4533 | Native |
| Immich Server | 2283 | OCI |
| Immich ML | 3003 | OCI |
| PostgreSQL (Immich) | 5432 | OCI |
| Valkey (Immich) | 6381 | OCI |
| Home Assistant | 8123 | OCI (host net) |
| Audiobookshelf | 13378 | OCI |
| Gathio | 3001 | OCI |
| MongoDB | 27017 | OCI |
| qBittorrent | 8085 | OCI |
| Homepage | 3002 | OCI |
| UnPoller | 9130 | OCI |
| Alert Discord Relay | 9095 | Native |

### Alert Discord Relay — Nix Derivation Stub

The relay is a Python/Flask app (`relay.py` + `requirements.txt`: Flask, requests, gunicorn). Derivation skeleton:

```nix
# overlays/alert-discord-relay.nix
{ lib, python3Packages, ... }:
python3Packages.buildPythonApplication {
  pname = "alert-discord-relay";
  version = "1.0.0";
  src = ../services/alert-discord-relay;  # Copy source from current repo

  propagatedBuildInputs = with python3Packages; [
    flask
    requests
    gunicorn
  ];

  # No tests in this project
  doCheck = false;

  meta = { description = "Alertmanager to Discord webhook relay"; };
}
```

Systemd service:
```nix
systemd.services.alert-discord-relay = {
  description = "Alert Discord Relay";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.alert-discord-relay}/bin/gunicorn -b 127.0.0.1:9095 relay:app";
    DynamicUser = true;
    EnvironmentFile = config.sops.secrets.discord-webhook-env.path;
    MemoryMax = "128M";
    PrivateTmp = true;
    ProtectSystem = "strict";
  };
};
```

### qBittorrent Incoming Peer Port

qBittorrent requires an incoming peer port for torrent traffic. Add to firewall and container config:
```nix
# In networking.nix:
networking.firewall.allowedTCPPorts = [ 80 443 8096 8123 <peer-port> ];

# In qbittorrent container:
ports = [ "127.0.0.1:8085:8085" "<peer-port>:<peer-port>" ];
```
Check the current qBittorrent configuration for the user-configured peer port before migration.

## Appendix B: NixOS Module Verification Flags

Before execution, verify these assumptions in a NixOS VM:

1. **`services.nextcloud` + `caching.redis`** — Does the module auto-configure the Redis connection from `services.redis.servers.nextcloud`, or does it need explicit `redis.host`/`redis.port` in `settings`? Check the module source or test in VM.

2. **`services.loki` configuration schema** — The `common:` key used in the Loki config may not match the NixOS module's expected schema exactly. The module passes `configuration` as raw YAML to Loki, so it should work, but verify the Loki version in nixpkgs-unstable matches the config format.

3. **`virtualisation.oci-containers` with `dependsOn`** — Supported in recent nixpkgs for the Podman backend, but verify that `dependsOn = [ "postgresql-immich" ]` generates correct systemd `After=`/`Requires=` directives.

4. **`services.nextcloud` Nginx integration** — RESOLVED: The module auto-creates its own Nginx vhost. Do NOT define a manual `virtualHosts."nextcloud.patriark.org"` in `nginx.nix` — merge ACME and rate-limit settings into the module's auto-generated vhost instead. See section 3.1 comments.

5. **ADR conflicts** — This plan conflicts with ADR-001 (rootless containers → system services), ADR-016 (Traefik routing → Nginx), and ADR-019 (SELinux → AppArmor). ADR-021 must explicitly supersede these. See ADR stub below.

6. **Home Assistant macvlan follow-up** — After initial deployment with `--network=host`, migrate HA to a macvlan network with a static DHCP reservation on the UDM Pro. This restores network isolation while preserving mDNS/SSDP. Test: `podman network create -d macvlan --subnet=192.168.1.0/24 --gateway=192.168.1.1 -o parent=enp4s0 ha-macvlan`.

7. **Vaultwarden UID compatibility** — The NixOS module uses DynamicUser (random UID). Current container data is owned by UID 1000. Run `chown -R vaultwarden: /mnt/btrfs-pool/subvol7-containers/vaultwarden` after first module activation to fix ownership.

8. **Authelia WebAuthn/FIDO2 verification** — Test YubiKey login immediately after migration. The `rp_id` and `rp_origin` in `configuration.yml` must match `patriark.org` / `https://sso.patriark.org` exactly.

## Appendix C: Key Advantages Over Current System

1. **Full reproducibility** — `nixos-rebuild switch` from bare metal
2. **Atomic upgrades** — instant rollback via boot generations
3. **60% fewer containers** — 30 → 12 OCI containers
4. **No network complexity** — ADR-018 static IP problem eliminated entirely
5. **Secrets in Git** — encrypted with age, declarative with sops-nix
6. **Type-checked config** — Nix catches errors before deployment
7. **VM testing** — test full system in QEMU before touching production
8. **Integration tests** — automated NixOS test framework
9. **Declarative backup** — btrbk replaces 500-line custom script
10. **No SELinux labels** — AppArmor + systemd sandboxing (DynamicUser, ProtectSystem, etc.)

---

## ADR-020 Stub: NixOS Migration Decision

**Title:** ADR-020: NixOS Migration — Declarative Infrastructure

**Status:** Proposed

**Context:** The Fedora Workstation 43 + Podman homelab has reached 30 containers, 38 quadlet files, 56 scripts, and 27 secrets. Configuration drift detection requires custom tooling. Rollback is manual. The system works but the complexity ceiling creates maintenance burden.

**Decision:** Migrate to NixOS. Use native modules for services with mature NixOS support (18 of 30 containers). Keep OCI containers for 12 services without NixOS modules. Replace Traefik with Nginx (OpenResty). Replace Podman secrets with sops-nix. Replace custom backup with btrbk.

**Supersedes:** ADR-002 (Systemd Quadlets — replaced by NixOS modules + OCI containers)

## ADR-021 Stub: NixOS Security Model

**Title:** ADR-021: NixOS Security Model — AppArmor + systemd Sandboxing

**Status:** Proposed

**Context:** The current system uses SELinux enforcing with `:Z`/`:z` labels on all bind mounts (ADR-001), rootless Podman containers (UID 1000), and Traefik-centralized routing (ADR-016).

**Decision:** Replace SELinux with AppArmor (NixOS default) + systemd sandboxing directives (DynamicUser, ProtectSystem, PrivateTmp, NoNewPrivileges). Replace Traefik with OpenResty/Nginx for routing. Native services run as system services (not rootless containers) with per-service sandboxing profiles.

**Supersedes:** ADR-001 (Rootless Containers — native services run as system users with sandboxing), ADR-016 (Traefik Configuration — replaced by NixOS Nginx module), ADR-019 (Filesystem Permission Model — replaced by NixOS tmpfiles + DynamicUser)

**Trade-offs:**
- Lost: SELinux MAC, rootless container isolation for native services
- Gained: Type-checked config, atomic rollback, DynamicUser auto-isolation, declarative firewall
