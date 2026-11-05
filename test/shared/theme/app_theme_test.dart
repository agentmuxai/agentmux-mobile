import 'dart:math' as math;

import 'package:agentmux_mobile/features/feed/code_highlight.dart';
import 'package:agentmux_mobile/features/feed/feed_theme.dart';
import 'package:agentmux_mobile/features/feed/markdown_view.dart';
import 'package:agentmux_mobile/features/feed/transcript_view.dart';
import 'package:agentmux_mobile/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative luminance of an opaque colour.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

/// [fg] (which may have alpha) drawn over the opaque [bg].
double _contrast(Color fg, Color bg) {
  final shown = Color.alphaBlend(fg, bg);
  final a = _luminance(shown);
  final b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  group('palette', () {
    test('light text reaches 4.5:1 on the light background and surface', () {
      const p = AppPalette.light;
      for (final (name, c) in [
        ('textPrimary', p.textPrimary),
        ('textSecondary', p.textSecondary),
        ('textMuted', p.textMuted),
        ('textSoft', p.textSoft),
        ('textDim', p.textDim),
        ('textFaint', p.textFaint),
        ('success', p.success),
        ('warning', p.warning),
        ('error', p.error),
        ('primary', p.primary),
        ('live', p.live),
        ('teal', p.teal),
        ('violet', p.violet),
        ('amber', p.amber),
      ]) {
        for (final bg in [p.background, p.surface]) {
          expect(
            _contrast(c, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name on ${bg.toARGB32().toRadixString(16)}',
          );
        }
      }
    });

    test('dark primary and secondary text keep their contrast', () {
      const p = AppPalette.dark;
      for (final c in [p.textPrimary, p.textSecondary, p.textSoft]) {
        for (final bg in [p.background, p.surface]) {
          expect(_contrast(c, bg), greaterThanOrEqualTo(4.5));
        }
      }
    });

    test('the feed light text reaches 4.5:1 on the light surface', () {
      const f = FeedPalette.light;
      for (final (name, c) in [
        ('text', f.text),
        ('secondary', f.secondary),
        ('grey', f.grey),
        ('accent', f.accent),
        ('successText', f.successText),
        ('warningText', f.warningText),
        // Tool bars, and also the colour of a tool's name and glyph.
        ('success', f.success),
        ('warning', f.warning),
        ('error', f.error),
        ('errorText', f.errorText),
        ('info', f.info),
        ('link', f.link),
        ('termGreen', f.termGreen),
        ('termCyan', f.termCyan),
        ('termMagenta', f.termMagenta),
      ]) {
        expect(
          _contrast(c, AppPalette.light.surface),
          greaterThanOrEqualTo(4.5),
          reason: name,
        );
      }
    });

    test('the feed dark set is the desktop pane palette', () {
      expect(FeedPalette.dark.text, const Color(0xFFF7F7F7));
      expect(FeedPalette.dark.link, const Color(0xFF32AFFF));
      expect(FeedPalette.dark.blockSolid, const Color(0xFF000000));
    });

    test('the dark set is what the app always showed', () {
      expect(AppPalette.dark.background, const Color(0xFF0F0F0F));
      expect(AppPalette.dark.surface, const Color(0xFF1A1A1A));
      expect(AppPalette.dark.primary, const Color(0xFF3B82F6));
      expect(AppPalette.dark.textDim, Colors.white54);
      expect(AppPalette.dark.textFaint, Colors.white38);
    });
  });

  group('the app follows the OS colour mode', () {
    Widget app({Widget? home}) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: appThemeBuilder,
      home: home ?? const Scaffold(body: SizedBox()),
    );

    AppPalette palette(WidgetTester tester) =>
        AppPalette.of(tester.element(find.byType(Scaffold)));

    SystemUiOverlayStyle overlay(WidgetTester tester) => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .byType(AnnotatedRegion<SystemUiOverlayStyle>)
              .first,
        )
        .value;

    testWidgets('light OS: light palette, dark status-bar icons', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app());
      expect(palette(tester).background, AppPalette.light.background);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
      expect(overlay(tester).statusBarIconBrightness, Brightness.dark);
      expect(overlay(tester).systemNavigationBarIconBrightness, Brightness.dark);
      // iOS reads the bar's own brightness, the opposite of its icons.
      expect(overlay(tester).statusBarBrightness, Brightness.light);
    });

    testWidgets('dark OS: dark palette, light status-bar icons', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app());
      expect(palette(tester).background, AppPalette.dark.background);
      expect(overlay(tester).statusBarIconBrightness, Brightness.light);
      expect(overlay(tester).statusBarBrightness, Brightness.dark);
    });

    testWidgets('changing the OS setting while running switches the palette', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app());
      expect(palette(tester).surface, AppPalette.dark.surface);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(palette(tester).surface, AppPalette.light.surface);
    });
  });

  testWidgets('crossing the wide-window threshold keeps screen state', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: appThemeBuilder,
        home: const Scaffold(body: TextField(key: ValueKey('field'))),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('field')), 'kept');
    // A phone turned to landscape is wider than the snack bar cap.
    tester.view.physicalSize = const Size(852, 393);
    await tester.pumpAndSettle();
    expect(find.text('kept'), findsOneWidget);
    tester.view.physicalSize = const Size(393, 852);
    await tester.pumpAndSettle();
    expect(find.text('kept'), findsOneWidget);
  });

  group('the feed follows the OS colour mode', () {
    Future<void> pumpIn(WidgetTester tester, Brightness mode, Widget child) {
      tester.platformDispatcher.platformBrightnessTestValue = mode;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('prose takes the text colour of each mode', (
      tester,
    ) async {
      await pumpIn(tester, Brightness.light, const FeedMarkdown('Hello there'));
      var run = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(run.textSpan?.style?.color ?? run.style?.color, FeedPalette.light.text);
      await pumpIn(tester, Brightness.dark, const FeedMarkdown('Hello there'));
      await tester.pumpAndSettle();
      run = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(run.textSpan?.style?.color ?? run.style?.color, FeedPalette.dark.text);
    });

    testWidgets('the prompt block inverts: light text on a dark box in light mode', (
      tester,
    ) async {
      await pumpIn(
        tester,
        Brightness.light,
        const PromptBlock(text: 'Fix the test'),
      );
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('Fix the test'), matching: find.byType(Container))
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, FeedPalette.light.text);
      expect(
        tester.widget<EditableText>(find.text('Fix the test')).style.color,
        FeedPalette.light.blockSolid,
      );
    });

    test('syntax highlighting is cached per mode, with a theme for each', () {
      const code = 'fn main() { let x = 1; }';
      const base = TextStyle(fontSize: 12);
      final dark = CodeHighlighter.highlightSync(code, 'rust', base, Brightness.dark)!;
      final light = CodeHighlighter.highlightSync(code, 'rust', base, Brightness.light)!;
      Set<Color?> colours(InlineSpan s) {
        final out = <Color?>{};
        void walk(InlineSpan n) {
          if (n is TextSpan) {
            out.add(n.style?.color);
            n.children?.forEach(walk);
          }
        }

        walk(s);
        return out;
      }

      expect(colours(dark), isNot(colours(light)));
    });
  });

  group('snack bar', () {
    Future<void> show(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          builder: appThemeBuilder,
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied 12 log entries')),
                        ),
                    child: const Text('go'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The snack bar's own card: the SnackBar widget itself spans the row.
    Finder card() => find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first;

    testWidgets('floats, rounded, in the surface colour, inset from the edges', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await show(tester, const Size(393, 852));
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.backgroundColor, AppPalette.light.surfaceVariant);
      expect(bar.content, isA<Text>());
      final rect = tester.getRect(card());
      expect(rect.left, greaterThanOrEqualTo(12));
      expect(rect.right, lessThanOrEqualTo(393 - 12));
      expect(rect.bottom, lessThan(852));
    });

    testWidgets('on a wide window it stops at a readable width', (tester) async {
      await show(tester, const Size(1376, 774));
      expect(
        tester.getSize(card()).width,
        AppTheme.snackBarMaxWidth,
      );
    });
  });
}
