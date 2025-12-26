#!/usr/bin/env python3
"""
Remediation Webhook Handler
Phase 4: Alert-Driven Remediation

Receives Alertmanager webhooks and triggers appropriate remediation playbooks.
Implements rate limiting, idempotency, circuit breaker, and comprehensive logging.

Usage:
    ./remediation-webhook-handler.py [--config webhook-routing.yml] [--port 9096]

Architecture:
    Alertmanager → POST /webhook → Parse → Route → Execute → Log → Response
"""

import argparse
import hashlib
import json
import logging
import os
import re
import subprocess
import sys
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import yaml

# Constants
SCRIPT_DIR = Path(__file__).parent.resolve()
REMEDIATION_DIR = SCRIPT_DIR.parent
DEFAULT_CONFIG = REMEDIATION_DIR / "webhook-routing.yml"
DEFAULT_PORT = 9096
DEFAULT_BIND = "127.0.0.1"

# Global state
config: Dict = {}
execution_history: deque = deque(maxlen=1000)
rate_limit_tracker: Dict[str, List[float]] = defaultdict(list)
idempotency_tracker: Dict[str, float] = {}
circuit_breaker_state: Dict[str, Dict] = {}
oscillation_detector: Dict[str, List[float]] = defaultdict(list)


class RemediationWebhookHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Alertmanager webhooks."""

    def log_message(self, format, *args):
        """Override to use custom logging."""
        logging.info(f"{self.address_string()} - {format % args}")

    def do_GET(self):
        """Handle GET requests (health check endpoint)."""
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        """Handle POST requests (webhook endpoint) with token authentication."""
        # Parse URL for token
        from urllib.parse import urlparse, parse_qs

        parsed_url = urlparse(self.path)
        if parsed_url.path != "/webhook":
            self.send_error(404, "Not Found")
            return

        # Validate token
        query_params = parse_qs(parsed_url.query)
        provided_token = query_params.get('token', [''])[0]

        # Load expected token from environment variable (preferred) or config file (fallback)
        # Environment variable provides better security (not committed to Git)
        expected_token = os.environ.get('WEBHOOK_AUTH_TOKEN', '')
        if not expected_token:
            # Fallback to config file (legacy, less secure)
            expected_token = config.get('config', {}).get('security', {}).get('auth_token', '')
            if expected_token and expected_token != 'REPLACE_WITH_ENV_VAR':
                logging.warning("Using auth_token from config file - consider migrating to environment variable")

        if not expected_token or expected_token == 'REPLACE_WITH_ENV_VAR':
            logging.critical("No auth_token configured - refusing to start without authentication")
            logging.critical("Set WEBHOOK_AUTH_TOKEN environment variable or configure in webhook-routing.yml")
            self.send_error(503, "Service Unavailable - Authentication not configured")
            return
        elif not provided_token or provided_token != expected_token:
            self.send_error(401, "Unauthorized")
            logging.warning(f"Invalid/missing token from {self.address_string()}")
            return

        try:
            # Read and parse payload
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            payload = json.loads(body.decode("utf-8"))

            logging.info(f"Received webhook: {len(payload.get('alerts', []))} alerts")

            # Process each alert in the payload
            results = []
            for alert in payload.get("alerts", []):
                result = process_alert(alert)
                results.append(result)

            # Send response
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            response = {
                "status": "processed",
                "alerts_received": len(payload.get("alerts", [])),
                "results": results,
            }
            self.wfile.write(json.dumps(response).encode())

        except json.JSONDecodeError as e:
            logging.error(f"Invalid JSON payload: {e}")
            self.send_error(400, "Invalid JSON")
        except Exception as e:
            logging.error(f"Error processing webhook: {e}", exc_info=True)
            self.send_error(500, "Internal Server Error")


def load_config(config_path: Path) -> Dict:
    """Load webhook routing configuration from YAML file."""
    if not config_path.exists():
        logging.error(f"Config file not found: {config_path}")
        sys.exit(1)

    with open(config_path) as f:
        cfg = yaml.safe_load(f)

    logging.info(f"Loaded config: {len(cfg.get('routes', []))} routes")
    return cfg


def get_alert_id(alert: Dict, key_fields: List[str]) -> str:
    """Generate unique identifier for alert (for idempotency)."""
    values = []
    for field in key_fields:
        if field == "alertname":
            values.append(alert.get("labels", {}).get("alertname", "unknown"))
        elif field in alert.get("labels", {}):
            values.append(alert["labels"][field])

    id_string = "|".join(values)
    return hashlib.sha256(id_string.encode()).hexdigest()[:16]


def check_idempotency(alert_id: str, window_minutes: int) -> bool:
    """Check if alert was recently processed (prevent duplicates)."""
    if alert_id in idempotency_tracker:
        last_execution = idempotency_tracker[alert_id]
        elapsed = time.time() - last_execution
        if elapsed < window_minutes * 60:
            logging.info(
                f"Idempotency check: Alert {alert_id} processed {elapsed:.0f}s ago (within {window_minutes}m window)"
            )
            return False  # Already processed recently

    # Update tracker
    idempotency_tracker[alert_id] = time.time()
    return True  # OK to process


def check_rate_limit(
    alert_name: str, max_per_hour: int, max_per_alert: int, cooldown_minutes: int
) -> Tuple[bool, str]:
    """Check if rate limits allow execution."""
    now = time.time()
    one_hour_ago = now - 3600
    cooldown_threshold = now - (cooldown_minutes * 60)

    # Clean old entries
    rate_limit_tracker[alert_name] = [
        t for t in rate_limit_tracker[alert_name] if t > one_hour_ago
    ]
    rate_limit_tracker["_global"] = [
        t for t in rate_limit_tracker.get("_global", []) if t > one_hour_ago
    ]

    # Check global rate limit
    global_count = len(rate_limit_tracker.get("_global", []))
    if global_count >= max_per_hour:
        return False, f"Global rate limit exceeded ({global_count}/{max_per_hour} per hour)"

    # Check per-alert rate limit
    alert_count = len(rate_limit_tracker[alert_name])
    if alert_count >= max_per_alert:
        return False, f"Alert rate limit exceeded ({alert_count}/{max_per_alert} per hour)"

    # Check cooldown (most recent execution)
    if rate_limit_tracker[alert_name]:
        last_execution = rate_limit_tracker[alert_name][-1]
        if last_execution > cooldown_threshold:
            elapsed = now - last_execution
            return False, f"Cooldown active ({elapsed:.0f}s < {cooldown_minutes}m)"

    # Update tracker
    rate_limit_tracker[alert_name].append(now)
    rate_limit_tracker["_global"].append(now)

    return True, "OK"


def check_circuit_breaker(playbook: str, threshold: int, timeout_minutes: int) -> Tuple[bool, str]:
    """Check circuit breaker state for playbook."""
    if playbook not in circuit_breaker_state:
        circuit_breaker_state[playbook] = {
            "state": "closed",
            "consecutive_failures": 0,
            "last_failure": None,
        }

    breaker = circuit_breaker_state[playbook]

    # Check if circuit is open
    if breaker["state"] == "open":
        if breaker["last_failure"]:
            elapsed = time.time() - breaker["last_failure"]
            if elapsed > timeout_minutes * 60:
                # Reset circuit breaker
                logging.info(
                    f"Circuit breaker for {playbook} reset after {elapsed:.0f}s"
                )
                breaker["state"] = "closed"
                breaker["consecutive_failures"] = 0
                return True, "Circuit closed (reset after timeout)"
            else:
                remaining = (timeout_minutes * 60) - elapsed
                return False, f"Circuit open ({remaining:.0f}s remaining until reset)"

    return True, "Circuit closed"


def record_circuit_breaker_outcome(playbook: str, success: bool, threshold: int):
    """Update circuit breaker state based on execution outcome."""
    if playbook not in circuit_breaker_state:
        circuit_breaker_state[playbook] = {
            "state": "closed",
            "consecutive_failures": 0,
            "last_failure": None,
        }

    breaker = circuit_breaker_state[playbook]

    if success:
        # Reset on success
        breaker["consecutive_failures"] = 0
        if breaker["state"] == "open":
            logging.info(f"Circuit breaker for {playbook} recovered")
            breaker["state"] = "closed"
    else:
        # Increment failures
        breaker["consecutive_failures"] += 1
        breaker["last_failure"] = time.time()

        if breaker["consecutive_failures"] >= threshold:
            logging.warning(
                f"Circuit breaker opened for {playbook} ({breaker['consecutive_failures']} consecutive failures)"
            )
            breaker["state"] = "open"


def strip_ansi_codes(text: str) -> str:
    """
    Remove ANSI escape sequences from text.

    ANSI codes are used for terminal colors/formatting (e.g., \\033[0;34m for blue text).
    These codes make logs unreadable in Loki/Grafana, rendering as literal text like:
        ^[[0;34m━━━━━━━━━━^[[0m

    This function strips all ANSI escape sequences, leaving only the actual text content.

    Args:
        text: Input text potentially containing ANSI escape codes

    Returns:
        Text with all ANSI escape sequences removed

    Example:
        Input:  "\\033[0;34mDEBUG\\033[0m: Success"
        Output: "DEBUG: Success"
    """
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def detect_oscillation(alert_name: str, playbook: str, threshold: int = 3, window_minutes: int = 15) -> bool:
    """Detect if same alert+playbook is oscillating."""
    key = f"{alert_name}:{playbook}"
    now = time.time()
    window_start = now - (window_minutes * 60)

    # Clean old entries
    oscillation_detector[key] = [t for t in oscillation_detector[key] if t > window_start]

    # Check threshold
    if len(oscillation_detector[key]) >= threshold:
        logging.warning(f"Oscillation detected: {alert_name} → {playbook} ({len(oscillation_detector[key])} in {window_minutes}m)")
        return True

    oscillation_detector[key].append(now)
    return False


def substitute_parameters(param_template: str, alert: Dict) -> str:
    """Substitute {{.Labels.foo}} placeholders in parameters."""
    result = param_template

    # Replace {{.Labels.name}} with alert label value
    labels = alert.get("labels", {})
    for key, value in labels.items():
        placeholder = f"{{{{.Labels.{key}}}}}"
        result = result.replace(placeholder, str(value))

    return result


def find_route(alert_name: str, routes: List[Dict]) -> Optional[Dict]:
    """Find matching route for alert name."""
    for route in routes:
        if route.get("alert") == alert_name:
            return route
    return None


def execute_playbook(
    playbook: str, parameters: Optional[str] = None
) -> Tuple[bool, str, str]:
    """Execute remediation playbook via apply-remediation.sh."""
    cmd = [str(SCRIPT_DIR / "apply-remediation.sh"), "--playbook", playbook]

    if parameters:
        cmd.extend(parameters.split())

    logging.info(f"Executing: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            cwd=SCRIPT_DIR,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minute timeout
        )

        success = result.returncode == 0
        return success, result.stdout, result.stderr

    except subprocess.TimeoutExpired:
        return False, "", "Execution timeout (5 minutes)"
    except Exception as e:
        return False, "", str(e)


def process_alert(alert: Dict) -> Dict:
    """Process single alert and execute remediation if appropriate."""
    alert_name = alert.get("labels", {}).get("alertname", "unknown")
    status = alert.get("status", "unknown")

    logging.info(f"Processing alert: {alert_name} (status: {status})")

    # Only process firing alerts (ignore resolved)
    if status != "firing":
        logging.info(f"Skipping {status} alert: {alert_name}")
        return {
            "alert": alert_name,
            "action": "skipped",
            "reason": f"Alert status is {status}, not firing",
        }

    # Find routing rule
    routes = config.get("routes", [])
    route = find_route(alert_name, routes)

    if not route:
        logging.info(f"No route configured for alert: {alert_name}")
        return {"alert": alert_name, "action": "no_route", "reason": "No matching route"}

    playbook = route.get("playbook")
    if playbook == "none":
        logging.info(f"Alert {alert_name} configured as alert-only (no remediation)")
        return {
            "alert": alert_name,
            "action": "alert_only",
            "reason": "Configured as alert-only",
        }

    # Check service overrides
    service_overrides = config.get("service_overrides", [])
    service_name = alert.get("labels", {}).get("service", "")
    if service_name in service_overrides:
        logging.warning(
            f"Service {service_name} in override list - skipping remediation"
        )
        return {
            "alert": alert_name,
            "action": "blocked",
            "reason": f"Service {service_name} in override list",
        }

    # Idempotency check
    cfg_global = config.get("config", {})
    idempotency_cfg = cfg_global.get("idempotency", {})
    alert_id = get_alert_id(alert, idempotency_cfg.get("key_fields", ["alertname"]))

    if not check_idempotency(alert_id, idempotency_cfg.get("window_minutes", 5)):
        return {
            "alert": alert_name,
            "action": "duplicate",
            "reason": "Already processed recently (idempotency)",
        }

    # Rate limiting check
    rate_limit_cfg = cfg_global.get("rate_limit", {})
    rate_ok, rate_reason = check_rate_limit(
        alert_name,
        rate_limit_cfg.get("max_executions_per_hour", 5),
        rate_limit_cfg.get("max_executions_per_alert", 3),
        rate_limit_cfg.get("cooldown_minutes", 15),
    )

    if not rate_ok:
        logging.warning(f"Rate limit check failed: {rate_reason}")
        return {"alert": alert_name, "action": "rate_limited", "reason": rate_reason}

    # Circuit breaker check
    circuit_cfg = cfg_global.get("circuit_breaker", {})
    circuit_ok, circuit_reason = check_circuit_breaker(
        playbook,
        circuit_cfg.get("failure_threshold", 3),
        circuit_cfg.get("reset_timeout_minutes", 30),
    )

    if not circuit_ok:
        logging.warning(f"Circuit breaker check failed: {circuit_reason}")
        return {
            "alert": alert_name,
            "action": "circuit_open",
            "reason": circuit_reason,
        }

    # Oscillation check
    if detect_oscillation(alert_name, playbook, threshold=3, window_minutes=15):
        logging.error(f"Blocked oscillating remediation: {alert_name} → {playbook}")
        return {
            "alert": alert_name,
            "action": "blocked_oscillation",
            "reason": "3+ triggers in 15min"
        }

    # Confidence check
    confidence = route.get("confidence", 0)
    requires_confirmation = route.get("requires_confirmation", False)

    if confidence < 90 or requires_confirmation:
        logging.info(
            f"Low confidence ({confidence}%) or requires confirmation - escalating"
        )
        return {
            "alert": alert_name,
            "action": "escalate",
            "reason": f"Confidence {confidence}% (threshold: 90%) or manual confirmation required",
            "playbook": playbook,
        }

    # Execute playbook
    parameter_template = route.get("parameter", "")
    parameters = substitute_parameters(parameter_template, alert) if parameter_template else None

    logging.info(
        f"Executing remediation: playbook={playbook}, confidence={confidence}%, params={parameters}"
    )

    success, stdout, stderr = execute_playbook(playbook, parameters)

    # Record circuit breaker outcome
    record_circuit_breaker_outcome(playbook, success, circuit_cfg.get("failure_threshold", 3))

    # Log execution (strip ANSI codes for clean Loki output)
    execution_record = {
        "timestamp": time.time(),
        "alert": alert_name,
        "playbook": playbook,
        "parameters": parameters,
        "success": success,
        "confidence": confidence,
        "stdout": strip_ansi_codes(stdout[:500]),  # Strip ANSI, truncate to prevent huge logs
        "stderr": strip_ansi_codes(stderr[:500]),  # Strip ANSI, truncate to prevent huge logs
    }
    execution_history.append(execution_record)

    # Log to decision log (append to jsonl file)
    try:
        decision_log_path = Path(cfg_global.get("logging", {}).get("decision_log", ""))
        if decision_log_path:
            with open(decision_log_path, "a") as f:
                f.write(json.dumps(execution_record) + "\n")
    except Exception as e:
        logging.error(f"Failed to write decision log: {e}")

    if success:
        logging.info(f"Remediation succeeded: {alert_name} → {playbook}")
        return {
            "alert": alert_name,
            "action": "executed",
            "playbook": playbook,
            "result": "success",
        }
    else:
        logging.error(f"Remediation failed: {alert_name} → {playbook}")

        # Send Discord notification on failure
        try:
            send_failure_notification_discord(alert_name, playbook, stderr[:200])
        except Exception as e:
            logging.error(f"Discord failure notification error: {e}")

        return {
            "alert": alert_name,
            "action": "executed",
            "playbook": playbook,
            "result": "failure",
            "error": stderr[:200],
        }


def send_failure_notification_discord(alert_name: str, playbook: str, error_msg: str):
    """Send Discord notification when remediation fails."""
    import requests

    # Get Discord webhook URL from alert-discord-relay container
    discord_webhook = None
    try:
        result = subprocess.run(
            ["podman", "exec", "alert-discord-relay", "env"],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.split('\n'):
            if line.startswith("DISCORD_WEBHOOK_URL="):
                discord_webhook = line.split('=', 1)[1].strip()
                break
    except Exception as e:
        logging.error(f"Failed to get Discord webhook: {e}")
        return

    if not discord_webhook:
        logging.warning("Discord webhook URL not available")
        return

    # Build Discord embed
    embed = {
        "embeds": [{
            "title": "🚨 Remediation Failure",
            "description": f"Automatic remediation failed for alert **{alert_name}**",
            "color": 15158332,  # Red
            "fields": [
                {"name": "Alert", "value": alert_name, "inline": True},
                {"name": "Playbook", "value": playbook, "inline": True},
                {"name": "Error", "value": f"```\n{error_msg[:500]}\n```", "inline": False}
            ],
            "footer": {"text": "Remediation Webhook Handler"},
            "timestamp": datetime.utcnow().isoformat()
        }]
    }

    # Send to Discord
    try:
        response = requests.post(discord_webhook, json=embed, timeout=10)
        if response.status_code in [200, 204]:
            logging.info("Discord failure notification sent")
        else:
            logging.error(f"Discord notification failed: {response.status_code}")
    except Exception as e:
        logging.error(f"Failed to send Discord notification: {e}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Remediation Webhook Handler")
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"Path to routing config (default: {DEFAULT_CONFIG})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"Port to listen on (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--bind",
        default=DEFAULT_BIND,
        help=f"Address to bind to (default: {DEFAULT_BIND})",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level",
    )

    args = parser.parse_args()

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[
            logging.StreamHandler(sys.stdout),
        ],
    )

    # Load configuration
    global config
    config = load_config(args.config)

    # Start HTTP server
    server_address = (args.bind, args.port)
    httpd = HTTPServer(server_address, RemediationWebhookHandler)

    logging.info(f"Starting webhook handler on {args.bind}:{args.port}")
    logging.info(f"Health check: http://{args.bind}:{args.port}/health")
    logging.info(f"Webhook endpoint: http://{args.bind}:{args.port}/webhook")
    logging.info(f"Loaded {len(config.get('routes', []))} routing rules")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logging.info("Shutting down webhook handler")
        httpd.shutdown()


if __name__ == "__main__":
    main()
