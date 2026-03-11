import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agentmux_mobile/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AgentMuxApp()),
    );
    expect(find.text('AgentMux'), findsOneWidget);
  });
}
