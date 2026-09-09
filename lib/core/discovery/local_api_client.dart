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
  /// (`discovery_provider.dart`). Every instance reaching this code carries
  /// the narrow, LAN-broadcast `lan_key`, never the full instance key, and
  /// `/agentmux/discovery` requires full auth — so a 401 here is not staleness
  /// or a transient failure, it is the **guaranteed, permanent** result of
  /// calling this route with that credential. "Rebuild the app" was actively
  /// wrong advice for the case this actually handles (Codex P2 on
  /// agentmux-mobile#20/#21) — nothing about rebuilding changes what a
  /// lan_key is scoped to. The rebuild-fixable staleness case is real, but
  /// belongs to dev auto-connect specifically, which DOES hold the full key
  /// — see `DiscoveryNotifier._maybeAutoConnect`'s own catch block.
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
        'so its agent list cannot be fetched this way. See '
        'docs/specs/REMOTE_TERMINALS_AND_CONVERSATION_HISTORY.md for the '
        'scoped-read-credential proposal this would need. Agent list left '
        'empty.';
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
