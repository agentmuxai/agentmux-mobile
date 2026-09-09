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
  /// (`discovery_provider.dart`).
  ///
  /// **Evidence this depends on lives in the sibling `agentmux` (desktop/srv)
  /// repo, not this one — flagging that explicitly since it isn't verifiable
  /// from `agentmux-mobile`'s own source (ReAgent P1 on this PR correctly
  /// pointed out that nothing here shows it).** As of `agentmux` PR #2572
  /// ("stop broadcasting the full-access auth_key to LAN peers", landing
  /// `docs/specs/SPEC_JEKT_LAN_WAN_TRUST_HARDENING_2026_08_13.md`'s LAN P0-1),
  /// the value broadcast over mDNS/UDP — read here as `instance.authKey` — is
  /// a separate, narrowly-scoped `lan_key`, not the full instance `auth_key`.
  /// Server-side, `agentmux-srv/src/server/mod.rs`'s `lan_or_full_auth_middleware`
  /// accepts that `lan_key` on exactly three routes (`reactive/inject`,
  /// `reactive/agent`, `reactive/agent-names`); `/agentmux/discovery` is
  /// registered under the separate `authed_routes` group (full `auth_key`
  /// only). So a 401 from this route, for an instance sourced from mDNS/UDP,
  /// is not staleness or a transient failure — it is the **guaranteed,
  /// permanent** result of calling it with a credential that was never valid
  /// there. "Rebuild the app" was actively wrong advice for the case this
  /// actually handles (Codex P2, separately) — nothing about rebuilding
  /// changes what a `lan_key` is scoped to. The rebuild-fixable staleness
  /// case is real, but belongs to dev auto-connect specifically, which DOES
  /// hold the full key — see `DiscoveryNotifier._maybeAutoConnect`'s own
  /// catch block.
  @visibleForTesting
  static String fetchAgentsFailureMessage(Object error, String base) {
    final isUnauthorized =
        error is DioException && error.response?.statusCode == 401;
    if (!isUnauthorized) {
      return 'fetchAgents failed for $base, agent list left empty';
    }
    return 'fetchAgents got 401 for $base — expected, not a bug: this '
        "instance's LAN-broadcast credential (lan_key) is scoped to a few "
        'forwarding routes and does not grant access to /agentmux/discovery, '
        'so its agent list cannot be fetched this way (see '
        'agentmux/docs/specs/SPEC_JEKT_LAN_WAN_TRUST_HARDENING_2026_08_13.md, '
        'LAN P0-1). Agent list left empty.';
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

  /// Calls GET /agentmux/discovery and returns version + agents. Throws on error.
  Future<({String version, List<LanAgent> agents})> fetchDiscoveryInfo() async {
    final res = await _dio.get<Map<String, dynamic>>('/agentmux/discovery');
    final data = res.data;
    if (data == null) return (version: 'unknown', agents: const <LanAgent>[]);
    final host = data['host'] as Map<String, dynamic>? ?? {};
    final addressable =
        (host['addressable'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    return (
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
