import 'dart:convert';

import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/terminal/terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import '../../core/viewer/viewer_fakes.dart';

void main() {
  late InMemorySecureStore store;
  setUp(() => store = InMemorySecureStore());

  Future<void> pump(WidgetTester tester, FakeAdapter adapter) async {
    final paired = testPairedHost();
    await PairedHostsRepository(store).save([paired]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(
            host: host,
            port: port,
            fingerprint: fingerprint,
            token: token,
            adapter: adapter,
          ),
        ),
      ],
      child: MaterialApp(
        home: TerminalScreen(
          pairing: PairingMatch(paired: paired, host: paired.host, port: paired.port),
          blockId: 'blk',
          label: 'build',
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('shows the terminal read-only, at the desktop\'s width', (tester) async {
    final data = base64Encode(utf8.encode('\$ make\r\nok\r\n'));
    await pump(
      tester,
      FakeAdapter([
        FakeResponse(200, keepOpen: true, chunks: [
          'event: snapshot\nid: 12\ndata: {"offset":0,"next_offset":12,'
              '"data64":"$data","rows":24,"cols":200}\n\n',
        ]),
      ]),
    );
    expect(find.text('build'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.readOnly, isTrue);
    expect(view.autoResize, isFalse, reason: 'never resized from the device');
    expect(view.terminal.viewWidth, 200);
    expect(view.terminal.buffer.getText(), contains('ok'));
    // 200 columns don't fit a phone: it scrolls sideways.
    final box = tester.getSize(find.byType(TerminalView));
    expect(box.width, greaterThan(tester.getSize(find.byType(Scaffold)).width));
    await unmount(tester);
  });

  testWidgets('says how to turn sharing on when the computer doesn\'t share',
      (tester) async {
    await pump(tester, FakeAdapter([const FakeResponse(403, chunks: [])]));
    expect(find.text('This computer doesn\'t share its terminals'), findsOneWidget);
    expect(find.textContaining('Share terminals with paired devices'), findsOneWidget);
    await unmount(tester);
  });
}
