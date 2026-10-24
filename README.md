# Darkstar Robotics

<p align="center">
  <img src="docs/logo.png" alt="Darkstar Robotics — BUILD • EXPLORE • DEPLOY" width="320">
</p>

*BUILD • EXPLORE • DEPLOY*

A native macOS app (Swift + SwiftUI) — a robotics development
workstation that gives budding roboticists one friendly place for
robotics development on their MacBook:

- **Dashboard** — live state of the managed Linux runtime (UTM VM), the
  active Ubuntu/ROS/Gazebo pairing, PX4 SITL, and the Tailscale link.
- **Preflight** — a prerequisite checklist that probes this Mac and the
  runtime (memory, disk, Xcode, UTM, VM state, Tailscale, ROS 2, Gazebo,
  PX4), gives each failed item a one-click remedy where one exists, and
  lists every heavy dependency with its size, source, and download state.
- **Environments** — validated pairings (Ubuntu 24.04 + ROS 2 Jazzy +
  Gazebo Harmonic today; Ubuntu 22.04 + ROS 2 Humble next). Pick what you
  want to build, never which versions "go together".
- **Hardware** — photo/scan intake: drop a picture of a board, flight
  controller, label, or QR code and the fleet starts from what you own.
  (Recognition engine plugs in behind this intake.)
- **Missions** — the PX4 swarm-recovery golden demo with its verified
  evidence (PASS · 8.095 m min separation · 641 samples · 2 reassignments).
- **Viewer** — embedded replay/telemetry viewing.

The Linux side runs in a managed runtime under the hood (the Omega-Ubuntu
UTM VM is the working prototype, built and tuned Oct 2026). The user never
touches a terminal, an apt lock, or a version matrix.

## Why I built it

Darkstar Robotics started with two things I care about: robotics and the experience of using a MacBook.

After reading Steve Jobs' biography and spending years with iPhones and MacBook Pros, I became a fan of Apple's attention to design. A MacBook is lightweight, portable, and powerful enough to work from almost anywhere—even comfortably reclining with it on my lap. I wanted that ease of use to carry over into robotics development.

But much of the robotics ecosystem is built around Linux. When I started working with ROS 2, PX4, Gazebo, and their surrounding frameworks, getting the right versions and dependencies running on a Mac was a project in itself. I spent time wrestling with virtual machines, setup instructions, terminal commands, and failures that were hard to distinguish from bugs in my own code. At one point, even the browser inside my VM was breaking because of its graphics/session configuration; changing the Wayland-related setting resolved it. That's the kind of obscure environment issue a beginner shouldn't have to diagnose just to start learning robotics. I don't want the next MacBook user getting started in robotics to have to struggle through all of that.

That's why I'm building Darkstar: a native macOS front end for Linux-based robotics workflows, with compatible environments, clear preflight checks, actionable fixes, and visible simulation and test evidence. The aim isn't to replace Linux or hide how robotics works. It's to make those tools easier to access from a computer people already enjoy using.

I want students, independent builders, and robotics teams—especially MacBook users new to these stacks—to spend less time fighting their setup and more time building, experimenting, and learning. Darkstar starts with the problems I've encountered firsthand and grows as the workflows are tested and improved.

**Build the robot. Explore the system. Deploy with evidence.**

## Run it

Open `Package.swift` in Xcode and press Run — or:

```
swift run
```

Requires macOS 14+. Settings (⌘,) holds the VM name and SSH target.
The Swift package/target is still named `RoboticsControlCenter`
internally; the product name is Darkstar Robotics (renamed from
Hangar Bay on 2026-10-23 — the GitHub repo keeps its original name
for now).

## Status

v0.4 — Error handling + test suite, 2026-10-24. New DarkstarCore
library: typed errors with plain-language messages and recovery
suggestions for every failure the app can hit (missing utmctl, failed
probes, blocked cleartext replay URLs, update-check failures), surfaced
in the UI instead of silently swallowed. 52 automated tests (unit,
integration, end-to-end) verified on macOS and Linux toolchains. The
installer now validates its payload version, stages the install, and
rolls back on failure. Release packaging: bundles are ad-hoc
code-signed and zipped with ditto on a Mac so downloads open with the
standard unsigned-build prompt. App icon baked into the bundle.

v0.3 — Darkstar Robotics rebrand, 2026-10-23. New user-supplied star
emblem logo; palette retuned to the rebrand system (Starfire #FF4A2F
primary, Ember #FF785A, Signal Cyan #00CFFF instrumentation, System
Green #28D97A verified success only, Alert Red #F64D4D errors only).
Honesty taxonomy unchanged; all runtime behavior preserved.

v0.2 — DARKSTAR design foundation, 2026-10-23 (see
`docs/DARKSTAR-UI-UX-PLAN.md`). Obsidian/gunmetal theme tokens, branded
sidebar, mission-control Dashboard, and the honesty taxonomy as a UI
component: every status is chipped LIVE, RECORDED, DEMO, PENDING, or
UNKNOWN — telemetry green means verified success only; signal red is
brand + alerts only. All v0.1 runtime behavior preserved.

v0.1 — first native build, written 2026-10-23. Runtime probes are real
(utmctl, Tailscale CLI, FileManager). In-runtime checks (ROS/Gazebo/PX4)
currently show their out-of-band verified state and move in-app with the
runtime bridge. Provisioning/download engine lands with the packaging step
(one setup script + golden image) described in the project notes.
