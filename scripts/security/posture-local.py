#!/usr/bin/env python3
"""
posture-local.py — Internal-plane security posture intel for fedora-htpc.

Active gap-finder run from inside the LAN. Looks at the things external probes
cannot see: bind surfaces, container egress reality, Traefik middleware chain
completeness, CrowdSec/Loki pipeline liveness, cert/ACL/SELinux hygiene,
config drift, and journal anomalies.

Output: one JSON file per run at
    data/security-posture/local/<UTC timestamp>.json

The output is designed to be ingested by a fresh Claude Code session that
synthesises a hardening plan from one or more runs. Fields:
    meta       — vantage, timestamp, host, git HEAD, tool versions
    findings   — one entry per observation, with severity and evidence
    raw        — structured dumps (listeners, middleware graph, etc.)

Findings schema (per entry):
    id            — stable short ID, e.g., LBIND-0001
    category      — bind | egress | chain | crowdsec | loki | cert | auth |
                    container | firewall | drift | journal | adr
    severity      — info | low | medium | high | critical
    title         — one-line human summary
    evidence      — list of raw strings (command output fragments)
    adr_refs      — list of ADR IDs this finding bears on
    hint          — short remediation pointer (no auto-fix)

Philosophy: gather, do not interpret. Severity is heuristic; the
interpretation is done by the consuming Claude session.

Usage:
    ./scripts/security/posture-local.py                  # full run
    ./scripts/security/posture-local.py --pretty         # also print to stdout
    ./scripts/security/posture-local.py --category chain # single category

Exit codes:
    0  run completed (findings may exist)
    2  run aborted due to environment (not in repo, podman unavailable, ...)
    3  script-internal error

Status: ACTIVE
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shlex
import socket
import ssl
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
REPORT_DIR = REPO_ROOT / "data" / "security-posture" / "local"
QUADLETS = REPO_ROOT / "quadlets"
DYNAMIC = REPO_ROOT / "config" / "traefik" / "dynamic"

EXPECTED_WAN_PORTS = {80, 443, 8096, 7359}
EXPECTED_LAN_LISTEN_IPS = {"192.168.1.70", "127.0.0.1", "::1", "0.0.0.0"}
EXPECTED_INTERNAL_NETWORKS = {
    "auth_services",
    "gathio",
    "home_automation",
    "mail",
    "media_services",
    "monitoring",
    "nextcloud",
    "photos",
    "syslog",
}
# CrowdSec's local whitelist absorbs these; documented in acquis notes
LAN_CIDRS = ("192.168.1.", "192.168.100.", "10.89.")


# ---------------------------------------------------------------------------
# Utility layer
# ---------------------------------------------------------------------------


class FindingStore:
    def __init__(self) -> None:
        self._items: list[dict[str, Any]] = []
        self._counters: dict[str, int] = {}

    def add(
        self,
        category: str,
        severity: str,
        title: str,
        evidence: Iterable[str] | str = (),
        adr_refs: Iterable[str] = (),
        hint: str = "",
        prefix: str | None = None,
    ) -> None:
        prefix = prefix or category[:5].upper()
        self._counters[prefix] = self._counters.get(prefix, 0) + 1
        fid = f"L{prefix}-{self._counters[prefix]:04d}"
        if isinstance(evidence, str):
            evidence = [evidence]
        self._items.append(
            {
                "id": fid,
                "category": category,
                "severity": severity,
                "title": title,
                "evidence": [e for e in evidence if e],
                "adr_refs": list(adr_refs),
                "hint": hint,
            }
        )

    def all(self) -> list[dict[str, Any]]:
        return list(self._items)


def run(cmd: list[str] | str, timeout: int = 15) -> tuple[int, str, str]:
    """Run a command, return (rc, stdout, stderr). Never raises."""
    if isinstance(cmd, str):
        cmd_list = shlex.split(cmd)
    else:
        cmd_list = cmd
    try:
        p = subprocess.run(
            cmd_list,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"{cmd_list[0]}: not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"
    except Exception as e:
        return 1, "", f"{type(e).__name__}: {e}"


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def podman(*args: str, timeout: int = 15) -> tuple[int, str, str]:
    return run(["podman", *args], timeout=timeout)


def have(bin_name: str) -> bool:
    rc, _, _ = run(["which", bin_name], timeout=3)
    return rc == 0


# ---------------------------------------------------------------------------
# Meta
# ---------------------------------------------------------------------------


def collect_meta() -> dict[str, Any]:
    rc, head, _ = run(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"])
    rc2, dirty, _ = run(
        ["git", "-C", str(REPO_ROOT), "status", "--porcelain", "--untracked-files=no"]
    )
    rc3, podver, _ = run(["podman", "--version"])
    rc4, krn, _ = run(["uname", "-r"])
    return {
        "schema_version": 1,
        "vantage": "local",
        "host": socket.gethostname(),
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "git_head": head.strip() if rc == 0 else None,
        "git_dirty": bool(dirty.strip()) if rc2 == 0 else None,
        "podman_version": podver.strip() if rc3 == 0 else None,
        "kernel": krn.strip() if rc4 == 0 else None,
        "repo_root": str(REPO_ROOT),
    }


# ---------------------------------------------------------------------------
# Category: bind surface (ss + firewalld)
# ---------------------------------------------------------------------------


def collect_bind_surface(f: FindingStore) -> dict[str, Any]:
    """Every TCP/UDP listener, cross-checked against firewalld open ports."""
    raw: dict[str, Any] = {}

    # Listeners
    _, tcp, _ = run(["ss", "-tlnpH"])
    _, udp, _ = run(["ss", "-ulnpH"])
    raw["ss_tcp"] = tcp.strip().splitlines()
    raw["ss_udp"] = udp.strip().splitlines()

    listeners: list[dict[str, Any]] = []
    for proto, block in (("tcp", tcp), ("udp", udp)):
        for line in block.splitlines():
            parts = line.split()
            if len(parts) < 5:
                continue
            local = parts[3]
            proc = " ".join(parts[5:]) if len(parts) > 5 else ""
            host, _, port = local.rpartition(":")
            host = host.strip("[]")
            try:
                port_i = int(port)
            except ValueError:
                continue
            listeners.append(
                {"proto": proto, "host": host, "port": port_i, "process": proc}
            )
    raw["listeners"] = listeners

    # Firewalld
    _, fw, _ = run(["firewall-cmd", "--list-all"])
    raw["firewalld"] = fw.strip().splitlines()

    fw_ports: set[tuple[int, str]] = set()
    for line in fw.splitlines():
        line = line.strip()
        if line.startswith("ports:"):
            for tok in line.replace("ports:", "").strip().split():
                if "/" in tok:
                    p, proto = tok.split("/", 1)
                    try:
                        fw_ports.add((int(p), proto))
                    except ValueError:
                        pass
    raw["firewall_open_ports"] = sorted(fw_ports)

    # Gap check 1: any 0.0.0.0 bind that isn't 80/443 (those are Traefik's edge).
    for lst in listeners:
        if lst["host"] in ("0.0.0.0", "::") and lst["port"] not in EXPECTED_WAN_PORTS:
            # Allow ssh on 22 (LAN-restricted at firewall)
            if lst["port"] == 22:
                continue
            # Loopback-bound listeners show up as 127.0.0.1/::1 — not here
            f.add(
                "bind",
                "high",
                f"Listener on wildcard {lst['host']}:{lst['port']}/{lst['proto']} beyond expected WAN ports",
                evidence=[json.dumps(lst)],
                adr_refs=["#141", "#142"],
                hint="Rebind to 192.168.1.70:PORT (LAN) or 127.0.0.1 (host-only). Pattern: ADR-free follow-on to PR #170.",
            )

    # Gap check 2: firewall open ports with no matching listener = dead rule.
    listen_tcp_ports = {
        l["port"] for l in listeners if l["proto"] == "tcp" and l["host"] != "127.0.0.1"
    }
    listen_udp_ports = {
        l["port"] for l in listeners if l["proto"] == "udp" and l["host"] != "127.0.0.1"
    }
    for port, proto in fw_ports:
        listen_set = listen_tcp_ports if proto == "tcp" else listen_udp_ports
        if port not in listen_set:
            f.add(
                "firewall",
                "low",
                f"Firewalld allows {port}/{proto} but nothing is listening on it",
                evidence=[f"fw open={port}/{proto}", f"listeners={sorted(listen_set)}"],
                hint="Dead firewall rule — remove if service decommissioned (firewall-cmd --remove-port).",
            )

    # Gap check 3: listener on LAN IP with port not in firewalld = inconsistent
    for lst in listeners:
        if lst["host"] == "192.168.1.70":
            if (lst["port"], lst["proto"]) not in fw_ports:
                f.add(
                    "firewall",
                    "low",
                    f"LAN-bound listener {lst['port']}/{lst['proto']} has no explicit firewall rule",
                    evidence=[json.dumps(lst)],
                    hint="LAN-bound means LAN clients reach it by default. Either add explicit rule for intent, or unbind.",
                )

    return raw


# ---------------------------------------------------------------------------
# Category: container egress reality (Internal=true enforcement)
# ---------------------------------------------------------------------------


def collect_container_egress(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {"networks": {}, "probes": []}

    rc, nets_json, _ = podman("network", "ls", "--format", "json")
    if rc != 0:
        f.add(
            "egress",
            "medium",
            "podman network ls failed",
            evidence=[nets_json],
            hint="Investigate podman state before trusting egress posture.",
        )
        return raw

    try:
        nets = json.loads(nets_json)
    except json.JSONDecodeError:
        return raw

    for net in nets:
        name = net.get("name", "")
        internal_flag = net.get("internal", False)
        short = name.replace("systemd-", "")
        raw["networks"][name] = {
            "internal": internal_flag,
            "subnets": [s.get("subnet") for s in net.get("subnets", [])],
        }
        if short in EXPECTED_INTERNAL_NETWORKS and not internal_flag:
            f.add(
                "egress",
                "high",
                f"Network {name} expected Internal=true but podman reports false",
                evidence=[json.dumps(net)[:400]],
                adr_refs=["#141"],
                hint=(
                    "Known gotcha (journal 2026-04-21): edits to .network files don't re-apply via "
                    "systemctl restart because `podman network create --ignore` short-circuits. "
                    "Fix: podman network rm then restart *-network.service."
                ),
            )

    # Active probe: pick one container per internal network and attempt DNS + HTTPS out.
    _, ps_json, _ = podman("ps", "--format", "json")
    try:
        containers = json.loads(ps_json)
    except json.JSONDecodeError:
        containers = []

    tested_nets: set[str] = set()
    for c in containers:
        c_name = c.get("Names", [""])[0] if c.get("Names") else c.get("Name", "")
        c_nets = c.get("Networks") or []
        for net_name in c_nets:
            short = net_name.replace("systemd-", "")
            if short not in EXPECTED_INTERNAL_NETWORKS or net_name in tested_nets:
                continue
            # Only test if this container is NOT also on reverse_proxy (which is the escape hatch).
            if any(n.replace("systemd-", "") == "reverse_proxy" for n in c_nets):
                continue
            tested_nets.add(net_name)
            probe = {"container": c_name, "network": net_name, "checks": {}}
            # DNS probe — expect failure on Internal=true
            rc_d, out_d, err_d = podman(
                "exec",
                c_name,
                "sh",
                "-c",
                "getent hosts example.com || nslookup example.com 2>&1 | head -5",
                timeout=10,
            )
            probe["checks"]["dns"] = {
                "rc": rc_d,
                "out": (out_d + err_d).strip()[:400],
            }
            # Connect probe (port 443 to a public host by IP to bypass DNS)
            rc_c, out_c, err_c = podman(
                "exec",
                c_name,
                "sh",
                "-c",
                # 1.1.1.1 is stable; timeout quickly
                "timeout 3 sh -c '(echo > /dev/tcp/1.1.1.1/443) 2>&1' || echo BLOCKED",
                timeout=10,
            )
            probe["checks"]["tcp_out"] = {
                "rc": rc_c,
                "out": (out_c + err_c).strip()[:400],
            }
            raw["probes"].append(probe)

            # Analyse
            dns_reached = (
                rc_d == 0 and "example.com" in out_d and "can't" not in (out_d + err_d)
            )
            tcp_reached = "BLOCKED" not in (out_c + err_c) and rc_c == 0
            short = net_name.replace("systemd-", "")
            expected_isolated = short in EXPECTED_INTERNAL_NETWORKS
            if expected_isolated and (dns_reached or tcp_reached):
                f.add(
                    "egress",
                    "critical",
                    f"{c_name} on {net_name} reached the internet — egress isolation broken",
                    evidence=[
                        f"dns_rc={rc_d} dns_out={out_d.strip()[:200]}",
                        f"tcp_rc={rc_c} tcp_out={out_c.strip()[:200]}",
                    ],
                    adr_refs=["#141"],
                    hint="Expected Internal=true. Investigate podman network flags and container multi-network membership.",
                )
    return raw


# ---------------------------------------------------------------------------
# Category: Traefik routing chain (middleware completeness)
# ---------------------------------------------------------------------------

MIDDLEWARE_MIN_CHAIN = {
    "crowdsec": "crowdsec-bouncer",
    "rate_limit_prefix": "rate-limit",
    "headers": "security-headers",
}


def collect_traefik_chain(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    routers_yml = read_text(DYNAMIC / "routers.yml")
    middleware_yml = read_text(DYNAMIC / "middleware.yml")
    raw["routers_yml_path"] = str(DYNAMIC / "routers.yml")
    raw["routers_yml_size"] = len(routers_yml)
    if not routers_yml:
        f.add(
            "chain",
            "critical",
            "routers.yml missing or empty — Traefik has no dynamic config",
            hint="Verify config/traefik/dynamic/routers.yml exists.",
        )
        return raw

    # Parse router blocks by naive regex (avoid PyYAML dep). Each router starts
    # at `<name>:` under `routers:` and ends before the next router or service.
    try:
        import yaml  # type: ignore
    except ImportError:
        yaml = None
    if not yaml:
        f.add(
            "chain",
            "low",
            "PyYAML not installed — skipping deep chain audit",
            hint="dnf install python3-pyyaml for full chain introspection.",
        )
        return raw

    # Strip Go-template expressions (e.g., `"{{ env "X" }}"`) so PyYAML doesn't
    # choke on nested quotes. They only appear in values we don't audit here.
    def _strip_templates(src: str) -> str:
        return re.sub(r'"?\{\{[^}]*\}\}"?', '"__tmpl__"', src)

    try:
        doc = yaml.safe_load(_strip_templates(routers_yml)) or {}
    except Exception as e:
        f.add("chain", "high", f"routers.yml parse failure: {e}")
        return raw
    try:
        mid_doc = yaml.safe_load(_strip_templates(middleware_yml)) or {}
    except Exception as e:
        f.add("chain", "medium", f"middleware.yml parse failure: {e}")
        mid_doc = {}

    routers = (doc.get("http", {}) or {}).get("routers", {}) or {}
    defined_mw = set((mid_doc.get("http", {}) or {}).get("middlewares", {}).keys())
    referenced_mw: set[str] = set()

    router_audit: list[dict[str, Any]] = []
    for rname, rconf in routers.items():
        entrypoints = rconf.get("entryPoints") or []
        if "websecure" not in entrypoints:
            continue
        host_rule = rconf.get("rule", "")
        mws = [m.rsplit("@", 1)[0] for m in (rconf.get("middlewares") or [])]
        for m in mws:
            referenced_mw.add(m)
        has_crowdsec = any(m.startswith("crowdsec-bouncer") for m in mws)
        has_rate = any(m.startswith("rate-limit") for m in mws)
        has_headers = any(m.startswith("security-headers") or m == "hsts-only" for m in mws)
        has_auth = any(m in ("authelia",) for m in mws)
        router_audit.append(
            {
                "name": rname,
                "rule": host_rule,
                "middlewares": mws,
                "has_crowdsec": has_crowdsec,
                "has_rate_limit": has_rate,
                "has_headers": has_headers,
                "has_authelia": has_auth,
            }
        )

        if not has_crowdsec:
            f.add(
                "chain",
                "high",
                f"Router {rname} missing CrowdSec bouncer",
                evidence=[f"rule={host_rule}", f"mws={mws}"],
                adr_refs=["ADR-008", "ADR-016"],
                hint="Every websecure router must start with crowdsec-bouncer@file (fail-fast).",
            )
        if not has_rate:
            f.add(
                "chain",
                "high",
                f"Router {rname} missing rate-limit middleware",
                evidence=[f"rule={host_rule}", f"mws={mws}"],
                adr_refs=["ADR-008"],
                hint="Add rate-limit@file or a service-specific variant.",
            )
        if not has_headers:
            f.add(
                "chain",
                "medium",
                f"Router {rname} missing security-headers middleware",
                evidence=[f"rule={host_rule}", f"mws={mws}"],
                adr_refs=["ADR-016"],
                hint="Add security-headers@file (or -public/-strict) to emit HSTS/CSP.",
            )

    # Middleware drift
    dead = defined_mw - referenced_mw
    orphan = referenced_mw - defined_mw
    for m in sorted(dead):
        f.add(
            "chain",
            "low",
            f"Middleware '{m}' defined but never referenced",
            adr_refs=["#156"],
            hint="Candidate for deletion — reduces audit surface.",
        )
    for m in sorted(orphan):
        # Exclude inline Traefik defaults (e.g., @internal)
        if m in {"chain", "plugin"}:
            continue
        f.add(
            "chain",
            "high",
            f"Router references undefined middleware '{m}'",
            hint="Traefik will log an error and the chain won't apply. Define it or remove the reference.",
        )

    raw["routers"] = router_audit
    raw["middlewares_defined"] = sorted(defined_mw)
    raw["middlewares_referenced"] = sorted(referenced_mw)
    raw["middlewares_dead"] = sorted(dead)
    raw["middlewares_orphan"] = sorted(orphan)
    return raw


# ---------------------------------------------------------------------------
# Category: CrowdSec posture
# ---------------------------------------------------------------------------


def collect_crowdsec(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    rc_ps, _, _ = podman("exec", "crowdsec", "true", timeout=5)
    if rc_ps != 0:
        f.add(
            "crowdsec",
            "critical",
            "CrowdSec container not reachable",
            hint="Check systemctl --user status crowdsec.service.",
        )
        return raw

    for sub, label in [
        (["bouncers", "list", "-o", "json"], "bouncers"),
        (["decisions", "list", "-o", "json"], "decisions"),
        (["alerts", "list", "--since", "24h", "-o", "json"], "alerts_24h"),
        (["scenarios", "list", "-o", "json"], "scenarios"),
        (["metrics", "show", "acquisition", "-o", "json"], "acquisition"),
    ]:
        rc, out, err = podman("exec", "crowdsec", "cscli", *sub, timeout=15)
        if rc != 0:
            raw[label] = {"error": err[:200]}
            continue
        try:
            raw[label] = json.loads(out)
        except json.JSONDecodeError:
            raw[label] = {"raw": out[:1200]}

    # Bouncer presence
    if not raw.get("bouncers"):
        f.add(
            "crowdsec",
            "high",
            "CrowdSec has no registered bouncers",
            hint="Traefik's crowdsec-bouncer plugin must be enrolled. Without a bouncer, decisions do not reach traffic.",
        )

    # Acquisition sources
    acq = raw.get("acquisition") or {}
    if isinstance(acq, dict):
        sources = list(acq.keys()) if acq else []
        raw["acquisition_sources"] = sources
        if not sources:
            f.add(
                "crowdsec",
                "high",
                "CrowdSec acquisition is empty — no log sources tailed",
                adr_refs=["#137"],
                hint="Configure data/crowdsec/config/acquis.d/*.yaml. See journal 2026-04-21.",
            )
        else:
            # Sanity: Traefik acquisition should be reading > 0 lines since uptime.
            for src, stats in acq.items():
                if not isinstance(stats, dict):
                    continue
                read = stats.get("reads") or stats.get("lines_read")
                if read == 0:
                    f.add(
                        "crowdsec",
                        "medium",
                        f"Acquisition source {src} has read 0 lines",
                        evidence=[json.dumps(stats)[:300]],
                        hint="Container restarted recently, or the log path is wrong.",
                    )

    # Decision count
    decs = raw.get("decisions") or []
    raw["decision_count"] = len(decs) if isinstance(decs, list) else 0
    # 0 decisions is normal for a quiet week (see journal 2026-04-22) — info only.
    if raw["decision_count"] == 0:
        f.add(
            "crowdsec",
            "info",
            "CrowdSec has zero active decisions",
            hint=(
                "Not necessarily bad — layered defense upstream (UDM Region Block) "
                "may be absorbing most traffic. See journal 2026-04-22-ingress-forensics. "
                "Cross-check with remote-vantage probes."
            ),
        )

    return raw


# ---------------------------------------------------------------------------
# Category: Loki/Promtail pipeline liveness
# ---------------------------------------------------------------------------


def collect_loki_liveness(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    # Loki is on reverse_proxy + monitoring networks, bound to 3100 internally.
    # Use Traefik's /etc/hosts shim: resolve via container exec.
    # Probe via prometheus container (has wget; shares reverse_proxy network with loki).
    # promtail is distroless — no shell/wget available.
    rc, labels, err = podman(
        "exec", "prometheus", "wget", "-qO-",
        "http://loki:3100/loki/api/v1/labels", timeout=10,
    )
    if rc != 0:
        f.add(
            "loki",
            "high",
            "Loki /loki/api/v1/labels unreachable from prometheus probe",
            evidence=[err[:200]],
            hint="Pipeline break — without Loki, security events don't index.",
        )
        return raw
    try:
        raw["labels"] = json.loads(labels).get("data", [])
    except json.JSONDecodeError:
        raw["labels"] = []

    # Per-job last-ingest probe
    _, jobs_out, _ = podman(
        "exec", "prometheus", "wget", "-qO-",
        "http://loki:3100/loki/api/v1/label/job/values", timeout=10,
    )
    try:
        jobs = json.loads(jobs_out).get("data", [])
    except json.JSONDecodeError:
        jobs = []
    raw["jobs"] = jobs

    now = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1_000_000_000)
    window = 30 * 60 * 1_000_000_000  # 30 minutes
    per_job_last: dict[str, int | None] = {}
    for job in jobs:
        # Query last entry timestamp
        q = f'{{job="{job}"}}'
        url = (
            f"http://loki:3100/loki/api/v1/query_range?"
            f"query={q}&limit=1&start={now - window}&end={now}&direction=backward"
        )
        rc_q, out_q, _ = podman("exec", "prometheus", "wget", "-qO-", url, timeout=10)
        if rc_q != 0:
            per_job_last[job] = None
            continue
        try:
            data = json.loads(out_q)
            results = data.get("data", {}).get("result", [])
            last_ts = None
            for stream in results:
                values = stream.get("values", [])
                if values:
                    last_ts = int(values[0][0])
                    break
            per_job_last[job] = last_ts
        except json.JSONDecodeError:
            per_job_last[job] = None

    raw["per_job_last_ingest_ns"] = per_job_last
    raw["now_ns"] = now

    for job, last in per_job_last.items():
        if last is None:
            f.add(
                "loki",
                "medium",
                f"Loki job '{job}' has no entries in last 30 min",
                adr_refs=[],
                hint=(
                    "Silent pipeline failure is worse than a broken one — verify promtail "
                    "target. See journal 2026-04-22-udm-pro-siem-syslog-pipeline lesson on "
                    "healthy-queue-with-wrong-data."
                ),
            )
    return raw


# ---------------------------------------------------------------------------
# Category: Cert expiry
# ---------------------------------------------------------------------------


def collect_certs(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    rc, acme, _ = podman("exec", "traefik", "cat", "/letsencrypt/acme.json", timeout=10)
    if rc != 0 or not acme.strip():
        f.add(
            "cert",
            "medium",
            "Cannot read Traefik acme.json",
            hint="Verify /letsencrypt/acme.json exists with 600 perms.",
        )
        return raw
    try:
        data = json.loads(acme)
    except json.JSONDecodeError:
        return raw

    certs = []
    for resolver, v in data.items():
        for cert in v.get("Certificates") or []:
            main = cert.get("domain", {}).get("main", "?")
            sans = cert.get("domain", {}).get("sans", []) or []
            pem_b64 = cert.get("certificate", "")
            not_after = None
            try:
                import base64

                pem = base64.b64decode(pem_b64).decode(errors="replace")
                # Parse notAfter via openssl
                rc_o, out_o, _ = run(
                    ["openssl", "x509", "-noout", "-enddate"],
                    timeout=5,
                )
                # Re-run with input piped
                p = subprocess.run(
                    ["openssl", "x509", "-noout", "-enddate"],
                    input=pem,
                    text=True,
                    capture_output=True,
                    timeout=5,
                )
                if p.returncode == 0:
                    m = re.search(r"notAfter=(.+)", p.stdout)
                    if m:
                        not_after = m.group(1).strip()
            except Exception:
                pass
            days_left = None
            if not_after:
                try:
                    end = dt.datetime.strptime(
                        not_after, "%b %d %H:%M:%S %Y %Z"
                    ).replace(tzinfo=dt.timezone.utc)
                    days_left = (end - dt.datetime.now(dt.timezone.utc)).days
                except ValueError:
                    pass
            entry = {
                "main": main,
                "sans": sans,
                "not_after": not_after,
                "days_left": days_left,
                "resolver": resolver,
            }
            certs.append(entry)
            if days_left is not None and days_left < 21:
                sev = "critical" if days_left < 7 else "high"
                f.add(
                    "cert",
                    sev,
                    f"Certificate for {main} expires in {days_left} days",
                    evidence=[json.dumps(entry)],
                    hint="Traefik should auto-renew. If not, check ACME DNS-01 challenge state.",
                )
    raw["certificates"] = certs
    return raw


# ---------------------------------------------------------------------------
# Category: Container hardening (privileges, caps, mounts)
# ---------------------------------------------------------------------------

SENSITIVE_MOUNT_PATTERNS = [
    "/run/user/1000/podman/podman.sock",
    "/var/run/docker.sock",
    "/etc/shadow",
    "/root/",
]


def collect_container_hardening(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {"containers": []}
    rc, ps_json, _ = podman("ps", "--format", "json")
    if rc != 0:
        return raw
    try:
        containers = json.loads(ps_json)
    except json.JSONDecodeError:
        return raw

    for c in containers:
        names = c.get("Names") or [c.get("Name", "")]
        name = names[0] if names else ""
        rc_i, insp, _ = podman("inspect", name, timeout=15)
        if rc_i != 0:
            continue
        try:
            data = json.loads(insp)[0]
        except (json.JSONDecodeError, IndexError):
            continue
        hc = data.get("HostConfig", {}) or {}
        cfg = data.get("Config", {}) or {}
        privileged = hc.get("Privileged", False)
        cap_add = hc.get("CapAdd") or []
        cap_drop = hc.get("CapDrop") or []
        ipc = hc.get("IpcMode", "")
        pid_mode = hc.get("PidMode", "")
        readonly = hc.get("ReadonlyRootfs", False)
        userns = hc.get("UsernsMode", "")
        security_opt = hc.get("SecurityOpt") or []

        mounts = data.get("Mounts") or []
        mount_paths = [m.get("Source", "") for m in mounts]

        entry = {
            "name": name,
            "privileged": privileged,
            "cap_add": cap_add,
            "cap_drop": cap_drop,
            "ipc_mode": ipc,
            "pid_mode": pid_mode,
            "readonly_rootfs": readonly,
            "userns_mode": userns,
            "security_opt": security_opt,
            "mounts": [
                {
                    "src": m.get("Source"),
                    "dst": m.get("Destination"),
                    "mode": m.get("Mode"),
                    "rw": m.get("RW"),
                }
                for m in mounts
            ],
        }
        raw["containers"].append(entry)

        if privileged:
            f.add(
                "container",
                "critical",
                f"{name} runs privileged",
                evidence=[json.dumps({"privileged": True})],
                adr_refs=["ADR-001"],
                hint="Violates rootless-containers principle. Pin down which cap is actually needed and grant selectively.",
            )
        for cap in cap_add:
            f.add(
                "container",
                "medium",
                f"{name} adds capability {cap}",
                adr_refs=["ADR-001"],
                hint=f"Justify CAP_{cap}; remove if unused.",
            )
        if pid_mode == "host":
            f.add(
                "container",
                "high",
                f"{name} shares host PID namespace",
                hint="host PID namespace defeats process isolation.",
            )
        if ipc == "host":
            f.add(
                "container",
                "medium",
                f"{name} shares host IPC namespace",
                hint="Rare legitimate need. Verify.",
            )
        for mp in mount_paths:
            for pattern in SENSITIVE_MOUNT_PATTERNS:
                if pattern in mp:
                    f.add(
                        "container",
                        "high",
                        f"{name} mounts sensitive host path {mp}",
                        hint="Container escape risk. Especially podman.sock = full rootless control.",
                    )

    return raw


# ---------------------------------------------------------------------------
# Category: SSH + auth surface
# ---------------------------------------------------------------------------


def _parse_sshd_config() -> dict[str, str]:
    """Read /etc/ssh/sshd_config + drop-ins without sudo. Last value wins (matches sshd -T semantics closely enough for audit purposes; does not honor Match blocks)."""
    effective: dict[str, str] = {}
    paths: list[Path] = []
    main = Path("/etc/ssh/sshd_config")
    if main.exists():
        paths.append(main)
    dropin = Path("/etc/ssh/sshd_config.d")
    if dropin.is_dir():
        # Include order matters; sshd reads *.conf lexically
        paths.extend(sorted(dropin.glob("*.conf")))
    for p in paths:
        try:
            for line in p.read_text(errors="replace").splitlines():
                s = line.strip()
                if not s or s.startswith("#") or s.lower().startswith("match "):
                    continue
                parts = s.split(None, 1)
                if len(parts) == 2:
                    effective[parts[0].lower()] = parts[1].strip()
        except OSError:
            continue
    return effective


def collect_ssh_surface(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    effective = _parse_sshd_config()
    raw["sshd_effective"] = effective
    raw["sshd_note"] = "Parsed from sshd_config + sshd_config.d/*.conf (no sudo). Match blocks not expanded."

    defaults_if_missing = {
        "permitrootlogin": "prohibit-password",
        "passwordauthentication": "yes",
        "permitemptypasswords": "no",
        "x11forwarding": "no",
    }
    for k, bad_values in [
        ("permitrootlogin", ("yes", "without-password", "prohibit-password")),
        ("passwordauthentication", ("yes",)),
        ("permitemptypasswords", ("yes",)),
        ("x11forwarding", ("yes",)),
    ]:
        val = effective.get(k, defaults_if_missing[k]).lower()
        if val in bad_values:
            sev = "high" if k in ("passwordauthentication", "permitemptypasswords") else "medium"
            f.add(
                "auth",
                sev,
                f"sshd_config {k} = {val}",
                evidence=[f"source={'config' if k in effective else 'default'}"],
                hint="Harden sshd per CIS baseline; prefer PubkeyAuthentication only.",
            )

    # authorized_keys
    ak = Path.home() / ".ssh" / "authorized_keys"
    if ak.exists():
        content = read_text(ak)
        lines = [
            l for l in content.splitlines() if l.strip() and not l.startswith("#")
        ]
        raw["authorized_keys_count"] = len(lines)
        raw["authorized_keys_types"] = [
            l.split()[0] for l in lines if l.split()
        ]
        for l in lines:
            if l.startswith("ssh-rsa ") and "from=" not in l:
                f.add(
                    "auth",
                    "medium",
                    "authorized_keys: RSA key with no from= restriction",
                    evidence=[l[:80]],
                    hint="Prefer FIDO2 sk-* keys (ADR-006). Old RSA keys should carry from=\"192.168.1.0/24\".",
                )
            if not l.startswith("sk-") and "from=" not in l:
                f.add(
                    "auth",
                    "low",
                    "authorized_keys: non-FIDO key without LAN restriction",
                    evidence=[l[:80]],
                    adr_refs=["ADR-006"],
                    hint='Add from="192.168.1.0/24" or migrate to YubiKey sk-*.',
                )
    return raw


# ---------------------------------------------------------------------------
# Category: Config drift
# ---------------------------------------------------------------------------


def collect_drift(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    # Working tree
    rc, wt, _ = run(
        ["git", "-C", str(REPO_ROOT), "status", "--porcelain"], timeout=10
    )
    raw["working_tree"] = wt.splitlines()
    if wt.strip():
        f.add(
            "drift",
            "low",
            f"Git working tree has {len(wt.splitlines())} uncommitted entries",
            evidence=wt.splitlines()[:20],
            hint="Not a security issue per se, but untracked configs are un-audited configs.",
        )

    # Unpushed commits
    rc, ahead, _ = run(
        ["git", "-C", str(REPO_ROOT), "log", "--oneline", "@{u}..HEAD"], timeout=10
    )
    if rc == 0 and ahead.strip():
        raw["unpushed"] = ahead.splitlines()
        f.add(
            "drift",
            "info",
            f"{len(ahead.splitlines())} unpushed commits",
            evidence=ahead.splitlines()[:5],
        )

    # check-drift.sh if present
    drift_script = REPO_ROOT / "scripts" / "check-drift.sh"
    if drift_script.exists():
        rc, out, err = run(["bash", str(drift_script)], timeout=60)
        raw["check_drift_rc"] = rc
        raw["check_drift_out"] = (out + err).splitlines()[:60]
        if rc not in (0, 1):
            f.add(
                "drift",
                "medium",
                f"check-drift.sh returned non-standard rc={rc}",
                evidence=raw["check_drift_out"][:15],
            )
    return raw


# ---------------------------------------------------------------------------
# Category: Journal anomalies
# ---------------------------------------------------------------------------


def collect_journal(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    # SELinux denials in last 24h
    rc, denials, _ = run(
        [
            "journalctl",
            "--since",
            "24 hours ago",
            "-g",
            "SELinux.*denied|avc:.*denied",
            "-o",
            "short",
            "--no-pager",
        ],
        timeout=15,
    )
    lines = [l for l in denials.splitlines() if "denied" in l.lower()]
    raw["selinux_denials_24h"] = lines[-50:]
    if lines:
        f.add(
            "journal",
            "medium",
            f"{len(lines)} SELinux denials in last 24h",
            evidence=lines[-5:],
            hint="Check for mislabeled bind mounts. Pattern: ausearch -m avc -ts recent.",
        )

    # OOM kills
    rc, oom, _ = run(
        [
            "journalctl",
            "--since",
            "24 hours ago",
            "-g",
            "Out of memory|oom-killer|OOM",
            "--no-pager",
        ],
        timeout=10,
    )
    oom_lines = [l for l in oom.splitlines() if "oom" in l.lower() or "Out of memory" in l]
    raw["oom_24h"] = oom_lines[-20:]
    if oom_lines:
        f.add(
            "journal",
            "high",
            f"{len(oom_lines)} OOM events in last 24h",
            evidence=oom_lines[-5:],
            hint="Memory pressure — could be a leak, could be an attack. Correlate with container stats.",
        )

    # Failed systemd units (user + system)
    for scope in ([], ["--user"]):
        rc, failed, _ = run(
            ["systemctl", *scope, "--failed", "--no-legend", "--plain"], timeout=10
        )
        key = "system_failed" if not scope else "user_failed"
        raw[key] = [l for l in failed.splitlines() if l.strip()]
        if raw[key]:
            f.add(
                "journal",
                "high",
                f"Failed systemd units ({'user' if scope else 'system'}): {len(raw[key])}",
                evidence=raw[key][:10],
                hint="Run systemctl status <unit> -n 50 on each.",
            )

    return raw


# ---------------------------------------------------------------------------
# Category: ADR compliance cross-checks
# ---------------------------------------------------------------------------


def collect_adr_compliance(f: FindingStore) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    # ADR-018: multi-network containers get static IPs + /etc/hosts shim
    rc, ps_json, _ = podman("ps", "--format", "json")
    try:
        containers = json.loads(ps_json)
    except (json.JSONDecodeError, TypeError):
        containers = []

    multi_net = []
    for c in containers:
        nets = c.get("Networks") or []
        name = (c.get("Names") or [c.get("Name", "")])[0]
        if len(nets) > 1:
            multi_net.append({"name": name, "networks": nets})
    raw["multi_network_containers"] = multi_net

    # Check for /etc/hosts overrides in traefik container (where the shim lives)
    rc, hosts, _ = podman("exec", "traefik", "cat", "/etc/hosts", timeout=5)
    raw["traefik_etc_hosts"] = hosts.splitlines() if rc == 0 else []
    static_ip_entries = [
        l for l in raw["traefik_etc_hosts"] if "10.89." in l and not l.startswith("#")
    ]
    raw["static_ip_entries"] = static_ip_entries

    # ADR-016: labels=false for Traefik provider (no routing in container labels)
    rc, trfk_yml, _ = podman("exec", "traefik", "cat", "/etc/traefik/traefik.yml", timeout=5)
    if rc == 0 and "exposedByDefault: false" not in trfk_yml:
        f.add(
            "adr",
            "high",
            "Traefik provider.docker.exposedByDefault != false",
            adr_refs=["ADR-016"],
            hint="Enforces 'no routing in labels' rule. See ADR-016.",
        )
    raw["traefik_static_config_snippet"] = trfk_yml[:2000]

    return raw


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


COLLECTORS: dict[str, Any] = {
    "bind": collect_bind_surface,
    "egress": collect_container_egress,
    "chain": collect_traefik_chain,
    "crowdsec": collect_crowdsec,
    "loki": collect_loki_liveness,
    "cert": collect_certs,
    "container": collect_container_hardening,
    "auth": collect_ssh_surface,
    "drift": collect_drift,
    "journal": collect_journal,
    "adr": collect_adr_compliance,
}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--category", choices=sorted(COLLECTORS.keys()), help="run one only")
    ap.add_argument("--pretty", action="store_true", help="also print JSON to stdout")
    ap.add_argument("--stdout-only", action="store_true", help="don't write report file")
    args = ap.parse_args(argv)

    if not (REPO_ROOT / "CLAUDE.md").exists():
        print(f"ERROR: not in repo root ({REPO_ROOT})", file=sys.stderr)
        return 2
    if not have("podman"):
        print("ERROR: podman not found", file=sys.stderr)
        return 2

    findings = FindingStore()
    raw: dict[str, Any] = {}

    cats = [args.category] if args.category else list(COLLECTORS.keys())
    for cat in cats:
        try:
            raw[cat] = COLLECTORS[cat](findings) or {}
        except Exception as e:
            findings.add(
                cat,
                "medium",
                f"collector '{cat}' crashed: {type(e).__name__}",
                evidence=[str(e)[:400]],
                hint="Collector bug — does not invalidate other categories.",
            )

    meta = collect_meta()
    items = findings.all()
    summary: dict[str, int] = {}
    for it in items:
        summary[it["severity"]] = summary.get(it["severity"], 0) + 1
    report = {
        "meta": meta,
        "summary": summary,
        "findings": items,
        "raw": raw,
    }

    if not args.stdout_only:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        ts = meta["generated_at"].replace(":", "-")
        out_path = REPORT_DIR / f"{ts}.json"
        out_path.write_text(json.dumps(report, indent=2, default=str))
        print(f"wrote {out_path}", file=sys.stderr)

    if args.pretty or args.stdout_only:
        json.dump(report, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        # short human summary
        print(
            f"local posture: {sum(summary.values())} findings "
            f"(crit={summary.get('critical',0)} high={summary.get('high',0)} "
            f"med={summary.get('medium',0)} low={summary.get('low',0)} info={summary.get('info',0)})",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
