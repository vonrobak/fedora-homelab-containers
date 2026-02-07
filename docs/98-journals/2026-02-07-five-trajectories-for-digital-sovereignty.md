# Five Trajectories for Digital Sovereignty

**Date:** 2026-02-07
**Type:** Strategic reflection and learning blueprint
**Context:** 100 days into the homelab journey, 401 commits, 27 containers, 100/100 health score

---

## The Arc So Far

Before charting what's ahead, it's worth acknowledging what happened.

On October 20, 2025, a person who didn't know what `firewalld` was sat down at a Fedora machine and couldn't figure out why a container was reachable locally but not from the network. The error wasn't exotic. The fix was one command. But it represented the starting condition: *someone who wanted to control their own infrastructure but didn't yet have the vocabulary for it.*

109 days later, that same person debugged a kernel-upgrade-triggered DNS resolution ordering issue across multi-homed container networks by running controlled experiments, identified Podman's aardvark-dns as the root cause, researched upstream issues (#14262, #12850), found the maintainers had closed them as "working as designed," and designed an architectural solution (static IPs + /etc/hosts override) documented as ADR-018.

That is not incremental improvement. That is a phase transition.

The commit history tells the story in compressed form:

| Period | Commits | Theme |
|--------|---------|-------|
| Oct 31 - Nov 4 | 5 | First commit, learning git itself |
| Nov 5 - Nov 14 | 264 | Explosive building (monitoring, Immich, Authelia, Vaultwarden) |
| Dec 2025 | 63 | Deepening (Nextcloud, alert redesign, operational polish) |
| Jan 2026 | 59 | Maturation (Home Assistant, SLO calibration, Matter) |
| Feb 2026 | 13 | Judgment (DNS root cause, Collabora decommission, skill audit) |

The declining commit count isn't slowing down. It's a sign of maturity. Early commits were small, frequent, often fixing what the previous commit broke. Recent commits are deliberate, scoped, meaningful. PR #84 (Collabora decommission) contains a single, clean decision. PR #67 (SLO burn rate fix) is surgical. The person writing those commits thinks differently than the person who committed a CrowdSec LAPI key to a public repo on day one.

---

## What Digital Sovereignty Actually Demands

The phrase "digital sovereignty" gets used loosely. In this context, it means something specific: **the ability to make informed, independent decisions about the systems you depend on, and to act on those decisions without requiring permission from or dependence on entities whose interests may not align with yours.**

This is not just about self-hosting. A person who self-hosts services they don't understand has traded one dependency (cloud providers) for another (the next person who helps them fix it). True sovereignty requires three capabilities:

1. **Diagnostic independence** - When something breaks, you can find the root cause yourself
2. **Design judgment** - When facing trade-offs, you can evaluate options and choose wisely
3. **Implementation autonomy** - When you've decided what to do, you can do it

The homelab journey so far has built significant strength in all three, but unevenly. The Collabora decommission showed excellent design judgment. The DNS debugging showed strong diagnostic independence. But implementation autonomy still leans heavily on AI assistance for writing code, generating configurations, and structuring complex deployments.

That's not a criticism. It's a map of where the growth edges are.

---

## The Five Trajectories

### Trajectory 1: Programming Fluency (Python)

**Score: 91/100**

**The gap this addresses:**

Throughout 109 days, every script in this homelab was written by Claude, not by the user. `homelab-intel.sh`, `autonomous-check.sh`, `auto-doc-orchestrator.sh` - all generated. The user can read them, modify them, debug them when they break. But the user has not yet written a non-trivial program from scratch.

This is the single largest constraint on sovereignty. When the Mill air purifier integration filters devices as "Unsupported," the user identified the problem through log analysis (impressive), located the data in the API response (smart), and cataloged three solution approaches (mature). But couldn't execute any of them without assistance, because all three require writing Python code.

**What Python unlocks:**

- **Home Assistant custom components.** The Mill fix is a 50-line Python modification. The user who can write it doesn't need to wait for upstream, file feature requests, or ask for help. That's sovereignty in action.
- **Custom Prometheus exporters.** The UDM Pro metrics gap (firewall/IDS data not in Prometheus) can be solved with a Python exporter that queries the UniFi API. It's ~100 lines of code. Knowing how to write it means the monitoring stack covers what *you* need, not just what off-the-shelf exporters provide.
- **Automation scripts with real logic.** Bash is adequate for glue. But the moment you need to parse JSON, make HTTP requests, handle errors gracefully, or build something with state, Python is the right tool. The autonomous operations framework currently does all of this in bash, and it shows in the complexity.
- **Understanding the tools you depend on.** Authelia, Prometheus, Grafana, Home Assistant, Traefik - all have Python in their ecosystem. Reading their source code becomes possible. Filing informed bug reports becomes natural. Contributing patches becomes thinkable.

**How to learn it within existing hardware (cost: zero):**

The homelab itself is the curriculum. Not abstract exercises. Real projects with real stakes:

1. **First project:** Fix the Mill air purifier integration. Fork `custom_components/mill`, modify the device filter, create sensors from `lastMetrics`. This is small, bounded, and immediately useful.
2. **Second project:** Write a UDM Pro Prometheus exporter. Query the UniFi API, expose firewall block counts and IDS alerts as metrics. This teaches HTTP clients, metric design, and service architecture.
3. **Third project:** Rewrite one bash script (e.g., `check-drift.sh`) in Python. Compare the result. Learn what Python does better and what bash does better.

**Why this scores highest:**

Every other trajectory on this list benefits from programming fluency. Network mastery is deeper when you can write packet analysis tools. Linux internals are more tangible when you can write programs that exercise cgroups and namespaces. Community contribution is more impactful when you can submit code, not just documentation. Programming is the force multiplier beneath all other multipliers.

**The hard truth:** There is a period of frustration where writing Python feels slower than asking Claude to write it. That period is the investment. The return is permanent capability.

---

### Trajectory 2: Network Architecture & Security at the Wire Level

**Score: 85/100**

**The gap this addresses:**

The homelab has 8 container networks, a UDM Pro, a Pi-hole, VLANs (ASUS RT-N66U on 192.168.2.0/24 for IoT), and port forwarding. But most of this was configured by following guides rather than by understanding the underlying model. The DNS root cause investigation in February revealed both talent (systematic hypothesis testing) and a gap (the user didn't initially understand why Podman's DNS behavior was architecture-dependent rather than a bug).

The UDM Pro is the most powerful and least understood piece of equipment in the homelab. It has:
- A full stateful firewall with zone-based rules
- IDS/IPS (Suricata-based)
- DPI (Deep Packet Inspection)
- Traffic analytics
- VPN server
- DHCP with static mappings

Most of this is running on defaults or minimally configured.

**What network mastery unlocks:**

- **VLAN-based security segmentation.** The current IoT VLAN (192.168.2.0/24 on the ASUS router) is a good start but is architecturally limited - traffic between VLANs routes through the ASUS router rather than through the UDM Pro's firewall. Understanding VLANs deeply means you can redesign this: IoT devices on a UDM-managed VLAN, firewall rules controlling exactly what can talk to what, no inter-VLAN routing except explicitly allowed paths.
- **DNS as a control plane.** Pi-hole blocks ads. But DNS can do much more: split-horizon DNS (internal vs external resolution), DNS-over-HTTPS for privacy, conditional forwarding, DNSSEC validation. Understanding DNS deeply means understanding how every device on your network finds every service.
- **Firewall rule design.** The difference between "port 443 is forwarded to Traefik" and "I understand every rule in my firewall, why each exists, and what the blast radius would be if I removed it." Sovereignty at the network layer means you can draw the complete path of any packet from the internet to a container and back.
- **TLS and certificate management.** Let's Encrypt + Traefik handles certificates automatically. But understanding the certificate chain, OCSP stapling, key pinning, and what happens when ACME fails gives you the ability to debug certificate issues yourself rather than searching Stack Overflow.

**How to learn it (cost: zero, existing hardware):**

1. **Exercise 1:** Draw the complete network topology from memory. Every device, every IP, every VLAN, every firewall rule. Then verify against reality. The gaps between your drawing and reality are your learning targets.
2. **Exercise 2:** Use the UDM Pro's traffic analytics for one week. Understand what devices are talking to what endpoints. Ask: is there traffic you didn't expect? Traffic you can't explain?
3. **Exercise 3:** Set up a proper IoT VLAN on the UDM Pro (replacing or supplementing the ASUS router approach). Configure firewall rules so IoT devices can reach the internet but cannot initiate connections to the server VLAN. This is real security engineering.
4. **Exercise 4:** Implement DNSSEC validation on Pi-hole. Understand what it protects against and what it doesn't. Test with `dig +dnssec`.

**Why this score:**

The network is the trust boundary. Every security control in the homelab - CrowdSec, Authelia, rate limiting, TLS - operates *above* the network layer. If the network layer is misconfigured or misunderstood, those controls can be bypassed in ways that are invisible to application-layer monitoring. Understanding the network deeply is understanding the foundation everything else stands on.

It scores below Python because network knowledge, while critical, is more bounded in what it enables. You'll reach a plateau of "I understand my network fully" faster than you'll exhaust what programming unlocks.

---

### Trajectory 3: Linux Internals & the Machinery Beneath Containers

**Score: 82/100**

**The gap this addresses:**

The user configures systemd units, SELinux labels (`:Z`), cgroup resource limits (`MemoryMax`, `MemoryHigh`), container slices, and kernel parameters. But these are used as configuration knobs rather than understood as systems with their own logic.

The February DNS incident is illustrative. A kernel upgrade (6.12 to 6.18) changed timing behavior, which changed the order aardvark-dns returned IP addresses, which caused Traefik to route through the wrong network. The user fixed it with a `/etc/hosts` override (pragmatic, correct), but the deeper question - *why does a kernel upgrade change DNS timing, and what does that tell you about how container networking actually works?* - remains unexplored.

**What Linux internals unlock:**

- **Namespaces and cgroups** are the two technologies that make containers work. Understanding them means understanding what a "container" actually *is* (not a VM, not magic - just processes with restricted views and resource limits). When a container behaves unexpectedly, this knowledge turns mystifying problems into traceable system calls.
- **SELinux policy** goes beyond `:Z`. Understanding the type enforcement model (what labels mean, how policy allows/denies, how to read audit logs) means you can write custom policies when needed rather than choosing between `:Z` and disabling SELinux. Some day you'll want a container to access a device file or a socket that `:Z` doesn't cover.
- **systemd internals** - dependency ordering, socket activation, cgroup delegation, journal structured logging. The user already uses quadlets (which are systemd generators), but understanding *how* quadlets become unit files, how systemd resolves dependencies, and how `Slice=` actually controls cgroup hierarchies turns quadlets from "magic files" into "configuration for a system I understand."
- **BTRFS internals** - the user relies heavily on BTRFS (system SSD + 14.55TB pool) but understanding copy-on-write semantics, extent trees, the relationship between snapshots and space usage, and degraded mode operation would be valuable. The NOCOW flag for databases (`chattr +C`) was applied as a recipe. Understanding *why* COW is bad for databases (fragmentation from in-place updates on COW filesystems creating ever-growing extent trees) deepens judgment about storage architecture.

**How to learn it (cost: zero):**

1. **Exercise 1:** Run `nsenter` into a running container. Examine `/proc/self/cgroup`, `/proc/self/mountinfo`, `/proc/self/status`. Understand what the container can and cannot see.
2. **Exercise 2:** Read `systemctl --user show jellyfin.service` (all properties). For every property you don't understand, find out what it does. This is tedious but transformative.
3. **Exercise 3:** Trigger an SELinux denial intentionally (mount a volume without `:Z`). Read the audit log (`ausearch -m avc`). Understand the denial message. Use `audit2allow` to see what policy would permit it. Then understand why you should use `:Z` instead.
4. **Exercise 4:** Simulate a BTRFS drive failure. (Use a loopback device, not your real pool.) Create a BTRFS filesystem on two loop devices, write data, remove one, mount in degraded mode, observe behavior. This builds confidence for the day a real drive fails.

**Why this score:**

This knowledge is deep and transferable. It's the difference between a homelab operator and a systems engineer. But it scores below networking because the immediate practical benefit is smaller - the homelab works well without this knowledge. This is about building depth of understanding that pays off over years, not weeks.

---

### Trajectory 4: Community Participation & Upstream Contribution

**Score: 75/100**

**The gap this addresses:**

The homelab repository is public on GitHub. The documentation is extensive. But the user is currently a *consumer* of open source, not a *contributor*. Every tool in the stack - Podman, Traefik, Home Assistant, Prometheus, Authelia, CrowdSec - was built by communities of people who share their work. Digital sovereignty that only takes and never gives back is fragile sovereignty. The projects you depend on need contributors to survive.

More practically: the user has encountered real bugs and limitations (Podman DNS ordering, Mill integration filtering, Collabora WOPI issues) and has the diagnostic skill to write excellent bug reports. This skill is going to waste.

**What upstream contribution unlocks:**

- **Influence over the tools you depend on.** A well-written bug report with reproduction steps gets developer attention. A submitted PR gets merged. Suddenly you're not just using Podman - you're shaping its future.
- **Technical writing and communication skills.** Writing for an upstream audience (who doesn't know your setup) is harder than writing for yourself. It forces clarity of thought. The user already writes extensively in journals - adapting that skill to GitHub issues, forum posts, and PR descriptions is a small step with large returns.
- **Network effects.** The r/selfhosted community, the Podman community, the Home Assistant community - these are full of people solving the same problems. Sharing your quadlet patterns, your Traefik dynamic config approach (ADR-016), your multi-network static IP solution (ADR-018) would help others and attract people who can help you.
- **Understanding through teaching.** Explaining *why* you chose quadlets over docker-compose, *why* you put all routing in dynamic config instead of labels, *why* you order middleware by execution cost - this forces you to examine your own reasoning and often reveals gaps or alternatives you hadn't considered.

**Concrete starting points (cost: zero):**

1. **Mill air purifier:** File a detailed GitHub issue on the Home Assistant Mill integration with the log evidence you already have. Include the sensor data that's available but filtered. This is a 30-minute task that might unblock the feature for everyone.
2. **Quadlet patterns:** Write a blog post or r/selfhosted guide on "Podman Quadlets: A Practical Guide from Someone Who Learned the Hard Way." Your journal entries from October 2025 contain the exact confusion a newcomer has and the exact insights that resolve it.
3. **Traefik dynamic config pattern:** Your ADR-016 approach (no labels, all routing in dynamic files) is opinionated and well-reasoned. A short write-up on why and how would be valuable to the Traefik community.
4. **ADR-018 (static IPs for multi-network containers):** This solves a real problem that Podman's maintainers dismissed. Documenting it publicly helps everyone who hits the same issue.

**Why this score:**

This trajectory develops important skills (communication, community engagement, reputation) but it builds *on top of* existing technical skills rather than creating new ones. It's most valuable when combined with Trajectory 1 (Python), because then you can contribute code, not just documentation. Standing alone, it's worthwhile but less transformative than the technical trajectories.

---

### Trajectory 5: IoT, Protocols, and the Physical-Digital Bridge

**Score: 70/100**

**The gap this addresses:**

The homelab currently lives entirely in the digital world. Containers, networks, HTTP requests, YAML files. Home Assistant is the first bridge to the physical world (Hue, Roborock, Mill), but the integration is through cloud APIs and vendor-provided protocols. The ESP32 for Plejd (on order) represents a different approach: direct hardware communication via Bluetooth LE, bypassing vendor clouds entirely.

This is where digital sovereignty meets the physical world. Your lights, your heating, your cleaning robot - these are all controlled by software you don't fully control, communicating through protocols you don't fully understand, to cloud services you don't own.

**What IoT protocol mastery unlocks:**

- **ESP32 and ESPHome.** The ESP32 is a programmable microcontroller. ESPHome turns it into a Home Assistant-integrated sensor/actuator platform. For ~8 EUR per board, you can build: temperature/humidity sensors, presence detectors, Bluetooth proxies (Plejd), energy monitors, plant watering systems, custom buttons. This is hardware sovereignty at the lowest possible cost.
- **MQTT.** The protocol that connects IoT devices. Understanding MQTT (publish/subscribe, topics, QoS levels, retained messages) is understanding how smart home devices communicate. Home Assistant supports MQTT natively. Once you understand it, you can integrate *anything* that speaks MQTT - including devices from manufacturers who don't provide Home Assistant integrations.
- **Matter and Thread.** The future of smart home interoperability. Matter devices work across ecosystems (Apple Home, Google Home, Home Assistant). Thread is the mesh networking protocol underneath. The user has already planned Matter smart plugs for Sept-Oct 2026, but understanding the protocol *before* buying devices means making better purchasing decisions.
- **Bluetooth LE.** The Plejd integration requires understanding BLE communication: advertising, services, characteristics, pairing. The ESP32 acts as a BLE-to-WiFi bridge. Understanding this protocol means you can integrate any BLE device, not just Plejd.

**How to learn it (cost: minimal, ~10-20 EUR for ESP32 boards):**

1. **First project:** When the ESP32 arrives, flash ESPHome, set up the Plejd Bluetooth proxy. This is the immediate practical goal.
2. **Second project:** Add a temperature/humidity sensor (DHT22, ~3 EUR) to the ESP32. Expose it to Home Assistant via ESPHome. Create an automation that triggers the Mill heater based on actual room temperature rather than the heater's built-in thermostat.
3. **Third project:** Set up an MQTT broker (Mosquitto container - you know how to deploy containers). Connect the ESP32 to MQTT. Understand the message flow from physical sensor to MQTT broker to Home Assistant to automation to physical actuator.
4. **Fourth project:** Research Matter-compatible smart plugs with energy monitoring. Understand what Thread border router you'd need (Home Assistant has this in some configurations, or nRF52840 dongle for ~12 EUR).

**Why this score:**

This trajectory is exciting and practical but scores lowest because it requires patience (hardware delivery), has a narrower skill transfer profile (IoT protocol knowledge is less broadly useful than Python or networking), and involves the most new purchases (even if small). It's deeply relevant to sovereignty in the physical world, but the learning curve is steep and the ecosystem is still maturing (Matter/Thread are not yet fully stable).

That said: for someone who lives in a physical space and wants that space to respond to their needs rather than a cloud provider's business model, this trajectory connects digital sovereignty to daily life in a way the others don't.

---

## Trajectory Comparison

| Trajectory | Score | Cost | Time to First Win | Sovereignty Impact | Skill Transfer |
|-----------|-------|------|-------------------|-------------------|----------------|
| 1. Python Programming | 91 | Zero | 1-2 weeks | Transformative | Very high (career) |
| 2. Network Architecture | 85 | Zero | 1 week | High (security) | High (career) |
| 3. Linux Internals | 82 | Zero | 2-3 weeks | Deep (understanding) | Very high (career) |
| 4. Community Contribution | 75 | Zero | 1 day | Moderate (influence) | High (reputation) |
| 5. IoT & Protocols | 70 | ~10-20 EUR | 2-4 weeks | High (physical world) | Moderate (niche) |

---

## How These Trajectories Interlock

These are not isolated paths. They reinforce each other:

```
                    Python (T1)
                   /     |     \
                  /      |      \
    Network (T2)    Linux (T3)    IoT (T5)
          \          |          /
           \         |         /
            Community (T4)
```

- **Python + Mill fix** = first upstream PR (T1 enables T4)
- **Python + UDM Pro exporter** = network visibility (T1 enables T2)
- **Network + IoT VLANs** = secure smart home (T2 enables T5)
- **Linux internals + container debugging** = better bug reports (T3 enables T4)
- **IoT + Python** = custom ESPHome components (T5 + T1)

The strongest two-trajectory combination is **T1 (Python) + T2 (Network)**. Together they cover the full stack from wire to application, and both have zero cost and high career transferability.

---

## A Suggested Sequence

Not all at once. Not a sprint. The homelab was built through sustained engagement over 109 days, and the next phase should follow the same rhythm.

**Months 1-2: Python foundations through the Mill fix project**
Start with a real problem you care about. The Mill air purifier integration is bounded (one file to modify), immediately useful (unlocks 14 sensors), and teaches the core skills (Python syntax, API interaction, Home Assistant architecture). Don't use online courses. Use your homelab as the classroom.

**Month 2-3: Network deep dive with UDM Pro**
Draw the full topology. Audit every firewall rule. Redesign the IoT VLAN. Write the Python Prometheus exporter for UDM Pro metrics (combining T1 and T2). At the end, you should be able to trace any packet from internet to container.

**Month 3-4: First upstream contribution**
Take the Mill fix, the quadlet guide, or the ADR-018 pattern and share it. One GitHub issue, one blog post, one community thread. Lower the bar for "contribution" - a well-written bug report counts.

**Month 4-6: Linux internals and IoT as interest dictates**
By now Python and networking are solid. Explore cgroups and namespaces when you're curious. Build ESP32 sensors when the hardware arrives. Let interest guide the pace.

---

## The Philosophical Note

There is a pattern in your learning journals. In October, the tone was "I'm amazed this works." In November, it was "I'm building something real." In January, it was "I know when to stop." In February, it was "I understand why this broke."

Each phase shows a deeper relationship with the systems. Not just operating them, but understanding them. Not just understanding them, but making judgment calls about them.

The next phase isn't about building more. You have 27 containers and they work. The next phase is about **deepening your relationship with the layers beneath what you've built** so that when novel problems arise - and they will - you can meet them with understanding rather than with search queries.

Digital sovereignty is not a destination. It's a practice. The homelab is the dojo.

---

**Prepared by:** Claude Code (Opus 4.6)
**For:** The person who went from "what's a firewall rule" to "I'll write an ADR for that" in 109 days
**Status:** Awaiting strategic choice
