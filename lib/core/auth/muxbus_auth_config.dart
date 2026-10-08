import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'auth_errors.dart';

/// Where the app signs in: the sign-in service's host and the app's client id.
class MuxbusAuthConfig {
  const MuxbusAuthConfig({required this.domain, required this.clientId});

  /// Host (and port, when not the default), no scheme or path: what
  /// `Uri.https` takes as its authority.
  final String domain;
  final String clientId;
}

/// [raw] as a host[:port] for `Uri.https`, or null when it is not usable.
/// Takes a bare host (`auth.example.test`) as well as a full https URL
/// (`https://auth.example.test/`), which is how the discovery document gives
/// it. Anything not https is refused.
String? normaliseCognitoDomain(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// Resolves [MuxbusAuthConfig]: each `--dart-define` override wins, and
/// whatever is missing comes from the cloud discovery document
/// (`GET {apiBase}/.well-known/agentmux-cloud.json`, public, no token), read
/// once per session. So a release build needs no ids compiled in.
class MuxbusAuthConfigSource {
  MuxbusAuthConfigSource({
    required Dio dio,
    required this.apiBase,
    String domainOverride = '',
    String clientIdOverride = '',
  }) : _dio = dio,
       _domainOverride = normaliseCognitoDomain(domainOverride),
       _clientIdOverride =
           clientIdOverride.trim().isEmpty ? null : clientIdOverride.trim();

  final Dio _dio;
  final String apiBase;
  final String? _domainOverride;
  final String? _clientIdOverride;

  Future<Map<String, Object?>>? _document;

  /// Throws [AuthUnavailable] when no client id (or domain) can be found, and
  /// [AuthNetworkError] when the document could not be read.
  Future<MuxbusAuthConfig> resolve() async {
    var domain = _domainOverride;
    var clientId = _clientIdOverride;
    if (domain == null || clientId == null) {
      final cognito = await _cognitoSection();
      domain ??= normaliseCognitoDomain(_string(cognito['domain']));
      clientId ??= _string(cognito['mobileClientId']);
    }
    if (domain == null || clientId == null) throw AuthUnavailable();
    return MuxbusAuthConfig(domain: domain, clientId: clientId);
  }

  /// Whether sign-in can be offered: true or false when known, null when the
  /// document could not be read (offline), so the page asks again on tap.
  Future<bool?> available() async {
    try {
      await resolve();
      return true;
    } on AuthUnavailable {
      return false;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> _cognitoSection() async {
    // One read per session; a failed read is forgotten so the next try asks
    // again.
    final doc = _document ??= _fetch();
    try {
      final d = await doc;
      final cognito = d['cognito'];
      return cognito is Map ? cognito.cast<String, Object?>() : const {};
    } catch (_) {
      if (identical(_document, doc)) _document = null;
      rethrow;
    }
  }

  Future<Map<String, Object?>> _fetch() async {
    final base =
        apiBase.endsWith('/')
            ? apiBase.substring(0, apiBase.length - 1)
            : apiBase;
    try {
      final res = await _dio.get<Object>(
        '$base/.well-known/agentmux-cloud.json',
        options: Options(responseType: ResponseType.json),
      );
      var data = res.data;
      if (data is String) data = jsonDecode(data);
      return data is Map ? data.cast<String, Object?>() : const {};
    } on DioException catch (e) {
      // A relay that doesn't serve the document has no settings to give.
      if (e.response?.statusCode == 404) return const {};
      throw AuthNetworkError();
    } on FormatException {
      return const {};
    }
  }

  static String? _string(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
}
