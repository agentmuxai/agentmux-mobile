import 'package:dio/dio.dart';

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
        'fetchAgents failed for $_base, agent list left empty',
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
