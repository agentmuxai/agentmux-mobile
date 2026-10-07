import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';

/// One AgentMux install (a channel on a machine) as the account's cloud list
/// (`GET /wan-instances`) reports it. See
/// `docs/specs/SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 5.
///
/// Every field is bounded: it is display data that came off another machine.
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

  /// When the relay last received this install's record, by the relay's
  /// clock. Presence is judged from it.
  final int receivedAtMs;

  static String? _text(Object? v, int max) =>
      v is String && v.isNotEmpty && v.length <= max && !hasControlChar(v)
          ? v
          : null;

  /// Parses one record, or returns null when a required field is missing or
  /// out of bounds. Optional fields that are malformed are dropped.
  static CloudInstance? tryParse(Object? json) {
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
    final rawAgents = json['agents'];
    final agents = <LanAgent>[];
    if (rawAgents is List) {
      for (final a in rawAgents.take(maxAgents)) {
        if (a is! Map) continue;
        final name = _text(a['name'], maxNameLength);
        if (name == null) continue;
        final lower = name.toLowerCase();
        if (agents.any((x) => x.name.toLowerCase() == lower)) continue;
        agents.add(LanAgent(name: name, kind: parseAgentKind(a['kind'])));
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
      receivedAtMs: received,
    );
  }

  /// Parses a `GET /wan-instances` body (`{"instances": [...]}`): bad
  /// records are skipped, and an install listed twice keeps its newest record.
  static List<CloudInstance> parseList(Object? body) {
    if (body is! Map) return const [];
    final raw = body['instances'];
    if (raw is! List) return const [];
    final byId = <String, CloudInstance>{};
    for (final r in raw.take(maxInstances)) {
      final c = tryParse(r);
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
