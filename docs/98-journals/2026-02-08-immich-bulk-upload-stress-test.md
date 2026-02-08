# Immich Bulk Upload Stress Test: 10,608 Assets from iPhone

**Date:** 2026-02-08 (session: 2026-02-07 20:57 → 2026-02-08 02:45)
**Author:** Claude Opus 4.6
**Status:** Complete. Configuration improvements applied. Phases 2-6 observations captured.

---

## Summary

What began as a Phase 2 client device test (iPhone) turned into a full-scale stress test when the user enabled Apple Photos backup, sending 10,608 assets (~118GB of photos and videos) through the entire Immich pipeline in a single session. This unplanned bulk migration -- originally scheduled as a separate Phase 6 activity -- exercised every layer of the stack: Traefik routing, Immich server upload handling, PostgreSQL metadata storage, Redis caching, and ML processing (face detection, CLIP search, OCR).

**Key outcome:** The upload completed successfully (10,608/10,608, zero remainder), but exposed two infrastructure-level issues that were diagnosed and fixed in real time: a 60-second Traefik `readTimeout` default that blocked large file uploads, and a circuit breaker that tripped on client-side disconnections. Both fixes are now permanent.

**Version context:** Immich was updated from v2.5.2 to v2.5.5 at the start of this session. The upload ran entirely on v2.5.5.

---

## Timeline

| Time | Event |
|------|-------|
| 20:57 | Immich updated v2.5.2 → v2.5.5, all 4 containers healthy |
| 21:07 | iPhone backup started, first uploads received |
| 21:15 | Face detection and VAAPI video transcoding active |
| 21:16 | First ECONNRESET errors (3x) -- connection drops during upload |
| 21:17 | immich-ml worker recycled due to inactivity timeout, 2 ML jobs failed |
| 21:25 | immich-ml recycled again, reloaded models |
| ~21:30 | Upload stalled at 211 files for ~10 minutes |
| 21:33 | Upload resumed after app navigation, high-speed transfer |
| 23:37 | **Circuit breaker tripped** -- Traefik blocking all Immich traffic |
| 23:40 | Circuit breaker re-tripped during recovery |
| 23:50 | Circuit breaker tripped again |
| 00:08 | Brief recovery |
| 00:16 | Circuit breaker tripped again |
| 00:23 | **Circuit breaker temporarily disabled** from Immich route |
| 00:23-02:30 | Upload running steadily, occasional ECONNRESET on large files |
| 02:08 | Large files failing at exactly 60-second intervals (3 files, 3 retries) |
| 02:33 | Same 60-second pattern confirmed -- hard timeout identified |
| 02:42 | **Traefik restarted with readTimeout: 600s** |
| 02:43 | Large file uploads resumed successfully |
| ~02:50 | Upload complete: 10,608/10,608, remainder 0 |
| 02:50+ | Server processing backlog (thumbnails, ML, transcoding) |

---

## Findings

### Finding 1: Traefik Default readTimeout Blocks Large Uploads

**Root cause of the most persistent upload failures.**

Traefik's `websecure` entrypoint had no explicit timeout configuration, inheriting a 60-second `readTimeout` default. This is a hard cap on how long Traefik will wait to read the entire request body, including file upload data.

**Evidence:** Upload failures occurred in perfectly synchronized groups of 3 (one per concurrent upload), exactly 60 seconds apart:
- 02:08:20 → 02:09:20 (60s)
- 02:33:33 → 02:34:34 (61s)
- 02:37:12 → 02:38:12 (60s)

The second failure in each pair was the `retry@file` middleware attempting to replay the upload, which immediately failed since the request body stream was already consumed.

**Impact:** Any file too large to fully transfer within 60 seconds would fail. At 10MB/s, this meant files >600MB. At slower speeds (thermal throttling, WiFi congestion), even smaller files could fail.

**Fix applied:**
```yaml
# config/traefik/traefik.yml
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 600s     # 10 minutes - supports large file uploads
        writeTimeout: 600s    # 10 minutes - supports large file downloads
        idleTimeout: 180s     # 3 minutes - keep-alive connections
```

**Verification:** After Traefik restart, three large files that had failed repeatedly at 60s uploaded successfully at full speed.

**Gotcha for future reference:** Traefik's default timeouts are designed for web applications serving small request/response cycles. Any service that handles large file uploads (Immich, Nextcloud, Vaultwarden attachments) needs explicit timeout configuration. This should be added to deployment patterns.

### Finding 2: Circuit Breaker Trips on Client-Side Disconnections

**Root cause of the "Service Unavailable" periods.**

The Traefik circuit breaker middleware (`NetworkErrorRatio() > 0.50`) counts ECONNRESET errors from client-side disconnections as network errors. During bulk upload from a mobile device, client disconnections are frequent and expected (iOS background behavior, thermal throttling, large file timeouts). When the error ratio exceeded 50%, the breaker tripped and blocked ALL Immich traffic -- including new upload attempts and web browsing.

**Evidence:** Traefik logs showed 25+ circuit breaker state transitions:
- `state=tripped` → returns 503 to all clients
- `state=recovering` → allows some traffic through
- Re-trips within seconds when retry traffic generates more errors

The iPhone app reported these as "ClientException with SocketException: Connection reset by peer (OS Error: errno = 54)".

**The vicious cycle:**
1. Client disconnection → ECONNRESET
2. Error ratio rises → circuit breaker trips
3. All requests get 503 → clients retry
4. Retries during recovery → more errors → re-trip

**Temporary fix:** Removed circuit breaker from Immich route during upload. Re-enabled after completion.

**Permanent consideration:** The circuit breaker as configured is inappropriate for Immich's upload-heavy traffic pattern. Options:
- Remove circuit breaker from Immich route entirely (client errors are not backend failures)
- Create an Immich-specific circuit breaker with higher thresholds
- Change expression to only trigger on `ResponseCodeRatio` (5xx), not `NetworkErrorRatio`

### Finding 3: immich-ml Inactivity Timeout Causes Transient Failures

**Minor issue, self-healing.**

immich-ml's gunicorn worker has a 300-second inactivity timeout. During the upload, iCloud delivered files in waves with gaps. When a gap exceeded 5 minutes, ML unloaded models and shut down its worker. The next burst of ML requests (face detection, CLIP) failed because the worker was restarting.

**Evidence:**
- ML logs: `"Shutting down due to inactivity"` → `"Worker (pid:119) was sent SIGINT!"` → `"Booting worker with pid: 223"`
- Server logs: `"Machine learning request to http://immich-ml:3003 failed: fetch failed"` → `"Unable to run job handler (AssetDetectFaces)"`

**Impact:** 2-4 ML job failures per recycling event. All jobs are automatically retried by Immich's job queue. No permanent data loss.

**Potential fix:** Environment variable `MACHINE_LEARNING_WORKER_TIMEOUT=0` (disable inactivity shutdown) or increase to 600s. Trade-off: ML process uses ~1.3GB RAM when models are loaded.

### Finding 4: VAAPI Transcoding Graceful Fallback Works

**Positive finding -- the system handled codec edge cases correctly.**

Of 197 video transcoding operations, 177 (90%) used AMD VAAPI hardware acceleration successfully. 20 videos (10%) had codecs incompatible with VAAPI and triggered ffmpeg errors. In every case, Immich correctly caught the error and retried with `"VAAPI acceleration disabled"` (software encoding). All 197 videos completed successfully.

**Specific codecs that failed VAAPI:** mjpeg-based .MOV files (often from older cameras or screen recordings), and some non-standard mp4 containers.

### Finding 5: Live Photo Dual-File Upload Counting

**Cosmetic issue in Immich iOS app.**

The backup screen temporarily showed 19,028 "backed up" against 10,611 total assets, with a negative remainder of -8,417. This is because each Live Photo uploads as two files (HEIC + MOV companion), but displays as one asset. After navigating away and back, the counters corrected to accurate values.

The 8,725 "duplicate key" constraint violations in the server logs confirm the app attempted to re-upload already-synced assets during retry cycles, and the server correctly rejected them via the `UQ_assets_owner_checksum` unique constraint.

### Finding 6: iCloud as Upload Bottleneck

**Hypothesis, supported by behavioral evidence.**

The burst-then-stall upload pattern (rapid uploads → minutes of silence → rapid uploads) is consistent with iOS downloading photos from iCloud on demand when "Optimize iPhone Storage" is enabled. The phone doesn't store full-resolution originals locally; it fetches them from Apple's servers before uploading to Immich. Apple likely applies rate limiting or connection pooling on these downloads.

**Evidence (circumstantial):**
- Stalls don't correlate with server load, Traefik state, or WiFi metrics
- Uploads resume in bursts (consistent with a batch of iCloud downloads completing)
- Phone was cold (midwinter Norway, placed in window) -- ruling out thermal throttling

### Finding 7: 3 Unsupported File Types

Three `.jfif` files (JPEG File Interchange Format variant) were rejected by Immich:
- `inflation.jfif` (20 retry attempts)
- `emotionalchild.jfif` (23 retry attempts)
- `leftrightbigot.jfif` (23 retry attempts)

These are likely downloaded images saved in JFIF format, which Immich doesn't support. The filenames suggest internet-sourced content. The app persistently retried these -- ideally it should mark them as permanently unsupported after the first rejection.

---

## Processing Statistics (354,743 Log Lines)

| Metric | Count |
|--------|-------|
| **Total assets uploaded** | 10,608 |
| **Total data received by server** | ~351GB (includes retries) |
| **Library size on disk** | 254GB (up from 136GB baseline, +118GB net) |
| **Faces detected** | 4,062 |
| **Unique persons created** | 203 |
| **Videos transcoded** | 197 (100% success rate) |
| **VAAPI hardware encoded** | 177 (90%) |
| **Software fallback encoded** | 20 (10%) |
| **ECONNRESET errors** | 97 |
| **Duplicate upload rejections** | 8,725 |
| **Failed ML jobs** | 10 (7 thumbnail, 2 face, 1 OCR) |
| **Unsupported files** | 3 (.jfif format) |
| **Circuit breaker trips** | 6+ events across 3 hours |
| **Upload duration** | ~4 hours (20:57 → ~02:50) |

---

## Resource Utilization

### Peak vs Baseline (All 4 Containers)

| Container | Baseline CPU | Peak CPU | Baseline RAM | Peak RAM | Limit |
|-----------|-------------|----------|-------------|----------|-------|
| immich-server | 1.5% | **317%** | 457MB | **3.85GB** | 4G |
| immich-ml | 1.5% | **174%** | 249MB | **1.4GB** | 4G |
| postgresql-immich | 0.3% | **0.5%** | 60MB | **475MB** | 1G |
| redis-immich | 0.2% | **0.3%** | 14MB | **25MB** | 512M |

### Observations

- **immich-server** approached the 3.6GB `MemoryHigh` soft limit during peak processing but never hit the 4G hard cap. Systemd cgroup pressure likely slowed processing slightly.
- **immich-ml** peaked at 1.4GB when all models were loaded (CLIP, buffalo_l face detection/recognition, PP-OCRv5). Comfortable headroom within 4G limit.
- **PostgreSQL** tripled its memory usage (60MB → 475MB) handling metadata inserts for 10,608 assets. Still within limits.
- **Redis** stayed minimal throughout -- its role is session/cache, not bulk data.

### Storage Impact

| Location | Before | After | Delta |
|----------|--------|-------|-------|
| Immich library | 136GB | 254GB | **+118GB** |
| BTRFS pool free | 3.82TiB | 3.67TiB | -150GB (includes transcoded video copies) |
| System SSD | Unchanged | Unchanged | 0 |

---

## Configuration Changes Applied

### Permanent: Traefik Upload Timeouts (`config/traefik/traefik.yml`)

```yaml
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 600s
        writeTimeout: 600s
        idleTimeout: 180s
```

**Rationale:** Default 60s readTimeout proved too short for large video uploads. 600s (10 minutes) accommodates files up to several GB even at reduced transfer speeds.

### Permanent: Immich Version Update (`quadlets/immich-server.container`, `quadlets/immich-ml.container`)

- `ghcr.io/immich-app/immich-server:v2.5.2` → `v2.5.5`
- `ghcr.io/immich-app/immich-machine-learning:v2.5.2` → `v2.5.5`

### Temporary (Reverted): Circuit Breaker Disable

Circuit breaker was removed from Immich route during upload and re-enabled after completion. The global circuit breaker thresholds remain unchanged but should be revisited (see Open Items).

---

## Open Items

### Immediate

1. **Server processing backlog** -- immich-server was at 254% CPU and "unhealthy" (healthcheck timeout) when upload completed. Processing queue (thumbnails, ML, transcoding) will take time to drain. Monitor until health returns to normal.

2. **Cross-device sync verification** -- Upload was from iPhone only. Need to verify all 10,608 assets are visible on iPad Pro, Gaming PC browser, and Fedora HTPC browser.

### Configuration Improvements to Evaluate

3. **Circuit breaker for Immich** -- Current global thresholds (`NetworkErrorRatio() > 0.50`) are inappropriate for upload-heavy services. Consider: (a) removing from Immich route, (b) Immich-specific breaker with `ResponseCodeRatio` only, or (c) higher thresholds.

4. **Retry middleware for Immich** -- The `retry@file` middleware attempts to replay failed uploads, which is impossible for streamed request bodies. Consider removing from Immich route or configuring `retryExpression` to exclude upload-size requests.

5. **immich-ml inactivity timeout** -- 300s timeout causes worker recycling during bursty workloads. Evaluate increasing to 600s or disabling. Trade-off: ~1.3GB persistent RAM usage.

6. **OpenVINO for immich-ml** -- ML currently runs on CPU only (`CPUExecutionProvider`). The AMD Ryzen 5600G's Radeon Vega iGPU could potentially accelerate ML inference via OpenVINO. Requires image variant `immich-machine-learning:v2.5.5-openvino` and `/dev/dri` device access. Note: OpenVINO primarily targets Intel GPUs; AMD ROCm would be the correct path for Radeon, but Vega iGPU support is limited. Research needed.

### Phases Remaining (from Phase 1 Journal)

7. **Phase 3: Cross-device sync** -- Upload on iPhone, verify on iPad/browser within 30 seconds
8. **Phase 4: Resilience testing** -- Container restart during operation, corrupt file handling, burst upload monitoring
9. **Phase 5: SLO validation** -- Wait 2-3 weeks for error budget to recover, validate with monthly SLO report
10. **Phase 6: Documentation finalization** -- This journal covers the bulk of it; consider Immich incident response runbook

---

## Gotchas Reference

1. **Traefik readTimeout default is 60s** (or behaves as such in v3.2). Always set explicit timeouts on entrypoints serving upload-heavy applications.

2. **Circuit breakers count client disconnections as network errors.** ECONNRESET from mobile clients inflates `NetworkErrorRatio()`, causing false trips. Use `ResponseCodeRatio` for upload-heavy services.

3. **Retry middleware cannot replay streamed uploads.** Large file uploads are consumed streams -- retrying sends an empty body. Only useful for small API requests.

4. **immich-ml unloads models after 300s of inactivity.** First request after recycling will fail. Immich's job queue retries automatically, but it causes transient errors in logs and SLO metrics.

5. **iPhone Live Photos upload as 2 files, display as 1 asset.** The backup screen file count will be higher than the asset count. The negative "remainder" display is an app bug.

6. **iCloud "Optimize Storage" throttles bulk backup.** The phone must download originals from Apple before uploading to Immich. Expect burst-then-stall patterns during large backups.

7. **Immich server healthcheck fails under heavy processing load.** The `/api/server/ping` endpoint times out when CPU is saturated (>250%). This is expected during bulk processing -- the server is working, not crashed. The healthcheck will recover once the queue drains.

8. **VAAPI transcoding silently falls back to software encoding.** Some codecs (mjpeg .MOV, non-standard mp4) are incompatible with hardware encoding. Immich handles this gracefully -- look for `"Retrying with VAAPI acceleration disabled"` in logs.

9. **`.jfif` files are not supported by Immich.** These JPEG variants will be permanently rejected. The app retries them indefinitely -- no way to mark as permanent failure from server side.

---

## Infrastructure Health After Upload

| Container | Health | CPU | Memory |
|-----------|--------|-----|--------|
| immich-server | Unhealthy (processing backlog) | 254% | 3.85GB / 4G |
| immich-ml | Healthy | 112% | 826MB / 4G |
| postgresql-immich | Healthy | 0.5% | 401MB / 1G |
| redis-immich | Healthy | 0.3% | 23MB / 512M |

**SLO Metrics:**
- Availability: 98.93% (climbing, Feb 2 incident rolling out)
- Upload success ratio: 1.0
- Error budget remaining: -1.14 (will turn positive in ~2 weeks)

**BTRFS Pool:** 3.67TiB free of 14.55TiB (74.8% used)
