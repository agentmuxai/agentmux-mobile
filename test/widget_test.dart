import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agentmux_mobile/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AgentMuxApp()),
    );
    expect(find.text('AgentMux'), findsOneWidget);

    // Let the first discovery round's scan-window timers fire. The notifier's
    // periodic tick and round timers are cancelled when the ProviderScope is
    // disposed at teardown, so the binding's pending-timer check passes.
    await tester.pump(const Duration(seconds: 6));
  });
}
