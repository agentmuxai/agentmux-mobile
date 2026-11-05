import 'package:agentmux_mobile/features/demo/demo_fleet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no status-bar sized gap between the DEMO banner and the list', (
    tester,
  ) async {
    // An iPhone 17 Pro Max: a 59 pt status bar.
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(top: 177, bottom: 102)
      ..viewPadding = const FakeViewPadding(top: 177, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DemoFleetScreen()));
    final banner = tester.getBottomLeft(find.textContaining('DEMO DATA'));
    final hosts = tester.getTopLeft(find.text('Hosts'));
    // The banner's own padding and the list's: about 22, not 81.
    expect(hosts.dy - banner.dy, lessThan(40));
  });
}
