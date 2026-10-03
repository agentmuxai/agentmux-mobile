import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/channel_session.dart';
import '../../core/fleet/fleet_store.dart';

/// A machine and what runs on it, as a tree: host -> channel -> agents.
///
/// The channel level only appears when the host runs more than one channel; a
/// single channel's agents hang directly off the host. A host or channel that
/// has gone quiet is dimmed with its last-seen age, and a channel that cannot
/// be read says why instead of showing an empty list.
class HostCard extends StatelessWidget {
  const HostCard({super.key, required this.host});
  final HostNode host;

  @override
  Widget build(BuildContext context) {
    final channels = host.channels;
    final only = channels.first;
    final live = host.presence == Presence.live;
    return Opacity(
      opacity: live ? 1 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          // The tile's expanded state follows the host, not its position.
          key: PageStorageKey('host:${host.name.toLowerCase()}'),
          leading: Icon(
            Icons.computer,
            color: live ? Colors.greenAccent : Colors.white38,
          ),
          title: Text(
            host.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _hostSubtitle(host, only),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          initiallyExpanded: true,
          children: host.showChannels
              ? [
                  for (final c in channels)
                    _ChannelTile(
                      key: PageStorageKey(
                          'channel:${host.name.toLowerCase()}/${c.name}'),
                      channel: c,
                    ),
                ]
              : _agentRows(only, indent: 20),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({super.key, required this.channel});
  final ChannelNode channel;

  @override
  Widget build(BuildContext context) {
    final live = channel.presence == Presence.live;
    return Opacity(
      opacity: live ? 1 : 0.6,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(
          Icons.account_tree_outlined,
          size: 18,
          color: live ? Colors.white54 : Colors.white24,
        ),
        title: Text(channel.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          _channelStatus(channel),
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        initiallyExpanded: true,
        children: _agentRows(channel, indent: 36),
      ),
    );
  }
}

String _endpoint(LanInstance i) => 'v${i.version}  •  ${i.address}:${i.port}';

String _hostSubtitle(HostNode host, ChannelNode only) {
  if (!host.showChannels) return _channelStatus(only);
  final count = '${host.channels.length} channels';
  if (host.presence == Presence.live) return count;
  final seen = host.lastSeen;
  return seen == null ? count : '$count  •  last seen ${_ago(seen)}';
}

/// The endpoint, plus why the channel is not current when it is not.
String _channelStatus(ChannelNode c) {
  final parts = [_endpoint(c.via)];
  final error = c.error;
  if (error != null) parts.add(_errorText(error));
  if (c.presence != Presence.live && c.lastSeen != null) {
    parts.add('last seen ${_ago(c.lastSeen!)}');
  }
  return parts.join('  •  ');
}

String _errorText(ChannelError e) => switch (e) {
      ChannelError.unreachable => 'unreachable',
      ChannelError.unauthorized => 'not authorised',
    };

String _ago(DateTime t) {
  final diff = clock.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  return '${diff.inHours} h ago';
}

List<Widget> _agentRows(ChannelNode channel, {required double indent}) {
  if (channel.agents.isEmpty) {
    // An unreadable channel already says why in its status line; this line
    // is only for a channel that answered and has no agents.
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(indent, 0, 16, 12),
        child: Text(
          channel.error == null ? 'No agents reported.' : 'Agents unknown.',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ),
    ];
  }
  return [
    for (final agent in channel.agents)
      _AgentRow(
        key: ValueKey('agent:${agent.name.toLowerCase()}'),
        agent: agent,
        instance: channel.via,
        channelLive: channel.presence == Presence.live,
        indent: indent,
      ),
  ];
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    super.key,
    required this.agent,
    required this.instance,
    required this.channelLive,
    required this.indent,
  });
  final LanAgent agent;
  final LanInstance instance;
  final bool channelLive;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final lastSeen = agent.lastSeen;
    // A full-key connection reports each agent's last-seen time. A LAN one
    // reports names only, and those names are the agents its channel has
    // registered as reachable, so they are as current as the channel.
    final isActive = lastSeen != null ? _isRecent(lastSeen) : channelLive;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: indent),
      leading: Icon(
        Icons.circle,
        size: 10,
        color: isActive ? Colors.greenAccent : Colors.white24,
      ),
      title: Text(agent.name),
      subtitle: lastSeen != null
          ? Text(
              _formatLastSeen(lastSeen),
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            )
          : null,
      onTap: () => context.push(
        '/instance/${Uri.encodeComponent('${instance.address}:${instance.port}')}/agent/${Uri.encodeComponent(agent.name)}',
        extra: {'instance': instance, 'agent': agent},
      ),
    );
  }

  bool _isRecent(int lastSeenMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
    return clock.now().difference(dt).inMinutes < 5;
  }

  String _formatLastSeen(int lastSeenMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
    final diff = clock.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
