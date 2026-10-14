import 'package:agentmux_mobile/core/discovery/host_tree.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/features/swarm/swarm_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _instance = LanInstance(
  hostname: 'narko',
  version: '0.60.0',
  address: '198.51.100.30',
  port: 29700,
  authKey: 'k',
  channel: 'stable',
);

ChannelNode _channel(List<LanAgent> agents) =>
    ChannelNode(name: 'stable', via: _instance, agents: agents);

void main() {
  const agents = [
    LanAgent(name: 'Loap', state: AgentState.idle),
    LanAgent(name: 'zed', state: AgentState.working),
    LanAgent(name: 'Clamk', state: AgentState.working),
    LanAgent(name: 'QTest', state: AgentState.waiting),
    LanAgent(name: 'Old', state: AgentState.stopped),
    LanAgent(name: 'Mute'),
  ];

  test('most active first, by name within a state', () {
    expect(swarmOrder(agents).map((a) => a.name), ['QTest', 'Clamk', 'zed', 'Loap', 'Old', 'Mute']);
  });

  test('the summary: the count, then working and waiting', () {
    expect(swarmSummary(agents), '6 agents · 2 working · 1 waiting');
    expect(swarmSummary(const [LanAgent(name: 'A', state: AgentState.idle)]), '1 agent');
    expect(swarmSummary(const []), '0 agents');
  });

  test('a channel is found by host and channel key', () {
    final c = _channel(agents);
    final host = HostNode(key: 'narko', name: 'narko', channels: [c]);
    expect(findChannel([host], 'narko', 'stable'), same(c));
    expect(findChannel([host], 'narko', 'other'), isNull);
    expect(findChannel([host], 'other', 'stable'), isNull);
  });

  testWidgets('the screen lists every agent, most active first', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SwarmScreen(hostKey: 'narko', channelKey: 'stable', initial: _channel(agents)),
      ),
    ));
    await tester.pump();
    expect(find.text('Swarm'), findsOneWidget);
    expect(find.text('narko  •  stable'), findsOneWidget);
    expect(find.text('6 agents · 2 working · 1 waiting'), findsOneWidget);
    final ys = [for (final n in ['QTest', 'Clamk', 'zed', 'Loap', 'Old', 'Mute']) tester.getCenter(find.text(n)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    await tester.pumpWidget(const SizedBox());
  });
}
