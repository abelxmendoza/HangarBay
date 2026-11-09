#!/bin/bash
# Darkstar Robotics — one-command setup for a Mac.
#   doctor → Mac toolchain (asks first) → tests → build + install app → open
# Flags: --yes (no prompts), --skip-toolchain, --skip-tests, --runtime (also provision the VM)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

SKIP_TOOLCHAIN=0; SKIP_TESTS=0; RUNTIME=0
for arg in "$@"; do
  case "$arg" in
    --yes) export DARKSTAR_YES=1 ;;
    --skip-toolchain) SKIP_TOOLCHAIN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --runtime) RUNTIME=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

printf '\033[1;38;5;202mDARKSTAR ROBOTICS\033[0m  setup · v%s\n' "$DARKSTAR_VERSION"

if ! xcode-select -p >/dev/null 2>&1; then
  c_fail "Xcode command line tools are missing. A macOS dialog will open to install them; re-run setup when it finishes."
  xcode-select --install || true
  exit 1
fi

bash "$DARKSTAR_SRC/Scripts/doctor.sh" || true

if (( SKIP_TOOLCHAIN == 0 )) && confirm "Install missing Mac robotics tools (UTM, Tailscale, QGroundControl, Foxglove, cmake, ninja, python, node)?"; then
  bash "$DARKSTAR_SRC/Scripts/toolchain-mac.sh"
fi

if (( SKIP_TESTS == 0 )); then
  c_step "Running the test suite"
  ( cd "$DARKSTAR_SRC" && swift test ) || { c_fail "Tests failed; not installing. Re-run with --skip-tests to install anyway."; exit 1; }
fi

bash "$DARKSTAR_SRC/Scripts/install-app.sh"

if (( RUNTIME == 1 )); then
  bash "$DARKSTAR_SRC/Scripts/runtime.sh"
fi

echo
c_ok "Done. Darkstar Robotics is in /Applications and on your Desktop."
echo "  Day to day:  bash dev.sh run     (build + launch from source)"
echo "               bash dev.sh doctor  (check this Mac + the VM)"
echo "               bash dev.sh runtime (provision ROS 2 / Gazebo / PX4 in the VM)"
