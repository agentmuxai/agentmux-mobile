import '../discovery/models/lan_instance.dart';
import '../discovery/peer_fields.dart';

/// One channel's state as `GET /agentmux/fleet` and the `fleet` event of
/// `/agentmux/fleet/events` report it: agent names only, plus the instance
/// metadata a LAN peer can already see in the mDNS record.
///
/// See `docs/specs/SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md` section 4.1, and
/// `SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` section 4 for the
/// display fields (`os`, `install_id`, `channels_running`, `agent_kinds`)
/// newer desktops add, and `SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
/// section 13.1 for `agent_status` and `now_ms`. Those are optional: an older
/// desktop leaves them out.
class FleetSnapshot {
  const FleetSnapshot({
    required this.epoch,
    required this.rev,
    required this.hostname,
    required this.version,
    required this.agents,
    this.channel,
    this.os,
    this.installId,
    this.channelsRunning,
    this.agentKinds = const {},
    this.agentStatus = const {},
    this.nowMs,
  });

  /// Bounds on peer-supplied data: a LAN peer is unauthenticated, so nothing
  /// it sends may grow without limit.
  static const maxAgents = 500;
  static const maxNameLength = 128;
  static const maxFieldLength = 256;

  /// Random per srv launch; a new value means the channel restarted.
  final String epoch;

  /// Increments on every change of [agents] within one [epoch].
  final int rev;
  final String hostname;
  final String version;
  final String? channel;
  final List<String> agents;

  /// Validated platform token, see `parseOs`.
  final String? os;
  final String? installId;
  final int? channelsRunning;

  /// Kind per agent, keyed by lower-cased name; agents left out have none.
  final Map<String, AgentKind> agentKinds;

  /// State per agent, keyed by lower-cased name; agents left out have none.
  final Map<String, ReportedAgentStatus> agentStatus;

  /// The desktop's clock when it made this snapshot, the only time a
  /// `since_ms` in [agentStatus] is compared with.
  final int? nowMs;

  /// The SSE `id` / ETag body for this state.
  String get eventId => '$epoch:$rev';

  /// Parses a fleet body, or returns null when it is not one.
  static FleetSnapshot? tryParse(Object? json) {
    if (json is! Map) return null;
    final epoch = json['epoch'];
    final rev = json['rev'];
    final agents = json['agents'];
    if (epoch is! String || epoch.isEmpty || epoch.length > maxFieldLength) {
      return null;
    }
    if (rev is! int || agents is! List) return null;
    String field(String key) {
      final v = json[key];
      return v is String && v.length <= maxFieldLength ? v : '';
    }

    final channel = field('channel');
    return FleetSnapshot(
      epoch: epoch,
      rev: rev,
      hostname: field('hostname'),
      version: field('version'),
      channel: channel.isEmpty ? null : channel,
      agents: agents
          .whereType<String>()
          .where((n) => n.isNotEmpty && n.length <= maxNameLength)
          .take(maxAgents)
          .toList(),
      os: parseOs(json['os']),
      installId: parseInstallId(json['install_id']),
      channelsRunning: parseChannelsRunning(json['channels_running']),
      agentKinds: parseAgentKinds(json['agent_kinds'], maxEntries: maxAgents),
      agentStatus: parseAgentStatus(
        json['agent_status'],
        maxEntries: maxAgents,
      ),
      nowMs: parseUnixMs(json['now_ms']),
    );
  }
}
