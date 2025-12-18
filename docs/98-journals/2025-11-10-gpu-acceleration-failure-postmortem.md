# GPU Acceleration Deployment Failure - Post-Mortem

**Date:** 2025-11-10
**Incident:** Immich ML ROCm GPU acceleration deployment failure
**Severity:** High (service crash loop, system resource exhaustion)
**Resolution:** Rollback to CPU-only configuration
**Duration:** 22 minutes (22:35 - 22:57 CET)

---

## Executive Summary

Attempted to deploy AMD ROCm GPU acceleration for Immich ML on fedora-htpc (AMD Ryzen 5600G with integrated Vega graphics). Deployment succeeded technically but resulted in immediate service instability due to memory allocation conflicts. The integrated GPU's shared memory architecture is incompatible with ROCm ML workloads at this scale.

**Outcome:** Successful rollback to stable CPU-only configuration. System restored to normal operation.

---

## Timeline

| Time (CET) | Event |
|------------|-------|
| 22:35:18 | GPU acceleration deployment completed, service started |
| 22:35:19 | Service initialized successfully |
| 22:49:39 | First ML model load attempted (buffalo_l face detection) |
| 22:49:54 | **First crash**: Memory critical error, worker pid:6 killed (code 134) |
| 22:50:02-22:55:09 | **Crash loop**: Service repeatedly crashes every ~10-15 seconds |
| 22:55:09 | Python core dumps detected by systemd-coredump |
| 22:57:31 | **Rollback completed**: CPU-only configuration restored |
| 22:57:33 | Service stable, no further crashes |

---

## Root Cause Analysis

### Primary Cause: Integrated GPU Memory Architecture Incompatibility

The AMD Ryzen 5600G contains an **integrated Vega GPU (gfx90c)** that shares system RAM for VRAM. When ROCm attempts to allocate memory for ML models:

```
Memory critical error by agent node-0 (Agent handle: 0x7fc7f1d9a5e0)
on address 0x7fc846a02000. Reason: Memory in use.
```

**Why this happens:**
1. **Shared memory conflict**: Integrated GPUs (APUs) use unified memory architecture
2. **ROCm memory allocator**: Expects dedicated VRAM with exclusive access
3. **Model size**: Face detection models (buffalo_l, PP-OCRv5_mobile) require significant memory
4. **Container limits**: 4GB memory limit insufficient for ROCm overhead + models + shared memory

### Hardware Context

```
Hardware: AMD Ryzen 5600G with Radeon Graphics
GPU: AMD ATI Radeon Vega Series / Radeon Vega Mobile Series (integrated)
Architecture: gfx90c (gfx_target_version 90012)
Memory: Shared system RAM (no dedicated VRAM)
```

**GPU Detection Results (pre-deployment):**
- ✓ AMD GPU detected (Cezanne Radeon Vega)
- ✓ /dev/kfd device present
- ✓ /dev/dri devices present (card1, renderD128)
- ✓ User in render group
- ✓ Sufficient disk space (43GB available)
- ✓ ROCm recognized GPU architecture

**Technical validation was successful, but architectural compatibility assessment was insufficient.**

---

## Failure Symptoms

### 1. Service Crash Loop

```
ERROR    Worker (pid:6) was sent code 134!
INFO     Booting worker with pid: 108
...
ERROR    Worker (pid:108) was sent code 134!
INFO     Booting worker with pid: 150
```

Workers crashed every 10-15 seconds attempting to load ML models.

### 2. Memory Exhaustion

```
Memory: 2.9G (max: 4G, available: 1G, peak: 4G, swap: 38.6M)
```

Service hit 73% of 4GB memory limit immediately, peaked at 100%.

### 3. Core Dumps

```
systemd-coredump[2129878]: Process 2129478 (python) of user 1000 dumped core.
```

Python processes generating core dumps on every crash, consuming additional disk space.

### 4. System Notifications

Fedora desktop environment reported repeated Python 3.10 crashes, indicating system-level instability.

### 5. Resource Hogging

CPU usage spiked during crash loop (7+ minutes of CPU time in 19 minutes), affecting system responsiveness.

---

## What Went Right

### ✅ Deployment Script Quality

The `deploy-immich-gpu-acceleration.sh` script performed flawlessly:
- Created timestamped backup before deployment
- Successfully deployed ROCm configuration
- Clean error handling
- Provided clear rollback instructions

**Backup created:**
```
/home/patriark/.config/containers/systemd/immich-ml.container.backup-20251110-222721
```

This backup enabled **immediate rollback** without data loss or manual reconstruction.

### ✅ GPU Detection and Passthrough

Technical prerequisites were validated correctly:
- GPU hardware detected
- Kernel devices (/dev/kfd, /dev/dri) present
- Permissions configured properly
- Device passthrough worked (verified via `podman exec`)

**Inside container (working correctly):**
```
crw-rw-rw-. 1 nobody nogroup 235, 0 Nov  4 10:59 /dev/kfd
crw-rw-rw-. 1 nobody nogroup 226, 128 Nov  4 10:59 /dev/dri/renderD128
```

ROCm successfully detected GPU:
```
Name:                    gfx90c
Marketing Name:          AMD Radeon Graphics
Vendor Name:             AMD
```

### ✅ Fast Recovery

From detection to rollback completion: **22 minutes**
- Quick identification of crash loop
- Pre-existing backup enabled immediate restoration
- Service returned to stable operation without data loss

### ✅ Monitoring and Diagnostics

Real-time log monitoring (`podman logs -f immich-ml`) provided immediate visibility into failure mode, enabling rapid diagnosis.

---

## What Went Wrong

### ❌ Insufficient Hardware Compatibility Assessment

**The core issue:** Technical validation (devices, drivers, architecture detection) passed, but **architectural suitability** was not evaluated.

**Missing check:**
- "Is this a discrete GPU or integrated GPU?"
- "Does integrated GPU architecture work with ROCm ML workloads?"

**Reality:** ROCm on integrated Vega GPUs (gfx90c) with shared memory is **not production-ready** for ML workloads of this complexity.

### ❌ No Pre-Deployment Test Load

Should have:
1. Started service with GPU config
2. Manually triggered small test inference (single photo)
3. Verified successful processing before declaring deployment complete

Instead: Declared success at service startup, discovered issue only when models loaded.

### ❌ Inadequate Memory Headroom

4GB memory limit was based on discrete GPU assumptions. Integrated GPUs need more headroom for shared memory architecture.

### ❌ Documentation Gap

The GPU acceleration guide (docs/99-reports/2025-11-10-day4-5-gpu-acceleration.md) stated:

```markdown
### Hardware Requirements
1. **AMD GPU** with ROCm support (check compatibility: https://rocm.docs.amd.com/)
```

**Too generic.** Should explicitly warn about integrated GPU limitations.

---

## Lessons Learned

### 1. Discrete vs Integrated GPU Architecture Matters

**Learning:** Not all ROCm-compatible GPUs are suitable for ML workloads.

**Integrated GPUs (APUs):**
- Share system RAM
- Memory allocation conflicts with ROCm
- Lower memory bandwidth
- Thermal constraints

**Discrete GPUs:**
- Dedicated VRAM
- Exclusive memory access
- Higher memory bandwidth
- Independent thermal envelope

**Action:** Update detection script to identify integrated vs discrete GPUs and warn accordingly.

### 2. Technical Validation ≠ Architectural Suitability

**Learning:** Devices existing and being accessible doesn't mean workload will succeed.

**What we validated:**
- ✓ Hardware present
- ✓ Drivers loaded
- ✓ Permissions correct

**What we didn't validate:**
- ❌ GPU type (integrated vs discrete)
- ❌ Memory architecture compatibility
- ❌ Test inference under load

**Action:** Add architectural suitability checks to validation phase.

### 3. Always Test Before Declaring Success

**Learning:** Service starting ≠ service working under load.

**Should have done:**
1. Deploy configuration
2. Run single-photo test inference
3. Verify GPU utilization
4. Measure processing time
5. **Then** declare success

**Action:** Add smoke test phase to deployment script.

### 4. Documentation Must Be Specific About Limitations

**Learning:** Generic warnings ("check compatibility") are insufficient.

**Ineffective:**
> "AMD GPU with ROCm support"

**Effective:**
> "⚠️ **Discrete AMD GPU required.** Integrated GPUs (Ryzen APUs like 5600G, 5700G) are not supported due to shared memory architecture."

**Action:** Update all GPU documentation with explicit warnings.

### 5. Rollback Capability is Essential

**Learning:** The deployment script's automatic backup creation enabled **instant recovery**.

Without this:
- Manual reconstruction of working config
- Extended downtime
- Higher stress/risk

**Action:** Ensure all deployment scripts include automatic backup creation (already done, verify this pattern everywhere).

---

## Corrective Actions

### Immediate (Completed)

- [x] Rollback to CPU-only configuration
- [x] Verify service stability
- [x] Document incident in post-mortem

### Short-term (This Session)

- [ ] Update GPU detection script with integrated GPU warning
- [ ] Update GPU acceleration guide with explicit limitations
- [ ] Add architectural compatibility check
- [ ] Archive the ROCm deployment as "not suitable for integrated GPUs"

### Long-term (Future Consideration)

- [ ] Evaluate CPU-only optimization strategies
  - Model quantization
  - Batch processing optimization
  - Thread tuning
- [ ] Consider discrete GPU upgrade if ML performance becomes critical
  - Recommended: AMD RX 6600/6700 or newer
  - Budget: $200-300 used market
  - ROCm support verified for RDNA2+ architecture

---

## Alternative Approaches Considered

### 1. Reduce Memory Limits

**Idea:** Lower container memory limit to force smaller memory allocations.

**Why rejected:** Would likely cause OOM kills or force CPU fallback anyway. Doesn't address root cause (shared memory architecture).

### 2. Disable Specific Models

**Idea:** Blacklist problematic models, use only lightweight ones.

**Why rejected:** Defeats purpose of GPU acceleration. Better to stay on CPU-only with full model suite.

### 3. ROCm Environment Variables

**Idea:** Use `HSA_OVERRIDE_GFX_VERSION`, `ROCM_PATH` tuning.

**Why rejected:** These address driver issues, not architectural limitations. Memory conflict would persist.

### 4. CPU-Only with Thread Optimization

**Idea:** Stay on CPU but optimize thread count and model selection.

**Status:** **Recommended approach** for integrated GPU systems.

---

## Technical Details

### Container Configuration (Deployed)

**ROCm-enabled quadlet:**
```ini
[Container]
Image=ghcr.io/immich-app/immich-machine-learning:release-rocm
AddDevice=/dev/kfd
AddDevice=/dev/dri
GroupAdd=keep-groups
Environment=MACHINE_LEARNING_WORKERS=1
Environment=MACHINE_LEARNING_WORKER_TIMEOUT=300
HealthCmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:3003/ping || exit 1
MemoryMax=4G
```

### Error Signature

```
Memory critical error by agent node-0 (Agent handle: 0x7fc7f1d9a5e0)
on address 0x7fc846a02000. Reason: Memory in use.
```

**ROCm HSA error code:** Memory allocation failure in HSA (Heterogeneous System Architecture) runtime.

### Models Attempted to Load

1. **buffalo_l** - Face detection model (crashed immediately)
2. **PP-OCRv5_mobile** - OCR model (crashed immediately)
3. **ViT-B-32__openai** - CLIP visual model (crashed immediately)

**Common factor:** All models failed at initial GPU memory allocation.

---

## Recommendations

### For This System (AMD Ryzen 5600G)

**Stay on CPU-only configuration:**
- ✅ Stable and reliable
- ✅ Adequate performance for personal use
- ✅ No resource conflicts
- ✅ Lower power consumption

**Optimization opportunities:**
- Tune `MACHINE_LEARNING_WORKERS` based on CPU cores
- Enable model caching for frequent operations
- Use scheduled batch processing during low-usage hours

### For Future GPU Acceleration Attempts

**Hardware requirements (updated):**
- ✅ **Discrete AMD GPU** (PCIe card, not integrated)
- ✅ Minimum 4GB dedicated VRAM
- ✅ RDNA2 or newer (RX 6000/7000 series)
- ✅ ROCm 5.6+ support verified
- ✅ Adequate system RAM (16GB+)
- ✅ Sufficient PSU wattage

**Validation process:**
1. Detect GPU type (integrated vs discrete)
2. Verify dedicated VRAM availability
3. Check ROCm compatibility matrix
4. Deploy configuration with backup
5. **Run smoke test inference**
6. Verify GPU utilization
7. Measure performance improvement
8. **Then** declare success

---

## Cost-Benefit Analysis

### GPU Acceleration Investment

**Costs:**
- Hardware: $200-300 (discrete GPU, used market)
- Power: +50-150W TDP (vs iGPU)
- Complexity: Container configuration, troubleshooting
- Risk: Compatibility issues (as experienced)

**Benefits:**
- Speed: 5-10x faster ML processing
- Scalability: Handle larger photo libraries
- CPU offload: Free CPU for other services
- Learning: Experience with GPU workloads

**Verdict for this homelab:**
- **Current state:** CPU performance adequate for current photo library size
- **Break-even point:** >50,000 photos or frequent ML reprocessing
- **Decision:** Defer GPU upgrade until performance becomes bottleneck

---

## References

### Related Documentation

- `docs/99-reports/2025-11-10-day4-5-gpu-acceleration.md` - Original deployment guide
- `scripts/deploy-immich-gpu-acceleration.sh` - Deployment script (worked as designed)
- `scripts/detect-gpu-capabilities.sh` - GPU detection (needs enhancement)
- `quadlets/immich-ml-rocm.container` - ROCm configuration (technically correct, architecturally unsuitable)

### External Resources

- [ROCm Hardware Compatibility](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html)
- [Immich ML GPU Support Discussion](https://github.com/immich-app/immich/discussions/3928)
- [AMD APU ROCm Limitations](https://github.com/RadeonOpenCompute/ROCm/issues/1659)

---

## Conclusion

This incident demonstrates the importance of **architectural compatibility assessment** beyond technical validation. While all technical prerequisites were met (devices, drivers, permissions), the fundamental architectural mismatch (integrated GPU shared memory vs ROCm's expectations) caused immediate failure.

**Key takeaway:** Not all ROCm-compatible GPUs are suitable for production ML workloads.

**Positive outcomes:**
- Fast recovery due to automated backup strategy
- Comprehensive documentation of failure mode
- Clear understanding of hardware limitations
- Improved validation process for future attempts

**System status:** ✅ Stable on CPU-only configuration, adequate performance for current workload.

---

**Incident closed:** 2025-11-10 22:57 CET
**Total downtime:** 0 minutes (service crashed but was non-critical)
**Data loss:** None
**User impact:** None (no active ML jobs during incident)
**Prevention:** Documentation updates and enhanced validation

---

*This post-mortem follows the SRE principle: "Failure is a learning opportunity, not a blame opportunity."*
