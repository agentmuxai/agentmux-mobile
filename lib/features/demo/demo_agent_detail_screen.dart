import 'package:flutter/material.dart';

import '../../core/demo/demo_data.dart';
import '../../core/models/message.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/adaptive.dart';
import '../../shared/widgets/demo_banner.dart';
import '../../shared/widgets/edge_insets.dart';

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
      appBar: AppBarInset(child: AppBar(
        title: Text(agentId),
      )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inject isn\'t available in demo mode.'),
          ),
        ),
        icon: const Icon(Icons.send),
        label: const Text('Inject'),
        // A quiet button in both modes; its text keeps full contrast.
        backgroundColor: context.palette.surface,
        foregroundColor: context.palette.textPrimary,
      ),
      body: Column(
        children: [
          const DemoBanner(),
          Expanded(
            child: ContentWidth(child: ListView.builder(
              // The top inset is covered by the app bar and the banner.
              padding: insetListPadding(
                context,
                const EdgeInsets.fromLTRB(12, 12, 12, 80),
              ).copyWith(top: 12),
              itemCount: messages.length,
              itemBuilder: (ctx, i) => _DemoMessageTile(message: messages[i]),
            )),
          ),
        ],
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
                    color: context.palette.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _formatTime(message.time),
                style: TextStyle(color: context.palette.textMuted, fontSize: 11),
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
