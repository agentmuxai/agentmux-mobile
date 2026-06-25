import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/agent.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/status_badge.dart';
import 'agent_list_provider.dart';

class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(agentListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(agentListProvider.notifier).refresh(),
          ),
        ],
      ),
      body: agentsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.read(agentListProvider.notifier).refresh(),
        ),
        data: (agents) => agents.isEmpty
            ? const _EmptyView()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(agentListProvider.notifier).refresh(),
                color: AppColors.primary,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: agents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _AgentCard(agent: agents[i]),
                ),
              ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/agent/${agent.id}'),
        leading: StatusBadge(status: agent.status),
        title: Text(
          agent.id,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          _lastSeenLabel(agent),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        trailing: agent.messagesSent > 0
            ? _MessagesBadge(count: agent.messagesSent)
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

class _MessagesBadge extends StatelessWidget {
  const _MessagesBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '${count}msg',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          'No agents online',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: AppColors.textMuted, size: 40),
              const SizedBox(height: 12),
              Text(message,
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
