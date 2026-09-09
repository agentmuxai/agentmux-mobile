import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';

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
}
