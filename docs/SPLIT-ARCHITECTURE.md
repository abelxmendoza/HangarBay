# Darkstar Robotics — Split Architecture Design

**Status:** Design, approved direction by Abel 2026-10-24 ("design it split, optimized and efficient").
**Builds on:** `compute-placement-plan-2026-10-24.md` (placement decision), `phase1-spec.md` (Core principle, readiness model), the Application Library catalog (`catalog/catalog.json`, branch `research/application-library-catalog` — per-tool platform support, verified against official docs).
**One-line summary:** the Mac is the control plane, the Linux VM is the engine room. The user lives in the Mac app; the heavy robotics stack runs headless in the VM; the two talk over SSH/Tailscale; nothing is duplicated on both sides without a reason.

---

## 1. Principles

1. **Two sides, one product.** "Mac side" and "VM side" are one system with a wire between them, not two apps. Darkstar presents a single workstation view that merges both sides' state.
2. **The user never enters the VM desktop.** Everything the VM does is requested, observed, and stopped from the Mac app. The VM's GUI existing is an implementation detail (and, after the Xorg fixes, a fallback, not a workflow).
3. **Compute follows the workload, not convenience.** Each tool runs where it runs best per its *verified* platform support — not where it happens to be installable. "It can be made to run on macOS" is not a placement reason (ROS 2 Tier 3 is the standing example).
4. **No silent duplication.** A tool lives on exactly one side unless the placement matrix names a deliberate split (Gazebo: server in VM, viewer on Mac). Duplicated stacks (e.g. Docker Desktop on Mac *and* Docker in the VM) are called out as waste, not redundancy.
5. **Honesty crosses the wire unchanged.** The Phase 1 evidence model (installed / configured / compatible / operational; READY / MISCONFIGURED / INCOMPATIBLE / NOT INSTALLED / UNKNOWN) applies per side. A VM that is off or unreachable yields **UNKNOWN** for its side — never "broken," never a stale READY cached from yesterday.
6. **Core stays independently usable.** With the VM off or absent, the Mac app still does everything Mac-side: embedded lab, QGroundControl, preflight of the host, catalog browsing. The VM is an engine, not a single point of failure for the whole product.

## 2. The two sides

### Mac side — control plane (native, always available)

| Responsibility | Why here |
|---|---|
| Darkstar UI: dashboard, library, preflight, reports, photo intake | Instant, laptop-native, the user's home |
| VM lifecycle: start / stop / console / SSH (already shipped via `utmctl` + Tailscale) | Only the host can manage the guest |
| Embedded Firmware Lab: PlatformIO, Arduino IDE, ESP-IDF, STM32CubeIDE, Zephyr/west, OpenOCD | All officially support macOS hosts (catalog-verified); hardware is plugged into the Mac |
| QGroundControl | Native macOS 13+ build; talks to vehicles over USB/network regardless of the VM |
| MAVSDK-based companion code | Library with macOS arm64 wheels; runs wherever the calling code runs |
| PX4 SIH; PX4 SITL (optional) | In-PX4 simulator needs no Gazebo; PX4 officially supports macOS dev |
| Sim **visualization**: Foxglove or Gazebo GUI as a *viewer* | Moves 3D rendering — the main VM tax — to the laptop GPU |
| Update checks, catalog, stack definitions | Data, not compute |

### VM side — engine room (Omega-Ubuntu, Ubuntu 24.04 ARM64, headless-first)

| Responsibility | Why here |
|---|---|
| ROS 2 Jazzy (ros-base today; desktop pieces only if a workflow needs them) | Tier 1 platform is Ubuntu 24.04 only; macOS is Tier 3/unsupported |
| Gazebo Sim Harmonic — **server only** (`gz sim -s`) | Official ros_gz pairing for Jazzy; guest 3D rendering is the VM tax, so the server runs graphics-free |
| RViz2 / Nav2 when a workflow needs them | ROS packages; they live where ROS lives |
| Micro XRCE-DDS Agent | Linux bridge component for PX4 ↔ ROS 2 |
| PX4 Autopilot SITL + the verified golden-demo stack | The recorded, reproducible environment is Linux |
| The Phase 1 workstation auditor (guest-side probes) | Ground truth about the guest must be measured *in* the guest |
| Docker (Engine, in-guest) when a workflow needs containers | Docker-on-Mac is itself a VM; one VM, not two |

**Resource shape (current, deliberate):** 6 vCPUs / 8 GB RAM for the guest — ARM binaries under UTM run near-native; the budget is spent on CPU, not guest graphics. Disk expansion 30G → ~100G remains a queued maintenance item before heavy stack growth.

## 3. The wire

- **Transport:** SSH over Tailscale (proven live 2026-10-23: Torque and the app reach `omegaubuntu` at its tailnet address; the app already ships SSH/VM controls). No new networking layer is introduced.
- **Mac → VM flows:** lifecycle commands (start/stop via `utmctl` on the host side), remote command requests (run auditor, launch headless sim, stop sim), file pulls (audit results, logs, evidence).
- **VM → Mac flows:** structured results, not screen-scrapes — `audit.json` from the auditor, sim topics via the viewer connection (foxglove_bridge / ros_gz_bridge inside the guest, or a gz-transport session the Mac GUI joins), log streams on request.
- **Every remote action is a named, bounded operation** with a start, an observable effect, and a stop — in the same spirit as the Phase 1 rule that nothing installs automatically. Darkstar shows *what will run where* before it runs.
- **Offline behavior:** if Tailscale/SSH is down, the Mac side reports the VM side as UNKNOWN with the reason (VM off / host asleep / network unreachable — whichever was actually observed), and Mac-side work continues.

## 4. Placement engine — how Darkstar decides, per tool

The catalog already carries each tool's verified platforms and version constraints. The split design adds one field of meaning per tool: its **placement class**.

| Class | Meaning | Members (from the catalog) |
|---|---|---|
| `mac-native` | Runs on the Mac; Darkstar detects/manages it there | QGroundControl, VS Code, PlatformIO, Arduino IDE, ESP-IDF, STM32CubeIDE, Zephyr, OpenOCD |
| `vm-only` | Linux-side in practice; Darkstar detects/manages it in the guest | ROS 2, Nav2, Micro XRCE-DDS Agent |
| `split` | Deliberately divided: compute in the VM, presentation on the Mac | Gazebo (server in VM / GUI viewer on Mac), RViz2 (in-guest when needed / Foxglove on Mac as the usual viewer) |
| `either` | Both sides legitimate; Darkstar follows the *selected stack's* rule, never installs both silently | PX4 (SITL/SIH on Mac; full Gazebo stack in VM), MAVSDK (follows the calling code), Docker (VM by policy — see principle 4) |

Rules:
- Placement is evaluated **per selected stack**, exactly like readiness: an unselected tool's placement is not computed and its absence anywhere is neutral.
- A tool found on the "wrong" side (e.g. a macOS ROS source build) is reported factually — installed there, class `vm-only`, compatibility per the catalog's rules — not hidden and not celebrated.
- Pairing rules (Jazzy ↔ Harmonic, Tier 1 Ubuntu per distro, QGC's Ubuntu 22.04 gap) are enforced from the catalog's compatibility rules, on whichever side they apply.

## 5. Efficiency rules (the "optimized" half)

1. **Headless by default in the guest.** Sim servers, bridges, and the auditor run without a desktop session's overhead; the guest desktop is a fallback for diagnosis, not a runtime.
2. **Rendering lives on the Mac.** Any 3D or heavy visualization is a Mac-side viewer connected to VM-side state. This is the single biggest performance decision in the design.
3. **One VM, one stack.** No Docker Desktop on the Mac alongside the guest; no second hypervisor; no duplicate ROS installs across sides.
4. **Start on demand, stop when done.** The Mac app starts the VM when a VM-side workflow is chosen and offers to stop it after — the guest's 8 GB reservation is not held idle all day. (Host guidance already established: stay plugged in for builds; one browser in the guest at a time.)
5. **Results are cached as evidence, labeled with when they were measured.** Re-probing everything on every screen is waste; showing stale results as fresh is dishonesty. The middle path: timestamped evidence, cheap re-check on demand ("Re-check everything" already exists in Settings).

## 6. What the user sees

- **Dashboard:** one workstation, two zones — Mac side (native state) and Runtime/VM side (state + why), each with its own honesty chips. VM off reads as off/UNKNOWN, not as an error.
- **Application Library:** every entry carries its placement class ("On this Mac", "In the Linux runtime", "Split — sim in runtime, viewer on Mac"), and stack readiness is computed across both sides: a stack is READY only when every selected component is ready *on its own side* and the wire between them is up.
- **Workflows:** choosing a VM-side workflow shows the sequence up front — start runtime → wait until ready (observed, not assumed) → run → view on the Mac → stop when done.

## 7. Build sequence

1. **Remote auditor run** (first proof, queued): Mac requests → auditor runs in Omega-Ubuntu over SSH → `audit.json` returns → Mac displays the compatibility report. Validates the wire, the evidence model, and the guest's real state in one move. *Blocked only on the VM being up.*
2. **Headless sim + Mac viewer proof:** `gz sim -s` in the guest; Mac-side viewer connects; success = live sim state visible on the Mac while the guest renders nothing.
3. **Placement in the Library UI:** placement class shown per catalog entry; cross-side stack readiness.
4. **Lifecycle polish:** one-click workflow runs (start → ready → run → stop) with observed states at each step.

## 8. Open decisions (Abel's calls, none blocking the design)

- **Default Mac viewer:** Foxglove (topic-centric, bridge needed in guest) vs Gazebo GUI on the Mac (joins the gz session natively). Design supports both; a default keeps the first proof simple.
- **PX4 SITL default side:** Mac (lighter, no VM needed for logic tests) vs VM (matches the verified stack exactly). Design default: Mac for SIH/logic, VM whenever Gazebo or ROS is in the loop.
- **Guest desktop:** keep the (fixed) Xorg desktop as a diagnostic fallback, or strip the guest to purely headless once the remote flows are proven? Revisit after step 2.

## 9. Resource awareness & management (added 2026-10-24, Abel approved)

The split only helps if users can *see* it working. A 16 GB host running an 8 GB VM, a browser, AI desktop apps, and an IDE oversubscribes memory — and macOS pays for the overflow in compression CPU, which users feel as "everything is slow" with no visible cause. Darkstar's job is to make resource state knowable and manageable without turning the user into a system administrator. Three verbs: **know, show, manage.**

### Know — measure both sides

- **Host probes (Mac side):** total RAM, memory used, memory pressure, compressed memory, swap, free disk, and the top memory consumers *by name*. (macOS exposes all of this; the current Preflight already reads host RAM/disk — this extends the same probe set.) Design reference point, measured live on the reference machine (M1 Pro, 16 GB): 13.3 GB used, 6.0 GB compressed with the VM + browser + AI apps up — pressure is a real, measurable state, not a vibe.
- **Guest probes (VM side):** over the same SSH channel the auditor uses — guest RAM free/total, CPU load, disk free. Guest state is part of the workstation picture only when freshly measured; otherwise it is UNKNOWN (§1, principle 5).
- **Stack cost cards:** every catalog stack carries resource requirements per side (extending the catalog's existing `system_requirements` seed, e.g. the PX4 stack's disk floor): VM RAM/cores, Mac-side RAM for viewers/tools, disk per side. Costs are data in the catalog, verified the same way as compatibility claims — vendor-documented where a vendor states them, marked as our operational estimate where they don't.

### Show — one picture, one verdict

- **Headroom bar** on the Dashboard: total RAM → VM reservation → measured free, with the selected stack's cost overlaid.
- **One verdict word per stack: FITS / TIGHT / WON'T FIT**, computed from measured headroom vs. the stack's cost card. This is a *presentation verdict over measurements*, deliberately separate from the Phase 1 status taxonomy (READY / MISCONFIGURED / …) — the two must never be conflated, the same way the three existing taxonomies stay separate.
- **The blocker is named in one sentence** when the verdict isn't FITS: "Tight — Firefox is using 3.1 GB" or "Won't fit — the runtime needs 8 GB and 5.2 GB is free." No raw metric is shown without its verdict; no verdict is shown without its evidence timestamp.

### Manage — modes, not settings

- **Workflow buttons own the sequence:** "Start PX4 Lab" = check headroom → start VM → wait until ready is *observed* → launch headless sim → open the Mac-side viewer. "Stop" reverses it and releases the VM's reservation. The user picks *what*; Darkstar owns *where* and *whether it fits*.
- **Focus presets** for the known contention patterns: **VM Build** (runtime up; suggests freeing memory from local AI), **Local AI** (VM suspended, its memory actually released to the host), **Mac Only** (runtime off). Presets change Darkstar-managed state only.
- **Hard rule: Darkstar never kills or suspends the user's own apps.** It names heavy consumers and offers one-tap quit *suggestions*; the decision is always the user's. (Same doctrine as dependencies: explained and approved, never silent.)
- **Guardrails:** starting a VM-side workflow under high measured pressure warns first, with the named blocker; ending a workflow offers suspend (fast resume) vs. stop (full release); two hypervisors or Docker Desktop detected alongside the runtime is surfaced as a factual conflict, in the catalog's conflict style — not a scolding.

### Simplicity rules (binding on the UI)

1. The user thinks in "can I run this now?" — every surface answers that question first.
2. One number, one word, one sentence: headroom figure, verdict, blocker. Depth lives one click down (Preflight/audit detail), never on the Dashboard.
3. Nothing about resources is ever a settings page of dials. If a choice matters, it is a preset or a workflow button.
4. Estimates are labeled as estimates; measurements carry timestamps; anything unmeasured is UNKNOWN.

**Sequencing:** host pressure probes + headroom bar land with Build Sequence step 3 (placement in the Library UI); stack cost cards land with the catalog's next revision; focus presets land with step 4 (lifecycle polish). The guest-side probes ride the step-1 remote auditor session — one more reason that session is the first proof.
