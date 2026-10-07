import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:agentmux_mobile/core/demo/demo_data.dart';
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/features/discovery/host_card.dart';
import 'package:agentmux_mobile/shared/widgets/tag_chip.dart';

FleetEntry _entry({
  String hostname = 'narko',
  int port = 29702,
  String? channel = 'local-main',
  String? os = 'windows',
  int? channelsRunning,
  ChannelRoute route = ChannelRoute.lan,
  String? installId,
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
        hostname: 'Area54',
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

  testWidgets('long names and every tag fit a 320 dp wide phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = buildHostTrees([
      _entry(
        hostname: 'a-very-long-host-name-indeed',
        channel: 'local-main-b28b7a-8bf515d4-and-more',
        channelsRunning: 3,
        route: ChannelRoute.lanAndCloud,
        agents: const [
          LanAgent(
            name: 'AVeryLongAgentNameThatGoesOnAndOn',
            kind: AgentKind.container,
          ),
        ],
      ),
    ]).single;
    await tester.pumpWidget(_app(HostCard(host: host)));
    expect(tester.takeException(), isNull);
    expect(find.text('LAN + Cloud'), findsNWidgets(2));
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
  });
}
