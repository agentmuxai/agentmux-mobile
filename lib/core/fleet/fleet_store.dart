import '../discovery/models/lan_instance.dart';
import '../discovery/network_environment.dart';
import 'channel_session.dart';
import 'cloud_instances.dart';

/// How a channel was found. LAN channels come and go on their own; channels
/// the user added (QR, manual) or the dev bootstrap are never hidden
/// automatically. A cloud channel comes from the account's install list
/// (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5): it has
/// no LAN endpoint and no session, and leaves when the list stops naming it.
enum EndpointSource { lan, manual, dev, cloud }

/// How the phone reaches a channel, for the route badge (spec section 3.3).
/// Display only: a message always goes by the channel's own endpoint.
enum ChannelRoute {
  /// Found on this network (mDNS, UDP, or a QR/manual private address).
  lan,

  /// Known only from the account's cloud install list.
  cloud,

  /// The same install seen both ways; reached over the LAN.
  lanAndCloud,

  /// A QR or manual entry whose address is not private.
  direct,
}

/// Spec P6, thresholds aligned with the desktop Swarm
/// (`SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md` section 4).
enum Presence { live, stale, gone }

const staleAfter = Duration(seconds: 60);
const goneAfter = Duration(seconds: 300);

/// A cloud install publishes every 60 s; three missed intervals dims it
/// (spec section 5). It is hidden only when the relay stops listing it, or
/// lists it as signed off.
const cloudStaleAfter = Duration(minutes: 3);

/// One channel endpoint and everything known about it.
class ChannelRecord {
  const ChannelRecord({
    required this.id,
    required this.hostname,
    required this.address,
    required this.port,
    required this.authKey,
    required this.version,
    required this.source,
    required this.lastSighting,
    this.channel,
    this.agents = const [],
    this.epoch,
    this.rev,
    this.lastContact,
    this.error,
    this.errorAt,
    this.os,
    this.installId,
    this.channelsRunning,
    this.viewerPort,
  });

  /// Stable for the record's lifetime; sessions and UI state key on it.
  final String id;
  final String hostname;
  final String address;
  final int port;
  final String authKey;
  final String version;
  final EndpointSource source;
  final String? channel;
  final List<LanAgent> agents;
  final String? epoch;
  final int? rev;

  /// Last successful answer from the channel itself.
  final DateTime? lastContact;

  /// Last time discovery saw it (mDNS record or UDP reply).
  final DateTime lastSighting;
  final ChannelError? error;
  final DateTime? errorAt;
  final String? os;
  final String? installId;
  final int? channelsRunning;
  final int? viewerPort;

  ChannelRecord copyWith({
    String? hostname,
    String? address,
    int? port,
    String? authKey,
    String? version,
    EndpointSource? source,
    String? channel,
    List<LanAgent>? agents,
    String? epoch,
    int? rev,
    DateTime? lastContact,
    DateTime? lastSighting,
    ChannelError? error,
    DateTime? errorAt,
    bool clearError = false,
    String? os,
    String? installId,
    int? channelsRunning,
    int? viewerPort,
  }) {
    return ChannelRecord(
      id: id,
      hostname: hostname ?? this.hostname,
      address: address ?? this.address,
      port: port ?? this.port,
      authKey: authKey ?? this.authKey,
      version: version ?? this.version,
      source: source ?? this.source,
      channel: channel ?? this.channel,
      agents: agents ?? this.agents,
      epoch: epoch ?? this.epoch,
      rev: rev ?? this.rev,
      lastContact: lastContact ?? this.lastContact,
      lastSighting: lastSighting ?? this.lastSighting,
      error: clearError ? null : (error ?? this.error),
      errorAt: clearError ? null : (errorAt ?? this.errorAt),
      os: os ?? this.os,
      installId: installId ?? this.installId,
      channelsRunning: channelsRunning ?? this.channelsRunning,
      viewerPort: viewerPort ?? this.viewerPort,
    );
  }

  /// The most recent proof of life, from either discovery or the channel.
  DateTime get lastAlive {
    final c = lastContact;
    return c != null && c.isAfter(lastSighting) ? c : lastSighting;
  }

  Presence presence(DateTime now) {
    final age = now.difference(lastAlive);
    if (source == EndpointSource.cloud) {
      return age < cloudStaleAfter ? Presence.live : Presence.stale;
    }
    if (age < staleAfter) return Presence.live;
    if (source != EndpointSource.lan || age < goneAfter) return Presence.stale;
    return Presence.gone;
  }

  /// The error worth showing: none while the channel itself answered within
  /// [staleAfter], so a stream that drops and reconnects within seconds never
  /// flashes one. Judged on contact alone: a channel discovery still sees but
  /// that has not answered for a minute has frozen agents, and says so.
  ChannelError? visibleError(DateTime now) {
    final c = lastContact;
    if (c != null && now.difference(c) < staleAfter) return null;
    return error;
  }

  /// The route badge for this endpoint alone; the tree turns a LAN channel
  /// and a cloud channel with the same install id into
  /// [ChannelRoute.lanAndCloud].
  ChannelRoute get route => switch (source) {
        EndpointSource.lan => ChannelRoute.lan,
        EndpointSource.cloud => ChannelRoute.cloud,
        EndpointSource.manual || EndpointSource.dev =>
          isPrivateAddress(address) ? ChannelRoute.lan : ChannelRoute.direct,
      };

  LanInstance toInstance() => LanInstance(
        hostname: hostname,
        version: version,
        address: address,
        port: port,
        authKey: authKey,
        channel: channel,
        os: os,
        installId: installId,
        channelsRunning: channelsRunning,
        viewerPort: viewerPort,
        agents: agents,
      );
}

/// A channel as discovery saw it, before it is matched to a record.
class Sighting {
  const Sighting({
    required this.hostname,
    required this.address,
    required this.port,
    required this.authKey,
    required this.version,
    this.channel,
    this.source = EndpointSource.lan,
    this.agents,
    this.os,
    this.installId,
    this.channelsRunning,
    this.viewerPort,
  });

  factory Sighting.fromInstance(
    LanInstance i, {
    EndpointSource source = EndpointSource.lan,
  }) =>
      Sighting(
        hostname: i.hostname,
        address: i.address,
        port: i.port,
        authKey: i.authKey,
        version: i.version,
        channel: i.channel,
        source: source,
        agents: i.agents.isEmpty ? null : i.agents,
        os: i.os,
        installId: i.installId,
        channelsRunning: i.channelsRunning,
        viewerPort: i.viewerPort,
      );

  final String hostname;
  final String address;
  final int port;
  final String authKey;
  final String version;
  final String? channel;
  final EndpointSource source;
  final List<LanAgent>? agents;
  final String? os;
  final String? installId;
  final int? channelsRunning;
  final int? viewerPort;
}

/// Whether two descriptions name the same channel (spec section 3).
///
/// Same non-empty hostname: the same channel when both report a channel name
/// and the names match, or, when either does not (an older srv), when the
/// ports match: several channels share a machine, each on its own port, and
/// the desktop's LAN listeners reuse the loopback port, so one process
/// reached two ways keeps its port. Without a hostname: address and port.
bool sameChannel({
  required String hostnameA,
  required String? channelA,
  required String addressA,
  required int portA,
  required String hostnameB,
  required String? channelB,
  required String addressB,
  required int portB,
}) {
  if (hostnameA.isNotEmpty &&
      hostnameA.toLowerCase() == hostnameB.toLowerCase()) {
    if (channelA != null && channelB != null) return channelA == channelB;
    return portA == portB;
  }
  return addressA == addressB && portA == portB;
}

/// What a sighting did to the store, so the owner knows which sessions to
/// start or restart.
enum SightingEffect { added, relocated, renewed }

/// The merged truth about every known channel. Immutable; every change
/// returns a new store. Pure, so it is tested without a network or a clock.
class FleetStore {
  const FleetStore([this.records = const {}]);

  final Map<String, ChannelRecord> records;

  ChannelRecord? _match(Sighting s) {
    for (final r in records.values) {
      // A cloud channel is never matched by name: only the tree joins it to a
      // LAN channel, and only by install id (spec section 5).
      if (r.source == EndpointSource.cloud) continue;
      if (sameChannel(
        hostnameA: r.hostname,
        channelA: r.channel,
        addressA: r.address,
        portA: r.port,
        hostnameB: s.hostname,
        channelB: s.channel,
        addressB: s.address,
        portB: s.port,
      )) {
        return r;
      }
    }
    return null;
  }

  /// Records a sighting. Returns the new store, the record's id, and whether
  /// its session must start (added) or restart (relocated).
  (FleetStore, String, SightingEffect) sight(
    Sighting s,
    DateTime now, {
    required String Function() newId,
  }) {
    final existing = _match(s);
    if (existing == null) {
      final id = newId();
      final record = ChannelRecord(
        id: id,
        hostname: s.hostname,
        address: s.address,
        port: s.port,
        authKey: s.authKey,
        version: s.version,
        source: s.source,
        channel: s.channel,
        agents: s.agents ?? const [],
        lastSighting: now,
        os: s.os,
        installId: s.installId,
        channelsRunning: s.channelsRunning,
        viewerPort: s.viewerPort,
      );
      return (_with(record), id, SightingEffect.added);
    }

    // A user-added or dev connection holds the stronger (full) key; a LAN
    // sighting of the same channel only proves it is still there.
    final keepLocator = existing.source != EndpointSource.lan &&
        s.source == EndpointSource.lan;
    // A restart on a new port or with a new key needs a new session. An
    // address change alone does not: a machine has several addresses (VPN
    // and VM adapters) and mDNS may name any of them, so keep the one that
    // works unless the channel is currently failing.
    final relocate = !keepLocator &&
        (existing.port != s.port ||
            existing.authKey != s.authKey ||
            (existing.address != s.address && existing.error != null));
    final updated = existing.copyWith(
      lastSighting: now,
      channel: s.channel,
      version: s.version.isEmpty ? null : s.version,
      address: relocate ? s.address : null,
      port: relocate ? s.port : null,
      authKey: relocate ? s.authKey : null,
      source: keepLocator ? null : s.source,
      clearError: relocate,
      os: s.os,
      installId: s.installId,
      channelsRunning: s.channelsRunning,
      viewerPort: s.viewerPort,
    );
    return (
      _with(updated),
      existing.id,
      relocate ? SightingEffect.relocated : SightingEffect.renewed,
    );
  }

  /// Applies a session's report for record [id].
  FleetStore apply(String id, SessionUpdate u, DateTime now) {
    final r = records[id];
    if (r == null) return this;
    switch (u) {
      case SessionFailure(:final error):
        return _with(r.copyWith(error: error, errorAt: now));
      case SessionContact():
        // Spec P2: within one epoch keep only the newest rev; a new epoch
        // (the srv restarted) replaces the state as-is.
        final staleRev = u.epoch != null &&
            u.epoch == r.epoch &&
            u.rev != null &&
            r.rev != null &&
            u.rev! <= r.rev!;
        final agents = staleRev ? null : u.agents;
        return _with(r.copyWith(
          lastContact: now,
          agents: agents,
          epoch: staleRev ? null : u.epoch,
          rev: staleRev ? null : u.rev,
          hostname: u.hostname,
          channel: u.channel,
          version: u.version,
          os: u.os,
          installId: u.installId,
          // A count change bumps `rev` like a name change, so it follows the
          // same rule as the agent list.
          channelsRunning: staleRev ? null : u.channelsRunning,
          viewerPort: u.viewerPort,
          clearError: true,
        ));
    }
  }

  /// Drops LAN records past [goneAfter]. Returns the new store and the ids
  /// removed, so their sessions can be stopped.
  (FleetStore, List<String>) prune(DateTime now) {
    final gone = [
      for (final r in records.values)
        if (r.presence(now) == Presence.gone) r.id,
    ];
    if (gone.isEmpty) return (this, const []);
    final next = Map<String, ChannelRecord>.of(records)
      ..removeWhere((k, _) => gone.contains(k));
    return (FleetStore(next), gone);
  }

  /// Replaces every cloud channel with [instances], the account's current
  /// install list: one record per install, keyed by its instance id so the
  /// record (and the UI state keyed on it) survives every refresh. An install
  /// the list no longer names is dropped (the relay stops listing it after
  /// 24 hours). LAN records are untouched.
  ///
  /// An install the list names as signed off ([CloudInstance.gone]) is
  /// dropped at once, like one it no longer names: it is not shown as live
  /// for the minutes its record would take to go stale, nor dimmed after.
  /// A LAN record of the same install is untouched and keeps its own LAN
  /// presence: an install that only signed out of the cloud, or stopped
  /// publishing, is still running on the LAN.
  FleetStore syncCloud(List<CloudInstance> instances) {
    final next = Map<String, ChannelRecord>.of(records)
      ..removeWhere((_, r) => r.source == EndpointSource.cloud);
    for (final c in instances) {
      if (c.gone) continue;
      final id = cloudRecordId(c.instanceId);
      next[id] = ChannelRecord(
        id: id,
        hostname: c.hostname,
        address: '',
        port: 0,
        authKey: '',
        version: c.version,
        source: EndpointSource.cloud,
        channel: c.channel,
        agents: c.agents,
        // The relay's receive time is the install's last proof of life.
        lastSighting: DateTime.fromMillisecondsSinceEpoch(c.receivedAtMs),
        os: c.os,
        installId: c.instanceId,
        channelsRunning: c.channelsRunning,
      );
    }
    return FleetStore(next);
  }

  /// Drops every cloud channel (signed out).
  FleetStore clearCloud() {
    if (!records.values.any((r) => r.source == EndpointSource.cloud)) {
      return this;
    }
    return syncCloud(const []);
  }

  static String cloudRecordId(String instanceId) => 'cloud:$instanceId';

  FleetStore remove(Iterable<String> ids) {
    final next = Map<String, ChannelRecord>.of(records)
      ..removeWhere((k, _) => ids.contains(k));
    return FleetStore(next);
  }

  FleetStore _with(ChannelRecord r) =>
      FleetStore(Map<String, ChannelRecord>.of(records)..[r.id] = r);
}
