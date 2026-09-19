import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_data.dart';
import '../../core/models/agent.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/demo_banner.dart';
import '../../shared/widgets/status_badge.dart';

/// A static, no-network preview of what the agent list looks like with a
/// real fleet connected. Reachable without login or a LAN instance — see
/// docs/specs/APP_STORE_SUBMISSION_READINESS.md for why this screen exists.
class DemoFleetScreen extends StatelessWidget {
  const DemoFleetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final agents = buildDemoAgents();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Fleet'),
        bottom: const DemoBanner(),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: agents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _DemoAgentCard(agent: agents[i]),
      ),
    );
  }
}

class _DemoAgentCard extends StatelessWidget {
  const _DemoAgentCard({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/demo/agent/${agent.id}'),
        leading: StatusBadge(status: agent.status),
        title: Text(agent.id, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          _lastSeenLabel(agent),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        trailing: agent.messagesSent > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${agent.messagesSent}msg',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              )
            : null,
      ),
    );
  }

  String _lastSeenLabel(Agent agent) {
    final ago = agent.lastSeenAgo;
    if (ago.inSeconds < 60) return 'Active now';
    if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
    if (ago.inHours < 24) return '${ago.inHours}h ago';
    return '${ago.inDays}d ago';
  }
}
