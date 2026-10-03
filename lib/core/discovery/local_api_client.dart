import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'models/lan_instance.dart';

class LocalApiClient {
  LocalApiClient(LanInstance instance)
      : _base = 'http://${instance.address}:${instance.port}',
        _authKey = instance.authKey;

  LocalApiClient.fromParts(String address, int port, String authKey)
      : _base = 'http://$address:$port',
        _authKey = authKey;

  final String _base;
  final String _authKey;

  /// Set once this server refused `/agentmux/discovery` to our key, so a
  /// client that polls (a fleet session) goes straight to agent names.
  bool _discoveryRefused = false;

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'X-AuthKey': _authKey},
  ));

  /// The log line for a failed [fetchAgents], split out so the 401 special
  /// case is testable without standing up a Dio mock.
  ///
  /// This is deliberately NOT the "your dev key is stale, rebuild" message —
  /// [fetchAgents] is only ever reached via `_enrichWithAgents`, whose sole
  /// callers are the mDNS scanner and UDP broadcast prober
  /// (`discovery_provider.dart`), so a 401 here means something structurally
  /// different from a 401 on the dev-connect path (see
  /// `DiscoveryNotifier._maybeAutoConnect`'s own message for that case).
  ///
  /// As of `agentmux` PR #2572 (`SPEC_JEKT_LAN_WAN_TRUST_HARDENING_2026_08_13.md`
  /// LAN P0-1), the value broadcast over mDNS/UDP is a separate, narrowly
  /// scoped `lan_key`, not the full instance `auth_key` — and
  /// `/agentmux/discovery` is not among the routes that credential grants
  /// (`lan_or_full_auth_middleware` in `agentmux-srv/src/server/mod.rs`).
  ///
  /// **That fact lives entirely in a sibling repo this one can't see, so it's
  /// deliberately hedged below rather than asserted as certain (ReAgent P1,
  /// raised twice on this PR) — a wrong CONFIDENT diagnosis is worse than a
  /// vague one, since a real stale/rotated key would then read as "expected,
  /// not a bug" and stop being investigated.** If a later `agentmux` change
  /// ever widens what `lan_key` can reach, this message would need updating
  /// too, and nothing in this repo would flag that drift automatically.
  @visibleForTesting
  static String fetchAgentsFailureMessage(Object error, String base) {
    final isUnauthorized =
        error is DioException && error.response?.statusCode == 401;
    if (!isUnauthorized) {
      return 'fetchAgents failed for $base, agent list left empty';
    }
    return 'fetchAgents got 401 for $base — if this instance came from LAN '
        'discovery (not QR/manual pairing), this is likely because its '
        'lan_key is scoped to a few forwarding routes that may not include '
        '/agentmux/discovery, rather than a stale/rotated key. Agent list '
        'left empty.';
  }

  /// Calls GET /agentmux/discovery and returns the agent list from host.addressable.
  /// Falls back to [] on any error.
  Future<List<LanAgent>> fetchAgents() async {
    try {
      final info = await fetchDiscoveryInfo();
      return info.agents;
    } catch (e, stackTrace) {
      // Falls back to [] so one unreachable instance doesn't blank the whole
      // discovery list, but logged rather than silently swallowed — this
      // exact call is what enriches mDNS/UDP results with agent lists, and a
      // silent failure here previously made a real connectivity problem
      // indistinguishable from "instance genuinely has no agents".
      AppLogger.log(
        fetchAgentsFailureMessage(e, _base),
        name: 'LocalApiClient',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Calls GET /agentmux/discovery and returns hostname + version + agents.
  /// Throws on error.
  ///
  /// `hostname` is empty for a server predating `agentmux` PR #3094 (which
  /// added the field) — callers should fall back to something else (e.g. the
  /// address) rather than display an empty string.
  ///
  /// A LAN-discovered instance only holds the narrow `lan_key`, which the
  /// desktop refuses on `/agentmux/discovery` (404/401/403) but accepts on
  /// `/agentmux/reactive/agent-names` — the route it exposes so a peer can
  /// list the agents another host runs. On that refusal this falls back to
  /// agent names alone (no hostname/version, no sibling channels, which need
  /// the full key).
  Future<({String hostname, String version, String? channel, List<LanAgent> agents})>
      fetchDiscoveryInfo() async {
    if (!_discoveryRefused) {
      try {
        final res =
            await _dio.get<Map<String, dynamic>>('/agentmux/discovery');
        return parseDiscovery(res.data);
      } on DioException catch (e) {
        if (!isDiscoveryRouteRefused(e)) rethrow;
        _discoveryRefused = true;
      }
    }
    final res =
        await _dio.get<Map<String, dynamic>>('/agentmux/reactive/agent-names');
    return (
      hostname: '',
      version: 'unknown',
      channel: null,
      agents: parseAgentNames(res.data),
    );
  }

  /// Whether [error] is the desktop refusing `/agentmux/discovery` to a
  /// `lan_key` holder, as opposed to a real connectivity/server failure that
  /// the agent-names fallback would only repeat.
  @visibleForTesting
  static bool isDiscoveryRouteRefused(DioException error) {
    final status = error.response?.statusCode;
    return status == 401 || status == 403 || status == 404;
  }

  /// Parses a `/agentmux/discovery` body: this instance's reachable agents
  /// (`host.addressable`) plus the agents of other channels running on the
  /// same machine (`host.cross_channel`), each tagged with its channel.
  @visibleForTesting
  static ({String hostname, String version, String? channel, List<LanAgent> agents})
      parseDiscovery(Map<String, dynamic>? data) {
    if (data == null) {
      return (
        hostname: '',
        version: 'unknown',
        channel: null,
        agents: const <LanAgent>[],
      );
    }
    final host = data['host'] as Map<String, dynamic>? ?? {};
    final addressable =
        (host['addressable'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final crossChannel =
        (host['cross_channel'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    return (
      hostname: (host['hostname'] as String?) ?? '',
      version: (host['version'] as String?) ?? 'unknown',
      channel: host['channel'] as String?,
      agents: [
        ...addressable.map(LanAgent.fromJson),
        ...crossChannel.map(
          (a) => LanAgent(
            name: a['name'] as String? ?? '',
            channel: a['channel'] as String?,
          ),
        ),
      ].where((a) => a.name.isNotEmpty).toList(),
    );
  }

  /// Parses a `/agentmux/reactive/agent-names` body: `{"agents": ["name", ...]}`.
  @visibleForTesting
  static List<LanAgent> parseAgentNames(Map<String, dynamic>? data) {
    final raw = data?['agents'];
    final names = raw is List ? raw.whereType<String>() : const <String>[];
    return names.map((n) => LanAgent(name: n)).toList();
  }

  /// POST /agentmux/reactive/inject — send a message to an agent on this instance.
  Future<void> inject({
    required String targetAgent,
    required String message,
  }) async {
    await _dio.post<void>('/agentmux/reactive/inject', data: {
      'target_agent': targetAgent,
      'message': message,
      'source_agent': 'mobile',
    });
  }
}
