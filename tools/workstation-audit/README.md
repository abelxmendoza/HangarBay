# Darkstar Robotics — Phase 1 Workstation Audit

A dependency-light, **read-only** auditor that inspects a robotics
workstation and produces an evidence-backed report: which robotics tools
are installed, which versions are compatible, what's missing, and what
needs attention.

> Darkstar Robotics — Spend less time setting up. Spend more time building robots.

This is the Phase 1 diagnostic engine described in
`phase1-spec.md` (§1–§4): the compatibility engine, not a catalog and
not an installer.

## Hard guarantees

- **Read-only.** Nothing is installed, modified, configured, started, or
  stopped. Probes only read files (`/etc/os-release`, `/opt/ros/*`),
  look up binaries on `PATH`, and run read-only queries
  (`gz sim --version`, `docker --version`, `docker info`), plus — inside a
  throwaway subshell — sourcing a ROS distro's own `setup.bash` and
  running `ros2 doctor --report`, the operational probe the spec names
  for ROS 2. The system is never touched.
- **No sudo** for the basic audit. **No network.** Python 3 standard
  library only — no pip installs.
- **No fabricated results.** Every status carries the probe and the
  observed value behind it.
- **No simulator smoke tests** in this version. A simulator's
  operational state is therefore *not assessed* and READY is never
  claimed for it (see Statuses).
- **An absent optional tool never degrades readiness.** Optional items
  are reported as information only.

## Target stack (Phase 1)

PX4 Drone Development: Ubuntu **24.04** · ROS 2 **Jazzy** · Gazebo
**Harmonic** · ≥ **40 GB** free disk. Pairing rules live as data in
`darkstar_audit/rules.py` (Jazzy ↔ Ubuntu 24.04, Humble ↔ Ubuntu 22.04;
Harmonic ↔ Jazzy, Fortress ↔ Humble, Garden ↔ Iron).

## Run it

```bash
cd tools/workstation-audit
python3 audit.py --out-dir ./audit-output
# optional: --disk-path /path/to/filesystem   (default: /)
```

Outputs, both generated from the same findings so they cannot disagree:

- `audit.json` — machine-readable evidence (for later import into the
  Darkstar Robotics macOS app's Diagnostics).
- `audit.md` — the same report, human-readable.

Exit code is 0 whenever the audit itself ran. Findings are a report,
not a pass/fail gate.

### Run it on Omega-Ubuntu (first validation target)

Copy or clone this repo onto the Ubuntu 24.04 machine, then inside it:

```bash
cd HangarBay/tools/workstation-audit
python3 audit.py --out-dir ~/darkstar-audit-output
cat ~/darkstar-audit-output/audit.md
python3 -m json.tool ~/darkstar-audit-output/audit.json > /dev/null && echo "audit.json is valid JSON"
```

And the tests (any machine with Python 3):

```bash
cd HangarBay/tools/workstation-audit
python3 -m unittest discover -s tests -v
```

## Checks

| Check | What is probed |
|---|---|
| Operating system | `/etc/os-release` (ID + VERSION_ID) vs. the stack target |
| CPU architecture | `platform.machine()` vs. the stack's supported targets (x86_64, arm64/aarch64) |
| Disk space | Free GB on the target filesystem vs. the 40 GB stack-policy floor |
| ROS 2 | Distros under `/opt/ros/<distro>`, `setup.bash` present, environment after sourcing it (ROS_DISTRO / AMENT_PREFIX_PATH), and `ros2 doctor --report` in that sourced shell |
| Gazebo | `gz`/`gazebo` on PATH + parsed version → flavour (8=Harmonic, 7=Garden, 6=Fortress) and pairing vs. the installed/target ROS distro |
| Docker (optional) | CLI presence/version **and** daemon reachability via `docker info`, recorded as separate evidence |

## Statuses

Each check tracks four states separately — **installed, configured,
compatible, operational** — and lands on one status:

| Status | Meaning |
|---|---|
| **READY** | Installed + configured + compatible + operational, each backed by probe evidence. Never granted for an executable alone. |
| **MISCONFIGURED** | Installed and version-compatible, but a configuration check failed — or a system requirement (e.g. the disk floor) is unmet. |
| **INCOMPATIBLE** | Installed, but its version conflicts with the stack or another member (e.g. ROS 2 Humble on Ubuntu 24.04, or Gazebo Fortress beside Jazzy). The conflicting pair and rule are named. |
| **NOT INSTALLED** | Detection found nothing; the evidence lists the methods tried. |
| **UNKNOWN** | The inspection could not determine the state. Two flavours, recorded in the `assessment` field: `inconclusive` (a probe errored/timed out/unparseable) and `not_assessed` (deliberately not probed in this version — e.g. Gazebo's operational state, which needs a smoke test). |

Two readiness numbers, never conflated:

- **Workstation readiness** — did the audit itself function (probes ran
  and produced determinations)? Tool absence does not affect it.
- **Stack readiness** — do the *required* checks for the selected stack
  pass? Only required items can block it; optional items are listed
  separately as notes.

### A consequence worth knowing

Because a compatible Gazebo Harmonic is *not assessed* operationally in
v1, it reports `UNKNOWN (not_assessed)` and the stack reports
`NOT READY` with Gazebo as a blocker — even on a perfect machine. That
is the honest result of the current evidence, not a bug: READY for a
simulator requires a headless smoke run, which is a separate, later
decision (spec §4, Decision 1).

## Reading the outputs

`audit.json` top level: `schema_version`, `tool`, `generated_at`,
`machine_profile` (raw OS/arch/disk observations), `target_stack`,
`findings[]`, `summary`. Each finding has `id`, `name`, `role`
(`required`/`optional`), `status`, `states{installed, configured,
compatible, operational}` (true/false/null = not assessed),
`assessment`, `evidence{}` (probe → observed value), `reasons[]`, and an
optional `recommendation`.

## Files

```
audit.py                     entry point (argparse, writes both reports)
darkstar_audit/
  probes.py                  read-only probes -> MachineProfile (raw evidence)
  rules.py                   pairing/compatibility data + target stack
  evaluate.py                pure evaluation: profile -> findings (unit-testable)
  report.py                  audit.json + audit.md from the same findings
tests/test_audit.py          unittest fixtures: missing ROS, low disk,
                             incompatible pairings, Docker daemon down,
                             unknown probes, report agreement, parsers
```

## Ground truth warning (Omega-Ubuntu)

Omega-Ubuntu's state changed during 2026-10-23: pre-install it had no
ROS and ~17 GB free; later that day ROS 2 Jazzy and Gazebo Sim 8.15.0
were installed and verified in-guest. The auditor intentionally has no
expected values baked in — it reports whatever it actually finds on the
machine at run time. If a report disagrees with what you believe about
the machine, investigate the probes; do not adjust expectations to make
the report "pass".

## Limitations (v1)

- Linux only (the spec's per-platform inspector interface is designed
  for three OSes; macOS/Windows inspectors are later phases).
- One target stack (PX4 Drone Development). Stack selection/schema
  files are a later step; rules are data in `rules.py` until then.
- No smoke tests, no PX4/MAVSDK/QGroundControl/VS Code probes yet —
  those are the spec's next tools after this first check set proves out.
- ROS functional evidence is `ros2 doctor --report` exiting 0 after
  sourcing; doctor warnings that still exit 0 are not parsed in v1.
- No remote/SSH/Tailscale auditing yet: run it on the machine, import
  the report files. That wiring is Step 3 of the Phase 1 plan.
