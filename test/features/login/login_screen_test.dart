import 'dart:async';

import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/core/auth/auth_repository.dart';
import 'package:agentmux_mobile/features/login/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_fakes.dart';

Widget _app(FakeAuthRepository auth, {double textScale = 1}) {
  final router = GoRouter(
    initialLocation: '/discover',
    routes: [
      GoRoute(
        path: '/discover',
        builder: (_, __) => const Scaffold(body: Text('discover page')),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
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

Future<void> _openLogin(
  WidgetTester tester,
  FakeAuthRepository auth, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(_app(auth, textScale: textScale));
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.text('discover page'))).push('/login');
  await tester.pumpAndSettle();
}

final _google = find.byKey(const ValueKey('connect-google'));
final _email = find.byKey(const ValueKey('use-email'));

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<ButtonStyleButton>(f).onPressed != null;

void main() {
  testWidgets('title, reason, Connect with Google, Use email and Not now', (
    tester,
  ) async {
    await _openLogin(tester, FakeAuthRepository());
    expect(find.text('MuxBus'), findsOneWidget);
    expect(find.text(muxbusSignInReason), findsOneWidget);
    expect(find.text('Connect with Google'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.text('Use email'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(_enabled(tester, _google), isTrue);
    expect(_enabled(tester, _email), isTrue);
  });

  testWidgets('Connect with Google signs in with Google, busy meanwhile', (
    tester,
  ) async {
    final auth = FakeAuthRepository()..pendingSignIn = Completer<void>();
    await _openLogin(tester, auth);

    await tester.tap(_google);
    await tester.pump();
    expect(auth.signIns, [SignInMethod.google]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Finish signing in in the browser…'), findsOneWidget);
    expect(_enabled(tester, _google), isFalse);
    expect(_enabled(tester, _email), isFalse);

    auth.pendingSignIn!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Use email signs in with the hosted page', (tester) async {
    final auth = FakeAuthRepository();
    await _openLogin(tester, auth);
    await tester.tap(_email);
    await tester.pumpAndSettle();
    expect(auth.signIns, [SignInMethod.email]);
  });

  testWidgets('cancelled: nothing is said', (tester) async {
    final auth = FakeAuthRepository()..signInError = AuthCancelled();
    await _openLogin(tester, auth);
    await tester.tap(_google);
    await tester.pumpAndSettle();
    expect(find.text(signInFailedText), findsNothing);
    expect(find.text(signInNetworkErrorText), findsNothing);
    expect(_enabled(tester, _google), isTrue);
  });

  testWidgets('offline: Couldn\'t reach MuxBus', (tester) async {
    final auth = FakeAuthRepository()..signInError = AuthNetworkError();
    await _openLogin(tester, auth);
    await tester.tap(_google);
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't reach MuxBus. Check your connection."),
      findsOneWidget,
    );
    // A retry is possible.
    expect(_enabled(tester, _google), isTrue);
  });

  testWidgets('a refused account, with the service\'s reason readable', (
    tester,
  ) async {
    final auth =
        FakeAuthRepository()
          ..signInError = AuthCallbackError(
            'access_denied',
            'PreSignUp failed with error not invited',
          );
    await _openLogin(tester, auth);
    await tester.tap(_google);
    await tester.pumpAndSettle();
    expect(
      find.text("That account can't sign in to MuxBus.\nNot invited."),
      findsOneWidget,
    );
  });

  testWidgets('another callback error shows its description', (tester) async {
    final auth =
        FakeAuthRepository()
          ..signInError = AuthCallbackError(
            'invalid_request',
            'the link has expired',
          );
    await _openLogin(tester, auth);
    await tester.tap(_email);
    await tester.pumpAndSettle();
    expect(find.text('The link has expired.'), findsOneWidget);
  });

  testWidgets('not configured: says so and offers no broken buttons', (
    tester,
  ) async {
    await _openLogin(tester, FakeAuthRepository(available: false));
    expect(find.text(signInUnavailableText), findsOneWidget);
    expect(_enabled(tester, _google), isFalse);
    expect(_enabled(tester, _email), isFalse);
  });

  testWidgets('availability unknown (offline): buttons stay on', (
    tester,
  ) async {
    await _openLogin(tester, FakeAuthRepository(available: null));
    expect(find.text(signInUnavailableText), findsNothing);
    expect(_enabled(tester, _google), isTrue);
  });

  testWidgets('Not now goes back', (tester) async {
    await _openLogin(tester, FakeAuthRepository());
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('discover page'), findsOneWidget);
    expect(find.text('Connect with Google'), findsNothing);
  });

  testWidgets('signInErrorText: every kind in plain words', (tester) async {
    expect(signInErrorText(AuthCancelled()), isNull);
    expect(signInErrorText(AuthUnavailable()), signInUnavailableText);
    expect(signInErrorText(AuthNetworkError()), signInNetworkErrorText);
    expect(signInErrorText(AuthStateMismatch()), signInStateMismatchText);
    expect(
      signInErrorText(AuthCallbackError('access_denied', null)),
      signInRefusedText,
    );
    expect(
      signInErrorText(AuthCallbackError('server_error', null)),
      signInFailedText,
    );
    expect(signInErrorText(StateError('x')), signInFailedText);
  });

  testWidgets('fits a 320 dp screen at large text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository()..signInError = AuthNetworkError();
    await _openLogin(tester, auth, textScale: 1.6);
    await tester.ensureVisible(_google);
    await tester.tap(_google);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Connect with Google'), findsOneWidget);
  });
}
