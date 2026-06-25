import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_provider.dart';
import 'features/agent_detail/agent_detail_screen.dart';
import 'features/agent_list/agent_list_screen.dart';
import 'features/login/login_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/usage/usage_screen.dart';
import 'shared/theme/app_theme.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter _buildRouter(AsyncValue<AuthStatus> authState) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/agents',
    redirect: (context, state) {
      final loading = authState.isLoading;
      if (loading) return null;
      final authed = authState.valueOrNull == AuthStatus.authenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!authed && !onLogin) return '/login';
      if (authed && onLogin) return '/agents';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, __, child) => _ScaffoldShell(child: child),
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

// Bottom-nav shell shared by /agents, /usage, /settings.
class _ScaffoldShell extends StatelessWidget {
  const _ScaffoldShell({required this.child});
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
