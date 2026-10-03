#!/usr/bin/env bash
# One-shot dev bootstrap: boot the AgentMux_Pixel9 emulator (if not already
# running), start the discovery relay so LAN discovery works from inside the
# emulator's NAT, then launch the app. Combines the manual steps documented in
# README.md's "Local Android sandbox" section so every discovery path (LAN
# relay, QR, manual, cloud, and the sidecar auto-connect with --dev-connect)
# is live on every launch instead of requiring separate manual steps each time.
#
# Usage: scripts/dev-full.sh [--dev-connect] [extra flutter run args]
#
# By default the app finds this machine the way a phone would: over the LAN
# (UDP probe via the relay; mDNS does not work on the emulator), holding only
# the broadcast lan_key. `--dev-connect` additionally bakes in this machine's
# own sidecar URL and FULL key (scripts/run-emulator.sh), which shows more than
# a phone can ever see (e.g. other channels with LAN off) - opt in only when
# that is what you are testing. See
# docs/specs/SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md section 5.5.
#
# Requires: flutter + adb + emulator on PATH, AVD `AgentMux_Pixel9` present;
# with --dev-connect, AGENTMUX_LOCAL_URL/AGENTMUX_AUTH_KEY set (see
# scripts/run-emulator.sh).
set -euo pipefail

dev_connect=0
if [ "${1:-}" = "--dev-connect" ]; then
  dev_connect=1
  shift
fi

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

# Wait for the relay to actually bind before launching the app. Without this,
# the app's first (and usually only) discovery scan can fire before the relay
# is listening, so the probe goes nowhere and the Discovery screen comes up
# empty — which looks exactly like a discovery bug rather than a startup race.
# Observed intermittently in practice; `dart run` has to compile first, so the
# bind is not instant.
echo "dev-full: waiting for relay to bind..."
for _ in $(seq 1 30); do
  if grep -q "listening on 127.0.0.1" /tmp/discovery_relay.log 2>/dev/null; then
    echo "dev-full: relay ready"
    break
  fi
  sleep 1
done
if ! grep -q "listening on 127.0.0.1" /tmp/discovery_relay.log 2>/dev/null; then
  echo "dev-full: WARNING - relay did not report ready within 30s; LAN discovery" >&2
  echo "dev-full:   from the emulator may find nothing. See /tmp/discovery_relay.log" >&2
fi

if [ "$dev_connect" = 1 ]; then
  exec scripts/run-emulator.sh -d "$DEVICE_ID" "$@"
fi
exec flutter run -d "$DEVICE_ID" "$@"
