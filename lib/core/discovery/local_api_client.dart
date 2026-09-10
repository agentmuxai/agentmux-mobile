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
  Future<({String hostname, String version, List<LanAgent> agents})>
      fetchDiscoveryInfo() async {
    final res = await _dio.get<Map<String, dynamic>>('/agentmux/discovery');
    final data = res.data;
    if (data == null) {
      return (hostname: '', version: 'unknown', agents: const <LanAgent>[]);
    }
    final host = data['host'] as Map<String, dynamic>? ?? {};
    final addressable =
        (host['addressable'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    return (
      hostname: (host['hostname'] as String?) ?? '',
      version: (host['version'] as String?) ?? 'unknown',
      agents: addressable.map(LanAgent.fromJson).toList(),
    );
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
