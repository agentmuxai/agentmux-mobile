import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/billing/billing_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'delete_account.dart';

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
    final email = ref.watch(accountEmailProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // Explicit back control. Based on navigation history
        // (context.canPop(), go_router's own router-level back capability),
        // not auth status — an authenticated user can also reach Settings
        // via a push (Discovery's overflow menu), not just the bottom-nav
        // tab, and in that case canPop() is genuinely true. Gating on
        // isAuthed alone (an earlier version of this fix) wrongly hid the
        // button for that case. The `|| !isAuthed` is a defensive fallback
        // for the original pre-auth entry point specifically: there,
        // Settings is the sole entry in the ShellRoute's nested navigator,
        // so Flutter's own Navigator.canPop is false and neither the
        // AppBar's default back arrow nor iOS's edge-swipe gesture (which
        // key off that same local canPop) appear on their own — even though
        // go_router's canPop()/back-dispatcher may or may not agree,
        // depending on shell-navigator internals this sandbox can't fully
        // verify. Omitted only for the genuine bottom-nav-tab case
        // (authenticated, not pushed, nothing to pop): Settings is then a
        // peer to Agents/Usage, neither of which has a back button either.
        leading: (!context.canPop() && isAuthed)
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
              title: 'Account',
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text('Signed in',
                      style: TextStyle(color: context.palette.textPrimary)),
                  subtitle: email == null
                      ? null
                      : Text(
                          email,
                          style: TextStyle(
                              color: context.palette.textSecondary, fontSize: 12),
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    tierAsync.maybeWhen(
                      data: (t) =>
                          t == 'free' ? 'MuxBus · Free tier' : 'MuxBus · Metered',
                      orElse: () => 'MuxBus',
                    ),
                    style: TextStyle(color: context.palette.textPrimary),
                  ),
                  subtitle: Text(
                    tierAsync.maybeWhen(
                      data: (t) => t == 'free'
                          ? '100 cloud injects / month free'
                          : 'Pay-as-you-go · \$0.01 per inject',
                      orElse: () => '',
                    ),
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: context.palette.textMuted),
                  onTap: () => context.go('/usage'),
                ),
                ListTile(
                  title: Text('Sign out',
                      style: TextStyle(color: context.palette.error)),
                  leading: Icon(Icons.logout, color: context.palette.error),
                  onTap: () => _confirmSignOut(context, ref),
                ),
                ListTile(
                  key: const ValueKey('delete-account'),
                  title: Text('Delete account',
                      style: TextStyle(color: context.palette.error)),
                  subtitle: Text(
                    'Removes your cloud account and what it stores',
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 12),
                  ),
                  leading: Icon(Icons.delete_outline,
                      color: context.palette.error),
                  onTap: () => confirmAndDeleteAccount(context, ref),
                ),
              ],
            ),
          ] else ...[
            _Section(
              title: 'MuxBus Cloud',
              children: [
                ListTile(
                  leading: Icon(Icons.cloud_outlined,
                      color: context.palette.textMuted),
                  title: Text('MuxBus Sign in',
                      style: TextStyle(color: context.palette.primary)),
                  subtitle: Text(
                    'See your computers and agents from anywhere',
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 12),
                  ),
                  onTap: () => context.push('/login'),
                ),
              ],
            ),
          ],
          _Section(
            title: 'About',
            children: [
              ListTile(
                title: Text('Version',
                    style: TextStyle(color: context.palette.textSecondary)),
                trailing: Text(
                  '$_appVersion+$_buildStamp',
                  style: TextStyle(color: context.palette.textMuted, fontSize: 13),
                ),
              ),
              ListTile(
                leading: Icon(Icons.visibility_outlined,
                    color: context.palette.textSecondary),
                title: Text('View a demo fleet',
                    style: TextStyle(color: context.palette.textSecondary)),
                trailing: Icon(Icons.chevron_right,
                    color: context.palette.textMuted),
                onTap: () => context.push('/demo'),
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined,
                    color: context.palette.textSecondary),
                title: Text('Privacy Policy',
                    style: TextStyle(color: context.palette.textSecondary)),
                trailing: Icon(Icons.open_in_new,
                    color: context.palette.textMuted, size: 16),
                onTap: () => _openUrl('https://agentmux.ai/mobile-privacy'),
              ),
              ListTile(
                leading: Icon(Icons.help_outline,
                    color: context.palette.textSecondary),
                title: Text('Support',
                    style: TextStyle(color: context.palette.textSecondary)),
                trailing: Icon(Icons.open_in_new,
                    color: context.palette.textMuted, size: 16),
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
        backgroundColor: context.palette.surface,
        title: Text('Sign out?',
            style: TextStyle(color: context.palette.textPrimary)),
        content: Text('You will need to sign in again.',
            style: TextStyle(color: context.palette.textSecondary)),
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
            style: FilledButton.styleFrom(backgroundColor: context.palette.error),
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
              style: TextStyle(
                color: context.palette.textMuted,
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
