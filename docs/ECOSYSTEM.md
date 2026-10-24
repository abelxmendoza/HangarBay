# Ecosystem: Hangar Bay × RobotForge

Status: architecture decision, recorded 2026-10-23. This document describes
a proposed integration boundary — **not** functionality already implemented.

## The two products

| | Hangar Bay | RobotForge |
| --- | --- | --- |
| Primary role | Native Mac workstation | Multiplatform robotics platform |
| Interface | SwiftUI, macOS-native | Muse-built, cross-platform |
| Application library | Local discovery, setup, launch | Shared application catalog and project integrations |
| Runtime | Local macOS/VM processes | Platform-independent orchestration |
| Robots | Local connections and diagnostics | Shared robot/project definitions |
| Simulation | Local launch and visualization | Portable workflows and results |

## Rules

1. **Separate repositories.** Two independently useful products with a clean
   integration boundary beat one enormous codebase. Do not merge them.
2. **No duplication.** Hangar Bay may one day provide a native Mac launcher
   for a RobotForge workflow rather than growing a second workflow engine
   (and vice versa).
3. **The shared seam is data, not code:** portable application definitions —
   each catalog entry describes supported operating systems, dependencies,
   installation methods, launch commands, and integration capabilities.
   Hangar Bay interprets those definitions for macOS; RobotForge could
   consume the same catalog for other environments.
4. **Hackathon boundary.** RobotForge is Abel's Meta Muse hackathon
   project. Its hackathon work happens in a separate repository created
   after the official rules are published (rules gate: Oct 26, 2026).
   Hangar Bay development continues independently and is never blocked by
   the hackathon; no RobotForge hackathon features are implemented here
   ahead of the start.
5. **Commit to the dependency only when it's proven.** RobotForge as the
   platform and Hangar Bay as its premium native Mac companion is the
   working hypothesis — it gets revisited after RobotForge's actual
   architecture and hackathon prototype exist.

## Platform strategy (recorded 2026-10-23)

Hangar Bay solves a *different* problem on each OS. Priority order:

1. **macOS — build now.** Robotics tooling is fragmented across native
   apps, Linux VMs, containers, and remote machines. The managed-runtime
   model (this app) is the answer; prove the application library,
   environment management, and robot workflows here first.
2. **Linux — prototype next.** The tools already run natively, so the
   product is not a launcher — it is a unified robotics *workspace
   manager*: application discovery with versions/dependencies,
   environment profiles (ROS distro, Python, sim config, workspace),
   robot fleet profiles, one-click multi-tool workflows, diagnostics
   (missing packages, version conflicts, network, misconfiguration), and
   reproducible environment export. Linux is the most important platform
   for validating whether that thesis provides real engineering value.
   It competes with Docker/devcontainers/launch files/shell scripts —
   it must be more convenient and reliable, not just prettier.
3. **Windows — expand later.** Focus on WSL2 integration, environment
   setup, and compatibility checks rather than assuming every tool runs
   the same way as on Linux.

**Detect capabilities; never assume.** Platforms differ in what they can
actually run (e.g., ROS 2 Jazzy is Tier 1 on Windows, while Gazebo
Harmonic officially targets Ubuntu amd64 with macOS/Windows best-effort).
Hangar Bay's preflight is the capability-detection layer that keeps this
honest.

**Future shape:** Hangar Core (shared application catalog, environment
definitions, robot profiles, diagnostics, launch specifications) under
Hangar Desktop (the native interface per OS). The SwiftUI app is *not*
rewritten in a cross-platform framework; Core gets extracted once the Mac
workflows are proven. Until then: keep logic in controllers and models,
views thin — that discipline is what makes the extraction possible.
