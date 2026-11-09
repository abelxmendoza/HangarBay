#!/bin/bash
# Runs INSIDE the Ubuntu 24.04 runtime VM (arm64 under UTM, or amd64).
# Installs the validated Darkstar pairing:
#   Ubuntu 24.04 + ROS 2 Jazzy + Gazebo Harmonic + PX4 SITL
#   + Micro XRCE-DDS Agent v2.4.3 + px4_msgs (pinned 392e831) + foxglove_bridge
# Safe to re-run: each step checks what is already there.
set -euo pipefail

PX4_DIR="$HOME/PX4-Autopilot"
XRCE_DIR="$HOME/Micro-XRCE-DDS-Agent"
XRCE_TAG="v2.4.3"
WS="$HOME/darkstar_ws"
PX4_MSGS_PIN="392e831"

ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;38;5;202m▸ %s\033[0m\n' "$*"; }

. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "24.04" ]]; then
  echo "This runtime expects Ubuntu 24.04 (found $PRETTY_NAME)." >&2; exit 1
fi
# Prompt only when needed: `sudo -v` asks for a password even under NOPASSWD
# if any other sudoers entry for the user requires one.
sudo -n true 2>/dev/null || sudo -v

step "Disk space"
# A full install (ROS 2 desktop + Gazebo + PX4 SITL + workspace) takes ~15 GB,
# and work needs room on top. Ubuntu's default LVM layout leaves half the
# virtual disk unallocated, so the root filesystem often looks "full" while
# the space is sitting right there. Claim it before starting, instead of
# failing 40 minutes into the PX4 build.
if [[ -d /opt/ros/jazzy && -x "$PX4_DIR/build/px4_sitl_default/bin/px4" ]]; then
  need_gb="${DARKSTAR_MIN_FREE_GB:-5}"    # already provisioned: re-runs are incremental
else
  need_gb="${DARKSTAR_MIN_FREE_GB:-25}"
fi
free_gb=$(( $(df -Pk / | awk 'NR==2 {print $4}') / 1048576 ))
root_src="$(findmnt -no SOURCE /)"
vg_free_gb=0
if [[ "$root_src" == /dev/mapper/* ]] && command -v vgs >/dev/null 2>&1; then
  vg_free="$(sudo vgs --noheadings --units g --nosuffix -o vg_free 2>/dev/null | head -1 | tr -d ' ')"
  vg_free_gb="${vg_free%%.*}"; [[ "$vg_free_gb" =~ ^[0-9]+$ ]] || vg_free_gb=0
fi
if (( free_gb < 25 && vg_free_gb >= 1 )); then
  echo "Root has ${free_gb} GB free; ${vg_free_gb} GB of the VM disk is unallocated."
  answer=n
  if [[ "${DARKSTAR_YES:-0}" == "1" ]]; then answer=y
  elif [[ -t 0 ]]; then read -r -p "Grow / to use it now (online, no reboot, keeps data)? [y/N] " answer || answer=n
  fi
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo lvextend -r -l +100%FREE "$root_src"
    free_gb=$(( $(df -Pk / | awk 'NR==2 {print $4}') / 1048576 ))
    ok "Root filesystem grown: ${free_gb} GB free"
  fi
fi
if (( free_gb < need_gb )); then
  echo "Only ${free_gb} GB free on /; this step needs about ${need_gb} GB." >&2
  if (( vg_free_gb >= 1 )); then
    echo "Re-run with DARKSTAR_YES=1 to claim the ${vg_free_gb} GB of unallocated VM disk." >&2
  else
    echo "Grow the VM's disk in UTM (VM settings → Drive → Resize), then re-run." >&2
  fi
  echo "(Override the check with DARKSTAR_MIN_FREE_GB=<n> if you know better.)" >&2
  exit 1
fi
ok "${free_gb} GB free on / (need ~${need_gb} GB)"

step "Base packages"
sudo apt-get update -qq
sudo apt-get install -y -qq locales curl gnupg lsb-release software-properties-common \
  git build-essential cmake ninja-build python3-pip python3-venv
sudo locale-gen en_US en_US.UTF-8 >/dev/null
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
sudo add-apt-repository -y universe >/dev/null

step "ROS 2 Jazzy"
if ! dpkg -s ros2-apt-source >/dev/null 2>&1 \
   && [[ ! -e /etc/apt/sources.list.d/ros2.list && ! -e /etc/apt/sources.list.d/ros2.sources ]]; then
  ver=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F '"tag_name"' | awk -F'"' '{print $4}')
  curl -fsSL -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ver}/ros2-apt-source_${ver}.${UBUNTU_CODENAME}_all.deb"
  sudo dpkg -i /tmp/ros2-apt-source.deb
  sudo apt-get update -qq
fi
sudo apt-get install -y -qq ros-jazzy-desktop ros-dev-tools ros-jazzy-ros-gz ros-jazzy-foxglove-bridge
ok "ROS 2 Jazzy + ros_gz + foxglove_bridge"

step "Gazebo Harmonic"
if ! command -v gz >/dev/null 2>&1; then
  sudo curl -fsSL https://packages.osrfoundation.org/gazebo.gpg -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $UBUNTU_CODENAME main" \
    | sudo tee /etc/apt/sources.list.d/gazebo-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gz-harmonic
fi
ok "Gazebo: $(gz sim --versions 2>/dev/null | head -1)"

step "rosdep"
[[ -f /etc/ros/rosdep/sources.list.d/20-default.list ]] || sudo rosdep init
rosdep update --rosdistro jazzy >/dev/null
ok "rosdep ready"

step "PX4-Autopilot"
if [[ ! -d "$PX4_DIR/.git" ]]; then
  git clone --recursive https://github.com/PX4/PX4-Autopilot.git "$PX4_DIR"
else
  git -C "$PX4_DIR" submodule update --init --recursive
fi
if [[ ! -f "$HOME/.darkstar-px4-deps" ]]; then
  bash "$PX4_DIR/Tools/setup/ubuntu.sh" --no-nuttx
  touch "$HOME/.darkstar-px4-deps"
fi
if [[ "${SKIP_PX4_BUILD:-0}" != "1" ]]; then
  # A Gazebo/apt upgrade between runs leaves stale library paths in PX4's
  # CMake cache ("missing and no known rule to make it"); reconfigure once.
  if ! ( cd "$PX4_DIR" && make px4_sitl ); then
    echo "PX4 build failed; dropping stale CMake cache and retrying once"
    rm -f "$PX4_DIR/build/px4_sitl_default/CMakeCache.txt"
    ( cd "$PX4_DIR" && make px4_sitl )
  fi
  ok "PX4 SITL built"
else
  ok "PX4 cloned (build skipped)"
fi

step "Micro XRCE-DDS Agent $XRCE_TAG"
if ! command -v MicroXRCEAgent >/dev/null 2>&1; then
  # An existing checkout at another tag (or configured with another CMake
  # generator) is left alone; the pinned tag gets its own dir + build dir.
  if [[ -d "$XRCE_DIR/.git" && "$(git -C "$XRCE_DIR" describe --tags 2>/dev/null)" != "$XRCE_TAG" ]]; then
    XRCE_DIR="$XRCE_DIR-$XRCE_TAG"
  fi
  [[ -d "$XRCE_DIR" ]] || git clone -b "$XRCE_TAG" https://github.com/eProsima/Micro-XRCE-DDS-Agent.git "$XRCE_DIR"
  cmake -S "$XRCE_DIR" -B "$XRCE_DIR/build-darkstar" -G Ninja
  cmake --build "$XRCE_DIR/build-darkstar"
  sudo cmake --install "$XRCE_DIR/build-darkstar"
  sudo ldconfig /usr/local/lib/
fi
ok "MicroXRCEAgent installed"

step "Darkstar ROS workspace ($WS)"
mkdir -p "$WS/src"
if [[ ! -d "$WS/src/px4_msgs" ]]; then
  git clone https://github.com/PX4/px4_msgs.git "$WS/src/px4_msgs"
  git -C "$WS/src/px4_msgs" checkout "$PX4_MSGS_PIN"
fi
[[ -d "$WS/src/px4_ros_com" ]] || git clone https://github.com/PX4/px4_ros_com.git "$WS/src/px4_ros_com"
set +u; source /opt/ros/jazzy/setup.bash; set -u
( cd "$WS" && rosdep install --from-paths src --ignore-src -y -r >/dev/null && colcon build --symlink-install )
ok "workspace built"

step "Shell setup"
if ! grep -q "darkstar runtime" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<RC

# darkstar runtime
source /opt/ros/jazzy/setup.bash
[ -f "$WS/install/setup.bash" ] && source "$WS/install/setup.bash"
export GZ_VERSION=harmonic
RC
fi
ok ".bashrc sources ROS 2 Jazzy + darkstar_ws"

echo
ok "Runtime ready. Try:  cd ~/PX4-Autopilot && make px4_sitl gz_x500"
ok "Foxglove on the Mac: ros2 launch foxglove_bridge foxglove_bridge_launch.xml, then connect to ws://<vm-ip>:8765"
