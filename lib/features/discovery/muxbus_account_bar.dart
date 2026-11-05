import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';

const muxbusSignInLabel = 'MuxBus Sign in';

String muxbusSignedInLabel(String? email) =>
    email == null || email.isEmpty
        ? 'MuxBus: signed in'
        : 'MuxBus: signed in as $email';

/// The discovery screen's footer, always on screen below the host list.
/// Signed out it is one big "MuxBus Sign in" button that opens the MuxBus
/// sign-in page; signed in, the same button names the account and opens
/// Settings.
class MuxbusAccountBar extends ConsumerWidget {
  const MuxbusAccountBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(authProvider).valueOrNull == AuthStatus.authenticated;
    final email = signedIn ? ref.watch(accountEmailProvider).valueOrNull : null;

    // On a short screen (a landscape phone; Material's compact height class is
    // under 480) the bar keeps its job but gives the list the room: it took
    // about a fifth of the height. An iPad or an unfolded foldable in landscape
    // is not short and keeps the full bar.
    final compact = MediaQuery.sizeOf(context).height < 480;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: compact
            ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
            : const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: FilledButton.icon(
          key: const ValueKey('muxbus-account-bar'),
          onPressed: () => context.push(signedIn ? '/settings' : '/login'),
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(compact ? 44 : 56),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: compact ? 6 : 12,
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(
            signedIn ? Icons.cloud_done_outlined : Icons.cloud_outlined,
          ),
          label: Text(
            signedIn ? muxbusSignedInLabel(email) : muxbusSignInLabel,
            maxLines: signedIn ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
