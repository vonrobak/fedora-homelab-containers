➜  ~ ls -la /home/patriark/.config/containers/systemd
total 28
drwxr-xr-x. 1 patriark patriark  284 okt.  24 10:16 .
drwxr-xr-x. 1 patriark patriark   14 okt.  20 11:02 ..
-rw-r--r--. 1 patriark patriark  117 okt.  20 20:48 auth_services.network
drwxr-xr-x. 1 patriark patriark  272 okt.  24 10:16 backups
-rw-r--r--. 1 patriark patriark  577 okt.  23 18:32 crowdsec.container
-rw-r--r--. 1 patriark patriark 1354 okt.  23 01:57 jellyfin.container
-rw-r--r--. 1 patriark patriark  108 okt.  20 15:00 media_services.network
-rw-r--r--. 1 patriark patriark  107 okt.  20 15:00 reverse_proxy.network
-rw-r--r--. 1 patriark patriark  824 okt.  23 01:54 tinyauth.container
-rw-r--r--. 1 patriark patriark  757 okt.  23 17:19 traefik.container
➜  ~ cat /home/patriark/.config/containers/systemd/auth_services.network 
[Unit]
Description=Authentication Services Network

[Network]
Subnet=10.89.3.0/24
Gateway=10.89.3.1
DNS=192.168.1.69
➜  ~ cat /home/patriark/.config/containers/systemd/media_services.network 
[Unit]
Description=Media Services Network

[Network]
Subnet=10.89.1.0/24
Gateway=10.89.1.1
DNS=192.168.1.69
➜  ~ cat /home/patriark/.config/containers/systemd/reverse_proxy.network 
[Unit]
Description=Reverse Proxy Network

[Network]
Subnet=10.89.2.0/24
Gateway=10.89.2.1
DNS=192.168.1.69
➜  ~ cat /home/patriark/.config/containers/systemd/crowdsec.container
[Unit]
Description=CrowdSec Security Engine
After=network-online.target
Wants=network-online.target

[Container]
Image=ghcr.io/crowdsecurity/crowdsec:latest
ContainerName=crowdsec
AutoUpdate=registry
Network=systemd-reverse_proxy

# Volumes
Volume=%h/containers/data/crowdsec/db:/var/lib/crowdsec/data:Z
Volume=%h/containers/data/crowdsec/config:/etc/crowdsec:Z

# Environment - Install Traefik collection
Environment=COLLECTIONS=crowdsecurity/traefik crowdsecurity/http-cve
Environment=GID=1000

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
➜  ~ cat /home/patriark/.config/containers/systemd/jellyfin.container 
[Unit]
Description=Jellyfin Media Server
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/jellyfin/jellyfin:latest
ContainerName=jellyfin
HostName=jellyfin
Network=media_services.network
Network=reverse_proxy.network
PublishPort=8096:8096
PublishPort=7359:7359/udp
AddDevice=/dev/dri/renderD128
Environment=TZ=Europe/Oslo
Environment=JELLYFIN_PublishedServerUrl=https://jellyfin.patriark.lokal # MAY NEED REVISION AS .LOKAL DOMAINS DO NOT GET TLS CERTIFICATES
Volume=%h/containers/config/jellyfin:/config:Z
Volume=/mnt/btrfs-pool/subvol6-tmp/jellyfin-cache:/cache:Z
Volume=/mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes:/config/transcodes:Z
Volume=/mnt/btrfs-pool/subvol4-multimedia:/media/multimedia:ro,Z
Volume=/mnt/btrfs-pool/subvol5-music:/media/music:ro,Z
DNS=192.168.1.69
DNSSearch=lokal

# Traefik labels (UPDATED DOMAIN - no authelia yet) ## NEEDS REVISION - SEEMS LIKE RELIC FROM PAST CONFIGS - .lokal domains have been substituted with .org after Cloudflare DNS and DDNS was properly configured
Label=traefik.enable=true
Label=traefik.http.routers.jellyfin.rule=Host(`jellyfin.patriark.lokal`)
Label=traefik.http.routers.jellyfin.entrypoints=websecure
Label=traefik.http.routers.jellyfin.tls=true
Label=traefik.http.services.jellyfin.loadbalancer.server.port=8096
Label=traefik.docker.network=systemd-reverse_proxy

HealthCmd=curl -f http://localhost:8096/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
AutoUpdate=registry

[Service]
Restart=on-failure
TimeoutStartSec=900

[Install]
WantedBy=default.target
➜  ~ cat /home/patriark/.config/containers/systemd/tinyauth.container 
[Unit]
Description=Tinyauth Authentication
After=traefik.service

[Container]
Image=ghcr.io/steveiliop56/tinyauth:v4
ContainerName=tinyauth
Network=systemd-reverse_proxy
Environment=APP_URL=https://auth.patriark.org
Environment=SECRET=8en5zX/GdM4Dtzz8kY+e1YE+iNUbG6bk8j+czuCQo+8=
Environment=USERS=patriark:$$2a$$10$$w6lh8foduKkyedg9fNnXf.JmEqm6FR0zutxptOs57lyPVamuE6uWO
Label=traefik.enable=true
Label=traefik.http.routers.tinyauth.rule=Host(`auth.patriark.lokal`) || Host(`auth.patriark.org`)
Label=traefik.http.routers.tinyauth.entrypoints=websecure
Label=traefik.http.routers.tinyauth.tls=true
Label=traefik.http.services.tinyauth.loadbalancer.server.port=3000
Label=traefik.http.middlewares.tinyauth.forwardauth.address=http://tinyauth:3000/api/auth/traefik

[Service]
Restart=always

[Install]
WantedBy=default.target
➜  ~ cat /home/patriark/.config/containers/systemd/traefik.container 
[Unit]
Description=Traefik Reverse Proxy
After=network-online.target reverse_proxy-network.service
Wants=network-online.target
Requires=reverse_proxy-network.service

[Container]
Image=docker.io/library/traefik:v3.2
ContainerName=traefik
HostName=traefik
AutoUpdate=registry
Network=systemd-reverse_proxy
PublishPort=80:80
PublishPort=443:443
PublishPort=8080:8080
Volume=%h/containers/config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro,Z
Volume=%h/containers/config/traefik/dynamic:/etc/traefik/dynamic:ro,Z
Volume=%h/containers/config/traefik/letsencrypt:/letsencrypt:Z
Volume=/run/user/%U/podman/podman.sock:/var/run/podman/podman.sock:ro
SecurityLabelDisable=true

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
➜  ~ ls -la /home/patriark/containers/config/traefik
total 4
drwxr-xr-x. 1 patriark patriark  68 okt.  24 10:28 .
drwxr-xr-x. 1 patriark patriark  84 okt.  23 15:49 ..
drwxr-xr-x. 1 patriark patriark  36 okt.  20 13:47 certs
drwxr-xr-x. 1 patriark patriark 242 okt.  23 17:34 dynamic
drw-------. 1 patriark patriark  18 okt.  23 17:23 letsencrypt
-rw-r--r--. 1 patriark patriark 919 okt.  23 18:08 traefik.yml
➜  ~ cat /home/patriark/containers/config/traefik/traefik.yml 
# Traefik Static Configuration v3.2
# Domain: patriark.org

api:
  dashboard: true
  insecure: false

ping:
  entryPoint: "traefik"

log:
  level: INFO

entryPoints:
  traefik:
    address: ":8080"

  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/podman/podman.sock"
    exposedByDefault: false
    network: systemd-reverse_proxy

  file:
    directory: /etc/traefik/dynamic
    watch: true

global:
  sendAnonymousUsage: false

experimental:
  plugins:
    crowdsec-bouncer-traefik-plugin:
      moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version: "v1.4.5"

certificatesResolvers:
  letsencrypt:
    acme:
      email: blyhode@hotmail.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
➜  ~ cat /home/patriark/containers/config/traefik/dynamic/middleware.yml 
http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        customFrameOptionsValue: "SAMEORIGIN"
    
    tinyauth:
      forwardAuth:
        address: "http://tinyauth:3000/api/auth/traefik"
        authResponseHeaders:
          - "Remote-User"
          - "Remote-Email"
          - "Remote-Name"
    
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
    
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          enabled: true
          crowdsecMode: live
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiKey: PMzGXoBZt1GkM0CV3nLC4c2VC01sR/PyV9d2VU5H7Gs
➜  ~ cat /home/patriark/containers/config/traefik/dynamic/rate-limit.yml 
# Rate Limiting Configuration

http:
  middlewares:
    # Global rate limit - prevents brute force
    global-rate-limit:
      rateLimit:
        average: 50
        burst: 100
        period: "1m"
    
    # Strict rate limit for auth endpoints
    auth-rate-limit:
      rateLimit:
        average: 10
        burst: 20
        period: "1m"
    
    # API rate limit
    api-rate-limit:
      rateLimit:
        average: 30
        burst: 50
        period: "1m"
➜  ~ cat /home/patriark/containers/config/traefik/dynamic/routers.yml
http:
  routers:
    # Root domain redirect
    root-redirect:
      rule: "Host(`patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
      tls:
        certResolver: letsencrypt

    # Tinyauth portal
    tinyauth-portal:
      rule: "Host(`auth.patriark.org`)"
      service: "tinyauth"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
      tls:
        certResolver: letsencrypt

    # Traefik Dashboard
    traefik-dashboard:
      rule: "Host(`traefik.patriark.org`)"
      service: "api@internal"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - tinyauth@file
      tls:
        certResolver: letsencrypt

    # Jellyfin
    jellyfin-secure:
      rule: "Host(`jellyfin.patriark.org`)"
      service: "jellyfin"
      entryPoints:
        - websecure
      middlewares:
        - crowdsec-bouncer
        - rate-limit
        - tinyauth@file
      tls:
        certResolver: letsencrypt

  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"

    tinyauth:
      loadBalancer:
        servers:
          - url: "http://tinyauth:3000"
➜  ~ cat /home/patriark/containers/config/traefik/dynamic/tls.yml
# TLS Configuration (Dynamic)
# Certificates managed by Let's Encrypt

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
➜  ~ sudo ls -la /home/patriark/containers/config/traefik/letsencrypt
total 44
drw-------. 1 patriark patriark    18 okt.  23 17:23 .
drwxr-xr-x. 1 patriark patriark    68 okt.  24 10:28 ..
-rw-------. 1 patriark patriark 42434 okt.  23 17:24 acme.json
➜  ~ ls -la ~/containers/secrets 
total 24
drwx------. 1 patriark patriark 178 okt.  23 00:03 .
drwxr-xr-x. 1 patriark patriark  96 okt.  24 10:18 ..
-rw-------. 1 patriark patriark 870 okt.  20 18:45 authelia.env
-rw-------. 1 patriark patriark 829 okt.  20 18:13 authelia.env.bak
-rw-------. 1 patriark patriark  41 okt.  22 23:58 cloudflare_token
-rw-------. 1 patriark patriark  33 okt.  23 00:03 cloudflare_zone_id
-rw-------. 1 patriark patriark  65 okt.  22 19:28 redis_password
-rw-------. 1 patriark patriark  21 okt.  22 18:50 smtp_password
