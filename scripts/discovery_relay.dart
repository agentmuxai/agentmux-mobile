#!/usr/bin/env dart
// Copyright 2026, AgentMux Corp.
// SPDX-License-Identifier: Apache-2.0
//
// Host-side relay that lets the Android emulator's Discovery screen find a
// real AgentMux instance on this machine's real LAN — see
// docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md's follow-up: the emulator's
// default networking (QEMU/SLIRP, 10.0.2.0/24) is an isolated NAT that
// cannot send/receive real mDNS multicast or LAN broadcast at all, and the
// Android emulator's `-net-tap` bridging flag is documented as broken on
// Windows specifically (unlike Linux) — so this sidesteps OS-level
// networking entirely rather than fighting it.
//
// How it works: the app (when it detects it's running in a NAT-sandbox
// environment — see network_environment.dart) sends its normal UDP
// discovery probe an extra time, unicast, to 10.0.2.2:47892. SLIRP's
// well-known host-loopback gateway alias (10.0.2.2) NATs that straight to
// this relay's 127.0.0.1:47892 with no emulator flags or host network
// config needed — this is the exact same mechanism scripts/run-emulator.sh
// already relies on for its own HTTP connection. This relay then performs
// a REAL broadcast on the host's actual network interface, collects
// real responses from real AgentMux instances (this machine's own, or any
// other on the LAN), and relays each one back to the emulator over the
// same NAT'd channel the request arrived on — the app's *existing*
// UdpBroadcastProber listener picks them up with zero additional parsing
// code, since the wire format is identical to a normal broadcast response.
//
// Run this alongside the emulator during development:
//   dart run scripts/discovery_relay.dart
//
// Only meaningful when targeting the emulator. Does nothing for a real
// device (which doesn't send a probe here in the first place — see
// UdpBroadcastProber's relay gating).

import 'dart:async';
import 'dart:io';

const _emulatorFacingPort = 47892;
const _realDiscoveryPort = 47891;
const _broadcastCollectionWindow = Duration(milliseconds: 1500);

Future<void> main() async {
  // Loopback-only, deliberately: the emulator's 10.0.2.2 gateway alias NATs
  // straight to 127.0.0.1 on the host (see the module doc comment above), so
  // binding to anyIPv4 instead would accept probes from any device on the
  // real LAN too — turning this into an open, unauthenticated UDP reflector
  // (broadcast + relay-to-sender) that's abusable for amplification, since
  // nothing here checks the requester's identity.
  final relaySocket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4, _emulatorFacingPort);
  stdout.writeln(
      'discovery_relay: listening on 127.0.0.1:$_emulatorFacingPort '
      '(emulator reaches this via 10.0.2.2:$_emulatorFacingPort)');
  stdout.writeln(
      'discovery_relay: will broadcast probes to 255.255.255.255:$_realDiscoveryPort '
      'and relay real responses back to the emulator. Ctrl+C to stop.');

  relaySocket.listen((event) async {
    if (event != RawSocketEvent.read) return;
    final probe = relaySocket.receive();
    if (probe == null) return;
    // This is always the emulator's SLIRP-NAT'd loopback address
    // (127.0.0.1:<ephemeral>) — the return address for relaying real
    // responses back, same as any normal UDP request/response pair.
    final emulatorSrc = probe.address;
    final emulatorPort = probe.port;
    stdout.writeln('discovery_relay: relaying a probe from emulator '
        '($emulatorSrc:$emulatorPort)');

    RawDatagramSocket? broadcastSocket;
    try {
      broadcastSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      broadcastSocket.broadcastEnabled = true;
      broadcastSocket.send(
        probe.data,
        InternetAddress('255.255.255.255'),
        _realDiscoveryPort,
      );

      var responseCount = 0;
      final sub = broadcastSocket.listen((e) {
        if (e != RawSocketEvent.read) return;
        final response = broadcastSocket?.receive();
        if (response == null) return;
        responseCount++;
        // Relay verbatim — the app's UdpBroadcastProber.parseResponse()
        // parses this exact wire format already, whether it arrived via a
        // real broadcast or (as here) a relayed unicast forward.
        relaySocket.send(response.data, emulatorSrc, emulatorPort);
        stdout.writeln('discovery_relay:   relayed a response from '
            '${response.address}:${response.port} back to the emulator');
      });
      await Future<void>.delayed(_broadcastCollectionWindow);
      await sub.cancel();
      if (responseCount == 0) {
        stdout.writeln('discovery_relay:   no responses on the real LAN '
            'within ${_broadcastCollectionWindow.inMilliseconds}ms');
      }
    } finally {
      broadcastSocket?.close();
    }
  });
}
