import 'dart:math';

import '../fleet/channel_session.dart';
import '../fleet/fleet_store.dart';
import 'models/lan_instance.dart';

/// One discovered channel as the view needs it: what it reports, plus how
/// fresh that is, whether reading it failed, and how it is reached.
class FleetEntry {
  const FleetEntry({
    required this.instance,
    this.presence = Presence.live,
    this.error,
    this.lastSeen,
    this.route = ChannelRoute.lan,
  });

  final LanInstance instance;
  final Presence presence;
  final ChannelError? error;
  final DateTime? lastSeen;

  /// [ChannelRoute.cloud] for an entry from the cloud install list (its
  /// [LanInstance.installId] is the install's instance id, and it has no LAN
  /// endpoint); otherwise how its LAN endpoint was found.
  final ChannelRoute route;

  bool get isCloud => route == ChannelRoute.cloud;
}

/// A host's platform, from its `os` token. Only these three get a tag; any
/// other token, or none, shows nothing rather than a guess.
enum HostPlatform { windows, macos, linux }

HostPlatform? platformFromOs(String? os) => switch (os) {
      'windows' => HostPlatform.windows,
      'macos' => HostPlatform.macos,
      'linux' => HostPlatform.linux,
      _ => null,
    };

/// One channel (stable, dev, ...) on a host, with the agents it runs.
///
/// [via] is the discovered instance to talk to for this channel's agents: the
/// channel's own instance when it was discovered, otherwise a sibling on the
/// same host that reported these agents (the desktop forwards a message to
/// another channel on the same machine itself). For a channel known only from
/// the cloud list ([cloudOnly]) it carries the install's details and no
/// usable endpoint; its agents are reached through the cloud.
class ChannelNode {
  const ChannelNode({
    required this.name,
    required this.via,
    required this.agents,
    this.presence = Presence.live,
    this.error,
    this.lastSeen,
    this.route = ChannelRoute.lan,
    this.cloudOnly = false,
    String? key,
  }) : key = key ?? name;

  final String name;
  final LanInstance via;
  final List<LanAgent> agents;
  final Presence presence;
  final ChannelError? error;
  final DateTime? lastSeen;

  /// The route badge (spec section 3.3).
  final ChannelRoute route;

  /// No LAN endpoint at all: agents open the cloud agent screen.
  final bool cloudOnly;

  /// Identity within its host, for UI state: the channel name for a LAN
  /// channel, `cloud:<instance id>` for a cloud-only one (two installs may
  /// share a channel name).
  final String key;
}

/// One machine and the channels running on it.
class HostNode {
  HostNode({
    required this.name,
    required this.channels,
    this.os,
    this.channelsRunning,
    String? key,
  }) : key = key ?? 'host:${name.toLowerCase()}';

  final String name;
  final List<ChannelNode> channels;

  /// The platform token its channels report; null when none does.
  final String? os;

  /// The most channels any of its channels says the machine runs, including
  /// ones not shared on the LAN. Null when no channel reports it.
  final int? channelsRunning;

  /// Identity for UI state: the lower-cased host name, plus the platform
  /// when one name had to be split by platform (a Windows host and its WSL
  /// instance).
  final String key;

  HostPlatform? get platform => platformFromOs(os);

  /// The channel level is only worth showing when the machine runs more than
  /// one channel; a lone channel's agents hang directly off the host. What it
  /// runs counts, not what this phone can see (spec section 3.2).
  bool get showChannels => max(channels.length, channelsRunning ?? 0) > 1;

  /// Channels the machine runs that are not in [channels]: the `+N channels
  /// not shared on LAN` line. Zero when unknown.
  int get hiddenChannels => max(0, (channelsRunning ?? 0) - channels.length);

  /// The route shared by every channel, for the host row; null when they mix.
  ChannelRoute? get route {
    final routes = channels.map((c) => c.route).toSet();
    return routes.length == 1 ? routes.single : null;
  }

  /// The version shared by every channel, for the host row; null when they
  /// differ or none is known.
  String? get version {
    final versions = channels.map((c) => displayVersion(c.via.version)).toSet();
    return versions.length == 1 ? versions.single : null;
  }

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

/// A version worth showing: not the placeholders older routes report.
String? displayVersion(String version) =>
    version.isEmpty || version == '?' || version == 'unknown' ? null : version;

/// The label for an instance whose channel the desktop did not report.
/// A port is unique per srv on a host, so it still tells channels apart.
String channelLabel(LanInstance instance) =>
    instance.channel ?? ':${instance.port}';

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Groups discovered channels into host -> channel -> agents
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5).
///
/// A cloud entry and a LAN entry are one channel only when the LAN entry's
/// install id equals the cloud entry's instance id; never by name. Entries
/// are grouped into hosts by lower-cased hostname (address when a server
/// reports none), LAN and cloud alike, and a host whose channels report
/// different platforms is shown once per platform. Each LAN entry is one
/// channel; agents it reports for other channels on the same machine
/// (`LanAgent.channel`) are placed under those channels, merged with that
/// channel's own entry when it was discovered too. Hosts, channels and
/// agents are sorted by name so an update never reorders what is on screen.
List<HostNode> buildHostTrees(List<FleetEntry> entries) {
  final resolved = _mergeByInstallId(entries);

  final byName = <String, List<_Resolved>>{};
  for (final r in resolved) {
    final i = r.entry.instance;
    final key = (i.hostname.isNotEmpty ? i.hostname : i.address).toLowerCase();
    byName.putIfAbsent(key, () => []).add(r);
  }

  final built = <HostNode>[];
  for (final MapEntry(key: lower, value: group) in byName.entries) {
    final oses = {
      for (final r in group)
        if (r.entry.instance.os != null) r.entry.instance.os!,
    };
    if (oses.length <= 1) {
      built.add(_build(group, key: 'host:$lower', os: oses.firstOrNull));
      continue;
    }
    // Same name, different platforms: separate machines as far as the view
    // can tell (spec section 3.1). A channel that reports no platform cannot
    // be placed, so it gets its own, untagged, card.
    for (final os in [...oses]..sort()) {
      built.add(_build(
        group.where((r) => r.entry.instance.os == os),
        key: 'host:$lower/$os',
        os: os,
      ));
    }
    final unknown = group.where((r) => r.entry.instance.os == null);
    if (unknown.isNotEmpty) {
      built.add(_build(unknown, key: 'host:$lower/', os: null));
    }
  }
  built.sort((a, b) {
    final byHost = _byName(a.name, b.name);
    return byHost != 0 ? byHost : a.key.compareTo(b.key);
  });
  return built;
}

HostNode _build(Iterable<_Resolved> group, {required String key, String? os}) {
  final first = group.first.entry.instance;
  final builder =
      _HostBuilder(first.hostname.isNotEmpty ? first.hostname : first.address);
  for (final r in group) {
    builder.add(r);
  }
  return builder.build(key: key, os: os);
}

/// An entry after the LAN/cloud merge.
class _Resolved {
  const _Resolved(this.entry, {required this.cloudOnly});
  final FleetEntry entry;
  final bool cloudOnly;
}

List<_Resolved> _mergeByInstallId(List<FleetEntry> entries) {
  final cloudById = <String, FleetEntry>{
    for (final e in entries)
      if (e.isCloud && e.instance.installId != null) e.instance.installId!: e,
  };
  final used = <String>{};
  final result = <_Resolved>[];
  for (final e in entries) {
    if (e.isCloud) continue;
    final id = e.instance.installId;
    // Only the first LAN entry claiming an install id takes its cloud twin.
    final twin = id == null || used.contains(id) ? null : cloudById[id];
    if (twin == null) {
      result.add(_Resolved(e, cloudOnly: false));
      continue;
    }
    used.add(id!);
    result.add(_Resolved(_mergeChannel(e, twin), cloudOnly: false));
  }
  for (final e in entries) {
    if (!e.isCloud) continue;
    if (used.contains(e.instance.installId)) continue;
    result.add(_Resolved(e, cloudOnly: true));
  }
  return result;
}

/// One install seen both on the LAN and in the cloud list. It keeps the LAN
/// endpoint (a message goes over the LAN); its agents are the LAN list while
/// the LAN answers, the cloud list when only the cloud is current, with
/// kinds taken from whichever source has them.
///
/// Agent states come only from the list in use: the LAN's while the LAN is
/// live (live, and how long), the cloud's only when the LAN is not. A state
/// the LAN leaves out is unknown, never filled from an older cloud record
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` section 3).
FleetEntry _mergeChannel(FleetEntry lan, FleetEntry cloud) {
  final lanLive = lan.presence == Presence.live;
  final cloudLive = cloud.presence == Presence.live;
  final useCloud = !lanLive && cloudLive;
  final primary = useCloud ? cloud.instance.agents : lan.instance.agents;
  final other = useCloud ? lan.instance.agents : cloud.instance.agents;
  final otherKinds = {
    for (final a in other)
      if (a.kind != null) a.name.toLowerCase(): a.kind,
  };
  // `copyWith` keeps each agent's own state: a state is never taken from
  // [other].
  final agents = [
    for (final a in primary)
      a.kind != null ? a : a.copyWith(kind: otherKinds[a.name.toLowerCase()]),
  ];
  final l = lan.instance;
  final c = cloud.instance;
  final running = [l.channelsRunning, c.channelsRunning].whereType<int>();
  final lanSeen = lan.lastSeen;
  final cloudSeen = cloud.lastSeen;
  return FleetEntry(
    instance: l.copyWith(
      agents: agents,
      os: l.os ?? c.os,
      version: displayVersion(l.version) != null ? l.version : c.version,
      channelsRunning: running.isEmpty ? null : running.reduce(max),
    ),
    presence: lanLive || cloudLive ? Presence.live : lan.presence,
    // The LAN's failure is not news while the cloud list stands in for it.
    error: useCloud ? null : lan.error,
    lastSeen: lanSeen == null
        ? cloudSeen
        : (cloudSeen != null && cloudSeen.isAfter(lanSeen) ? cloudSeen : lanSeen),
    route: switch ((lanLive, cloudLive)) {
      (true, false) => lan.route,
      (false, true) => ChannelRoute.cloud,
      _ => ChannelRoute.lanAndCloud,
    },
  );
}

class _ChannelBuilder {
  _ChannelBuilder(this.key, this.name, this.entry,
      {required this.own, this.cloudOnly = false});

  final String key;
  final String name;

  /// The entry that reported this channel; its own entry once seen.
  FleetEntry entry;

  /// Whether [entry] is this channel's own instance, not a sibling's report.
  bool own;
  final bool cloudOnly;
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
  int? _channelsRunning;

  void add(_Resolved resolved) {
    final entry = resolved.entry;
    final instance = entry.instance;
    final running = instance.channelsRunning;
    if (running != null) {
      _channelsRunning = max(_channelsRunning ?? 0, running);
    }

    if (resolved.cloudOnly) {
      // Its own channel, keyed by install: a cloud channel never merges with
      // a LAN channel by name, even one with the same name.
      final key = 'cloud:${instance.installId}';
      final c = _channels[key] = _ChannelBuilder(
        key,
        channelLabel(instance),
        entry,
        own: true,
        cloudOnly: true,
      );
      instance.agents.forEach(c.addAgent);
      return;
    }

    final ownName = channelLabel(instance);
    // The instance itself is the authority for its own channel, even if a
    // sibling already created that channel from its agent list.
    final own = _channels.putIfAbsent(
      ownName,
      () => _ChannelBuilder(ownName, ownName, entry, own: true),
    )
      ..entry = entry
      ..own = true;

    for (final agent in instance.agents) {
      final tag = agent.channel;
      if (tag == null || tag == ownName) {
        own.addAgent(agent);
      } else {
        _channels
            .putIfAbsent(
                tag, () => _ChannelBuilder(tag, tag, entry, own: false))
            .addAgent(agent);
      }
    }
  }

  HostNode build({required String key, String? os}) {
    final channels = [
      for (final c in _channels.values)
        ChannelNode(
          key: c.key,
          name: c.name,
          via: c.entry.instance,
          agents: [...c.agents]..sort((a, b) => _byName(a.name, b.name)),
          presence: c.entry.presence,
          // A sibling's failure is not this channel's.
          error: c.own ? c.entry.error : null,
          lastSeen: c.entry.lastSeen,
          route: c.entry.route,
          cloudOnly: c.cloudOnly,
        ),
    ]..sort((a, b) {
        final byChannel = _byName(a.name, b.name);
        return byChannel != 0 ? byChannel : a.key.compareTo(b.key);
      });
    return HostNode(
      key: key,
      name: name,
      channels: channels,
      os: os,
      channelsRunning: _channelsRunning,
    );
  }
}
