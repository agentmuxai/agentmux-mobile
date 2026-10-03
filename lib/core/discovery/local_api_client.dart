import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
