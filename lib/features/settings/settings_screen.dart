import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
      appBar: AppBar(
        title: const Text('Settings'),
        // Explicit back control, shown only for the unauthenticated
        // pre-login entry point (Discovery's app bar pushes here). In that
        // case this is the sole entry in the ShellRoute's nested navigator,
        // so Navigator.canPop is false and neither the AppBar's default
        // back arrow nor iOS's edge-swipe gesture (which key off that same
        // local canPop) appear — even though go_router's own back-button
        // dispatcher happens to still resolve a hardware/system back press
        // to /discover. Don't rely on that ambient, platform-inconsistent
        // behavior. Omitted when authenticated: Settings is then reached as
        // a bottom-nav tab (peer to Agents/Usage, neither of which has a
        // back button either), not a pushed screen.
        leading: isAuthed
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/discover'),
              ),
      ),
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
          _Section(
            title: 'About',
            children: [
              const ListTile(
                title: Text('Version',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: Text(
                  '$_appVersion+$_buildStamp',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined,
                    color: AppColors.textSecondary),
                title: const Text('View a demo fleet',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textMuted),
                onTap: () => context.push('/demo'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: AppColors.textSecondary),
                title: const Text('Privacy Policy',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.open_in_new,
                    color: AppColors.textMuted, size: 16),
                onTap: () => _openUrl('https://agentmux.ai/mobile-privacy'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline,
                    color: AppColors.textSecondary),
                title: const Text('Support',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.open_in_new,
                    color: AppColors.textMuted, size: 16),
                onTap: () => _openUrl('https://agentmux.ai/support'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openUrl(String url) => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

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
