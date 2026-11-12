import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/core/discovery/discovery_provider.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/secure_store.dart';
import 'package:agentmux_mobile/features/discovery/discovery_screen.dart';
import 'package:agentmux_mobile/features/welcome/welcome.dart';
import 'package:agentmux_mobile/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_fakes.dart';
import '../../core/viewer/viewer_fakes.dart';

/// Discovery that counts how often it was started, and finds nothing.
class _CountingDiscovery extends DiscoveryNotifier {
  static int built = 0;

  @override
  DiscoveryState build() {
    built++;
    return const DiscoveryEmpty(cloud: CloudListStatus.signedOut);
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshCloud() async {}
}

/// A store that can't be read or written.
class _BrokenStore implements SecureStore {
  @override
  Future<String?> read(String key) => Future.error(StateError('no store'));

  @override
  Future<void> write(String key, String value) =>
      Future.error(StateError('no store'));

  @override
  Future<void> delete(String key) async {}
}

Widget _app(SecureStore store, {double textScale = 1}) {
  final router = GoRouter(
    initialLocation: '/discover',
    routes: [
      GoRoute(path: '/discover', builder: (_, __) => const DiscoveryScreen()),
      GoRoute(
        path: '/demo',
        builder: (_, __) => const Scaffold(body: Text('demo page')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      discoveryProvider.overrideWith(_CountingDiscovery.new),
      secureStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
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

/// A phone: the default test window is a landscape 800 x 600.
void _phone(WidgetTester tester, [Size size = const Size(393, 852)]) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The button's own box. Its widget is 4 taller: Material pads the tap
/// target to 48.
Finder _box(Finder button) =>
    find.descendant(of: button, matching: find.byType(Material)).first;

void main() {
  setUp(() => _CountingDiscovery.built = 0);

  testWidgets(
    'the first launch says what AgentMux is, and does not look at the network yet',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(InMemorySecureStore()));
      await tester.pumpAndSettle();

      expect(find.text(whatAgentMuxIs), findsOneWidget);
      for (final (_, text) in welcomePoints) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('View a demo fleet'), findsOneWidget);
      // The phone's local-network question must come after the explanation.
      expect(_CountingDiscovery.built, 0);
    },
  );

  testWidgets('Continue goes to the computers, and the welcome is not shown again', (
    tester,
  ) async {
    _phone(tester);
    final store = InMemorySecureStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsNothing);
    expect(
      find.text('No AgentMux instances found on this network'),
      findsOneWidget,
    );
    expect(_CountingDiscovery.built, 1);
    expect(store.values[welcomeSeenKey], '1');

    // The next launch, with the same store.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
    expect(find.byKey(const ValueKey('scan-offer')), findsOneWidget);
  });

  testWidgets('the demo is reachable from the welcome page', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(InMemorySecureStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View a demo fleet'));
    await tester.pumpAndSettle();
    expect(find.text('demo page'), findsOneWidget);
  });

  testWidgets('a store that cannot be read skips the welcome', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(_BrokenStore()));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
    expect(find.byKey(const ValueKey('scan-offer')), findsOneWidget);
  });

  testWidgets('a store that cannot be written still lets the person on', (
    tester,
  ) async {
    _phone(tester);
    final store = _WriteFails();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-continue')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('scan-offer')), findsOneWidget);
  });

  testWidgets(
    'with nothing connected the screen says what AgentMux is and offers the QR code first',
    (tester) async {
      _phone(tester);
      final store = InMemorySecureStore()..values[welcomeSeenKey] = '1';
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      expect(find.text(whatAgentMuxIs), findsOneWidget);
      final offer = find.byKey(const ValueKey('scan-offer'));
      expect(
        find.descendant(of: offer, matching: find.text('Connect a computer')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: offer, matching: find.text(whereTheQrCodeIs)),
        findsOneWidget,
      );
      // The scan is the filled button; the other ways come after it.
      final scan = find.descendant(
        of: offer,
        matching: find.ancestor(
          of: find.text('Scan QR code'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(scan, findsOneWidget);
      expect(
        tester.getTopLeft(scan).dy,
        lessThan(tester.getTopLeft(find.text('Connect manually')).dy),
      );
      expect(find.text(lanDiscoveryHint), findsOneWidget);
    },
  );

  testWidgets('buttons are 44 high with square corners, as in the Cloud Console', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(InMemorySecureStore()));
    await tester.pumpAndSettle();
    for (final key in ['welcome-scan', 'welcome-continue']) {
      final box = _box(find.byKey(ValueKey(key)));
      expect(tester.getSize(box).height, AppTheme.buttonHeight, reason: key);
      final shape = tester.widget<Material>(box).shape;
      expect(
        (shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.zero,
        reason: key,
      );
    }
  });

  testWidgets('the welcome page fits a small phone at a large text size', (
    tester,
  ) async {
    _phone(tester, const Size(320, 568));
    await tester.pumpWidget(_app(InMemorySecureStore(), textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // It scrolls to its last button.
    await tester.ensureVisible(find.text('View a demo fleet'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _WriteFails extends InMemorySecureStore {
  @override
  Future<void> write(String key, String value) =>
      Future.error(StateError('read-only'));
}
