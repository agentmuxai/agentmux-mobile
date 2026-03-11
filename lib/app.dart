import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/connections/connections_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/terminal/terminal_screen.dart';
import 'features/agent/agent_screen.dart';
import 'features/settings/settings_screen.dart';
import 'shared/theme/app_theme.dart';

final _router = GoRouter(
  initialLocation: '/connections',
  routes: [
    GoRoute(
      path: '/connections',
      builder: (context, state) => const ConnectionsScreen(),
    ),
    GoRoute(
      path: '/connections/add',
      builder: (context, state) => const AddConnectionScreen(),
    ),
    GoRoute(
      path: '/sessions',
      builder: (context, state) => const SessionsScreen(),
    ),
    GoRoute(
      path: '/terminal/:blockId',
      builder: (context, state) => TerminalScreen(
        blockId: state.pathParameters['blockId']!,
      ),
    ),
    GoRoute(
      path: '/agent/:blockId',
      builder: (context, state) => AgentScreen(
        blockId: state.pathParameters['blockId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class AgentMuxApp extends StatelessWidget {
  const AgentMuxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AgentMux',
      theme: AppTheme.dark,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
