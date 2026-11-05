import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';
import 'injection_provider.dart';

class InjectionSheet extends ConsumerStatefulWidget {
  const InjectionSheet({super.key, required this.targetAgent});
  final String targetAgent;

  @override
  ConsumerState<InjectionSheet> createState() => _InjectionSheetState();
}

class _InjectionSheetState extends ConsumerState<InjectionSheet> {
  final _controller = TextEditingController();
  static const _priorities = ['normal', 'urgent'];
  static const _priorityLabels = {'normal': 'Normal', 'urgent': 'Urgent'};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(injectionProvider(widget.targetAgent));
    final notifier = ref.read(injectionProvider(widget.targetAgent).notifier);

    // Close sheet on successful send.
    ref.listen(injectionProvider(widget.targetAgent), (prev, next) {
      if (next.sent != null && prev?.sent == null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Injection sent')),
        );
      }
      // Show quota dialog when MuxBus free tier is exhausted.
      if (next.quotaExceeded && !(prev?.quotaExceeded ?? false)) {
        _showQuotaDialog(context);
      }
    });

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Inject into ${widget.targetAgent}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: context.palette.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            autofocus: true,
            style: TextStyle(color: context.palette.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Type your message…',
            ),
            onChanged: notifier.setMessage,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Priority',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
              const SizedBox(width: 12),
              ..._priorities.map((p) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_priorityLabels[p]!),
                      selected: state.priority == p,
                      onSelected: (_) => notifier.setPriority(p),
                      selectedColor: context.palette.primary.withAlpha(40),
                      labelStyle: TextStyle(
                        color: state.priority == p
                            ? context.palette.primary
                            : context.palette.textSecondary,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: state.priority == p
                            ? context.palette.primary
                            : context.palette.border,
                      ),
                    ),
                  )),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(state.error!,
                style: TextStyle(color: context.palette.error, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: state.submitting || state.message.trim().isEmpty
                ? null
                : notifier.submit,
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: state.submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send injection'),
          ),
        ],
      ),
    );
  }

  void _showQuotaDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: Text(
          'MuxBus free tier reached',
          style: TextStyle(color: context.palette.textPrimary),
        ),
        content: Text(
          'You\'ve used your 100 free cloud injects this month.\n\n'
          'Upgrade to pay-as-you-go (\$0.01/inject) at cloud.agentmux.ai/billing, '
          'or send messages directly over LAN for free.',
          style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // close sheet too
              context.push('/settings');
            },
            child: const Text('View billing'),
          ),
        ],
      ),
    );
  }
}
