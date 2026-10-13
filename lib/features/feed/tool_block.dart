import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_highlight.dart';
import 'feed_theme.dart';
import 'line_diff.dart';
import 'markdown_view.dart';
import 'tool_meta.dart';
import 'transcript.dart';

/// One tool call as the desktop draws it (`components/ToolBlock.tsx`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §6): a header
/// line (status · icon · label · detail · duration · pill) with a 2 px bar
/// on the left in the call's state colour, and, when [open], a preview about
/// 13 lines tall that scrolls inside and can be made taller.
class ToolBlock extends StatefulWidget {
  const ToolBlock({super.key, required this.tool, required this.open, this.onToggle});
  final ToolCallItem tool;
  final bool open;
  final VoidCallback? onToggle;

  @override
  State<ToolBlock> createState() => _ToolBlockState();
}

class _ToolBlockState extends State<ToolBlock> {
  bool _tall = false;

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: toolBarColor(tool.state), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: ToolHeader(tool: tool, open: widget.open),
          ),
          if (widget.open)
            ToolPreview(
              tool: tool,
              tall: _tall,
              onTall: () => setState(() => _tall = !_tall),
            ),
        ],
      ),
    );
  }
}

final _headerStyle = feedCode.copyWith(fontSize: 12.5, height: 1.4);

/// The header line.
class ToolHeader extends StatelessWidget {
  const ToolHeader({super.key, required this.tool, required this.open});
  final ToolCallItem tool;
  final bool open;

  /// Under this width the pill is left out before the detail is.
  static const pillMinWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final kind = toolKind(tool.name);
    final detail = toolDetail(tool);
    final label = toolLabel(tool, detail);
    final color = toolNameColor(kind);
    final range = readRange(tool);
    final ms = tool.durationMs;
    final pill = toolPill(tool);
    final muted = _headerStyle.copyWith(color: FeedColors.secondary);
    return LayoutBuilder(builder: (context, c) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s1, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text(
                toolGlyph(tool),
                textAlign: TextAlign.center,
                style: muted.copyWith(fontSize: 11, color: toolBarColor(tool.state)),
                semanticsLabel: tool.state.name,
              ),
            ),
            const SizedBox(width: FeedSpace.s1),
            Text(toolIcon(kind), style: _headerStyle.copyWith(fontSize: 11)),
            const SizedBox(width: FeedSpace.s1),
            if (label != null) ...[
              Flexible(
                flex: 0,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _headerStyle.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: FeedSpace.s1_5),
            ],
            Expanded(child: _detail(kind, detail, color)),
            if (range != null) ...[
              const SizedBox(width: FeedSpace.s1),
              Text(range, style: muted),
            ],
            if (ms != null) ...[
              const SizedBox(width: FeedSpace.s1),
              Text(formatToolDuration(ms), style: muted),
            ],
            if (pill != null && c.maxWidth >= pillMinWidth) ...[
              const SizedBox(width: FeedSpace.s1),
              _Pill(pill),
            ],
          ],
        ),
      );
    });
  }

  Widget _detail(ToolKind kind, String detail, Color color) {
    if (detail.isEmpty) return const SizedBox.shrink();
    final style = _headerStyle.copyWith(color: color);
    if (toolDetailIsPath(tool)) return LeftEllipsisText(detail, style: style);
    if (kind == ToolKind.bash) {
      final span = CodeHighlighter.highlightSync(detail, 'bash', _headerStyle);
      if (span != null) {
        return Text.rich(span, maxLines: 1, overflow: TextOverflow.ellipsis, style: _headerStyle);
      }
    }
    return Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.pill);
  final ToolPill pill;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: FeedColors.tint(pill.color, 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          pill.label,
          style: feedProse.copyWith(fontSize: 11, color: pill.color, height: 1.5),
        ),
      );
}

/// One line of text cut from the left when it doesn't fit ("…/lib/app.dart"),
/// so a path's file name stays in view.
class LeftEllipsisText extends StatelessWidget {
  const LeftEllipsisText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final shown = fitFromLeft(
        text,
        style,
        c.maxWidth,
        MediaQuery.textScalerOf(context),
      );
      return Text(shown, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);
    });
  }
}

/// The longest end of [text] that fits [width] with a leading "…".
String fitFromLeft(String text, TextStyle style, double width, TextScaler scaler) {
  bool fits(String s) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final ok = p.width <= width;
    p.dispose();
    return ok;
  }

  if (!width.isFinite || fits(text)) return text;
  var lo = 1;
  var hi = text.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (fits('…${text.substring(mid)}')) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return '…${text.substring(lo)}';
}

// ─── Previews ────────────────────────────────────────────────────────────────

/// Previews keep this many lines: logs their end, files and diffs their start.
const maxPreviewLines = 1000;

const truncatedResultText = 'Output truncated (open on the computer)';
const truncatedInputText = 'Too large to show here (open on the computer)';
const runningText = '⏳ Thinking…';

/// About 13 lines of preview text before it scrolls, as the desktop's third
/// of half a window.
const previewLines = 13;

const _previewStyle = feedCode;
final _mutedStyle = feedCode.copyWith(color: FeedColors.secondary);

/// A tool call's preview, by tool.
class ToolPreview extends StatelessWidget {
  const ToolPreview({super.key, required this.tool, this.tall = false, this.onTall});
  final ToolCallItem tool;
  final bool tall;
  final VoidCallback? onTall;

  @override
  Widget build(BuildContext context) {
    final p = buildPreview(tool);
    final lineHeight = (_previewStyle.fontSize ?? 12) * (_previewStyle.height ?? 1.45);
    final maxHeight = lineHeight * previewLines * (tall ? 3 : 1) + 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(FeedSpace.s3, 0, 0, FeedSpace.s1),
          padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s2, vertical: 6),
          constraints: BoxConstraints(maxHeight: maxHeight),
          color: FeedColors.panel,
          child: SingleChildScrollView(
            // A log follows its latest output; a document opens at its top.
            reverse: p.follow,
            child: p.child,
          ),
        ),
        if (p.lines > previewLines && onTall != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: onTall,
              child: Text(tall ? 'Shorter' : 'Taller'),
            ),
          ),
      ],
    );
  }
}

/// What a preview shows: the widget, about how many lines it is, and
/// whether it starts at its end.
class Preview {
  const Preview(this.child, {this.lines = 1, this.follow = false});
  final Widget child;
  final int lines;
  final bool follow;
}

Preview _note(String text, {Color color = FeedColors.secondary}) =>
    Preview(SelectableText(text, style: _previewStyle.copyWith(color: color)));

Preview buildPreview(ToolCallItem tool) {
  final kind = toolKind(tool.name);
  // Edit and Write show their input, which is there from the start.
  if (kind == ToolKind.edit || kind == ToolKind.write) {
    if (tool.inputTruncatedBytes != null) return _note(truncatedInputText);
    return kind == ToolKind.edit ? _editPreview(tool) : _writePreview(tool);
  }
  if (tool.truncatedBytes != null) return _note(truncatedResultText);
  final result = tool.result;
  if (result == null) {
    return switch (tool.state) {
      ToolState.running => _note(
          tool.name == 'AskUserQuestion' ? '❓ Waiting for an answer on the computer' : runningText,
        ),
      ToolState.cancelled => _note('Cancelled'),
      _ => _note('No output'),
    };
  }
  if (tool.state == ToolState.denied) return _note('Denied: $result');
  if (tool.state == ToolState.failed && kind != ToolKind.bash) {
    return _textPreview(result, color: FeedColors.errorText, follow: false);
  }
  return switch (kind) {
    ToolKind.bash => _bashPreview(tool, result),
    ToolKind.read => _readPreview(tool, result),
    ToolKind.glob => _textPreview(globFiles(result).join('\n'), follow: false),
    ToolKind.grep => _textPreview(result, follow: false),
    ToolKind.agent || ToolKind.webFetch => _markdownPreview(result),
    ToolKind.webSearch => _webSearchPreview(result),
    _ => _genericPreview(result),
  };
}

/// Keeps [maxPreviewLines] of [lines] from [fromEnd] or the start, with a
/// marker for the rest.
(List<String>, int) capLines(List<String> lines, {required bool fromEnd}) {
  if (lines.length <= maxPreviewLines) return (lines, 0);
  final hidden = lines.length - maxPreviewLines;
  return (
    fromEnd ? lines.sublist(hidden) : lines.sublist(0, maxPreviewLines),
    hidden,
  );
}

Widget _hiddenMarker(int n, {required bool earlier}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '… $n ${earlier ? 'earlier' : 'more'} ${n == 1 ? 'line' : 'lines'} hidden',
        style: _mutedStyle.copyWith(fontStyle: FontStyle.italic, fontSize: 11),
      ),
    );

Preview _textPreview(String text, {Color? color, bool follow = true}) {
  final (lines, hidden) = capLines(text.trimRight().split('\n'), fromEnd: follow);
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hidden > 0 && follow) _hiddenMarker(hidden, earlier: true),
        SelectableText(
          lines.join('\n'),
          style: _previewStyle.copyWith(color: color),
        ),
        if (hidden > 0 && !follow) _hiddenMarker(hidden, earlier: false),
      ],
    ),
    lines: lines.length,
    follow: follow,
  );
}

Preview _bashPreview(ToolCallItem tool, String result) {
  final f = tool.facts;
  final exit = bashExit(f.stdout ?? result);
  final out = (exit?.body ?? f.stdout ?? result).trimRight();
  final err = (f.stdout != null ? f.stderr ?? '' : '').trimRight();
  final (outLines, hidden) = capLines(out.isEmpty ? const [] : out.split('\n'), fromEnd: true);
  final errLines = err.isEmpty ? const <String>[] : err.split('\n');
  final failed = exit != null ? exit.code != 0 : tool.state == ToolState.failed;
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hidden > 0) _hiddenMarker(hidden, earlier: true),
        if (outLines.isNotEmpty)
          SelectableText(
            outLines.join('\n'),
            style: _previewStyle.copyWith(
              color: tool.state == ToolState.failed && exit == null ? FeedColors.errorText : null,
            ),
          ),
        if (errLines.isNotEmpty)
          SelectableText(
            errLines.join('\n'),
            style: _previewStyle.copyWith(color: FeedColors.errorText),
          ),
        if (outLines.isEmpty && errLines.isEmpty) Text('No output', style: _mutedStyle),
        if (f.interrupted) Text('Interrupted', style: _mutedStyle),
        if (failed && exit != null)
          Text(
            'Exit code: ${exit.code}',
            style: _previewStyle.copyWith(color: FeedColors.errorText),
          ),
      ],
    ),
    lines: outLines.length + errLines.length + 1,
    follow: true,
  );
}

/// The file line over a file preview: the path, and what is known about it.
Widget _fileLine(String path, [String? extra]) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        extra == null ? path : '$path · $extra',
        style: _mutedStyle.copyWith(fontSize: 11),
      ),
    );

String _path(ToolCallItem tool) {
  for (final k in const ['file_path', 'notebook_path', 'path']) {
    final v = tool.input[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return '';
}

bool _isMarkdown(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.md') || p.endsWith('.markdown') || p.endsWith('.mdx');
}

/// Code that scrolls sideways rather than wrapping.
Widget _sideways(Widget child) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );

Preview _editPreview(ToolCallItem tool) {
  final path = _path(tool);
  final input = tool.input;
  final hunks = <(String, String)>[];
  final edits = input['edits'];
  if (edits is List) {
    for (final e in edits) {
      if (e is Map) hunks.add((_s(e['old_string']), _s(e['new_string'])));
    }
  } else if (input.containsKey('old_string') || input.containsKey('new_string')) {
    hunks.add((_s(input['old_string']), _s(input['new_string'])));
  } else if (input['new_source'] is String) {
    hunks.add(('', input['new_source'] as String));
  }
  final language = CodeHighlighter.languageForPath(path);
  final rows = <Widget>[];
  var count = 0;
  var hidden = 0;
  for (var h = 0; h < hunks.length; h++) {
    if (h > 0) rows.add(Text('⋯', style: _mutedStyle));
    for (final line in lineDiff(hunks[h].$1, hunks[h].$2)) {
      if (count >= maxPreviewLines) {
        hidden++;
        continue;
      }
      count++;
      rows.add(DiffRow(line: line, language: language));
    }
  }
  final failed = tool.state == ToolState.failed && tool.result != null;
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fileLine(path),
        if (failed)
          SelectableText(
            tool.result!,
            style: _previewStyle.copyWith(color: FeedColors.errorText),
          ),
        _sideways(IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        )),
        if (hidden > 0) _hiddenMarker(hidden, earlier: false),
      ],
    ),
    lines: count + 1,
  );
}

String _s(Object? v) => v is String ? v : '';

/// One diff line: a marker column, then the line highlighted by the file's
/// language, on a green or red tint.
class DiffRow extends StatelessWidget {
  const DiffRow({super.key, required this.line, this.language});
  final DiffLine line;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final (marker, color) = switch (line.op) {
      DiffOp.added => ('+', FeedColors.successText),
      DiffOp.removed => ('−', FeedColors.errorText),
      DiffOp.same => (' ', null),
    };
    final span = CodeHighlighter.highlightSync(line.text, language, _previewStyle);
    return Container(
      color: color == null ? null : FeedColors.tint(color, 0.15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: _previewStyle.copyWith(color: color ?? FeedColors.secondary),
            ),
          ),
          Text.rich(
            span ?? TextSpan(text: line.text),
            style: _previewStyle,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

Preview _writePreview(ToolCallItem tool) {
  final path = _path(tool);
  final content = _s(tool.input['content']);
  final size = formatBytes(utf8.encode(content).length);
  final failed = tool.state == ToolState.failed && tool.result != null;
  final (lines, hidden) = capLines(content.split('\n'), fromEnd: false);
  final shown = lines.join('\n');
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fileLine(path, size),
        if (failed)
          SelectableText(
            tool.result!,
            style: _previewStyle.copyWith(color: FeedColors.errorText),
          ),
        if (_isMarkdown(path))
          FeedMarkdown(shown, style: feedProse.copyWith(fontSize: 13))
        else
          _sideways(HighlightedCode(
            code: shown,
            language: CodeHighlighter.languageForPath(path),
          )),
        if (hidden > 0) _hiddenMarker(hidden, earlier: false),
      ],
    ),
    lines: lines.length + 1,
  );
}

final _reminder = RegExp(r'\n*<system-reminder>[\s\S]*?</system-reminder>\s*');
final _gutter = RegExp(r'^\s*(\d+)(?:\t|→|$)(.*)$');

/// Claude Code's reminders inside a tool result, which aren't the file.
/// Only trailing newlines go with them: a file's last line may be empty
/// but for its gutter's tab.
String stripReminders(String text) =>
    text.replaceAll(_reminder, '\n').replaceFirst(RegExp(r'\n+$'), '');

Preview _readPreview(ToolCallItem tool, String result) {
  final path = _path(tool);
  final range = readRange(tool);
  if (tool.facts.unchanged) return _note(stripReminders(result));
  final raw = stripReminders(result).split('\n');
  final numbers = <String>[];
  final code = <String>[];
  for (final l in raw) {
    final m = _gutter.firstMatch(l);
    if (m == null) {
      numbers.add('');
      code.add(l);
    } else {
      numbers.add(m[1]!);
      code.add(m[2]!);
    }
  }
  final gutter = numbers.where((n) => n.isNotEmpty).length >= raw.length ~/ 2;
  final (lines, hidden) = capLines(gutter ? code : raw, fromEnd: false);
  final shown = lines.join('\n');
  final Widget body;
  if (_isMarkdown(path)) {
    body = FeedMarkdown(shown, style: feedProse.copyWith(fontSize: 13));
  } else {
    final highlighted = HighlightedCode(
      code: shown,
      language: CodeHighlighter.languageForPath(path),
    );
    body = gutter
        ? _sideways(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                numbers.take(lines.length).join('\n'),
                textAlign: TextAlign.right,
                style: _mutedStyle.copyWith(color: FeedColors.grey),
              ),
              const SizedBox(width: FeedSpace.s2),
              highlighted,
            ],
          ))
        : _sideways(highlighted);
  }
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fileLine(path, range),
        body,
        if (hidden > 0) _hiddenMarker(hidden, earlier: false),
      ],
    ),
    lines: lines.length + 1,
  );
}

Preview _markdownPreview(String result) {
  final text = stripReminders(result);
  return Preview(
    FeedMarkdown(text, style: feedProse.copyWith(fontSize: 13)),
    lines: '\n'.allMatches(text).length + 1,
  );
}

Preview _webSearchPreview(String result) {
  final links = webSearchLinks(result);
  final text = result
      .replaceAll(RegExp(r'^Links: \[.*\]\s*$', multiLine: true), '')
      .replaceFirst(RegExp(r'^Web search results for query: .*$', multiLine: true), '')
      .trim();
  return Preview(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in links)
          InkWell(
            onTap: () {
              final uri = Uri.tryParse(l.url);
              if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '↗ ${l.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: feedProse.copyWith(fontSize: 13, color: FeedColors.link),
              ),
            ),
          ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: FeedSpace.s1),
          FeedMarkdown(text, style: feedProse.copyWith(fontSize: 13)),
        ],
      ],
    ),
    lines: links.length + '\n'.allMatches(text).length + 1,
  );
}

/// Anything else: one line as text, several in a monospace box, JSON as a
/// one-line summary that opens.
Preview _genericPreview(String result) {
  final text = stripReminders(result);
  final trimmed = text.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final value = jsonDecode(trimmed);
      if (value is Map || value is List) return Preview(JsonSummary(value: value), lines: 1);
    } on FormatException {
      // Not JSON after all: shown as text below.
    }
  }
  if (!trimmed.contains('\n')) {
    return Preview(SelectableText(trimmed, style: feedProse.copyWith(fontSize: 13)));
  }
  return _textPreview(text);
}

/// JSON as "{3 keys}" or "[12 items]", tapped open to the whole of it.
class JsonSummary extends StatefulWidget {
  const JsonSummary({super.key, required this.value});
  final Object value;

  @override
  State<JsonSummary> createState() => _JsonSummaryState();
}

class _JsonSummaryState extends State<JsonSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final summary = v is Map
        ? '{${v.length} ${v.length == 1 ? 'key' : 'keys'}}'
        : '[${(v as List).length} ${v.length == 1 ? 'item' : 'items'}]';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Text('${_open ? '▾' : '▸'} $summary', style: _mutedStyle),
        ),
        if (_open)
          HighlightedCode(
            code: const JsonEncoder.withIndent('  ').convert(v),
            language: 'json',
          ),
      ],
    );
  }
}
