import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/features/discovery/discovery_screen.dart';
import 'package:agentmux_mobile/features/discovery/muxbus_account_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_fakes.dart';

/// Discovery with a fixed state: no scanning, no timers.
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

Widget _app(
  FakeAuthRepository auth, {
  DiscoveryState state = const DiscoveryEmpty(cloud: CloudListStatus.signedOut),
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: '/discover',
    routes: [
      GoRoute(path: '/discover', builder: (_, __) => const DiscoveryScreen()),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('login page')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings page')),
      ),
      GoRoute(
        path: '/demo',
        builder: (_, __) => const Scaffold(body: Text('demo page')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      discoveryProvider.overrideWith(() => _FixedDiscovery(state)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
    ),
  );
}

final _bar = find.byKey(const ValueKey('muxbus-account-bar'));

void main() {
  testWidgets('the overflow menu has no cloud login, and the demo is there', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeAuthRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Cloud login'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Debug log'), findsOneWidget);
    // Demo mode stays reachable (App Review): menu and the empty view.
    expect(find.text('View a demo fleet'), findsNWidgets(2));
  });

  testWidgets('nothing found says so', (tester) async {
    await tester.pumpWidget(_app(FakeAuthRepository()));
    await tester.pumpAndSettle();
    expect(
      find.text('No AgentMux instances found on this network'),
      findsOneWidget,
    );
  });

  testWidgets('signed out: one "MuxBus Sign in" button at the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text(muxbusSignInLabel), findsOneWidget);
    expect(
      find.descendant(of: _bar, matching: find.text(muxbusSignInLabel)),
      findsOneWidget,
    );
    // It is the Scaffold's footer, not part of the scrolling content.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isA<MuxbusAccountBar>());
    // No second call to action in the body.
    expect(find.textContaining('Sign in to cloud'), findsNothing);
    expect(
      find.text('Cloud hosts are not shown (not signed in)'),
      findsOneWidget,
    );
    // Below everything else on screen.
    final barTop = tester.getTopLeft(_bar).dy;
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(barTop, greaterThan(screen.height / 2));
  });

  testWidgets('MuxBus Sign in opens the MuxBus sign-in page', (tester) async {
    await tester.pumpWidget(_app(FakeAuthRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(muxbusSignInLabel));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('signed in: the same spot names the account and opens Settings', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      signedIn: true,
      email: 'person@example.test',
    );
    await tester.pumpWidget(
      _app(auth, state: const DiscoveryEmpty(cloud: CloudListStatus.ok)),
    );
    await tester.pumpAndSettle();

    expect(find.text(muxbusSignInLabel), findsNothing);
    expect(
      find.text('MuxBus: signed in as person@example.test'),
      findsOneWidget,
    );
    await tester.tap(_bar);
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });

  testWidgets('signed in without a known email still says signed in', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeAuthRepository(signedIn: true)));
    await tester.pumpAndSettle();
    expect(find.text('MuxBus: signed in'), findsOneWidget);
  });

  for (final signedIn in [false, true]) {
    testWidgets(
      'fits a 320 dp screen at large text (signed ${signedIn ? 'in' : 'out'})',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.reset);
        final auth = FakeAuthRepository(
          signedIn: signedIn,
          email: 'someone.with.a.long.address@example.test',
        );
        await tester.pumpWidget(_app(auth, textScale: 1.6));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_bar, findsOneWidget);
        final rect = tester.getRect(_bar);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(568));
      },
    );
  }
}
