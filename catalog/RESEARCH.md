# Darkstar Robotics — Application Library Research Report

Date: 2026-10-23 · Companion file: `catalog/catalog.json` (schema_version 1) · Branch: `research/application-library-catalog` (not merged to main)
Scope of this pass: 15 tools only, official documentation only, no code touched, nothing installed.

## 1. Scope & method

1. Read the Phase 1 spec and the 2026-10-23 catalog proposal in full first. The catalog is built to the spec's model: four states (installed / configured / compatible / operational), statuses READY / MISCONFIGURED / INCOMPATIBLE / NOT INSTALLED / UNKNOWN, dependency types Required / Optional / Alternative with a mandatory human `why` on every dependency, and the founding principle that a stack is a *preset selection, not a bundle*.
2. Researched each tool on its official documentation site only (docs.ros.org ecosystem, gazebosim.org, docs.px4.io, docs.qgroundcontrol.com, mavsdk.mavlink.io, code.visualstudio.com, docs.docker.com, docs.platformio.org, docs.espressif.com, docs.arduino.cc, st.com, docs.zephyrproject.org, openocd.org). Blogs, Wikipedia, forums and third-party mirrors were excluded.
3. A claim is `"evidence": "verified"` only if a researcher actually opened the official page and saw it stated. Everything else — spec-derived, proposal-derived, search-snippet-only, or inferred — is `"evidence": "proposed"`. Per-tool `sources` arrays hold the exact fetched URLs.

## 2. Sources actually fetched (by tool)

| Tool | Official pages fetched |
|---|---|
| ROS 2 | https://reps.openrobotics.org/rep-2000/ (Tier 1/2/3 matrix, support windows, dependency floors) |
| Gazebo | https://gazebosim.org/ · https://gazebosim.org/docs/latest/getstarted/ · https://gazebosim.org/docs/harmonic/install_ubuntu/ · https://gazebosim.org/docs/harmonic/ros_installation/ (the pairing table) |
| RViz2 | https://index.ros.org/r/rviz/ |
| Nav2 | https://docs.nav2.org/rolling/ · https://docs.nav2.org/development_guides/build_docs/index.html · https://docs.nav2.org/development_guides/index.html |
| PX4 Autopilot | https://px4.io/ · https://docs.px4.io/main/en/index · …/dev_setup/dev_env_linux_ubuntu · …/dev_setup/dev_env_mac · …/dev_setup/dev_env_windows_wsl · …/ros2/user_guide · …/sim_gazebo_gz/ |
| QGroundControl | https://qgroundcontrol.com/ · https://docs.qgroundcontrol.com/Stable_V5.1/en/qgc-user-guide/index.html · …/getting_started/download_and_install.html (Stable V5.1 and master variants) |
| MAVSDK | https://mavsdk.mavlink.io/v1.0/en/ · https://mavsdk.mavlink.io/main/en/python/quickstart.html · https://mavsdk.mavlink.io/main/en/cpp/quickstart.html |
| Docker | https://www.docker.com/ · https://docs.docker.com/get-started/get-docker/ · …/engine/install/ubuntu/ · …/desktop/setup/install/linux/ubuntu/ · …/desktop/setup/install/windows-install/ · …/desktop/setup/install/mac-install/ · https://docs.docker.com/reference/cli/docker/system/info/ |
| VS Code | https://code.visualstudio.com/ · …/docs · …/Download · …/docs/getstarted/overview · …/docs/setup/windows · …/docs/supporting/requirements · …/docs/configure/command-line |
| PlatformIO | https://docs.platformio.org/en/latest/integration/ide/pioide.html · …/en/latest/integration/ide/vscode.html · …/en/stable/core/installation/methods/installer-script.html · …/en/stable/core/userguide/index.html |
| ESP-IDF | https://docs.espressif.com/projects/esp-idf/en/latest/esp32c5/get-started/index.html · …/get-started/linux-setup.html · https://docs.espressif.com/projects/esp-idf/en/v5.2/esp32p4/get-started/linux-macos-setup.html |
| Arduino IDE | https://www.arduino.cc/en/software · https://docs.arduino.cc/software/ide · …/ide-v2/tutorials/getting-started/ide-v2-downloading-and-installing |
| STM32CubeIDE | https://www.st.com/en/development-tools/stm32cubeide · UM2563 installation guide (Rev 7, Feb 2026, PDF) · RN0114 release notes v2.2.0 (PDF) |
| Zephyr | https://zephyrproject.org/faqs/ · https://docs.zephyrproject.org/latest/develop/getting_started/index.html · …/develop/west/index.html · …/develop/toolchains/zephyr_sdk.html |
| OpenOCD | http://openocd.org/doc/html/index.html · https://openocd.org/doc/html/About.html (homepage and the guide's "Running" chapter failed to fetch — rate-limited) |

Not fetched (canonical URLs used in the catalog but not verified this pass): ros.org and the docs.ros.org install pages (fetch blocked by the site's bot check), platformio.org homepage, MAVSDK's unversioned main-branch index (fetch failed), openocd.org homepage.

## 3. Verified vs. proposed split

112 evidence-tagged claims in `catalog.draft.json`:

| Claim class | Verified | Proposed |
|---|---|---|
| Tool platform entries | 36 | 1 |
| Detection methods | 28 | 7 |
| Version constraints | 27 | 5 |
| Compatibility rules | 7 | 1 |
| **Total** | **98** | **14** |

The single proposed compatibility rule is the **Zephyr SDK ↔ Zephyr version matrix** (the SDK docs defer to a matrix page that wasn't fetched — no pairing numbers asserted). The other proposed items cluster where official docs are genuinely silent: no documented `--version` probe for QGC, `west --version` and `openocd --version` not stated on fetched pages, `ros2 --version`/apt variant names (docs.ros.org blocked), MAVSDK's `pip show` check (our probe for their documented package, not their documented command), OpenOCD's host-OS list, PlatformIO's `framework = espidf` key, and RViz2's membership in the `desktop` install variant.

Headline verified rules the Phase 1 resolver can enforce immediately:
- REP 2000 Tier 1 pairings: **Jazzy ↔ Ubuntu 24.04, Humble ↔ Ubuntu 22.04** (Windows 10 is also Tier 1 for both; macOS is Tier 3 only).
- Official ros_gz table: **Jazzy ↔ Harmonic, Humble ↔ Fortress** recommended; **Jazzy + Fortress/Ionic/Jetty and Humble + Ionic/Jetty are incompatible** — the spec's anticipated conflict is real.
- PX4's current guide recommends **ROS 2 Jazzy on Ubuntu 24.04** (superseding older docs' Humble recommendation — do not carry the old pairing forward), and PX4's setup installs **Gazebo Harmonic** by default.
- QGC binaries do **not** cover Ubuntu 22.04 (build-from-source only) — a real constraint for 22.04-targeted stacks.

## 4. Gaps in the existing 25-entry proposal

1. **No detection story at all.** The proposal lists names, a category, and a one-line platform guess per tool — no commands, paths, or packages. Every detection method in the draft catalog is new work, and several tools turn out to be awkward to detect honestly (QGC has no documented version probe; STM32CubeIDE has no CLI; OpenOCD is usually a bundled component, not an install).
2. **Kinds are loose or missing.** MAVSDK sits in "SDKs" alongside applications with no marker that it is a *library you import/link*, with per-language installs. PX4 is listed as "Autonomy" with no marker that it is a *source checkout you build*, so "installed" for PX4 really means checkout + built `build/px4_sitl_default/bin/px4`. RViz2 and Nav2 are ROS *packages* (their detection is package presence inside a distro), which the proposal's app-style framing hides.
3. **Platform labels are wrong or vague in places.** "ROS 2 · Linux/Windows" omits that Tier 1 is exactly one Ubuntu LTS per distro and macOS is Tier 3. "Gazebo · Linux preferred" hides the strict ros_gz pairing table. "QGroundControl · Mac/Win/Linux" hides that current binaries skip Ubuntu 22.04.
4. **The embedded half of this assignment is absent.** The proposal's only embedded-adjacent entry is PlatformIO. ESP-IDF, Arduino IDE, STM32CubeIDE, Zephyr/west and OpenOCD — the whole Embedded Firmware Lab stack — have no entries, no categories ("Embedded Development" doesn't exist in its category list), and no dependency grammar for framework-vs-IDE alternatives (ESP-IDF vs Arduino IDE vs PlatformIO frameworks).
5. **No version knowledge.** Nothing in the proposal could produce an INCOMPATIBLE verdict: no pairings, no conflicts, no floors (Docker Desktop's Windows/WSL floor, CubeIDE's 64-bit-only rule, ESP-IDF's Python/CMake floors are all absent).
6. **Vendor self-contradiction is unhandled.** ST's installation guide (UM2563 Rev 7) and its current release notes (RN0114) list *different* supported Ubuntu/Fedora versions for STM32CubeIDE. The proposal's model has no way to say "pin this claim to a product release" — the draft handles it as a version constraint with both sources attached; the schema should expect more cases like this.

## 5. High-value additions only

Kept deliberately short, per the assignment's "small and accurate over large and unreliable":

- **Micro XRCE-DDS Agent** — PX4's ROS 2 guide makes the agent (companion-computer side of uXRCE-DDS) a distinct installable component that the PX4 stack's *operational* state depends on; today it is invisible inside the PX4/ROS 2 entries. It has an official home (eProsima docs) and a clean detection story (the `MicroXRCEAgent` binary). This is the one addition that changes stack correctness.
- Nothing else. The remaining 10 proposal entries (Foxglove, Webots, OpenCV, Mission Planner, ArduPilot, PlotJuggler, MuJoCo, Isaac Sim, CoppeliaSim, MoveIt 2, micro-ROS, Open3D, RealSense SDK, Open-RMF, Wireshark) should stay out until a stack needs them *and* the same fetched-evidence pass has been run — adding names without detection/compatibility evidence recreates the proposal's core gap.

## 6. Assumptions

- Catalog `kind` assignments: Docker is typed `application` (its user-facing forms are Engine-as-service and Desktop-as-app; neither `cli` nor `framework` fits both), PlatformIO is typed `ide` (extension-first, with a real CLI core), ESP-IDF is typed `framework` (its own name/docs), Zephyr is one entry covering RTOS + west + Zephyr SDK as named components rather than three entries.
- QGC platform claims use the **Stable V5.1** guide (the current stable), with the master-docs macOS floor difference (14.4+) recorded as a constraint note rather than silently picking one.
- ESP-IDF detection covers both the current EIM-managed install and the legacy `~/esp/esp-idf` + `export.sh` flow (legacy was default before ESP-IDF v6.0); a machine may have either.
- Detection entries carry two extra fields beyond the requested shape — `evidence` and `sources` — because the evidence rules require knowing which probes are doc-confirmed vs. inferred (e.g. `gz sim` is doc-confirmed as the launch command; `openocd --version` is not).
- Stack `targets` are descriptive strings, not the spec's structured `{os, release, arch}` objects; the PX4 stack additionally carries the spec sketch's 40 GB disk floor as an extra `system_requirements` object, marked proposed (it is our operational lesson, not a vendor requirement).
- `homepage` for ROS 2, PlatformIO, MAVSDK and OpenOCD points at the canonical site even where the fetch of that exact page failed; the report's source table (§2) is the record of what was actually opened.

## 7. Decisions for the primary agent

1. **Detection evidence fields:** keep or drop the extra `evidence`/`sources` on detection entries? Recommended: keep — the resolver needs to know which probes are trustworthy (QGC/`west`/`openocd` version probes are currently unverified).
2. **File placement & format:** the spec's stack schema is YAML-authored with a JSON Schema underneath, while this catalog is JSON. Decide whether the shipped catalog is (a) one JSON file as drafted, (b) JSON for tools/rules + one YAML per stack per the spec sketch, before the resolver is built against it.
3. **docs.ros.org verification pass:** the ROS 2 install-page claims (apt variant names `ros-<distro>-desktop`/`-ros-base`, RViz2-in-desktop) are proposed solely because the site blocked fetching. Someone with browser access to docs.ros.org should confirm or strike them — ROS 2 is the catalog's root dependency, so its entry should not carry proposals.
4. **Fetch the Zephyr SDK compatibility matrix** (GitHub, linked from the SDK docs) before encoding any SDK-version pairing; the draft deliberately asserts none.
5. **STM32CubeIDE claim pinning:** decide the policy for vendor self-contradictions — the draft's approach is "constraint entry with both sources, pin to a release at enforcement time." Confirm that's the house rule.
6. **Micro XRCE-DDS Agent:** add as a 16th tool (recommended in §5) or model it as part of the PX4↔ROS 2 pairing rule? It has its own install/detection lifecycle, which argues for a tool entry.
7. **QGC detection on Windows** has no doc-confirmed path or probe; decide whether Windows QGC detection waits for the Windows inspector phase (Phase 1 is Linux-first per the spec) — the draft marks it proposed.
8. **OpenOCD's standalone entry:** its host-OS support and version probe are unverified from its own docs, and most real installs are bundled copies. Decide whether OpenOCD ships in the catalog as a standalone tool, only as a component of Zephyr SDK / STM32CubeIDE, or both (draft: both, honestly labelled).

## 8. Claims that could NOT be confirmed from official docs

- ROS 2: exact install-page contents (apt package/variant names, desktop-variant definitions) and the verbatim "RViz2 ships in the desktop install" claim — docs.ros.org / ros.org blocked fetching (bot check). REP 2000 and the ROS index carried the platform/version facts instead.
- Gazebo: `gz sim --version` as a documented flag (launch command `gz sim` and the `gz-harmonic` metapackage are confirmed; PX4's macOS setup page does list `gz sim --versions` among its verification commands).
- MAVSDK: the unversioned main-branch introduction page (fetch failed); cross-platform wording verified on the v1.0 guide instead. No Micro XRCE-DDS agent version numbers are stated on PX4's fetched ROS 2 page.
- QGroundControl: any CLI version flag; an iOS install route (iOS is claimed as a platform but has no section on either fetched download page); the Windows install path.
- VS Code: per-OS setup pages for macOS/Linux were not fetched (requirements/download/CLI pages were); the requirements page deliberately gives a macOS *rule*, not a version number.
- PlatformIO: a formal Core host-OS list; the `framework = espidf` key on a fetched docs page (Registry search result only); the pip install page (search result only); the platformio.org homepage.
- ESP-IDF: an exhaustive supported-chip list on one page (per-chip guides verified for ESP32-C5 and ESP32-P4); the `idf.py --version` flag; the `idf.py openocd` detail (search result only).
- Arduino IDE: the exact installed bundle/binary name; any CLI version probe for IDE 2.
- STM32CubeIDE: which of ST's two conflicting OS lists is canonical per release; any CLI/headless detection command.
- Zephyr: `west --version`; exact Zephyr↔SDK version pairing numbers (compatibility matrix not fetched).
- OpenOCD: homepage content and the User's Guide "Running" chapter (fetches rate-limited); a standalone official install page, host-OS list, and the `openocd --version` flag from its own documentation.
- Docker: Engine support specifics for non-Ubuntu distros (only the Ubuntu Engine page was fetched); the literal `docker --version` output (the daemon probe `docker info` is the documented check and is what the catalog uses).

## 9. Reviewer validation (Torque, 2026-10-23)

- JSON validated programmatically: parses cleanly; 15 tools with unique ids; every `depends_on` target and every stack member resolves to a catalog tool; every dependency and stack member carries the mandatory `why`; all dependency types are within Required/Optional/Alternative; every claim tagged `verified` in platforms, version constraints, and compatibility rules carries at least one source URL. Evidence tally across all tagged claims (including detection): 98 verified / 14 proposed, matching §3.
- Independent spot-checks against official pages (reviewer-fetched, 2026-10-23): the ros_gz compatibility table on gazebosim.org (Harmonic docs, "Installing Gazebo with ROS") confirms Jazzy ↔ Harmonic recommended, Jazzy + Fortress/Ionic/Jetty incompatible, Humble ↔ Fortress recommended — exactly as encoded in the catalog's rules. The QGroundControl Stable V5.1 download page confirms AppImage support for Ubuntu 24.04/26.04 only, with 22.04 requiring a self-build — as encoded in the QGC entry.
- Not reviewer-verified: the remaining fetched-source claims rest on the research pass's recorded URLs (§2); the 14 proposed claims are listed in §3/§8 and must not be enforced until verified.
