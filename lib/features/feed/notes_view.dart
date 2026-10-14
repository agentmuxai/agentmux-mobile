import 'package:flutter/material.dart';

import 'feed_theme.dart';
import 'markdown_view.dart';
import 'messages.dart';
import 'transcript.dart';

/// The rows for what isn't the user's own words
/// (`SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §7).

final _small = feedProse.copyWith(fontSize: 12, color: FeedColors.secondary, height: 1.4);
final _mono = feedCode.copyWith(fontSize: 11.5, color: FeedColors.secondary);

/// A line that opens to more: "▸ summary", "▾ summary" and the body under
/// it (the desktop's `CollapsibleMessage`). [bar] draws a 2 px bar on the
/// left.
class CollapsibleLine extends StatelessWidget {
  const CollapsibleLine({
    super.key,
    required this.summary,
    required this.open,
    required this.body,
    this.onToggle,
    this.bar,
  });
  final Widget summary;
  final bool open;
  final Widget Function() body;
  final VoidCallback? onToggle;
  final Color? bar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: bar == null
          ? null
          : BoxDecoration(border: Border(left: BorderSide(color: bar!, width: 2))),
      padding: EdgeInsets.only(left: bar == null ? 0 : FeedSpace.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 14,
                    height: 18,
                    child: Text(
                      open ? '▾' : '▸',
                      style: const TextStyle(fontSize: 10, color: FeedColors.secondary),
                    ),
                  ),
                  Expanded(child: summary),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: FeedSpace.s1),
              child: body(),
            ),
        ],
      ),
    );
  }
}

/// A box that scrolls inside past about a sixth of the screen, as the
/// desktop caps an opened jekt or reminder.
Widget _capped(BuildContext context, Widget child) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 4),
      padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s2, vertical: 6),
      color: FeedColors.panel,
      child: SingleChildScrollView(child: child),
    );

String contextSummary(ContextItem item) => switch (item.kind) {
      ContextKind.systemReminder => 'System reminder',
      ContextKind.memory => '🧠 Memory reinjected — ${item.globalCount ?? 0} global, '
          '${item.personalCount ?? 0} personal (~${formatTokens(estimateTokens(item.text))} tok, est.)',
      ContextKind.sessionContext => '⓵ Session context',
      ContextKind.continuation => "🔁 AgentMux's record of the earlier session",
      ContextKind.compactSummary => '📋 Agent given a summary of the conversation',
    };

/// Text given to the agent, collapsed to one muted line.
class ContextLine extends StatelessWidget {
  const ContextLine({super.key, required this.item, required this.open, this.onToggle});
  final ContextItem item;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final excerpt = item.kind == ContextKind.compactSummary ? compactExcerpt(item.text) : '';
    if (item.kind == ContextKind.memory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: InkWell(
              onTap: onToggle,
              child: _Pill(contextSummary(item), color: FeedColors.secondary),
            ),
          ),
          if (open) ...[
            const SizedBox(height: FeedSpace.s1),
            _capped(context, SelectableText(item.text, style: _mono)),
          ],
        ],
      );
    }
    return CollapsibleLine(
      open: open,
      onToggle: onToggle,
      summary: Text.rich(
        TextSpan(children: [
          TextSpan(text: contextSummary(item)),
          if (excerpt.isNotEmpty && !open)
            TextSpan(text: '  $excerpt', style: const TextStyle(fontStyle: FontStyle.italic)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _small,
      ),
      body: () => _capped(
        context,
        item.kind == ContextKind.compactSummary || item.kind == ContextKind.continuation
            ? FeedMarkdown(item.text, style: feedProse.copyWith(fontSize: 13))
            : SelectableText(item.text, style: _mono),
      ),
    );
  }
}

/// Another agent's message: "▸ 📥 From X [tier] [delivery]", opening to its
/// body, its marker and the raw message.
class JektView extends StatefulWidget {
  const JektView({super.key, required this.jekt, required this.open, this.onToggle});
  final Jekt jekt;
  final bool open;
  final VoidCallback? onToggle;

  @override
  State<JektView> createState() => _JektViewState();
}

class _JektViewState extends State<JektView> {
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final j = widget.jekt;
    final tierColor = switch (j.tier) {
      'sensitive' => FeedColors.error,
      'info' => FeedColors.secondary,
      _ => FeedColors.accent,
    };
    return CollapsibleLine(
      open: widget.open,
      onToggle: widget.onToggle,
      bar: j.sensitive ? FeedColors.error : FeedColors.accent,
      summary: Wrap(
        spacing: FeedSpace.s1,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '📥 '),
              TextSpan(text: 'From ${j.from}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            style: feedProse.copyWith(fontSize: 13),
          ),
          _Pill('${jektTierIcons[j.tier] ?? ''} ${j.tier}', color: tierColor),
          _Pill('${jektDeliveryIcons[j.delivery] ?? ''} ${j.delivery}', color: FeedColors.secondary),
        ],
      ),
      body: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _capped(context, SelectableText(j.body, style: feedProse.copyWith(fontSize: 13))),
          const SizedBox(height: FeedSpace.s1),
          Text(
            [
              'From: ${j.from}',
              'To: ${j.to}',
              'MSGID: ${j.msgId.isEmpty ? '—' : j.msgId}',
              'Trust: ${j.trust}',
              if (j.fields['SIG'] != null) 'Sig: ${j.fields['SIG']}',
              'Priority: ${j.priority}',
              if (j.sentAt != null) _when(j.sentAt!),
            ].join('  ·  '),
            style: _small.copyWith(fontSize: 11),
          ),
          InkWell(
            onTap: () => setState(() => _raw = !_raw),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${_raw ? '▾' : '▸'} Raw payload', style: _small.copyWith(fontSize: 11)),
            ),
          ),
          if (_raw) _capped(context, SelectableText(j.raw, style: _mono)),
        ],
      ),
    );
  }
}

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: FeedColors.tint(color, 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: _small.copyWith(fontSize: 11, color: color)),
      );
}

Color noticeColor(NoticeTone tone) => switch (tone) {
      NoticeTone.info => FeedColors.secondary,
      NoticeTone.warn => FeedColors.warningText,
      NoticeTone.error => FeedColors.errorText,
    };

/// An AgentMux note: a centred divider with its label, and a detail line.
class NoticeDivider extends StatelessWidget {
  const NoticeDivider({super.key, required this.item});
  final NoticeItem item;

  @override
  Widget build(BuildContext context) {
    final color = noticeColor(item.tone);
    final detail = item.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FeedSpace.s1),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: FeedColors.border)),
              const SizedBox(width: FeedSpace.s2),
              Flexible(
                flex: 4,
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: _small.copyWith(fontSize: 11, color: color),
                ),
              ),
              const SizedBox(width: FeedSpace.s2),
              const Expanded(child: Divider(color: FeedColors.border)),
            ],
          ),
          if (detail != null && detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: _small.copyWith(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

/// The turn's error: "Error" or "HTTP 401" and the message, on a red tint.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.item});
  final ErrorItem item;

  @override
  Widget build(BuildContext context) {
    final code = item.code;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s2, vertical: 6),
      decoration: BoxDecoration(
        color: FeedColors.tint(FeedColors.error, 0.08),
        border: const Border(left: BorderSide(color: FeedColors.error, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code == null ? 'Error' : 'HTTP $code',
            style: feedCode.copyWith(color: FeedColors.errorText, fontWeight: FontWeight.w700),
          ),
          SelectableText(item.message, style: _small.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

/// What AgentMux gave the agent: a title line that opens to one row per
/// item.
class DeliveryCard extends StatelessWidget {
  const DeliveryCard({super.key, required this.item, required this.open, this.onToggle});
  final DeliveryItem item;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = item.entries.fold<int>(0, (n, e) => n + e.tokens);
    return CollapsibleLine(
      open: open,
      onToggle: onToggle,
      summary: Text(
        '📥 ${item.title}${tokens > 0 ? '  ~${formatTokens(tokens)} tok (est.)' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _small,
      ),
      body: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in item.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Text('${e.icon} ', style: _small),
                  Expanded(
                    child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _small.copyWith(color: FeedColors.text)),
                  ),
                  const SizedBox(width: FeedSpace.s1),
                  _Pill(e.chip, color: FeedColors.secondary),
                  if (e.cut) ...[
                    const SizedBox(width: FeedSpace.s1),
                    const _Pill('cut', color: FeedColors.warningText),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An AskUserQuestion that was answered: the question as Markdown, the
/// answer as the user's input block, as the desktop shows it.
({String question, String answer})? answeredQuestion(ToolCallItem tool) {
  if (tool.name != 'AskUserQuestion' || tool.state != ToolState.done) return null;
  final result = tool.result;
  if (result == null) return null;
  final qs = tool.input['questions'];
  final questions = <String>[
    if (qs is List)
      for (final q in qs)
        if (q is Map && q['question'] is String) q['question'] as String,
  ];
  if (questions.isEmpty) return null;
  final pairs = RegExp(r'"([^"]*)"="([^"]*)"').allMatches(result).toList();
  final answer = pairs.isEmpty
      ? result.trim()
      : pairs.map((m) => pairs.length == 1 ? m[2]! : '${m[1]}: ${m[2]}').join('\n');
  return (question: questions.join('\n\n'), answer: answer);
}
