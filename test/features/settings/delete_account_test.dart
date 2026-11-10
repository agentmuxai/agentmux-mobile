import 'package:agentmux_mobile/core/api/api_provider.dart';
import 'package:agentmux_mobile/core/api/muxbus_client.dart';
import 'package:agentmux_mobile/core/auth/auth_provider.dart';
import 'package:agentmux_mobile/features/settings/delete_account.dart';
import 'package:agentmux_mobile/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_fakes.dart';

Future<FakeAuthRepository> _open(
  WidgetTester tester,
  Map<String, FakeAnswer> routes, {
  bool signedIn = true,
}) async {
  final auth = FakeAuthRepository(
    signedIn: signedIn,
    email: 'person@example.test',
  );
  final client = MuxbusClient(auth, httpClientAdapter: RouteAdapter(routes));
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/discover',
        builder: (_, __) => const Scaffold(body: Text('discover page')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        muxbusClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

final _delete = find.byKey(const ValueKey('delete-account'));
final _confirm = find.byKey(const ValueKey('delete-account-confirm'));

Future<void> _deleteAndConfirm(WidgetTester tester) async {
  await tester.tap(_delete);
  await tester.pumpAndSettle();
  await tester.tap(_confirm);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed in: an Account section with Delete account', (
    tester,
  ) async {
    await _open(tester, {});
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(_delete, findsOneWidget);
  });

  testWidgets('signed out: no Delete account', (tester) async {
    await _open(tester, {}, signedIn: false);
    expect(_delete, findsNothing);
  });

  testWidgets('Cancel deletes nothing', (tester) async {
    final auth = await _open(tester, {'/api/account': const FakeAnswer(200)});
    await tester.tap(_delete);
    await tester.pumpAndSettle();
    expect(find.text(deleteAccountTitle), findsOneWidget);
    // Apple keeps its own link to the app; the person is told how to drop it.
    expect(find.textContaining('Sign in with Apple'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-account-cancel')));
    await tester.pumpAndSettle();
    expect(auth.sessionsCleared, 0);
    expect(find.text(deleteAccountTitle), findsNothing);
  });

  testWidgets('confirmed: the account is deleted and the session ends', (
    tester,
  ) async {
    final auth = await _open(tester, {
      '/api/account': const FakeAnswer(200, {'status': 'deleted'}),
    });
    await _deleteAndConfirm(tester);
    expect(auth.sessionsCleared, 1);
    expect(find.text(accountDeletedText), findsOneWidget);
    expect(_delete, findsNothing);
  });

  testWidgets('a 401 ends the session without saying the account was deleted', (
    tester,
  ) async {
    final auth = await _open(tester, {
      '/api/account': const FakeAnswer(401, {'error': 'Unauthorized'}),
    });
    await _deleteAndConfirm(tester);
    expect(auth.sessionsCleared, 1);
    expect(find.text(signedOutText), findsOneWidget);
    expect(find.text(accountDeletedText), findsNothing);
  });

  testWidgets('a failure offers Try again and keeps the session', (
    tester,
  ) async {
    final auth = await _open(tester, {
      '/api/account': const FakeAnswer(500, {
        'error': 'deletion_failed',
        'retryable': true,
      }),
    });
    await _deleteAndConfirm(tester);
    expect(find.text(deleteAccountFailedText), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-account-retry')), findsOneWidget);
    expect(auth.sessionsCleared, 0);
  });

  testWidgets('a refusal says to email privacy@agentmux.ai', (tester) async {
    final auth = await _open(tester, {
      '/api/account': const FakeAnswer(403, {'error': 'forbidden'}),
    });
    await _deleteAndConfirm(tester);
    expect(find.text(deleteAccountRefusedText), findsOneWidget);
    expect(auth.sessionsCleared, 0);
  });
}
