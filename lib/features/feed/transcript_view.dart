import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import 'transcript.dart';

/// One transcript item on the feed screen. Read-only: nothing here acts on
/// the agent.
class TranscriptItemView extends StatelessWidget {
  const TranscriptItemView({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final TranscriptItem item;

  /// For a tool call: whether its result is shown.
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => switch (item) {
        PromptItem(:final text) => _PromptBubble(text: text),
        // Markdown source, shown as text: the app has no Markdown renderer.
        AssistantTextItem(:final text) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        final ToolCallItem tool =>
          _ToolLine(tool: tool, expanded: expanded, onToggle: onToggle),
        TurnDividerItem(:final durationMs, :final error) =>
          _TurnDivider(durationMs: durationMs, error: error),
        TruncatedItem() => const _Note(text: truncatedText),
        PlainTextItem(:final text) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
      };
}

const truncatedText = 'Output truncated (open on the computer)';

class _PromptBubble extends StatelessWidget {
  const _PromptBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(48, 8, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _ToolLine extends StatelessWidget {
  const _ToolLine({required this.tool, required this.expanded, this.onToggle});
  final ToolCallItem tool;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (tool.state) {
      ToolState.running => (Icons.more_horiz, AppColors.warning, 'running'),
      ToolState.done => (Icons.check, AppColors.success, 'done'),
      ToolState.failed => (Icons.close, AppColors.error, 'failed'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color, semanticLabel: label),
                const SizedBox(width: 8),
                Text(
                  tool.name,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tool.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (expanded) _ToolResult(tool: tool),
      ],
    );
  }
}

class _ToolResult extends StatelessWidget {
  const _ToolResult({required this.tool});
  final ToolCallItem tool;

  @override
  Widget build(BuildContext context) {
    final result = tool.result;
    final String text;
    var muted = false;
    if (tool.truncatedBytes != null) {
      text = truncatedText;
      muted = true;
    } else if (tool.state == ToolState.running) {
      text = 'Running…';
      muted = true;
    } else if (result == null || result.isEmpty) {
      text = 'No output';
      muted = true;
    } else {
      text = result;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(38, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: tool.state == ToolState.failed
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: muted ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _TurnDivider extends StatelessWidget {
  const _TurnDivider({this.durationMs, this.error});
  final int? durationMs;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ms = durationMs;
    final label = error != null
        ? 'Turn ended with an error'
        : (ms == null ? 'Turn ended' : 'Turn ended · ${formatTurnDuration(ms)}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: error != null ? AppColors.error : AppColors.textMuted,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                error!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// `4.2s`, `38s`, `3m 05s`, `1h 02m`.
String formatTurnDuration(int ms) {
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final s = ms ~/ 1000;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
}
