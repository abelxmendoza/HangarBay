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
