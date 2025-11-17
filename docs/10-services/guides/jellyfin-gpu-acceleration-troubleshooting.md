# Jellyfin GPU Acceleration Troubleshooting Guide

**Hardware:** AMD Ryzen 5 5600G (APU with integrated Radeon Vega Graphics)
**OS:** Fedora Workstation 42
**Container Runtime:** Podman (rootless)
**Current Status:** Configuration exists, verification needed
**Created:** 2025-11-17

---

## Executive Summary

This guide provides a systematic approach to troubleshooting and enabling GPU-accelerated transcoding for Jellyfin on an AMD APU system running rootless Podman containers.

**Current Configuration Status:**
- ✅ Quadlet has `AddDevice=/dev/dri/renderD128` configured (line 19 of `quadlets/jellyfin.container`)
- ❓ GPU driver installation and initialization needs verification
- ❓ VA-API functionality needs testing
- ❓ Jellyfin GPU transcoding needs validation

**Key Challenges with APU vs Discrete GPU:**
- APU shares memory with system (no dedicated VRAM)
- Driver naming may differ (amdgpu vs radeon)
- Render node may have different numbering
- Performance characteristics differ from discrete GPUs

---

## Phase 1: System-Level GPU Verification

### Step 1.1: Verify GPU Hardware Detection

**Objective:** Confirm the kernel detects the AMD APU graphics

```bash
# Check PCI devices for AMD graphics
lspci | grep -i vga
# Expected output: AMD/ATI Renoir [Radeon Vega Series]

# Verify AMD GPU driver loaded
lsmod | grep amdgpu
# Expected: amdgpu module loaded with dependencies

# Check kernel messages for GPU initialization
dmesg | grep -i amdgpu | tail -20
# Look for: "amdgpu 0000:XX:XX.X: ring gfx initialized"
```

**Success Criteria:**
- ✅ GPU appears in `lspci` output
- ✅ `amdgpu` kernel module is loaded
- ✅ No error messages in dmesg about GPU initialization

**Common Issues:**

| Issue | Symptoms | Solution |
|-------|----------|----------|
| No GPU in lspci | Command shows no VGA controller | Check BIOS settings, ensure iGPU is enabled |
| Module not loaded | `lsmod` shows no amdgpu | Install `amdgpu` driver package (see Step 1.2) |
| Driver errors in dmesg | "failed to initialize" messages | Check for firmware issues, update kernel |

### Step 1.2: Install Required Mesa/VAAPI Packages

**Objective:** Ensure all required graphics drivers and VA-API libraries are installed

```bash
# Install Mesa drivers for AMD (if not already installed)
sudo dnf install -y \
    mesa-dri-drivers \
    mesa-va-drivers \
    mesa-vdpau-drivers \
    libva \
    libva-utils \
    libva-vdpau-driver \
    libdrm

# For AMD specifically
sudo dnf install -y \
    mesa-amdgpu-va-drivers

# Verify installation
rpm -qa | grep -E '(mesa|libva|amdgpu)'
```

**Fedora 42 Specific Notes:**
- Mesa packages are typically installed by default on Workstation
- `mesa-amdgpu-va-drivers` may have been replaced by unified `mesa-va-drivers`
- Check DNF for exact package names: `dnf search mesa | grep -i va`

**Success Criteria:**
- ✅ All packages installed without errors
- ✅ `rpm -qa` shows mesa-va-drivers and libva packages

### Step 1.3: Verify DRI Device Nodes Exist

**Objective:** Confirm `/dev/dri/` directory exists with proper render nodes

```bash
# List DRI devices
ls -la /dev/dri/
# Expected output:
# drwxr-xr-x. root root   /dev/dri/
# crw-rw----+ root video  /dev/dri/card0
# crw-rw-rw-+ root render /dev/dri/renderD128

# Check your user is in the 'render' group
groups | grep render
# Or check group membership
id | grep render

# If not in render group, add yourself
sudo usermod -aG render $USER
# NOTE: Requires logout/login to take effect
```

**APU-Specific Considerations:**
- APUs typically create `/dev/dri/card0` (primary display)
- Render node is usually `/dev/dri/renderD128` (for compute/transcoding)
- On some systems, APU might create `renderD129` instead - verify actual device

**Success Criteria:**
- ✅ `/dev/dri/` directory exists
- ✅ At least one `renderD*` device present
- ✅ User is member of `render` group (or device has appropriate permissions)

**Troubleshooting:**

```bash
# If /dev/dri/ doesn't exist
sudo modprobe amdgpu  # Manually load driver
udevadm trigger       # Trigger device creation

# If permissions are wrong
sudo chmod 666 /dev/dri/renderD128  # Temporary fix (lost on reboot)
# Permanent: Create udev rule
sudo tee /etc/udev/rules.d/70-amdgpu.rules <<EOF
KERNEL=="renderD*", GROUP="render", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Step 1.4: Test VA-API Functionality

**Objective:** Verify VA-API can access the GPU before involving containers

```bash
# Set VA-API driver (AMD uses 'radeonsi' or 'amdgpu' depending on GPU generation)
export LIBVA_DRIVER_NAME=radeonsi

# Test VA-API
vainfo
# Expected output:
# libva info: VA-API version 1.X.X
# libva info: Trying to open /usr/lib64/dri/radeonsi_drv_video.so
# libva info: Found init function __vaDriverInit_1_X
# libva info: va_openDriver() returns 0
# vainfo: VA-API version: 1.X (libva X.X.X)
# vainfo: Driver version: Mesa Gallium driver XX.X.X
# vainfo: Supported profile and entrypoints
#     VAProfileH264Main: VAEntrypointVLD
#     VAProfileH264High: VAEntrypointVLD
#     VAProfileHEVCMain: VAEntrypointVLD
# ...
```

**Interpreting vainfo output:**
- **Success:** Lists supported profiles (H264, HEVC, VP9) with VAEntrypointVLD and VAEntrypointEncSlice
- **Failure:** "vaInitialize failed" or "failed to open driver"

**Common Issues:**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "cannot open shared object file" | VA-API library not installed | `dnf install libva-utils mesa-va-drivers` |
| "failed to open /dev/dri/renderD128" | Permission denied | Add user to `render` group |
| "unknown libva driver name" | Wrong driver specified | Try `export LIBVA_DRIVER_NAME=amdgpu` or remove export |
| "vaInitialize failed with error code -1" | Driver mismatch | Update mesa packages |

**Vega APU Specific Notes:**
- Renoir/Cezanne APUs (Ryzen 5000 series) use `radeonsi` driver
- Some documentation mentions `amdgpu` - both may work
- If `radeonsi` fails, try: `export LIBVA_DRIVER_NAME=amdgpu && vainfo`

**Success Criteria:**
- ✅ `vainfo` runs without errors
- ✅ Shows H264, HEVC encoding capabilities (VAEntrypointEncSlice)
- ✅ Shows decoding capabilities (VAEntrypointVLD)

---

## Phase 2: Podman/Container GPU Access

### Step 2.1: Verify Rootless Podman Can Access DRI

**Objective:** Test that rootless Podman containers can access GPU devices

```bash
# Simple test: Run container with GPU device
podman run --rm \
  --device /dev/dri/renderD128 \
  --device /dev/dri/card0 \
  docker.io/jrottenberg/ffmpeg:latest \
  -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccels

# Expected output: Should list 'vaapi' as available hardware accelerator

# Test VA-API inside container
podman run --rm \
  --device /dev/dri/renderD128 \
  --device /dev/dri/card0 \
  -e LIBVA_DRIVER_NAME=radeonsi \
  docker.io/linuxserver/jellyfin:latest \
  vainfo

# Should show same VA-API profiles as host test
```

**Rootless Container Considerations:**
- Rootless containers run as your UID (1000)
- Device permissions must allow your user to access `/dev/dri/*`
- SELinux may block device access even with correct UNIX permissions

**Success Criteria:**
- ✅ Container can list VA-API as available accelerator
- ✅ `vainfo` works inside container
- ✅ No "permission denied" errors

### Step 2.2: Check SELinux Context for DRI Devices

**Objective:** Verify SELinux allows container access to GPU

```bash
# Check SELinux context of DRI devices
ls -lZ /dev/dri/
# Expected: system_u:object_r:dri_device_t:s0

# Check for SELinux denials related to DRI
sudo ausearch -m avc -ts recent | grep dri
# Or check audit log
sudo journalctl -t setroubleshoot --since "1 hour ago"

# If denials found, check if container_t can access dri_device_t
sesearch -A -s container_t -t dri_device_t -c chr_file
```

**Fedora SELinux Policy:**
- By default, `container_t` should have access to `dri_device_t`
- Podman's SELinux policy includes GPU access rules
- If using custom SELinux policies, this may break

**Troubleshooting SELinux Issues:**

```bash
# Temporarily set SELinux to permissive (for testing only)
sudo setenforce 0

# Test container GPU access again
podman run --rm --device /dev/dri/renderD128 docker.io/jrottenberg/ffmpeg:latest -hwaccels

# If it works now, SELinux is the issue
# Re-enable enforcing
sudo setenforce 1

# Create custom SELinux policy (if needed)
# This is rarely necessary on Fedora - file a bug if you hit this
sudo setsebool -P container_use_devices=1
```

**Success Criteria:**
- ✅ No SELinux AVC denials in audit log
- ✅ Container can access `/dev/dri/renderD128` with SELinux enforcing
- ✅ `ls -lZ` shows correct SELinux context on devices

### Step 2.3: Update Jellyfin Quadlet (if needed)

**Objective:** Ensure quadlet has correct device mappings for APU

**Current Configuration:**
```ini
# From quadlets/jellyfin.container line 19
AddDevice=/dev/dri/renderD128
```

**Recommended Configuration for APU:**
```ini
# Add both card0 (display) and renderD128 (compute)
AddDevice=/dev/dri/card0
AddDevice=/dev/dri/renderD128

# Alternative: Pass entire /dev/dri directory (less secure but more flexible)
# AddDevice=/dev/dri
```

**Why add card0 for APU?**
- Some VA-API implementations require display device access
- APU integrates display and compute functions
- More likely to work across different Mesa versions
- Minimal security impact (container still rootless)

**Apply Changes:**
```bash
# Edit quadlet
nano ~/.config/containers/systemd/jellyfin.container

# Add line after existing AddDevice:
# AddDevice=/dev/dri/card0

# Reload systemd
systemctl --user daemon-reload

# Restart Jellyfin
systemctl --user restart jellyfin.service

# Verify container has both devices
podman exec jellyfin ls -la /dev/dri/
```

**Success Criteria:**
- ✅ Quadlet includes both `/dev/dri/card0` and `/dev/dri/renderD128`
- ✅ Service restarts successfully
- ✅ Devices visible inside container: `podman exec jellyfin ls /dev/dri/`

---

## Phase 3: Jellyfin Configuration

### Step 3.1: Enable Hardware Transcoding in Jellyfin

**Objective:** Configure Jellyfin to use VA-API for transcoding

**Steps:**

1. **Access Jellyfin Dashboard:**
   - Navigate to: https://jellyfin.patriark.org
   - Login as administrator
   - Go to: Dashboard → Playback

2. **Configure Hardware Acceleration:**
   ```
   Transcoding Section:
   ┌─────────────────────────────────────────────────┐
   │ Hardware acceleration: Video Acceleration API   │
   │                        (VA-API)            [▼]  │
   ├─────────────────────────────────────────────────┤
   │ VA-API Device: /dev/dri/renderD128              │
   ├─────────────────────────────────────────────────┤
   │ ☑ Enable hardware decoding for:                │
   │   ☑ H264                                        │
   │   ☑ HEVC                                        │
   │   ☑ HEVC 10bit                                  │
   │   ☑ VP9                                         │
   │   ☑ VP9 10bit                                   │
   ├─────────────────────────────────────────────────┤
   │ ☑ Enable hardware encoding                     │
   │   Encoding preset: [Speed]              [▼]     │
   │   ☐ Enable VPP Tone mapping              │
   │   ☐ Enable Dolby Vision hw decoding            │
   └─────────────────────────────────────────────────┘
   ```

3. **Advanced Settings (Optional):**
   - H264 encoding CRF: 23 (default, lower = better quality)
   - HEVC encoding CRF: 28 (default)
   - Encoding preset: "Speed" for real-time, "Balanced" for quality
   - Thread count: 0 (auto-detect)

4. **Save Configuration**

**AMD Vega APU Capabilities:**
- ✅ H.264 decode/encode up to 4K@60fps
- ✅ H.265/HEVC decode/encode up to 4K@60fps
- ✅ VP9 decode (encoding support varies)
- ❌ AV1 decode/encode (not supported on Vega)
- ⚠️ 10-bit HEVC: Decode yes, encode may be limited

**Success Criteria:**
- ✅ VA-API selected as hardware acceleration
- ✅ Device set to `/dev/dri/renderD128`
- ✅ Hardware decoding enabled for H264/HEVC
- ✅ Hardware encoding enabled
- ✅ Configuration saves without errors

### Step 3.2: Verify Jellyfin Logs for VA-API Initialization

**Objective:** Confirm Jellyfin successfully initializes VA-API

```bash
# Check Jellyfin container logs for VA-API messages
podman logs jellyfin 2>&1 | grep -i -E '(vaapi|hardware|ffmpeg)'

# Look for successful initialization
# Expected messages:
# [INF] FFmpeg: Hardware acceleration type vaapi
# [INF] FFmpeg: Codec h264_vaapi initialized

# Check for errors
podman logs jellyfin 2>&1 | grep -i -E '(error|fail|warn)' | grep -i vaapi

# If errors, check ffmpeg-transcode logs specifically
podman exec jellyfin cat /config/log/ffmpeg-transcode-*.txt | tail -50
```

**Successful Initialization Indicators:**
- Log messages mention "vaapi" without errors
- FFmpeg codec initialization succeeds
- No "failed to open device" errors

**Common Error Messages:**

| Error | Cause | Solution |
|-------|-------|----------|
| "Cannot load libva-amd.so" | Missing VA-API driver in container | Use jellyfin/jellyfin:latest (includes drivers) |
| "Failed to initialize VAAPI" | Device not accessible | Check container has /dev/dri/ devices |
| "No VA display found" | Wrong device specified | Try /dev/dri/card0 instead of renderD128 |
| "Codec not found" | Unsupported codec for hardware | Check vainfo for supported profiles |

**Success Criteria:**
- ✅ No VA-API errors in logs
- ✅ FFmpeg shows successful codec initialization
- ✅ Transcoding logs reference hardware acceleration

---

## Phase 4: Transcoding Validation

### Step 4.1: Test Transcoding with Sample Video

**Objective:** Verify GPU is actually being used during transcoding

**Test Procedure:**

1. **Start a video playback requiring transcoding:**
   - Use Jellyfin web interface
   - Select a 4K HEVC video (if available)
   - Force transcoding: Settings → Quality → Lower quality than original

2. **Monitor GPU utilization during playback:**
   ```bash
   # Install radeontop if not present
   sudo dnf install radeontop

   # Monitor GPU usage in real-time
   radeontop

   # Expected during transcoding:
   # Video Engine (VCE): 40-80% utilization
   # Graphics Pipe: Low (<10%)
   #
   # If GPU not used:
   # All utilization stays at 0-5%
   ```

3. **Monitor CPU utilization:**
   ```bash
   htop

   # With GPU transcoding: CPU usage 5-15%
   # Without GPU transcoding: CPU usage 80-300% (multiple cores maxed)
   ```

4. **Check Jellyfin Activity Dashboard:**
   - Go to: Dashboard → Activity
   - Look at active stream details
   - Should show: "Transcode Reason: VideoCodecNotSupported"
   - Method should indicate hardware acceleration

**Success Indicators:**

| Metric | GPU Transcoding | CPU Transcoding |
|--------|----------------|-----------------|
| `radeontop` VCE usage | 40-80% | 0-5% |
| CPU usage (htop) | 5-15% | 80-300% |
| Transcode speed | 1.5-3.0x realtime | 0.5-1.2x realtime |
| Transcode start delay | <2 seconds | 5-10 seconds |
| System responsiveness | No lag | Noticeable lag |

**Success Criteria:**
- ✅ `radeontop` shows VCE/Video Engine utilization
- ✅ CPU usage remains low during transcoding
- ✅ Playback starts quickly without buffering
- ✅ Can play multiple streams simultaneously

### Step 4.2: Verify FFmpeg Command Line

**Objective:** Confirm Jellyfin is passing correct VA-API flags to FFmpeg

```bash
# During active transcoding, check running ffmpeg processes
podman exec jellyfin ps aux | grep ffmpeg

# Look for VA-API specific flags:
# -hwaccel vaapi
# -hwaccel_device /dev/dri/renderD128
# -c:v h264_vaapi (or hevc_vaapi)

# Example expected command:
# /usr/lib/jellyfin-ffmpeg/ffmpeg -hwaccel vaapi \
#   -hwaccel_device /dev/dri/renderD128 \
#   -i /media/video.mkv \
#   -c:v h264_vaapi -preset fast \
#   -c:a aac -ac 2 /config/transcodes/output.m3u8

# Check detailed transcoding logs
podman exec jellyfin ls -lt /config/log/ | head -5
podman exec jellyfin cat /config/log/ffmpeg-transcode-*.txt | tail -100
```

**Correct VA-API FFmpeg Flags:**
- `-hwaccel vaapi` - Enable VA-API acceleration
- `-hwaccel_device /dev/dri/renderD128` - Specify render node
- `-hwaccel_output_format vaapi` - Keep frames in GPU memory
- `-c:v h264_vaapi` or `-c:v hevc_vaapi` - Hardware encoder
- `-init_hw_device vaapi=va:/dev/dri/renderD128` - Alternative initialization

**If CPU transcoding is being used instead:**
- FFmpeg command will show `-c:v libx264` (software encoder)
- No `-hwaccel` flags present
- Fallback to software usually indicates initialization failure

**Success Criteria:**
- ✅ FFmpeg command includes `-hwaccel vaapi`
- ✅ Hardware encoder specified: `h264_vaapi` or `hevc_vaapi`
- ✅ Correct device path: `/dev/dri/renderD128`

### Step 4.3: Benchmark Transcoding Performance

**Objective:** Quantify transcoding performance improvement

```bash
# Create a test transcoding script
cat > /tmp/test-transcode.sh << 'EOF'
#!/bin/bash
echo "Testing CPU transcoding..."
time podman exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg \
  -i /media/multimedia/test-video.mkv \
  -t 60 -c:v libx264 -preset fast -f null -

echo "Testing GPU transcoding..."
time podman exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg \
  -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -i /media/multimedia/test-video.mkv \
  -t 60 -c:v h264_vaapi -f null -
EOF

chmod +x /tmp/test-transcode.sh
/tmp/test-transcode.sh

# Compare "real" time from output
# GPU should be 2-5x faster than CPU for this APU
```

**Expected Performance (Ryzen 5 5600G):**
- **1080p H264 → H264:** GPU 3-4x realtime, CPU 1-2x realtime
- **4K H265 → 1080p H264:** GPU 1.5-2x realtime, CPU 0.3-0.8x realtime
- **Multiple streams:** GPU handles 3-4 concurrent, CPU struggles with 2

**Success Criteria:**
- ✅ GPU transcoding significantly faster than CPU (2x minimum)
- ✅ GPU transcoding achieves >1.0x realtime for typical workloads
- ✅ System remains responsive during GPU transcoding

---

## Phase 5: Troubleshooting Common Issues

### Issue 1: "Failed to initialize VAAPI"

**Symptoms:**
- Jellyfin logs show VA-API initialization failure
- Transcoding falls back to CPU (libx264)
- `radeontop` shows 0% usage during transcoding

**Diagnosis:**
```bash
# Test VA-API inside container
podman exec jellyfin vainfo

# Check device permissions
podman exec jellyfin ls -la /dev/dri/

# Verify container has devices mapped
podman inspect jellyfin | grep -A 5 Devices
```

**Solutions:**

1. **Device not mapped to container:**
   ```bash
   # Add to quadlet
   nano ~/.config/containers/systemd/jellyfin.container
   # Add: AddDevice=/dev/dri/card0
   #      AddDevice=/dev/dri/renderD128
   systemctl --user daemon-reload
   systemctl --user restart jellyfin.service
   ```

2. **Wrong device specified in Jellyfin:**
   - Dashboard → Playback → VA-API Device
   - Try `/dev/dri/card0` instead of `/dev/dri/renderD128`
   - Or try `/dev/dri/by-path/...` (use tab completion)

3. **VA-API driver not in container:**
   ```bash
   # Verify container has VA-API libraries
   podman exec jellyfin ls /usr/lib64/dri/ | grep radeonsi
   # Should show: radeonsi_drv_video.so

   # If missing, wrong container image
   # Ensure using: jellyfin/jellyfin:latest (official image includes drivers)
   ```

### Issue 2: Transcoding Works But Very Slow

**Symptoms:**
- GPU utilization shows in `radeontop`
- But transcoding speed <1.0x realtime
- Frequent buffering during playback

**Diagnosis:**
```bash
# Check if APU is thermal throttling
sensors | grep -i temp
# CPU temps should be <80°C under load

# Check memory pressure (APU shares RAM with system)
free -h
# Should have >2GB available during transcoding

# Check transcoding preset
podman logs jellyfin | grep preset
```

**Solutions:**

1. **Lower encoding quality preset:**
   - Dashboard → Playback → Encoding preset: "Speed" or "Fastest"
   - Trade quality for performance

2. **Thermal throttling:**
   ```bash
   # Monitor temps during transcoding
   watch -n1 sensors

   # If CPU >85°C:
   # - Clean dust from heatsink
   # - Improve case airflow
   # - Reapply thermal paste
   ```

3. **Memory pressure (APU specific):**
   ```bash
   # APU shares system RAM for VRAM
   # Ensure adequate free memory

   # Check if other services competing for RAM
   podman stats --no-stream

   # Consider increasing Jellyfin memory limit
   nano ~/.config/containers/systemd/jellyfin.container
   # MemoryMax=6G (from current 4G)
   ```

### Issue 3: Playback Stuttering/Artifacts

**Symptoms:**
- Video plays but has visual glitches
- Stuttering or freezing frames
- Corrupted macroblocks

**Diagnosis:**
```bash
# Check FFmpeg errors in transcode logs
podman exec jellyfin cat /config/log/ffmpeg-transcode-*.txt | grep -i error

# Check if specific codec causing issues
# Play different video formats to isolate
```

**Solutions:**

1. **10-bit HEVC encoding issue (common on Vega):**
   - Dashboard → Playback
   - Uncheck "HEVC 10bit" under hardware decoding
   - Let Jellyfin use software decode for 10-bit content

2. **VPP tone mapping problems:**
   - Dashboard → Playback
   - Uncheck "Enable VPP Tone mapping"
   - HDR content will be software processed

3. **Encoding CRF too low (bitrate too high):**
   - Dashboard → Playback → H264 encoding CRF: Increase to 25-28
   - Lower quality but more reliable encoding

### Issue 4: Permission Denied on /dev/dri/renderD128

**Symptoms:**
- `podman exec jellyfin ls /dev/dri/` fails with permission denied
- Even though host user can access device

**Diagnosis:**
```bash
# Check host permissions
ls -la /dev/dri/renderD128
# -rw-rw----. 1 root render

# Check user groups
groups
# Must include 'render' group

# Check container user mapping
podman exec jellyfin id
# Should show uid=1000 (same as host user)
```

**Solutions:**

1. **Add user to render group:**
   ```bash
   sudo usermod -aG render $USER
   # MUST logout and login again for this to take effect

   # Or use temporary group assignment
   newgrp render
   systemctl --user restart jellyfin.service
   ```

2. **SELinux blocking access:**
   ```bash
   # Check for SELinux denials
   sudo ausearch -m avc -ts recent | grep renderD128

   # Temporarily disable to test
   sudo setenforce 0
   systemctl --user restart jellyfin.service
   # Test transcoding
   sudo setenforce 1

   # If this fixed it, create SELinux policy
   # (Shouldn't be necessary on Fedora - report bug)
   ```

3. **Rootless Podman subuid/subgid issue:**
   ```bash
   # Verify subuid/subgid mappings
   grep $USER /etc/subuid
   grep $USER /etc/subgid

   # Should show ranges like:
   # username:100000:65536

   # If missing, recreate
   sudo usermod --add-subuids 100000-165535 $USER
   sudo usermod --add-subgids 100000-165535 $USER
   podman system migrate
   ```

### Issue 5: VA-API Works But Jellyfin Doesn't Use It

**Symptoms:**
- `vainfo` works on host and in container
- Devices accessible in container
- Jellyfin still uses CPU transcoding

**Diagnosis:**
```bash
# Check Jellyfin playback settings
# Dashboard → Playback → Hardware acceleration
# Must be set to "Video Acceleration API (VA-API)"

# Check if codec is supported by GPU
vainfo | grep -A 5 "VAEntrypointEncSlice"

# Check Jellyfin user permissions (runs as jellyfin user inside container)
podman exec jellyfin whoami
podman exec jellyfin groups
```

**Solutions:**

1. **Jellyfin not configured for VA-API:**
   - Navigate to Dashboard → Playback
   - Ensure dropdown is set to "Video Acceleration API (VA-API)"
   - Device field: `/dev/dri/renderD128`
   - Click Save

2. **Codec not supported by hardware:**
   ```bash
   # If trying to transcode AV1 (not supported by Vega):
   # Software transcoding is expected

   # Check what codec source video uses
   podman exec jellyfin /usr/lib/jellyfin-ffmpeg/ffprobe \
     /media/multimedia/video.mkv 2>&1 | grep "Video:"

   # If codec unsupported, disable hardware decoding for that codec
   ```

3. **Client requesting software transcode:**
   - Some clients force software transcoding
   - Check Jellyfin Activity dashboard during playback
   - "Transcode Reason" field shows why transcoding triggered

---

## Phase 6: Optimization and Tuning

### Optimization 1: Transcode Quality vs Speed

**For Real-Time Streaming (Low Latency):**
```
Dashboard → Playback
├─ Encoding preset: Speed (or Fastest)
├─ H264 CRF: 25-28 (lower quality, faster encoding)
├─ Thread count: 0 (auto)
└─ Enable hardware encoding: ✓
```

**For High-Quality Archival:**
```
Dashboard → Playback
├─ Encoding preset: Balanced (or Quality)
├─ H264 CRF: 20-23 (higher quality, slower encoding)
├─ Thread count: 0 (auto)
└─ Enable hardware encoding: ✓
```

**APU Consideration:** APUs have less powerful encoding units than discrete GPUs. Using "Speed" preset recommended for smooth playback.

### Optimization 2: Memory Allocation (APU Specific)

**APU Memory Architecture:**
- System RAM is shared between CPU and GPU
- Jellyfin transcoding benefits from more available RAM
- Vega iGPU typically uses 512MB-2GB of shared memory

**Recommended Settings:**
```ini
# In jellyfin.container quadlet
MemoryMax=4G      # Current setting (adequate)
MemoryHigh=3G     # Soft limit

# If frequent transcoding of 4K content:
MemoryMax=6G
MemoryHigh=5G

# Monitor actual usage:
# podman stats jellyfin
```

**System RAM Recommendations:**
- Minimum: 8GB total system RAM (4GB for OS, 4GB for Jellyfin+GPU)
- Recommended: 16GB total (comfortable for multiple streams)
- Optimal: 32GB (no memory pressure even with heavy transcoding)

### Optimization 3: Concurrent Stream Limits

**Vega APU Transcoding Capacity:**
- 1080p streams: 3-4 concurrent
- 4K→1080p streams: 2-3 concurrent
- Mixed load: ~3 streams total

**Configure Jellyfin limits:**
```
Dashboard → Playback
└─ Transcoding
   ├─ Maximum concurrent transcode sessions: 3
   └─ Hardware decoding maximum threads: 0 (auto)
```

**Why limit concurrent streams:**
- Prevents overloading GPU/APU
- Ensures quality for active streams
- Avoids memory exhaustion

### Optimization 4: Transcode Cache Location

**Current Configuration:**
```ini
# From jellyfin.container
Volume=/mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes:/config/transcodes:Z
```

**This is optimal because:**
- ✅ Off system SSD (prevents wear and space exhaustion)
- ✅ Large BTRFS pool can handle big temp files
- ✅ Temp data separate from persistent config

**Monitoring transcode cache:**
```bash
# Check transcode directory size
du -sh /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/

# Clean old transcodes (Jellyfin usually auto-cleans)
find /mnt/btrfs-pool/subvol6-tmp/jellyfin-transcodes/ \
  -type f -mtime +1 -delete
```

---

## Phase 7: Validation Checklist

Use this checklist to verify GPU acceleration is fully operational:

### System Level
- [ ] `lspci` shows AMD VGA controller
- [ ] `lsmod | grep amdgpu` shows loaded module
- [ ] `/dev/dri/renderD128` exists with correct permissions
- [ ] User is member of `render` group
- [ ] `vainfo` shows H264/HEVC encode/decode profiles
- [ ] No VA-API errors in `vainfo` output

### Container Level
- [ ] Jellyfin quadlet has `AddDevice=/dev/dri/renderD128` (minimum)
- [ ] Optionally has `AddDevice=/dev/dri/card0` (recommended for APU)
- [ ] `podman exec jellyfin ls /dev/dri/` shows devices
- [ ] `podman exec jellyfin vainfo` works without errors
- [ ] No SELinux denials in audit log

### Jellyfin Configuration
- [ ] Dashboard → Playback → Hardware acceleration set to "VA-API"
- [ ] VA-API Device field: `/dev/dri/renderD128`
- [ ] Hardware decoding enabled for H264, HEVC
- [ ] Hardware encoding enabled
- [ ] Configuration saved successfully

### Transcoding Validation
- [ ] Active transcode shows GPU usage in `radeontop`
- [ ] CPU usage remains low (<20%) during transcode
- [ ] FFmpeg process shows `-hwaccel vaapi` flags
- [ ] Transcode speed >1.0x realtime for 1080p content
- [ ] Playback is smooth without buffering
- [ ] Can handle 2+ concurrent streams

### Performance Validation
- [ ] GPU transcode at least 2x faster than CPU transcode
- [ ] System remains responsive during transcoding
- [ ] No thermal throttling (CPU temps <85°C)
- [ ] Adequate free memory during transcoding (>2GB)

---

## Reference: Useful Commands

### Monitoring Commands
```bash
# GPU utilization (real-time)
radeontop

# CPU/Memory per container
podman stats jellyfin

# Overall system resources
htop

# Jellyfin logs (live)
journalctl --user -u jellyfin.service -f

# FFmpeg transcode logs
podman exec jellyfin cat /config/log/ffmpeg-transcode-*.txt | tail -100

# Active streams
curl -s http://localhost:8096/Sessions | jq '.[] | {Device, PlayState, TranscodingInfo}'
```

### Diagnostic Commands
```bash
# Verify VA-API host
vainfo

# Verify VA-API container
podman exec jellyfin vainfo

# Check devices in container
podman exec jellyfin ls -la /dev/dri/

# Check running FFmpeg processes
podman exec jellyfin ps aux | grep ffmpeg

# Check SELinux denials
sudo ausearch -m avc -ts recent | grep -E '(dri|jellyfin)'

# Verify hardware acceleration enabled in Jellyfin
curl -s http://localhost:8096/System/Configuration | jq '.EncodingOptions.HardwareAccelerationType'
```

### Service Management
```bash
# Restart Jellyfin after config changes
systemctl --user restart jellyfin.service

# Check service status
systemctl --user status jellyfin.service

# View full container inspect
podman inspect jellyfin | less
```

---

## Appendix A: AMD Ryzen 5 5600G Specifications

**Integrated Graphics:**
- Architecture: Vega (GCN 5)
- Compute Units: 7 CUs
- GPU Cores: 448 stream processors
- GPU Clock: Up to 1.9 GHz
- Memory: Shared system RAM (no dedicated VRAM)

**Video Codec Support:**
- **Decode:** H.264, H.265/HEVC (8-bit, 10-bit), VP9, MPEG-2, VC-1
- **Encode:** H.264, H.265/HEVC (8-bit, limited 10-bit)
- **Max Resolution:** 4K @ 60fps (encode/decode)
- **NOT Supported:** AV1 (too old architecture)

**Linux Driver:**
- Kernel module: `amdgpu`
- VA-API driver: `radeonsi` (Mesa)
- Supported since: Linux kernel 5.11+ (fully stable in 5.15+)
- Fedora 42: Fully supported (ships with recent kernel/Mesa)

---

## Appendix B: Expected Performance Benchmarks

**1080p H.264 → 1080p H.264:**
- CPU (Ryzen 5 5600G software): 80-120 fps (~3x realtime)
- GPU (Vega VA-API): 150-200 fps (~6x realtime)
- **Speedup:** ~2x

**4K H.265 → 1080p H.264:**
- CPU (software): 8-15 fps (~0.5x realtime)
- GPU (VA-API): 40-60 fps (~2x realtime)
- **Speedup:** ~4x

**Power Consumption:**
- CPU transcode: ~60-80W package power
- GPU transcode: ~30-45W package power
- **Savings:** ~35-50% lower power

**Heat Generation:**
- CPU transcode: 70-85°C
- GPU transcode: 50-65°C
- **Cooler operation:** ~20°C lower temps

---

## Appendix C: Troubleshooting Decision Tree

```
Jellyfin transcoding slow/using CPU?
│
├─ Is GPU detected by kernel?
│  ├─ No → Install amdgpu drivers, check BIOS iGPU settings
│  └─ Yes ↓
│
├─ Does /dev/dri/renderD128 exist?
│  ├─ No → Load amdgpu module, check dmesg for errors
│  └─ Yes ↓
│
├─ Does `vainfo` work on host?
│  ├─ No → Install mesa-va-drivers, check LIBVA_DRIVER_NAME
│  └─ Yes ↓
│
├─ Does container have /dev/dri/ devices?
│  ├─ No → Add AddDevice to quadlet, restart service
│  └─ Yes ↓
│
├─ Does `podman exec jellyfin vainfo` work?
│  ├─ No → Check permissions, SELinux, try adding /dev/dri/card0
│  └─ Yes ↓
│
├─ Is VA-API enabled in Jellyfin dashboard?
│  ├─ No → Dashboard → Playback → Set to VA-API, save
│  └─ Yes ↓
│
├─ During transcode, is radeontop showing GPU usage?
│  ├─ No → Check FFmpeg command for -hwaccel flags, review logs
│  └─ Yes → ✅ GPU acceleration working!
│
└─ Still having issues?
   └─ See "Phase 5: Troubleshooting Common Issues"
```

---

## Appendix D: Related Documentation

**Project Documentation:**
- Jellyfin guide: `docs/10-services/guides/jellyfin.md`
- Storage layout: `docs/20-operations/guides/storage-layout.md`
- Podman fundamentals: `docs/00-foundation/guides/podman-fundamentals.md`

**External Resources:**
- [Jellyfin Hardware Acceleration Guide](https://jellyfin.org/docs/general/administration/hardware-acceleration/)
- [AMD VA-API Documentation](https://wiki.archlinux.org/title/Hardware_video_acceleration#AMD)
- [Podman Device Mapping](https://docs.podman.io/en/latest/markdown/podman-run.1.html#device)
- [FFmpeg VA-API Guide](https://trac.ffmpeg.org/wiki/Hardware/VAAPI)

**Fedora Specific:**
- [Fedora AMD GPU Setup](https://docs.fedoraproject.org/en-US/quick-docs/set-up-amd-gpu/)
- [RPM Fusion Mesa Drivers](https://rpmfusion.org/)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-17
**Tested On:** Fedora Workstation 42, AMD Ryzen 5 5600G, Podman 4.x
**Maintainer:** patriark
**Status:** Ready for execution
