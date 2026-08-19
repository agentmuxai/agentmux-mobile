import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/network_environment.dart';

InternetAddress _v4(String ip) => InternetAddress(ip, type: InternetAddressType.IPv4);

void main() {
  group('classifyNetworkHint', () {
    test('flags the Android emulator\'s QEMU/SLIRP NAT range (10.0.2.0/24)', () {
      // Confirmed live 2026-08-18 on AgentMux_Pixel9: eth0=10.0.2.15,
      // wlan0=10.0.2.16 — the exact case that motivated this spec.
      final hint = classifyNetworkHint([_v4('10.0.2.15'), _v4('10.0.2.16')]);
      expect(hint, isNotNull);
      expect(hint, contains('Android emulator'));
    });

    test('does not flag a normal 10.x LAN outside the /24 emulator range', () {
      // 10.x.x.x is also extremely common for real corporate/home LANs —
      // the check must be scoped to 10.0.2.0/24 specifically, not all of
      // 10.0.0.0/8, or this would false-positive on legitimate networks.
      expect(classifyNetworkHint([_v4('10.1.2.3')]), isNull);
      expect(classifyNetworkHint([_v4('10.0.3.5')]), isNull);
    });

    test('flags CGNAT range (100.64.0.0/10)', () {
      final hint = classifyNetworkHint([_v4('100.70.1.1')]);
      expect(hint, isNotNull);
      expect(hint, contains('CGNAT'));
    });

    test('does not flag addresses just outside the CGNAT /10 boundary', () {
      // 100.64.0.0/10 spans 100.64.0.0-100.127.255.255 (non-byte-aligned
      // prefix) — this pins the boundary is a real bitwise mask, not a
      // naive string-prefix check on "100.".
      expect(classifyNetworkHint([_v4('100.128.0.1')]), isNull);
      expect(classifyNetworkHint([_v4('100.63.255.255')]), isNull);
    });

    test('flags link-local-only as no real network connection', () {
      final hint = classifyNetworkHint([_v4('169.254.1.5')]);
      expect(hint, isNotNull);
      expect(hint, contains('link-local'));
    });

    test('flags an empty address list as no connectivity', () {
      final hint = classifyNetworkHint([]);
      expect(hint, isNotNull);
      expect(hint, contains('no network connectivity'));
    });

    test('does not flag a normal real LAN address', () {
      expect(classifyNetworkHint([_v4('192.168.1.42')]), isNull);
      expect(classifyNetworkHint([_v4('172.16.5.5')]), isNull);
    });

    test('a mix of one flagged + one normal address still flags (any match wins)', () {
      final hint = classifyNetworkHint([_v4('192.168.1.42'), _v4('10.0.2.15')]);
      expect(hint, isNotNull);
      expect(hint, contains('Android emulator'));
    });
  });

  group('isEmulatorNatAddress', () {
    test('true for the QEMU/SLIRP range', () {
      expect(isEmulatorNatAddress([_v4('10.0.2.15')]), isTrue);
      expect(isEmulatorNatAddress([_v4('10.0.2.16')]), isTrue);
    });

    test('false for a normal 10.x LAN outside the /24 emulator range', () {
      // Same false-positive concern as classifyNetworkHint — this is the
      // narrower signal discovery_relay-gating relies on, so it must not
      // fire scripts/discovery_relay.dart traffic for a real 10.x network.
      expect(isEmulatorNatAddress([_v4('10.1.2.3')]), isFalse);
    });

    test('false for CGNAT (distinct signal from classifyNetworkHint\'s general hint)', () {
      // CGNAT gets a hint too, but has no 10.0.2.2 gateway — must not be
      // conflated with the emulator-specific case.
      expect(isEmulatorNatAddress([_v4('100.70.1.1')]), isFalse);
    });

    test('true if only one of several addresses matches', () {
      expect(isEmulatorNatAddress([_v4('192.168.1.42'), _v4('10.0.2.15')]), isTrue);
    });

    test('false for an empty address list', () {
      expect(isEmulatorNatAddress([]), isFalse);
    });
  });

  group('captureNetworkSnapshot', () {
    test('never throws, even in a sandboxed test environment', () async {
      // No real assertions on the actual interface list (test environment
      // varies) — the contract this pins is "never throws," matching
      // UdpBroadcastProber.probe()'s existing "completes cleanly" test
      // precedent for environment-dependent networking calls.
      await expectLater(captureNetworkSnapshot(), completes);
    });
  });
}
