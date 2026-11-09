#!/bin/bash
# Installs the Mac side of the Darkstar robotics toolchain with Homebrew.
# Skips anything already installed. Set UPGRADE_UTM=1 to replace an old UTM
# that has no utmctl (VMs are stored outside the app and are kept).
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if ! command -v brew >/dev/null 2>&1; then
  c_warn "Homebrew is not installed."
  if confirm "Install Homebrew now (official installer, asks for your password)?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    c_fail "Homebrew is required for the toolchain. Nothing was installed."; exit 1
  fi
fi

c_step "Command line tools"
# git: source control · cmake/ninja: PX4 + C++ builds · python@3.12: Mac-side
# PX4/MAVSDK tooling · node: PX4 replay viewer · gh: GitHub releases/updates
for f in git cmake ninja python@3.12 node gh; do
  if brew list --formula "$f" >/dev/null 2>&1; then c_ok "$f already installed"
  else brew install "$f" && c_ok "$f installed"; fi
done

install_cask() { # $1 = app name in /Applications, rest = cask names to try in order
  local app="$1"; shift
  if [[ -d "/Applications/$app.app" ]]; then c_ok "$app already installed"; return 0; fi
  local cask
  for cask in "$@"; do
    if brew info --cask "$cask" >/dev/null 2>&1; then
      if brew install --cask "$cask"; then c_ok "$app installed ($cask)"; return 0; fi
    fi
  done
  c_warn "Could not install $app with Homebrew (tried: $*). Install it by hand."
}

c_step "Robotics apps"
if [[ -d /Applications/UTM.app && ! -x /Applications/UTM.app/Contents/MacOS/utmctl ]]; then
  if [[ "${UPGRADE_UTM:-0}" == "1" ]]; then
    c_warn "Replacing old UTM (no utmctl). VMs live in ~/Library/Containers/com.utmapp.UTM and are kept."
    osascript -e 'quit app "UTM"' 2>/dev/null || true
    brew install --cask --force utm && c_ok "UTM upgraded"
  else
    c_warn "UTM is installed but has no utmctl. Re-run with UPGRADE_UTM=1 to upgrade it."
  fi
else
  install_cask "UTM" utm                                    # runtime VM host
fi
install_cask "Tailscale" tailscale-app tailscale            # link to the VM / robots
install_cask "QGroundControl" qgroundcontrol                # PX4 ground station
if ls -d /Applications/Foxglove*.app >/dev/null 2>&1; then c_ok "Foxglove already installed"
else install_cask "Foxglove" foxglove foxglove-studio; fi    # ROS 2 visualisation

echo
c_ok "Mac toolchain done. ROS 2, Gazebo and PX4 SITL run inside the Ubuntu VM: bash dev.sh runtime"
