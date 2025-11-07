# Homelab Summary (auto-generated)
Generated: 2025-10-21T22:19:23+02:00

## Host
- OS: Fedora Linux 42 (Workstation Edition)
- Kernel: 6.16.12-200.fc42.x86_64
- Uptime: up 2 days, 32 minutes
- SELinux: Enforcing
- unprivileged_port_start: 80

## Firewall & Listeners
- firewalld: running
- open ports: 80/tcp 443/tcp 8096/tcp 7359/udp

### Listening (80/443/8096/9091/8080)
tcp   LISTEN 0      4096                                   *:8096             *:*    users:(("rootlessport",pid=1893085,fd=10))
tcp   LISTEN 0      4096                                   *:8080             *:*    users:(("rootlessport",pid=1892705,fd=12))
tcp   LISTEN 0      4096                                   *:80               *:*    users:(("rootlessport",pid=1892705,fd=10))
tcp   LISTEN 0      4096                                   *:443              *:*    users:(("rootlessport",pid=1892705,fd=11))

## Podman
```
Client:        Podman Engine
Version:       5.6.2
API Version:   5.6.2
Go Version:    go1.24.7
Git Commit:    9dd5e1ed33830612bc200d7a13db00af6ab865a4
Built:         Tue Sep 30 02:00:00 2025
Build Origin:  Fedora Project
OS/Arch:       linux/amd64
```

### Containers (running)
Name  |  Image  |  Ports  |  Status
----|----|----|----
NAMES           IMAGE                               PORTS                                                             STATUS
traefik         docker.io/library/traefik:v3.2      0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:8080->8080/tcp  Up 26 hours
jellyfin        docker.io/jellyfin/jellyfin:latest  0.0.0.0:8096->8096/tcp, 0.0.0.0:7359->7359/udp                    Up 26 hours (healthy)
authelia-redis  docker.io/library/redis:7-alpine    6379/tcp                                                          Up 25 hours
authelia        docker.io/authelia/authelia:latest  9091/tcp                                                          Up 23 hours (healthy)

### Containers (all)
Name  |  Image  |  Ports  |  Status
----|----|----|----


## Networks
NETWORK ID    NAME                    DRIVER
2f259bab93aa  podman                  bridge
72ac489aa932  systemd-auth_services   bridge
f891dad27177  systemd-media_services  bridge
d795412b2b27  systemd-reverse_proxy   bridge
e7b65d1416a9  web_services            bridge

### Inspects

### podman
[
     {
          "name": "podman",
          "id": "2f259bab93aaaaa2542ba43ef33eb990d0999ee1b9924b557b7be53c0b7a1bb9",
          "driver": "bridge",
          "network_interface": "podman0",
          "created": "2025-10-21T22:19:22.708000098+02:00",
          "subnets": [
               {
                    "subnet": "10.88.0.0/16",
                    "gateway": "10.88.0.1"
               }
          ],
          "ipv6_enabled": false,
          "internal": false,
          "dns_enabled": false,
          "ipam_options": {
               "driver": "host-local"
          },
          "containers": {}
     }
]

### systemd-auth_services
[
     {
          "name": "systemd-auth_services",
          "id": "72ac489aa932cc94e1351ae728f243b995f5a2b14424d69916d192510aac4e7b",
          "driver": "bridge",
          "network_interface": "podman4",
          "created": "2025-10-20T17:01:10.079987686+02:00",
          "subnets": [
               {
                    "subnet": "10.89.3.0/24",
                    "gateway": "10.89.3.1"
               }
          ],
          "ipv6_enabled": false,
          "internal": false,
          "dns_enabled": true,
          "network_dns_servers": [
               "192.168.1.69"
          ],
          "ipam_options": {
               "driver": "host-local"
          },
          "containers": {
               "21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213": {
                    "name": "authelia",
                    "interfaces": {
                         "eth0": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.3.61/24",
                                        "gateway": "10.89.3.1"
                                   }
                              ],
                              "mac_address": "32:45:55:84:27:23"
                         }
                    }
               },
               "3dc3fca7d9466a00842730c223cebf516d471666fd8fa8419c28e942d3fcd9cd": {
                    "name": "authelia-redis",
                    "interfaces": {
                         "eth0": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.3.32/24",
                                        "gateway": "10.89.3.1"
                                   }
                              ],
                              "mac_address": "b6:56:1d:5a:c7:65"
                         }
                    }
               }
          }
     }
]

### systemd-media_services
[
     {
          "name": "systemd-media_services",
          "id": "f891dad271779530aa3bdab648f0bde96075690ee4189e6f4d57d525db670dbe",
          "driver": "bridge",
          "network_interface": "podman3",
          "created": "2025-10-20T15:19:42.621197014+02:00",
          "subnets": [
               {
                    "subnet": "10.89.1.0/24",
                    "gateway": "10.89.1.1"
               }
          ],
          "ipv6_enabled": false,
          "internal": false,
          "dns_enabled": true,
          "network_dns_servers": [
               "192.168.1.69"
          ],
          "ipam_options": {
               "driver": "host-local"
          },
          "containers": {
               "92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c": {
                    "name": "jellyfin",
                    "interfaces": {
                         "eth0": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.1.4/24",
                                        "gateway": "10.89.1.1"
                                   }
                              ],
                              "mac_address": "9e:06:35:55:53:9b"
                         }
                    }
               }
          }
     }
]

### systemd-reverse_proxy
[
     {
          "name": "systemd-reverse_proxy",
          "id": "d795412b2b279b89f9d0169bdbe973d0a7dc341edfca13e6e743c9a6d433c297",
          "driver": "bridge",
          "network_interface": "podman2",
          "created": "2025-10-20T15:15:54.845610412+02:00",
          "subnets": [
               {
                    "subnet": "10.89.2.0/24",
                    "gateway": "10.89.2.1"
               }
          ],
          "ipv6_enabled": false,
          "internal": false,
          "dns_enabled": true,
          "network_dns_servers": [
               "192.168.1.69"
          ],
          "ipam_options": {
               "driver": "host-local"
          },
          "containers": {
               "21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213": {
                    "name": "authelia",
                    "interfaces": {
                         "eth1": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.2.66/24",
                                        "gateway": "10.89.2.1"
                                   }
                              ],
                              "mac_address": "b6:16:7f:84:b2:1f"
                         }
                    }
               },
               "92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c": {
                    "name": "jellyfin",
                    "interfaces": {
                         "eth1": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.2.27/24",
                                        "gateway": "10.89.2.1"
                                   }
                              ],
                              "mac_address": "9a:0a:48:b1:7b:2d"
                         }
                    }
               },
               "dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df": {
                    "name": "traefik",
                    "interfaces": {
                         "eth0": {
                              "subnets": [
                                   {
                                        "ipnet": "10.89.2.26/24",
                                        "gateway": "10.89.2.1"
                                   }
                              ],
                              "mac_address": "0a:0c:47:cc:7f:19"
                         }
                    }
               }
          }
     }
]

### web_services
[
     {
          "name": "web_services",
          "id": "e7b65d1416a970c480918adf16a214291a6b746c5a3fcbda31c38ecc532ace57",
          "driver": "bridge",
          "network_interface": "podman1",
          "created": "2025-10-19T14:35:41.933782842+02:00",
          "subnets": [
               {
                    "subnet": "10.89.0.0/24",
                    "gateway": "10.89.0.1"
               }
          ],
          "ipv6_enabled": false,
          "internal": false,
          "dns_enabled": true,
          "network_dns_servers": [
               "192.168.1.69"
          ],
          "ipam_options": {
               "driver": "host-local"
          },
          "containers": {}
     }
]


## Quadlets & Units
Rendered units:
```
  authelia-redis.service                                 loaded active running Redis for Authelia Sessions (Secure)
  authelia.service                                       loaded active running Authelia SSO Server (Secure)
  jellyfin.service                                       loaded active running Jellyfin Media Server
  traefik.service                                        loaded active running Traefik Reverse Proxy
```

### Unit status
```

---- traefik.service ----
● traefik.service - Traefik Reverse Proxy
     Loaded: loaded (/home/patriark/.config/containers/systemd/traefik.container; generated)
    Drop-In: /usr/lib/systemd/user/service.d
             └─10-timeout-abort.conf
     Active: active (running) since Mon 2025-10-20 20:41:55 CEST; 1 day 1h ago
 Invocation: 79694171552a49a9b82b907b664b14a3
   Main PID: 1892725 (conmon)
      Tasks: 39 (limit: 37554)
     Memory: 57M (peak: 68.8M, swap: 3.5M, swap peak: 4.1M)
        CPU: 58.042s
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/traefik.service
             ├─libpod-payload-dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df
             │ └─1892727 traefik traefik
             └─runtime
               ├─1892705 rootlessport
               ├─1892712 rootlessport-child
               └─1892725 /usr/bin/conmon --api-version 1 -c dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df -u dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df -r /usr/bin/crun -b /home/patriark/.local/share/containers/storage/overlay-containers/dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df/userdata -p /run/user/1000/containers/overlay-containers/dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df/userdata/pidfile -n traefik --exit-dir /run/user/1000/libpod/tmp/exits --persist-dir /run/user/1000/libpod/tmp/persist/dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df --full-attach -l journald --log-level warning --syslog --runtime-arg --log-format=json --runtime-arg --log --runtime-arg=/run/user/1000/containers/overlay-containers/dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df/userdata/oci-log --conmon-pidfile /run/user/1000/containers/overlay-containers/dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df/userdata/conmon.pid --exit-command /usr/bin/podman --exit-command-arg --root --exit-command-arg /home/patriark/.local/share/containers/storage --exit-command-arg --runroot --exit-command-arg /run/user/1000/containers --exit-command-arg --log-level --exit-command-arg warning --exit-command-arg --cgroup-manager --exit-command-arg systemd --exit-command-arg --tmpdir --exit-command-arg /run/user/1000/libpod/tmp --exit-command-arg --network-config-dir --exit-command-arg "" --exit-command-arg --network-backend --exit-command-arg netavark --exit-command-arg --volumepath --exit-command-arg /home/patriark/.local/share/containers/storage/volumes --exit-command-arg --db-backend --exit-command-arg boltdb --exit-command-arg --transient-store=false --exit-command-arg --hooks-dir --exit-command-arg /usr/share/containers/oci/hooks.d --exit-command-arg --runtime --exit-command-arg crun --exit-command-arg --storage-driver --exit-command-arg overlay --exit-command-arg --events-backend --exit-command-arg journald --exit-command-arg container --exit-command-arg cleanup --exit-command-arg --stopped-only --exit-command-arg --rm --exit-command-arg dd92a319a67c63217e84974eda3d696f21d92c0c79c4acfdef24feffd5fb93df

okt. 20 20:41:55 fedora-htpc traefik[1892725]: 2025-10-20T18:41:55Z INF Starting provider *docker.Provider
okt. 20 20:41:55 fedora-htpc traefik[1892725]: 2025-10-20T18:41:55Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 20:43:17 fedora-htpc traefik[1892725]: 2025-10-20T18:43:17Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 20:43:48 fedora-htpc traefik[1892725]: 2025-10-20T18:43:48Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 20:51:56 fedora-htpc traefik[1892725]: 2025-10-20T18:51:56Z WRN A new release of Traefik has been found: 3.5.3. Please consider updating.
okt. 20 21:38:24 fedora-htpc traefik[1892725]: 2025-10-20T19:38:24Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 21:42:46 fedora-htpc traefik[1892725]: 2025-10-20T19:42:46Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 22:27:41 fedora-htpc traefik[1892725]: 2025-10-20T20:27:41Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 20 22:46:23 fedora-htpc traefik[1892725]: 2025-10-20T20:46:23Z ERR error="middleware \"authelia@docker\" does not exist" entryPointName=websecure routerName=api@docker
okt. 21 20:41:56 fedora-htpc traefik[1892725]: 2025-10-21T18:41:56Z WRN A new release of Traefik has been found: 3.5.3. Please consider updating.

---- authelia.service ----
● authelia.service - Authelia SSO Server (Secure)
     Loaded: loaded (/home/patriark/.config/containers/systemd/authelia.container; generated)
    Drop-In: /usr/lib/systemd/user/service.d
             └─10-timeout-abort.conf
     Active: active (running) since Mon 2025-10-20 22:50:39 CEST; 23h ago
 Invocation: 9b99f424a8e749d9a5d981d82be75a6d
   Main PID: 1918543 (conmon)
      Tasks: 18 (limit: 37554)
     Memory: 24.7M (peak: 98.9M, swap: 9M, swap peak: 9.1M)
        CPU: 24.434s
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/authelia.service
             ├─libpod-payload-21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213
             │ └─1918545 authelia
             └─runtime
               └─1918543 /usr/bin/conmon --api-version 1 -c 21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213 -u 21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213 -r /usr/bin/crun -b /home/patriark/.local/share/containers/storage/overlay-containers/21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213/userdata -p /run/user/1000/containers/overlay-containers/21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213/userdata/pidfile -n authelia --exit-dir /run/user/1000/libpod/tmp/exits --persist-dir /run/user/1000/libpod/tmp/persist/21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213 --full-attach -l journald --log-level warning --syslog --runtime-arg --log-format=json --runtime-arg --log --runtime-arg=/run/user/1000/containers/overlay-containers/21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213/userdata/oci-log --conmon-pidfile /run/user/1000/containers/overlay-containers/21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213/userdata/conmon.pid --exit-command /usr/bin/podman --exit-command-arg --root --exit-command-arg /home/patriark/.local/share/containers/storage --exit-command-arg --runroot --exit-command-arg /run/user/1000/containers --exit-command-arg --log-level --exit-command-arg warning --exit-command-arg --cgroup-manager --exit-command-arg systemd --exit-command-arg --tmpdir --exit-command-arg /run/user/1000/libpod/tmp --exit-command-arg --network-config-dir --exit-command-arg "" --exit-command-arg --network-backend --exit-command-arg netavark --exit-command-arg --volumepath --exit-command-arg /home/patriark/.local/share/containers/storage/volumes --exit-command-arg --db-backend --exit-command-arg boltdb --exit-command-arg --transient-store=false --exit-command-arg --hooks-dir --exit-command-arg /usr/share/containers/oci/hooks.d --exit-command-arg --runtime --exit-command-arg crun --exit-command-arg --storage-driver --exit-command-arg overlay --exit-command-arg --events-backend --exit-command-arg journald --exit-command-arg container --exit-command-arg cleanup --exit-command-arg --stopped-only --exit-command-arg --rm --exit-command-arg 21a6f65f4f129507c150e3bbf74d0d180dd99e1a088afad91913000cd0f82213

okt. 20 22:50:39 fedora-htpc authelia[1918543]: time="2025-10-20T20:50:39Z" level=info msg="Startup complete"
okt. 20 22:50:39 fedora-htpc authelia[1918543]: time="2025-10-20T20:50:39Z" level=info msg="Listening for non-TLS connections on '[::]:9091' path '/'" server=main service=server
okt. 20 22:51:36 fedora-htpc authelia[1918543]: time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43150: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
okt. 20 22:51:36 fedora-htpc authelia[1918543]: time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43152: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
okt. 20 22:51:36 fedora-htpc authelia[1918543]: time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43130: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
okt. 20 23:08:24 fedora-htpc authelia[1918543]: time="2025-10-20T21:08:24Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:42976: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
okt. 20 23:08:24 fedora-htpc authelia[1918543]: time="2025-10-20T21:08:24Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:42978: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
okt. 20 23:09:02 fedora-htpc authelia[1918543]: time="2025-10-20T21:09:02Z" level=info msg="The user session elevation has already expired so it has been destroyed" expired=1760993571 method=GET path=/api/user/session/elevation remote_ip=10.89.2.26 username=patriark
okt. 20 23:29:49 fedora-htpc authelia[1918543]: time="2025-10-20T21:29:49Z" level=info msg="The user session elevation has already expired so it has been destroyed" expired=1760995173 method=GET path=/api/user/session/elevation remote_ip=10.89.2.26 username=patriark
okt. 20 23:29:55 fedora-htpc authelia[1918543]: time="2025-10-20T21:29:55Z" level=error msg="Error occurred validating user session elevation One-Time Code challenge for user 'patriark': error occurred retrieving the code challenge from the storage backend" error="the code didn't match any recorded code challenges" method=PUT path=/api/user/session/elevation remote_ip=10.89.2.26

---- jellyfin.service ----
● jellyfin.service - Jellyfin Media Server
     Loaded: loaded (/home/patriark/.config/containers/systemd/jellyfin.container; generated)
    Drop-In: /usr/lib/systemd/user/service.d
             └─10-timeout-abort.conf
     Active: active (running) since Mon 2025-10-20 20:43:17 CEST; 1 day 1h ago
 Invocation: 7fe0e60f12214335923ba1225a4e96cc
   Main PID: 1893130 (conmon)
      Tasks: 49 (limit: 37554)
     Memory: 13.5G (peak: 14.7G, swap: 3M, swap peak: 3M)
        CPU: 18h 37min 19.609s
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/jellyfin.service
             ├─libpod-payload-92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c
             │ ├─1893132 /jellyfin/jellyfin
             │ └─2300935 /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -i "/media/music/Rock-Alternative-Prog/Pink Floyd/2001 - Eclipse/04 - Atom Heart Mother.mp3" -af ebur128=framelog=verbose -f null -
             └─runtime
               ├─1893085 rootlessport
               ├─1893092 rootlessport-child
               └─1893130 /usr/bin/conmon --api-version 1 -c 92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c -u 92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c -r /usr/bin/crun -b /home/patriark/.local/share/containers/storage/overlay-containers/92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c/userdata -p /run/user/1000/containers/overlay-containers/92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c/userdata/pidfile -n jellyfin --exit-dir /run/user/1000/libpod/tmp/exits --persist-dir /run/user/1000/libpod/tmp/persist/92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c --full-attach -l journald --log-level warning --syslog --runtime-arg --log-format=json --runtime-arg --log --runtime-arg=/run/user/1000/containers/overlay-containers/92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c/userdata/oci-log --conmon-pidfile /run/user/1000/containers/overlay-containers/92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c/userdata/conmon.pid --exit-command /usr/bin/podman --exit-command-arg --root --exit-command-arg /home/patriark/.local/share/containers/storage --exit-command-arg --runroot --exit-command-arg /run/user/1000/containers --exit-command-arg --log-level --exit-command-arg warning --exit-command-arg --cgroup-manager --exit-command-arg systemd --exit-command-arg --tmpdir --exit-command-arg /run/user/1000/libpod/tmp --exit-command-arg --network-config-dir --exit-command-arg "" --exit-command-arg --network-backend --exit-command-arg netavark --exit-command-arg --volumepath --exit-command-arg /home/patriark/.local/share/containers/storage/volumes --exit-command-arg --db-backend --exit-command-arg boltdb --exit-command-arg --transient-store=false --exit-command-arg --hooks-dir --exit-command-arg /usr/share/containers/oci/hooks.d --exit-command-arg --runtime --exit-command-arg crun --exit-command-arg --storage-driver --exit-command-arg overlay --exit-command-arg --events-backend --exit-command-arg journald --exit-command-arg container --exit-command-arg cleanup --exit-command-arg --stopped-only --exit-command-arg --rm --exit-command-arg 92bb833bdc6f87ef2b8c02caef6eebbcea3def23e92e4c7354f5e26f72cf410c

okt. 21 21:34:06 fedora-htpc jellyfin[1893130]: [out#0/null @ 0x5567ee927940] video:0KiB audio:0KiB subtitle:0KiB other streams:0KiB global headers:0KiB muxing overhead: unknown
okt. 21 21:34:06 fedora-htpc jellyfin[1893130]: [out#0/null @ 0x5567ee927940] Output file is empty, nothing was encoded(check -ss / -t / -frames parameters if used)
okt. 21 21:34:06 fedora-htpc jellyfin[1893130]: frame=    0 fps=0.0 q=0.0 Lsize=N/A time=N/A bitrate=N/A speed=N/A    
okt. 21 21:34:06 fedora-htpc jellyfin[1893130]: [21:34:06] [INF] [218] MediaBrowser.MediaEncoding.Attachments.AttachmentExtractor: ffmpeg attachment extraction completed for file:"/media/multimedia/Serier/Arcane/Arcane.S01.REPACK.2160p.UHD.BluRay.TrueHD.5.1.DV.HDR10.x265-MainFrame/Arcane.S01E09.The.Monster.You.Created.REPACK.2160p.BluRay.TrueHD.5.1.DV.HDR10.x265-MainFrame.mkv" to /cache/attachments/bf08e70879a4eb289c8bad41a632e4fb
okt. 21 21:34:06 fedora-htpc jellyfin[1893130]: [21:34:06] [INF] [218] MediaBrowser.MediaEncoding.Transcoding.TranscodeManager: /usr/lib/jellyfin-ffmpeg/ffmpeg -analyzeduration 200M -probesize 1G  -canvas_size 1920x1080 -i file:"/media/multimedia/Serier/Arcane/Arcane.S01.REPACK.2160p.UHD.BluRay.TrueHD.5.1.DV.HDR10.x265-MainFrame/Arcane.S01E09.The.Monster.You.Created.REPACK.2160p.BluRay.TrueHD.5.1.DV.HDR10.x265-MainFrame.mkv" -map_metadata -1 -map_chapters -1 -threads 0 -map 0:0 -map 0:1 -map -0:0 -codec:v:0 libx264 -preset veryfast -crf 23 -maxrate 42156987 -bufsize 84313974 -profile:v:0 high -level 51 -x264opts:0 subme=0:me_range=16:rc_lookahead=10:me=hex:open_gop=0 -force_key_frames:0 "expr:gte(t,n_forced*3)" -sc_threshold:v:0 0 -filter_complex "[0:3]scale,scale=-1:1632:fast_bilinear,crop,pad=max(3840\,iw):max(1632\,ih):(ow-iw)/2:(oh-ih)/2:black@0,crop=3840:1632[sub];[0:0]setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc,scale=trunc(min(max(iw\,ih*a)\,min(3840\,1632*a))/2)*2:trunc(min(max(iw/a\,ih)\,min(3840/a\,1632))/2)*2,tonemapx=tonemap=bt2390:desat=0:peak=100:t=bt709:m=bt709:p=bt709:format=yuv420p[main];[main][sub]overlay=eof_action=pass:repeatlast=0" -start_at_zero -codec:a:0 libfdk_aac -ac 2 -ab 256000 -af "volume=2" -copyts -avoid_negative_ts disabled -max_muxing_queue_size 2048 -f hls -max_delay 5000000 -hls_time 3 -hls_segment_type fmp4 -hls_fmp4_init_filename "55feb6703f2a3bc26c65c1b0eb9a0097-1.mp4" -start_number 0 -hls_segment_filename "/cache/transcodes/55feb6703f2a3bc26c65c1b0eb9a0097%d.mp4" -hls_playlist_type vod -hls_list_size 0 -y "/cache/transcodes/55feb6703f2a3bc26c65c1b0eb9a0097.m3u8"
okt. 21 21:34:07 fedora-htpc jellyfin[1893130]: [21:34:07] [INF] [70] Emby.Server.Implementations.Session.SessionManager: Playback stopped reported by app Jellyfin Web 10.10.7 playing Oil and Water. Stopped at 2304029 ms
okt. 21 21:57:48 fedora-htpc jellyfin[1893130]: [21:57:48] [INF] [79] MediaBrowser.MediaEncoding.Transcoding.TranscodeManager: FFmpeg exited with code 0
okt. 21 21:59:38 fedora-htpc jellyfin[1893130]: [21:59:38] [ERR] [79] Emby.Server.Implementations.ScheduledTasks.Tasks.AudioNormalizationTask: Failed to find LUFS value in output
okt. 21 22:13:21 fedora-htpc jellyfin[1893130]: [22:13:21] [INF] [57] MediaBrowser.MediaEncoding.Transcoding.TranscodeManager: Deleting partial stream file(s) /cache/transcodes/55feb6703f2a3bc26c65c1b0eb9a0097.m3u8
okt. 21 22:13:23 fedora-htpc jellyfin[1893130]: [22:13:23] [INF] [57] Emby.Server.Implementations.Session.SessionManager: Playback stopped reported by app Jellyfin Web 10.10.7 playing The Monster You Created. Stopped at 2348596 ms

```

## Traefik
- static file: /home/patriark/containers/config/traefik/etc/traefik.yml  [MISSING]
- dynamic dir: /home/patriark/containers/config/traefik/etc/dynamic
  files:
No dynamic files
- acme.json: /home/patriark/containers/config/traefik/acme/acme.json (absent)

### Traefik logs (tail)
```
[90m2025-10-20T18:41:55Z[0m [32mINF[0m Traefik version 3.2.5 built on 2025-01-07T14:16:14Z [36mversion=[0m3.2.5
[90m2025-10-20T18:41:55Z[0m [32mINF[0m 
Stats collection is disabled.
Help us improve Traefik by turning this feature on :)
More details on: https://doc.traefik.io/traefik/contributing/data-collection/

[90m2025-10-20T18:41:55Z[0m [32mINF[0m Starting provider aggregator *aggregator.ProviderAggregator
[90m2025-10-20T18:41:55Z[0m [32mINF[0m Starting provider *file.Provider
[90m2025-10-20T18:41:55Z[0m [32mINF[0m Starting provider *traefik.Provider
[90m2025-10-20T18:41:55Z[0m [32mINF[0m Starting provider *acme.ChallengeTLSALPN
[90m2025-10-20T18:41:55Z[0m [32mINF[0m Starting provider *docker.Provider
[90m2025-10-20T18:41:55Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T18:43:17Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T18:43:48Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T18:51:56Z[0m [31mWRN[0m A new release of Traefik has been found: 3.5.3. Please consider updating.
[90m2025-10-20T19:38:24Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T19:42:46Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T20:27:41Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-20T20:46:23Z[0m [1m[31mERR[0m[0m [36merror=[0m[31m"middleware \"authelia@docker\" does not exist"[0m [36mentryPointName=[0mwebsecure [36mrouterName=[0mapi@docker
[90m2025-10-21T18:41:56Z[0m [31mWRN[0m A new release of Traefik has been found: 3.5.3. Please consider updating.
```

## Authelia
- config dir: /home/patriark/containers/config/authelia
- files:
configuration.yml
users_database.yml

### Authelia logs (tail)
```
time="2025-10-20T20:50:39Z" level=info msg="Authelia v4.39.13 is starting"
time="2025-10-20T20:50:39Z" level=info msg="Log severity set to info"
time="2025-10-20T20:50:39Z" level=info msg="Storage schema is being checked for updates"
time="2025-10-20T20:50:39Z" level=info msg="Storage schema is already up to date"
time="2025-10-20T20:50:39Z" level=info msg="Startup complete"
time="2025-10-20T20:50:39Z" level=info msg="Listening for non-TLS connections on '[::]:9091' path '/'" server=main service=server
time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43150: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43152: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
time="2025-10-20T20:51:36Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:43130: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
time="2025-10-20T21:08:24Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:42976: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
time="2025-10-20T21:08:24Z" level=error msg="Request timeout occurred while handling request from client." error="read tcp 10.89.2.66:9091->10.89.2.26:42978: i/o timeout" method=GET path=/ remote_ip=10.89.2.26 status_code=408
time="2025-10-20T21:09:02Z" level=info msg="The user session elevation has already expired so it has been destroyed" expired=1760993571 method=GET path=/api/user/session/elevation remote_ip=10.89.2.26 username=patriark
time="2025-10-20T21:29:49Z" level=info msg="The user session elevation has already expired so it has been destroyed" expired=1760995173 method=GET path=/api/user/session/elevation remote_ip=10.89.2.26 username=patriark
time="2025-10-20T21:29:55Z" level=error msg="Error occurred validating user session elevation One-Time Code challenge for user 'patriark': error occurred retrieving the code challenge from the storage backend" error="the code didn't match any recorded code challenges" method=PUT path=/api/user/session/elevation remote_ip=10.89.2.26
```

### Notifier hints
```
/home/patriark/containers/config/authelia/backup-20251020-183838/configuration.yml:74:notifier:
/home/patriark/containers/config/authelia/configuration.yml:93:notifier:
```
