import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';

/// One AgentMux install (a channel on a machine) as the account's cloud list
/// (`GET /wan-instances`) reports it. See
/// `docs/specs/SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5.
///
/// Every field is bounded: it is display data that came off another machine.
///
/// A `v: 2` record's agents may carry `state`
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` section 13.1); a v1
/// record has none, and a `state` on one is ignored.
///
/// An install that signed off cleanly (quit, signed out, or stopped
/// publishing) is listed for a while as a tombstone: `gone: true`, with the
/// time it went offline in `gone_at_ms` when the relay sends one. Both fields
/// are optional, so a record without them (any older relay) is an install
/// that has not signed off.
class CloudInstance {
  const CloudInstance({
    required this.instanceId,
    required this.hostname,
    required this.channel,
    required this.version,
    required this.agents,
    required this.receivedAtMs,
    this.os,
    this.channelsRunning,
    this.gone = false,
    this.goneAtMs,
  });

  static const maxInstances = 500;
  static const maxAgents = 200;
  static const maxNameLength = 128;
  static const maxVersionLength = 64;

  final String instanceId;
  final String hostname;
  final String channel;
  final String version;
  final String? os;
  final int? channelsRunning;
  final List<LanAgent> agents;

  /// When the relay last received this install's record, moved onto this
  /// device's clock (see [parseList]). Presence and the "as of" age are
  /// judged from it.
  final int receivedAtMs;

  /// The install signed off: devices hide it at once rather than wait for
  /// its record to go stale.
  final bool gone;

  /// When it went offline, on this device's clock: the relay's `gone_at_ms`
  /// when it sends a usable one, otherwise [receivedAtMs] (the goodbye is
  /// the last record the install sent). Null unless [gone].
  final int? goneAtMs;

  static String? _text(Object? v, int max) =>
      v is String && v.isNotEmpty && v.length <= max && !hasControlChar(v)
          ? v
          : null;

  /// Parses one record, or returns null when a required field is missing or
  /// out of bounds. Optional fields that are malformed are dropped.
  ///
  /// [clockOffsetMs] is added to the relay's `received_at_ms` to put it on
  /// this device's clock.
  static CloudInstance? tryParse(Object? json, {int clockOffsetMs = 0}) {
    if (json is! Map) return null;
    final instanceId = parseInstallId(json['instance_id']);
    final hostname = _text(json['hostname'], maxNameLength);
    final channel = _text(json['channel'], maxNameLength);
    final received = json['received_at_ms'];
    if (instanceId == null ||
        hostname == null ||
        channel == null ||
        received is! int ||
        received <= 0) {
      return null;
    }
    final receivedLocal = received + clockOffsetMs;
    // Only a real `true` is a tombstone: anything else reads as live.
    final gone = json['gone'] == true;
    final goneAt = json['gone_at_ms'];
    final goneAtLocal = !gone
        ? null
        : (goneAt is int && goneAt > 0
            ? goneAt + clockOffsetMs
            : receivedLocal);
    final version = json['v'];
    final hasStates = version is int && version >= 2;
    final rawAgents = json['agents'];
    final agents = <LanAgent>[];
    if (rawAgents is List) {
      for (final a in rawAgents.take(maxAgents)) {
        if (a is! Map) continue;
        final name = _text(a['name'], maxNameLength);
        if (name == null) continue;
        final lower = name.toLowerCase();
        if (agents.any((x) => x.name.toLowerCase() == lower)) continue;
        final state = hasStates ? parseAgentState(a['state']) : null;
        agents.add(LanAgent(
          name: name,
          kind: parseAgentKind(a['kind']),
          state: state,
          // No since time in the cloud: the chip says how old the record is.
          stateAsOf: state == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(receivedLocal),
        ));
      }
    }
    return CloudInstance(
      instanceId: instanceId,
      hostname: hostname,
      channel: channel,
      version: _text(json['version'], maxVersionLength) ?? '',
      os: parseOs(json['os']),
      channelsRunning: parseChannelsRunning(json['channels_running']),
      agents: agents,
      receivedAtMs: receivedLocal,
      gone: gone,
      goneAtMs: goneAtLocal,
    );
  }

  /// Parses a `GET /wan-instances` body (`{"instances": [...]}`): bad
  /// records are skipped, and an install listed twice keeps its newest record
  /// (so a tombstone received after a live record wins, and the reverse).
  ///
  /// The relay's times are moved onto this device's clock by the difference
  /// between [fetchedAt] (this device's clock when the answer arrived) and
  /// [relayNow] (the relay's clock then, from the response's `Date` header),
  /// so a device clock that runs ahead of or behind the relay's never makes a
  /// fresh record look old or an old one fresh. Without [relayNow] the times
  /// are used as given.
  static List<CloudInstance> parseList(
    Object? body, {
    DateTime? relayNow,
    DateTime? fetchedAt,
  }) {
    final offsetMs = relayNow != null && fetchedAt != null
        ? fetchedAt.millisecondsSinceEpoch - relayNow.millisecondsSinceEpoch
        : 0;
    if (body is! Map) return const [];
    final raw = body['instances'];
    if (raw is! List) return const [];
    final byId = <String, CloudInstance>{};
    for (final r in raw.take(maxInstances)) {
      final c = tryParse(r, clockOffsetMs: offsetMs);
      if (c == null) continue;
      final seen = byId[c.instanceId];
      if (seen == null || c.receivedAtMs > seen.receivedAtMs) {
        byId[c.instanceId] = c;
      }
    }
    return byId.values.toList();
  }
}

/// The relay does not serve the install list (an older relay answered 404).
class CloudInstancesUnsupported implements Exception {
  const CloudInstancesUnsupported();

  @override
  String toString() => 'CloudInstancesUnsupported';
}
