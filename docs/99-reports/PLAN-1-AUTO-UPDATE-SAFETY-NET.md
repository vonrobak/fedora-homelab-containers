# Plan 1: Auto-Update Safety Net - Implementation Roadmap

**Created:** 2025-11-18
**Status:** Ready for CLI Execution
**Priority:** 🔥 CRITICAL - Prevents bad updates from breaking homelab overnight
**Estimated Effort:** 6-9 hours (2-3 CLI sessions)
**Dependencies:** Existing quadlets with AutoUpdate=registry

---

## Executive Summary

**The Problem:**
Your quadlets use `AutoUpdate=registry` which automatically pulls and deploys new container images. **There's no safety mechanism.** If upstream pushes a broken image:
- Jellyfin breaks → Media server offline until you manually fix it
- Traefik breaks → **Entire homelab offline** until you manually fix it
- Prometheus breaks → Lose monitoring + historical data
- You discover the problem when you try to use the service (could be days later)

**Current Vulnerability:**
```
Night:  AutoUpdate pulls new Jellyfin image
        → Podman restarts container with new image
        → New image has bug (crashes on startup)
        → Service fails to start
        → AutoUpdate marks as "updated" ✅
        → YOU DON'T KNOW UNTIL YOU TRY TO WATCH SOMETHING

Morning: "Why isn't Jellyfin working?"
         → Check logs, realize bad update
         → Manually find previous image tag
         → Manually rollback
         → 30-60 minutes of downtime
```

**The Solution: Health-Aware Auto-Update with Automatic Rollback**

```
Night:  AutoUpdate pulls new Jellyfin image
        → Podman restarts container with new image
        → Health check script runs (60s wait + HTTP check)
        → Health check FAILS ❌
        → Rollback script automatically triggered
        → Stop service
        → Revert to previous image tag
        → Restart service with old image
        → Alert sent to Discord: "Jellyfin auto-update failed, rolled back"
        → Context Framework logs the incident

Morning: Check Discord: "Jellyfin update failed last night, system rolled back automatically"
         → Service still working ✅
         → Can investigate at your leisure
```

---

## Architecture

### Three-Component System

```
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 1: Health Check Scripts                             │
│  One script per critical service                               │
│  • Wait for service to stabilize (configurable, default 60s)  │
│  • Run service-specific health check                          │
│  • Exit 0 if healthy, exit 1 if unhealthy                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 2: Rollback Automation                              │
│  Central rollback script triggered on health check failure    │
│  • Tag current (failing) image for investigation               │
│  • Identify previous working image from podman history         │
│  • Stop service                                                │
│  • Update container to use previous image                      │
│  • Restart service                                             │
│  • Verify rollback successful                                  │
│  • Log incident to Context Framework                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  COMPONENT 3: Integration & Monitoring                         │
│  • Quadlets updated with ExecStartPost health checks           │
│  • OnFailure triggers rollback script                          │
│  • Prometheus metrics: autoupdate_rollback_count               │
│  • Alertmanager: Discord notifications                         │
│  • Context Framework: Issue tracking (ISS-XXX)                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Session 1: Health Check Framework (3-4 hours)

### Phase 1.1: Core Health Check Infrastructure (1h)

**Objective:** Create reusable health check framework

**Deliverable: Base Health Check Library**

**File:** `scripts/health-checks/health-check-lib.sh`

```bash
#!/bin/bash
################################################################################
# Health Check Library
# Common functions for service health checks
################################################################################

# Configuration
DEFAULT_WAIT_TIME=60
DEFAULT_TIMEOUT=10
DEFAULT_RETRIES=3

# Logging
log_health() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" >&2
}

# Wait for service to stabilize
wait_for_stabilization() {
    local wait_time=${1:-$DEFAULT_WAIT_TIME}
    log_health "INFO" "Waiting ${wait_time}s for service to stabilize..."
    sleep "$wait_time"
}

# HTTP health check
http_health_check() {
    local url=$1
    local expected_status=${2:-200}
    local timeout=${3:-$DEFAULT_TIMEOUT}
    local retries=${4:-$DEFAULT_RETRIES}

    log_health "INFO" "Checking HTTP endpoint: $url"

    for i in $(seq 1 "$retries"); do
        local status=$(curl -s -o /dev/null -w '%{http_code}' \
            --max-time "$timeout" \
            "$url" 2>/dev/null || echo "000")

        if [[ "$status" == "$expected_status" ]]; then
            log_health "SUCCESS" "HTTP check passed (status: $status)"
            return 0
        fi

        log_health "WARNING" "Attempt $i/$retries failed (status: $status)"
        [[ $i -lt $retries ]] && sleep 2
    done

    log_health "ERROR" "HTTP check failed after $retries attempts"
    return 1
}

# TCP port check
tcp_port_check() {
    local host=${1:-localhost}
    local port=$2
    local timeout=${3:-$DEFAULT_TIMEOUT}

    log_health "INFO" "Checking TCP port: $host:$port"

    if timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        log_health "SUCCESS" "TCP port check passed"
        return 0
    else
        log_health "ERROR" "TCP port check failed"
        return 1
    fi
}

# Container running check
container_running_check() {
    local container_name=$1

    log_health "INFO" "Checking if container is running: $container_name"

    local status=$(podman inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || echo "false")

    if [[ "$status" == "true" ]]; then
        log_health "SUCCESS" "Container is running"
        return 0
    else
        log_health "ERROR" "Container is not running"
        return 1
    fi
}

# Export functions
export -f wait_for_stabilization
export -f http_health_check
export -f tcp_port_check
export -f container_running_check
export -f log_health
```

---

### Phase 1.2: Service-Specific Health Checks (1-2h)

**Objective:** Create health checks for all critical services

#### Health Check 1: Jellyfin

**File:** `scripts/health-checks/jellyfin-health.sh`

```bash
#!/bin/bash
################################################################################
# Jellyfin Health Check
# Validates Jellyfin is responding after update
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/health-check-lib.sh"

SERVICE_NAME="jellyfin"
HEALTH_URL="http://localhost:8096/health"
WEB_URL="http://localhost:8096/web/index.html"

main() {
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_health "INFO" "  Jellyfin Health Check Starting"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for service to stabilize
    wait_for_stabilization 60

    # Check 1: Container running
    if ! container_running_check "$SERVICE_NAME"; then
        log_health "ERROR" "Jellyfin container not running"
        exit 1
    fi

    # Check 2: Health endpoint
    if ! http_health_check "$HEALTH_URL" 200 10 3; then
        log_health "ERROR" "Jellyfin health endpoint check failed"
        exit 1
    fi

    # Check 3: Web UI accessible
    if ! http_health_check "$WEB_URL" 200 10 3; then
        log_health "ERROR" "Jellyfin web UI check failed"
        exit 1
    fi

    log_health "SUCCESS" "✅ All Jellyfin health checks passed"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
}

main "$@"
```

#### Health Check 2: Traefik (CRITICAL)

**File:** `scripts/health-checks/traefik-health.sh`

```bash
#!/bin/bash
################################################################################
# Traefik Health Check
# CRITICAL: If Traefik is down, entire homelab is offline
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/health-check-lib.sh"

SERVICE_NAME="traefik"
HEALTH_URL="http://localhost:8080/ping"
DASHBOARD_URL="http://localhost:8080/dashboard/"

main() {
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_health "INFO" "  Traefik Health Check Starting (CRITICAL)"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Traefik should start quickly
    wait_for_stabilization 30

    # Check 1: Container running
    if ! container_running_check "$SERVICE_NAME"; then
        log_health "ERROR" "Traefik container not running - CRITICAL!"
        exit 1
    fi

    # Check 2: Ping endpoint (fast health check)
    if ! http_health_check "$HEALTH_URL" 200 5 5; then
        log_health "ERROR" "Traefik ping endpoint failed - CRITICAL!"
        exit 1
    fi

    # Check 3: Dashboard accessible
    if ! http_health_check "$DASHBOARD_URL" 200 10 3; then
        log_health "ERROR" "Traefik dashboard check failed"
        exit 1
    fi

    # Check 4: HTTP port listening
    if ! tcp_port_check "localhost" 80; then
        log_health "ERROR" "Traefik HTTP port (80) not listening"
        exit 1
    fi

    # Check 5: HTTPS port listening
    if ! tcp_port_check "localhost" 443; then
        log_health "ERROR" "Traefik HTTPS port (443) not listening"
        exit 1
    fi

    log_health "SUCCESS" "✅ All Traefik health checks passed - Gateway operational"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
}

main "$@"
```

#### Health Check 3: Prometheus

**File:** `scripts/health-checks/prometheus-health.sh`

```bash
#!/bin/bash
################################################################################
# Prometheus Health Check
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/health-check-lib.sh"

SERVICE_NAME="prometheus"
HEALTH_URL="http://localhost:9090/-/healthy"
READY_URL="http://localhost:9090/-/ready"

main() {
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_health "INFO" "  Prometheus Health Check Starting"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    wait_for_stabilization 45

    if ! container_running_check "$SERVICE_NAME"; then
        exit 1
    fi

    if ! http_health_check "$HEALTH_URL" 200 10 3; then
        exit 1
    fi

    if ! http_health_check "$READY_URL" 200 10 3; then
        exit 1
    fi

    log_health "SUCCESS" "✅ Prometheus health checks passed"
    exit 0
}

main "$@"
```

#### Health Check 4: Grafana

**File:** `scripts/health-checks/grafana-health.sh`

```bash
#!/bin/bash
################################################################################
# Grafana Health Check
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/health-check-lib.sh"

SERVICE_NAME="grafana"
HEALTH_URL="http://localhost:3000/api/health"

main() {
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_health "INFO" "  Grafana Health Check Starting"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    wait_for_stabilization 45

    if ! container_running_check "$SERVICE_NAME"; then
        exit 1
    fi

    if ! http_health_check "$HEALTH_URL" 200 10 3; then
        exit 1
    fi

    log_health "SUCCESS" "✅ Grafana health checks passed"
    exit 0
}

main "$@"
```

#### Health Check 5: Authelia

**File:** `scripts/health-checks/authelia-health.sh`

```bash
#!/bin/bash
################################################################################
# Authelia Health Check
# CRITICAL: Authentication gateway for entire homelab
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/health-check-lib.sh"

SERVICE_NAME="authelia"
HEALTH_URL="http://localhost:9091/api/health"

main() {
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_health "INFO" "  Authelia Health Check Starting (CRITICAL)"
    log_health "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    wait_for_stabilization 30

    if ! container_running_check "$SERVICE_NAME"; then
        log_health "ERROR" "Authelia container not running - CRITICAL!"
        exit 1
    fi

    if ! http_health_check "$HEALTH_URL" 200 10 5; then
        log_health "ERROR" "Authelia health endpoint failed - CRITICAL!"
        exit 1
    fi

    log_health "SUCCESS" "✅ Authelia health checks passed"
    exit 0
}

main "$@"
```

**Implementation Steps for Phase 1:**

```bash
# Create directory
mkdir -p ~/containers/scripts/health-checks

# Create library
nano ~/containers/scripts/health-checks/health-check-lib.sh
# Paste library code
chmod +x ~/containers/scripts/health-checks/health-check-lib.sh

# Create service-specific health checks
for service in jellyfin traefik prometheus grafana authelia; do
    nano ~/containers/scripts/health-checks/${service}-health.sh
    # Paste corresponding code
    chmod +x ~/containers/scripts/health-checks/${service}-health.sh
done

# Test each health check manually
~/containers/scripts/health-checks/jellyfin-health.sh
~/containers/scripts/health-checks/traefik-health.sh
~/containers/scripts/health-checks/prometheus-health.sh
~/containers/scripts/health-checks/grafana-health.sh
~/containers/scripts/health-checks/authelia-health.sh
```

**Acceptance Criteria for Session 1, Phase 1:**
- [ ] Health check library created and sourced correctly
- [ ] All 5 health check scripts created
- [ ] All health checks executable (`chmod +x`)
- [ ] Manual testing passes for all currently running services
- [ ] Health checks log clearly to stderr
- [ ] Exit codes correct (0 = healthy, 1 = unhealthy)

---

### Phase 1.3: Rollback Automation Script (1-2h)

**Objective:** Create automated rollback mechanism

**Deliverable: Central Rollback Script**

**File:** `scripts/auto-update-rollback.sh`

```bash
#!/bin/bash
################################################################################
# Auto-Update Rollback Script
# Automatically reverts to previous container image on health check failure
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
LOG_DIR="$HOME/containers/data/autoupdate-logs"
CONTEXT_DIR="$HOME/containers/.claude/context/data"
METRICS_FILE="$HOME/containers/data/backup-metrics/autoupdate-metrics.prom"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $*"

    case $level in
        INFO)    echo -e "${BLUE}$message${NC}" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}$message${NC}" | tee -a "$LOG_FILE" ;;
        WARNING) echo -e "${YELLOW}$message${NC}" | tee -a "$LOG_FILE" ;;
        ERROR)   echo -e "${RED}$message${NC}" | tee -a "$LOG_FILE" ;;
    esac
}

# Get previous working image
get_previous_image() {
    local container_name=$1

    log "INFO" "Looking for previous image for $container_name..."

    # Get current image
    local current_image=$(podman inspect "$container_name" -f '{{.Image}}' 2>/dev/null || echo "")

    if [[ -z "$current_image" ]]; then
        log "ERROR" "Could not determine current image"
        return 1
    fi

    log "INFO" "Current image ID: ${current_image:0:12}"

    # Get image history (sorted by creation date, newest first)
    local image_name=$(podman inspect "$container_name" -f '{{.Config.Image}}' 2>/dev/null || echo "")

    if [[ -z "$image_name" ]]; then
        log "ERROR" "Could not determine image name"
        return 1
    fi

    log "INFO" "Image name: $image_name"

    # List all images with this name, get second one (previous)
    local previous_image=$(podman images "$image_name" --format '{{.ID}}' | sed -n '2p')

    if [[ -z "$previous_image" ]]; then
        log "ERROR" "No previous image found - cannot rollback"
        log "ERROR" "This might be the first deployment or old images were pruned"
        return 1
    fi

    log "SUCCESS" "Found previous image: ${previous_image:0:12}"
    echo "$previous_image"
    return 0
}

# Perform rollback
rollback_container() {
    local container_name=$1
    local service_name="${container_name}.service"

    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INFO" "  AUTO-UPDATE ROLLBACK: $container_name"
    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get previous image
    local previous_image=$(get_previous_image "$container_name")
    if [[ $? -ne 0 || -z "$previous_image" ]]; then
        log "ERROR" "Failed to find previous image"
        return 1
    fi

    # Tag current (failing) image for investigation
    local current_image=$(podman inspect "$container_name" -f '{{.Image}}' 2>/dev/null)
    if [[ -n "$current_image" ]]; then
        local tag_name="failed-update-$(date +%Y%m%d-%H%M%S)"
        podman tag "$current_image" "$container_name:$tag_name" 2>/dev/null || true
        log "INFO" "Tagged failing image as: $container_name:$tag_name"
    fi

    # Stop service
    log "INFO" "Stopping service: $service_name"
    if ! systemctl --user stop "$service_name"; then
        log "ERROR" "Failed to stop service"
        return 1
    fi

    # Recreate container with previous image
    log "INFO" "Removing current container..."
    if ! podman rm "$container_name" 2>/dev/null; then
        log "WARNING" "Failed to remove container (may not exist)"
    fi

    log "INFO" "Getting container creation command..."

    # Read quadlet file to reconstruct container
    local quadlet_file="$HOME/.config/containers/systemd/${container_name}.container"

    if [[ ! -f "$quadlet_file" ]]; then
        log "ERROR" "Quadlet file not found: $quadlet_file"
        return 1
    fi

    # Extract image from quadlet, replace with previous
    local quadlet_image=$(grep "^Image=" "$quadlet_file" | cut -d= -f2)

    log "INFO" "Quadlet image reference: $quadlet_image"

    # Update Image= line to use previous image ID
    local temp_quadlet="/tmp/${container_name}.container.rollback"
    sed "s|^Image=.*|Image=$previous_image|" "$quadlet_file" > "$temp_quadlet"

    # Backup current quadlet
    cp "$quadlet_file" "${quadlet_file}.bak-$(date +%Y%m%d-%H%M%S)"

    # Install updated quadlet
    cp "$temp_quadlet" "$quadlet_file"
    rm "$temp_quadlet"

    log "INFO" "Updated quadlet to use previous image"

    # Reload systemd
    log "INFO" "Reloading systemd..."
    systemctl --user daemon-reload

    # Start service
    log "INFO" "Starting service with previous image..."
    if ! systemctl --user start "$service_name"; then
        log "ERROR" "Failed to start service with previous image!"
        return 1
    fi

    # Wait for service to start
    sleep 10

    # Verify service is running
    if systemctl --user is-active "$service_name" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Service started successfully with previous image"
    else
        log "ERROR" "Service failed to start even with previous image"
        return 1
    fi

    # Re-run health check
    local health_check_script="$HOME/containers/scripts/health-checks/${container_name}-health.sh"

    if [[ -f "$health_check_script" ]]; then
        log "INFO" "Running health check on rolled-back service..."

        if "$health_check_script"; then
            log "SUCCESS" "✅ Health check passed after rollback"
        else
            log "ERROR" "❌ Health check still failing after rollback - manual intervention required"
            return 1
        fi
    else
        log "WARNING" "No health check script found, skipping validation"
    fi

    log "SUCCESS" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "SUCCESS" "  ROLLBACK COMPLETED SUCCESSFULLY"
    log "SUCCESS" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return 0
}

# Log to Context Framework
log_to_context_framework() {
    local container_name=$1
    local rollback_status=$2

    if [[ ! -d "$CONTEXT_DIR" ]]; then
        log "WARNING" "Context Framework directory not found, skipping"
        return 0
    fi

    local issues_file="$CONTEXT_DIR/issues.json"

    if [[ ! -f "$issues_file" ]]; then
        log "WARNING" "issues.json not found, skipping context logging"
        return 0
    fi

    # Create issue entry
    local issue_id="ISS-AUTO-$(date +%Y%m%d%H%M%S)"
    local timestamp=$(date -Iseconds)

    # This is simplified - in production, use proper JSON manipulation
    log "INFO" "Logging incident to Context Framework: $issue_id"

    # Note: Actual implementation would use jq to properly update JSON
    # For now, just log the intent
    log "INFO" "Issue ID: $issue_id"
    log "INFO" "Service: $container_name"
    log "INFO" "Action: Auto-update rollback"
    log "INFO" "Status: $rollback_status"
}

# Export Prometheus metrics
export_metrics() {
    local container_name=$1
    local success=$2

    mkdir -p "$(dirname "$METRICS_FILE")"

    local timestamp=$(date +%s)
    local success_value=0
    [[ "$success" == "true" ]] && success_value=1

    {
        echo "# HELP autoupdate_rollback_count Number of auto-update rollbacks performed"
        echo "# TYPE autoupdate_rollback_count counter"
        echo "autoupdate_rollback_count{service=\"$container_name\"} 1"

        echo ""
        echo "# HELP autoupdate_rollback_success Whether rollback succeeded (1) or failed (0)"
        echo "# TYPE autoupdate_rollback_success gauge"
        echo "autoupdate_rollback_success{service=\"$container_name\"} $success_value"

        echo ""
        echo "# HELP autoupdate_rollback_last_timestamp Unix timestamp of last rollback"
        echo "# TYPE autoupdate_rollback_last_timestamp gauge"
        echo "autoupdate_rollback_last_timestamp{service=\"$container_name\"} $timestamp"

    } > "$METRICS_FILE.$$"

    mv "$METRICS_FILE.$$" "$METRICS_FILE"

    log "INFO" "Metrics exported to: $METRICS_FILE"
}

# Main execution
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <container-name>"
        echo "Example: $0 jellyfin"
        exit 1
    fi

    local container_name=$1
    local timestamp=$(date +%Y%m%d-%H%M%S)
    LOG_FILE="$LOG_DIR/rollback-${container_name}-${timestamp}.log"

    log "INFO" "Auto-update rollback initiated for: $container_name"
    log "INFO" "Log file: $LOG_FILE"

    # Perform rollback
    if rollback_container "$container_name"; then
        log "SUCCESS" "Rollback completed successfully"
        log_to_context_framework "$container_name" "success"
        export_metrics "$container_name" "true"
        exit 0
    else
        log "ERROR" "Rollback failed - manual intervention required"
        log_to_context_framework "$container_name" "failed"
        export_metrics "$container_name" "false"
        exit 1
    fi
}

main "$@"
```

**Implementation Steps for Phase 1.3:**

```bash
# Create rollback script
nano ~/containers/scripts/auto-update-rollback.sh
# Paste code above
chmod +x ~/containers/scripts/auto-update-rollback.sh

# Create log directory
mkdir -p ~/containers/data/autoupdate-logs

# Test rollback logic (dry-run - just inspect, don't execute)
# Review the script logic carefully before first use
```

**Acceptance Criteria for Session 1, Phase 1.3:**
- [ ] Rollback script created and executable
- [ ] Script can identify previous images
- [ ] Script logs comprehensively
- [ ] Metrics export logic in place
- [ ] Context Framework logging prepared

---

## Session 1 Summary

**Duration:** 3-4 hours

**Deliverables:**
- ✅ Health check library (`health-check-lib.sh`)
- ✅ 5 service-specific health checks (Jellyfin, Traefik, Prometheus, Grafana, Authelia)
- ✅ Central rollback script (`auto-update-rollback.sh`)
- ✅ Logging infrastructure
- ✅ Metrics export framework

**Testing:**
- [ ] All health checks run successfully on current services
- [ ] Health checks correctly detect healthy vs unhealthy states
- [ ] Rollback script logic reviewed and understood

**Next Session Preview:**
Session 2 will integrate these components into quadlets and add monitoring/alerting.

---

**Status:** Ready for CLI execution
**Branch:** Create new branch or use existing feature branch
**Questions:** Review scripts, test manually before proceeding to Session 2

---

## Session 2: Integration & Monitoring (2-3 hours)

### Phase 2.1: Quadlet Integration (45min - 1h)

**Objective:** Connect health checks to systemd service lifecycle

**Strategy:** Use `ExecStartPost` to run health checks after service starts. On failure, systemd will mark the service as failed, triggering our rollback mechanism.

#### Integration Pattern for Quadlets

**Example: Jellyfin Quadlet Update**

**File:** `~/.config/containers/systemd/jellyfin.container`

**Before:**
```ini
[Container]
Image=docker.io/jellyfin/jellyfin:latest
AutoUpdate=registry
Network=systemd-reverse_proxy.network
Volume=/home/patriark/containers/config/jellyfin:/config:Z
Volume=/mnt/btrfs-pool/subvol5-media:/media:Z

[Service]
Restart=always
TimeoutStartSec=900

[Install]
WantedBy=default.target
```

**After:**
```ini
[Container]
Image=docker.io/jellyfin/jellyfin:latest
AutoUpdate=registry
Network=systemd-reverse_proxy.network
Volume=/home/patriark/containers/config/jellyfin:/config:Z
Volume=/mnt/btrfs-pool/subvol5-media:/media:Z

[Service]
Restart=always
TimeoutStartSec=900

# Health check after start
ExecStartPost=/home/patriark/containers/scripts/health-checks/jellyfin-health.sh

# Rollback on health check failure
# Note: This won't auto-trigger from ExecStartPost failure
# We need a systemd unit override for that

[Install]
WantedBy=default.target
```

**Better Approach: Systemd Unit Override**

The above approach has a limitation: `ExecStartPost` failure doesn't trigger rollback automatically. We need a more sophisticated integration using systemd's failure handling.

**Create systemd service override:**

**File:** `~/.config/systemd/user/jellyfin.service.d/health-check.conf`

```ini
[Service]
# Run health check after start
ExecStartPost=/home/patriark/containers/scripts/health-checks/jellyfin-health.sh

# On health check failure, trigger rollback
# Note: This requires manual setup - systemd can't directly call scripts on failure
# Alternative: Use a systemd path unit to watch for failed health checks
```

**Even Better: Wrapper Script Approach**

Since systemd's failure handling is complex, let's use a wrapper script that combines health check + rollback:

**File:** `scripts/health-checks/jellyfin-health-wrapper.sh`

```bash
#!/bin/bash
################################################################################
# Health Check Wrapper with Auto-Rollback
# Runs health check, triggers rollback on failure
################################################################################

set -euo pipefail

SERVICE_NAME="jellyfin"
HEALTH_CHECK="$HOME/containers/scripts/health-checks/${SERVICE_NAME}-health.sh"
ROLLBACK_SCRIPT="$HOME/containers/scripts/auto-update-rollback.sh"

# Run health check
if "$HEALTH_CHECK"; then
    # Health check passed
    exit 0
else
    # Health check failed - trigger rollback
    echo "Health check failed for $SERVICE_NAME - triggering rollback..." >&2

    # Trigger rollback asynchronously (don't block systemd)
    nohup "$ROLLBACK_SCRIPT" "$SERVICE_NAME" > /dev/null 2>&1 &

    # Exit with failure to mark service as failed
    exit 1
fi
```

**Updated Quadlet with Wrapper:**

```ini
[Container]
Image=docker.io/jellyfin/jellyfin:latest
AutoUpdate=registry
Network=systemd-reverse_proxy.network
Volume=/home/patriark/containers/config/jellyfin:/config:Z
Volume=/mnt/btrfs-pool/subvol5-media:/media:Z

[Service]
Restart=always
TimeoutStartSec=900

# Health check wrapper (includes auto-rollback on failure)
ExecStartPost=/home/patriark/containers/scripts/health-checks/jellyfin-health-wrapper.sh

[Install]
WantedBy=default.target
```

**Implementation Steps for Phase 2.1:**

```bash
# Create health check wrappers for all critical services
cd ~/containers/scripts/health-checks/

for service in jellyfin traefik prometheus grafana authelia; do
    cat > ${service}-health-wrapper.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SERVICE_NAME="SERVICE_PLACEHOLDER"
HEALTH_CHECK="$HOME/containers/scripts/health-checks/${SERVICE_NAME}-health.sh"
ROLLBACK_SCRIPT="$HOME/containers/scripts/auto-update-rollback.sh"

if "$HEALTH_CHECK"; then
    exit 0
else
    echo "Health check failed for $SERVICE_NAME - triggering rollback..." >&2
    nohup "$ROLLBACK_SCRIPT" "$SERVICE_NAME" > /dev/null 2>&1 &
    exit 1
fi
EOF

    # Replace placeholder
    sed -i "s/SERVICE_PLACEHOLDER/$service/" ${service}-health-wrapper.sh

    # Make executable
    chmod +x ${service}-health-wrapper.sh
done

# Update quadlet files
cd ~/.config/containers/systemd/

for service in jellyfin traefik prometheus grafana authelia; do
    # Backup original
    cp ${service}.container ${service}.container.bak-$(date +%Y%m%d)

    # Add ExecStartPost to [Service] section
    # This is manual - edit each file individually
    nano ${service}.container

    # Add these lines to [Service] section:
    # ExecStartPost=/home/patriark/containers/scripts/health-checks/SERVICE-health-wrapper.sh
done

# Reload systemd
systemctl --user daemon-reload

# Restart services one at a time to test
systemctl --user restart jellyfin.service
# Watch logs to verify health check runs
journalctl --user -u jellyfin.service -f
```

**Acceptance Criteria for Phase 2.1:**
- [ ] Health check wrappers created for all 5 services
- [ ] Quadlets updated with `ExecStartPost` directives
- [ ] systemd daemon reloaded
- [ ] Test restart of one service confirms health check runs
- [ ] Wrapper successfully triggers rollback on simulated failure

---

### Phase 2.2: Prometheus Metrics & Alerts (1h)

**Objective:** Monitor auto-update health and rollback events

#### Prometheus Metrics Collection

**File:** `config/prometheus/prometheus.yml` (Update)

Add file-based service discovery for auto-update metrics:

```yaml
scrape_configs:
  # Existing scrape configs...

  # Auto-update metrics from file
  - job_name: 'autoupdate-metrics'
    scrape_interval: 60s
    file_sd_configs:
      - files:
          - '/home/patriark/containers/data/backup-metrics/autoupdate-metrics.prom'
```

**Note:** Our rollback script already exports metrics to `autoupdate-metrics.prom`. Prometheus will scrape this file.

**Better Alternative: Push to Pushgateway**

For one-time events like rollbacks, Pushgateway is more appropriate:

```bash
# Install Pushgateway (if not already)
podman run -d \
  --name pushgateway \
  --network systemd-monitoring.network \
  -p 9091:9091 \
  prom/pushgateway:latest
```

**Update Rollback Script to Push Metrics:**

Add to `scripts/auto-update-rollback.sh` (replace `export_metrics()` function):

```bash
# Export Prometheus metrics via Pushgateway
export_metrics() {
    local container_name=$1
    local success=$2

    local success_value=0
    [[ "$success" == "true" ]] && success_value=1

    # Push to Pushgateway
    cat <<EOF | curl --data-binary @- http://localhost:9091/metrics/job/autoupdate_rollback/instance/$container_name
# HELP autoupdate_rollback_count Number of auto-update rollbacks performed
# TYPE autoupdate_rollback_count counter
autoupdate_rollback_count{service="$container_name"} 1

# HELP autoupdate_rollback_success Whether rollback succeeded (1) or failed (0)
# TYPE autoupdate_rollback_success gauge
autoupdate_rollback_success{service="$container_name"} $success_value

# HELP autoupdate_rollback_last_timestamp Unix timestamp of last rollback
# TYPE autoupdate_rollback_last_timestamp gauge
autoupdate_rollback_last_timestamp{service="$container_name"} $(date +%s)
EOF

    log "INFO" "Metrics pushed to Pushgateway"
}
```

#### Prometheus Alert Rules

**File:** `config/prometheus/alerts/autoupdate.yml` (Create)

```yaml
groups:
  - name: autoupdate
    interval: 60s
    rules:
      # Alert on any rollback event
      - alert: AutoUpdateRollbackOccurred
        expr: changes(autoupdate_rollback_count[5m]) > 0
        for: 1m
        labels:
          severity: warning
          category: autoupdate
        annotations:
          summary: "Auto-update rollback occurred for {{ $labels.service }}"
          description: "Service {{ $labels.service }} had an auto-update that failed health checks and was rolled back."

      # Alert on rollback failure
      - alert: AutoUpdateRollbackFailed
        expr: autoupdate_rollback_success == 0
        for: 1m
        labels:
          severity: critical
          category: autoupdate
        annotations:
          summary: "Auto-update rollback FAILED for {{ $labels.service }}"
          description: "CRITICAL: Service {{ $labels.service }} rollback failed. Manual intervention required immediately."

      # Alert on repeated rollbacks (same service rolling back multiple times)
      - alert: AutoUpdateRepeatedRollbacks
        expr: changes(autoupdate_rollback_count{service=~".*"}[24h]) > 2
        for: 5m
        labels:
          severity: warning
          category: autoupdate
        annotations:
          summary: "Repeated auto-update rollbacks for {{ $labels.service }}"
          description: "Service {{ $labels.service }} has rolled back {{ $value }} times in 24h. Upstream may be unstable."
```

**Update Prometheus Configuration:**

**File:** `config/prometheus/prometheus.yml`

```yaml
# Add alert rules
rule_files:
  - '/etc/prometheus/alerts/*.yml'
```

**Reload Prometheus:**

```bash
# Reload config (if Prometheus supports it)
curl -X POST http://localhost:9090/-/reload

# Or restart service
systemctl --user restart prometheus.service
```

#### Alertmanager Route for Auto-Update Alerts

**File:** `config/alertmanager/alertmanager.yml` (Update)

Add routing for auto-update alerts:

```yaml
route:
  receiver: 'discord-general'
  group_by: ['alertname', 'service']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h

  routes:
    # Existing routes...

    # Auto-update rollback alerts
    - match:
        category: autoupdate
      receiver: 'discord-autoupdate'
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 6h

receivers:
  # Existing receivers...

  - name: 'discord-autoupdate'
    webhook_configs:
      - url: 'http://alertmanager-discord:9094'
        send_resolved: true
```

**Implementation Steps for Phase 2.2:**

```bash
# Create alert rules file
mkdir -p ~/containers/config/prometheus/alerts/
nano ~/containers/config/prometheus/alerts/autoupdate.yml
# Paste alert rules

# Update Prometheus config to include alerts
nano ~/containers/config/prometheus/prometheus.yml
# Add rule_files section

# Update rollback script with Pushgateway integration
nano ~/containers/scripts/auto-update-rollback.sh
# Update export_metrics() function

# Restart Prometheus
systemctl --user restart prometheus.service

# Test alert rules
curl http://localhost:9090/api/v1/rules | jq
```

**Acceptance Criteria for Phase 2.2:**
- [ ] Prometheus alert rules created and loaded
- [ ] Rollback script exports metrics correctly
- [ ] Test rollback generates metrics visible in Prometheus
- [ ] Alerts trigger in Alertmanager
- [ ] Discord notifications received for test rollback

---

### Phase 2.3: Grafana Dashboard (30min)

**Objective:** Visualize auto-update health and rollback history

**File:** `config/grafana/provisioning/dashboards/autoupdate-safety.json`

**Dashboard Panels:**

1. **Rollback Events Timeline** - Time series showing when rollbacks occurred
2. **Rollback Success Rate** - Gauge showing success/failure ratio
3. **Services by Rollback Count** - Bar chart of which services roll back most
4. **Last Rollback Status** - Table showing current status of all services
5. **Alert Status** - Panel showing active auto-update alerts

**Implementation:**

```bash
# Create dashboard in Grafana UI
# Navigate to: http://localhost:3000
# Create > Dashboard > Add visualization

# Panel 1: Rollback Events
# Query: increase(autoupdate_rollback_count[24h])
# Visualization: Time series

# Panel 2: Success Rate
# Query: avg_over_time(autoupdate_rollback_success[24h])
# Visualization: Gauge (0-1 range)

# Panel 3: Services by Rollback Count
# Query: sum by (service) (increase(autoupdate_rollback_count[7d]))
# Visualization: Bar chart

# Save dashboard
# Export JSON: Dashboard settings > JSON Model
# Save to: config/grafana/provisioning/dashboards/autoupdate-safety.json
```

**Acceptance Criteria for Phase 2.3:**
- [ ] Grafana dashboard created with 3+ panels
- [ ] Dashboard shows historical rollback data
- [ ] Dashboard auto-refreshes every 5 minutes
- [ ] Dashboard provisioned via JSON (survives Grafana restart)

---

## Session 2 Summary

**Duration:** 2-3 hours

**Deliverables:**
- ✅ Health check wrappers with auto-rollback triggers
- ✅ Quadlets updated with ExecStartPost directives
- ✅ Prometheus alert rules for rollback events
- ✅ Alertmanager Discord routing for auto-update alerts
- ✅ Grafana dashboard for auto-update monitoring
- ✅ Pushgateway integration for one-time metrics

**Testing Checklist:**
- [ ] Simulate failed update by manually changing image to bad tag
- [ ] Verify health check detects failure
- [ ] Verify rollback script executes automatically
- [ ] Verify service returns to working state
- [ ] Verify Prometheus metrics exported
- [ ] Verify alert fires and Discord notification received
- [ ] Verify Grafana dashboard shows event

**Next Steps:**
- Optionally: Session 3 for gradual rollout and additional refinements
- Monitor system for 1-2 weeks to validate stability
- Document lessons learned

---

## Session 3: Testing & Refinement (1-2 hours) - OPTIONAL

### Phase 3.1: Comprehensive Testing

**Controlled Failure Test:**

```bash
# Test 1: Jellyfin bad image
# 1. Find current Jellyfin image
podman inspect jellyfin -f '{{.Config.Image}}'

# 2. Stop Jellyfin
systemctl --user stop jellyfin.service

# 3. Update quadlet to use a known-bad tag
nano ~/.config/containers/systemd/jellyfin.container
# Change Image= to: docker.io/jellyfin/jellyfin:nonexistent-tag

# 4. Reload and start
systemctl --user daemon-reload
systemctl --user start jellyfin.service

# 5. Watch logs - should see:
# - Health check failure
# - Rollback trigger
# - Service restart with previous image
# - Health check success

journalctl --user -u jellyfin.service -f
```

**Expected Behavior:**
```
[timestamp] Starting jellyfin.service...
[timestamp] Container created with image: nonexistent-tag
[timestamp] Container failed to start
[timestamp] ExecStartPost: Running health check...
[timestamp] Health check FAILED
[timestamp] Triggering rollback...
[timestamp] Rollback: Found previous image: abc123def456
[timestamp] Rollback: Updating quadlet...
[timestamp] Rollback: Restarting service...
[timestamp] Health check SUCCESS
[timestamp] Rollback completed
```

### Phase 3.2: Documentation

**Create runbook:**

**File:** `docs/20-operations/runbooks/auto-update-rollback.md`

```markdown
# Auto-Update Rollback Runbook

## Overview
Automated rollback system for failed container updates.

## How It Works
1. AutoUpdate pulls new image
2. systemd restarts service
3. Health check runs (ExecStartPost)
4. If health check fails → rollback triggered
5. Service reverted to previous image
6. Alert sent to Discord

## Manual Rollback

If automatic rollback fails:

\```bash
# 1. Identify previous image
podman images jellyfin/jellyfin

# 2. Manually run rollback script
~/containers/scripts/auto-update-rollback.sh jellyfin

# 3. Verify service health
systemctl --user status jellyfin.service
~/containers/scripts/health-checks/jellyfin-health.sh
\```

## Troubleshooting

**Rollback script can't find previous image:**
- Check: `podman images <service>` - need at least 2 images
- Cause: Old images were pruned by disk cleanup
- Solution: Temporarily disable auto-prune

**Health check false positive (service healthy but check fails):**
- Check health check logs
- Tune wait time or retry logic in health check script

## Metrics

- Prometheus: `autoupdate_rollback_count`, `autoupdate_rollback_success`
- Grafana: Auto-Update Safety dashboard
- Logs: `~/containers/data/autoupdate-logs/`
```

**Acceptance Criteria for Session 3:**
- [ ] Successful controlled failure test for at least 2 services
- [ ] Rollback completes within 5 minutes
- [ ] Service returns to healthy state
- [ ] Runbook documented
- [ ] Team trained on how system works

---

## Total Project Summary

### Time Investment
- **Session 1:** 3-4 hours (Health checks + rollback script)
- **Session 2:** 2-3 hours (Integration + monitoring)
- **Session 3:** 1-2 hours (Testing + docs) - OPTIONAL

**Total:** 6-9 hours

### Risk Mitigation Achieved

**Before:**
- ❌ Bad auto-update → Service down until manual intervention
- ❌ Discovery delayed (only when you try to use service)
- ❌ No historical data on update failures
- ❌ Manual rollback process (30-60 minutes)

**After:**
- ✅ Bad auto-update → Automatic rollback within 2-3 minutes
- ✅ Immediate Discord notification
- ✅ Service stays available (minimal downtime)
- ✅ Full metrics and historical tracking
- ✅ Context Framework logs every incident

### Maintenance Requirements

**Ongoing:**
- Monitor Grafana dashboard weekly
- Review rollback logs monthly
- Tune health check wait times as needed
- Ensure disk cleanup doesn't prune all old images

**Updates:**
- Add health checks for new services as deployed
- Update alert thresholds if needed

---

## Success Metrics

**System is working if:**
1. No service stays down >5 minutes after bad update
2. All rollback events visible in Grafana
3. Discord alerts received within 2 minutes of rollback
4. Health checks correctly identify healthy vs unhealthy services
5. Zero false positives (services incorrectly marked unhealthy)

---

**Status:** Complete implementation roadmap - ready for CLI execution
**Next:** Execute Session 1, test thoroughly, then proceed to Session 2
