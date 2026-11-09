#!/bin/bash
# Darkstar Robotics — every common task is one command:  bash dev.sh <task>
# All tasks use Apple's toolchain even when conda base is active.
set -euo pipefail
cd "$(dirname "$0")"
source Scripts/_env.sh

task="${1:-help}"; shift || true
case "$task" in
  setup)     bash Scripts/setup.sh "$@" ;;
  run)       swift run RoboticsControlCenter ;;
  build)     swift build ;;
  test)      bash Scripts/run-tests.sh "$@" ;;
  app)       APP_ONLY=1 bash Scripts/package.sh ;;
  dist)      bash Scripts/package.sh ;;
  install)   bash Scripts/install-app.sh ;;
  doctor)    bash Scripts/doctor.sh ;;
  toolchain) bash Scripts/toolchain-mac.sh ;;
  runtime)   bash Scripts/runtime.sh ;;
  sim)       bash Scripts/sim.sh "$@" ;;
  cli)       swift run darkstar "$@" ;;
  clean)     swift package clean ;;
  help|*)
    cat <<HELP
Darkstar Robotics $DARKSTAR_VERSION — bash dev.sh <task>
  setup      one-time: doctor + Mac toolchain + tests + install app
  run        build and launch the app from source (debug)
  test       test suite (add unit | integration | e2e for one tier)
  install    release build -> /Applications + Desktop shortcut, then open
  dist       app + installer + zips in ../DarkstarRobotics-Dist
  doctor     read-only check of this Mac and the runtime VM
  toolchain  Homebrew: UTM, Tailscale, QGroundControl, Foxglove, cmake, ninja, python, node
             (UPGRADE_UTM=1 bash dev.sh toolchain  replaces the old UTM that lacks utmctl)
  runtime    provision ROS 2 Jazzy + Gazebo Harmonic + PX4 SITL inside the VM
  sim        PX4 SITL demo in the VM: start | status | fly | stop (QGC + Foxglove on the Mac)
  cli vm     run the darkstar CLI (status | vm | version)
HELP
    ;;
esac
