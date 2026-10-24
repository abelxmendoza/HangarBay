#!/bin/bash
# Darkstar Robotics — end-to-end smoke pass.
#
# Always: the automated E2E tests (real processes, a fake utmctl binary,
# and a real local replay server).
#
# With DARKSTAR_SMOKE_APP=1: also builds the app, launches it for a few
# seconds, and confirms the process starts and exits on request. This part
# needs a logged-in GUI session; skip it on headless CI.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --filter DarkstarE2ETests

if [[ "${DARKSTAR_SMOKE_APP:-0}" == "1" ]]; then
  echo "Building app for launch smoke…"
  swift build
  BIN=".build/debug/RoboticsControlCenter"
  "$BIN" &
  APP_PID=$!
  sleep 4
  if kill -0 "$APP_PID" 2>/dev/null; then
    echo "App launched and stayed up (pid $APP_PID)."
    kill "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
  else
    echo "App exited early — launch smoke FAILED." >&2
    exit 1
  fi
fi

echo "E2E smoke complete."
