import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(tokenStorageProvider));
});

// AuthState — simple enum; screens redirect on unauthenticated.
enum AuthStatus { loading, authenticated, unauthenticated }

class AuthNotifier extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    final auth = ref.watch(authRepositoryProvider);
    final ok = await auth.isAuthenticated();
    return ok ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  /// Signs in. The state changes only on success; a failure (including
  /// [AuthCancelled]) is thrown to the caller, the sign-in page, which shows
  /// it. Not passing through a loading state keeps the app's router (rebuilt
  /// on every auth change) from leaving the sign-in page mid-flow.
  Future<void> signIn({SignInMethod method = SignInMethod.email}) async {
    await ref.read(authRepositoryProvider).signIn(method: method);
    state = const AsyncValue.data(AuthStatus.authenticated);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);

/// The signed-in account's email; null when signed out or unknown.
final accountEmailProvider = FutureProvider<String?>((ref) async {
  final status = ref.watch(authProvider).valueOrNull;
  if (status != AuthStatus.authenticated) return null;
  try {
    return await ref.read(authRepositoryProvider).getAccountEmail();
  } catch (_) {
    return null;
  }
});
