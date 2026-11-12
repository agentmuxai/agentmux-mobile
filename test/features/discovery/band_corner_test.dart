import 'package:agentmux_mobile/features/discovery/fleet_status.dart';
import 'package:agentmux_mobile/features/discovery/muxbus_account_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the band text keeps clear of the rounded display corner', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FleetStatusLine(
              status: FleetStatus(
                connection: 'LAN',
                computers: 3,
                working: 0,
                waiting: 1,
                live: true,
              ),
              indicatorGap: true,
              height: 34,
            ),
          ),
        ),
      ),
    );
    final screenWidth = tester.view.physicalSize.width / 3;
    final right = tester.getTopRight(find.textContaining('needs you'));
    final left = tester.getTopLeft(find.textContaining('LAN'));
    // A phone's bottom corners are about 55 pt: 30 pt in at least.
    expect(screenWidth - right.dx, greaterThanOrEqualTo(30));
    expect(left.dx, greaterThanOrEqualTo(30));
  });

  testWidgets('the band text keeps clear of the home indicator on a 6.9" phone', (
    tester,
  ) async {
    // iPhone 16 Pro Max: 440 pt wide, its home indicator 156.7 pt wide.
    const indicatorHalf = 156.7 / 2;
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FleetStatusLine(
              status: FleetStatus(
                connection: 'LAN',
                computers: 4,
                working: 3,
                waiting: 0,
                live: true,
              ),
              indicatorGap: true,
              height: 34,
            ),
          ),
        ),
      ),
    );
    final centre = tester.view.physicalSize.width / 3 / 2;
    final leftEnd = tester.getTopRight(find.textContaining('LAN')).dx;
    final rightStart = tester.getTopLeft(find.textContaining('working')).dx;
    expect(leftEnd, lessThanOrEqualTo(centre - indicatorHalf));
    expect(rightStart, greaterThanOrEqualTo(centre + indicatorHalf));
  });
}
