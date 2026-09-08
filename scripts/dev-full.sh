#!/usr/bin/env bash
# One-shot dev bootstrap: boot the AgentMux_Pixel9 emulator (if not already
# running), start the discovery relay so LAN discovery works from inside the
# emulator's NAT, then launch the app via run-emulator.sh so it also
# auto-connects to this machine's own AgentMux sidecar. Combines the manual
# steps documented in README.md's "Local Android sandbox" section so every
# discovery path (sidecar auto-connect, LAN relay, QR, manual, cloud) is live
# on every launch instead of requiring separate manual steps each time.
#
# Usage: scripts/dev-full.sh [extra flutter run args, e.g. --dart-define=...]
#
# Requires: flutter + adb + emulator on PATH, AVD `AgentMux_Pixel9` present,
# AGENTMUX_LOCAL_URL/AGENTMUX_AUTH_KEY set (see scripts/run-emulator.sh).
set -euo pipefail

cd "$(dirname "$0")/.."

AVD_NAME="AgentMux_Pixel9"
DEVICE_ID="emulator-5554"

if ! adb devices | grep -qE "^${DEVICE_ID}[[:space:]]+device$"; then
  echo "dev-full: booting ${AVD_NAME}..."
  emulator -avd "$AVD_NAME" -no-snapshot-load > /tmp/emulator.log 2>&1 &
  adb -s "$DEVICE_ID" wait-for-device
  until [ "$(adb -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 3
  done
else
  echo "dev-full: ${DEVICE_ID} already booted"
fi

echo "dev-full: starting discovery relay..."
dart run scripts/discovery_relay.dart > /tmp/discovery_relay.log 2>&1 &
relay_pid=$!
trap 'kill "$relay_pid" 2>/dev/null || true' EXIT

exec scripts/run-emulator.sh -d "$DEVICE_ID" "$@"
