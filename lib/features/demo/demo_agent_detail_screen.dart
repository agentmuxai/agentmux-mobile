import 'package:flutter/material.dart';

import '../../core/demo/demo_data.dart';
import '../../core/models/message.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/demo_banner.dart';

/// Static message-feed preview for one demo agent. Mirrors AgentDetailScreen's
/// layout so a reviewer (or a user browsing before connecting a real fleet)
/// sees a faithful preview — Inject is visibly present but disabled, since
/// there's no live agent to inject into during demo mode.
class DemoAgentDetailScreen extends StatelessWidget {
  const DemoAgentDetailScreen({super.key, required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context) {
    final messages = buildDemoMessages(agentId);

    return Scaffold(
      appBar: AppBar(
        title: Text(agentId),
        bottom: const DemoBanner(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inject isn\'t available in demo mode.'),
          ),
        ),
        icon: const Icon(Icons.send),
        label: const Text('Inject'),
        backgroundColor: AppColors.textMuted,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: messages.length,
        itemBuilder: (ctx, i) => _DemoMessageTile(message: messages[i]),
      ),
    );
  }
}

class _DemoMessageTile extends StatelessWidget {
  const _DemoMessageTile({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
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
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _formatTime(message.time),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.message,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
      'urgent' => AppColors.error,
      'high' => AppColors.warning,
      _ => AppColors.textMuted,
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
