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

  Future<void> signIn() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signIn();
      return AuthStatus.authenticated;
    });
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);
