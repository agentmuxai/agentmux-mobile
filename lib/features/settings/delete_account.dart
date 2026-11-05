import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_provider.dart';
import '../../core/api/muxbus_client.dart' show DeleteAccountOutcome;
import '../../core/auth/auth_provider.dart';
import '../../shared/theme/app_theme.dart';

const deleteAccountTitle = 'Delete your account?';
const deleteAccountBody =
    'This deletes your AgentMux Cloud account and everything stored in it: '
    'your cloud agents, keys and message history. Your computers keep working '
    'on their own, and signing in again later starts a new, empty account.\n\n'
    "This can't be undone.";
const accountDeletedText = 'Your account was deleted.';
const signedOutText = 'You are signed out.';
const deleteAccountFailedText =
    "We couldn't finish deleting your account. Nothing is lost by trying again.";
const deleteAccountRefusedText =
    "This account can't be deleted from the app. Email privacy@agentmux.ai "
    'and we will delete it for you.';

/// "Delete account" in Settings: asks once, deletes, and ends the session.
/// App Store guideline 5.1.1(v) and Google Play both ask for this in the app.
Future<void> confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final sure = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: context.palette.surface,
          title: Text(
            deleteAccountTitle,
            style: TextStyle(color: context.palette.textPrimary),
          ),
          content: Text(
            deleteAccountBody,
            style: TextStyle(color: context.palette.textSecondary),
          ),
          actions: [
            TextButton(
              key: const ValueKey('delete-account-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('delete-account-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: context.palette.error),
              child: const Text('Delete account'),
            ),
          ],
        ),
  );
  if (sure != true || !context.mounted) return;
  await _delete(context, ref);
}

Future<void> _delete(BuildContext context, WidgetRef ref) async {
  // Settings is replaced when the session ends; these outlive it.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final client = ref.read(muxbusClientProvider);
  final auth = ref.read(authProvider.notifier);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: context.palette.surface,
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(
                  'Deleting your account…',
                  style: TextStyle(color: context.palette.textPrimary),
                ),
              ],
            ),
          ),
        ),
  );
  final outcome = await client.deleteAccount();
  navigator.pop();

  switch (outcome) {
    case DeleteAccountOutcome.deleted:
      await auth.endSessionAfterDeletion();
      messenger.showSnackBar(const SnackBar(content: Text(accountDeletedText)));
    case DeleteAccountOutcome.signedOut:
      // The service no longer knows this session; whether the account is gone
      // is not something to claim.
      await auth.endSessionAfterDeletion();
      messenger.showSnackBar(const SnackBar(content: Text(signedOutText)));
    case DeleteAccountOutcome.refused:
      if (context.mounted) await _tell(context, deleteAccountRefusedText);
    case DeleteAccountOutcome.failed:
      if (!context.mounted) return;
      final again = await _tell(context, deleteAccountFailedText, retry: true);
      if (again && context.mounted) await _delete(context, ref);
  }
}

/// A message with OK, or with Cancel and "Try again" when [retry]; true on retry.
Future<bool> _tell(
  BuildContext context,
  String text, {
  bool retry = false,
}) async {
  final again = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: context.palette.surface,
          content: Text(
            text,
            style: TextStyle(color: context.palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(retry ? 'Cancel' : 'OK'),
            ),
            if (retry)
              FilledButton(
                key: const ValueKey('delete-account-retry'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Try again'),
              ),
          ],
        ),
  );
  return again ?? false;
}
