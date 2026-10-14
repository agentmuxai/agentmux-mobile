import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/tower_snapshot.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/tower/tower_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/viewer/viewer_fakes.dart';

const _gb = 1024 * 1024 * 1024;

final _snapshot = {
  'ts_ms': 1,
  'hostname': 'narko',
  'os': 'windows',
  'cpu_count': 8,
  'memory_metric': 'private working set',
  'interval_ms': 2000,
  'remote': true,
  'tasks': [
    {
      'id': 'b1',
      'kind': 'agent',
      'label': 'Clamk',
      'tracking': 'high',
      'cpu': 2.0,
      'cpu_account': true,
      'mem': 2 * _gb,
      'processes': [
        {'id': '1:1', 'pid': 101, 'name': 'claude.exe', 'cpu': 1.5, 'mem': _gb},
      ],
    },
    {'id': 'x', 'kind': 'mystery', 'label': 'skipped'},
  ],
  'machine': {'cpu': 4.0, 'mem': 10 * _gb, 'processes': 142},
  'host': {
    'processes': [
      {'id': '2:1', 'pid': 7, 'name': 'idle.exe', 'cpu': 0.1, 'mem': 1024 * 1024},
      {'id': '3:1', 'pid': 9, 'name': 'cargo.exe', 'cpu': 3.0, 'mem': 900 * 1024 * 1024, 'detail': 'Build'},
    ],
    'unmeasured': 0,
    'mem': 10 * _gb,
    'total': 142,
    'matched': 142,
  },
};

Widget _screen(FakeAdapter adapter) => ProviderScope(
      overrides: [
        viewerClientFactoryProvider.overrideWithValue(
          ({required host, required port, required fingerprint, token}) =>
              ViewerClient(host: host, port: port, fingerprint: fingerprint, token: token, adapter: adapter),
        ),
      ],
      child: MaterialApp(
        home: TowerScreen(pairing: PairingMatch(paired: testPairedHost(), host: '198.51.100.30', port: 29800)),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  test('a snapshot: tasks of known kinds, totals, processes', () {
    final s = TowerSnapshot.fromJson(_snapshot)!;
    expect(s.cpuCount, 8);
    expect(s.tasks.single.label, 'Clamk');
    expect(s.tasks.single.processes.single.name, 'claude.exe');
    expect(s.machine!.processes, 142);
    expect(s.host!.processes.map((p) => p.pid), [7, 9]);
    expect(s.percentOfMachine(4.0), 50);
    expect(TowerSnapshot.fromJson('x'), isNull);
  });

  test('the row\'s summary', () {
    expect(towerSummaryText(TowerNow(TowerSnapshot.fromJson(_snapshot)!)), '142 processes');
    expect(towerSummaryText(const TowerNotShared()), 'Not shared');
    expect(towerSummaryText(const TowerTooOld()), 'Needs a newer AgentMux');
    expect(formatMemory(10 * _gb), '10.0 GB');
    expect(formatMemory(900 * 1024 * 1024), '900 MB');
  });

  testWidgets('not shared: how to turn it on, in the desktop\'s words', (tester) async {
    await tester.pumpWidget(_screen(FakeAdapter([const FakeResponse(403)])));
    await _settle(tester);
    expect(find.textContaining(towerShareSetting), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shared: totals, tasks that open, busiest first', (tester) async {
    final adapter = FakeAdapter([FakeResponse(200, json: _snapshot)]);
    await tester.pumpWidget(_screen(adapter));
    await _settle(tester);
    expect(find.text('CPU 50.0% · 10.0 GB in 142 processes · 8 cores'), findsOneWidget);
    expect(find.text('Clamk'), findsOneWidget);
    expect(find.text('25.0% · 2.0 GB · 1 process'), findsOneWidget);
    // Busiest first: cargo (37.5%) before idle (1.3%).
    expect(tester.getCenter(find.text('cargo.exe · Build')).dy, lessThan(tester.getCenter(find.text('idle.exe')).dy));
    expect(find.text('claude.exe'), findsNothing);
    await tester.tap(find.text('Clamk'));
    await tester.pumpAndSettle();
    expect(find.text('claude.exe'), findsOneWidget);
    expect(adapter.requests.first.uri.toString(), endsWith('/agentmux/viewer/procs?filter='));
    await tester.pumpWidget(const SizedBox());
  });
}
