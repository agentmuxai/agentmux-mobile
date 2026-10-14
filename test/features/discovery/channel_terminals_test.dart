import 'package:agentmux_mobile/core/viewer/paired_host.dart';
import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:agentmux_mobile/core/viewer/pairing_service.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/discovery/channel_terminals.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/viewer/viewer_fakes.dart';

Map<String, Object?> _pane(String id, String kind, String tab, {String label = ''}) => {
      'block_id': id,
      'kind': kind,
      'view': kind == 'terminal' ? 'term' : kind,
      'label': label,
      'window_id': 'w1',
      'window': 'Main',
      'tab_id': 't-$tab',
      'tab': tab,
    };

void main() {
  late InMemorySecureStore store;

  Future<ProviderContainer> container(FakeAdapter adapter, {bool invalid = false}) async {
    store = InMemorySecureStore();
    await PairedHostsRepository(store).save([testPairedHost(invalid: invalid)]);
    final c = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(store),
      viewerClientFactoryProvider.overrideWithValue(
        ({required host, required port, required fingerprint, token}) => ViewerClient(
          host: host,
          port: port,
          fingerprint: fingerprint,
          token: token,
          adapter: adapter,
        ),
      ),
    ]);
    addTearDown(c.dispose);
    c.read(pairedHostsProvider);
    await c.read(pairedHostsProvider.notifier).ready;
    return c;
  }

  PanesKey key() => (pairId: 'p1', host: '198.51.100.30', port: 29800);

  Future<ChannelPanes> read(ProviderContainer c) async {
    final sub = c.listen(channelPanesProvider(key()), (_, __) {});
    addTearDown(sub.close);
    return c.read(channelPanesProvider(key()).future);
  }

  test('terminals only, in the order the computer gives', () async {
    final c = await container(FakeAdapter([
      FakeResponse(200, json: {
        'terminals_shared': true,
        'panes': [
          _pane('a1', 'agent', 'Tab 1'),
          _pane('b1', 'terminal', 'Tab 2', label: 'cargo build'),
          _pane('e1', 'other', 'Tab 2'),
          _pane('b2', 'terminal', 'Tab 1', label: 'pwsh'),
        ],
      }),
    ]));
    final panes = await read(c) as PanesListed;
    expect(panes.shared, isTrue);
    expect(panes.terminals.map((t) => t.blockId), ['b1', 'b2']);
  });

  test('a 404 is an older AgentMux; a 401 unpairs', () async {
    expect(await read(await container(FakeAdapter([const FakeResponse(404)]))), isA<PanesTooOld>());
    final c = await container(FakeAdapter([const FakeResponse(401)]));
    expect(await read(c), isA<PanesUnpaired>());
    expect(c.read(pairedHostsProvider).single.invalid, isTrue);
  });

  test('a refused pairing isn\'t asked', () async {
    final adapter = FakeAdapter([const FakeResponse(200, json: {'panes': []})]);
    final c = await container(adapter, invalid: true);
    expect(await read(c), isA<PanesUnpaired>());
    expect(adapter.requests, isEmpty);
  });

  test('titles and second lines', () {
    ViewerPane t({String label = '', bool? running, String? parent}) => ViewerPane(
          blockId: 'b',
          view: 'term',
          kind: PaneKind.terminal,
          label: label,
          windowId: 'w',
          window: '',
          tabId: 't',
          tab: '',
          running: running,
          parentBlockId: parent,
        );
    expect(terminalTitle(t(label: 'cargo build')), 'cargo build');
    expect(terminalTitle(t()), 'Terminal');
    expect(terminalTitle(t(parent: 'a')), "Agent's shell");
    expect(terminalSubtitle(t(running: true)), 'running · watch live');
    expect(terminalSubtitle(t(label: 'npm test', parent: 'a', running: false)), "Agent's shell · stopped · watch live");
    expect(terminalSubtitle(t()), 'watch live');
  });

  test('the key is the pairing and where it was reached', () {
    final pairing = PairingMatch(paired: testPairedHost(), host: '198.51.100.30', port: 29800);
    expect(panesKeyOf(pairing), key());
  });
}
