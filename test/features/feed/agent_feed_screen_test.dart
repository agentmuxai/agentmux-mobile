import 'dart:convert';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/feed/agent_feed_screen.dart';
import 'package:agentmux_mobile/features/feed/unpaired_agent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/viewer/viewer_fakes.dart';
import 'claude_fixtures.dart';

const _instance = LanInstance(
  hostname: 'host-a',
  version: '0.60.0',
  address: '198.51.100.20',
  port: 29700,
  authKey: 'k',
  channel: 'stable',
  installId: testInstallId,
);
const _agent = LanAgent(name: 'AgentA', kind: AgentKind.host);

String _sse(String event, Object data, {String? id}) =>
    'event: $event\n${id == null ? '' : 'id: $id\n'}data: ${jsonEncode(data)}\n\n';

/// Lets the fake transport's futures and stream chunks run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late InMemorySecureStore store;
  late FakeAdapter adapter;

  Future<void> pumpFeed(
    WidgetTester tester,
    PairedHost paired, {
    LanAgent agent = _agent,
  }) async {
    await PairedHostsRepository(store).save([paired]);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => AgentFeedScreen(
          pairing: PairingMatch(
            paired: paired,
            host: paired.host,
            port: paired.port,
          ),
          agent: agent,
          instance: _instance,
          channel: 'stable',
          route: ChannelRoute.lan,
        ),
      ),
      GoRoute(
        path: '/instance/:addr/agent/:name',
        builder: (_, state) =>
            Text('message screen ${state.pathParameters['name']}'),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(
            host: host,
            port: port,
            fingerprint: fingerprint,
            token: token,
            adapter: adapter,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle(tester);
  }

  /// Disposes the screen, which closes its stream and timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  setUp(() => store = InMemorySecureStore());

  testWidgets('renders a Claude turn, read-only, live', (tester) async {
    adapter = FakeAdapter([
      FakeResponse(200, keepOpen: true, chunks: [
        _sse('snapshot', {
          'provider': 'claude',
          'gen': 1,
          'from_line': 0,
          'next_line': claudeTurn.length,
          'lines': claudeTurn,
        }, id: '1:${claudeTurn.length}'),
      ]),
    ]);
    await pumpFeed(tester, testPairedHost());

    // Header.
    expect(find.text('AgentA'), findsOneWidget);
    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('host-a  •  stable'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    // No composer.
    expect(find.byType(TextField), findsNothing);

    // The request was the agent's feed, with the viewer token.
    final req = adapter.requests.single;
    expect(req.uri.path, '/agentmux/viewer/agents/AgentA/feed');
    expect(req.headers['Authorization'], 'Bearer amxv_testtoken');

    // Body.
    expect(find.text('Fix the failing test'), findsOneWidget);
    expect(find.text('Looking at the test first.'), findsOneWidget);
    expect(find.textContaining('private reasoning'), findsNothing);
    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('lib/app.dart'), findsOneWidget);
    expect(find.text('Turn ended · 1m 05s'), findsOneWidget);

    // A tool's result opens on tap.
    expect(find.textContaining('On branch main'), findsNothing);
    await tester.tap(find.text('git status'));
    await tester.pump();
    expect(find.textContaining('On branch main'), findsOneWidget);

    // A cut result says so.
    await tester.tap(find.text('lib/main.dart'));
    await tester.pump();
    expect(find.text('Output truncated (open on the computer)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('status chip: the host list state, then the feed state',
      (tester) async {
    adapter = FakeAdapter([
      FakeResponse(200, keepOpen: true, chunks: [
        _sse('snapshot', {
          'provider': 'claude',
          'gen': 1,
          'from_line': 0,
          'next_line': 1,
          'lines': [userPrompt('hello')],
        }, id: '1:1'),
      ]),
    ]);
    await pumpFeed(
      tester,
      testPairedHost(),
      agent: const LanAgent(
        name: 'AgentA',
        kind: AgentKind.host,
        state: AgentState.idle,
      ),
    );
    // Before any status event: what the host list said.
    expect(find.text('idle'), findsOneWidget);

    // The feed's own status, three minutes in by the desktop's clock.
    adapter.open.single.add(Uint8List.fromList(utf8.encode(_sse('status', {
      'state': 'working',
      'since_ms': 1000000,
      'now_ms': 1000000 + 3 * 60 * 1000,
    }))));
    await settle(tester);
    expect(find.text('idle'), findsNothing);
    expect(find.text('working 3m'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('"Send a message…" is in the menu', (tester) async {
    adapter = FakeAdapter([const FakeResponse(200, keepOpen: true, chunks: [])]);
    await pumpFeed(tester, testPairedHost());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send a message…'));
    await tester.pumpAndSettle();
    expect(find.text('message screen AgentA'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('401: unpaired on the computer, offers to pair again',
      (tester) async {
    adapter = FakeAdapter([const FakeResponse(401, chunks: [])]);
    await pumpFeed(tester, testPairedHost());

    expect(find.text(unpairedOnComputerText), findsOneWidget);
    expect(find.text('Pair again'), findsOneWidget);
    // The pairing is marked invalid, so the host card says so too.
    final saved = await PairedHostsRepository(store).load();
    expect(saved.single.invalid, isTrue);
    await unmount(tester);
  });

  testWidgets('a pairing already refused does not connect', (tester) async {
    adapter = FakeAdapter([const FakeResponse(200, chunks: [])]);
    await pumpFeed(tester, testPairedHost(invalid: true));
    expect(find.text(unpairedOnComputerText), findsOneWidget);
    expect(adapter.requests, isEmpty);
    await unmount(tester);
  });

  testWidgets('the unpaired screen offers to pair this computer',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: UnpairedAgentScreen(
          instance: _instance,
          agent: _agent,
          channel: 'stable',
        ),
      ),
    ));
    expect(find.text('host-a isn\'t paired with this device'), findsOneWidget);
    expect(find.text('Pair this computer'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
