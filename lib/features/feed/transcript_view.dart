import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'feed_theme.dart';
import 'markdown_view.dart';
import 'messages.dart';
import 'notes_view.dart';
import 'tool_block.dart';
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

  /// For a row that opens (a tool call, a jekt, a reminder): whether it is.
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FeedSpace.s3,
          vertical: FeedSpace.s0_5,
        ),
        child: switch (item) {
          final PromptItem p => PromptBlock(
              text: p.text,
              broadcast: p.broadcast,
              recipients: p.recipients,
              attachments: p.attachments,
            ),
          final ToolCallItem tool when answeredQuestion(tool) != null =>
            _AnsweredQuestion(answeredQuestion(tool)!),
          final ContextItem c => ContextLine(item: c, open: expanded, onToggle: onToggle),
          JektItem(:final jekt) => JektView(jekt: jekt, open: expanded, onToggle: onToggle),
          final NoticeItem n => NoticeDivider(item: n),
          final ErrorItem e => ErrorBlock(item: e),
          final DeliveryItem d => DeliveryCard(item: d, open: expanded, onToggle: onToggle),
          AssistantTextItem(:final text) => FeedMarkdown(text),
          StreamingTextItem(:final text) => Throttled(
              value: text,
              builder: (text) => FeedMarkdown(text, streaming: true),
            ),
          ThinkingItem(:final text, :final streaming) =>
            ThinkingBlock(text: text, streaming: streaming),
          final ToolCallItem tool =>
            ToolBlock(tool: tool, open: expanded, onToggle: onToggle),
          TurnDividerItem(:final durationMs, :final failed) =>
            _TurnDivider(durationMs: durationMs, failed: failed),
          TruncatedItem() => const _Note(text: truncatedText),
          PlainTextItem(:final text) => SelectableText(text, style: feedCode),
        },
      );
}

const truncatedText = truncatedResultText;
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
  const PromptBlock({
    super.key,
    required this.text,
    this.broadcast = false,
    this.recipients,
    this.attachments = const [],
  });
  final String text;

  /// Typed once in Swarm for several agents: a note above the text.
  final bool broadcast;
  final int? recipients;

  /// Attached files, named above the text.
  final List<String> attachments;

  /// The muted note's colour: mixed toward this block's own background, as
  /// the desktop mixes it, so it reads on the inverted surface.
  static final noteColor = Color.lerp(FeedColors.text, FeedColors.blockSolid, 0.55)!;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.broadcast)
            Text(
              '📣 ${broadcastNote(widget.recipients)}',
              style: PromptBlock.style.copyWith(fontSize: 12, color: PromptBlock.noteColor),
            ),
          if (widget.attachments.isNotEmpty)
            Text(
              '📎 ${widget.attachments.join(', ')}',
              style: PromptBlock.style.copyWith(fontSize: 12, color: PromptBlock.noteColor),
            ),
          if (widget.text.trim().isNotEmpty)
            SelectableText.rich(
              TextSpan(children: _spans(widget.text.trimRight())),
              style: PromptBlock.style,
            ),
        ],
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

class _TurnDivider extends StatelessWidget {
  const _TurnDivider({this.durationMs, this.failed = false});
  final int? durationMs;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final ms = durationMs;
    final label = failed
        ? 'Turn ended with an error'
        : (ms == null ? 'Turn ended' : 'Turn ended · ${formatTurnDuration(ms)}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: FeedColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: failed ? FeedColors.errorText : FeedColors.secondary,
              ),
            ),
          ),
          const Expanded(child: Divider(color: FeedColors.border)),
        ],
      ),
    );
  }
}

/// An answered question: the question as Markdown, the answer as the
/// user's input block.
class _AnsweredQuestion extends StatelessWidget {
  const _AnsweredQuestion(this.qa);
  final ({String question, String answer}) qa;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeedMarkdown('❓ ${qa.question}'),
          const SizedBox(height: FeedSpace.s1),
          PromptBlock(text: qa.answer),
        ],
      );
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
