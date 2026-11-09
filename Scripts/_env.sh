#!/bin/bash
# Shared environment for Darkstar scripts. Sourced, not run.
#
# Abel's shell starts in conda "base", which puts conda's python, clang,
# and ld ahead of Apple's on PATH. SwiftPM and codesign must use Apple's
# toolchain, so every Darkstar script starts from a clean PATH.

if [[ -n "${CONDA_PREFIX:-}" || -n "${CONDA_DEFAULT_ENV:-}" ]]; then
  unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_PROMPT_MODIFIER CONDA_SHLVL CONDA_PYTHON_EXE CONDA_EXE _CE_CONDA _CE_M
fi
unset CC CXX LD LDFLAGS CFLAGS CPPFLAGS SDKROOT 2>/dev/null || true
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"

DARKSTAR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DARKSTAR_PROJECTS="$(cd "$DARKSTAR_SRC/.." && pwd)"
DARKSTAR_INSTALLER_SRC="$DARKSTAR_SRC/Installer"   # in this repo; package.sh stages its Payload
DARKSTAR_DIST="$DARKSTAR_PROJECTS/DarkstarRobotics-Dist"
DARKSTAR_VERSION="$(tr -d '[:space:]' < "$DARKSTAR_SRC/VERSION")"
DARKSTAR_APP_NAME="Darkstar Robotics"
DARKSTAR_INSTALLED_APP="/Applications/$DARKSTAR_APP_NAME.app"

# Runtime VM link (same env vars and defaults as the `darkstar` CLI).
DARKSTAR_SSH_USER="${DARKSTAR_SSH_USER:-ryuk}"
DARKSTAR_SSH_HOST="${DARKSTAR_SSH_HOST:-100.67.141.81}"

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_fail() { printf '\033[31m✗\033[0m %s\n' "$*"; }
c_step() { printf '\n\033[1;38;5;202m▸ %s\033[0m\n' "$*"; }

confirm() { # $1 = question; DARKSTAR_YES=1 answers yes
  [[ "${DARKSTAR_YES:-0}" == "1" ]] && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}
