#!/usr/bin/env bash
# Bootstrap the mobile app on an Android emulator connected to the local AgentMux sidecar.
#
# Usage: scripts/run-emulator.sh [extra flutter run args]
#
# Requires:
#   AGENTMUX_LOCAL_URL  — set automatically by the sidecar (e.g. http://127.0.0.1:59151)
#   AGENTMUX_AUTH_KEY   — set automatically by the sidecar
#   flutter + adb on PATH, emulator-5554 running

set -euo pipefail

: "${AGENTMUX_LOCAL_URL:?AGENTMUX_LOCAL_URL not set — is the AgentMux sidecar running?}"
: "${AGENTMUX_AUTH_KEY:?AGENTMUX_AUTH_KEY not set — is the AgentMux sidecar running?}"

# Extract port from http://127.0.0.1:PORT
PORT="${AGENTMUX_LOCAL_URL##*:}"

# The emulator reaches the host's loopback via the special 10.0.2.2 gateway.
EMULATOR_ADDR="10.0.2.2:${PORT}"

echo "Connecting emulator → AgentMux at ${EMULATOR_ADDR}"

exec flutter run \
  --dart-define="AGENTMUX_DEV_ADDR=${EMULATOR_ADDR}" \
  --dart-define="AGENTMUX_DEV_KEY=${AGENTMUX_AUTH_KEY}" \
  "$@"
