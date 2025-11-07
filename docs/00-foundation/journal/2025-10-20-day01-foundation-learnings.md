
## Firewall Configuration (Critical!)

### Problem Encountered
Container accessible locally but not from network → firewalld blocking

### Solution
Containers published on host ports need firewall rules:
```bash
# Quick: Open specific port
sudo firewall-cmd --add-port=8080/tcp --permanent

# Better: Create service definition for port ranges
sudo firewall-cmd --add-service=homelab-containers --permanent
sudo firewall-cmd --reload
```

### Firewall Zones
Current zone: FedoraWorkstation (default for desktop)
- Allows: ssh, dhcpv6-client, mdns, samba, samba-client
- Blocks: Everything else by default (secure!)

### Important Ports to Remember
- 8080-8099: Container testing/development
- 8096: Jellyfin (will add in Day 4)
- 80, 443: Reverse proxy (will add in Week 2)

### Checking Firewall Status
```bash
# See what's allowed
sudo firewall-cmd --list-all

# See all zones
sudo firewall-cmd --get-zones

# See active zones
sudo firewall-cmd --get-active-zones
```
