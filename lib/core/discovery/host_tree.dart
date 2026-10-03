import '../fleet/channel_session.dart';
import '../fleet/fleet_store.dart';
import 'models/lan_instance.dart';

/// One discovered channel as the view needs it: what it reports, plus how
/// fresh that is and whether reading it failed.
class FleetEntry {
  const FleetEntry({
    required this.instance,
    this.presence = Presence.live,
    this.error,
    this.lastSeen,
  });

  final LanInstance instance;
  final Presence presence;
  final ChannelError? error;
  final DateTime? lastSeen;
}

/// One channel (stable, dev, ...) on a host, with the agents it runs.
///
/// [via] is the discovered instance to talk to for this channel's agents: the
/// channel's own instance when it was discovered, otherwise a sibling on the
/// same host that reported these agents (the desktop forwards a message to
/// another channel on the same machine itself).
class ChannelNode {
  const ChannelNode({
    required this.name,
    required this.via,
    required this.agents,
    this.presence = Presence.live,
    this.error,
    this.lastSeen,
  });

  final String name;
  final LanInstance via;
  final List<LanAgent> agents;
  final Presence presence;
  final ChannelError? error;
  final DateTime? lastSeen;
}

/// One machine and the channels running on it.
class HostNode {
  const HostNode({required this.name, required this.channels});

  final String name;
  final List<ChannelNode> channels;

  /// The channel level is only worth showing when there is more than one
  /// channel to tell apart; a lone channel's agents hang directly off the host.
  bool get showChannels => channels.length > 1;

  /// Live if any channel is.
  Presence get presence => channels.any((c) => c.presence == Presence.live)
      ? Presence.live
      : Presence.stale;

  DateTime? get lastSeen {
    DateTime? newest;
    for (final c in channels) {
      final t = c.lastSeen;
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return newest;
  }
}

/// The label for an instance whose channel the desktop did not report.
/// A port is unique per srv on a host, so it still tells channels apart.
String channelLabel(LanInstance instance) =>
    instance.channel ?? ':${instance.port}';

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Groups discovered channels into host -> channel -> agents.
///
/// Entries are grouped by hostname (address when a server reports none).
/// Each entry is one channel; agents it reports for other channels on the
/// same machine (`LanAgent.channel`) are placed under those channels, merged
/// with that channel's own entry when it was discovered too. Hosts, channels
/// and agents are sorted by name so an update never reorders what is on
/// screen.
List<HostNode> buildHostTrees(List<FleetEntry> entries) {
  final hosts = <String, _HostBuilder>{};
  for (final entry in entries) {
    final i = entry.instance;
    final key = (i.hostname.isNotEmpty ? i.hostname : i.address).toLowerCase();
    hosts
        .putIfAbsent(
          key,
          () => _HostBuilder(i.hostname.isNotEmpty ? i.hostname : i.address),
        )
        .add(entry);
  }
  final built = hosts.values.map((h) => h.build()).toList()
    ..sort((a, b) => _byName(a.name, b.name));
  return built;
}

class _ChannelBuilder {
  _ChannelBuilder(this.name, this.entry, {required this.own});

  final String name;

  /// The entry that reported this channel; its own entry once seen.
  FleetEntry entry;

  /// Whether [entry] is this channel's own instance, not a sibling's report.
  bool own;
  final List<LanAgent> agents = [];

  void addAgent(LanAgent agent) {
    final lower = agent.name.toLowerCase();
    if (agents.any((a) => a.name.toLowerCase() == lower)) return;
    agents.add(agent);
  }
}

class _HostBuilder {
  _HostBuilder(this.name);

  final String name;
  final _channels = <String, _ChannelBuilder>{};

  void add(FleetEntry entry) {
    final instance = entry.instance;
    final ownName = channelLabel(instance);
    // The instance itself is the authority for its own channel, even if a
    // sibling already created that channel from its agent list.
    final own = _channels.putIfAbsent(
      ownName,
      () => _ChannelBuilder(ownName, entry, own: true),
    )
      ..entry = entry
      ..own = true;

    for (final agent in instance.agents) {
      final tag = agent.channel;
      if (tag == null || tag == ownName) {
        own.addAgent(agent);
      } else {
        _channels
            .putIfAbsent(tag, () => _ChannelBuilder(tag, entry, own: false))
            .addAgent(agent);
      }
    }
  }

  HostNode build() {
    final channels = [
      for (final c in _channels.values)
        ChannelNode(
          name: c.name,
          via: c.entry.instance,
          agents: [...c.agents]..sort((a, b) => _byName(a.name, b.name)),
          presence: c.entry.presence,
          // A sibling's failure is not this channel's.
          error: c.own ? c.entry.error : null,
          lastSeen: c.entry.lastSeen,
        ),
    ]..sort((a, b) => _byName(a.name, b.name));
    return HostNode(name: name, channels: channels);
  }
}
