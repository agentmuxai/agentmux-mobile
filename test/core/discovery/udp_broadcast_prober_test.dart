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

    test(
        'trusts relay_source_address when the datagram arrives from the '
        'relay\'s own loopback bind (10.0.2.2:47892)', () {
      final instance = UdpBroadcastProber.parseResponse(Datagram(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 1,
          'hostname': 'gamerlove',
          'version': '0.55.37',
          'port': 60371,
          'auth_key': 'k',
          'relay_source_address': '192.168.1.105',
        }))),
        InternetAddress('10.0.2.2'),
        47892,
      ));

      expect(instance, isNotNull);
      // Without this, every relayed instance would collapse onto the
      // relay's own loopback address instead of the real responder's.
      expect(instance!.address, '192.168.1.105');
      expect(instance.port, 60371);
    });

    test(
        'ignores relay_source_address from 10.0.2.2 on a port other than '
        'the relay\'s — only that exact address/port pair is unforgeable',
        () {
      final instance = UdpBroadcastProber.parseResponse(Datagram(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 1,
          'hostname': 'h',
          'version': '1',
          'port': 1,
          'auth_key': 'k',
          'relay_source_address': '192.168.1.105',
        }))),
        InternetAddress('10.0.2.2'),
        9999,
      ));

      expect(instance, isNotNull);
      expect(instance!.address, '10.0.2.2');
    });

    test(
        'falls back to the datagram source if relay_source_address is '
        'missing from a relay-channel response', () {
      final instance = UdpBroadcastProber.parseResponse(Datagram(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'type': 'agentmux_discover_response',
          'v': 1,
          'hostname': 'h',
          'version': '1',
          'port': 1,
          'auth_key': 'k',
        }))),
        InternetAddress('10.0.2.2'),
        47892,
      ));

      expect(instance, isNotNull);
      expect(instance!.address, '10.0.2.2');
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
  group('UdpBroadcastProber.parseResponseWithSiblings', () {
    Map<String, Object?> reply({Object? siblings}) => {
          'type': 'agentmux_discover_response',
          'v': 1,
          'hostname': 'narko',
          'version': '0.59.7',
          'port': 29704,
          'auth_key': 'lan-a',
          'channel': 'local-main',
          if (siblings != null) 'siblings': siblings,
        };

    test('each sibling becomes an instance at the replying host address', () {
      final all = UdpBroadcastProber.parseResponseWithSiblings(_datagram(
        jsonEncode(reply(siblings: [
          {'channel': 'stable', 'port': 29700, 'auth_key': 'lan-b', 'version': '0.59.4'},
        ])),
        ip: '192.168.1.230',
      ));
      expect(all.map((i) => i.port), [29704, 29700]);
      final sib = all[1];
      expect(sib.hostname, 'narko');
      expect(sib.address, '192.168.1.230');
      expect(sib.authKey, 'lan-b');
      expect(sib.channel, 'stable');
      expect(sib.version, '0.59.4');
    });

    test('a reply without siblings is just the responder', () {
      final all = UdpBroadcastProber.parseResponseWithSiblings(
          _datagram(jsonEncode(reply())));
      expect(all, hasLength(1));
      expect(all.single.channel, 'local-main');
    });

    test('malformed siblings are skipped, the responder kept', () {
      final all = UdpBroadcastProber.parseResponseWithSiblings(_datagram(
        jsonEncode(reply(siblings: [
          'nonsense',
          {'channel': 'x', 'port': 0, 'auth_key': 'k'},
          {'channel': 'x', 'port': 70000, 'auth_key': 'k'},
          {'channel': 'x', 'port': 29701, 'auth_key': ''},
          {'channel': 'x', 'port': 29704, 'auth_key': 'k'},
          {'channel': 'ok', 'port': 29702, 'auth_key': 'k'},
        ])),
      ));
      expect(all.map((i) => i.port), [29704, 29702]);
    });

    test('a siblings field that is not a list is ignored', () {
      final all = UdpBroadcastProber.parseResponseWithSiblings(
          _datagram(jsonEncode(reply(siblings: {'channel': 'x'}))));
      expect(all, hasLength(1));
    });

    test('takes at most maxSiblings', () {
      final all = UdpBroadcastProber.parseResponseWithSiblings(_datagram(
        jsonEncode(reply(siblings: [
          for (var i = 0; i < 40; i++)
            {'channel': 'c$i', 'port': 30000 + i, 'auth_key': 'k'},
        ])),
      ));
      expect(all, hasLength(1 + UdpBroadcastProber.maxSiblings));
    });

    test('an invalid reply yields nothing', () {
      expect(
          UdpBroadcastProber.parseResponseWithSiblings(_datagram('{}')), isEmpty);
    });
  });
}
