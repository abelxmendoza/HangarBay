# Research: Reducing Robotics Setup Friction on MacBooks

Research snapshot: 2026-10-24. This document separates external documentation from the founder's personal experience. It is a product research note, not a claim that every proposed Darkstar feature already works.

## Core finding

There is a real integration problem, but **macOS is not universally unsupported**. PX4's current documentation supports macOS development, including Gazebo simulation, while its platform matrix lists **ROS 2 with Gazebo simulation** on Ubuntu/Windows but not macOS. The gap Darkstar can target is the *end-to-end, reproducible experience*, not simply installing PX4.

Sources:
- PX4 development platform matrix: https://docs.px4.io/main/en/dev_setup/dev_env
- PX4 macOS development environment: https://docs.px4.io/main/en/dev_setup/dev_env_mac

## External findings and product implications

| Finding from upstream documentation | What it means for users | Candidate Darkstar response |
| --- | --- | --- |
| PX4's macOS setup requires Xcode CLI tools, Homebrew, Python environment, and additional simulator tooling; the macOS guide also notes file-descriptor limits and XQuartz setup. | Installation has multiple hidden prerequisites and machine-specific state. | Detect prerequisite versions and limits; offer explicit, reversible remedies and a source/size manifest. |
| PX4 supports native macOS Gazebo SITL, but its matrix does not mark ROS 2 + Gazebo simulation as a macOS target. | Native macOS support must not be conflated with support for every integrated robotics workflow. | Offer native PX4 workflows when supported, and a Linux VM workflow for ROS 2 integrations; label each pathway's support level. |
| Gazebo's ROS integration guide identifies ROS 2 Jazzy + Gazebo Harmonic as a recommended combination; other pairings may require caution or be incompatible. | Version selection is an engineering decision, not just choosing the newest package. | Maintain an upstream-sourced, versioned compatibility catalog; block known-incompatible presets, warn on experimental pairings. |
| Gazebo Harmonic documents Ubuntu Noble/Jammy binaries, while macOS and ARM are best-effort platforms in its support notes. | CPU architecture and platform affect support expectations. | Detect Apple Silicon vs Intel and guest architecture; distinguish tested, best-effort, and unsupported combinations. |
| Gazebo installation docs warn of package conflicts between Gazebo Classic and Harmonic. | Mixing simulator generations can break an environment. | Isolate stacks and detect conflicting packages before installation. |

Sources:
- https://gazebosim.org/docs/jetty/ros_installation/
- https://gazebosim.org/docs/harmonic/install/
- https://gazebosim.org/docs/harmonic/install_ubuntu/
- https://docs.px4.io/main/en/dev_setup/dev_env_mac

## Founder-reported incident (not independently reproduced)

A browser in the founder's Ubuntu VM malfunctioned under a Wayland-related graphics/session configuration; changing that setting resolved the issue. The exact VM display adapter, browser, logs, and changed setting have not yet been recorded. **Do not assert that Wayland itself was definitively the root cause.** Treat this as a reproducible-investigation candidate.

Proposed incident record fields: host Mac model/chip, macOS version, UTM version, VM image/architecture, Ubuntu version, Wayland/X11 session, virtual GPU/display settings, browser/version, reproduction steps, screenshots/logs, exact fix, rollback steps, and regression result.

Potential Preflight check: detect session type and rendering configuration; show a diagnostic with evidence, never silently force a display-server change.

## Prioritized experiments (not completed)

1. **Baseline matrix:** clean install on Apple Silicon and Intel where available; record VM boot, network, graphics, SSH, ROS discovery, Gazebo headless, Gazebo GUI, PX4 SITL, and telemetry replay.
2. **Preflight provenance:** every check records command, observed output, expected condition, timestamp, host/guest context, and confidence; never report success from static demo data.
3. **Compatibility lockfiles:** pin OS, ROS distro, Gazebo release, PX4 revision, architecture, and installer hashes for a known-good preset.
4. **Recovery UX:** reproduce a graphics/session failure, then test a safe, opt-in remedy with rollback.
5. **User outcome study:** compare time-to-first-working-simulation, manual commands, unresolved errors, and recovery time against upstream instructions.

## Scope and differentiation

Existing PX4 and Gazebo documentation already provide installation paths; Darkstar should **not** claim that Mac users cannot run these tools today. The proposed differentiation is a native, beginner-friendly orchestration layer with validated combinations, visible diagnostics, recoverable provisioning, and evidence-backed simulation outcomes.

Research limitations: these are documentation-based findings. No user study, cross-platform benchmark, or fresh runtime validation was conducted for this research note. Recheck upstream support tables before encoding them as hard policy.
