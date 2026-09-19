import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_provider.dart';
import 'core/discovery/models/lan_instance.dart';
import 'features/agent_detail/agent_detail_screen.dart';
import 'features/agent_list/agent_list_screen.dart';
import 'features/debug/debug_log_screen.dart';
import 'features/demo/demo_agent_detail_screen.dart';
import 'features/demo/demo_fleet_screen.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/lan_agent/lan_agent_screen.dart';
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

      // ── Debug log (no auth required) ────────────────────────────────────
      GoRoute(
        path: '/debug-log',
        builder: (_, __) => const DebugLogScreen(),
      ),

      // ── Demo mode: static sample data, no network call, no auth ────────
      // See docs/specs/APP_STORE_SUBMISSION_READINESS.md — this is the
      // reviewer-testability path for anyone without a LAN instance or a
      // real Cognito account.
      GoRoute(
        path: '/demo',
        builder: (_, __) => const DemoFleetScreen(),
      ),
      GoRoute(
        path: '/demo/agent/:id',
        builder: (_, state) =>
            DemoAgentDetailScreen(agentId: state.pathParameters['id']!),
      ),

      // ── LAN agent detail (no auth required) ───────────────────────────
      GoRoute(
        path: '/instance/:addr/agent/:name',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null ||
              extra['instance'] is! LanInstance ||
              extra['agent'] is! LanAgent) {
            return const DiscoveryScreen();
          }
          return LanAgentScreen(
            instance: extra['instance'] as LanInstance,
            agent: extra['agent'] as LanAgent,
          );
        },
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
class _CloudShell extends ConsumerWidget {
  const _CloudShell({required this.child});
  final Widget child;

  static const _tabs = ['/agents', '/usage', '/settings'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexWhere((t) => location.startsWith(t)).clamp(0, 2);
    final authState = ref.watch(authProvider);
    final isAuthed = authState.valueOrNull == AuthStatus.authenticated;

    // Only Settings is actually usable unauthenticated — Agents/Usage are
    // both auth-gated by the router's own redirect and would just bounce
    // straight to /login with no explanation if tapped. Showing all three
    // tabs as if they were live options is misleading in that state (a real
    // finding from Codex/ReAgent review on #28: an unauthenticated user
    // reaching Settings via Discovery's new menu item could tap Agents/Usage
    // and get silently redirected). Settings' own AppBar already has an
    // explicit back button for this case, so dropping the tab bar entirely
    // isn't a dead end.
    if (!isAuthed) {
      return Scaffold(body: child);
    }

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
