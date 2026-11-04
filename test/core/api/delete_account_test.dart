import 'package:agentmux_mobile/core/api/muxbus_client.dart';
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
}
