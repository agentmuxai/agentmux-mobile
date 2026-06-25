import 'package:dio/dio.dart';

import 'models/lan_instance.dart';

class LocalApiClient {
  LocalApiClient(LanInstance instance)
      : _base = 'http://${instance.address}:${instance.port}',
        _authKey = instance.authKey;

  final String _base;
  final String _authKey;

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'X-AuthKey': _authKey},
  ));

  /// Calls GET /agentmux/discovery and returns the populated agent list.
  /// Falls back to [] on any error (firewall, endpoint not yet shipped).
  Future<List<LanAgent>> fetchAgents() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/agentmux/discovery');
      final data = res.data;
      if (data == null) return [];
      final host = data['host'] as Map<String, dynamic>?;
      final instances =
          (host?['instances'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
      if (instances == null || instances.isEmpty) return [];
      final agentsRaw =
          (instances.first['agents'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
      return agentsRaw?.map(LanAgent.fromJson).toList() ?? [];
    } catch (_) {
      return [];
    }
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
