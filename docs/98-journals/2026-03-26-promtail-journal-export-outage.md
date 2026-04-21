# Promtail Journal Export Outage — Incident Report

**Date:** 2026-03-26
**Incident:** Repeated Discord alerts for missing `promtail_custom_nextcloud_cron_success_total` metric
**Severity:** Low (monitoring gap — no data loss or service impact)
**Duration:** ~2 days (2026-03-24 12:15 to 2026-03-26 08:26)
**Resolution:** Flushed volatile journal to persistent storage, vacuumed old entries, restarted journal-export

---

## Executive Summary

The NVMe system drive filled to 100% around 2026-03-24, preventing all writes. This caused systemd-journald to stop writing to persistent storage (`/var/log/journal/`). After the drive was freed and the system rebooted, journald silently fell back to volatile storage (`/run/log/journal/`), which does not create per-user journal split files (`user-1000.journal`). The `journal-export.service` uses `journalctl --user -f` which depends on these split files — it produced zero output, leaving Promtail's `journal.log` empty. Without log data, Promtail could not extract the `nextcloud_cron_success_total` metric, triggering the alert.

---

## Timeline

| Time (CET) | Event |
|------------|-------|
| 2026-03-24 ~12:00 | NVMe drive (/dev/nvme0n1p3) reached 100% capacity |
| 2026-03-24 12:15 | Last entry written to persistent user journal (`user-1000.journal`) |
| 2026-03-24 ~12:22 | System rebooted; journald started but fell back to volatile storage |
| 2026-03-24 13:00 | journal-export.service restarted; journal.log recreated at 0 bytes |
| 2026-03-24 15:54 | First Discord alert: `promtail_custom_nextcloud_cron_success_total` missing |
| 2026-03-24 – 03-26 | Repeated Discord alerts (~every 65 minutes) |
| 2026-03-26 08:20 | Investigation began |
| 2026-03-26 08:25 | Root cause identified: `journalctl --user` returning zero entries |
| 2026-03-26 08:25 | Fix applied: `journalctl --flush` + `--vacuum-size=2G` + restart journal-export |
| 2026-03-26 08:26 | Metric confirmed present in Promtail (23 increments at priority 6) |

---

## Root Cause Analysis

### The Failure Chain (4 stages)

```
Stage 1: NVMe Full
  System drive hit 100% → no writes possible
  → journald could not write to /var/log/journal/

Stage 2: Silent Fallback
  After reboot, journald fell back to volatile storage (/run/log/journal/)
  Volatile mode does NOT create per-user journal files (user-1000.journal)
  No error logged — completely silent degradation

Stage 3: journal-export Blind
  journal-export.service runs: journalctl --user -f -o json
  --user flag depends on user journal split files
  With no user journal → zero output → journal.log stays at 0 bytes

Stage 4: Metric Disappears
  Promtail reads empty journal.log → no log lines to process
  nextcloud_cron_success_total metric never incremented
  Alert fires: "Promtail metric extraction may have failed"
```

### Why the Alert Was Correct But Misleading

The alert correctly detected that the metric was missing. However, the suggested causes in the alert body (pipeline regex mismatch, position file issue, cron timer stopped) were all wrong. The actual cause was two layers deeper: journald's storage mode change broke the `--user` flag semantics.

---

## Resolution

```bash
# Flush volatile journal entries to persistent storage
sudo journalctl --flush

# Vacuum old entries (freed 1.9G of archived user journals)
sudo journalctl --vacuum-size=2G

# Restart journal-export to pick up restored user journal
systemctl --user restart journal-export.service
```

After restart, `journalctl --user` returned 3115 entries in the first minute, journal.log began filling immediately, and Promtail exported the metric within seconds.

---

## Observations

- The persistent journal had accumulated 4GB of user journal archives — 19 rotated `user-1000@*.journal` files at ~100MB each. Vacuuming freed 1.9GB.
- All 30 containers continued running normally throughout the incident. Only the monitoring pipeline was affected.
- The nextcloud-cron timer ran successfully every 5 minutes during the entire outage — only the *observation* of success was broken.

---

## Open Investigation: Volatile Journal Fallback

**Status:** Not yet investigated — handoff for future session.

### What We Know
- After the NVMe filled and the system rebooted, journald started writing to `/run/log/journal/` (volatile/tmpfs) instead of `/var/log/journal/` (persistent/NVMe).
- The `journald.conf` has `Storage=auto` (default) which should prefer persistent if `/var/log/journal/` exists and is writable.
- `/var/log/journal/2b6e6a4ebb9447679e5731ef2588426d/` exists with correct ownership (root:systemd-journal) and ACLs.
- After running `journalctl --flush`, the persistent journal resumed working.

### Questions to Answer
1. **Why did journald not resume persistent writes after the drive was freed?** With `Storage=auto`, journald should write to `/var/log/journal/` if the directory exists. Was there a stale lock file? Corrupted journal header? BTRFS filesystem issue?
2. **Is `journalctl --flush` idempotent and safe to run periodically?** If so, consider adding it to the reboot script or a systemd timer as a defensive measure.
3. **Should journal-export use `_UID=1000` instead of `--user`?** The `--user` flag is fragile because it depends on journal split mode. Filtering by `_UID=1000` pulls from the system journal directly and worked throughout the outage (139K entries available). Trade-off: `_UID=1000` would include non-service entries (SSH sessions, etc.) but the Promtail pipeline already filters by `syslog_id` label.
4. **Should we set `Storage=persistent` explicitly in `journald.conf`?** This would force persistent storage and fail loudly rather than silently falling back to volatile.
5. **Should we add disk space monitoring alerts?** The NVMe filling to 100% was the trigger for this entire chain. A `node_filesystem_avail_bytes` alert at 90% would provide early warning.
6. **Should we cap the user journal size?** The 4GB of accumulated user journals contributed to disk pressure. Consider setting `SystemMaxUse=2G` in `journald.conf`.

### How to Investigate
```bash
# Check if journald is currently using persistent or volatile
journalctl --header | head -5  # File path shows which

# Check for journal corruption
journalctl --verify 2>&1 | grep -i "fail\|error\|corrupt"

# Check BTRFS health on system drive
sudo btrfs device stats /

# Test: would journald survive another full-disk event?
# (simulate in a test environment, not production)
```
