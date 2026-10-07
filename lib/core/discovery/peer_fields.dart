import 'models/lan_instance.dart';

/// Parsers for the display fields a peer or the relay reports about a host
/// (`docs/specs/SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` sections
/// 5 and 6). Everything here is untrusted input: each parser bounds its value
/// and returns null for anything it does not accept, never throws.

final _osPattern = RegExp(r'^[a-z0-9_-]{1,16}$');

/// The desktop's own rule for an `os` token (`host_os.rs`).
String? parseOs(Object? value) =>
    value is String && _osPattern.hasMatch(value) ? value : null;

/// A WAN instance id: 26 chars of lowercase base32 today; anything plain and
/// short is accepted so a later id format does not silently drop the field.
final _installIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

String? parseInstallId(Object? value) =>
    value is String && _installIdPattern.hasMatch(value) ? value : null;

/// `channels_running`, clamped to 1..99; null when absent or not a number.
int? parseChannelsRunning(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toInt().clamp(1, 99);
}

/// A TCP port (1 to 65535), e.g. `viewer_port`; null when absent or invalid.
int? parsePort(Object? value) =>
    value is int && value > 0 && value <= 65535 ? value : null;

AgentKind? parseAgentKind(Object? value) => switch (value) {
      'host' => AgentKind.host,
      'container' => AgentKind.container,
      _ => null,
    };

/// `agent_kinds` (`{"Name": "host" | "container"}`), keyed by lower-cased
/// name since names compare case-insensitively. Unknown kinds are left out.
Map<String, AgentKind> parseAgentKinds(Object? value, {int maxEntries = 500}) {
  if (value is! Map) return const {};
  final kinds = <String, AgentKind>{};
  for (final e in value.entries.take(maxEntries)) {
    final name = e.key;
    final kind = parseAgentKind(e.value);
    if (name is! String || name.isEmpty || name.length > 128 || kind == null) {
      continue;
    }
    kinds[name.toLowerCase()] = kind;
  }
  return kinds;
}

AgentState? parseAgentState(Object? value) => switch (value) {
      'working' => AgentState.working,
      'waiting' => AgentState.waiting,
      'idle' => AgentState.idle,
      'stopped' => AgentState.stopped,
      'error' => AgentState.error,
      _ => null,
    };

/// A Unix time in milliseconds (`now_ms`, `since_ms`): a positive integer,
/// else null.
int? parseUnixMs(Object? value) => value is int && value > 0 ? value : null;

/// One entry of `agent_status`, as the desktop sent it.
class ReportedAgentStatus {
  const ReportedAgentStatus(this.state, {this.sinceMs});

  final AgentState state;

  /// When the agent entered [state], by the desktop's clock. Only ever
  /// compared with the same desktop's `now_ms`.
  final int? sinceMs;

  @override
  bool operator ==(Object other) =>
      other is ReportedAgentStatus &&
      other.state == state &&
      other.sinceMs == sinceMs;

  @override
  int get hashCode => Object.hash(state, sinceMs);
}

/// `agent_status` (`{"Name": {"state": "working", "since_ms": <unix ms>}}`,
/// `SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` section 13.1), keyed
/// by lower-cased name. An entry with an unknown or missing state is left
/// out (the agent shows no chip); a bad `since_ms` drops only the duration.
Map<String, ReportedAgentStatus> parseAgentStatus(
  Object? value, {
  int maxEntries = 500,
}) {
  if (value is! Map) return const {};
  final status = <String, ReportedAgentStatus>{};
  for (final e in value.entries.take(maxEntries)) {
    final name = e.key;
    final entry = e.value;
    if (name is! String || name.isEmpty || name.length > 128 || entry is! Map) {
      continue;
    }
    final state = parseAgentState(entry['state']);
    if (state == null) continue;
    status[name.toLowerCase()] =
        ReportedAgentStatus(state, sinceMs: parseUnixMs(entry['since_ms']));
  }
  return status;
}

/// How long an agent has been in its state, from the desktop's own `since_ms`
/// and `now_ms`, anchored at [receivedAt] on this device's clock. Null when
/// either time is missing: the device's clock is never compared with the
/// desktop's. A `since_ms` after `now_ms` counts as just now.
StateSince? stateSinceFrom({
  required int? sinceMs,
  required int? nowMs,
  required DateTime receivedAt,
}) {
  if (sinceMs == null || nowMs == null) return null;
  final elapsed = nowMs - sinceMs;
  return StateSince(
    elapsedAtReceipt: Duration(milliseconds: elapsed < 0 ? 0 : elapsed),
    receivedAt: receivedAt,
  );
}

/// An agent of a LAN answer, with its kind and its reported status applied.
LanAgent lanAgentFrom(
  String name, {
  AgentKind? kind,
  ReportedAgentStatus? status,
  int? nowMs,
  required DateTime receivedAt,
}) =>
    LanAgent(
      name: name,
      kind: kind,
      state: status?.state,
      stateSince: status == null
          ? null
          : stateSinceFrom(
              sinceMs: status.sinceMs,
              nowMs: nowMs,
              receivedAt: receivedAt,
            ),
    );

/// Whether [s] contains a control character (U+0000 to U+001F).
bool hasControlChar(String s) => s.codeUnits.any((c) => c < 0x20);
