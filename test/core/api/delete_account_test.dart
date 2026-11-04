import 'package:agentmux_mobile/core/api/muxbus_client.dart';
import 'package:agentmux_mobile/core/auth/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/auth_fakes.dart';

MuxbusClient _client(RouteAdapter adapter) => MuxbusClient(
  FakeAuthRepository(signedIn: true),
  httpClientAdapter: adapter,
);

void main() {
  test('200: deleted, with a DELETE to /api/account', () async {
    final adapter = RouteAdapter({
      '/api/account': const FakeAnswer(200, {'status': 'deleted'}),
    });
    expect(
      await _client(adapter).deleteAccount(),
      DeleteAccountOutcome.deleted,
    );
    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.uri.path, '/api/account');
  });

  test('200 for a repeat (already_deleted) is deleted too', () async {
    final adapter = RouteAdapter({
      '/api/account': const FakeAnswer(200, {
        'status': 'deleted',
        'already_deleted': true,
      }),
    });
    expect(
      await _client(adapter).deleteAccount(),
      DeleteAccountOutcome.deleted,
    );
  });

  test('401 means the session is already gone', () async {
    final adapter = RouteAdapter({
      '/api/account': const FakeAnswer(401, {'error': 'Unauthorized'}),
    });
    expect(
      await _client(adapter).deleteAccount(),
      DeleteAccountOutcome.signedOut,
    );
  });

  test('403 is a refusal', () async {
    final adapter = RouteAdapter({
      '/api/account': const FakeAnswer(403, {'error': 'forbidden'}),
    });
    expect(
      await _client(adapter).deleteAccount(),
      DeleteAccountOutcome.refused,
    );
  });

  test('500 (partway) and an unreachable service are failed: try again', () async {
    final partway = RouteAdapter({
      '/api/account': const FakeAnswer(500, {
        'error': 'deletion_failed',
        'retryable': true,
      }),
    });
    expect(
      await _client(partway).deleteAccount(),
      DeleteAccountOutcome.failed,
    );
    final offline = RouteAdapter({'/api/account': const FakeAnswer.offline()});
    expect(
      await _client(offline).deleteAccount(),
      DeleteAccountOutcome.failed,
    );
  });

  group('the token', () {
    test('a refresh that could not reach the service is failed, not signed out', () async {
      final auth = FakeAuthRepository(signedIn: true)
        ..tokenError = DioException.connectionError(
          requestOptions: RequestOptions(path: '/oauth2/token'),
          reason: 'offline',
        );
      final adapter = RouteAdapter({'/api/account': const FakeAnswer(200)});
      final client = MuxbusClient(auth, httpClientAdapter: adapter);
      expect(await client.deleteAccount(), DeleteAccountOutcome.failed);
      expect(adapter.requests, isEmpty);
    });

    test('a 5xx or 429 from the token endpoint, or a network or storage fault, is failed', () async {
      for (final error in <Object>[
        DioException(
          requestOptions: RequestOptions(path: '/oauth2/token'),
          response: Response(
            requestOptions: RequestOptions(path: '/oauth2/token'),
            statusCode: 503,
          ),
        ),
        DioException(
          requestOptions: RequestOptions(path: '/oauth2/token'),
          response: Response(
            requestOptions: RequestOptions(path: '/oauth2/token'),
            statusCode: 429,
          ),
        ),
        AuthNetworkError(),
        AuthUnavailable(),
        StateError('secure storage'),
      ]) {
        final auth = FakeAuthRepository(signedIn: true)..tokenError = error;
        final adapter = RouteAdapter({'/api/account': const FakeAnswer(200)});
        expect(
          await MuxbusClient(auth, httpClientAdapter: adapter).deleteAccount(),
          DeleteAccountOutcome.failed,
          reason: '$error',
        );
        expect(adapter.requests, isEmpty);
      }
    });

    test('a refresh the service refused, or no session, is signed out', () async {
      final refused = FakeAuthRepository(signedIn: true)
        ..tokenError = DioException(
          requestOptions: RequestOptions(path: '/oauth2/token'),
          response: Response(
            requestOptions: RequestOptions(path: '/oauth2/token'),
            statusCode: 400,
          ),
        );
      final adapter = RouteAdapter({'/api/account': const FakeAnswer(200)});
      expect(
        await MuxbusClient(refused, httpClientAdapter: adapter).deleteAccount(),
        DeleteAccountOutcome.signedOut,
      );
      final none = FakeAuthRepository()..tokenError = AuthException('Not authenticated');
      expect(
        await MuxbusClient(none, httpClientAdapter: adapter).deleteAccount(),
        DeleteAccountOutcome.signedOut,
      );
      expect(adapter.requests, isEmpty);
    });
  });
}
