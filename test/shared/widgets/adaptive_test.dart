import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:agentmux_mobile/shared/theme/app_theme.dart';
import 'package:agentmux_mobile/shared/widgets/adaptive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const probe = ValueKey('probe');

  Widget app(Widget home) => MaterialApp(
    theme: AppTheme.light,
    builder: appThemeBuilder,
    home: home,
  );

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view
      ..physicalSize = s
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('ContentWidth', () {
    Widget page() => Scaffold(
      body: ContentWidth(child: Container(key: probe, color: Colors.red)),
    );

    testWidgets('a tablet gets a centred column', (tester) async {
      await size(tester, const Size(1376, 774));
      await tester.pumpWidget(app(page()));
      final r = tester.getRect(find.byKey(probe));
      expect(r.width, listMaxWidth);
      expect(r.center.dx, 688);
      expect(r.height, 774);
    });

    testWidgets('a phone, portrait or landscape, keeps its full width', (
      tester,
    ) async {
      await size(tester, const Size(393, 852));
      await tester.pumpWidget(app(page()));
      expect(tester.getSize(find.byKey(probe)).width, 393);
      await size(tester, const Size(956, 440));
      await tester.pumpWidget(app(page()));
      await tester.pump();
      expect(tester.getSize(find.byKey(probe)).width, 956);
    });

    testWidgets('the side margin clears the safe area it overlaps', (
      tester,
    ) async {
      await size(tester, const Size(1376, 774));
      late EdgeInsets padding;
      await tester.pumpWidget(
        MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(left: 40, right: 40, top: 10),
                ),
                child: child!,
              ),
          home: Scaffold(
            body: ContentWidth(
              child: Builder(
                builder: (context) {
                  padding = MediaQuery.paddingOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      // The 368 pt margin covers a 40 pt inset; the top inset stays.
      expect(padding.left, 0);
      expect(padding.right, 0);
      expect(padding.top, 10);
    });

    testWidgets('crossing the limit keeps the screen\'s state', (tester) async {
      await size(tester, const Size(393, 852));
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: ContentWidth(child: TextField(key: probe)),
          ),
        ),
      );
      await tester.enterText(find.byKey(probe), 'kept');
      await size(tester, const Size(1032, 1376));
      await tester.pumpAndSettle();
      expect(find.text('kept'), findsOneWidget);
      expect(tester.getSize(find.byKey(probe)).width, listMaxWidth);
    });
  });

  group('window controls (iPadOS)', () {
    Future<double> backArrowLeft(
      WidgetTester tester, {
      required Size display,
      required Size window,
    }) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      tester.view.display
        ..size = display
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      await tester.pumpWidget(
        app(
          Scaffold(
            appBar: AppBarInset(
              child: AppBar(
                leading: const BackButton(key: probe),
                title: const Text('Demo'),
              ),
            ),
          ),
        ),
      );
      final left = tester.getRect(find.byKey(probe)).left;
      // Before the test body ends: the binding checks it then.
      debugDefaultTargetPlatformOverride = null;
      return left;
    }

    testWidgets('a windowed iPad moves the back arrow clear of them', (
      tester,
    ) async {
      final left = await backArrowLeft(
        tester,
        display: const Size(1376, 1032),
        window: const Size(1376, 774),
      );
      expect(left, greaterThanOrEqualTo(windowControlsWidth));
    });

    testWidgets('full screen, the arrow stays where it was', (tester) async {
      final left = await backArrowLeft(
        tester,
        display: const Size(1376, 1032),
        window: const Size(1376, 1032),
      );
      expect(left, lessThan(windowControlsWidth));
    });

    testWidgets('an iPhone has no window controls', (tester) async {
      final left = await backArrowLeft(
        tester,
        display: const Size(393, 852),
        window: const Size(393, 600),
      );
      expect(left, lessThan(windowControlsWidth));
    });
  });

  testWidgets('nothing is drawn across a half-open hinge', (tester) async {
    await size(tester, const Size(2208, 1840));
    tester.view.displayFeatures = [
      const DisplayFeature(
        bounds: Rect.fromLTWH(1100, 0, 8, 1840),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    await tester.pumpWidget(
      app(Scaffold(body: Container(key: probe, color: Colors.red))),
    );
    final r = tester.getRect(find.byKey(probe));
    expect(r.right, lessThanOrEqualTo(1100));
    expect(r.left, 0);
  });

  testWidgets('an unfolded foldable with a flat fold is one screen', (
    tester,
  ) async {
    await size(tester, const Size(2208, 1840));
    tester.view.displayFeatures = [
      const DisplayFeature(
        bounds: Rect.fromLTWH(1104, 0, 0, 1840),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    await tester.pumpWidget(
      app(Scaffold(body: Container(key: probe, color: Colors.red))),
    );
    expect(tester.getSize(find.byKey(probe)).width, 2208);
  });
}
