import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../shared/theme/app_theme.dart';
import '../injection/injection_sheet.dart';
import 'agent_detail_provider.dart';

class AgentDetailScreen extends ConsumerWidget {
  const AgentDetailScreen({super.key, required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(agentDetailProvider(agentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(agentId),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(agentDetailProvider(agentId).notifier).refresh(agentId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInjectionSheet(context, ref),
        icon: const Icon(Icons.send),
        label: const Text('Inject'),
      ),
      body: messagesAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.palette.primary),
        ),
        error: (e, _) => Center(
          child: Text(e.toString(),
              style: TextStyle(color: context.palette.textSecondary)),
        ),
        data: (messages) => messages.isEmpty
            ? const _EmptyMessages()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: messages.length,
                itemBuilder: (ctx, i) => _MessageTile(message: messages[i]),
              ),
      ),
    );
  }

  void _showInjectionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: InjectionSheet(targetAgent: agentId),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PriorityChip(priority: message.priority),
              const SizedBox(width: 8),
              Text(
                message.fromAgent,
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(message.time),
                style: TextStyle(
                  color: context.palette.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.message,
            style: TextStyle(color: context.palette.textPrimary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${t.month}/${t.day}';
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'urgent' => context.palette.error,
      'high' => context.palette.warning,
      _ => context.palette.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        priority,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          'No messages yet',
          style: TextStyle(color: context.palette.textSecondary),
        ),
      );
}
