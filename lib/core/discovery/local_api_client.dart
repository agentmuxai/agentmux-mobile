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
  @visibleForTesting
  static String fetchAgentsFailureMessage(Object error, String base) {
    final isUnauthorized =
        error is DioException && error.response?.statusCode == 401;
    if (!isUnauthorized) {
      return 'fetchAgents failed for $base, agent list left empty';
    }
    return 'fetchAgents got 401 for $base — the auth key is almost certainly '
        'stale (the desktop mints a new one per launch; AGENTMUX_DEV_KEY is '
        'baked in at build time). Rebuild the app against the running '
        'instance. Agent list left empty.';
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
      //
      // A 401 gets its own message because it has one overwhelmingly likely
      // cause that the generic text sends you hunting in the wrong place:
      // the desktop mints a FRESH auth_key on every launch
      // (agentmux-launcher's srv_spawner.rs — "Generate a fresh auth_key per
      // run"), while AGENTMUX_DEV_KEY is baked into this app at BUILD time by
      // scripts/run-emulator.sh. So any AgentMux restart — including an
      // auto-update — invalidates the built-in key, and the instance silently
      // renders as "No agents reported" rather than "your key is stale".
      // The fix is to rebuild the app, not to debug connectivity.
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
