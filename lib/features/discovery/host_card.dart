import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/channel_session.dart';
import '../../core/fleet/cloud_instance_source.dart';
import '../../core/fleet/fleet_store.dart';
import '../../core/viewer/paired_host.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/agent_state_chip.dart';
import '../../shared/widgets/tag_chip.dart';

/// What happens when an agent row is tapped; the demo screen replaces the
/// default navigation with its own.
typedef AgentTap = void Function(
    BuildContext context, ChannelNode channel, LanAgent agent);

/// Forget a pairing on this device (the host card's long-press menu).
typedef UnpairCallback = void Function(PairedHost host);

/// A machine and what runs on it, as a tree: host -> channel -> agents.
///
/// The host row carries the name, platform, route and version
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 3.6); the
/// address lives on the agent screen. The channel level only appears when
/// the machine runs more than one channel; a single channel's agents hang
/// directly off the host. A host or channel that has gone quiet is dimmed
/// with its last-seen age, and a channel that cannot be read says why
/// instead of showing an empty list.
///
/// A channel this device has paired with carries a "Paired" tag, on the host
/// row when the channel level is not shown; long-pressing the card offers to
/// unpair it ([onUnpair]).
class HostCard extends StatelessWidget {
  const HostCard({
    super.key,
    required this.host,
    this.onAgentTap,
    this.onUnpair,
  });
  final HostNode host;
  final AgentTap? onAgentTap;
  final UnpairCallback? onUnpair;

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
    final paired = [
      for (final c in channels)
        if (c.pairing != null) c,
    ];
    final unpair = onUnpair;
    return Opacity(
      opacity: live ? 1 : 0.5,
      child: GestureDetector(
        onLongPress: paired.isEmpty || unpair == null
            ? null
            : () => _showUnpairSheet(context, host, paired, unpair),
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
                      if (!host.showChannels && only.pairing != null)
                        pairedTag(only.pairing!.paired),
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
      ),
    );
  }
}

/// "Paired", or "Pair again" once the computer has refused this device.
Widget pairedTag(PairedHost paired) => paired.invalid
    ? const TagChip(
        label: 'Pair again',
        color: AppColors.warning,
        tooltip: 'This device was unpaired on the computer',
      )
    : const TagChip(
        label: 'Paired',
        color: AppColors.primary,
        tooltip: 'This device can watch these agents live',
      );

void _showUnpairSheet(
  BuildContext context,
  HostNode host,
  List<ChannelNode> paired,
  UnpairCallback onUnpair,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in paired)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: Text(host.showChannels
                  ? 'Unpair ${c.name}'
                  : 'Unpair ${host.name}'),
              subtitle: const Text(
                'This device stops watching its agents. Revoke it in '
                'AgentMux on the computer too.',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onUnpair(c.pairing!.paired);
              },
            ),
        ],
      ),
    ),
  );
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
            if (channel.pairing != null) ...[
              const SizedBox(width: 6),
              pairedTag(channel.pairing!.paired),
            ],
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
  final silentSince = c.notPublishingSince;
  if (silentSince != null) {
    parts.add(notPublishingText(clock.now().difference(silentSince)));
  }
  return parts.isEmpty ? null : parts.join('  •  ');
}

/// For a channel that answers on the LAN while its cloud record has gone
/// stale (install presence spec, section 3.7): devices off this network see
/// it dimmed, and this says why.
String notPublishingText(Duration silent) {
  final minutes = max(0, silent.inMinutes);
  final span = minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';
  return 'this computer has not published for $span';
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
    // After HOST / SANDBOX, what the agent is doing (spec 6.3). Rows keep
    // their order whatever the state.
    final state = AgentStateChip.forAgent(
      agent,
      live: channel.presence == Presence.live,
    );

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: indent),
      leading: Icon(
        Icons.circle,
        size: 10,
        color: isActive ? Colors.greenAccent : Colors.white24,
      ),
      title: _NameAndTags(
        name: agent.name,
        // No tag when the kind or state is not reported: never a guess.
        tags: [
          if (kind != null) TagChip.agentKind(kind),
          if (state != null) state,
        ],
      ),
      subtitle: lastSeen != null
          ? Text(
              _formatLastSeen(lastSeen),
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            )
          : null,
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

/// An agent's name with its tags (HOST / SANDBOX, then its state) at the
/// right. The tags never take the whole row: the name keeps [_minName], or
/// 40% of a narrower row, and tags past the rest wrap onto another line, so
/// a long name keeps room on a narrow device and nothing overflows.
class _NameAndTags extends StatelessWidget {
  const _NameAndTags({required this.name, required this.tags});
  final String name;
  final List<Widget> tags;

  static const _minName = 96.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final title = Text(name);
    if (tags.isEmpty) return title;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tagShare =
            max(0.0, width - _gap - min(_minName, width * 0.4));
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: _gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tagShare),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: tags,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where an agent row leads. An agent reached only through the cloud (a
/// channel known only from the cloud list) opens the cloud agent screen, as
/// before (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5).
/// Otherwise tapping an agent opens its live feed
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 6.1) when this
/// device has paired with its channel; when it has not, a screen that says so
/// and offers to pair, unless the channel is only current through the cloud
/// (a merged channel whose LAN endpoint has gone quiet), which keeps the
/// cloud screen.
String agentLocation(ChannelNode channel, LanAgent agent) {
  final name = Uri.encodeComponent(agent.name);
  if (channel.cloudOnly) return '/agents/$name';
  final pairing = channel.pairing;
  if (pairing != null) {
    return '/viewer/${Uri.encodeComponent(pairing.paired.id)}/agent/$name';
  }
  if (channel.route == ChannelRoute.cloud) return '/agents/$name';
  return '${messageLocation(channel.via, agent)}/unpaired';
}

/// Today's "send a message" screen for [agent] of [instance].
String messageLocation(LanInstance instance, LanAgent agent) =>
    '/instance/${Uri.encodeComponent('${instance.address}:${instance.port}')}'
    '/agent/${Uri.encodeComponent(agent.name)}';

void openAgent(BuildContext context, ChannelNode channel, LanAgent agent) {
  final location = agentLocation(channel, agent);
  if (location.startsWith('/agents/')) {
    context.push(location);
    return;
  }
  context.push(location, extra: {
    'instance': channel.via,
    'agent': agent,
    'route': channel.route,
    'channel': channel.name,
    if (channel.pairing != null) 'pairing': channel.pairing,
  });
}

/// Opens the "send a message" screen (the feed screen's menu).
void openMessageScreen(
  BuildContext context,
  LanInstance instance,
  LanAgent agent, {
  ChannelRoute? route,
}) {
  context.push(messageLocation(instance, agent), extra: {
    'instance': instance,
    'agent': agent,
    'route': route,
  });
}
