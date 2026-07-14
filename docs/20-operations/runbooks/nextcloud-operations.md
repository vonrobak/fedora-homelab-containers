---
type: Runbook
title: "Nextcloud Operational Runbook"
description: "Public stub — the full Nextcloud operational runbook lives in the private homelab vault; its value is its host-specific detail."
sensitivity: public
created: 2025-12-21
updated: 2026-07-14
---

# Nextcloud Operational Runbook

Day-to-day operational procedures for the Nextcloud stack — user and
FIDO2/WebAuthn device management, external-storage mounts, backup and restore,
maintenance mode, and troubleshooting.

The full runbook — the exact `occ` commands, subvolume paths, quadlet edits,
and snapshot/restore steps — lives in the private homelab operations vault,
not in this public repo. It was moved there deliberately (ADR-043 D3 runbook
split test): the procedures are load-bearing on this host's specific storage
layout and account model, so their value is precisely the detail that should
not be published. Nextcloud's architecture and deployment decisions remain
public in `docs/10-services/` and the ADRs.
