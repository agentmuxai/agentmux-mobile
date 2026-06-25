import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_provider.dart';
import 'features/agent_detail/agent_detail_screen.dart';
import 'features/agent_list/agent_list_screen.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/login/login_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/usage/usage_screen.dart';
import 'shared/theme/app_theme.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// Cloud-only routes that require authentication.
const _cloudRoutes = ['/usage', '/agents'];

GoRouter _buildRouter(AsyncValue<AuthStatus> authState) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/discover',
    redirect: (context, state) {
      if (authState.isLoading) return null;
      final authed = authState.valueOrNull == AuthStatus.authenticated;
      final loc = state.matchedLocation;

      // Cloud screens require auth.
      if (_cloudRoutes.any((r) => loc.startsWith(r))) {
        if (!authed) return '/login';
      }
      // Authed user landing on /login → send to cloud agents view.
      if (authed && loc == '/login') return '/agents';
      return null;
    },
    routes: [
      // ── Discovery (default, no auth required) ──────────────────────────
      GoRoute(
        path: '/discover',
        builder: (_, __) => const DiscoveryScreen(),
      ),

      // ── Login ─────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Cloud shell (auth-gated via redirect) ──────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, __, child) => _CloudShell(child: child),
        routes: [
          GoRoute(
            path: '/agents',
            builder: (_, __) => const AgentListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) =>
                    AgentDetailScreen(agentId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/usage',
            builder: (_, __) => const UsageScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}

class AgentMuxApp extends ConsumerWidget {
  const AgentMuxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final router = _buildRouter(authState);

    return MaterialApp.router(
      title: 'AgentMux',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// Bottom-nav shell for cloud screens: /agents, /usage, /settings.
class _CloudShell extends StatelessWidget {
  const _CloudShell({required this.child});
  final Widget child;

  static const _tabs = ['/agents', '/usage', '/settings'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexWhere((t) => location.startsWith(t)).clamp(0, 2);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            activeIcon: Icon(Icons.smart_toy),
            label: 'Agents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Usage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
