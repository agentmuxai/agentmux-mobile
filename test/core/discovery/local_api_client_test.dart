import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/local_api_client.dart';

DioException _dioWithStatus(int status) {
  final req = RequestOptions(path: '/agentmux/discovery');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('LocalApiClient.fetchAgentsFailureMessage', () {
    // fetchAgents() is only ever reached via _enrichWithAgents, whose sole
    // callers are the mDNS scanner and UDP broadcast prober — every instance
    // that reaches here carries the narrow lan_key, never the full instance
    // key, and /agentmux/discovery requires full auth. So a 401 here is a
    // structural, permanent consequence of that scoping, not staleness — an
    // earlier version of this message wrongly said "rebuild the app", which
    // was actively misleading (Codex P2 on agentmux-mobile#20/#21): rebuilding
    // cannot change what a lan_key is scoped to. The rebuild-fixable
    // staleness case is real, but belongs to dev auto-connect specifically,
    // covered separately in discovery_provider_test.dart.
    test('a 401 explains the lan_key scoping, not staleness', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(401),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('401'));
      expect(msg, contains('lan_key'));
      expect(msg, isNot(contains('stale')));
      expect(msg, isNot(contains('Rebuild')));
      expect(msg, contains('http://192.168.1.68:60371'));
    });

    test('other Dio status codes keep the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(500),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
    });

    test('a non-Dio error keeps the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        StateError('boom'),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
      expect(msg, contains('http://192.168.1.68:60371'));
    });

    // A connect timeout has no response at all — `response?.statusCode` is
    // null, which must not be mistaken for a 401.
    test('a Dio error with no response keeps the generic message', () {
      final req = RequestOptions(path: '/agentmux/discovery');
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        DioException(
          requestOptions: req,
          type: DioExceptionType.connectionTimeout,
        ),
        'http://10.0.2.2:60237',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('lan_key')));
    });
  });
}
