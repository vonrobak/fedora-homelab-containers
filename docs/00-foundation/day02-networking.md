
## DNS Configuration Issues & Resolution

### Problem Encountered
`nslookup` was trying 127.0.0.1 first (systemd-resolved) before falling back to Pi-hole, causing errors and NXDOMAIN responses.

### Root Cause
- systemd-resolved was intercepting DNS queries
- /etc/resolv.conf pointed to 127.0.0.1 (stub resolver)
- Search domain not configured for .lokal

### Solution Applied
1. Disabled systemd-resolved
2. Configured NetworkManager to use Pi-hole directly
3. Set search domain to "lokal"
4. Created static /etc/resolv.conf:
```
   nameserver 192.168.1.69
   search lokal
```

### Why .lokal Instead of .local?
- .local is reserved for mDNS (Avahi/Bonjour)
- .lokal avoids conflicts with Apple devices and Linux mDNS
- This is actually a best practice! ✓

### Verification Commands
```bash
# Check DNS config
cat /etc/resolv.conf

# Test resolution
nslookup jellyfin.lokal
nslookup jellyfin  # Should also work (search domain adds .lokal)

# From container
podman exec web1 nslookup jellyfin.lokal
```

### Current DNS Flow (Fixed)
```
Container query for jellyfin.lokal
    ↓
aardvark-dns (10.89.0.1)
    ↓ Not a container name, forward to host
Host /etc/resolv.conf → 192.168.1.69 (direct, no stub)
    ↓
Pi-hole (192.168.1.69)
    ↓ Check custom DNS entries
Found: jellyfin.lokal → 192.168.1.70
    ↓
Returns cleanly ✓
```

### Your Pi-hole Local DNS Records
Total entries: 27 domains mapping to various IPs
All homelab services (*.lokal) → 192.168.1.70
Network devices have their own IPs:
- raspberrypi.lokal → 192.168.1.69 (Pi-hole itself)
- unifiu7pro.lokal → 192.168.1.10 (UDM Pro)
- huebridge.lokal → 192.168.2.60 (IoT VLAN)
- etc.

This is excellent organization! ✓

## Container DNS Search Domain Issue

### Problem
Containers could resolve internet domains and container names, but not local `.lokal` domains without FQDN.

### Root Cause
Podman wasn't passing the DNS search domain (`lokal`) to containers.

### Solution
Created `/etc/containers/containers.conf.d/dns.conf`:
```ini
[containers]
dns_search = ["lokal"]
```

### Alternative (Per-Container)
Add DNS settings when creating containers:
```bash
podman run --dns 192.168.1.69 --dns-search lokal ...
```

### Verification
```bash
# Check container DNS config
podman exec CONTAINER cat /etc/resolv.conf

# Should include:
# search lokal
# nameserver 10.89.0.1
# nameserver 192.168.1.69 (if using --dns flag)
```

### Result
Containers can now resolve:
✓ Container names (web1, web2)
✓ Local domains (jellyfin.lokal)
✓ Internet domains (google.com)
