import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/channel_session.dart';
import '../../core/fleet/cloud_instance_source.dart';
import '../../core/fleet/fleet_store.dart';
import '../../shared/widgets/tag_chip.dart';

/// What happens when an agent row is tapped; the demo screen replaces the
/// default navigation with its own.
typedef AgentTap = void Function(
    BuildContext context, ChannelNode channel, LanAgent agent);

/// A machine and what runs on it, as a tree: host -> channel -> agents.
///
/// The host row carries the name, platform, route and version
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 3.6); the
/// address lives on the agent screen. The channel level only appears when
/// the machine runs more than one channel; a single channel's agents hang
/// directly off the host. A host or channel that has gone quiet is dimmed
/// with its last-seen age, and a channel that cannot be read says why
/// instead of showing an empty list.
class HostCard extends StatelessWidget {
  const HostCard({super.key, required this.host, this.onAgentTap});
  final HostNode host;
  final AgentTap? onAgentTap;

  @override
  Widget build(BuildContext context) {
    final channels = host.channels;
    final only = channels.first;
    final live = host.presence == Presence.live;
    final platform = host.platform;
    final route = host.route;
    final version = host.version;
    final subtitle = _hostSubtitle(host, only);
    final hidden = host.hiddenChannels;
    return Opacity(
      opacity: live ? 1 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          // The tile's expanded state follows the host, not its position.
          key: PageStorageKey(host.key),
          leading: Icon(
            Icons.computer,
            color: live ? Colors.greenAccent : Colors.white38,
          ),
          title: Row(
            children: [
              // The tags follow the name and wrap under it on a narrow
              // screen rather than overflow.
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      host.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (platform != null) TagChip.platform(platform),
                    // Channels that mix routes carry their own badges instead.
                    if (route != null) TagChip.route(route),
                  ],
                ),
              ),
              if (version != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'v$version',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
            ],
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
          initiallyExpanded: true,
          children: host.showChannels
              ? [
                  for (final c in channels)
                    _ChannelTile(
                      key: PageStorageKey('channel:${host.key}/${c.key}'),
                      channel: c,
                      showVersion: version == null,
                      onAgentTap: onAgentTap,
                    ),
                  if (hidden > 0) _HiddenChannelsLine(count: hidden),
                ]
              : _agentRows(only, indent: 20, onAgentTap: onAgentTap),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    super.key,
    required this.channel,
    required this.showVersion,
    this.onAgentTap,
  });
  final ChannelNode channel;
  final bool showVersion;
  final AgentTap? onAgentTap;

  @override
  Widget build(BuildContext context) {
    final live = channel.presence == Presence.live;
    final status = _channelStatus(channel, showVersion: showVersion);
    return Opacity(
      opacity: live ? 1 : 0.6,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(
          Icons.account_tree_outlined,
          size: 18,
          color: live ? Colors.white54 : Colors.white24,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                channel.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 6),
            TagChip.route(channel.route),
          ],
        ),
        subtitle: status == null
            ? null
            : Text(
                status,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
        initiallyExpanded: true,
        children: _agentRows(channel, indent: 36, onAgentTap: onAgentTap),
      ),
    );
  }
}

/// The channels a host runs that this phone cannot see (spec section 3.2):
/// a count only, never names.
class _HiddenChannelsLine extends StatelessWidget {
  const _HiddenChannelsLine({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          hiddenChannelsText(count),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ),
    );
  }
}

String hiddenChannelsText(int count) =>
    '+$count ${count == 1 ? 'channel' : 'channels'} not shared on LAN';

/// The line under the host list about the cloud list (spec section 3.5), so
/// the list never implies it is everything. Null when there is nothing to
/// say.
String? cloudNoteText(CloudListStatus status) => switch (status) {
      CloudListStatus.signedOut => 'Cloud hosts are not shown (not signed in)',
      CloudListStatus.unavailable => 'Cloud hosts unavailable',
      CloudListStatus.pending ||
      CloudListStatus.ok ||
      CloudListStatus.unsupported =>
        null,
    };

class CloudNote extends StatelessWidget {
  const CloudNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}

String? _hostSubtitle(HostNode host, ChannelNode only) {
  if (!host.showChannels) return _channelStatus(only, showVersion: false);
  final n = max(host.channels.length, host.channelsRunning ?? 0);
  final count = '$n channels';
  if (host.presence == Presence.live) return count;
  final seen = host.lastSeen;
  return seen == null ? count : '$count  •  last seen ${_ago(seen)}';
}

/// Why the channel is not current, when it is not, plus its version when the
/// host row cannot carry one for every channel. Null when there is nothing
/// to say.
String? _channelStatus(ChannelNode c, {required bool showVersion}) {
  final parts = <String>[];
  final version = displayVersion(c.via.version);
  if (showVersion && version != null) parts.add('v$version');
  final error = c.error;
  if (error != null) parts.add(_errorText(error));
  if (c.presence != Presence.live && c.lastSeen != null) {
    parts.add('last seen ${_ago(c.lastSeen!)}');
  }
  return parts.isEmpty ? null : parts.join('  •  ');
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

List<Widget> _agentRows(
  ChannelNode channel, {
  required double indent,
  AgentTap? onAgentTap,
}) {
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
        channel: channel,
        indent: indent,
        onTap: onAgentTap,
      ),
  ];
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    super.key,
    required this.agent,
    required this.channel,
    required this.indent,
    this.onTap,
  });
  final LanAgent agent;
  final ChannelNode channel;
  final double indent;
  final AgentTap? onTap;

  @override
  Widget build(BuildContext context) {
    final lastSeen = agent.lastSeen;
    // A full-key connection reports each agent's last-seen time. A LAN one
    // reports names only, and those names are the agents its channel has
    // registered as reachable, so they are as current as the channel.
    final isActive = lastSeen != null
        ? _isRecent(lastSeen)
        : channel.presence == Presence.live;
    final kind = agent.kind;

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
      // No tag when the kind is not reported: never a guess.
      trailing: kind == null ? null : TagChip.agentKind(kind),
      onTap: () => (onTap ?? openAgent)(context, channel, agent),
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

/// Where an agent row leads (spec section 5): an agent reached through the
/// cloud (a channel known only from the cloud list, or a merged one whose LAN
/// endpoint has gone quiet) opens the cloud agent screen; otherwise the LAN
/// screen, which sends over its own channel's LAN endpoint.
@visibleForTesting
String agentLocation(ChannelNode channel, LanAgent agent) {
  if (_viaCloud(channel)) return '/agents/${Uri.encodeComponent(agent.name)}';
  final i = channel.via;
  return '/instance/${Uri.encodeComponent('${i.address}:${i.port}')}'
      '/agent/${Uri.encodeComponent(agent.name)}';
}

bool _viaCloud(ChannelNode channel) =>
    channel.cloudOnly || channel.route == ChannelRoute.cloud;

void openAgent(BuildContext context, ChannelNode channel, LanAgent agent) {
  final location = agentLocation(channel, agent);
  if (_viaCloud(channel)) {
    context.push(location);
    return;
  }
  context.push(location, extra: {
    'instance': channel.via,
    'agent': agent,
    'route': channel.route,
  });
}
