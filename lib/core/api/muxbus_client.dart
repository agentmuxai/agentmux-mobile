import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mutex/mutex.dart';

import '../auth/auth_repository.dart';
import '../models/agent.dart';
import '../models/injection.dart';
import '../models/message.dart';
import '../models/usage.dart';

const _apiBase = String.fromEnvironment(
  'MUXBUS_API_BASE',
  defaultValue: 'https://muxbus.agentmux.ai',
);

class MuxbusClient {
  MuxbusClient(this._auth) {
    _dio = Dio(BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    _dio.interceptors.add(_AuthInterceptor(_auth, _dio, _refreshMutex));
  }

  final AuthRepository _auth;
  final _refreshMutex = Mutex();
  late final Dio _dio;

  // ── Agents ───────────────────────────────────────────────────────────────

  Future<List<Agent>> getAgents() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/agents');
    final list = (res.data!['agents'] as List).cast<Map<String, dynamic>>();
    return list.map(Agent.fromJson).toList();
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<List<Message>> getMessages(
    String agentId, {
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/messages',
      queryParameters: {
        'unread_only': unreadOnly,
        'limit': limit,
        'mark_as_read': true,
      },
      options: Options(headers: {'x-agent-id': agentId}),
    );
    final list = (res.data!['messages'] as List).cast<Map<String, dynamic>>();
    return list.map(Message.fromJson).toList();
  }

  // ── Injections ───────────────────────────────────────────────────────────

  Future<Injection> postInjection({
    required String targetAgent,
    required String message,
    required String priority,
    required String sourceAgentId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/reactive/inject',
      data: {
        'target_agent': targetAgent,
        'message': message,
        'priority': priority,
      },
      options: Options(headers: {'x-agent-id': sourceAgentId}),
    );
    return Injection.fromJson(res.data!['injection'] as Map<String, dynamic>);
  }

  // ── Usage & billing ───────────────────────────────────────────────────────

  Future<UsageSummary> getUsage() async {
    final usageRes = await _dio.get<Map<String, dynamic>>('/usage/current');
    final tierRes = await _dio.get<Map<String, dynamic>>('/billing/tier');

    return UsageSummary(
      quotas: UsageSummary.parseQuotas(usageRes.data!),
      tier: tierRes.data!['billing_tier'] as String? ?? 'free',
    );
  }
}

// ── Auth + refresh interceptor ────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._auth, this._dio, this._mutex);

  final AuthRepository _auth;
  final Dio _dio;
  final Mutex _mutex;

  // "One future" pattern — all concurrent 401s wait on the same refresh.
  Completer<String>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await _auth.getValidIdToken();
      options.headers['Authorization'] = 'Bearer $token';
    } catch (_) {
      // No token yet — let the request proceed; server will 401.
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    String newToken;
    if (_refreshing != null) {
      // Another request already kicked off a refresh — wait for it.
      try {
        newToken = await _refreshing!.future;
      } catch (e) {
        return handler.reject(err);
      }
    } else {
      final completer = Completer<String>();
      _refreshing = completer;
      try {
        newToken = await _mutex.protect(() => _auth.refreshTokens());
        completer.complete(newToken);
      } catch (e) {
        completer.completeError(e);
        _refreshing = null;
        return handler.reject(err);
      } finally {
        _refreshing = null;
      }
    }

    // Retry original request with new token.
    err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
    try {
      final retried = await _dio.fetch(err.requestOptions);
      handler.resolve(retried);
    } catch (e) {
      handler.reject(err);
    }
  }
}
