import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/fleet_store.dart';
import 'package:agentmux_mobile/features/discovery/fleet_status.dart';
import 'package:agentmux_mobile/features/discovery/muxbus_account_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/auth/auth_fakes.dart';

FleetEntry _entry(
  String host, {
  ChannelRoute route = ChannelRoute.lan,
  List<LanAgent> agents = const [],
}) => FleetEntry(
  instance: LanInstance(
    hostname: host,
    version: '0.60.15',
    address: '198.51.100.30',
    port: 29702,
    authKey: 'k',
    channel: 'stable',
    os: 'macos',
    agents: agents,
  ),
  route: route,
);

class _FixedDiscovery extends DiscoveryNotifier {
  _FixedDiscovery(this.fixed);
  final DiscoveryState fixed;

  @override
  DiscoveryState build() => fixed;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshCloud() async {}
}

void main() {
  group('summarizeFleet', () {
    test('counts computers, working and waiting agents, and the route', () {
      final hosts = buildHostTrees([
        _entry(
          'studio-mac',
          agents: const [
            LanAgent(name: 'Nova', state: AgentState.working),
            LanAgent(name: 'Orion', state: AgentState.waiting),
            LanAgent(name: 'Vega', state: AgentState.idle),
          ],
        ),
        _entry(
          'build-box',
          agents: const [LanAgent(name: 'Atlas', state: AgentState.working)],
        ),
        _entry('office-pc'),
      ]);
      final s = summarizeFleet(DiscoveryResults(hosts));
      expect(s.connection, 'LAN');
      expect(s.computers, 3);
      expect(s.working, 2);
      expect(s.waiting, 1);
      expect(s.live, isTrue);
      expect(s.left(), 'LAN · 3 computers');
      expect(s.left(short: true), 'LAN · 3');
      expect(s.right(), '2 working · 1 needs you');
      expect(s.right(short: true), '1 needs you');
      expect(s.spoken, 'LAN, 3 computers, 2 working · 1 needs you');
    });

    test('says Cloud, and LAN + Cloud when both reach computers', () {
      final cloudOnly = buildHostTrees([
        _entry('a', route: ChannelRoute.cloud),
      ]);
      expect(summarizeFleet(DiscoveryResults(cloudOnly)).connection, 'Cloud');
      expect(
        summarizeFleet(DiscoveryResults(cloudOnly)).left(),
        'Cloud · 1 computer',
      );
      final both = buildHostTrees([
        _entry('a'),
        _entry('b', route: ChannelRoute.cloud),
      ]);
      expect(summarizeFleet(DiscoveryResults(both)).connection, 'LAN + Cloud');
    });

    test('a channel seen both ways counts as both; a direct one is Direct', () {
      final both = buildHostTrees([
        _entry('a', route: ChannelRoute.lanAndCloud),
      ]);
      expect(summarizeFleet(DiscoveryResults(both)).connection, 'LAN + Cloud');
      final direct = buildHostTrees([_entry('a', route: ChannelRoute.direct)]);
      expect(summarizeFleet(DiscoveryResults(direct)).connection, 'Direct');
      final mixed = buildHostTrees([
        _entry('a', route: ChannelRoute.direct),
        _entry('b', route: ChannelRoute.cloud),
      ]);
      expect(
        summarizeFleet(DiscoveryResults(mixed)).connection,
        'Direct + Cloud',
      );
    });

    test('scanning and empty', () {
      expect(summarizeFleet(const DiscoveryScanning()).left(), 'Searching…');
      final none = summarizeFleet(const DiscoveryEmpty());
      expect(none.left(), 'No computers');
      expect(none.right(), '');
    });
  });

  group('the account bar', () {
    Future<void> pump(
      WidgetTester tester, {
      required double bottom,
      double keyboard = 0,
      Size size = const Size(402, 874),
      DiscoveryState state = const DiscoveryEmpty(),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            discoveryProvider.overrideWith(() => _FixedDiscovery(state)),
          ],
          child: MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: EdgeInsets.only(bottom: bottom),
                    viewPadding: EdgeInsets.only(bottom: bottom),
                    viewInsets: EdgeInsets.only(bottom: keyboard),
                  ),
                  child: child!,
                ),
            home: const Scaffold(bottomNavigationBar: MuxbusAccountBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final status = find.textContaining('No computers');
    final button = find.byKey(const ValueKey('muxbus-account-bar'));

    testWidgets('with a home-indicator band the status line sits in the band', (
      tester,
    ) async {
      await pump(tester, bottom: 34);
      expect(status, findsOneWidget);
      // Below the button, inside the 34 pt band at the bottom of the screen.
      expect(
        tester.getRect(status).top,
        greaterThan(tester.getRect(button).bottom),
      );
      expect(tester.getRect(status).bottom, lessThanOrEqualTo(874));
      expect(tester.getRect(status).bottom, greaterThan(874 - 34));
      // Clear of the curved corner.
      expect(tester.getRect(status).left, greaterThanOrEqualTo(22));
    });

    testWidgets('without a band the same line is a row above the button', (
      tester,
    ) async {
      await pump(tester, bottom: 0, size: const Size(375, 667));
      expect(status, findsOneWidget);
      expect(
        tester.getRect(status).bottom,
        lessThanOrEqualTo(tester.getRect(button).top),
      );
    });

    testWidgets('the line is left out while the keyboard is up', (
      tester,
    ) async {
      await pump(tester, bottom: 34, keyboard: 300);
      expect(status, findsNothing);
      expect(button, findsOneWidget);
    });

    testWidgets('large text does not push the line out of its band', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pump(tester, bottom: 34);
      expect(tester.takeException(), isNull);
      // 11 pt text, not 34: the band is 34 pt tall.
      expect(tester.getSize(status).height, lessThan(20));
    });

    testWidgets('a three-button navigation bar is not a band: row above', (
      tester,
    ) async {
      await pump(tester, bottom: 48);
      expect(status, findsOneWidget);
      expect(
        tester.getRect(status).bottom,
        lessThanOrEqualTo(tester.getRect(button).top),
      );
    });

    final busy = DiscoveryResults(
      buildHostTrees([
        _entry(
          'studio-mac',
          agents: const [
            LanAgent(name: 'Nova', state: AgentState.working),
            LanAgent(name: 'Orion', state: AgentState.waiting),
          ],
        ),
      ]),
    );

    testWidgets('on a 393 pt phone the right half keeps one whole count', (
      tester,
    ) async {
      await pump(tester, bottom: 34, size: const Size(393, 852), state: busy);
      // The count that asks something of the person, not an ellipsis.
      expect(find.text('1 needs you'), findsOneWidget);
      expect(find.text('LAN · 1'), findsOneWidget);
    });

    testWidgets('a wide window shows both counts in full', (tester) async {
      await pump(tester, bottom: 34, size: const Size(520, 900), state: busy);
      expect(find.text('1 working · 1 needs you'), findsOneWidget);
      expect(find.text('LAN · 1 computer'), findsOneWidget);
    });

    testWidgets('shows the fleet it is given', (tester) async {
      final hosts = buildHostTrees([
        _entry(
          'studio-mac',
          agents: const [LanAgent(name: 'Nova', state: AgentState.working)],
        ),
      ]);
      // Wide enough for the long wording beside the home indicator.
      await pump(
        tester,
        bottom: 34,
        size: const Size(440, 956),
        state: DiscoveryResults(hosts),
      );
      expect(find.text('LAN · 1 computer'), findsOneWidget);
      expect(find.text('1 working'), findsOneWidget);
    });
  });
}
