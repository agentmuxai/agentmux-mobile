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
    // A 401 here has one overwhelmingly likely cause — the desktop mints a
    // fresh auth_key every launch while AGENTMUX_DEV_KEY is baked in at build
    // time — and the generic "failed" text sends you debugging connectivity
    // instead of rebuilding. Observed live: an AgentMux auto-update mid-session
    // silently turned a working instance into "No agents reported".
    test('a 401 says the key is stale and to rebuild', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(401),
        'http://10.0.2.2:59859',
      );
      expect(msg, contains('401'));
      expect(msg, contains('stale'));
      expect(msg, contains('Rebuild'));
      expect(msg, contains('http://10.0.2.2:59859'));
    });

    test('other Dio status codes keep the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        _dioWithStatus(500),
        'http://10.0.2.2:59859',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('stale')));
    });

    test('a non-Dio error keeps the generic message', () {
      final msg = LocalApiClient.fetchAgentsFailureMessage(
        StateError('boom'),
        'http://192.168.1.68:60371',
      );
      expect(msg, contains('agent list left empty'));
      expect(msg, isNot(contains('stale')));
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
      expect(msg, isNot(contains('stale')));
    });
  });
}
