import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'code_highlight.dart';
import 'feed_theme.dart';

/// Markdown as the desktop agent pane draws it (`element/markdown.tsx`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §4): GitHub-
/// flavoured Markdown, highlighted code fences with Copy, AgentMux's
/// semantic spans and GitHub callouts. Any other HTML shows as text.
///
/// [streaming] text is still growing: an unclosed fence at its end is not
/// highlighted until it closes.
class FeedMarkdown extends StatelessWidget {
  const FeedMarkdown(
    this.text, {
    super.key,
    this.streaming = false,
    this.style,
  });

  final String text;
  final bool streaming;

  /// Overrides the prose style (thinking is italic and muted).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final segments = splitCallouts(text);
    final openTail = streaming ? openFenceTail(text) : null;
    final sheet = style == null ? _sheet : _sheetFor(style!);
    final children = [
      for (final s in segments)
        switch (s) {
          MarkdownSegment(:final source) => _body(source, sheet, openTail),
          CalloutSegment(:final kind, :final body) => _Callout(
              kind: kind,
              child: FeedMarkdown(body, streaming: streaming, style: style),
            ),
        },
    ];
    if (children.length == 1) return children.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _body(String source, MarkdownStyleSheet sheet, String? openTail) {
    return MarkdownBody(
      data: source,
      selectable: true,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [AmSpanSyntax()],
      builders: {
        'pre': _CodeBuilder(openTail),
        'h1': _RuledHeadingBuilder(sheet),
        'h2': _RuledHeadingBuilder(sheet),
        AmSpanSyntax.tag: _AmSpanBuilder(),
      },
      imageBuilder: (uri, title, alt) => _ImageCard(uri: uri, alt: alt),
      onTapLink: (text, href, title) => _openLink(href),
    );
  }

  static final _sheet = _sheetFor(feedProse);
  static final _sheets = <TextStyle, MarkdownStyleSheet>{};

  /// One sheet per prose style, kept so a rebuild doesn't re-parse.
  static MarkdownStyleSheet _sheetFor(TextStyle p) =>
      _sheets[p] ??= _buildSheet(p);

  static MarkdownStyleSheet _buildSheet(TextStyle p) {
    final heading = p.copyWith(fontWeight: FontWeight.w600, height: 1.3);
    return MarkdownStyleSheet(
      p: p,
      pPadding: EdgeInsets.zero,
      blockSpacing: FeedSpace.s2,
      a: p.copyWith(color: FeedColors.link),
      code: feedCode.copyWith(
        fontSize: 12.5,
        backgroundColor: FeedColors.tint(FeedColors.text, 0.08),
        fontStyle: p.fontStyle,
        color: p.color,
      ),
      h1: heading.copyWith(fontSize: 28),
      h1Padding: const EdgeInsets.only(top: 6),
      h2: heading.copyWith(fontSize: 21),
      h2Padding: const EdgeInsets.only(top: 6),
      h3: heading.copyWith(fontSize: 17.5),
      h3Padding: const EdgeInsets.only(top: 6),
      h4: heading.copyWith(fontSize: 14),
      h5: heading.copyWith(fontSize: 12.25),
      h6: heading.copyWith(fontSize: 11.9),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      blockquote: p,
      blockquotePadding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
      blockquoteDecoration: const BoxDecoration(color: FeedColors.panel),
      listBullet: p,
      listIndent: 20,
      checkbox: p,
      tableHead: p.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      tableBody: p.copyWith(fontSize: 13),
      tableBorder: const TableBorder.symmetric(
        inside: BorderSide(color: FeedColors.border, width: 0.5),
        outside: BorderSide(color: FeedColors.border, width: 0.5),
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tableHeadCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tableHeadCellsDecoration: const BoxDecoration(color: FeedColors.hover),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FeedColors.border)),
      ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
    );
  }
}

Future<void> _openLink(String? href) async {
  if (href == null) return;
  final uri = Uri.tryParse(href);
  // Only web links: anything else names something on the computer.
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ─── Splitting: callouts, and the open fence while streaming ────────────────

sealed class Segment {}

class MarkdownSegment extends Segment {
  MarkdownSegment(this.source);
  final String source;
}

/// `> [!WARNING]` and the quoted lines under it.
class CalloutSegment extends Segment {
  CalloutSegment(this.kind, this.body);
  final CalloutKind kind;
  final String body;
}

enum CalloutKind { note, tip, important, warning, caution }

final _calloutStart =
    RegExp(r'^ {0,3}>\s*\[!(note|tip|important|warning|caution)\]\s*$', caseSensitive: false);
final _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// [text] cut into plain Markdown and GitHub callouts, outside code fences.
List<Segment> splitCallouts(String text) {
  if (!text.contains('[!')) return [MarkdownSegment(text)];
  final lines = text.split('\n');
  final out = <Segment>[];
  final plain = <String>[];
  String? fence;
  void flushPlain() {
    if (plain.isEmpty) return;
    out.add(MarkdownSegment(plain.join('\n')));
    plain.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final f = _fenceLine.firstMatch(line)?.group(1);
    if (fence != null) {
      if (f != null && f[0] == fence[0] && f.length >= fence.length) fence = null;
      plain.add(line);
      continue;
    }
    if (f != null) {
      fence = f;
      plain.add(line);
      continue;
    }
    final start = _calloutStart.firstMatch(line);
    if (start == null) {
      plain.add(line);
      continue;
    }
    final body = <String>[];
    while (i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('>')) {
      i++;
      body.add(lines[i].trimLeft().replaceFirst(RegExp(r'^> ?'), ''));
    }
    flushPlain();
    out.add(CalloutSegment(
      CalloutKind.values.byName(start.group(1)!.toLowerCase()),
      body.join('\n'),
    ));
  }
  flushPlain();
  return out;
}

/// The content of a code fence still open at the end of [text], or null
/// when every fence is closed.
String? openFenceTail(String text) {
  final lines = text.split('\n');
  String? fence;
  var start = 0;
  for (var i = 0; i < lines.length; i++) {
    final f = _fenceLine.firstMatch(lines[i])?.group(1);
    if (f == null) continue;
    if (fence == null) {
      fence = f;
      start = i + 1;
    } else if (f[0] == fence[0] && f.length >= fence.length) {
      fence = null;
    }
  }
  if (fence == null) return null;
  return lines.skip(start).join('\n');
}

// ─── Code ────────────────────────────────────────────────────────────────────

class _CodeBuilder extends MarkdownElementBuilder {
  _CodeBuilder(this.openTail);

  /// The unclosed fence's content while streaming: shown plain.
  final String? openTail;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    String? info;
    final inner = element.children?.firstOrNull;
    if (inner is md.Element) {
      final cls = inner.attributes['class'] ?? '';
      if (cls.startsWith('language-')) info = cls.substring('language-'.length);
    }
    final open = openTail != null && openTail!.trimRight() == code.trimRight();
    return CodeBlock(
      code: code,
      language: open ? null : CodeHighlighter.language(info),
    );
  }
}

/// A code block: the panel background, monospace, wrapped, highlighted when
/// [language] is known, with a Copy button.
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.code, this.language});
  final String code;
  final String? language;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: FeedColors.panel,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 36, 6),
            child: HighlightedCode(code: code, language: language),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CopyButton(text: code),
          ),
        ],
      ),
    );
  }
}

/// [code] as selectable text, highlighted when [language] is known: at once
/// when small, else off the UI thread, shown plain until then.
class HighlightedCode extends StatefulWidget {
  const HighlightedCode({
    super.key,
    required this.code,
    this.language,
    this.style = feedCode,
  });
  final String code;
  final String? language;
  final TextStyle style;

  @override
  State<HighlightedCode> createState() => _HighlightedCodeState();
}

class _HighlightedCodeState extends State<HighlightedCode> {
  TextSpan? _span;

  @override
  void initState() {
    super.initState();
    _highlight();
  }

  @override
  void didUpdateWidget(HighlightedCode old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.language != widget.language) _highlight();
  }

  void _highlight() {
    final code = widget.code;
    final language = widget.language;
    final style = widget.style;
    _span = CodeHighlighter.highlightSync(code, language, style) ??
        CodeHighlighter.cached(code, language);
    if (_span != null || language == null) return;
    unawaited(CodeHighlighter.highlightAsync(code, language, style).then((span) {
      if (!mounted || span == null) return;
      if (widget.code != code || widget.language != language) return;
      setState(() => _span = span);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      _span ?? TextSpan(text: widget.code, style: widget.style),
      style: widget.style,
    );
  }
}

/// Copies [text]; always visible, as a phone has no hover.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy',
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      color: FeedColors.secondary,
      icon: const Icon(Icons.copy_rounded),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 1),
          ));
      },
    );
  }
}

// ─── Headings ────────────────────────────────────────────────────────────────

/// h1 and h2 with the rule under them.
class _RuledHeadingBuilder extends MarkdownElementBuilder {
  _RuledHeadingBuilder(this.sheet);
  final MarkdownStyleSheet sheet;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FeedColors.border)),
      ),
      child: _InlineText(
        nodes: element.children ?? const [],
        style: preferredStyle ?? feedProse,
        sheet: sheet,
      ),
    );
  }
}

/// Inline Markdown (code, emphasis, links, semantic spans) as one selectable
/// paragraph, for a block a builder draws itself.
class _InlineText extends StatefulWidget {
  const _InlineText({required this.nodes, required this.style, required this.sheet});
  final List<md.Node> nodes;
  final TextStyle style;
  final MarkdownStyleSheet sheet;

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _spans(List<md.Node> nodes, TextStyle style) => [
        for (final n in nodes) ..._span(n, style),
      ];

  List<InlineSpan> _span(md.Node node, TextStyle style) {
    if (node is md.Text) return [TextSpan(text: node.text, style: style)];
    if (node is! md.Element) return const [];
    final children = node.children ?? const <md.Node>[];
    final sheet = widget.sheet;
    switch (node.tag) {
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: style.merge(sheet.code).copyWith(
                  fontSize: (style.fontSize ?? 14) * 0.9,
                  color: style.color,
                ),
          ),
        ];
      case 'strong':
        return _spans(children, style.merge(sheet.strong));
      case 'em':
        return _spans(children, style.merge(sheet.em));
      case 'del':
        return _spans(children, style.merge(sheet.del));
      case 'a':
        final href = node.attributes['href'];
        final r = TapGestureRecognizer()..onTap = () => unawaited(_openLink(href));
        _recognizers.add(r);
        return [
          TextSpan(
            text: node.textContent,
            style: style.copyWith(color: FeedColors.link),
            recognizer: r,
          ),
        ];
      case AmSpanSyntax.tag:
        final classes = (node.attributes['class'] ?? '').split(' ').toSet();
        return [TextSpan(text: node.textContent, style: style.merge(amSpanStyle(classes)))];
      default:
        return _spans(children, style);
    }
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    return SelectableText.rich(
      TextSpan(children: _spans(widget.nodes, widget.style)),
      style: widget.style,
    );
  }
}

// ─── AgentMux's semantic spans ───────────────────────────────────────────────

/// `<span class="am-ok">…</span>`, the classes the desktop allows
/// (`element/markdown-semantic.ts`). Unknown classes are dropped; the text
/// stays.
class AmSpanSyntax extends md.InlineSyntax {
  AmSpanSyntax() : super(r'<span\s+class="([a-z\- ]{1,80})"\s*>([^<]{0,2000})</span>');

  static const tag = 'am-span';
  static const classes = {
    'am-ok',
    'am-warn',
    'am-error',
    'am-info',
    'am-muted',
    'am-added',
    'am-removed',
    'am-badge',
  };

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final kept = match[1]!.split(' ').where(classes.contains).toList();
    final element = md.Element.text(tag, match[2]!);
    element.attributes['class'] = kept.join(' ');
    parser.addNode(element);
    return true;
  }
}

class _AmSpanBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final classes = (element.attributes['class'] ?? '').split(' ').toSet();
    final text = element.textContent;
    final base = parentStyle ?? feedProse;
    final style = base.merge(amSpanStyle(classes));
    if (!classes.contains('am-badge')) {
      return Text.rich(TextSpan(text: text, style: style));
    }
    final color = style.color ?? FeedColors.secondary;
    return Text.rich(TextSpan(children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: FeedColors.tint(color, 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: style.copyWith(
              fontSize: (base.fontSize ?? 14) * 0.85,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.5,
            ),
          ),
        ),
      ),
    ]));
  }
}

/// The style of a semantic span's classes (`markdown.scss`).
TextStyle amSpanStyle(Set<String> classes) {
  var s = const TextStyle();
  if (classes.contains('am-badge')) s = s.copyWith(color: FeedColors.secondary);
  if (classes.contains('am-ok')) s = s.copyWith(color: FeedColors.successText);
  if (classes.contains('am-warn')) s = s.copyWith(color: FeedColors.warningText);
  if (classes.contains('am-error')) s = s.copyWith(color: FeedColors.errorText);
  if (classes.contains('am-info')) s = s.copyWith(color: FeedColors.info);
  if (classes.contains('am-muted')) s = s.copyWith(color: FeedColors.secondary);
  if (classes.contains('am-added')) {
    s = s.copyWith(
      color: FeedColors.successText,
      backgroundColor: FeedColors.tint(FeedColors.successText, 0.14),
    );
  }
  if (classes.contains('am-removed')) {
    s = s.copyWith(
      color: FeedColors.errorText,
      backgroundColor: FeedColors.tint(FeedColors.errorText, 0.14),
      decoration: TextDecoration.lineThrough,
    );
  }
  return s;
}

// ─── Callouts ────────────────────────────────────────────────────────────────

class _Callout extends StatelessWidget {
  const _Callout({required this.kind, required this.child});
  final CalloutKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = calloutColor(kind);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 6),
      decoration: BoxDecoration(
        color: FeedColors.tint(color, 0.08),
        border: Border(left: BorderSide(color: color, width: 3.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            calloutTitle(kind),
            style: feedProse.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          child,
        ],
      ),
    );
  }
}

Color calloutColor(CalloutKind kind) => switch (kind) {
      CalloutKind.note => FeedColors.info,
      CalloutKind.tip => FeedColors.successText,
      CalloutKind.important => FeedColors.accent,
      CalloutKind.warning => FeedColors.warningText,
      CalloutKind.caution => FeedColors.errorText,
    };

String calloutTitle(CalloutKind kind) => switch (kind) {
      CalloutKind.note => 'Note',
      CalloutKind.tip => 'Tip',
      CalloutKind.important => 'Important',
      CalloutKind.warning => 'Warning',
      CalloutKind.caution => 'Caution',
    };

// ─── Images ──────────────────────────────────────────────────────────────────

/// An image in the reply. A local path names a file on the computer, which
/// the phone can't read; a web image loads only when tapped, as on the
/// desktop.
class _ImageCard extends StatefulWidget {
  const _ImageCard({required this.uri, this.alt});
  final Uri uri;
  final String? alt;

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  bool _load = false;

  @override
  Widget build(BuildContext context) {
    final uri = widget.uri;
    final web = uri.scheme == 'https' || uri.scheme == 'http';
    if (web && _load) {
      return Image.network(
        uri.toString(),
        errorBuilder: (_, __, ___) => _card(Icons.broken_image_outlined, 'Image didn\'t load: ${uri.host}'),
      );
    }
    final name = uri.pathSegments.isEmpty ? uri.toString() : uri.pathSegments.last;
    final label = web
        ? 'Image from ${uri.host}: tap to load'
        : 'Image on the computer: $name';
    final card = _card(Icons.image_outlined, label);
    return web ? InkWell(onTap: () => setState(() => _load = true), child: card) : card;
  }

  Widget _card(IconData icon, String label) {
    final alt = widget.alt;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: FeedColors.panel,
        border: Border.all(color: FeedColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: FeedColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alt == null || alt.isEmpty ? label : '$label\n$alt',
              style: feedProse.copyWith(fontSize: 12, color: FeedColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}
