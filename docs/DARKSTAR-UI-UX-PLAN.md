# Hangar Bay — DARKSTAR UI/UX design plan

Status: design proposal only. Do not replace working runtime logic or claim sample/historical data is live.

## Visual system
- Industrial cyberpunk + aerospace mission control, with macOS-native usability.
- Tokens: Obsidian #090D13; Gunmetal #1C2630; Signal Red #FF553D; Telemetry Green #55D6A0; Frost #E9EEF3.
- Typography: clear sans-serif for primary UI, monospaced digits for telemetry, restrained condensed uppercase labels. Ensure contrast and keyboard navigation.
- Angular accents and subtle emissive highlights, no overwhelming neon.

## Information architecture
- Keep NavigationSplitView; build branded sidebar and persistent runtime/connection status.
- Dashboard: current host/runtime state, validated environment, mission quick access, contextual action.
- Preflight: grouped checks with timestamps, remedies, honest pending/unknown states.
- Environments: version compatibility profiles, provenance, resource estimates.
- Hardware: photo intake, confirm-before-configure, optional 3D fleet inspection.
- Missions: evidence-driven metrics, mission timeline, clear replay entry.
- Viewer: existing WKWebView first; enhance telemetry/timeline without replacing working renderer prematurely.

## 3D priorities
1. Lightweight optional drone/rover scene on Dashboard, with low-power static fallback.
2. Recorded PX4 replay with real telemetry, trajectory lines, time scrub, dropout and reassignment events.
3. Hardware inspection only for assets that exist and match identified devices.
Use RealityKit or SceneKit after validating macOS target/toolchain. Keep SwiftUI native. Metal/Canvas only where warranted. Avoid unnecessary dependencies.

## Motion/accessibility
- Functional transitions 150–300ms; subdued ambient motion.
- Respect Reduce Motion, high contrast, Dynamic Type where supported, keyboard focus, VoiceOver.
- Pause offscreen 3D and cap rendering costs; degrade gracefully on lower-end Macs.
- Red means alert/action, green means verified success, amber warning; never encode state in color alone.
- Distinguish LIVE, RECORDED, DEMO, PENDING, UNKNOWN. Do not label historical evidence as current telemetry.

## Delivery
Phase 0: screenshots, baseline performance and navigation audit.
Phase 1: design tokens + reusable status chips, cards, buttons, header/sidebar.
Phase 2: dashboard and preflight hierarchy; maintain existing runtime behavior.
Phase 3: missions/replay interaction and evidence provenance.
Phase 4: opt-in 3D hardware and motion polish, profiling, accessibility tests.

## Acceptance criteria
- No regression in start/stop VM, console/SSH, checks, image intake, or embedded viewer.
- Zero fake operational statuses; action feedback includes progress/error.
- Usable at compact window sizes, keyboard-only, Reduce Motion.
- No permanent GPU-heavy animation; test idle CPU/GPU impact.
- Every primary task accessible in <=3 intentional interactions.
- Before implementation, produce screenshots/wireframes and compare to baseline.

## Current code observations (2026-10-23)
- ContentView.swift uses NavigationSplitView and six SidebarSection cases.
- DashboardView.swift uses adaptive cards for VM, pairing, PX4, and Tailscale.
- PreflightView.swift renders checks and sample dependency download rows.
- HardwareView.swift has photo import/drop and an in-memory sample fleet.
- MissionsView.swift presents recorded swarm-recovery evidence and opens localhost replay.
- ViewerView.swift embeds localhost replay with WKWebView.
- Package.swift targets macOS 14+, Swift tools 5.9.

This document is a visual/UX brief, not implementation approval.