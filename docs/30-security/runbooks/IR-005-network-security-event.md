---
type: Runbook
title: "IR-005: Network Security Event"
description: "Public stub — the full network-security-event incident runbook lives in the private homelab vault; its value is its host-specific detail."
sensitivity: public
created: 2026-01-08
updated: 2026-07-14
---

# IR-005: Network Security Event

Incident-response procedure for network-layer security events — UDM Pro DPI
threat detections, bandwidth spikes, and firewall block surges surfaced via
Unpoller.

The full runbook — the specific detection queries, UDM Pro firewall steps,
CrowdSec ban commands, and evidence-capture procedure — lives in the private
homelab operations vault, not in this public repo. It was moved there
deliberately (ADR-043 D3 runbook split test): its operational value *is* its
host-specific detail, so publishing a scrubbed shell would help no one while
leaking the specifics would help an attacker. The generic incident-response
runbooks IR-001–IR-004 remain public.
