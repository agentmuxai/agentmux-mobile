import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/udp_broadcast_prober.dart';

Datagram _datagram(String body, {String ip = '192.168.1.50'}) {
  return Datagram(
    Uint8List.fromList(utf8.encode(body)),
    InternetAddress(ip),
    probePort,
  );
}

void main() {
  group('UdpBroadcastProber.parseResponse', () {
    test('parses a valid response, taking address from the datagram source',
        () {
      final instance = UdpBroadcastProber.parseResponse(_datagram(
        jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 1,
          'instance_id': 'abc-123',
          'hostname': 'my-desktop',
          'version': '0.2.0',
          'port': 12345,
          'auth_key': 'secretkey',
        }),
        ip: '10.0.0.42',
      ));

      expect(instance, isNotNull);
      expect(instance!.hostname, 'my-desktop');
      expect(instance.version, '0.2.0');
      expect(instance.port, 12345);
      expect(instance.authKey, 'secretkey');
      expect(instance.instanceId, 'abc-123');
      // Ground truth is the socket source address, not any field in the body.
      expect(instance.address, '10.0.0.42');
    });

    test('accepts a response with no instance_id', () {
      final instance = UdpBroadcastProber.parseResponse(_datagram(jsonEncode({
        'type': 'agentmux_discover_response',
        'v': 1,
        'hostname': 'my-desktop',
        'version': '0.2.0',
        'port': 12345,
        'auth_key': 'secretkey',
      })));

      expect(instance, isNotNull);
      expect(instance!.instanceId, isNull);
    });

    test('ignores wrong type', () {
      expect(
        UdpBroadcastProber.parseResponse(_datagram(jsonEncode({
          'type': 'something_else',
          'v': 1,
          'hostname': 'h',
          'version': '1',
          'port': 1,
          'auth_key': 'k',
        }))),
        isNull,
      );
    });

    test('ignores wrong protocol version', () {
      expect(
        UdpBroadcastProber.parseResponse(_datagram(jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 2,
          'hostname': 'h',
          'version': '1',
          'port': 1,
          'auth_key': 'k',
        }))),
        isNull,
      );
    });

    test('ignores missing required fields', () {
      expect(
        UdpBroadcastProber.parseResponse(_datagram(jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 1,
          'hostname': 'h',
          // version missing
          'port': 1,
          'auth_key': 'k',
        }))),
        isNull,
      );
    });

    test('ignores malformed JSON without throwing', () {
      expect(
        () => UdpBroadcastProber.parseResponse(_datagram('not json at all')),
        returnsNormally,
      );
      expect(
        UdpBroadcastProber.parseResponse(_datagram('not json at all')),
        isNull,
      );
    });

    test('ignores unrelated JSON noise on the port', () {
      expect(
        UdpBroadcastProber.parseResponse(
            _datagram(jsonEncode({'unrelated': 'packet'}))),
        isNull,
      );
    });
  });

  group('UdpBroadcastProber.probe', () {
    test('completes and closes cleanly within its internal window', () async {
      final prober = UdpBroadcastProber();
      final instances = await prober
          .probe(timeout: const Duration(milliseconds: 200))
          .toList();
      // No real responder on the network in the test environment, so we
      // just assert the stream completes cleanly (socket bind/send/close
      // lifecycle) rather than hanging or throwing.
      expect(instances, isA<List>());
    });
  });
}
