#!/bin/bash
# PX4 SITL demo in the runtime VM, viewed from this Mac.
#   bash dev.sh sim start    XRCE agent + PX4 SITL (Gazebo Harmonic, x500, headless)
#                            + foxglove_bridge, MAVLink streamed to this Mac for QGC
#   bash dev.sh sim status   what's running, topics, vehicle state, viewer URLs
#   bash dev.sh sim fly      arm, take off to ~2.5 m, hover, land (needs QGC connected:
#                            PX4 won't arm without a ground station)
#   bash dev.sh sim stop     shut PX4 down cleanly and stop everything
# Everything runs in the VM's tmux session "darkstar" (ssh in and
# `tmux attach -t darkstar` to watch). Read-only for the Mac except opening
# QGroundControl on `start`.
#   DARKSTAR_GCS_IP   where QGC runs. Default: this Mac's address on UTM's
#                     local bridge when the VM runs on this Mac (direct,
#                     ~1-6 ms), else this Mac's Tailscale IPv4. Tailscale
#                     between a Mac and its own VM often falls back to a
#                     DERP relay (~50 ms, drops), and a dropped GCS link
#                     makes PX4 failsafe-land mid-flight.
#   DARKSTAR_SIM_MODEL  PX4 airframe target (default gz_x500)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

TARGET="$DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST"
SESSION=darkstar
MODEL="${DARKSTAR_SIM_MODEL:-gz_x500}"
ROS_ENV='source /opt/ros/jazzy/setup.bash; [ -f ~/darkstar_ws/install/setup.bash ] && source ~/darkstar_ws/install/setup.bash'

vm() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$TARGET" "$@"; }
pxh() { vm "tmux send-keys -t $SESSION:px4 '$1' Enter"; }

gcs_ip() {
  if [[ -n "${DARKSTAR_GCS_IP:-}" ]]; then echo "$DARKSTAR_GCS_IP"; return; fi
  # Same machine? The VM's default gateway is this Mac on UTM's shared network.
  local gw
  gw="$(vm "ip -4 route show default | awk '{print \$3; exit}'" 2>/dev/null || true)"
  if [[ -n "$gw" ]] && ifconfig 2>/dev/null | grep -q "inet $gw "; then echo "$gw"; return; fi
  local ts
  for ts in /Applications/Tailscale.app/Contents/MacOS/Tailscale /opt/homebrew/bin/tailscale /usr/local/bin/tailscale; do
    [[ -x "$ts" ]] && { "$ts" ip -4 2>/dev/null | head -1; return; }
  done
}

require_vm() {
  vm true 2>/dev/null || { c_fail "Can't SSH to $TARGET — start the runtime (bash dev.sh doctor shows why)."; exit 1; }
}

# Prints the vehicle's local z (NED, metres; negative is up) and arming state.
vehicle_state() {
  vm "$ROS_ENV; z=\$(timeout 10 ros2 topic echo --once --field z /fmu/out/vehicle_local_position 2>/dev/null | head -1);
      a=\$(timeout 10 ros2 topic echo --once --field arming_state /fmu/out/vehicle_status_v1 2>/dev/null | head -1);
      [ -z \"\$a\" ] && a=\$(timeout 10 ros2 topic echo --once --field arming_state /fmu/out/vehicle_status 2>/dev/null | head -1);
      echo \"\${z:-?} \${a:-?}\""
}

start() {
  require_vm
  if vm "tmux has-session -t $SESSION 2>/dev/null"; then
    c_warn "Sim already running (tmux session '$SESSION'). bash dev.sh sim status | stop"; return 0
  fi
  c_step "Starting PX4 SITL ($MODEL) in the runtime"
  vm "tmux new-session -d -s $SESSION -n xrce 'MicroXRCEAgent udp4 -p 8888 2>&1 | tee /tmp/darkstar-xrce.log'
      tmux new-window -t $SESSION -n px4 'cd ~/PX4-Autopilot && HEADLESS=1 make px4_sitl $MODEL 2>&1 | tee /tmp/darkstar-px4.log; bash'
      tmux new-window -t $SESSION -n foxglove '$ROS_ENV; ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765 address:=0.0.0.0 2>&1 | tee /tmp/darkstar-foxglove.log'"
  printf 'Waiting for PX4'
  local i
  for i in $(seq 1 90); do
    if vm "grep -q 'Ready for takeoff' /tmp/darkstar-px4.log 2>/dev/null || grep -q 'time sync converged' /tmp/darkstar-px4.log 2>/dev/null"; then break; fi
    printf '.'; sleep 2
  done; echo
  vm "grep -q 'uxrce_dds_client' /tmp/darkstar-px4.log" || { c_fail "PX4 didn't come up — see /tmp/darkstar-px4.log in the VM"; exit 1; }
  c_ok "PX4 SITL up, XRCE bridge connected"

  local ip; ip="$(gcs_ip || true)"
  if [[ -n "$ip" ]]; then
    pxh "mavlink start -x -u 14561 -o 14550 -t $ip"
    c_ok "MAVLink → $ip:14550 (QGroundControl auto-connects)"
    [[ -d /Applications/QGroundControl.app ]] && open -a QGroundControl || true
  else
    c_warn "No Tailscale IP for this Mac; set DARKSTAR_GCS_IP to stream MAVLink to QGC."
  fi
  status
}

status() {
  require_vm
  c_step "Sim in the runtime ($TARGET)"
  if ! vm "tmux has-session -t $SESSION 2>/dev/null"; then c_warn "Not running (bash dev.sh sim start)"; return 0; fi
  c_ok "tmux session '$SESSION': $(vm "tmux list-windows -t $SESSION -F '#W' | paste -sd' ' -")"
  local topics; topics="$(vm "$ROS_ENV; timeout 15 ros2 topic list 2>/dev/null | grep -c '^/fmu/out/'" || true)"
  if [[ "${topics:-0}" -gt 0 ]]; then c_ok "ROS 2 sees $topics /fmu/out topics"; else c_warn "No /fmu/out topics yet"; fi
  read -r z arming <<<"$(vehicle_state)"
  case "$arming" in 1) arming="disarmed" ;; 2) arming="armed" ;; esac
  c_ok "Vehicle: z=$z m (NED; negative is up), $arming"
  local lan; lan="$(vm "ip -4 -o addr show scope global | awk '\$2 !~ /tailscale/ {sub(/\\/.*/, \"\", \$4); print \$4; exit}'" 2>/dev/null || true)"
  if vm "ss -ltn | grep -q ':8765 '"; then c_ok "Foxglove: Open connection → ws://${lan:-$DARKSTAR_SSH_HOST}:8765${lan:+ (or ws://$DARKSTAR_SSH_HOST:8765 over Tailscale)}"
  else c_warn "foxglove_bridge not listening on 8765"; fi
  if vm "grep -q 'No connection to the ground' <(tmux capture-pane -p -t $SESSION:px4 -S -15)"; then
    c_warn "PX4 has no ground station yet — finish any QGroundControl dialogs (and allow local network access)"
  fi
}

fly() {
  require_vm
  vm "tmux has-session -t $SESSION 2>/dev/null" || { c_fail "Sim not running (bash dev.sh sim start)"; exit 1; }
  local mark; mark="$(vm "wc -l < /tmp/darkstar-px4.log")"
  c_step "Takeoff"
  pxh "commander takeoff"
  local z arming i peak=0
  for i in $(seq 1 8); do
    sleep 2
    read -r z arming <<<"$(vehicle_state)"
    printf '  t+%2ss  z=%s  arming_state=%s\n' "$((i*2))" "$z" "$arming"
    [[ "$z" =~ ^-?[0-9.]+(e-?[0-9]+)?$ ]] && peak="$(awk -v p="$peak" -v z="$z" 'BEGIN{print (z<p)?z:p}')"
  done
  if awk -v p="$peak" 'BEGIN{exit !(p<=-1.5)}'; then c_ok "Reached $(awk -v p="$peak" 'BEGIN{printf "%.2f", -p}') m"
  else
    c_fail "Didn't climb (lowest z=$peak). If PX4 says 'No connection to the ground', connect QGroundControl first."
    vm "tmux capture-pane -p -t $SESSION:px4 -S -20 | grep -E 'WARN|ERROR|Fail' | tail -5" || true
    exit 1
  fi
  read -r z arming <<<"$(vehicle_state)"
  if [[ "$arming" == "1" ]]; then
    c_fail "PX4 landed on its own before the land command (failsafe):"
    vm "tail -n +$mark /tmp/darkstar-px4.log | grep -E 'failsafe|Failsafe|lost|RTL|Landing|Disarmed' | sed 's/\x1b\[[0-9;]*m//g' | head -8" || true
    exit 1
  fi
  c_step "Landing"
  pxh "commander land"
  for i in $(seq 1 20); do
    sleep 2
    read -r z arming <<<"$(vehicle_state)"
    [[ "$arming" == "1" ]] && { c_ok "Landed and disarmed (z=$z m)"; return 0; }
  done
  c_warn "Still armed after 40 s (z=$z) — check QGroundControl"
}

stop() {
  require_vm
  if vm "tmux has-session -t $SESSION 2>/dev/null"; then
    pxh "shutdown" || true; sleep 3
    # [g]/[M] so pkill doesn't match this remote shell's own command line.
    vm "tmux kill-session -t $SESSION 2>/dev/null; pkill -f '[g]z sim' 2>/dev/null; pkill -f '[M]icroXRCEAgent' 2>/dev/null; true"
    c_ok "Sim stopped"
  else
    c_ok "Sim not running"
  fi
}

case "${1:-status}" in
  start) start ;;
  status) status ;;
  fly) fly ;;
  stop) stop ;;
  *) echo "Usage: bash dev.sh sim start|status|fly|stop" >&2; exit 2 ;;
esac
