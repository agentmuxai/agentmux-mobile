import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/features/demo/demo_agent_detail_screen.dart';
import 'package:agentmux_mobile/features/demo/demo_fleet_screen.dart';
import 'package:agentmux_mobile/features/discovery/manual_add_sheet.dart';
import 'package:agentmux_mobile/features/discovery/muxbus_account_bar.dart';
import 'package:agentmux_mobile/shared/widgets/edge_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/auth/auth_fakes.dart';

/// A landscape iPhone 17 Pro Max: 62 pt of Dynamic Island on each side and the
/// 20 pt home-indicator band, no status bar.
const _landscapeInsets = EdgeInsets.only(left: 62, right: 62, bottom: 20);

Widget _app(
  Widget home, {
  Size size = const Size(956, 440),
  EdgeInsets? insets,
}) {
  return ProviderScope(
    child: MaterialApp(
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              padding: insets ?? _landscapeInsets,
              viewPadding: insets ?? _landscapeInsets,
            ),
            child: child!,
          ),
      home: home,
    ),
  );
}

void main() {
  testWidgets('insetListPadding adds the safe area to the base padding', (
    tester,
  ) async {
    late EdgeInsets got;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            got = insetListPadding(context, const EdgeInsets.all(12));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, const EdgeInsets.fromLTRB(74, 12, 74, 32));
  });

  testWidgets('demo fleet: cards stay out of the island side, banner reaches '
      'both edges', (tester) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const DemoFleetScreen()));

    final banner = find.text('DEMO DATA — not a live connection');
    expect(banner, findsOneWidget);
    // The yellow is the banner's Container: full width, edge to edge.
    final colour = find.ancestor(of: banner, matching: find.byType(Container));
    final box = tester.getRect(colour.first);
    expect(box.left, 0);
    expect(box.right, 956);
    // The text itself keeps clear of the island.
    expect(tester.getRect(banner).left, greaterThanOrEqualTo(62));

    // The first card starts after the inset plus its 12 pt of padding.
    final firstCard = find.byType(Card).first;
    expect(tester.getRect(firstCard).left, greaterThanOrEqualTo(62 + 12));
    expect(tester.getRect(firstCard).right, lessThanOrEqualTo(956 - 62 - 12));
  });

  testWidgets('demo fleet: the last card ends above the home-indicator band', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const portrait = EdgeInsets.only(top: 62, bottom: 34);
    await tester.pumpWidget(
      _app(
        const DemoFleetScreen(),
        size: const Size(402, 874),
        insets: portrait,
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    final lastCard = find.byType(Card).last;
    expect(tester.getRect(lastCard).bottom, lessThanOrEqualTo(874 - 34));
  });

  testWidgets('demo agent: messages stay out of the island side', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const DemoAgentDetailScreen(agentId: 'Nova')));
    // A message tile is a Container with a bordered decoration.
    final tiles = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null,
    );
    expect(tiles, findsWidgets);
    expect(tester.getRect(tiles.first).left, greaterThanOrEqualTo(62 + 12));
    expect(tester.getRect(tiles.first).right, lessThanOrEqualTo(956 - 62 - 12));
  });

  testWidgets('connect manually: scrolls above a landscape keyboard instead '
      'of overflowing', (tester) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 208);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showManualAddSheet(context),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualAddSheet), findsOneWidget);
    // A RenderFlex overflow is reported as a test exception.
    expect(tester.takeException(), isNull);
    // The Connect button can be scrolled into view.
    await tester.ensureVisible(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  Future<double> barHeight(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: MuxbusAccountBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .getSize(find.byKey(const ValueKey('muxbus-account-bar')))
        .height;
  }

  testWidgets('sign-in bar: compact on a short landscape phone only', (
    tester,
  ) async {
    final phone = await barHeight(tester, const Size(956, 440));
    final portrait = await barHeight(tester, const Size(402, 874));
    final ipad = await barHeight(tester, const Size(1376, 774));
    expect(phone, lessThan(portrait));
    // A wide, tall landscape iPad keeps the full bar.
    expect(ipad, portrait);
  });
}
