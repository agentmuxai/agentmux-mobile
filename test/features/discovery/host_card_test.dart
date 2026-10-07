import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:agentmux_mobile/core/demo/demo_data.dart';
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/features/discovery/host_card.dart';
import 'package:agentmux_mobile/shared/widgets/agent_state_chip.dart';
import 'package:agentmux_mobile/shared/widgets/tag_chip.dart';

FleetEntry _entry({
  String hostname = 'narko',
  int port = 29702,
  String? channel = 'local-main',
  String? os = 'windows',
  int? channelsRunning,
  ChannelRoute route = ChannelRoute.lan,
  String? installId,
  Presence presence = Presence.live,
  List<LanAgent> agents = const [
    LanAgent(name: 'Camper', kind: AgentKind.host),
    LanAgent(name: 'AgentX', kind: AgentKind.container),
    LanAgent(name: 'Lark'),
  ],
}) =>
    FleetEntry(
      instance: LanInstance(
        hostname: hostname,
        version: '0.59.11',
        address: '198.51.100.30',
        port: port,
        authKey: 'k',
        channel: channel,
        os: os,
        channelsRunning: channelsRunning,
        installId: installId,
        agents: agents,
      ),
      route: route,
      presence: presence,
    );

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('host row: name, platform, route and version; no address',
      (tester) async {
    final host = buildHostTrees([_entry()]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));

    expect(find.text('narko'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('LAN'), findsOneWidget);
    expect(find.text('v0.59.11'), findsOneWidget);
    expect(find.textContaining('198.51.100.30'), findsNothing);
  });

  testWidgets('agents carry HOST / SANDBOX, and no tag when unknown',
      (tester) async {
    final host = buildHostTrees([_entry()]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));

    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
    final lark = find.ancestor(
      of: find.text('Lark'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: lark, matching: find.byType(TagChip)),
      findsNothing,
    );
  });

  testWidgets('an unknown platform shows no platform tag', (tester) async {
    final host = buildHostTrees([_entry(os: 'freebsd')]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));
    expect(find.text('freebsd'), findsNothing);
    // Only the route tag and the agents' tags remain.
    expect(find.text('LAN'), findsOneWidget);
  });

  testWidgets('one visible channel of three: its name and the +N line',
      (tester) async {
    final host = buildHostTrees([_entry(channelsRunning: 3)]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));

    expect(find.text('local-main'), findsOneWidget);
    expect(find.text('+2 channels not shared on LAN'), findsOneWidget);
    // The host row and the channel row both say LAN; they agree.
    expect(find.text('LAN'), findsNWidgets(2));
  });

  testWidgets('a lone channel with no count shows no channel name',
      (tester) async {
    final host = buildHostTrees([_entry()]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));
    expect(find.text('local-main'), findsNothing);
    expect(find.textContaining('not shared on LAN'), findsNothing);
  });

  testWidgets('channels that mix routes: a badge each, none on the host row',
      (tester) async {
    final host = buildHostTrees([
      _entry(channel: 'a', port: 1),
      _entry(
        channel: 'b',
        route: ChannelRoute.cloud,
        installId: 'cccccccccccccccccccccccccc',
      ),
    ]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));

    expect(find.text('LAN'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);
  });

  testWidgets('a cloud-only agent opens the cloud agent screen',
      (tester) async {
    final host = buildHostTrees([
      _entry(
        hostname: 'Atlas',
        os: 'macos',
        route: ChannelRoute.cloud,
        installId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
        agents: const [LanAgent(name: 'AgentA', kind: AgentKind.host)],
      ),
    ]).single;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            Scaffold(body: SingleChildScrollView(child: HostCard(host: host))),
      ),
      GoRoute(
        path: '/agents/:id',
        builder: (_, state) =>
            Text('cloud agent ${state.pathParameters['id']}'),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Cloud'), findsOneWidget);
    expect(find.text('macOS'), findsOneWidget);
    await tester.tap(find.text('AgentA'));
    await tester.pumpAndSettle();
    expect(find.text('cloud agent AgentA'), findsOneWidget);
  });

  test('the notes under the list', () {
    expect(cloudNoteText(CloudListStatus.signedOut),
        'Cloud hosts are not shown (not signed in)');
    expect(cloudNoteText(CloudListStatus.unavailable),
        'Cloud hosts unavailable');
    expect(cloudNoteText(CloudListStatus.ok), isNull);
    expect(cloudNoteText(CloudListStatus.unsupported), isNull);
    expect(cloudNoteText(CloudListStatus.pending), isNull);
    expect(hiddenChannelsText(1), '+1 channel not shared on LAN');
  });

  testWidgets('long names, every tag and every chip fit a 320 dp wide device',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = buildHostTrees([
      _entry(
        hostname: 'a-very-long-host-name-indeed',
        channel: 'local-main-0a1b2c-5e6f7a8b-and-more',
        channelsRunning: 3,
        route: ChannelRoute.lanAndCloud,
        agents: [
          LanAgent(
            name: 'AVeryLongAgentNameThatGoesOnAndOn',
            kind: AgentKind.container,
            state: AgentState.working,
            stateSince: StateSince(
              elapsedAtReceipt: const Duration(minutes: 59),
              receivedAt: clock.now(),
            ),
          ),
          LanAgent(
            name: 'AnotherVeryLongAgentNameThatWaits',
            kind: AgentKind.container,
            state: AgentState.waiting,
            stateAsOf: clock.now().subtract(const Duration(minutes: 59)),
          ),
          const LanAgent(
            name: 'AThirdVeryLongAgentNameWithNoKind',
            state: AgentState.stopped,
          ),
        ],
      ),
    ]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));
    expect(tester.takeException(), isNull);
    expect(find.text('LAN + Cloud'), findsNWidgets(2));
    expect(find.text('working 59m'), findsOneWidget);
    expect(find.text('needs you, as of 59m ago'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
    // Every chip stays on screen, and every name keeps room to show.
    for (final chip in find.byType(AgentStateChip).evaluate()) {
      expect(tester.getRect(find.byWidget(chip.widget)).right,
          lessThanOrEqualTo(320));
    }
    for (final name in [
      'AVeryLongAgentNameThatGoesOnAndOn',
      'AnotherVeryLongAgentNameThatWaits',
      'AThirdVeryLongAgentNameWithNoKind',
    ]) {
      expect(tester.getSize(find.text(name)).width, greaterThan(60),
          reason: name);
    }
  });

  testWidgets('the demo fleet shows every platform and route', (tester) async {
    await tester.pumpWidget(_app(Column(children: [
      for (final h in buildDemoHosts()) HostCard(host: h),
    ])));

    for (final label in [
      'Windows',
      'macOS',
      'Linux',
      'LAN',
      'Cloud',
      'LAN + Cloud',
      'Direct',
      'HOST',
      'SANDBOX',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('+2 channels not shared on LAN'), findsOneWidget);
    for (final label in [
      'working 3m',
      'needs you',
      'idle',
      'stopped',
      'error',
      'working, as of 1m ago',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  group('agent state chips', () {
    Finder rowOf(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ListTile));

    testWidgets('a chip at the right of the row, after HOST / SANDBOX',
        (tester) async {
      final host = buildHostTrees([
        _entry(agents: [
          LanAgent(
            name: 'Camper',
            kind: AgentKind.host,
            state: AgentState.working,
            stateSince: StateSince(
              elapsedAtReceipt: const Duration(minutes: 3),
              receivedAt: clock.now(),
            ),
          ),
          const LanAgent(name: 'Lark', state: AgentState.idle),
        ]),
      ]).single;
      await tester.pumpWidget(_app(HostCard(host: host)));

      final working = find.descendant(
        of: rowOf('Camper'),
        matching: find.text('working 3m'),
      );
      expect(working, findsOneWidget);
      final kind =
          find.descendant(of: rowOf('Camper'), matching: find.text('HOST'));
      expect(tester.getRect(working).left,
          greaterThan(tester.getRect(kind).right));
      // No kind: the chip alone.
      expect(find.descendant(of: rowOf('Lark'), matching: find.text('idle')),
          findsOneWidget);
    });

    testWidgets('no state, no chip', (tester) async {
      final host = buildHostTrees([_entry()]).single;
      await tester.pumpWidget(_app(HostCard(host: host)));
      expect(find.byType(AgentStateChip), findsNothing);
    });

    testWidgets('rows keep their name order whatever the state',
        (tester) async {
      final host = buildHostTrees([
        _entry(agents: const [
          LanAgent(name: 'Zed', state: AgentState.waiting),
          LanAgent(name: 'Alpha', state: AgentState.stopped),
          LanAgent(name: 'Mid', state: AgentState.working),
        ]),
      ]).single;
      await tester.pumpWidget(_app(HostCard(host: host)));
      final ys = [
        for (final n in ['Alpha', 'Mid', 'Zed']) tester.getCenter(find.text(n)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('a channel gone quiet mutes its chips and stops the clock',
        (tester) async {
      final host = buildHostTrees([
        _entry(
          presence: Presence.stale,
          agents: [
            LanAgent(
              name: 'Camper',
              state: AgentState.working,
              stateSince: StateSince(
                elapsedAtReceipt: const Duration(minutes: 3),
                receivedAt: clock.now(),
              ),
            ),
          ],
        ),
      ]).single;
      await tester.pumpWidget(_app(HostCard(host: host)));
      expect(find.text('working'), findsOneWidget);
      expect(find.text('working 3m'), findsNothing);
      expect(
        tester
            .widget<Opacity>(find.descendant(
              of: find.byType(AgentStateChip),
              matching: find.byType(Opacity),
            ))
            .opacity,
        0.55,
      );
    });
  });
}
