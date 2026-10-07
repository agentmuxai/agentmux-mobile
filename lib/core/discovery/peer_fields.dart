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

/// Whether [s] contains a control character (U+0000 to U+001F).
bool hasControlChar(String s) => s.codeUnits.any((c) => c < 0x20);
