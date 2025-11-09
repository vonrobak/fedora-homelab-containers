# Homelab Snapshot Script: Developer Guide
## Learn to Build, Understand, and Extend System Intelligence

**Last Updated:** 2025-11-09
**Target Audience:** Developers learning bash scripting, system intelligence, infrastructure as code
**Prerequisites:** Basic bash knowledge, understanding of containers and systemd

---

## Table of Contents

1. [What is the Snapshot Script?](#what-is-the-snapshot-script)
2. [Architecture Overview](#architecture-overview)
3. [How It Works: Data Flow](#how-it-works-data-flow)
4. [Code Walkthrough](#code-walkthrough)
5. [Data Collection Techniques](#data-collection-techniques)
6. [JSON Structure Reference](#json-structure-reference)
7. [Extension Guide](#extension-guide)
8. [Testing & Validation](#testing--validation)
9. [Troubleshooting](#troubleshooting)
10. [Learning Resources](#learning-resources)

---

## What is the Snapshot Script?

### Purpose

The `homelab-snapshot.sh` script is a **system intelligence tool** that captures a comprehensive, point-in-time snapshot of your entire homelab infrastructure in JSON format.

**Think of it as:**
- A photographer capturing your infrastructure at a moment in time
- A health checkup for your homelab
- A detective gathering evidence about system state
- A documentation generator that never forgets details

### What It Captures

The script collects 14 categories of information:

1. **System Info** - Hostname, kernel, OS version, uptime
2. **Services** - All running containers with metadata
3. **Networks** - Network topology and container IPs
4. **Traefik Routing** - Reverse proxy configuration
5. **Storage** - Disk usage and volume mappings
6. **Resources** - Memory, CPU, swap usage
7. **Quadlet Configs** - Systemd service definitions
8. **Architecture** - Design patterns and principles
9. **Health Check Analysis** - Coverage and status
10. **Resource Limits Analysis** - Memory/CPU limits coverage
11. **Configuration Drift** - Running vs configured services
12. **Network Utilization** - Container distribution across networks
13. **Service Uptime** - How long services have been running
14. **Health Check Validation** - Binary validation and recommendations
15. **Automated Recommendations** - AI-driven improvement suggestions

### Output

A single JSON file in `docs/99-reports/snapshot-TIMESTAMP.json` containing:
- **820 lines** of structured data (for 16-service homelab)
- **Complete state** that can be diff'd over time
- **Machine-readable** for programmatic analysis
- **Human-readable** with proper JSON formatting

---

## Architecture Overview

### Design Philosophy

The script follows these principles:

**1. Non-Invasive**
- Read-only operations (never modifies system)
- Safe to run anytime, multiple times
- No dependencies beyond standard tools

**2. Fail-Safe**
- Individual collection failures don't crash the entire script
- Graceful degradation (missing data = empty fields)
- Always produces valid JSON

**3. Modular**
- Each data category is collected by independent function
- Functions follow naming convention: `collect_<category>()`
- Easy to add new collection functions

**4. Performance-Aware**
- Efficient data collection (no unnecessary loops)
- Timeouts on potentially slow operations
- Minimal resource usage during collection

**5. Structured Output**
- Consistent JSON schema
- Backwards compatible (old keys never removed)
- Documented structure

### Script Structure

```
homelab-snapshot.sh
├── Configuration & Argument Parsing
├── Helper Functions
│   ├── log_section()    - Pretty progress logging
│   ├── log_info()       - Success messages
│   └── json_escape()    - JSON string sanitization
├── Data Collection Functions (14 total)
│   ├── collect_system_info()
│   ├── collect_services()
│   ├── collect_networks()
│   ├── collect_traefik_routing()
│   ├── collect_storage()
│   ├── collect_resources()
│   ├── collect_quadlet_configs()
│   ├── collect_architectural_metadata()
│   ├── collect_health_analysis()
│   ├── collect_resource_limits_analysis()
│   ├── collect_configuration_drift()
│   ├── collect_network_utilization()
│   ├── collect_service_uptime()
│   ├── collect_health_check_validation()
│   └── collect_recommendations()
└── Main Function
    ├── Create output directory
    ├── Call all collection functions
    ├── Generate JSON
    ├── Validate output
    └── Print summary
```

---

## How It Works: Data Flow

### High-Level Flow

```
┌─────────────────┐
│   User runs     │
│  snapshot.sh    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Parse Arguments                    │
│  (--output-dir for custom location) │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Initialize                         │
│  - Set TIMESTAMP                    │
│  - Create output directory          │
│  - Set up JSON output file path     │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Data Collection (14 functions)     │
│  Each outputs JSON fragment         │
│  Logged to stderr for user feedback │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  JSON Assembly                      │
│  - Combine fragments into object    │
│  - Ensure valid syntax              │
│  - Write to file                    │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Validation                         │
│  - Check JSON validity (jq empty)   │
│  - Print summary statistics         │
│  - Report success/failure           │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Output                             │
│  docs/99-reports/snapshot-*.json    │
└─────────────────────────────────────┘
```

### Data Collection Pattern

Each collection function follows this pattern:

```bash
collect_<category>() {
    log_section "Collecting <category>"

    # 1. Initialize local variables
    local first=true
    local data=""

    # 2. Output JSON opening
    echo '  "<category>": {'

    # 3. Collect data (loop/query/parse)
    while <condition>; do
        # Handle commas (all but first item)
        [ "$first" = false ] && echo ","

        # Output JSON fragment
        cat <<EOF
    "key": {
      "field": "value"
    }
EOF
        first=false
    done

    # 4. Output JSON closing
    echo ""
    echo '  },'

    # 5. Log completion
    log_info "Collected <category>"
}
```

**Key Patterns:**
- `first=true` pattern for comma handling
- `cat <<EOF` heredocs for multi-line JSON
- `json_escape()` for string safety
- Error handling with `2>/dev/null` and fallbacks

---

## Code Walkthrough

### 1. Configuration & Setup

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**What this does:**
- `set -e` - Exit on error (fail-fast)
- `set -u` - Error on undefined variables (catch typos)
- `set -o pipefail` - Fail if any command in pipeline fails

**Why it matters:**
- Prevents script from continuing after errors
- Makes debugging easier (fails at the source, not downstream)
- Enforces strict error handling

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORT_DIR="${PROJECT_ROOT}/docs/99-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_OUTPUT="${REPORT_DIR}/snapshot-${TIMESTAMP}.json"
```

**What this does:**
- Finds script location (works when symlinked or called from elsewhere)
- Calculates project root (one directory up from scripts/)
- Sets report directory
- Creates timestamp (YYYYMMDDHHmmss format)
- Constructs output filename

**Why it matters:**
- Works from any directory (no hardcoded paths)
- Timestamp prevents overwriting previous snapshots
- Consistent naming convention

### 2. Helper Functions

#### json_escape()

```bash
json_escape() {
    local string="$1"
    printf '%s' "$string" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/; $s/\\n$//'
}
```

**What this does:**
- Escapes backslashes: `\` → `\\`
- Escapes quotes: `"` → `\"`
- Adds newline after each line: `line` → `line\n`
- Removes trailing newline from last line

**Why it matters:**
- Prevents JSON syntax errors from strings containing special characters
- Example: Service description "Uses \"quotes\"" becomes "Uses \\\"quotes\\\""

**When to use:**
- ANY user-provided string that goes into JSON
- Service names, paths, configuration values

### 3. Data Collection Functions

#### collect_system_info() - Simple Example

```bash
collect_system_info() {
    log_section "Collecting system information"

    # Gather data
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local os_version=$(cat /etc/fedora-release 2>/dev/null || echo "Unknown")
    local selinux=$(getenforce 2>/dev/null || echo "Unknown")

    # Output JSON
    cat <<EOF
  "system": {
    "hostname": "$hostname",
    "kernel": "$kernel",
    "os": "$(json_escape "$os_version")",
    "selinux": "$selinux",
    "uptime_seconds": $uptime_seconds,
    "timestamp": "$(date -Iseconds)",
    "snapshot_version": "1.1"
  },
EOF
}
```

**Learning Points:**

1. **Variable naming:** Use descriptive names (`uptime_seconds`, not `us`)
2. **Error handling:** `2>/dev/null || echo "Unknown"` provides fallback
3. **String escaping:** Use `json_escape()` for `$os_version` (contains spaces)
4. **Numbers vs Strings:** `$uptime_seconds` is unquoted (number), `"$hostname"` is quoted (string)
5. **Trailing comma:** Notice the comma after closing brace (needed for JSON array)

#### collect_services() - Complex Example

```bash
collect_services() {
    log_section "Collecting service inventory"

    local first=true
    echo '  "services": {'

    while IFS= read -r container_name; do
        [ "$first" = false ] && echo ","

        # Get container details using podman inspect
        local image=$(podman inspect "$container_name" --format '{{.ImageName}}' 2>/dev/null || echo "unknown")
        local status=$(podman inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        local health=$(podman inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

        # ... more data collection ...

        cat <<EOF
    "$container_name": {
      "image": "$(json_escape "$image")",
      "status": "$status",
      "health": "$health"
      # ... more fields ...
    }
EOF
        first=false
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)

    echo ""
    echo '  },'
}
```

**Learning Points:**

1. **Loop pattern:** `while IFS= read -r` safely reads lines (handles spaces)
2. **Comma handling:** `first=true` pattern avoids leading comma
3. **Process substitution:** `< <(command)` creates input from command output
4. **podman inspect:** Use `--format` templates to extract specific fields
5. **Defensive programming:** Every command has `2>/dev/null || echo "fallback"`

#### collect_health_check_validation() - Advanced Example

```bash
collect_health_check_validation() {
    log_section "Validating health check configurations"

    local first=true
    echo '  "health_check_validation": {'
    echo '    "validated_services": {'

    while IFS= read -r container_name || [ -n "$container_name" ]; do
        # Get health check command
        local health_cmd=$(podman inspect "$container_name" \
            --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}none{{end}}' \
            2>/dev/null || echo "none")

        if [ "$health_cmd" != "none" ] && [ -n "$health_cmd" ]; then
            # Parse command and validate binary exists
            local cmd_binary=$(echo "$health_cmd" | jq -r '.[1]' 2>/dev/null | \
                grep -oE '(curl|wget|nc)' | head -1)

            # Test binary existence with timeout
            (timeout --kill-after=1s 2s podman exec "$container_name" \
                which "$cmd_binary" </dev/null) &>/dev/null
            local exit_code=$?

            # Determine validation status
            if [ $exit_code -eq 0 ]; then
                validation_status="valid"
            elif [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
                validation_status="timeout"
            else
                validation_status="invalid"
            fi

            # Output JSON with recommendations
            # ...
        fi
    done < <(podman ps --format '{{.Names}}' 2>/dev/null)
}
```

**Advanced Techniques:**

1. **Conditional JSON extraction:** `{{if .Config.Healthcheck}}...{{else}}...{{end}}`
2. **jq parsing:** Extract elements from JSON arrays
3. **Timeout handling:** Prevent hanging on unresponsive containers
4. **Exit code interpretation:** Different failures mean different things
5. **Subshell isolation:** `(timeout ...)` prevents script termination
6. **Null input:** `</dev/null` prevents stdin interference

---

## Data Collection Techniques

### Technique 1: podman inspect

**Purpose:** Extract detailed container metadata

**Basic usage:**
```bash
podman inspect <container> --format '{{.Field}}'
```

**Common fields:**
- `.ImageName` - Container image
- `.State.Status` - Running/stopped/created
- `.State.Health.Status` - healthy/unhealthy/none
- `.State.StartedAt` - Start timestamp
- `.NetworkSettings.Networks` - Network membership
- `.Mounts` - Volume mappings

**Advanced patterns:**

Extract JSON array:
```bash
podman inspect <container> --format '{{json .Config.Healthcheck.Test}}'
```

Conditional extraction:
```bash
podman inspect <container> --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
```

Loop over map:
```bash
podman inspect <container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

### Technique 2: systemd Service Inspection

**Purpose:** Determine quadlet configuration and service status

**Check if service is active:**
```bash
systemctl --user is-active <service>.service &>/dev/null
if [ $? -eq 0 ]; then
    echo "Service is active"
fi
```

**Find quadlet file:**
```bash
if [ -f "${HOME}/.config/containers/systemd/${container_name}.container" ]; then
    quadlet_file="${HOME}/.config/containers/systemd/${container_name}.container"
fi
```

**Parse quadlet configuration:**
```bash
local image=$(grep '^Image=' "$quadlet_file" | sed 's/Image=//')
local memory_max=$(grep '^MemoryMax=' "$quadlet_file" | sed 's/MemoryMax=//')
```

### Technique 3: Network Topology Mapping

**Purpose:** Map containers to networks with IP addresses

**Challenge:** Podman doesn't directly show IP per network

**Solution - Multi-step extraction:**

```bash
# 1. Get all networks for a container
local container_networks=$(podman inspect "$container_name" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')

# 2. For each network, extract IP
for network in $container_networks; do
    local ip=$(podman inspect "$container_name" --format "json" | \
        grep -A 20 "\"$network_name\"" | \
        grep "IPAddress" | head -1 | \
        sed 's/.*: "\(.*\)".*/\1/')

    echo "${container_name}:${ip}"
done
```

**Alternative - Network-first approach:**
```bash
# Inspect network to find all containers
podman network inspect "$network_name" | \
    grep -B 5 '"name": "<container>"' | \
    grep "ipv4" | \
    sed 's/.*: "\([^/]*\).*/\1/'
```

### Technique 4: YAML Parsing (Traefik Config)

**Purpose:** Extract routing configuration from YAML files

**Challenge:** No `yq` available, need bash-based parsing

**Solution - Pattern matching:**

```bash
local current_router=""
local current_rule=""

while IFS= read -r line; do
    # Detect router name
    if echo "$line" | grep -E '^    [a-z-]+:$' >/dev/null; then
        current_router=$(echo "$line" | sed 's/^ *//; s/:$//')
    fi

    # Extract rule
    if echo "$line" | grep -E '^ *rule:' >/dev/null; then
        current_rule=$(echo "$line" | sed 's/.*rule: *//; s/"//g')
    fi

    # Extract middlewares (array items)
    if echo "$line" | grep -E '^ *- [a-z-]+' >/dev/null; then
        middleware=$(echo "$line" | sed 's/.*- *//')
        middlewares="${middlewares},\"$middleware\""
    fi
done < "$routers_file"
```

**Limitations:**
- Fragile (breaks if YAML structure changes significantly)
- No nested structure support
- Consider using `yq` in future versions

### Technique 5: Timestamp Parsing & Calculation

**Purpose:** Calculate service uptime from start timestamp

**Challenge:** Podman timestamps have non-standard format

**Podman format:**
```
2025-11-04 12:00:10.44327386 +0100 CET
```

**GNU date needs:**
```
2025-11-04 12:00:10 +0100
```

**Cleaning solution:**
```bash
# Remove fractional seconds and timezone name
local started_clean=$(echo "$started" | \
    sed 's/\.[0-9]* / /' | \  # Remove .fractional_seconds
    sed 's/ [A-Z][A-Z]*$//')   # Remove timezone name (CET, UTC, etc.)

# Parse to epoch
local started_epoch=$(date -d "$started_clean" +%s 2>/dev/null || echo 0)
local current_epoch=$(date +%s)
local uptime_seconds=$((current_epoch - started_epoch))
```

**Convert seconds to human-readable:**
```bash
local days=$((uptime_seconds / 86400))
local hours=$(((uptime_seconds % 86400) / 3600))
local minutes=$(((uptime_seconds % 3600) / 60))

if [ $days -gt 0 ]; then
    uptime_human="${days}d ${hours}h ${minutes}m"
elif [ $hours -gt 0 ]; then
    uptime_human="${hours}h ${minutes}m"
else
    uptime_human="${minutes}m"
fi
```

### Technique 6: Health Check Binary Validation

**Purpose:** Verify health check commands can actually run

**Challenge:** Container may not have required binary (curl, wget)

**Safe validation with timeout:**

```bash
# Wrap in subshell to prevent script termination
(timeout --kill-after=1s 2s podman exec "$container_name" \
    which "$cmd_binary" </dev/null) &>/dev/null 2>&1

local exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "Binary found"
elif [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
    echo "Timeout (container unresponsive)"
else
    echo "Binary not found"
fi
```

**Why this is complex:**
- Container may be starting up (timeout needed)
- Container may be in crash loop (needs non-blocking check)
- Exit codes have meaning (0=found, 124=timeout, other=not found)

---

## JSON Structure Reference

### Top-Level Schema

```json
{
  "system": { ... },              // Host metadata
  "services": { ... },            // Container inventory
  "networks": { ... },            // Network topology
  "traefik_routing": { ... },     // Reverse proxy config
  "storage": { ... },             // Disk usage & volumes
  "resources": { ... },           // CPU, memory, load
  "quadlet_configs": { ... },     // Systemd definitions
  "architecture": { ... },        // Design patterns
  "health_check_analysis": { ... },       // Health coverage stats
  "resource_limits_analysis": { ... },    // Resource limit stats
  "configuration_drift": { ... },         // Running vs configured
  "network_utilization": { ... },         // Network distribution
  "service_uptime": { ... },              // Uptime calculations
  "health_check_validation": { ... },     // Binary validation
  "recommendations": { ... }              // Automated suggestions
}
```

### services Object

```json
"services": {
  "<container_name>": {
    "image": "docker.io/library/traefik:v3.2",
    "status": "running",
    "health": "healthy",  // or "unhealthy", "none"
    "started": "2025-11-09T18:07:32+01:00",
    "systemd_active": "active",
    "networks": ["systemd-reverse_proxy", "systemd-monitoring"],
    "ports": ["80/tcp", "443/tcp", "8080/tcp"],
    "volumes": ["/path/on/host:/path/in/container"],
    "memory_mb": 45,
    "quadlet_file": "/home/user/.config/containers/systemd/traefik.container"
  }
}
```

### networks Object

```json
"networks": {
  "<network_name>": {
    "subnet": "10.89.2.0/24",
    "gateway": "10.89.2.1",
    "driver": "bridge",
    "containers": ["traefik:10.89.2.74", "grafana:10.89.2.58"]
  }
}
```

### recommendations Object

```json
"recommendations": {
  "priority_actions": [
    {
      "priority": "high",
      "category": "health_check",
      "service": "traefik",
      "issue": "Service has no health check configured",
      "impact": "Cannot detect service failures automatically",
      "fix_command": "Add HealthCmd=... to quadlet file",
      "estimated_time": "5 minutes"
    }
  ],
  "summary": {
    "total_recommendations": 5,
    "by_priority": {
      "high": 2,
      "medium": 2,
      "low": 1
    }
  }
}
```

---

## Extension Guide

### Adding a New Collection Function

**Example: Collect SSL Certificate Expiry**

```bash
collect_ssl_certificates() {
    log_section "Analyzing SSL certificates"

    local cert_dir="${PROJECT_ROOT}/config/traefik/letsencrypt"
    local acme_json="${cert_dir}/acme.json"

    echo '  "ssl_certificates": {'

    if [ -f "$acme_json" ]; then
        # Extract certificate domains and expiry dates
        # (This would require jq to parse acme.json)

        echo '    "status": "implemented",'
        echo '    "certificates": []'
    else
        echo '    "status": "not_configured"'
    fi

    echo '  },'

    log_info "Analyzed SSL certificates"
}
```

**Integration steps:**

1. **Write the function** following naming convention: `collect_<category>()`
2. **Add to main()** in the appropriate order
3. **Test independently** by calling function directly
4. **Validate JSON** output with `jq empty`
5. **Update schema documentation** in this guide

### Adding Intelligence/Recommendations

**Example: Detect services without restart policies**

```bash
collect_restart_policy_analysis() {
    log_section "Analyzing restart policies"

    local services_without_restart=""
    local quadlet_dir="${HOME}/.config/containers/systemd"

    for quadlet_file in "$quadlet_dir"/*.container; do
        [ -f "$quadlet_file" ] || continue

        local service_name=$(basename "$quadlet_file" .container)

        # Check if Restart= directive exists
        if ! grep -q '^Restart=' "$quadlet_file"; then
            [ -n "$services_without_restart" ] && \
                services_without_restart="${services_without_restart}, "
            services_without_restart="${services_without_restart}\"$service_name\""
        fi
    done

    cat <<EOF
  "restart_policy_analysis": {
    "services_without_restart": [${services_without_restart}],
    "recommendation": "Add 'Restart=always' to [Service] section for production services"
  },
EOF

    log_info "Analyzed restart policies"
}
```

### Adding Validation Checks

**Example: Validate Traefik router syntax**

```bash
validate_traefik_routers() {
    local routers_file="${PROJECT_ROOT}/config/traefik/dynamic/routers.yml"

    # Check for common mistakes
    local issues=""

    # Check 1: Deprecated IPWhiteList
    if grep -q "IPWhiteList" "$routers_file"; then
        issues="Uses deprecated IPWhiteList (migrate to IPAllowList)"
    fi

    # Check 2: Missing security headers
    while read -r router_name; do
        if ! grep -A 10 "^    $router_name:" "$routers_file" | \
            grep -q "security-headers"; then
            issues="${issues}, ${router_name} missing security headers"
        fi
    done < <(grep -E '^    [a-z-]+:$' "$routers_file" | sed 's/://; s/^ *//')

    echo "Issues: $issues"
}
```

---

## Testing & Validation

### Unit Testing Individual Functions

**Test a single collection function:**

```bash
# Source the script without running main
source scripts/homelab-snapshot.sh

# Test individual function
collect_system_info | jq .
```

**Expected output:**
```json
{
  "system": {
    "hostname": "fedora-htpc",
    "kernel": "6.17.6-200.fc42.x86_64",
    ...
  }
}
```

### Integration Testing

**Full script test:**

```bash
# Run script
./scripts/homelab-snapshot.sh

# Validate JSON
jq empty docs/99-reports/snapshot-*.json && echo "Valid JSON" || echo "Invalid JSON"

# Pretty-print
jq . docs/99-reports/snapshot-*.json | less
```

### Validation Checklist

- [ ] Script completes without errors
- [ ] JSON is valid (`jq empty` succeeds)
- [ ] All services captured
- [ ] All networks mapped
- [ ] No "unknown" or "error" values (or they're expected)
- [ ] Timestamps are correct format
- [ ] Recommendations make sense
- [ ] File size is reasonable (800-1000 lines for 16 services)

### Regression Testing

**Compare snapshots over time:**

```bash
# Take baseline
./scripts/homelab-snapshot.sh
cp docs/99-reports/snapshot-*.json /tmp/baseline.json

# Make changes
systemctl --user restart traefik.service

# Take new snapshot
./scripts/homelab-snapshot.sh

# Compare (using jq for structured diff)
diff <(jq --sort-keys . /tmp/baseline.json) \
     <(jq --sort-keys . docs/99-reports/snapshot-*.json)
```

---

## Troubleshooting

### Problem: JSON Syntax Error

**Symptom:**
```
⚠ JSON validation failed - check output
```

**Debugging:**

```bash
# Find the syntax error
jq . docs/99-reports/snapshot-*.json
# Will show line number of error

# Check for common issues
grep -n ',,\|,\s*}' docs/99-reports/snapshot-*.json  # Double commas or trailing commas
```

**Common causes:**
1. **Double comma** - `first=true` pattern not working
2. **Trailing comma before }** - Missing comma removal
3. **Unescaped quotes** - Missing `json_escape()` call
4. **Missing comma** - Forgot comma after collection function

**Fix pattern:**
```bash
# In collection function, ensure:
[ "$first" = false ] && echo ","  # Before each item after first
first=false  # After outputting item
```

### Problem: Empty or Missing Data

**Symptom:** Fields show "unknown" or empty arrays

**Debugging:**

```bash
# Test podman command directly
podman inspect traefik --format '{{.ImageName}}'

# Check if service is actually running
podman ps | grep traefik

# Test quadlet file exists
ls -la ~/.config/containers/systemd/traefik.container
```

**Common causes:**
1. **Service not running** - `podman ps` shows nothing
2. **Wrong format string** - `podman inspect` returns nothing
3. **Permission issue** - Can't read quadlet files
4. **Network/service renamed** - Hardcoded names don't match

### Problem: Script Hangs

**Symptom:** Script stops responding, no output

**Likely culprit:** Health check validation (container not responding)

**Debugging:**

```bash
# Find which container is hanging
podman ps --format '{{.Names}}'

# Test health check manually
podman exec <container> which curl  # If this hangs, container is unresponsive
```

**Fix:** Already implemented via timeout:
```bash
(timeout --kill-after=1s 2s podman exec "$container" which curl) &>/dev/null
```

### Problem: Permission Denied

**Symptom:**
```
Error: cannot read /home/user/.config/containers/systemd/...
```

**Cause:** Running as different user

**Fix:**
```bash
# Ensure running as correct user
whoami  # Should match container owner

# Run with correct user context
sudo -u <user> ./scripts/homelab-snapshot.sh
```

---

## Learning Resources

### Bash Scripting

**Essential concepts for this script:**
- [Bash Heredocs](https://linuxize.com/post/bash-heredoc/) - Multi-line strings
- [Process Substitution](https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html) - `< <(command)`
- [Arrays and Loops](https://www.gnu.org/software/bash/manual/html_node/Arrays.html)
- [Conditional Expressions](https://www.gnu.org/software/bash/manual/html_node/Bash-Conditional-Expressions.html)

**Advanced patterns:**
- Error handling with `set -euo pipefail`
- String manipulation with `${var//pattern/replacement}`
- Exit code checking: `$?`
- Subshells and background jobs

### JSON in Bash

- [jq Tutorial](https://stedolan.github.io/jq/tutorial/) - JSON parsing
- [JSON escaping rules](https://www.json.org/json-en.html)
- Generating JSON from bash (this script is an example!)

### Podman Inspection

- [podman inspect reference](https://docs.podman.io/en/latest/markdown/podman-inspect.1.html)
- [Go template syntax](https://pkg.go.dev/text/template) - Used in `--format`
- [Podman REST API](https://docs.podman.io/en/latest/Reference.html) - Alternative to CLI

### SystemD

- [Systemd quadlet guide](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [systemctl reference](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- Parsing unit files with bash

---

## Next Steps

**Once you understand this script:**

1. **Extend it** - Add new collection functions (SSL certs, logs, metrics)
2. **Automate it** - Run daily via systemd timer, track changes
3. **Analyze it** - Write tools that consume the JSON (Python scripts, Grafana dashboards)
4. **Compare it** - Diff snapshots to detect drift and changes
5. **Share it** - Contribute patterns back to the community

**Related projects:**

- Build a web UI to visualize snapshots
- Create Grafana dashboard from snapshot data
- Write Python analyzer for recommendations
- Integrate with CI/CD for validation
- Generate network topology diagrams from snapshot data

---

## Conclusion

The homelab-snapshot script demonstrates:
- **System intelligence** - Comprehensive data collection
- **Bash proficiency** - Advanced scripting patterns
- **JSON generation** - Structured data output
- **Error handling** - Defensive programming
- **Modularity** - Extensible architecture

**Key takeaways:**
1. **Read-only intelligence** is powerful and safe
2. **Structured output** enables automation
3. **Modular design** makes extension easy
4. **Good error handling** makes scripts reliable
5. **Documentation** makes code maintainable

Use this guide as a reference when extending the script or building similar intelligence tools for your infrastructure.

---

**Last Updated:** 2025-11-09
**Version:** 1.0
**Maintained By:** Homelab Documentation Team
**Related:** `scripts/homelab-snapshot.sh`, `docs/99-reports/snapshot-*.json`
