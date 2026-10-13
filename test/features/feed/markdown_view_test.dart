import 'package:agentmux_mobile/features/feed/code_highlight.dart';
import 'package:agentmux_mobile/features/feed/feed_theme.dart';
import 'package:agentmux_mobile/features/feed/markdown_view.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:agentmux_mobile/features/feed/transcript_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// The root span of every RichText and SelectableText under [finder],
/// with the widget's own style as the inherited base.
List<(InlineSpan, TextStyle?)> _roots(WidgetTester tester, Finder? finder) {
  final out = <(InlineSpan, TextStyle?)>[];
  final scope = finder ?? find.byType(MaterialApp);
  for (final w in tester.widgetList<SelectableText>(
    find.descendant(of: scope, matching: find.byType(SelectableText)),
  )) {
    out.add((w.textSpan ?? TextSpan(text: w.data), w.style));
  }
  for (final w in tester.widgetList<RichText>(
    find.descendant(of: scope, matching: find.byType(RichText)),
  )) {
    out.add((w.text, null));
  }
  return out;
}

/// Every TextSpan with text, flattened, each with its effective style.
List<(String, TextStyle)> _spans(WidgetTester tester, [Finder? finder]) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle base) {
    if (s is! TextSpan) return;
    final style = base.merge(s.style);
    if (s.text != null) out.add((s.text!, style));
    s.children?.forEach((c) => walk(c, style));
  }

  for (final (root, style) in _roots(tester, finder)) {
    walk(root, style ?? const TextStyle());
  }
  return out;
}

String _text(WidgetTester tester) => _spans(tester).map((s) => s.$1).join();

/// The colour the first span containing [text] is drawn in.
Color? _colorOf(WidgetTester tester, String text) =>
    _spans(tester).where((s) => s.$1.contains(text)).firstOrNull?.$2.color;

void main() {
  group('splitCallouts', () {
    test('plain Markdown stays one segment', () {
      final s = splitCallouts('# Title\n\nText');
      expect(s.single, isA<MarkdownSegment>());
    });

    test('a callout and the text around it', () {
      final s = splitCallouts(
        'Before\n> [!WARNING]\n> Closing this loses the repro.\n> Twice.\nAfter',
      );
      expect(s.map((x) => x.runtimeType), [MarkdownSegment, CalloutSegment, MarkdownSegment]);
      final c = s[1] as CalloutSegment;
      expect(c.kind, CalloutKind.warning);
      expect(c.body, 'Closing this loses the repro.\nTwice.');
    });

    test('not inside a code fence, and an unknown kind is a quote', () {
      expect(splitCallouts('```\n> [!NOTE]\n> x\n```').single, isA<MarkdownSegment>());
      expect(splitCallouts('> [!FOO]\n> x').single, isA<MarkdownSegment>());
    });
  });

  test('openFenceTail: the unclosed fence at the end, or null', () {
    expect(openFenceTail('Text\n```dart\nvoid main'), 'void main');
    expect(openFenceTail('```dart\na\n```\nmore'), isNull);
    expect(openFenceTail('~~~~\n```\nstill open'), '```\nstill open');
  });

  group('CodeHighlighter', () {
    test('fence names, aliases and file extensions', () {
      expect(CodeHighlighter.language('ts'), 'ts');
      expect(CodeHighlighter.language('TypeScript'), 'typescript');
      expect(CodeHighlighter.language('zsh'), 'bash');
      expect(CodeHighlighter.language('toml'), 'ini');
      expect(CodeHighlighter.language('brainfuck'), isNull);
      expect(CodeHighlighter.language(''), isNull);
      expect(CodeHighlighter.languageForPath('src/main.rs'), 'rs');
      expect(CodeHighlighter.languageForPath(r'C:\a\Cargo.toml'), 'ini');
      expect(CodeHighlighter.languageForPath('README'), isNull);
    });

    test('colours code in more than one colour', () {
      final span = CodeHighlighter.highlightSync(
        'fn main() { let x = "hi"; }',
        'rust',
        feedCode,
      )!;
      final colors = <Color>{};
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.style?.color != null) colors.add(s.style!.color!);
          s.children?.forEach(walk);
        }
      }

      walk(span);
      expect(colors.length, greaterThan(2));
      expect(span.toPlainText(), 'fn main() { let x = "hi"; }');
    });

    test('unknown or too large stays plain', () {
      expect(CodeHighlighter.highlightSync('x', null, feedCode), isNull);
      final big = 'a' * (CodeHighlighter.syncChars + 1);
      expect(CodeHighlighter.highlightSync(big, 'rust', feedCode), isNull);
    });
  });

  group('FeedMarkdown', () {
    testWidgets('a fence is highlighted, and Copy copies it', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.pumpWidget(_host(const FeedMarkdown(
        'Run this:\n\n```bash\ngit status --short\n```',
      )));
      expect(find.byType(CodeBlock), findsOneWidget);
      final colors = _spans(tester, find.byType(CodeBlock))
          .map((s) => s.$2.color)
          .whereType<Color>()
          .toSet();
      expect(colors.length, greaterThan(1));

      await tester.tap(find.byTooltip('Copy'));
      await tester.pump();
      expect(copied, 'git status --short');
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('an unclosed fence while streaming stays plain', (tester) async {
      await tester.pumpWidget(_host(const FeedMarkdown(
        '```rust\nfn main() { let x = 1; }',
        streaming: true,
      )));
      final block = tester.widget<CodeBlock>(find.byType(CodeBlock));
      expect(block.language, isNull);
      expect(block.code, 'fn main() { let x = 1; }');
    });

    testWidgets('inline code, bold, links and a table render', (tester) async {
      await tester.pumpWidget(_host(const FeedMarkdown(
        'Use `flutter test` **now**, see [docs](https://example.com).\n\n'
        '| a | b |\n|---|---|\n| 1 | 2 |',
      )));
      final spans = _spans(tester);
      TextStyle styleOf(String t) => spans.firstWhere((s) => s.$1 == t).$2;
      expect(styleOf('flutter test').fontFamily, feedMono);
      expect(styleOf('flutter test').backgroundColor, isNotNull);
      expect(styleOf('now').fontWeight, FontWeight.w700);
      expect(styleOf('docs').color, FeedColors.link);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('AgentMux spans are coloured; other HTML shows as text', (tester) async {
      await tester.pumpWidget(_host(const FeedMarkdown(
        '<span class="am-ok">All tests pass</span> and '
        '<span class="am-badge am-error">P1</span> but <b>bold?</b>',
      )));
      expect(_colorOf(tester, 'All tests pass'), FeedColors.successText);
      expect(_colorOf(tester, 'P1'), FeedColors.errorText);
      final all = _text(tester);
      expect(all, contains('<b>bold?</b>'));
      expect(all, isNot(contains('am-ok')));
    });

    testWidgets('a callout has its title in its colour', (tester) async {
      await tester.pumpWidget(_host(const FeedMarkdown(
        '> [!CAUTION]\n> This deletes the branch.',
      )));
      expect(find.text('Caution'), findsOneWidget);
      expect(_colorOf(tester, 'Caution'), FeedColors.errorText);
      expect(_text(tester), contains('This deletes the branch.'));
    });

    testWidgets('a local image is a card naming the file', (tester) async {
      await tester.pumpWidget(_host(const FeedMarkdown(
        '![the toolbar](screenshots/toolbar-after.png)',
      )));
      expect(find.textContaining('Image on the computer: toolbar-after.png'), findsOneWidget);
    });
  });

  group('items', () {
    testWidgets('a prompt is a full-width inverted block, not a bubble', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(item: PromptItem(0, 'Fix the test'))));
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(PromptBlock),
        matching: find.byType(Container),
      ));
      final d = box.decoration! as BoxDecoration;
      expect(d.color, FeedColors.text);
      expect(d.borderRadius, isNull);
      expect((d.border! as Border).left.color, FeedColors.userInput);
      expect(find.byType(Align), findsNothing);
      final width = tester.getSize(find.byType(PromptBlock)).width;
      final screen = tester.getSize(find.byType(Scaffold)).width;
      expect(width, screen - 2 * FeedSpace.s3);
      expect(_colorOf(tester, 'Fix the test'), FeedColors.blockSolid);
    });

    testWidgets('a prompt is shown as typed, not as Markdown', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(item: PromptItem(0, '# not a heading **x**'))));
      expect(_text(tester), '# not a heading **x**');
    });

    testWidgets('thinking shows its text, italic and muted', (tester) async {
      await tester.pumpWidget(_host(TranscriptItemView(
        item: ThinkingItem(0, 'Maybe the *fixture* is stale'),
      )));
      final spans = _spans(tester);
      expect(spans.map((s) => s.$1).join(), 'Maybe the fixture is stale');
      expect(spans.every((s) => s.$2.fontStyle == FontStyle.italic), isTrue);
      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('a streaming reply re-renders at most every 90 ms', (tester) async {
      final item = StreamingTextItem(0, 'Hel');
      Widget view() => _host(TranscriptItemView(item: item));
      await tester.pumpWidget(view());
      item.text = 'Hello';
      await tester.pumpWidget(view());
      item.text = 'Hello there';
      await tester.pumpWidget(view());
      String shown() => _text(tester);
      // The first change after the first frame may land at once; the burst
      // after it waits for the interval.
      expect(shown(), isNot('Hello there'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(shown(), 'Hello there');
    });
  });
}
