# Ambilight + Hue: Deprecation Research & Software Alternatives

**Date:** 2026-02-08
**Category:** Research / Home Automation
**Status:** Options identified, awaiting decision

## Context

The living room Philips TV (65PUS7101/12, 2016 vintage) has Ambilight built into the panel and was previously configured to extend its ambient lighting to a Hue bulb in the kitchen via the native Ambilight+Hue feature. The TV currently only exposes an on/off toggle for Ambilight+Hue in its settings -- there is no option to add or manage additional Hue bulbs. The Hue app on iPhone also provides no way to configure the TV's Ambilight-to-Hue mapping.

The TV no longer receives firmware updates and is connected to the IoT VLAN (192.168.2.67) alongside the Hue Bridge (192.168.2.60).

Meanwhile, fedora-htpc (192.168.1.70) streams content to this TV via HDMI 2.0, which opens up a software-based alternative path.

## Research Findings

### Ambilight+Hue Is Dead

The Ambilight+Hue feature has been officially deprecated:

- **2023:** Philips removed Ambilight+Hue from all new 2023 TV models. The feature was quietly discontinued as TP Vision (who licenses the Philips TV brand) and Signify (who owns Hue) drifted apart operationally.
- **2025 (September):** Philips announced **AmbiScape** as the successor, using Matter and Thread standards instead of the proprietary Hue bridge protocol. Only 2025+ models with Titan OS support it (OLED760, OLED770, MLED950, PUS9000 series).
- **The new Hue Bridge Pro** (released 2025) explicitly does not support the old Ambilight+Hue protocol.

For the 65PUS7101 specifically: the TV's Ambilight+Hue integration was built on an older API that Signify no longer maintains. The on/off toggle likely controls a stale configuration from when it was first paired. The inability to add new bulbs is not a bug -- it's a dead feature on abandoned firmware.

**Bottom line:** There is no fix within the TV itself. The hardware Ambilight LEDs still work (they're part of the panel), but the bridge to Hue is a dead end.

### The Philips Hue Play HDMI Sync Box

Philips sells a hardware solution -- the Hue Play HDMI Sync Box (~$250-350) -- that sits between an HDMI source and the TV, analyzes the video signal, and drives Hue lights accordingly. A newer Sync Box 8K model exists.

**Why this is a poor fit for our setup:**
- Expensive proprietary hardware that duplicates what software can do
- fedora-htpc already generates the video signal -- we can capture it at the source
- The Sync Box is a closed ecosystem with no Home Assistant integration
- Goes against the digital sovereignty principle (buying hardware to replace software capability)

### Software Alternatives (The Interesting Part)

Since fedora-htpc generates the HDMI signal to the TV, we can capture the screen content *before* it leaves the machine and use it to drive Hue lights. No HDMI capture card needed.

#### Option A: HyperHDR (Recommended)

[HyperHDR](https://github.com/awawa-dev/HyperHDR) is the most capable option for this setup.

**Why it fits:**
- Runs natively on Linux x86_64
- **PipeWire screen grabber** with Wayland support (fedora-htpc runs Wayland)
- Native Philips Hue support via Entertainment API (low-latency streaming)
- HDR tone mapping (relevant for HDR content from Jellyfin)
- Ultra-low CPU usage (important -- fedora-htpc already runs 27 containers)
- Home Assistant integration via MQTT
- Supports sound-reactive mode for music visualization
- Active development (v20+ releases, maintained as of 2026)

**How it would work:**
```
Jellyfin/Browser → Wayland compositor → PipeWire → HyperHDR → Hue Entertainment API → Hue Bridge → Hue bulbs
                                                                                    ↓
                                                                              HDMI → TV (Ambilight LEDs still do their own thing)
```

The TV's built-in Ambilight would continue driving the panel-edge LEDs independently, while HyperHDR drives the room Hue bulbs. This is actually *better* than the old Ambilight+Hue because:
- The Ambilight LEDs react at panel refresh rate (zero latency)
- The Hue bulbs react via Entertainment API (~80ms latency)
- Together they create a layered ambient effect

**Deployment considerations:**
- Could run as a Podman container or a native systemd service
- Needs access to PipeWire socket for screen capture
- Needs network access to Hue Bridge on IoT VLAN (192.168.2.60)
- Cross-VLAN communication: fedora-htpc (192.168.1.70) -> Hue Bridge (192.168.2.60) may need a firewall rule on UDM Pro
- Memory footprint: minimal (~50-100MB)
- CPU impact: very low (grabs downscaled frames, averages color regions)

#### Option B: Hyperion.ng

[Hyperion.ng](https://github.com/hyperion-project/hyperion.ng) is the classic open-source Ambilight implementation.

**Pros:**
- Mature project, large community
- Native Home Assistant integration (dedicated HA component)
- Hue APIv2 support without needing Entertainment groups
- Rich effect engine

**Cons:**
- **Wayland screen capture is not supported** in Hyperion.ng -- this is a dealbreaker since fedora-htpc runs Wayland. There's an open issue (#1096) with no resolution.
- Less active development compared to HyperHDR
- X11 grabber works well but would require switching display server

**Verdict:** Not viable without switching to X11, which is a regression on Fedora 43.

#### Option C: Harmonize Project

[Harmonize Project](https://github.com/MCPCapital/HarmonizeProject) syncs HDMI video with Hue lights.

**Pros:**
- Purpose-built for Hue (uses Entertainment API natively)
- ~60 color updates/second, 80ms latency
- Runs on Linux

**Cons:**
- **Requires an HDMI capture card** -- it captures the HDMI output rather than the screen buffer
- Designed for Raspberry Pi (could run on fedora-htpc but adds unnecessary hardware)
- Would need an HDMI splitter (one output to TV, one to capture card)
- More complex physical setup

**Verdict:** Viable but over-engineered when software capture is available.

## Comparison Matrix

| Criteria | HyperHDR | Hyperion.ng | Harmonize | Hue Sync Box |
|----------|----------|-------------|-----------|-------------- |
| Wayland support | Yes (PipeWire) | No | N/A (HDMI) | N/A (hardware) |
| Hue support | Entertainment API | APIv2 | Entertainment API | Native |
| HDMI capture card needed | No | No | Yes | Built-in |
| Home Assistant integration | MQTT | Native HA component | No | No |
| HDR support | Yes (tone mapping) | Basic | No | Yes |
| CPU overhead | Very low | Low | Low | N/A |
| Cost | Free | Free | ~$30 (capture card) | $250-350 |
| Active development | Yes | Slower | Moderate | Proprietary |
| Runs on fedora-htpc as-is | Yes | No (Wayland) | No (needs hardware) | No |

## Recommendation

**HyperHDR is the clear winner** for this setup:

1. It's the only option that works with Wayland out of the box
2. Software-only solution (no additional hardware purchases)
3. Integrates with the existing Home Assistant instance via MQTT
4. Aligns with digital sovereignty (open source, self-hosted, no vendor lock-in)
5. The Entertainment API provides low-latency Hue control (~80ms)
6. Minimal resource impact on an already-busy container host

### Deployment Plan (If Proceeding)

1. **Network prerequisite:** Add UDM Pro firewall rule allowing fedora-htpc (192.168.1.70) to reach Hue Bridge (192.168.2.60) on the required ports (TCP 443 for HTTPS API, UDP for Entertainment streaming)
2. **Install HyperHDR** on fedora-htpc (native package or Podman container)
3. **Configure PipeWire grabber** for Wayland screen capture
4. **Create Hue Entertainment group** via Hue app with desired bulbs
5. **Configure HyperHDR** to output to Hue Entertainment API
6. **Map LED positions** to physical bulb locations around the room
7. **Integrate with Home Assistant** via MQTT for automation (e.g., auto-enable when Jellyfin is playing)
8. **Test with Jellyfin** content (movies, music videos) for latency and color accuracy

### Open Questions

- How many Hue bulbs should participate? Entertainment API supports up to 20.
- Should HyperHDR run as a container (isolation, follows homelab pattern) or native service (easier PipeWire access)?
- Is the cross-VLAN firewall rule acceptable from a security perspective? The IoT VLAN was designed to be isolated.
- Should the TV's built-in Ambilight be left running (layered effect) or disabled (let HyperHDR handle everything)?

## Sources

- [AmbiScape replaces Ambilight+Hue in Philips TVs (Hueblog, 2025-09)](https://hueblog.com/2025/09/30/ambiscape-replaces-ambilighthue-in-philips-tvs/)
- [2023 Ambilight TVs no longer have Hue integration (Hueblog, 2023-07)](https://hueblog.com/2023/07/04/2023-ambilight-tvs-no-longer-have-hue-integration/)
- [Ambilight+Hue does not work with Hue Bridge Pro (Hueblog, 2025-09)](https://hueblog.com/2025/09/15/ambilighthue-does-not-work-with-the-hue-bridge-pro/)
- [HyperHDR on GitHub](https://github.com/awawa-dev/HyperHDR)
- [Hyperion.ng on GitHub](https://github.com/hyperion-project/hyperion.ng)
- [Hyperion.ng Wayland issue #1096](https://github.com/hyperion-project/hyperion.ng/issues/1096)
- [Harmonize Project on GitHub](https://github.com/MCPCapital/HarmonizeProject)
- [Hyperion Home Assistant integration](https://www.home-assistant.io/integrations/hyperion/)
- [AmbiScape with Matter/Thread (MatterAlpha)](https://www.matteralpha.com/news/ambiscape-introduced-philips-tvs-get-new-matter-lighting-support-with-thread)
