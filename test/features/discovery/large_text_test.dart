import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/features/demo/demo_fleet_screen.dart';
import 'package:agentmux_mobile/features/login/login_screen.dart';
import 'package:agentmux_mobile/features/settings/settings_screen.dart';
import 'package:agentmux_mobile/features/discovery/discovery_screen.dart';
import 'package:agentmux_mobile/features/discovery/muxbus_account_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_fakes.dart';
import '../welcome/welcome_fakes.dart';

class _Empty extends DiscoveryNotifier {
  @override
  DiscoveryState build() => const DiscoveryEmpty();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshCloud() async {}
}

/// The largest iOS accessibility text (AX5 is about x3.1) on the narrowest
/// phone the app supports: I7 and A6 in
/// `docs/specs/SPEC_FORM_FACTORS_AND_EDGES_2026_11_04.md`.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double scale = 3.1,
  bool routed = false,
}) async {
  tester.view
    ..physicalSize = const Size(320, 568)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        discoveryProvider.overrideWith(_Empty.new), welcomeAlreadySeen,
      ],
      child: routed
          ? MaterialApp.router(
              routerConfig: GoRouter(
                routes: [GoRoute(path: '/', builder: (_, __) => home)],
              ),
            )
          : MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {

  testWidgets('the sign-in title is not broken inside the word', (tester) async {
    await _pump(tester, const LoginScreen());
    expect(tester.takeException(), isNull);
    // The title is clamped (the Ahem test font is too wide to count lines).
    final scaler = MediaQuery.textScalerOf(tester.element(find.text('MuxBus')));
    expect(scaler.scale(10), lessThanOrEqualTo(20));
  });

  testWidgets('settings: the version value goes under its label', (tester) async {
    await _pump(tester, const SettingsScreen(), routed: true);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Version'), 200);
    final label = tester.getRect(find.text('Version'));
    final value = tester.getRect(find.textContaining('0.1.0'));
    expect(value.top, greaterThanOrEqualTo(label.bottom));
  });
  testWidgets('host rows keep a readable name and put the tags under it', (
    tester,
  ) async {
    await _pump(tester, const DemoFleetScreen());
    expect(tester.takeException(), isNull);
    // "atlas" on one line, not a letter wide: well over three characters.
    final name = tester.getSize(find.text('atlas'));
    expect(name.width, greaterThan(60));
    expect(name.height, lessThan(2 * 31 * 1.2 * 2.2));
    // The version moved to the line under the name rather than beside it.
    expect(find.textContaining('v0.59.11'), findsWidgets);
    // The platform tag is a whole word, not a column of letters.
    expect(tester.getSize(find.text('Windows')).width, greaterThan(40));
  });

  testWidgets('agent names are not squeezed by their tags', (tester) async {
    await _pump(tester, const DemoFleetScreen());
    final nova = tester.getRect(find.text('Nova'));
    final host = tester.getRect(find.text('HOST').first);
    // The name is on its own line, above the tags.
    expect(host.top, greaterThanOrEqualTo(nova.bottom - 1));
    expect(nova.width, greaterThan(60));
  });

  testWidgets('the discovery title is not cut and refresh moves to the menu', (
    tester,
  ) async {
    await _pump(tester, const DiscoveryScreen());
    expect(tester.takeException(), isNull);
    // The title's text scale is clamped (the test font is as wide as it is
    // tall, so its fit is judged on the emulator, not here).
    final title = tester.widget<Text>(find.text('AgentMux'));
    expect(title.data, 'AgentMux');
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('AgentMux'))).scale(10),
      closeTo(13, 0.01),
    );
    // No refresh button in the bar; it is in the menu.
    expect(find.byTooltip('Refresh'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('a normal phone at normal text keeps the refresh button', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          discoveryProvider.overrideWith(_Empty.new), welcomeAlreadySeen,
        ],
        child: const MaterialApp(home: DiscoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('the sign-in button does not take a quarter of the screen', (
    tester,
  ) async {
    await _pump(tester, const Scaffold(bottomNavigationBar: MuxbusAccountBar()));
    final h =
        tester.getSize(find.byKey(const ValueKey('muxbus-account-bar'))).height;
    expect(h, lessThan(568 / 6));
  });

  testWidgets('the empty status is whole beside the home indicator on 320 dp', (
    tester,
  ) async {
    tester.view
      ..padding = const FakeViewPadding(bottom: 34)
      ..viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await _pump(tester, const Scaffold(bottomNavigationBar: MuxbusAccountBar()));
    // Each half of the band is about 63 dp wide there: the short word shows,
    // not "No com…".
    final word = find.text('None');
    expect(word, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(word).didExceedMaxLines, isFalse);
  });
}
