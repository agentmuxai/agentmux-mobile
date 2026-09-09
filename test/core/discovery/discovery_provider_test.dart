import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';

LanInstance _instance({
  required String hostname,
  required String address,
  required int port,
}) {
  return LanInstance(
    hostname: hostname,
    version: '0.55.39',
    address: address,
    port: port,
    authKey: 'k',
  );
}

DioException _dioWithStatus(int status) {
  final req = RequestOptions(path: '/agentmux/discovery');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('DiscoveryNotifier.devAutoConnectFailureMessage', () {
    // Unlike LocalApiClient.fetchAgentsFailureMessage's 401 case, THIS 401
    // really does mean a stale key: _kDevKey is always the full instance
    // auth_key (baked in at build time), never the scoped lan_key mDNS/UDP
    // results carry, and the desktop mints a fresh auth_key every launch.
    test('a 401 says the dev key is stale and to rebuild', () {
      final msg = DiscoveryNotifier.devAutoConnectFailureMessage(
        _dioWithStatus(401),
        '10.0.2.2',
        59859,
      );
      expect(msg, contains('401'));
      expect(msg, contains('stale'));
      expect(msg, contains('Rebuild'));
      expect(msg, contains('10.0.2.2:59859'));
    });

    test('other Dio status codes keep the generic message', () {
      final msg = DiscoveryNotifier.devAutoConnectFailureMessage(
        _dioWithStatus(500),
        '10.0.2.2',
        59859,
      );
      expect(msg, contains('failed'));
      expect(msg, isNot(contains('stale')));
    });

    test('a non-Dio error keeps the generic message', () {
      final msg = DiscoveryNotifier.devAutoConnectFailureMessage(
        StateError('boom'),
        '10.0.2.2',
        59859,
      );
      expect(msg, contains('failed'));
      expect(msg, isNot(contains('stale')));
      expect(msg, contains('10.0.2.2:59859'));
    });

    // A connect timeout has no response at all — `response?.statusCode` is
    // null, which must not be mistaken for a 401.
    test('a Dio error with no response keeps the generic message', () {
      final req = RequestOptions(path: '/agentmux/discovery');
      final msg = DiscoveryNotifier.devAutoConnectFailureMessage(
        DioException(
          requestOptions: req,
          type: DioExceptionType.connectionTimeout,
        ),
        '10.0.2.2',
        59859,
      );
      expect(msg, contains('failed'));
      expect(msg, isNot(contains('stale')));
    });
  });

  group('DiscoveryNotifier.isSameInstance', () {
    // Retro B1, confirmed live: the same physical machine reached two
    // different ways — dev auto-connect over loopback, UDP-broadcast
    // discovery over the real LAN address — rendered as two duplicate
    // cards ("10.0.2.2" and "claudius" side by side), because dedup
    // everywhere only ever compared address:port.
    test('same non-empty hostname merges even with different address:port',
        () {
      final devConnect = _instance(
        hostname: 'claudius',
        address: '10.0.2.2',
        port: 59859,
      );
      final udpDiscovered = _instance(
        hostname: 'claudius',
        address: '192.168.1.230',
        port: 51894,
      );
      expect(DiscoveryNotifier.isSameInstance(devConnect, udpDiscovered), isTrue);
    });

    test('different non-empty hostnames never merge, even sharing a port',
        () {
      final a = _instance(hostname: 'claudius', address: '192.168.1.230', port: 51894);
      final b = _instance(hostname: 'gamerlove', address: '192.168.1.68', port: 51894);
      expect(DiscoveryNotifier.isSameInstance(a, b), isFalse);
    });

    // Falls back to the original address:port comparison so behavior is
    // unchanged for a server predating the hostname field (agentmux PR
    // #3094) or an entry whose fetchDiscoveryInfo() call hasn't resolved yet.
    test('falls back to address:port when either side has no hostname', () {
      final withHostname = _instance(hostname: 'claudius', address: '10.0.2.2', port: 59859);
      final withoutHostname = _instance(hostname: '', address: '10.0.2.2', port: 59859);
      expect(DiscoveryNotifier.isSameInstance(withHostname, withoutHostname), isTrue);

      final differentAddress = _instance(hostname: '', address: '10.0.2.3', port: 59859);
      expect(DiscoveryNotifier.isSameInstance(withoutHostname, differentAddress), isFalse);
    });
  });
}
