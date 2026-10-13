import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'feed_theme.dart';
import 'markdown_view.dart';
import 'transcript.dart';

/// One transcript item on the feed screen, drawn as the desktop agent pane
/// draws it (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md`): full
/// width blocks in one column, no bubbles. Read-only: nothing here acts on
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FeedSpace.s3,
          vertical: FeedSpace.s0_5,
        ),
        child: switch (item) {
          PromptItem(:final text) => PromptBlock(text: text),
          AssistantTextItem(:final text) => FeedMarkdown(text),
          StreamingTextItem(:final text) => Throttled(
              value: text,
              builder: (text) => FeedMarkdown(text, streaming: true),
            ),
          ThinkingItem(:final text, :final streaming) =>
            ThinkingBlock(text: text, streaming: streaming),
          final ToolCallItem tool =>
            _ToolLine(tool: tool, expanded: expanded, onToggle: onToggle),
          TurnDividerItem(:final durationMs, :final error) =>
            _TurnDivider(durationMs: durationMs, error: error),
          TruncatedItem() => const _Note(text: truncatedText),
          PlainTextItem(:final text) => SelectableText(text, style: feedCode),
        },
      );
}

const truncatedText = 'Output truncated (open on the computer)';
const thinkingText = 'Thinking…';

/// Rebuilds [builder] with [value] at most every [interval], as the desktop
/// throttles a streaming reply's Markdown; the latest value always lands.
class Throttled<T> extends StatefulWidget {
  const Throttled({
    super.key,
    required this.value,
    required this.builder,
    this.interval = const Duration(milliseconds: 90),
  });

  final T value;
  final Widget Function(T value) builder;
  final Duration interval;

  @override
  State<Throttled<T>> createState() => _ThrottledState<T>();
}

class _ThrottledState<T> extends State<Throttled<T>> {
  late T _shown = widget.value;
  late Widget _child = widget.builder(_shown);
  final _since = Stopwatch()..start();
  Timer? _timer;

  @override
  void didUpdateWidget(Throttled<T> old) {
    super.didUpdateWidget(old);
    if (widget.value == _shown) return;
    final wait = widget.interval - _since.elapsed;
    if (wait <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      _show();
    } else {
      _timer ??= Timer(wait, () {
        _timer = null;
        if (mounted) setState(_show);
      });
    }
  }

  void _show() {
    _shown = widget.value;
    _child = widget.builder(_shown);
    _since.reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _child;
}

/// A prompt, as the desktop's user-input block: the theme's colours
/// inverted, a 3 px bar in the user-input colour on the left, the text as
/// typed (wrapped, not Markdown), web links tappable.
class PromptBlock extends StatefulWidget {
  const PromptBlock({super.key, required this.text});
  final String text;

  static const style = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: FeedColors.blockSolid,
  );

  @override
  State<PromptBlock> createState() => _PromptBlockState();
}

class _PromptBlockState extends State<PromptBlock> {
  final _recognizers = <TapGestureRecognizer>[];

  static final _url = RegExp(r'https?://[^\s<>")\]]+');

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _spans(String text) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _url.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      final uri = Uri.tryParse(m[0]!);
      final r = TapGestureRecognizer()
        ..onTap = () {
          if (uri != null) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
        };
      _recognizers.add(r);
      spans.add(TextSpan(
        text: m[0],
        recognizer: r,
        style: const TextStyle(decoration: TextDecoration.underline),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s1, vertical: 3),
      decoration: const BoxDecoration(
        color: FeedColors.text,
        border: Border(left: BorderSide(color: FeedColors.userInput, width: 3)),
      ),
      child: SelectableText.rich(
        TextSpan(children: _spans(widget.text.trimRight())),
        style: PromptBlock.style,
      ),
    );
  }
}

/// Thinking, as the desktop shows it: the full text as Markdown, italic,
/// muted, with a 2 px bar on the left.
class ThinkingBlock extends StatelessWidget {
  const ThinkingBlock({super.key, required this.text, this.streaming = false});
  final String text;
  final bool streaming;

  static final style = feedProse.copyWith(
    fontStyle: FontStyle.italic,
    color: FeedColors.secondary,
  );

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.6,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: FeedSpace.s1),
        padding: const EdgeInsets.only(left: FeedSpace.s2),
        decoration: BoxDecoration(
          color: FeedColors.tint(FeedColors.text, 0.02),
          border: const Border(
            left: BorderSide(color: FeedColors.secondary, width: 2),
          ),
        ),
        child: text.trim().isEmpty
            ? Text(thinkingText, style: style)
            : streaming
                ? Throttled(
                    value: text,
                    builder: (t) => FeedMarkdown(t, streaming: true, style: style),
                  )
                : FeedMarkdown(text, style: style),
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
      ToolState.running => (Icons.more_horiz, FeedColors.warning, 'running'),
      ToolState.done => (Icons.check, FeedColors.success, 'done'),
      ToolState.failed => (Icons.close, FeedColors.error, 'failed'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color, semanticLabel: label),
                const SizedBox(width: 8),
                Text(
                  tool.name,
                  style: feedCode.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tool.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: feedCode.copyWith(color: FeedColors.secondary),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: FeedColors.grey,
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
      margin: const EdgeInsets.only(left: 22, bottom: 4),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: FeedColors.panel,
        border: Border.all(
          color: tool.state == ToolState.failed
              ? FeedColors.error.withValues(alpha: 0.5)
              : FeedColors.border,
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: feedCode.copyWith(
            color: muted ? FeedColors.secondary : FeedColors.text,
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: FeedColors.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: error != null ? FeedColors.errorText : FeedColors.secondary,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: FeedColors.border)),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                error!,
                style: const TextStyle(fontSize: 12, color: FeedColors.errorText),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: FeedColors.secondary,
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
