#!/bin/bash
# Darkstar doctor — read-only check of this Mac and the runtime VM.
# Changes nothing. Exit code is the number of hard failures.
set -uo pipefail
source "$(dirname "$0")/_env.sh"

fails=0
hard_fail() { c_fail "$*"; fails=$((fails + 1)); }

c_step "This Mac"
os_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( os_major >= 14 )); then c_ok "macOS $(sw_vers -productVersion)"; else hard_fail "macOS $(sw_vers -productVersion) — Darkstar needs macOS 14 or newer"; fi
if [[ "$(uname -m)" == "arm64" ]]; then c_ok "Apple silicon"; else c_warn "Intel Mac — the runtime VM image is arm64; expect slow emulation"; fi
ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if (( ram_gb >= 16 )); then c_ok "${ram_gb} GB RAM"; else c_warn "${ram_gb} GB RAM — the runtime VM reserves 8 GB"; fi
free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if (( free_gb >= 100 )); then c_ok "${free_gb} GB free disk"; else c_warn "${free_gb} GB free disk — the runtime wants ~100 GB of headroom"; fi

c_step "Build toolchain"
if xcode-select -p >/dev/null 2>&1; then c_ok "Xcode tools at $(xcode-select -p)"; else hard_fail "Xcode command line tools missing — run: xcode-select --install"; fi
if [[ -d /Applications/Xcode.app ]]; then c_ok "Xcode.app installed"; else c_warn "Xcode.app missing — command line tools build the app; Xcode is for editing/debugging"; fi
if command -v swift >/dev/null 2>&1; then c_ok "$(swift --version 2>/dev/null | head -1)"; else hard_fail "swift not found"; fi
if command -v brew >/dev/null 2>&1; then c_ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"; else c_warn "Homebrew missing — needed only for the toolchain task"; fi
for tool in git cmake ninja python3.12 node; do
  if command -v "$tool" >/dev/null 2>&1; then c_ok "$tool"; else c_warn "$tool not installed (bash dev.sh toolchain)"; fi
done

c_step "Robotics apps on this Mac"
if [[ -d /Applications/UTM.app ]]; then
  utm_ver="$(defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo '?')"
  if [[ -x /Applications/UTM.app/Contents/MacOS/utmctl ]]; then c_ok "UTM $utm_ver with utmctl"
  else c_warn "UTM $utm_ver has no utmctl, so Darkstar cannot start/stop the VM (UPGRADE_UTM=1 bash dev.sh toolchain)"; fi
else hard_fail "UTM missing — the runtime VM lives in UTM (bash dev.sh toolchain)"; fi
if [[ -d /Applications/Tailscale.app ]]; then c_ok "Tailscale"; else c_warn "Tailscale app missing (bash dev.sh toolchain)"; fi
if [[ -d /Applications/QGroundControl.app ]]; then c_ok "QGroundControl"; else c_warn "QGroundControl missing — PX4 ground station (bash dev.sh toolchain)"; fi
if ls -d /Applications/Foxglove*.app >/dev/null 2>&1; then c_ok "Foxglove"; else c_warn "Foxglove missing — ROS 2 visualisation on the Mac (bash dev.sh toolchain)"; fi

c_step "Darkstar Robotics app"
if [[ -d "$DARKSTAR_INSTALLED_APP" ]]; then
  v="$(defaults read "$DARKSTAR_INSTALLED_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?')"
  if [[ "$v" == "$DARKSTAR_VERSION" ]]; then c_ok "Installed $v"; else c_warn "Installed $v, source is $DARKSTAR_VERSION (bash dev.sh install)"; fi
else c_warn "Not installed in /Applications yet (bash dev.sh install)"; fi

c_step "Runtime VM ($DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST)"
if ( cd "$DARKSTAR_SRC" && swift build --product darkstar >/dev/null 2>&1 ); then
  ( cd "$DARKSTAR_SRC" && "$(swift build --show-bin-path)/darkstar" vm --user "$DARKSTAR_SSH_USER" --host "$DARKSTAR_SSH_HOST" ) \
    || {
      ssh_out="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST" true 2>&1 || true)"
      if [[ "$ssh_out" == *"Permission denied"* ]]; then
        c_warn "Runtime VM is up but rejects this Mac's SSH key — run: ssh-copy-id $DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST"
      else
        c_warn "Runtime VM not reachable — start it in UTM and check Tailscale"
      fi
    }
else
  c_warn "Could not build the darkstar CLI to probe the VM"
fi

# VM disk headroom (same thresholds as PreflightRules.runtimeVMDiskStatus).
# Ubuntu's default LVM install gives / only half the virtual disk; when the
# volume group still has free space, say exactly how to claim it.
vm_target="$DARKSTAR_SSH_USER@$DARKSTAR_SSH_HOST"
if vm_disk="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$vm_target" \
      'echo "$(df -Pk / | awk "NR==2 {print \$4}") $(sudo -n vgs --noheadings --units g --nosuffix -o vg_free 2>/dev/null | head -1 | tr -d " ")"' 2>/dev/null)"; then
  read -r vm_free_kb vm_vg_free <<<"$vm_disk"
  vm_free_gb=$(( ${vm_free_kb:-0} / 1048576 ))
  vm_vg_free_gb="${vm_vg_free%%.*}"
  claim=""
  if [[ "${vm_vg_free_gb:-0}" =~ ^[0-9]+$ ]] && (( vm_vg_free_gb >= 1 )); then
    claim=" — ${vm_vg_free_gb} GB of the VM disk is unallocated; claim it with: ssh $vm_target 'sudo lvextend -r -l +100%FREE \$(findmnt -no SOURCE /)'"
  fi
  if (( vm_free_gb >= 25 )); then c_ok "VM root disk: ${vm_free_gb} GB free"
  elif (( vm_free_gb >= 15 )); then c_warn "VM root disk: ${vm_free_gb} GB free — tight for rebuilds and ros2 bags (want 25 GB+)${claim}"
  else c_warn "VM root disk: ${vm_free_gb} GB free — too low; provisioning needs ~25 GB${claim:- — grow the VM disk in UTM first}"; fi
fi

echo
if (( fails == 0 )); then c_ok "Doctor finished: no hard failures."; else c_fail "Doctor finished: $fails hard failure(s)."; fi
exit "$fails"
