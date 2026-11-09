# Running Darkstar Robotics on a Mac

## First time (one command)

```
git clone https://github.com/abelxmendoza/HangarBay.git ~/Desktop/projects/HangarBay
cd ~/Desktop/projects/HangarBay
bash dev.sh setup
```

Any folder works; the scripts find everything relative to the checkout.
Release builds go to a sibling `DarkstarRobotics-Dist/` folder.

or double-click **Darkstar Setup.command** in Finder.

Setup runs `bash dev.sh doctor`, offers to install the Mac toolchain, runs the test
suite, builds a release app, installs it to `/Applications`, points the
Desktop shortcut at it, and opens it. Add `--runtime` (`bash Scripts/setup.sh --runtime`)
to also provision the Ubuntu VM.

## Day to day

| Command | What it does |
|---|---|
| `bash dev.sh run` | Build and launch from source (fastest edit loop) |
| `bash dev.sh test` | Unit + integration + e2e tests |
| `bash dev.sh install` | Release build into `/Applications`, then open it |
| `bash dev.sh dist` | App + installer + zips into `../DarkstarRobotics-Dist` |
| `bash dev.sh doctor` | Read-only check of this Mac and the runtime VM |
| `bash dev.sh cli vm` | Deep probe of the VM with the `darkstar` CLI |

The version lives in `VERSION`. When you bump it, also bump `newVersion` in
`Installer/Sources/DarkstarInstaller/DarkstarInstallerApp.swift`;
`bash dev.sh dist` refuses to build an installer whose version doesn't match.

Conda: your shell starts in conda `base`. Every script resets PATH to Apple's
toolchain first, so conda's clang/ld never leak into Swift builds.

## Fly PX4 in simulation

With the runtime provisioned (`bash dev.sh runtime`) and running:

```
bash dev.sh sim start     # XRCE agent + PX4 SITL (Gazebo Harmonic, x500, headless) + foxglove_bridge
bash dev.sh sim status    # topics, vehicle altitude/arming, viewer URLs
bash dev.sh sim fly       # arm, take off to ~2.5 m, hover, land
bash dev.sh sim stop      # shut PX4 down and stop everything
```

- Everything runs in the VM's tmux session `darkstar` (`ssh ryuk@<vm>` then
  `tmux attach -t darkstar`; windows `xrce`, `px4` (the `pxh>` shell),
  `foxglove`). Logs: `/tmp/darkstar-{xrce,px4,foxglove}.log` in the VM.
- **QGroundControl** (on the Mac): `sim start` streams MAVLink to UDP 14550
  on this Mac and opens QGC, which auto-connects. When the VM runs on this
  Mac it uses UTM's local bridge (`192.168.64.1`), not Tailscale: between a
  Mac and its own VM Tailscale often falls back to a DERP relay (~50 ms vs
  ~1–6 ms), and when that relay hiccuped mid-hover the lost GCS link made
  PX4 failsafe (hold → return → land). `DARKSTAR_GCS_IP` overrides. The first
  launch shows setup dialogs and may ask to *find devices on your local
  network* — allow it, or QGC never opens its UDP link. PX4 refuses to arm
  until a ground station is connected ("Preflight Fail: No connection to the
  ground control station"), so connect QGC before `sim fly`.
- **Foxglove** (on the Mac): Open connection → Foxglove WebSocket →
  `ws://<vm-local-ip>:8765` (e.g. `ws://192.168.64.15:8765`; `ip -4 addr` in
  the VM) or the VM's Tailscale IP from another machine. PX4's topics are under `/fmu/out/*`
  (e.g. `/fmu/out/vehicle_local_position`; z is NED, negative is up).
- ROS 2 in the VM: `source /opt/ros/jazzy/setup.bash && source ~/darkstar_ws/install/setup.bash`,
  then `ros2 topic list | grep fmu`.

## Restarting the runtime VM

Use **Power Off, then Start** — not Reboot. Warm reboots of the arm64 Ubuntu
guest under UTM on Apple silicon occasionally hang right after
`EFI stub: Exiting boot services...` with every vCPU spinning, while UTM
still says "started". A cold start of the same kernel boots normally.

- Stop/Start from the Darkstar Dashboard, from UTM, or Ubuntu's *Power Off*.
- If a boot does hang, the Dashboard notices: UTM says running but SSH
  hasn't answered for 2 minutes → the runtime card shows **Not responding**
  with a **Force restart** button (power off + start). Darkstar never does
  this on its own. If Tailscale is down on the Mac it says it can't check,
  instead of guessing.
- The runtime's boot menu shows for 3 seconds (`bash dev.sh runtime` sets
  this, and golden images ship with it). If a new kernel won't boot, open
  the Console, choose *Advanced options for Ubuntu*, and pick the previous
  kernel.

## The toolchain

The robotics stack is split the way the app is designed:

**On the Mac** (`bash dev.sh toolchain`, Homebrew, skips anything already installed)

| Tool | Why |
|---|---|
| Xcode / command line tools | Builds the Swift app |
| UTM (with `utmctl`) | Hosts the runtime VM; Darkstar starts/stops it via `utmctl` |
| Tailscale | Link to the VM and to robots |
| QGroundControl | PX4 ground station |
| Foxglove | ROS 2 visualisation over `foxglove_bridge` |
| git, cmake, ninja, python@3.12, node, gh | PX4/C++ builds, MAVSDK tooling, the replay viewer, releases |

Your UTM is a 2022 build without `utmctl`, so the app can't start the VM.
`UPGRADE_UTM=1 bash dev.sh toolchain` replaces UTM.app with the current release;
VMs live in `~/Library/Containers/com.utmapp.UTM` and are kept.

**In the Ubuntu 24.04 VM** (`bash dev.sh runtime`, over SSH to `ryuk@100.67.141.81`)

ROS 2 Jazzy desktop + ros_gz, Gazebo Harmonic, rosdep, PX4-Autopilot SITL,
Micro XRCE-DDS Agent v2.4.3, a `~/darkstar_ws` with px4_msgs pinned to
392e831 and px4_ros_com, and foxglove_bridge. Re-running skips what exists.
Override the target with `DARKSTAR_SSH_USER` / `DARKSTAR_SSH_HOST`.
