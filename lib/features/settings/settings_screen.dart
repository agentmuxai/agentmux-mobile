import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/billing/billing_provider.dart';
import '../../shared/theme/app_theme.dart';

// Build-time stamp injected by CI or --dart-define.
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
const _buildStamp = String.fromEnvironment('BUILD_STAMP', defaultValue: 'dev');

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isAuthed = authState.valueOrNull == AuthStatus.authenticated;
    final tierAsync = ref.watch(billingTierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // MuxBus cloud section — only when signed in.
          if (isAuthed) ...[
            _Section(
              title: 'MuxBus Cloud',
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    tierAsync.maybeWhen(
                      data: (t) =>
                          t == 'free' ? 'MuxBus · Free tier' : 'MuxBus · Metered',
                      orElse: () => 'MuxBus',
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    tierAsync.maybeWhen(
                      data: (t) => t == 'free'
                          ? '100 cloud injects / month free'
                          : 'Pay-as-you-go · \$0.01 per inject',
                      orElse: () => '',
                    ),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textMuted),
                  onTap: () => context.go('/usage'),
                ),
                ListTile(
                  title: const Text('Sign out',
                      style: TextStyle(color: AppColors.error)),
                  leading: const Icon(Icons.logout, color: AppColors.error),
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ],
            ),
          ] else ...[
            _Section(
              title: 'MuxBus Cloud',
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined,
                      color: AppColors.textMuted),
                  title: const Text('Connect to MuxBus →',
                      style: TextStyle(color: AppColors.primary)),
                  subtitle: const Text(
                    'Remote access to agents anywhere',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  onTap: () => context.push('/login'),
                ),
              ],
            ),
          ],
          const _Section(
            title: 'About',
            children: [
              ListTile(
                title: Text('Version',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: Text(
                  '$_appVersion+$_buildStamp',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign out?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('You will need to sign in again.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(authProvider.notifier).signOut();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
          const Divider(height: 1),
          const SizedBox(height: 8),
        ],
      );
}
