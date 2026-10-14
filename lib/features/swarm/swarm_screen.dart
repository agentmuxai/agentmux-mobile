import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../discovery/host_card.dart';

/// A channel's Swarm (`PLAN_CHANNEL_AS_ONE_LIST_2026_10_13.md` step 2): every
/// agent of the channel on one screen, most active first, as the desktop's
/// Swarm shows them. Built from what discovery already has: live as it
/// updates, read-only, and a tap opens an agent's feed.
class SwarmScreen extends ConsumerWidget {
  const SwarmScreen({
    super.key,
    required this.hostKey,
    required this.channelKey,
    this.initial,
  });

  final String hostKey;
  final String channelKey;

  /// The channel as the row that opened this screen had it, shown until
  /// discovery has the channel again (and if it goes).
  final ChannelNode? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoveryProvider);
    final channel = switch (state) {
          DiscoveryResults(:final hosts) => findChannel(hosts, hostKey, channelKey),
          _ => null,
        } ??
        initial;
    final agents = channel == null ? const <LanAgent>[] : swarmOrder(channel.agents);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Swarm'),
            if (channel != null)
              Text(
                [channel.via.hostname, channel.name].where((s) => s.isNotEmpty).join('  •  '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
          ],
        ),
      ),
      body: channel == null || agents.isEmpty
          ? const Center(
              child: Text('No agents on this channel now.', style: TextStyle(color: Colors.white54)),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    swarmSummary(channel.agents),
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ),
                for (final agent in agents)
                  AgentRow(
                    key: ValueKey('swarm:${agent.name.toLowerCase()}'),
                    agent: agent,
                    channel: channel,
                    indent: 16,
                  ),
              ],
            ),
    );
  }
}

/// [channelKey] of [hostKey] in [hosts], or null.
ChannelNode? findChannel(List<HostNode> hosts, String hostKey, String channelKey) {
  final host = hosts.where((h) => h.key == hostKey).firstOrNull;
  return host?.channels.where((c) => c.key == channelKey).firstOrNull;
}

/// Most active first: needs an answer, working, idle, then the rest; by name
/// within each.
List<LanAgent> swarmOrder(List<LanAgent> agents) {
  int rank(AgentState? s) => switch (s) {
        AgentState.waiting => 0,
        AgentState.working => 1,
        AgentState.idle => 2,
        AgentState.stopped => 3,
        AgentState.error => 4,
        null => 5,
      };
  return [...agents]
    ..sort((a, b) {
      final r = rank(a.state).compareTo(rank(b.state));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

/// "3 agents · 2 working · 1 waiting": the count, then each active state.
String swarmSummary(List<LanAgent> agents) {
  final n = agents.length;
  final working = agents.where((a) => a.state == AgentState.working).length;
  final waiting = agents.where((a) => a.state == AgentState.waiting).length;
  return [
    '$n ${n == 1 ? 'agent' : 'agents'}',
    if (working > 0) '$working working',
    if (waiting > 0) '$waiting waiting',
  ].join(' · ');
}

/// Opens [channel]'s Swarm.
void openSwarm(BuildContext context, String hostKey, ChannelNode channel) {
  context.push(
    '/swarm/${Uri.encodeComponent(hostKey)}/${Uri.encodeComponent(channel.key)}',
    extra: {'channel': channel},
  );
}
