import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/panes/panes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/viewer/viewer_fakes.dart';

const _instance = LanInstance(
  hostname: 'host-a',
  version: '0.60.0',
  address: '198.51.100.20',
  port: 29700,
  authKey: 'k',
  channel: 'stable',
  installId: testInstallId,
);

ViewerPane _pane(
  String id,
  PaneKind kind, {
  String view = '',
  String label = '',
  String window = 'w1',
  String tab = 't1',
  bool active = false,
  String? agent,
  bool? running,
  String? parent,
}) =>
    ViewerPane(
      blockId: id,
      view: view,
      kind: kind,
      label: label,
      windowId: window,
      window: window == 'w1' ? 'Main' : '',
      tabId: tab,
      tab: tab == 't1' ? 'Work' : 'Notes',
      tabActive: active,
      agent: agent,
      running: running,
      parentBlockId: parent,
    );

Map<String, Object?> _json(ViewerPane p) => {
      'block_id': p.blockId,
      'view': p.view,
      'kind': p.kind.name,
      'label': p.label,
      'window_id': p.windowId,
      'window': p.window,
      'tab_id': p.tabId,
      'tab': p.tab,
      'tab_active': p.tabActive,
      if (p.agent != null) 'agent': p.agent,
      if (p.running != null) 'running': p.running,
      if (p.parentBlockId != null) 'parent_block_id': p.parentBlockId,
    };

void main() {
  test('panes group by window and tab in the desktop\'s order', () {
    final groups = groupPanes([
      _pane('a', PaneKind.agent, active: true),
      _pane('b', PaneKind.terminal),
      _pane('c', PaneKind.other, tab: 't2'),
      _pane('d', PaneKind.other, window: 'w2', tab: 't3'),
      _pane('e', PaneKind.terminal),
    ]);
    expect(groups.map((w) => w.windowId), ['w1', 'w2']);
    expect(groups[0].tabs.map((t) => t.tabId), ['t1', 't2']);
    expect(groups[0].tabs[0].panes.map((p) => p.blockId), ['a', 'b', 'e']);
    expect(groups[0].tabs[0].active, isTrue);
    expect(groups[1].tabs.single.panes.single.blockId, 'd');
  });

  test('each row says what the pane is and where it opens', () {
    expect(paneSubtitle(_pane('a', PaneKind.agent, agent: 'ada')),
        'Agent · watch live');
    expect(paneSubtitle(_pane('a', PaneKind.agent)), 'Agent · not running');
    expect(paneSubtitle(_pane('t', PaneKind.terminal, running: true)),
        'Terminal · running · opens on the computer');
    expect(
        paneSubtitle(
            _pane('s', PaneKind.terminal, running: false, parent: 'a')),
        'Agent\'s shell · stopped · opens on the computer');
    expect(paneSubtitle(_pane('t', PaneKind.terminal)),
        'Terminal · opens on the computer');
    expect(paneSubtitle(_pane('e', PaneKind.other, view: 'editor')),
        'Editor · opens on the computer');
    expect(paneTypeName(_pane('x', PaneKind.other, view: 'ext:acme.board')),
        'Widget');
    expect(paneTypeName(_pane('x', PaneKind.other, view: 'drone')), 'Drone');
  });

  group('screen', () {
    late InMemorySecureStore store;
    setUp(() => store = InMemorySecureStore());

    Future<void> pump(WidgetTester tester, FakeAdapter adapter) async {
      final paired = testPairedHost();
      await PairedHostsRepository(store).save([paired]);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => PanesScreen(
            pairing: PairingMatch(paired: paired, host: paired.host, port: paired.port),
            instance: _instance,
            channel: 'stable',
            route: ChannelRoute.lan,
          ),
        ),
        GoRoute(
          path: '/viewer/:pairId/agent/:name',
          builder: (_, state) {
            final extra = state.extra! as Map<String, dynamic>;
            final agent = extra['agent'] as LanAgent;
            return Text('feed ${state.pathParameters['name']} (${agent.name})');
          },
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('lists the panes under their tabs; an agent opens its feed',
        (tester) async {
      final adapter = FakeAdapter([
        FakeResponse(200, json: {
          'now_ms': 1,
          'panes': [
            _json(_pane('a', PaneKind.agent, view: 'agent', label: 'Ada', agent: 'ada', active: true)),
            _json(_pane('s', PaneKind.terminal, view: 'term', label: 'Ada shell', running: true, parent: 'a')),
            _json(_pane('e', PaneKind.other, view: 'editor', tab: 't2')),
          ],
        }),
      ]);
      await pump(tester, adapter);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('shown'), findsOneWidget, reason: 'the tab shown on the computer');
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Ada shell'), findsOneWidget);
      expect(find.text('Agent\'s shell · running · opens on the computer'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget, reason: 'an untitled pane is named by its type');
      expect(find.text('Main'), findsNothing, reason: 'one window: no window header');

      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(find.text('feed ada (ada)'), findsOneWidget);
    });

    FakeResponse listed() => FakeResponse(200, json: {
          'now_ms': 1,
          'panes': [
            _json(_pane('a', PaneKind.agent, view: 'agent', label: 'Ada', agent: 'ada')),
          ],
        });

    Future<void> refresh(WidgetTester tester) async {
      await tester.fling(find.text('Ada'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets('a refresh that fails keeps the list, and says so', (tester) async {
      await pump(tester, FakeAdapter([listed(), const FakeResponse(500, json: {})]));
      expect(find.text('Ada'), findsOneWidget);
      await refresh(tester);
      expect(find.text('Ada'), findsOneWidget);
      expect(
        find.text("Couldn't refresh: can't reach the computer. This is the list from before."),
        findsOneWidget,
      );
    });

    testWidgets('a refresh the computer refuses drops the list', (tester) async {
      await pump(tester, FakeAdapter([listed(), const FakeResponse(401, json: {})]));
      await refresh(tester);
      expect(find.text('Ada'), findsNothing);
      expect(find.text('This device was unpaired on the computer'), findsOneWidget);
    });

    testWidgets('a desktop without the route asks for an update', (tester) async {
      await pump(tester, FakeAdapter([const FakeResponse(404, json: {})]));
      expect(find.text('This computer can\'t list its panes'), findsOneWidget);
    });
  });
}
