#!/bin/bash
# Provisions the Ubuntu runtime VM over SSH (ROS 2 Jazzy, Gazebo Harmonic,
# PX4 SITL, Micro XRCE-DDS, px4_msgs workspace, foxglove_bridge).
# Idempotent: anything already installed is skipped. Asks for the VM's sudo
# password once.
#   DARKSTAR_SSH_USER / DARKSTAR_SSH_HOST  override ryuk@100.67.141.81
#   SKIP_PX4_BUILD=1                       clone PX4 but don't build SITL
set -euo pipefail
source "$(dirname "$0")/_env.sh"

TARGET="$DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST"
c_step "Runtime VM: $TARGET"
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$TARGET" true 2>/dev/null; then
  c_fail "Cannot SSH to $TARGET without a password."
  echo "  1. Start the VM in UTM (or from the Darkstar Dashboard)."
  echo "  2. Check Tailscale is connected on this Mac."
  echo "  3. If SSH keys aren't set up yet: ssh-copy-id $TARGET"
  exit 1
fi
# Unique remote name per run: bash reads scripts lazily, so overwriting a
# shared path while another run is executing it corrupts that run.
REMOTE_SCRIPT="/tmp/darkstar-provision-runtime.$$.$(date +%s).sh"
scp -q "$DARKSTAR_SRC/Scripts/provision-runtime.sh" "$TARGET:$REMOTE_SCRIPT"
ssh -t "$TARGET" "SKIP_PX4_BUILD=${SKIP_PX4_BUILD:-0} DARKSTAR_YES=${DARKSTAR_YES:-0} DARKSTAR_MIN_FREE_GB=${DARKSTAR_MIN_FREE_GB:-} bash $REMOTE_SCRIPT; rc=\$?; rm -f $REMOTE_SCRIPT; exit \$rc"
