import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/fleet/sse.dart';
import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/sysinfo_events.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/sysinfo/sysinfo_screen.dart';
import 'package:agentmux_mobile/features/sysinfo/sysinfo_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/viewer/viewer_fakes.dart';

String _sample(int ts, double cpu, {double used = 8, double total = 16}) => 'event: sample\nid: $ts\ndata: ${jsonEncode({
      'ts': ts,
      'values': {'cpu': cpu, 'cpu:0': cpu, 'cpu:1': cpu / 2, 'mem:used': used, 'mem:total': total},
      'uptime_secs': 60,
    })}\n\n';

/// Always the top of the backoff range, so waits are predictable.
class _MaxRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0.999;
  @override
  bool nextBool() => true;
}

void main() {
  group('a sample', () {
    test('from the desktop\'s TimeSeriesData', () {
      final s = SysinfoSample.fromJson({
        'ts': 5,
        'values': {'cpu': 23.4, 'cpu:10': 5, 'cpu:2': 50, 'mem:used': 4, 'mem:total': 16, 'bad': 'x'},
      })!;
      expect(s.ts, 5);
      expect(s.cpu, 23.4);
      expect(s.cores, [50, 5], reason: 'core order, by number');
      expect(s.memPercent, 25);
      expect(s.values.containsKey('bad'), isFalse);
      expect(SysinfoSample.fromJson({'values': {}}), isNull);
      expect(SysinfoSample.fromJson('x'), isNull);
    });

    test('only sample events are samples', () {
      expect(parseSysinfoEvent(const SseEvent(event: 'sample', data: '{"ts":1,"values":{}}'))?.ts, 1);
      expect(parseSysinfoEvent(const SseEvent(event: 'other', data: '{"ts":1,"values":{}}')), isNull);
      expect(parseSysinfoEvent(const SseEvent(event: 'sample', data: 'not json')), isNull);
    });

    test('the row\'s summary', () {
      expect(
        sysinfoSummaryText(const SysinfoNow(SysinfoSample(ts: 1, values: {'cpu': 23.4, 'mem:used': 9.8, 'mem:total': 16}))),
        'CPU 23% · RAM 61%',
      );
      expect(sysinfoSummaryText(const SysinfoNow(null)), 'No sample yet');
      expect(sysinfoSummaryText(const SysinfoTooOld()), 'Needs a newer AgentMux');
      expect(sysinfoSummaryText(const SysinfoUnreachable()), "Can't reach it");
      expect(sysinfoSummaryText(null), '');
    });

    test('kept in time order, once, for five minutes', () {
      final samples = <SysinfoSample>[];
      addSample(samples, const SysinfoSample(ts: 1000, values: {}));
      addSample(samples, const SysinfoSample(ts: 1000, values: {}));
      addSample(samples, const SysinfoSample(ts: 500, values: {}));
      addSample(samples, const SysinfoSample(ts: 2000, values: {}));
      expect(samples.map((s) => s.ts), [1000, 2000]);
      addSample(samples, SysinfoSample(ts: 2000 + sysinfoWindow.inMilliseconds, values: const {}));
      expect(samples.map((s) => s.ts), [2000, 2000 + sysinfoWindow.inMilliseconds]);
    });

    test('a clock set back starts the chart again', () {
      final samples = <SysinfoSample>[
        const SysinfoSample(ts: 100000, values: {}),
        const SysinfoSample(ts: 101000, values: {}),
      ];
      // A few seconds back is a sample this device already has.
      addSample(samples, const SysinfoSample(ts: 95000, values: {}));
      expect(samples.map((s) => s.ts), [100000, 101000]);
      // A minute back is the clock.
      addSample(samples, const SysinfoSample(ts: 41000, values: {}));
      expect(samples.map((s) => s.ts), [41000]);
    });
  });

  group('the client', () {
    ViewerClient client(FakeAdapter adapter) =>
        ViewerClient(host: '198.51.100.30', port: 29800, fingerprint: 'a' * 64, token: 'amxv_t', adapter: adapter);

    test('the latest sample; none yet; an older desktop', () async {
      final ok = client(FakeAdapter([
        const FakeResponse(200, json: {'ts': 9, 'values': {'cpu': 1}}),
      ]));
      expect((await ok.sysinfo())?.ts, 9);
      expect(await client(FakeAdapter([const FakeResponse(204)])).sysinfo(), isNull);
      expect(client(FakeAdapter([const FakeResponse(404)])).sysinfo(), throwsA(isA<ViewerNotFound>()));
    });

    test('the feed asks from since, and parses samples', () async {
      final adapter = FakeAdapter([FakeResponse(200, chunks: [_sample(10, 5)])]);
      final samples = await client(adapter).sysinfoFeed(since: 7).where((s) => s != null).take(1).toList();
      expect(samples.single!.ts, 10);
      expect(adapter.requests.single.uri.toString(), endsWith('/agentmux/viewer/sysinfo/feed?since=7'));
    });
  });

  testWidgets('the screen: live charts, cores under a tap', (tester) async {
    final adapter = FakeAdapter([
      FakeResponse(200, keepOpen: true, chunks: [_sample(1000, 20), _sample(2000, 40, used: 12)]),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token, adapter: adapter),
        ),
      ],
      child: MaterialApp(
        home: SysinfoScreen(
          pairing: PairingMatch(paired: testPairedHost(), host: '198.51.100.30', port: 29800),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('12.0 of 16.0 GB'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.tap(find.widgetWithText(ExpansionTile, '2 cores'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsNWidgets(2), reason: 'the card and core 0');
    expect(find.text('20%'), findsOneWidget, reason: 'core 1');

    // More samples append live.
    adapter.open.single.add(Uint8List.fromList(utf8.encode(_sample(3000, 90))));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('90%'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a computer that keeps failing is asked less and less often', (tester) async {
    // Every connection fails, as one to a computer that is switched off does.
    final adapter = FakeAdapter([const FakeResponse(500)]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token, adapter: adapter),
        ),
      ],
      child: MaterialApp(
        home: SysinfoScreen(
          pairing: PairingMatch(paired: testPairedHost(), host: '198.51.100.30', port: 29800),
          random: _MaxRandom(),
        ),
      ),
    ));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // At 0 s, then after 2, 4, 8 and 16 s more; a retry every 3 s made 17.
    expect(adapter.requests, hasLength(5));
    expect(find.text('Reconnecting…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an older desktop says to update it', (tester) async {
    final adapter = FakeAdapter([const FakeResponse(404)]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token, adapter: adapter),
        ),
      ],
      child: MaterialApp(
        home: SysinfoScreen(
          pairing: PairingMatch(paired: testPairedHost(), host: '198.51.100.30', port: 29800),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('Update AgentMux on the computer to see its Sysinfo here.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // Keeps unawaited futures from being reported as unused imports.
  unawaited(Future<void>.value());
}
