import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agentmux_mobile/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AgentMuxApp()),
    );
    expect(find.text('AgentMux'), findsOneWidget);

    // DiscoveryNotifier.build() schedules a 5s Stream.timeout() Timer for the
    // mDNS scan; advance the fake clock past it so the Timer fires and clears
    // before teardown, or the test binding's pending-timer invariant fails.
    await tester.pump(const Duration(seconds: 6));
  });
}
