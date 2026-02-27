#!/bin/bash
#
# Diagnostic script to understand redis-immich health check validation issue
#

echo "=== Redis-Immich Health Check Diagnostics ==="
echo ""

echo "1. Container Status:"
podman ps --filter "name=redis-immich" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"
echo ""

echo "2. Health Check Configuration:"
podman inspect redis-immich --format '{{json .Config.Healthcheck}}' | jq '.'
echo ""

echo "3. Health Check Command:"
podman inspect redis-immich --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}none{{end}}'
echo ""

echo "4. Current Health Status:"
podman inspect redis-immich --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
echo ""

echo "5. Health Check Logs (last failure):"
podman inspect redis-immich --format '{{json .State.Health.Log}}' | jq '.[-1]' 2>/dev/null || echo "No health check logs"
echo ""

echo "6. Testing binary detection:"
health_cmd=$(podman inspect redis-immich --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}none{{end}}' 2>/dev/null)
echo "Health command JSON: $health_cmd"

if [ "$health_cmd" != "none" ]; then
    cmd_type=$(echo "$health_cmd" | jq -r '.[0]' 2>/dev/null || echo "unknown")
    echo "Command type: $cmd_type"

    if [ "$cmd_type" = "CMD-SHELL" ]; then
        full_cmd=$(echo "$health_cmd" | jq -r '.[1]' 2>/dev/null || echo "")
        echo "Full command: $full_cmd"

        cmd_binary=$(echo "$full_cmd" | grep -oE '(curl|wget|nc|python|python3|node|java|psql|redis-cli)' | head -1 || echo "")
        echo "Detected binary: $cmd_binary"
    fi
fi
echo ""

echo "7. Testing podman exec with timeout:"
echo -n "   Attempting: timeout --kill-after=1s 2s podman exec redis-immich which redis-cli... "
if timeout --kill-after=1s 2s podman exec redis-immich which redis-cli </dev/null &>/dev/null; then
    echo "SUCCESS (exit $?)"
else
    exit_code=$?
    echo "FAILED (exit $exit_code)"
    if [ $exit_code -eq 124 ]; then
        echo "   -> Timeout (SIGTERM)"
    elif [ $exit_code -eq 137 ]; then
        echo "   -> Timeout (SIGKILL)"
    fi
fi
echo ""

echo "8. Testing direct exec (no timeout):"
echo -n "   Attempting: podman exec redis-immich which redis-cli... "
timeout 5 sh -c 'podman exec redis-immich which redis-cli </dev/null' &>/dev/null && echo "SUCCESS" || echo "FAILED (exit $?)"
echo ""

echo "9. Container responsiveness test:"
echo -n "   Attempting: podman exec redis-immich echo test... "
if timeout --kill-after=1s 2s podman exec redis-immich echo test </dev/null &>/dev/null; then
    echo "SUCCESS - container IS responsive"
else
    echo "FAILED - container NOT responding to exec"
fi
echo ""

echo "10. List of services with health checks (in order):"
podman ps --format '{{.Names}}' | while read name; do
    has_health=$(podman inspect "$name" --format '{{if .Config.Healthcheck}}yes{{else}}no{{end}}' 2>/dev/null)
    if [ "$has_health" = "yes" ]; then
        health_status=$(podman inspect "$name" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null)
        echo "   $name: $health_status"
    fi
done
echo ""

echo "=== Diagnostics Complete ==="
