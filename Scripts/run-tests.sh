#!/bin/bash
# Darkstar Robotics — full automated test suite.
#
# Usage:
#   Scripts/run-tests.sh              # unit + integration + end-to-end
#   Scripts/run-tests.sh unit         # DarkstarCoreTests only
#   Scripts/run-tests.sh integration  # DarkstarIntegrationTests only
#   Scripts/run-tests.sh e2e          # DarkstarE2ETests only
#
# Requires macOS with Xcode / Swift 5.9+. Exits non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-all}" in
  unit)        swift test --filter DarkstarCoreTests ;;
  integration) swift test --filter DarkstarIntegrationTests ;;
  e2e)         swift test --filter DarkstarE2ETests ;;
  all)         swift test ;;
  *) echo "Unknown tier: $1 (use unit, integration, e2e, or no argument)" >&2; exit 2 ;;
esac
