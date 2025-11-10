# Day 4-5: Immich ML GPU Acceleration with AMD ROCm

**Date:** 2025-11-10
**Goal:** Enable AMD GPU acceleration for Immich machine learning
**Status:** Ready for deployment

---

## Summary

Transform Immich ML from CPU-only processing to GPU-accelerated performance using AMD ROCm. This provides 5-10x faster face detection, object recognition, and smart search while reducing CPU load.

**Changes:**
- ✅ GPU detection and prerequisite validation script
- ✅ ROCm-enabled immich-ml quadlet configuration
- ✅ Automated deployment script with rollback capability
- ✅ Performance monitoring and verification tools

**Expected Results:**
- ML processing: CPU-only → **GPU-accelerated (5-10x faster)**
- Face detection: ~1-2s/photo → **~0.1-0.2s/photo**
- CPU load during ML: High → **Minimal**
- Smart search indexing: Hours → **Minutes** for large libraries

---

## Prerequisites

Before deploying GPU acceleration, you need:

### Hardware Requirements

1. **AMD GPU** with ROCm support (check compatibility: https://rocm.docs.amd.com/)
2. **Disk space**: ~35GB for ROCm image (first pull only)
3. **RAM**: 4GB recommended for GPU-accelerated workloads

### Software Requirements

1. **ROCm drivers installed** (provides /dev/kfd device)
2. **User in render group**: `sudo usermod -aG render $USER` (then log out/in)
3. **Podman** with device passthrough support (already installed)

### Detection

Run the detection script to verify all prerequisites:

```bash
cd ~/containers
./scripts/detect-gpu-capabilities.sh
```

**Expected output:**
```
✓ AMD GPU detected
✓ DRI devices available
✓ KFD device available
✓ User in render group
✓ KFD device accessible
✓ Sufficient disk space

🎉 All prerequisites met! Ready for ROCm GPU acceleration
```

**If any checks fail**, the script will provide specific remediation steps.

---

## Deployment

### Quick Deployment (Automated)

```bash
cd ~/containers
./scripts/deploy-immich-gpu-acceleration.sh
```

This script will:
1. Validate GPU prerequisites
2. Backup current CPU-only configuration
3. Measure baseline CPU performance
4. Deploy ROCm-enabled quadlet
5. Pull ROCm image (~35GB, takes 10-15 minutes first time)
6. Verify GPU utilization
7. Provide performance monitoring guidance

### Manual Deployment

If you prefer manual deployment:

```bash
# 1. Backup current config
cp ~/.config/containers/systemd/immich-ml.container \
   ~/.config/containers/systemd/immich-ml.container.backup

# 2. Stop current service
systemctl --user stop immich-ml.service
podman rm -f immich-ml

# 3. Deploy ROCm quadlet
cp quadlets/immich-ml-rocm.container ~/.config/containers/systemd/immich-ml.container

# 4. Reload and start
systemctl --user daemon-reload
systemctl --user start immich-ml.service

# 5. Wait for health check (10 minutes)
watch systemctl --user status immich-ml.service
```

---

## Configuration Details

### ROCm Quadlet Changes

**Image:**
```ini
# Before (CPU-only):
Image=ghcr.io/immich-app/immich-machine-learning:release

# After (GPU-accelerated):
Image=ghcr.io/immich-app/immich-machine-learning:release-rocm
```

**GPU Device Access:**
```ini
# /dev/kfd - Kernel Fusion Driver (main compute interface)
# /dev/dri - Direct Rendering Infrastructure (GPU rendering)
AddDevice=/dev/kfd
AddDevice=/dev/dri

# Keep system groups for 'render' group access
GroupAdd=keep-groups
```

**Resource Limits:**
```ini
# Before (CPU-only):
MemoryMax=2G

# After (GPU-accelerated):
MemoryMax=4G  # Increased for GPU workloads
```

### GPU Architecture Workarounds

For certain AMD GPUs, you may need compatibility overrides:

**RDNA 3.5 GPUs (gfx1150/gfx1151):**
```ini
# Add to quadlet if needed:
Environment=HSA_OVERRIDE_GFX_VERSION=10.3.0
Environment=HSA_USE_SVM=0
```

**See:** https://github.com/immich-app/immich/issues/22874

---

## Verification

### Check Service Status

```bash
# Service status
systemctl --user status immich-ml.service

# Container logs
podman logs -f immich-ml

# Health check
podman healthcheck run immich-ml
```

### Verify GPU Access

```bash
# Check devices are accessible inside container
podman exec -it immich-ml ls -la /dev/kfd /dev/dri

# Expected output:
# /dev/kfd
# /dev/dri:
#   renderD128
#   card0
```

### Monitor GPU Utilization

**During ML processing** (upload photos to trigger):

```bash
# AMD GPU monitoring (requires debug access)
watch -n 1 cat /sys/kernel/debug/dri/0/amdgpu_pm_info

# Or with radeontop (if installed):
radeontop

# Or with rocm-smi (if ROCm tools installed on host):
watch -n 1 rocm-smi
```

**Expected behavior:**
- Idle: GPU power state low
- Processing: GPU power state increases, compute usage visible
- After 5 min idle: GPU returns to low power state

### Check ROCm Initialization

```bash
# Look for ROCm/HIP initialization in logs
podman logs immich-ml | grep -i -E "(rocm|hip|gpu|gfx)"

# Expected messages (when ML jobs run):
# "Detected gfx..."
# "HIP initialized"
# "Using device: ..."
```

---

## Performance Comparison

### Baseline Measurement (CPU-only)

Before GPU deployment, note:
1. Upload a test set of 10 photos
2. Check ML job queue processing time in Immich
3. Note CPU usage during processing: `htop`

Example baseline:
- Face detection: 1.5s per photo
- Object recognition: 0.8s per photo
- Total for 10 photos: ~23 seconds
- CPU usage: 400-600% (all cores)

### GPU Performance

After GPU deployment, upload same photo set:
- Face detection: ~0.15s per photo (10x faster)
- Object recognition: ~0.1s per photo (8x faster)
- Total for 10 photos: ~2.5 seconds
- CPU usage: 50-100% (mostly idle)
- GPU usage: Active during processing

**Real-world improvement:** Processing a library of 1,000 photos
- CPU-only: ~45 minutes
- GPU-accelerated: ~5 minutes

---

## Troubleshooting

### Service Won't Start

**Check:**
```bash
journalctl --user -u immich-ml.service -n 50
```

**Common issues:**
1. **"Permission denied /dev/kfd"**
   - Solution: Add user to render group, log out/in
   - `sudo usermod -aG render $USER`

2. **"Device not found"**
   - Solution: Install ROCm drivers
   - Fedora: `sudo dnf install rocm-opencl rocm-runtime`

3. **"Image pull failed"**
   - Solution: Check disk space (need 35GB+)
   - `df -h ~/.local/share/containers`

### GPU Not Being Used

**Symptoms:** Service runs but no GPU activity

**Check:**
1. Verify devices in container:
   ```bash
   podman exec -it immich-ml ls -la /dev/kfd /dev/dri
   ```

2. Upload photos to trigger ML processing
   - GPU won't activate until there's work to do

3. Check for ROCm errors in logs:
   ```bash
   podman logs immich-ml | grep -i error
   ```

### Performance Not Improved

**If ML processing is still slow:**

1. **Verify GPU is actually processing:**
   ```bash
   watch -n 1 cat /sys/kernel/debug/dri/0/amdgpu_pm_info
   ```
   Should show activity during photo uploads

2. **Check for fallback to CPU:**
   ```bash
   podman logs immich-ml | grep -i "falling back to cpu"
   ```

3. **Architecture compatibility:**
   - Some newer AMD GPUs need HSA overrides
   - See "GPU Architecture Workarounds" section above

### High GPU Power When Idle

**Expected behavior:** GPU may stay in high power state for ~5 minutes after ML processing completes, then automatically returns to low power.

**If persistent:** This is a known ROCm issue (see Immich docs). Not harmful, but uses more power.

---

## Rollback to CPU-Only

If you need to revert to CPU-only processing:

```bash
# Restore backup
cp ~/.config/containers/systemd/immich-ml.container.backup-TIMESTAMP \
   ~/.config/containers/systemd/immich-ml.container

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart immich-ml.service
```

Or re-deploy original CPU quadlet:

```bash
cp quadlets/immich-ml.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart immich-ml.service
```

---

## Architecture Decision

### Why ROCm?

**Alternatives considered:**
1. **CPU-only** (current state) - Slow but reliable
2. **NVIDIA CUDA** - Not applicable (AMD hardware)
3. **AMD ROCm** - Native AMD GPU acceleration

**Decision:** ROCm provides significant performance benefits for AMD hardware.

**Trade-offs:**
- ✅ 5-10x faster ML processing
- ✅ Reduced CPU load
- ✅ Better user experience (faster smart search)
- ⚠️ 35GB larger image size
- ⚠️ Requires ROCm driver setup
- ⚠️ Some GPU architectures need workarounds

**Verdict:** Benefits outweigh costs for homelabs with AMD GPUs.

---

## Security Considerations

**GPU device access:**
- `/dev/kfd` and `/dev/dri` are added to container
- Requires user in `render` group (standard for GPU access)
- No additional capabilities needed beyond existing setup

**Attack surface:**
- ROCm runtime adds complexity
- Container still runs rootless
- GPU devices are read/write but limited to compute/render operations
- No network exposure (internal photos network only)

**Risk:** Low - GPU access is standard for ML workloads

---

## References

- Immich ML Hardware Acceleration: https://immich.app/docs/features/ml-hardware-acceleration/
- ROCm Installation Guide: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/
- Known Issues (RDNA 3.5): https://github.com/immich-app/immich/issues/22874
- Podman GPU Passthrough: https://github.com/containers/podman/discussions/23655

---

## Success Criteria

After deployment, you should see:

- ✅ immich-ml.service: active (running)
- ✅ Health check: healthy
- ✅ GPU activity during ML processing
- ✅ 5-10x faster face detection and smart search
- ✅ Reduced CPU load during ML operations
- ✅ Snapshot showing immich-ml using 4G memory limit

---

**Force Multiplier Week Progress:**
- ✅ Day 1-2: AI Intelligence System Foundation
- ✅ Day 3: Complete the Foundation (100% coverage)
- 🔄 Day 4-5: Immich GPU Acceleration ← You are here
- 🔜 Day 6: Authelia SSO Part 1
- 🔜 Day 7: Public Portfolio Showcase
