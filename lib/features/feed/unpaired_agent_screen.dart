import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/fleet_store.dart';
import '../../core/viewer/paired_match.dart';
import '../../shared/widgets/tag_chip.dart';
import '../discovery/host_card.dart';
import '../discovery/qr_scan_screen.dart';

/// What tapping an agent opens when this device has not paired with its
/// computer (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 6.1): the
/// live feed needs a pairing, so this says so and offers the scanner. Once
/// paired with this agent's channel it opens the feed in its place.
class UnpairedAgentScreen extends StatelessWidget {
  const UnpairedAgentScreen({
    super.key,
    required this.instance,
    required this.agent,
    this.channel,
    this.route,
  });

  final LanInstance instance;
  final LanAgent agent;
  final String? channel;
  final ChannelRoute? route;

  Future<void> _pair(BuildContext context) async {
    final paired = await showQrScanScreen(context);
    if (paired == null || !context.mounted) return;
    final node = ChannelNode(
      name: channel ?? channelLabel(instance),
      via: instance,
      agents: [agent],
      route: route ?? ChannelRoute.lan,
    );
    final match = matchPairing(node, [paired]);
    // Paired with some other computer or channel: stay here.
    if (match == null) return;
    final pairedNode = node.withPairing(match);
    context.pushReplacement(agentLocation(pairedNode, agent), extra: {
      'instance': instance,
      'agent': agent,
      'route': route,
      'channel': node.name,
      'pairing': match,
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = agent.kind;
    final hostname =
        instance.hostname.isNotEmpty ? instance.hostname : instance.address;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text(agent.name, overflow: TextOverflow.ellipsis)),
            if (kind != null) ...[
              const SizedBox(width: 8),
              TagChip.agentKind(kind),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'More',
            onSelected: (_) =>
                openMessageScreen(context, instance, agent, route: route),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('Send a message…')),
            ],
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              Text(
                '$hostname isn\'t paired with this device',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'To watch this agent live, choose "Pair a device" in AgentMux '
                'on the computer and scan the code it shows.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Pair this computer'),
                onPressed: () => _pair(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
