import 'package:agentmux_mobile/core/api/api_provider.dart';
import 'package:agentmux_mobile/core/api/muxbus_client.dart';
import 'package:agentmux_mobile/core/api/muxbus_socket.dart';
import 'package:agentmux_mobile/features/agent_detail/agent_detail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/auth/auth_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouteAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = RouteAdapter({
      '/api/messages': const FakeAnswer(200, {
        'messages': [
          {
            'id': 'm1',
            'from': 'AgentX',
            'to': 'Camper',
            'message': 'hello',
            'timestamp': '2026-10-09T12:00:00Z',
          },
        ],
      }),
    });
    final auth = FakeAuthRepository(signedIn: true);
    container = ProviderContainer(
      overrides: [
        muxbusClientProvider.overrideWithValue(
          MuxbusClient(auth, httpClientAdapter: adapter),
        ),
        // Never connected: init() is not called.
        muxbusSocketProvider.overrideWithValue(MuxbusSocket(auth)),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('agentDetailProvider', () {
    test('viewing an agent does not mark its messages read', () async {
      final messages = await container.read(
        agentDetailProvider('Camper').future,
      );

      expect(messages.single.id, 'm1');
      final request = adapter.requests.single;
      expect(request.uri.path, '/api/messages');
      expect(request.uri.queryParameters['mark_as_read'], 'false');
      expect(request.uri.queryParameters['unread_only'], 'false');
    });

    test('a refresh does not mark them read either', () async {
      await container.read(agentDetailProvider('Camper').future);
      await container
          .read(agentDetailProvider('Camper').notifier)
          .refresh('Camper');

      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((r) => r.uri.queryParameters['mark_as_read']),
        everyElement('false'),
      );
    });
  });

  group('MuxbusClient.getMessages', () {
    test('marks read only when asked to', () async {
      final client = MuxbusClient(
        FakeAuthRepository(signedIn: true),
        httpClientAdapter: adapter,
      );
      await client.getMessages('Camper');
      await client.getMessages('Camper', markAsRead: true);

      expect(
        adapter.requests.map((r) => r.uri.queryParameters['mark_as_read']),
        ['false', 'true'],
      );
    });
  });
}
