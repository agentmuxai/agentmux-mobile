import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';

/// Reads billing_tier from the stored Cognito id_token JWT claim.
/// Returns 'free' if unauthenticated or claim is absent.
/// No API call — the pre-token Lambda embeds this at token issue time.
final billingTierProvider = FutureProvider<String>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState.valueOrNull != AuthStatus.authenticated) return 'free';
  final storage = ref.read(tokenStorageProvider);
  return await storage.readBillingTier() ?? 'free';
});
